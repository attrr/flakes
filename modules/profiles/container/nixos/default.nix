# NixOS container base & trim (boot.isContainer, systemd suppression, gc/journald).
{
  config,
  lib,
  pkgs,
  ...
}:
{
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
