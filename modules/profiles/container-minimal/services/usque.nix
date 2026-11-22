{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.usque;
  coreutils = config.programs.coreutils.package;
in
{
  options.services.usque = {
    enable = lib.mkEnableOption "usque Cloudflare WARP MASQUE client";

    package = lib.mkPackageOption pkgs "usque-static" { };

    socksAddr = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Local address usque SOCKS5 listens on.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 1080;
      description = "Local port usque SOCKS5 listens on.";
    };

    ipv6 = lib.mkEnableOption "use IPv6 for MASQUE connection";
  };

  config = lib.mkIf cfg.enable {
    users.users.usque = {
      group = "usque";
      home = "/var/lib/usque";
      description = "usque WARP MASQUE daemon";
    };
    users.groups.usque = { };

    environment.systemPackages = [ cfg.package ];

    finit.services.usque = {
      description = "usque Cloudflare WARP MASQUE client";
      user = "usque";
      group = "usque";
      state-dir = "usque";
      state-dir-mode = "0700";
      workingDirectory = "/var/lib/usque";
      environment = {
        GOMEMLIMIT = lib.mkDefault "48MiB";
        GOGC = lib.mkDefault 50;
      };
      exec-start-pre = pkgs.writeScript "usque-register" ''
        #!${coreutils}/bin/sh
        if [ ! -f /var/lib/usque/config.json ]; then
          ${coreutils}/bin/chpst -u usque:usque ${lib.getExe cfg.package} register --accept-tos
        fi
      '';
      command = lib.concatStringsSep " " (
        [
          (lib.getExe cfg.package)
          "socks"
          "-b ${cfg.socksAddr}"
          "-p ${toString cfg.port}"
          "--always-reconnect"
        ]
        ++ lib.optional cfg.ipv6 "-6"
      );
    };
  };
}
