{
  common =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.nano-exporter;
    in
    {
      options.services.nano-exporter = {
        enable = lib.mkEnableOption "nano-exporter lightweight Prometheus metrics pusher";

        package = lib.mkPackageOption pkgs "nano-exporter2" { };

        extraFlags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Additional command-line flags passed to nano-exporter.";
        };

        nodename = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Override the nodename label in node_uname_info (useful when sethostname(2) is denied).";
        };

        extraCollectors = lib.mkOption {
          type = lib.types.listOf (lib.types.either lib.types.path lib.types.str);
          default = [ ];
          description = ''
            Additional executable metric collectors invoked during each push, writing
            Prometheus text exposition format to stdout. Failures are isolated per collector.
          '';
        };

        push = {
          url = lib.mkOption {
            type = lib.types.str;
            description = "Prometheus text import endpoint URL (e.g. VictoriaMetrics /api/v1/import/prometheus).";
          };

          interval = lib.mkOption {
            type = lib.types.str;
            default = "minutely";
            description = "Push schedule interval (finit/systemd calendar spec, e.g. \"minutely\").";
          };

          basicAuthUsername = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Optional HTTP basic-auth username.";
          };

          basicAuthPasswordFile = lib.mkOption {
            type = lib.types.nullOr (lib.types.either lib.types.path lib.types.str);
            default = null;
            description = "Optional path to a file containing the HTTP basic-auth password.";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.push.url != "";
            message = "services.nano-exporter.push.url must be non-empty";
          }
          {
            assertion = (cfg.push.basicAuthUsername == null) == (cfg.push.basicAuthPasswordFile == null);
            message = "services.nano-exporter.push.basicAuthUsername and basicAuthPasswordFile must be set together";
          }
        ];
      };
    };

  nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.nano-exporter;
      pushScript = import ./push.nix {
        inherit lib pkgs cfg;
        runtimeTools = [
          pkgs.coreutils
          pkgs.gnused
          pkgs.gawk
          pkgs.gzip
          config.systemd.package
        ];
      };
    in
    {
      config = lib.mkIf cfg.enable {
        users.users.nano-exporter = {
          isSystemUser = true;
          group = "nano-exporter";
          description = "Lightweight Prometheus metrics pusher";
        };
        users.groups.nano-exporter = { };

        systemd.services.nano-exporter-push = {
          description = "Push host metrics via nano-exporter";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            User = "nano-exporter";
            Group = "nano-exporter";
            ExecStart = lib.getExe pushScript;
          };
        };

        systemd.timers.nano-exporter-push = {
          description = "Periodic nano-exporter metrics push";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cfg.push.interval;
            RandomizedDelaySec = "5s";
            AccuracySec = "5s";
          };
        };
      };
    };

  finix =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.nano-exporter;
      pushScript = import ./push.nix {
        inherit lib pkgs cfg;
        runtimeTools = [ config.programs.coreutils.package ];
      };
    in
    {
      config = lib.mkIf cfg.enable {
        users.users.nano-exporter = {
          group = "nano-exporter";
          description = "Lightweight Prometheus metrics pusher";
        };
        users.groups.nano-exporter = { };

        providers.scheduler.tasks.nano-exporter-push = {
          interval = cfg.push.interval;
          user = "nano-exporter";
          command = pushScript;
        };
      };
    };
}
