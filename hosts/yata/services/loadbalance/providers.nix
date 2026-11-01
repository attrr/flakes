{
  lib,
  ctx,
  helpers,
  config,
  ...
}:
let
  lb = ctx.services.loadbalance;
  providerAdapter =
    name: value:
    value
    // {
      url._secret = value.url.path;
      _name = name;
    };
  providers = helpers.sing.mkProviders (lib.mapAttrsToList providerAdapter lb.providers);
  tags = map (p: p.tag) providers;
in
{
  yata.loadbalance.settings = {
    inherit providers;
    outbounds = lib.mkAfter [
      {
        type = "selector";
        tag = "select";
        providers = tags;
      }
      {
        type = "loadbalance";
        tag = "auto";
        providers = tags;
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

  yata.loadbalance.secrets = lib.mapAttrsToList (n: v: v.url.path) lb.providers;
}
