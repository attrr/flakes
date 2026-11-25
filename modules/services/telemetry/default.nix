{
  includes = [ ../nano-exporter ];

  module = {
    common =
      { config, lib, ... }:
      let
        cfg = config.infra.telemetry;
      in
      {
        options.infra.telemetry = {
          enable = lib.mkEnableOption "host telemetry agent";

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

        config = lib.mkIf cfg.enable {
          assertions = [
            {
              assertion =
                cfg.mode != "push"
                || (
                  cfg.push.url != null && cfg.push.url != "" && cfg.push.tokenFile != null && cfg.push.tokenFile != ""
                );
              message = "infra.telemetry (push) requires push.url and push.tokenFile";
            }
            {
              assertion = cfg.mode != "pull" || (cfg.pull.address != null && cfg.pull.address != "");
              message = "infra.telemetry (pull) requires pull.address";
            }
          ];
        };
      };

    nixos =
      { config, lib, ... }:
      let
        cfg = config.infra.telemetry;
      in
      {
        imports = [
          ./agent.nix
          ./relay.nix
        ];

        config = lib.mkIf cfg.enable (
          lib.mkMerge [
            {
              services.prometheus.exporters.node.enabledCollectors = lib.mkDefault [ "systemd" ];
            }

            (lib.mkIf (cfg.mode == "push") {
              infra.secrets = [
                {
                  path = cfg.push.tokenFile;
                  owner = if config.users.users ? vmagent then "vmagent" else "root";
                  restartUnits = lib.optionals (config.users.users ? vmagent) [ "vmagent.service" ];
                }
              ];
              services.vmagent.extraArgs = [ "-remoteWrite.maxDiskUsagePerURL=100MB" ];
            })

            (lib.mkIf (cfg.mode == "pull") {
              assertions = [
                {
                  assertion = config.services.tailscale.enable;
                  message = "infra.telemetry (pull) requires services.tailscale.enable";
                }
              ];
              systemd.services.prometheus-node-exporter = {
                after = [ "tailscaled.service" ];
                wants = [ "tailscaled.service" ];
              };
              networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ cfg.port ];
            })
          ]
        );
      };

    finix =
      {
        config,
        lib,
        ...
      }:
      let
        cfg = config.infra.telemetry;

        importUrl =
          if cfg.push.url != null then
            "${lib.removeSuffix "/api/v1/write" cfg.push.url}/api/v1/import/prometheus"
          else
            "";
      in
      {
        config = lib.mkIf cfg.enable {
          assertions = [
            {
              assertion = cfg.mode == "push";
              message = "${config.infra.server.hostname}: finix infra.telemetry only supports mode = \"push\"";
            }
          ];

          infra.secrets = lib.optional (cfg.mode == "push") {
            path = cfg.push.tokenFile;
            owner = "nano-exporter";
          };

          services.nano-exporter = {
            enable = lib.mkDefault true;
            nodename = lib.mkDefault cfg.labels.host;
            push = {
              url = lib.mkDefault importUrl;
              basicAuthUsername = lib.mkDefault cfg.push.username;
              basicAuthPasswordFile = lib.mkDefault cfg.push.tokenFile;
            };
          };
        };
      };
  };

  ctx = {
    common =
      {
        ctx,
        lib,
        registry,
        ...
      }:
      let
        cfg = ctx.services.telemetry;
        mode =
          if cfg.push then
            "push"
          else if cfg.local-only then
            "local-only"
          else
            "pull";
      in
      {
        infra.telemetry = lib.mkIf cfg.enable {
          enable = lib.mkDefault true;
          mode = lib.mkDefault mode;
          port = lib.mkDefault cfg.port;
          labels = {
            host = lib.mkDefault ctx.metadata.hostname;
            group = lib.mkDefault ctx.metadata.group;
          };
          push = lib.mkIf cfg.push {
            url = lib.mkDefault registry.telemetry.relay.url;
            username = lib.mkDefault ctx.metadata.hostname;
            tokenFile = lib.mkDefault cfg.token.path;
          };
          pull = lib.mkIf (mode == "pull") {
            address = lib.mkDefault ctx.tailscale.ipv4;
          };
        };
      };

    nixos =
      {
        ctx,
        lib,
        registry,
        ...
      }:
      let
        relay = ctx.services.telemetry.relay;
      in
      lib.mkIf relay.enable {
        infra.telemetry.relay = {
          enable = lib.mkDefault true;
          domain = lib.mkDefault relay.domain;
          target = lib.mkDefault relay.target;
          tls = {
            cert = lib.mkDefault relay.tls.cert;
            keyPath = lib.mkDefault relay.tls.key.path;
          };
          nodes = lib.mkDefault (
            builtins.listToAttrs (
              map (
                n:
                lib.nameValuePair n.host {
                  hostname = n.host;
                  inherit (n) group;
                  auth.hash = n.hash;
                }
              ) (lib.filter (n: n.mode == "push" && n.hash != null) registry.telemetry.nodes)
            )
          );
        };
      };
  };
}
