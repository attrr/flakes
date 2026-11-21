# Platform-independent host telemetry agent (node_exporter + optional vmagent push).
{ config, lib, ... }:
let
  cfg = config.infra.telemetry;
in
{
  options.infra.telemetry = {
    enable = lib.mkEnableOption "host telemetry (node_exporter + optional vmagent push)";

    mode = lib.mkOption {
      type = lib.types.enum [
        "push"
        "pull"
        "local-only"
      ];
      default = "local-only";
      description = "How node metrics are exposed or shipped.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9100;
      description = "Port for node_exporter.";
    };

    labels = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Host label attached to pushed metrics.";
      };
      group = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Group label attached to pushed metrics.";
      };
    };

    push = {
      url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Remote-write endpoint URL.";
      };
      username = lib.mkOption {
        type = lib.types.str;
        default = cfg.labels.host;
        defaultText = lib.literalExpression "config.infra.telemetry.labels.host";
        description = "Basic-auth username for remote-write.";
      };
      tokenFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to the remote-write token file.";
      };
    };

    pull = {
      address = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Bind address for node_exporter in pull mode.";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion =
              cfg.mode != "push"
              || (
                cfg.push.url != null
                && cfg.push.url != ""
                && cfg.push.tokenFile != null
                && cfg.push.tokenFile != ""
              );
            message = "infra.telemetry (push) requires push.url and push.tokenFile";
          }
          {
            assertion = cfg.mode != "pull" || (cfg.pull.address != null && cfg.pull.address != "");
            message = "infra.telemetry (pull) requires pull.address";
          }
        ];

        services.prometheus.exporters.node = {
          enable = lib.mkDefault true;
          port = lib.mkDefault cfg.port;
          listenAddress = lib.mkDefault (if cfg.mode == "pull" then cfg.pull.address else "127.0.0.1");
        };
      }

      (lib.mkIf (cfg.mode == "push") {
        services.vmagent = {
          enable = lib.mkDefault true;
          remoteWrite = {
            url = lib.mkDefault cfg.push.url;
            basicAuthUsername = lib.mkDefault cfg.push.username;
            basicAuthPasswordFile = lib.mkDefault cfg.push.tokenFile;
          };
          extraArgs = [
            "-httpListenAddr=127.0.0.1:8429"
            "-memory.allowedPercent=10"
          ];
          prometheusConfig = {
            global.scrape_interval = "60s";
            scrape_configs = [
              {
                job_name = "node";
                static_configs = [
                  {
                    targets = [ "127.0.0.1:${toString cfg.port}" ];
                    labels = {
                      inherit (cfg.labels) host group;
                    };
                  }
                ];
                relabel_configs = [
                  {
                    source_labels = [ "host" ];
                    target_label = "instance";
                  }
                ];
                # Some providers deny sethostname(2), so pin nodename to the logical host.
                metric_relabel_configs = [
                  {
                    source_labels = [ "__name__" ];
                    regex = "node_uname_info";
                    target_label = "nodename";
                    replacement = cfg.labels.host;
                  }
                ];
              }
            ];
          };
        };
      })
    ]
  );
}
