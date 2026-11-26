{
  lib,
  ctx,
  registry,
  ...
}:
let
  wg = ctx.services.wireguard;
  fdqn = ctx.metadata.fdqn;
  # the downloaders' netns, see containers.nix
  direct = "10.200.0.2";

  upstreams = {
    jellyfish = "127.0.0.1:8096";
    torrent = "${direct}:8080";
    transmission = "${direct}:9091";
    sabnzbd = "${direct}:8082";
  };
in
{
  infra.acme = {
    enable = true;
    api = registry.acme-dns.url;
    certs.${fdqn} = {
      domain = fdqn;
      extraDomainNames = [ "*.${fdqn}" ];
    };
  };

  services.caddy = {
    enable = true;
    virtualHosts = lib.mapAttrs' (
      name: upstream:
      lib.nameValuePair "${name}.${fdqn}" {
        useACMEHost = fdqn;
        listenAddresses = [
          wg.ipv4
          wg.ipv6
        ];
        extraConfig = ''
          encode zstd
          reverse_proxy ${upstream}
        '';
      }
    ) upstreams;
  };
  # it binds the wg addresses
  systemd.services.caddy = {
    wants = [ "wireguard-wg0.service" ];
    after = [ "wireguard-wg0.service" ];
  };

  networking.firewall.interfaces.wg0.allowedTCPPorts = [
    80
    443
  ];
}
