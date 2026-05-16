{
  lib,
  ctx,
  fn,
  config,
  ...
}:
let
  cfg = config.local.loadbalance;
  lb = ctx.services.loadbalance;
  providerAdapter =
    name: value:
    value
    // {
      url._secret = value.url.path;
      _name = name;
    };
in
{
  local.loadbalance.settings = {
    providers = fn.sing.mkProviders (lib.mapAttrsToList providerAdapter lb.providers);
    outbounds = lib.mkAfter [
      {
        type = "selector";
        tag = "select";
        providers = cfg.providers;
      }
      {
        type = "loadbalance";
        tag = "auto";
        providers = cfg.providers;
        check = {
          interval = "2m";
        };
        pick = {
          objective = "leastload";
          strategy = "random";
          max_fail = 0;
          max_rtt = "3000ms";
          expected = 3;
          baselines = [
            "30ms"
            "50ms"
            "100ms"
            "150ms"
            "200ms"
            "250ms"
            "350ms"
          ];
        };
      }
    ];
  };

  local.loadbalance.providers = map (p: p.tag) cfg.settings.providers;
  local.loadbalance.secrets = lib.mapAttrsToList (n: v: v.url.path) lb.providers;
}
