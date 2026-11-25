{
  config,
  lib,
  pkgs,
  ...
}:
let
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
    ./deploy.nix
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

    # Lightweight ops/debugging utilities (mostly reusing libs already in closure).
    environment.systemPackages = map lib.getBin [
      pkgs.curlMinimal
      pkgs.jq
      pkgs.lsof
      pkgs.mtr
      pkgs.netcat-openbsd
      pkgs.openssl
      pkgs.procps
      pkgs.htop
    ];
  };
}
