# Multi-class container runtime presets and capability workarounds (NixOS + finix).
{
  common =
    { config, lib, ... }:
    let
      cfg = config.infra.container;

      presets = {
        lxc = {
          sys_admin = true;
          net_admin = true;
          mknod = true;
        };
        incus = presets.lxc;
        podman = {
          sys_admin = false;
          net_admin = false;
          mknod = false;
        };
        docker = presets.podman;
      };
    in
    {
      options.infra.container = {
        runtime = lib.mkOption {
          type = lib.types.enum (builtins.attrNames presets);
          default = "podman";
          description = "Container runtime preset seeding default capabilities.";
        };

        capabilities = {
          sys_admin = lib.mkEnableOption "CAP_SYS_ADMIN (mount /run/* tmpfs and service capabilities)";
          net_admin = lib.mkEnableOption "CAP_NET_ADMIN (configure NICs, routes, and DNS)";
          mknod = lib.mkEnableOption "CAP_MKNOD (create device nodes like /dev/net/tun)";
        };
      };

      config.infra.container.capabilities = lib.mapAttrs (_: lib.mkDefault) presets.${cfg.runtime};
    };

  nixos =
    {
      config,
      lib,
      pkgs,
      options,
      ...
    }:
    let
      cap = config.infra.container.capabilities;
    in
    {
      config = lib.mkMerge [
        {
          infra.container.runtime = lib.mkOverride 1100 "lxc";
        }

        (lib.mkIf cap.mknod {
          systemd.tmpfiles.settings."10-tun"."/dev/net/tun".c = {
            mode = "0666";
            user = "root";
            group = "root";
            argument = "10:200";
          };
        })

        (lib.mkIf cap.net_admin {
          networking.useHostResolvConf = lib.mkOverride 900 false;
        })

        (lib.mkIf (!cap.net_admin) {
          # Runtime pre-configures eth0 and bind-mounts /etc/resolv.conf.
          infra.network.topology = lib.mkDefault null;
          networking.useDHCP = lib.mkDefault false;
          networking.useNetworkd = lib.mkOverride 900 false;
          networking.useHostResolvConf = lib.mkDefault true;
          networking.resolvconf.enable = lib.mkForce false;
        })

        (lib.mkIf (!cap.sys_admin) {
          # Runtime already mounts /dev, /proc, /run (tmpfs); mount units and specialfs fail without CAP_SYS_ADMIN.
          systemd.suppressedSystemUnits = [
            "run-keys.mount"
            "run-wrappers.mount"
          ];
          system.activationScripts.specialfs = lib.mkForce ''
            mkdir -p -m 0750 /run/keys
          '';

          # /run is mounted nosuid in Podman/Docker; redirect /run/wrappers onto / (matching finix)
          # so all SUID/SGID wrappers (sudo, unix_chkpwd, etc.) work natively.
          systemd.services.suid-sgid-wrappers.serviceConfig.ExecStartPre =
            pkgs.writeShellScript "container-wrappers-dir" ''
              ${pkgs.coreutils}/bin/mkdir -p /var/lib/wrappers
              ${pkgs.coreutils}/bin/ln -sfn /var/lib/wrappers /run/wrappers
            '';

          # User=nscd + RestrictSUIDSGID=true triggers 217/USER without CAP_SYS_ADMIN.
          systemd.services.nscd.serviceConfig.RestrictSUIDSGID = lib.mkForce false;

          # sops-install-secrets checks mountinfo.Mounted("/run/secrets.d") even when /run is already tmpfs;
          # skip remounting when the underlying filesystem already matches tmpfs magic.
          sops.package = lib.mkDefault (
            options.sops.package.default.overrideAttrs (old: {
              postPatch = (old.postPatch or "") + ''
                substituteInPlace pkgs/sops-install-secrets/linux.go \
                  --replace-fail 'mounted, err := mountinfo.Mounted(mountpoint)' '_, err := mountinfo.Mounted(mountpoint)' \
                  --replace-fail 'if !mounted || int32(buf.Type) != fsmagic {' 'if int32(buf.Type) != fsmagic {'
              '';
            })
          );
        })
      ];
    };

  finix =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cap = config.infra.container.capabilities;
      coreutils = config.programs.coreutils.package;
    in
    {
      config = lib.mkMerge [
        (lib.mkIf cap.mknod {
          system.activation.scripts.containerTun = {
            deps = [ "specialfs" ];
            text = ''
              if [ ! -e /dev/net/tun ]; then
                mkdir -p /dev/net
                ${coreutils}/bin/mknod -m 0666 /dev/net/tun c 10 200 2>/dev/null || true
              fi
            '';
          };
        })

        (lib.mkIf cap.net_admin {
          programs.ifupdown-ng = {
            enable = lib.mkDefault true;
            auto = [ "lo" ];
            iface.lo.use = "loopback";
          };

          services.nftables = {
            enable = lib.mkDefault true;
            trustedInterfaces = [ "lo" ];
            tables = {
              scanner-blocklist = {
                family = "inet";
                content = ''
                  include "${pkgs.scanner-blocklist-nft}"
                '';
              };
              nixos-fw.content = lib.mkAfter ''
                chain input-allow {
                  icmpv6 type { nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } accept
                }
              '';
            };
          };
          providers.firewall.backend = lib.mkDefault "nftables";
        })

        (lib.mkIf (!cap.net_admin) {
          environment.etc.hostname.enable = lib.mkForce false;
          environment.etc.hosts.enable = lib.mkForce false;
          providers.firewall.backend = lib.mkDefault "none";
        })

        (lib.mkIf cap.sys_admin {
          finit.run.mount-cgroup = {
            enable = true;
            description = "mount cgroup memory controller for container-scoped metrics";
            runlevel = "S";
            script = ''
              if [ -d /sys/fs/cgroup ] && ! mountpoint -q /sys/fs/cgroup; then
                if mount -t cgroup2 -o ro none /sys/fs/cgroup 2>/dev/null; then
                  if [ ! -r /sys/fs/cgroup/memory.events ]; then
                    umount /sys/fs/cgroup 2>/dev/null || true
                  fi
                fi
                if ! mountpoint -q /sys/fs/cgroup; then
                  if mount -t tmpfs -o mode=0755,nosuid,nodev,noexec tmpfs /sys/fs/cgroup 2>/dev/null; then
                    if ! (mkdir -p /sys/fs/cgroup/memory 2>/dev/null \
                      && mount -t cgroup -o memory,ro cgroup /sys/fs/cgroup/memory 2>/dev/null); then
                      umount /sys/fs/cgroup 2>/dev/null || true
                    fi
                  fi
                fi
              fi
            '';
          };
        })

        # LXC/Incus treats PID 1 exit-0 as poweroff; `reboot -f` invokes `reboot(2)` (SIGHUP to PID 1)
        # so the runtime restarts the container. Podman/Docker relies on PID 1 exit + restart policy
        # (and drops CAP_SYS_BOOT, where `reboot -f` would fail with EPERM).
        (lib.mkIf
          (builtins.elem config.infra.container.runtime [
            "lxc"
            "incus"
          ])
          {
            environment.systemPackages = [
              (lib.hiPrio (
                pkgs.writeShellScriptBin "reboot" ''
                  ${coreutils}/bin/sync
                  exec ${coreutils}/bin/reboot -f
                ''
              ))
            ];
          }
        )
      ];
    };
}
