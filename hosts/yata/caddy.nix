{
  ctx,
  lib,
  registry,
  ...
}:
let
  wg = ctx.services.wireguard;
in
{
  imports = [
    ../../modules/purpose/acme.nix
  ];

  # get hostname wildcard certs
  core.acme = {
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
      reloadServices = [ "caddy.service" ];
    };
  };

  services.caddy =
    let
      listenAddrs = map (s: builtins.head (lib.splitString "/" s)) wg.addresses;
      tlsConfig = ''
        tls /var/lib/acme/${ctx.metadata.fdqn}/cert.pem /var/lib/acme/${ctx.metadata.fdqn}/key.pem
      '';
    in
    {
      enable = true;
      # to loadbalance
      virtualHosts."loadbalance.${ctx.metadata.fdqn}" = {
        listenAddresses = listenAddrs;
        extraConfig = ''
          ${tlsConfig}
          reverse_proxy 127.0.0.1:9090
        '';
      };
      # to sing-box
      virtualHosts."sing-box.${ctx.metadata.fdqn}" = {
        listenAddresses = listenAddrs;
        extraConfig = ''
          ${tlsConfig}
          reverse_proxy 127.0.0.1:9091
        '';
      };
    };
}
