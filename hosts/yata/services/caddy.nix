{
  ctx,
  registry,
  ...
}:
let
  wg = ctx.services.wireguard;
in
{
  # get hostname wildcard certs
  infra.acme = {
    enable = true;
    api = registry.acme-dns.url;
    certs."${ctx.metadata.fdqn}" = {
      domain = ctx.metadata.fdqn;
      extraDomainNames = [
        "*.${ctx.metadata.fdqn}"
      ];
      extraLegoFlags = [
        "--dns.resolvers=${wg.ipv4}:53"
      ];
    };
  };

  services.caddy =
    let
      # the *.fdqn cert; useACMEHost orders caddy after it and reloads it on renewal
      useACMEHost = ctx.metadata.fdqn;
      # external_ui is served from /nix/store (mtime = 1970-01-01 00:00:01), so
      # Go's http.FileServer emits a bogus Last-Modified that triggers multi-year
      # heuristic caching and false 304 Not Modified across metacubexd upgrades.
      mkProxy = upstream: {
        inherit useACMEHost;
        extraConfig = ''
          reverse_proxy ${upstream} {
            header_up -If-Modified-Since
            header_down -Last-Modified
          }
        '';
      };
    in
    {
      enable = true;
      virtualHosts."loadbalance.${ctx.metadata.fdqn}" = mkProxy "127.0.0.1:9090";
      virtualHosts."sing-box.${ctx.metadata.fdqn}" = mkProxy "127.0.0.1:9091";
    };
}
