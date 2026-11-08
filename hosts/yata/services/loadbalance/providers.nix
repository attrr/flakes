{
  lib,
  ctx,
  helpers,
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
    http_clients = [ { tag = "direct"; } ];
    route.default_http_client = "direct";
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
        health_check = {
          interval = "2m";
        };
        pick = {
          objective = "quick";
          strategy = "random";
          max_fail = 0;
          max_rtt = "3000ms";
          min_nodes = 3;
        };
      }
    ];
  };

  yata.loadbalance.secrets = lib.mapAttrsToList (n: v: v.url.path) lb.providers;
}
