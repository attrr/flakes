# Glue from ctx.services.telemetry -> infra.telemetry.
{
  config,
  ctx,
  lib,
  options,
  registry,
  ...
}:
let
  cfg = ctx.services.telemetry;
  relay = cfg.relay;

  mode =
    if cfg.push then
      "push"
    else if cfg.local-only then
      "local-only"
    else
      "pull";
in
lib.mkMerge [
  (lib.mkIf cfg.enable {
    sops.secrets = lib.mkIf cfg.push {
      "${cfg.token.name}" = {
        owner =
          if config.users.users ? vmagent then
            lib.mkDefault "vmagent"
          else if config.users.users ? telemetry then
            lib.mkDefault "telemetry"
          else
            lib.mkDefault "root";
        restartUnits = lib.optionals (config.users.users ? vmagent) [ "vmagent.service" ];
      };
    };

    infra.telemetry = {
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
  })

  (lib.optionalAttrs (options.infra.telemetry ? relay) (
    lib.mkIf relay.enable {
      sops.secrets."${relay.tls.key.name}" = {
        owner = "caddy";
        reloadUnits = [ "caddy.service" ];
      };

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
    }
  ))
]
