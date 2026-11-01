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
    in
    {
      enable = true;
      # to loadbalance
      virtualHosts."loadbalance.${ctx.metadata.fdqn}" = {
        inherit useACMEHost;
        extraConfig = ''
          reverse_proxy 127.0.0.1:9090
        '';
      };
      # to sing-box
      virtualHosts."sing-box.${ctx.metadata.fdqn}" = {
        inherit useACMEHost;
        extraConfig = ''
          reverse_proxy 127.0.0.1:9091
        '';
      };
    };
}
