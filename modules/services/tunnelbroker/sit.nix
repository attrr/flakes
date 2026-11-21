# 6in4 SIT IPv6 tunnel (e.g. HE Tunnelbroker), adapting to useNetworkd.
{ config, lib, ... }:
let
  cfg = config.infra.tunnelbroker;
  active = cfg.enable && cfg.type == "sit";
  useNetworkd = config.networking.useNetworkd;
  parseCidr =
    s:
    let
      m = builtins.match "([^/]+)/([0-9]+)" s;
    in
    if m == null then
      throw "infra.tunnelbroker: invalid CIDR '${s}'"
    else
      {
        address = builtins.elemAt m 0;
        prefixLength = builtins.fromJSON (builtins.elemAt m 1);
      };
in
{
  config = lib.mkIf active (
    lib.mkMerge [
      (lib.mkIf useNetworkd {
        systemd.network.netdevs."20-${cfg.interface}" = {
          netdevConfig = {
            Name = cfg.interface;
            Kind = "sit";
            MTUBytes = toString cfg.mtu;
          };
          tunnelConfig = {
            Remote = cfg.remote;
            Independent = true;
            TTL = 255;
          }
          // lib.optionalAttrs (cfg.local != null) { Local = cfg.local; };
        };

        systemd.network.networks."20-${cfg.interface}" = {
          matchConfig.Name = cfg.interface;
          address = cfg.addresses;
          routes = [
            ({ Destination = "::/0"; } // lib.optionalAttrs (cfg.gateway != null) { Gateway = cfg.gateway; })
          ];
        };
      })
      (lib.mkIf (!useNetworkd) {
        networking = {
          sits.${cfg.interface} = {
            remote = cfg.remote;
            ttl = 255;
          }
          // lib.optionalAttrs (cfg.local != null) { local = cfg.local; };
          interfaces.${cfg.interface} = {
            inherit (cfg) mtu;
            ipv6.addresses = map parseCidr cfg.addresses;
          };
          defaultGateway6 = lib.mkIf (cfg.gateway != null) {
            address = cfg.gateway;
            interface = cfg.interface;
          };
        };
      })
    ]
  );
}
