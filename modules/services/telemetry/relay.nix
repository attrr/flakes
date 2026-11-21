{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.infra.telemetry.relay;

  # render auth and label mappings as standalone snippet
  nodes = pkgs.writeText "telemetry-nodes.caddy" ''
    basic_auth {
      ${lib.concatLines (lib.mapAttrsToList (_: n: "${n.auth.user} ${n.auth.hash}") cfg.nodes)}
    }
    map {http.auth.user.id} {telemetry_host} {telemetry_group} {
      ${lib.concatLines (
        lib.mapAttrsToList (_: n: "${n.auth.user} ${n.hostname} ${n.group}") cfg.nodes
      )}
      default {http.auth.user.id} untrusted
    }
  '';
in
{
  options.infra.telemetry.relay = {
    enable = lib.mkEnableOption "HTTPS telemetry write relay (Caddy -> VictoriaMetrics)";

    domain = lib.mkOption {
      type = lib.types.str;
      description = "Public domain name served by the telemetry relay.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8443;
      description = "TCP port for the telemetry relay virtual host.";
    };

    target = lib.mkOption {
      type = lib.types.str;
      description = "Upstream VictoriaMetrics base URL.";
    };

    tls = {
      cert = lib.mkOption {
        type = lib.types.oneOf [
          lib.types.path
          lib.types.str
        ];
        description = "Path to the TLS certificate PEM file.";
      };
      keyPath = lib.mkOption {
        type = lib.types.str;
        description = "Path to the TLS private key PEM file.";
      };
    };

    nodes = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, config, ... }:
          {
            options = {
              hostname = lib.mkOption {
                type = lib.types.str;
                default = name;
                description = "Logical hostname used in telemetry (may differ from OS hostname).";
              };
              group = lib.mkOption {
                type = lib.types.str;
                description = "Authoritative host group for alerting and routing.";
              };
              auth = {
                user = lib.mkOption {
                  type = lib.types.str;
                  default = config.hostname;
                  defaultText = lib.literalExpression "config.hostname";
                  description = "Basic-auth username for remote-write.";
                };
                hash = lib.mkOption {
                  type = lib.types.str;
                  description = "Password hash of the node's remote-write token.";
                };
              };
            };
          }
        )
      );
      default = { };
      description = "Authorized push nodes keyed by logical identifier.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.nodes != { };
        message = "infra.telemetry.relay.nodes must not be empty when relay is enabled";
      }
      {
        assertion = cfg.target != "";
        message = "infra.telemetry.relay.target must be non-empty";
      }
    ];

    services.caddy = {
      enable = lib.mkDefault true;
      virtualHosts."${cfg.domain}:${toString cfg.port}" = {
        extraConfig = ''
          tls ${cfg.tls.cert} ${cfg.tls.keyPath}

          @write {
            # Reject direct-to-origin traffic before bcrypt basic_auth to prevent CPU DoS.
            import ${pkgs.cloudflare-ips}/share/cloudflare-ips/caddy/remote-ip.caddy
            method POST
            path /api/v1/write
          }

          handle @write {
            route {
              request_body {
                max_size 10MB
              }
              import ${nodes}
              # Strip client query params and force authoritative host/instance/group labels in VM.
              rewrite * /api/v1/write?extra_label=host={telemetry_host}&extra_label=instance={telemetry_host}&extra_label=group={telemetry_group}
              reverse_proxy ${cfg.target} {
                header_up -Authorization
              }
            }
          }

          handle {
            respond 403
          }
        '';
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
