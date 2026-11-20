{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.infra.container;
  coreutils = config.programs.coreutils.package;

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
    ./services/sing-box.nix
    ./services/usque.nix
    ./infra/server.nix
    ./infra/network.nix
    ./infra/tunnelbroker.nix
    ./infra/sing-box.nix
  ];

  options = {
    infra.container = {
      runtime = lib.mkOption {
        type = lib.types.enum (builtins.attrNames presets);
        default = "podman";
        description = "Container runtime preset seeding default capabilities.";
      };

      capabilities = {
        sys_admin = lib.mkEnableOption "CAP_SYS_ADMIN";
        net_admin = lib.mkEnableOption "CAP_NET_ADMIN";
        mknod = lib.mkEnableOption "CAP_MKNOD";
      };
    };
  };

  config = {
    infra.container.capabilities = lib.mapAttrs (_: lib.mkDefault) presets.${cfg.runtime};

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
      enable = lib.mkDefault true;
      trustedInterfaces = [ "lo" ];
      tables.nixos-fw.content = lib.mkAfter ''
        chain input-allow {
          icmpv6 type { nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } accept
        }
      '';
    };
    providers.firewall.backend = lib.mkDefault "nftables";
    environment.variables.PATH = [ "/run/wrappers/bin" ] ++ systemPath;

    # Place physical SUID wrappers under `/var/lib/wrappers/bin` (on `/`, avoiding `/run`'s `nosuid`
    # mount in Podman/Docker) and symlink `/run/wrappers -> /var/lib/wrappers` so `pam_unix.so`'s
    # compiled-in `/run/wrappers/bin/unix_chkpwd` resolves onto `/` where SUID works.
    security.wrapperDir = "${wrapperRoot}/bin";
    finit.tmpfiles.rules = [
      "L+ /run/wrappers - - - - ${wrapperRoot}"
      "d / 0755 - -"
      "d /var 0755 - -"
      "d /var/lib 0755 - -"
      "d ${wrapperRoot} 0755 - -"
      "d /var/empty - - -"
      "d /var/log - - -"
      "d /tmp 1777 - -"
      "d /etc - - -"
      "d /bin - - -"
      "d /sbin - - -"
      "d /lib/systemd - - -"
      "d /nix/var/nix/profiles - - -"
    ];

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

    # Container bootstrap & takeover script run during `$toplevel/activate`.
    system.activation.scripts.containerInit = {
      deps = [
        "containerLustrate"
        "specialfs"
        "users"
        "etc"
        "tmpfiles"
      ];
      text = ''
        ${lib.optionalString cfg.capabilities.mknod ''
          if [ ! -e /dev/net/tun ]; then
            mkdir -p /dev/net
            ${coreutils}/bin/mknod -m 0666 /dev/net/tun c 10 200 || true
          fi
        ''}
        touch /etc/NIXOS

        if [ ! -e /nix/var/nix/profiles/system ]; then
          ln -sfn "$systemConfig" /nix/var/nix/profiles/system
        fi

        ln -sfn "$systemConfig/init" /sbin/init
        ln -sfn "$systemConfig/init" /lib/systemd/systemd
      '';
    };

    finit.services.syslogd = {
      command = "${coreutils}/bin/syslogd -n -O /var/log/messages -s 200 -b 1";
    };
  };
}
