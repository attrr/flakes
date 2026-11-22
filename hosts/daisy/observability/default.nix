{
  config,
  ctx,
  lib,
  registry,
  ...
}:
let
  cfg = config.daisy.observability;
  obs = ctx.services.observability;
  relayIps = registry.telemetry.relay.ips;
  hasSecretKey = obs.grafana.secret-key != null;
  hasAdminPassword = obs.grafana.admin-password != null;

  relabelHostToInstance = [
    {
      source_labels = [ "host" ];
      target_label = "instance";
    }
  ];
in
{
  imports = [
    ./alerting.nix
    ./blackbox.nix
  ];

  options.daisy.observability = {
    vmAddr = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:8428";
    };
    alertmanagerAddr = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:9093";
    };
    grafanaPort = lib.mkOption {
      type = lib.types.port;
      default = 3000;
    };
    scrapeInterval = lib.mkOption {
      type = lib.types.str;
      default = "60s";
    };
  };

  config = {
    services.victoriametrics = {
      enable = true;
      listenAddress = cfg.vmAddr;
      retentionPeriod = "90d";
      extraOptions = [
        # Shared host with harmonia + nix-builder; cap VM memory below the 60% default.
        "-memory.allowedPercent=30"
        "-maxLabelsPerTimeseries=40"
        "-search.maxUniqueTimeseries=100000"
      ];
      prometheusConfig = {
        global.scrape_interval = cfg.scrapeInterval;
        scrape_configs = [
          {
            job_name = "node";
            static_configs = map (t: {
              targets = [ "${t.address}:${toString t.port}" ];
              labels = {
                inherit (t) host group;
              };
            }) (lib.filter (t: t.mode == "pull") registry.telemetry.nodes);
            relabel_configs = relabelHostToInstance;
          }
          {
            job_name = "victoriametrics";
            static_configs = [
              {
                targets = [ cfg.vmAddr ];
                labels = {
                  host = ctx.metadata.hostname;
                  group = ctx.metadata.group;
                };
              }
            ];
            relabel_configs = relabelHostToInstance;
          }
        ];
      };
    };

    sops.secrets =
      lib.optionalAttrs hasSecretKey {
        "${obs.grafana.secret-key.name}".owner = "grafana";
      }
      // lib.optionalAttrs hasAdminPassword {
        "${obs.grafana.admin-password.name}".owner = "grafana";
      };

    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = cfg.grafanaPort;
          domain = obs.grafana.domain;
          root_url = "https://${obs.grafana.domain}";
        };
        security = {
          cookie_secure = true;
          disable_gravatar = true;
        }
        // lib.optionalAttrs hasSecretKey {
          secret_key = "$__file{${obs.grafana.secret-key.path}}";
        }
        // lib.optionalAttrs hasAdminPassword {
          admin_password = "$__file{${obs.grafana.admin-password.path}}";
        };
        users.allow_sign_up = false;
        analytics.reporting_enabled = false;
      };
      provision = {
        enable = true;
        datasources.settings.datasources = [
          {
            name = "VictoriaMetrics";
            type = "prometheus";
            access = "proxy";
            url = "http://${cfg.vmAddr}";
            isDefault = true;
            jsonData = {
              timeInterval = cfg.scrapeInterval;
              manageAlerts = false;
            };
          }
        ]
        ++ lib.optionals ctx.alerts.enable [
          {
            name = "Alertmanager";
            type = "alertmanager";
            uid = "alertmanager";
            access = "proxy";
            url = "http://${cfg.alertmanagerAddr}";
            jsonData.implementation = "prometheus";
          }
        ];
      };
    };

    services.caddy = {
      enable = true;
      virtualHosts = {
        ${obs.victoriametrics.domain} = {
          listenAddresses = ctx.tailscale.ips;
          useACMEHost = ctx.metadata.fdqn;
          extraConfig = ''
            # Only the telemetry-relay may write; deny admin/delete/snapshot endpoints on tailnet.
            ${lib.optionalString (relayIps != [ ]) ''
              @relay_write {
                remote_ip ${lib.concatStringsSep " " relayIps}
                method POST
                path /api/v1/write /api/v1/import/prometheus
              }
              handle @relay_write {
                request_body {
                  max_size 10MB
                }
                reverse_proxy ${cfg.vmAddr}
              }
            ''}

            @readonly {
              ${lib.optionalString (relayIps != [ ]) "not remote_ip ${lib.concatStringsSep " " relayIps}"}
              method GET HEAD POST
              path / /vmui /vmui/* /metrics /health /api/v1/query /api/v1/query_range /api/v1/series /api/v1/labels /api/v1/label/* /api/v1/status/* /api/v1/metadata /prometheus/api/v1/query /prometheus/api/v1/query_range /prometheus/api/v1/series /prometheus/api/v1/labels /prometheus/api/v1/label/* /prometheus/api/v1/status/* /prometheus/api/v1/metadata
            }
            handle @readonly {
              encode zstd gzip
              reverse_proxy ${cfg.vmAddr}
            }

            handle {
              respond 403
            }
          '';
        };

        ${obs.grafana.domain} = {
          listenAddresses = ctx.tailscale.ips;
          useACMEHost = ctx.metadata.fdqn;
          extraConfig = ''
            encode zstd gzip
            reverse_proxy 127.0.0.1:${toString cfg.grafanaPort}
          '';
        };
      };
    };

    networking.firewall.interfaces.tailscale0 = lib.mkIf config.services.tailscale.enable {
      allowedTCPPorts = [
        80
        443
      ];
      allowedUDPPorts = [ 443 ];
    };
  };
}
