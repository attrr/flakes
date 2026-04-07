{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pooper-scooper;
in
{
  options.services.pooper-scooper = {
    enable = lib.mkEnableOption "pooper-scooper service";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../pkgs/pooper-scooper/default.nix { };
      description = "The pooper-scooper package to use.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host to listen on.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 34443;
      description = "Port to listen on.";
    };

    doh_url = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "DNS-over-HTTPS URL for resolution (e.g. https://dns.google/resolve)";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.pooper-scooper = {
      description = "Pooper Scooper Proxy Cleaner Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart =
          "${cfg.package}/bin/pooper-scooper --host ${cfg.host} --port ${toString cfg.port}"
          + (lib.optionalString (cfg.doh_url != null) " --doh_url ${cfg.doh_url}");
        DynamicUser = true;
        Restart = "always";
        RestartSec = "5s";
      };
    };
  };
}
