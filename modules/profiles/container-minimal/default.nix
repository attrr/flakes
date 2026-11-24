# finix minimal container feature (base runtime + server/network-static/sing-box/secrets/telemetry + ctx).
{
  includes = [
    ../server
    ../../network
    ../../services/sing-box
    ../../secrets.nix
    ../../services/telemetry
  ];

  module.finix =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.infra.container;
      coreutils = config.programs.coreutils.package;

      wrapperRoot = "/var/lib/wrappers";

      # Directories searched after `/run/wrappers/bin` for login shells and sudo.
      systemPath = [
        "/run/current-system/sw/bin"
        "/run/current-system/sw/sbin"
        "/bin"
        "/sbin"
      ];
    in
    {
      imports = [
        ./base
        ./deploy.nix
        ../container/common.nix
      ];

      config = {

        # Use busybox as both `coreutils` and POSIX `/bin/sh` (`passthru.meta.mainProgram` avoids rebuilding busybox).
        programs.coreutils.package = lib.mkDefault pkgs.busybox;
        programs.sh.package = lib.mkDefault (
          pkgs.busybox
          // {
            meta = pkgs.busybox.meta // {
              mainProgram = "ash";
            };
          }
        );

        programs.bash.enable = lib.mkDefault true;

        environment.etc.services.enable = lib.mkDefault false;
        environment.etc.protocols.enable = lib.mkDefault false;
        environment.etc.hostname.enable = lib.mkIf (!cfg.capabilities.net_admin) (lib.mkForce false);
        environment.etc.hosts.enable = lib.mkIf (!cfg.capabilities.net_admin) (lib.mkForce false);

        programs.ifupdown-ng = {
          enable = lib.mkDefault cfg.capabilities.net_admin;
          auto = [ "lo" ];
          iface.lo.use = "loopback";
        };

        services.nftables = {
          enable = lib.mkDefault cfg.capabilities.net_admin;
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
        providers.firewall.backend = lib.mkDefault (
          if cfg.capabilities.net_admin then "nftables" else "none"
        );

        services.cron = {
          enable = lib.mkDefault true;
          settings = {
            MAILTO = lib.mkDefault "";
            RANDOM_DELAY = lib.mkDefault 1;
          };
        };

        services.sysklogd = {
          enable = lib.mkDefault true;
          extraConfig = lib.mkDefault ''
            rotate_size  200k
            rotate_count 1
          '';
        };

        # Place physical SUID wrappers under `/var/lib/wrappers/bin` (on `/`, avoiding `/run`'s `nosuid`
        # mount in Podman/Docker) and symlink `/run/wrappers -> /var/lib/wrappers` so `pam_unix.so`'s
        # compiled-in `/run/wrappers/bin/unix_chkpwd` resolves onto `/` where SUID works.
        security.wrapperDir = "${wrapperRoot}/bin";
        finit.tmpfiles.rules = [
          "d ${wrapperRoot} 0755 - -"
          "L+ /run/wrappers - - - - ${wrapperRoot}"
          "d /tmp 1777 - -"
        ];
        environment.variables.PATH = [ "/run/wrappers/bin" ] ++ systemPath;

        programs.sudo.enable = lib.mkDefault true;
        # `secure_path` pins sudo's PATH (incl. `/run/wrappers/bin`) when the caller has a bare one, e.g.
        # non-login `ssh host cmd` as used by deploy.
        # Wheel members (`sysadm`) run passwordless sudo (matching `profiles/server`).
        environment.etc.sudoers.text = lib.mkAfter ''
          Defaults secure_path="${lib.concatStringsSep ":" ([ "/run/wrappers/bin" ] ++ systemPath)}"
          %wheel ALL=(ALL:ALL) NOPASSWD: SETENV: ALL
        '';

        users.users.root.password = "!";
        users.users.${config.infra.server.user} = {
          isNormalUser = true;
          extraGroups = [ "wheel" ];
          password = "!";
        };

        # Container runtimes invoke `/sbin/init`, so `argv[0]` would be `/sbin/init` and `finix-setup`
        # would set `/run/current-system -> /sbin`. Use `bash`'s `exec -a` to pass `$sys/init` as `argv[0]`.
        boot.init = lib.mkDefault (
          pkgs.writeScript "init" ''
            #!${config.programs.bash.package}/bin/bash
            sys=$(${coreutils}/bin/readlink -f /nix/var/nix/profiles/system)
            ${coreutils}/bin/mkdir -p /run

            # Finit's `bootmisc` cleans non-tmpfs `/run` with `nftw()` without `FTW_PHYS`,
            # which follows symlinks and wipes `/nix/store/...-finix-system` or `/var/lib/*`!
            if ! ${coreutils}/bin/mountpoint -q /run; then
              ${coreutils}/bin/mount -t tmpfs -o mode=0755,nosuid,nodev tmpfs /run 2>/dev/null \
                || ${coreutils}/bin/rm -f /run/current-system /run/booted-system /run/secrets /run/wrappers
            fi

            exec -a "$sys/init" ${config.finit.package}/bin/finit "$@"
          ''
        );

        providers.bootloader.installHook = pkgs.writeScript "container-bootloader" ''
          #!${coreutils}/bin/sh
          mkdir -p /sbin /lib/systemd /usr/sbin /usr/lib/systemd
          ln -sfn "$1/init" /sbin/init
          ln -sfn "$1/init" /lib/systemd/systemd
          ln -sfn "$1/init" /usr/sbin/init
          ln -sfn "$1/init" /usr/lib/systemd/systemd
        '';

        # Container bootstrap & takeover script run during `$toplevel/activate`.
        system.activation.scripts.containerInit = {
          deps = [
            "containerLustrate"
            "specialfs"
            "users"
            "etc"
          ];
          text = ''
            ${lib.optionalString cfg.capabilities.mknod ''
              if [ ! -e /dev/net/tun ]; then
                mkdir -p /dev/net
                ${coreutils}/bin/mknod -m 0666 /dev/net/tun c 10 200 2>/dev/null || true
              fi
            ''}
            touch /etc/NIXOS

            if [ ! -e /nix/var/nix/profiles/system ]; then
              ln -sfn "$systemConfig" /nix/var/nix/profiles/system
            fi

            # Provider web consoles and `podman/lxc exec` often invoke `/bin/bash` directly.
            mkdir -p /bin
            ln -sfn /run/current-system/sw/bin/bash /bin/bash
            ${config.providers.bootloader.installHook} "$systemConfig"
          '';
        };

        finit.run.mount-cgroup = {
          enable = cfg.capabilities.sys_admin;
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

        # Lightweight ops/debugging utilities (mostly reusing libs already in closure), plus on
        # LXC/Incus (`sys_admin`) shadow `reboot` so finit's exit-0 doesn't get treated as poweroff.
        environment.systemPackages =
          (map lib.getBin [
            pkgs.curlMinimal
            pkgs.jq
            pkgs.lsof
            pkgs.mtr
            pkgs.netcat-openbsd
            pkgs.openssl
            pkgs.procps
            pkgs.htop
          ])
          ++ lib.optionals cfg.capabilities.sys_admin [
            (lib.hiPrio (
              pkgs.writeShellScriptBin "reboot" ''
                ${coreutils}/bin/sync
                exec ${coreutils}/bin/reboot -f
              ''
            ))
          ];
      };
    };

  ctx.finix =
    { ctx, lib, ... }:
    let
      engine = ctx.metadata.engine.type;
      caps = ctx.metadata.engine.capabilities;
      hasStatic = ctx.network.ipv4.addresses != [ ] || ctx.network.ipv6.addresses != [ ];
    in
    {
      infra.container = {
        runtime = lib.mkIf (builtins.elem engine [
          "lxc"
          "incus"
          "podman"
          "docker"
        ]) (lib.mkDefault engine);

        capabilities = lib.mapAttrs (_: v: lib.mkDefault v) (
          lib.filterAttrs (_: v: v != null) {
            inherit (caps) sys_admin net_admin mknod;
          }
        );
      };

      infra.network.topology = lib.mkIf hasStatic (lib.mkDefault "static");
    };
}
