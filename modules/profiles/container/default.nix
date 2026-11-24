# Container profile (tarball-booted, low-disk/RAM).
# Runtime presets seed default capabilities under infra.container.capabilities;
# network, tmpfiles, and /run mounts derive from them.
{
  config,
  lib,
  pkgs,
  options,
  ...
}:
let
  cfg = config.infra.container;
  cap = cfg.capabilities;
  aspectLib = import ../../../lib/aspects.nix { inherit lib; };
in
{
  imports = aspectLib.resolveModule "nixos" [ ../server ] ++ [ ./common.nix ];

  config = lib.mkMerge [
    {
      infra.container.runtime = lib.mkDefault "lxc";
      infra.server.lowend.enable = lib.mkDefault true;

      boot.isContainer = true;
      fileSystems."/" = {
        device = lib.mkDefault "none";
        fsType = lib.mkDefault "ext4";
      };
      services.openssh.startWhenNeeded = false;

      # Containers share the host kernel and typically mount /proc/sys read-only.
      boot.kernel.sysctl = lib.mkForce { };

      # No host kernel modules or block devices to manage.
      boot.blacklistedKernelModules = lib.mkForce [ ];
      boot.extraModprobeConfig = lib.mkForce "";
      zramSwap.enable = lib.mkForce false;
      infra.server.auto-resize = lib.mkForce false;

      # ramfs can fail in unprivileged/restricted containers.
      boot.specialFileSystems."/run/keys".fsType = lib.mkForce "tmpfs";
      sops.useTmpfs = true;

      boot.postBootCommands = ''
        if [ -f /nix-path-registration ]; then
          ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration &&
          rm /nix-path-registration
        fi
        if [ ! -e /nix/var/nix/profiles/system ]; then
          ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
        fi
        if ! ${pkgs.util-linux}/bin/mountpoint -q /sys/fs/cgroup; then
          ${pkgs.util-linux}/bin/mount -t cgroup2 none /sys/fs/cgroup || true
        fi
      '';

      system.activationScripts.containerInit = {
        deps = [ "containerLustrate" ];
        text = ''
          mkdir -p /sbin /bin /lib/systemd
          ln -sfn $systemConfig/init /sbin/init
          ln -sfn $systemConfig/init /lib/systemd/systemd
          ln -sfn ${pkgs.bashInteractive}/bin/bash /bin/bash
        '';
      };

      # First-boot takeover lustrate: move non-NixOS root cruft to /old-root
      # while preserving /nix, active mountpoints, and tarball identity files.
      system.activationScripts.containerLustrate = ''
        if [ ! -L /etc/static ]; then
          mkdir -p /old-root/etc/ssh /old-root/var/lib
          for d in /*; do
            case "$d" in
              /nix|/nix-path-registration|/proc|/sys|/dev|/run|/tmp|/etc|/var|/old-root) ;;
              *) mv "$d" /old-root/ 2>/dev/null || true ;;
            esac
          done
          for d in /etc/*; do
            case "$d" in
              /etc/NIXOS|/etc/static|/etc/hostname|/etc/hosts|/etc/resolv.conf|/etc/ssh) ;;
              *) mv "$d" /old-root/etc/ 2>/dev/null || true ;;
            esac
          done
          for d in /etc/ssh/*; do
            case "$d" in
              /etc/ssh/ssh_host_*) ;;
              *) mv "$d" /old-root/etc/ssh/ 2>/dev/null || true ;;
            esac
          done
          for d in /var/*; do
            case "$d" in
              /var/lib|/var/log|/var/empty) ;;
              *) mv "$d" /old-root/var/ 2>/dev/null || true ;;
            esac
          done
          for d in /var/lib/*; do
            [ "$d" = /var/lib/nixos ] || mv "$d" /old-root/var/lib/ 2>/dev/null || true
          done
        fi
      '';
      system.activationScripts.binsh.deps = [ "containerLustrate" ];
      system.activationScripts.etc.deps = [ "containerLustrate" ];
      system.activationScripts.users.deps = [ "containerLustrate" ];
      system.activationScripts.machineId = {
        deps = [ "etc" ];
        text = ''
          if [ ! -s /etc/machine-id ] || [ "$(cat /etc/machine-id)" = "uninitialized" ]; then
            rm -f /etc/machine-id
            ${config.systemd.package}/bin/systemd-machine-id-setup
          fi
        '';
      };

      systemd.coredump.enable = false;
      systemd.suppressedSystemUnits = [
        "console-getty.service"
        "sys-kernel-debug.mount"
        "sys-kernel-tracing.mount"
        "systemd-journald-audit.socket"
        "systemd-modules-load.service"
        "systemd-oomd.service"
        "systemd-sysctl.service"
      ];

      # trim
      nix.gc.options = lib.mkOverride 900 "--delete-older-than 3d";
      nix.settings = {
        min-free = lib.mkOverride 900 (64 * 1024 * 1024);
        max-free = lib.mkOverride 900 (128 * 1024 * 1024);
      };
      services.journald.extraConfig = ''
        Storage=volatile
        RuntimeMaxUse=32M
      '';
      services.fail2ban.enable = lib.mkForce false;
      programs.neovim.enable = lib.mkForce false;
      programs.git.enable = lib.mkForce false;
      fonts.fontconfig.enable = lib.mkForce false;
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
      # /run is already tmpfs; mount units under /run fail without CAP_SYS_ADMIN.
      systemd.suppressedSystemUnits = [
        "run-keys.mount"
        "run-wrappers.mount"
      ];
      systemd.services.suid-sgid-wrappers.serviceConfig = {
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /run/wrappers /var/lib/wrappers";
        # /run is mounted nosuid in Podman; mirror sudo onto / so SUID works.
        ExecStartPost = pkgs.writeShellScript "podman-sudo-suid" ''
          if [ -e /run/wrappers/bin/sudo ]; then
            ${pkgs.coreutils}/bin/install -o 0 -g 0 -m 4755 /run/wrappers/bin/sudo /var/lib/wrappers/sudo
            ${pkgs.coreutils}/bin/ln -sfn /var/lib/wrappers/sudo /run/wrappers/bin/sudo
          fi
        '';
      };
      # User=nscd + RestrictSUIDSGID=true triggers 217/USER without CAP_SYS_ADMIN.
      systemd.services.nscd.serviceConfig.RestrictSUIDSGID = lib.mkForce false;
      # /run is already tmpfs; skip mounting /run/secrets.d when already on tmpfs.
      sops.package = lib.mkDefault (
        options.sops.package.default.overrideAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            substituteInPlace pkgs/sops-install-secrets/linux.go \
              --replace-fail 'mounted, err := mountinfo.Mounted(mountpoint)' '_, err := mountinfo.Mounted(mountpoint)' \
              --replace-fail 'if !mounted || int32(buf.Type) != fsmagic {' 'if int32(buf.Type) != fsmagic {'
          '';
        })
      );
      # Runtime already mounts /dev, /proc, /run; remounting fails without CAP_SYS_ADMIN.
      system.activationScripts.specialfs = lib.mkForce ''
        mkdir -p -m 0750 /run/keys
      '';
    })
  ];
}
