# Glue from ctx.network -> infra.network and infra.tunnelbroker defaults.
{ ctx, lib, ... }:
let
  tun = ctx.network.ipv6.tunnel;
in
{
  infra.network = {
    interface = lib.mkIf (ctx.network.interface != null) (lib.mkDefault ctx.network.interface);
    ipv4 = {
      addresses = lib.mkDefault ctx.network.ipv4.cidr;
      gateway = lib.mkDefault ctx.network.ipv4.gateway;
    };
    ipv6 = lib.mkIf (!tun.enable) {
      addresses = lib.mkDefault ctx.network.ipv6.cidr;
      gateway = lib.mkDefault ctx.network.ipv6.gateway;
    };
  };

  infra.tunnelbroker = lib.mkIf tun.enable {
    enable = lib.mkDefault true;
    addresses = lib.mkDefault ctx.network.ipv6.cidr;
    gateway = lib.mkDefault ctx.network.ipv6.gateway;
    inherit (tun)
      type
      interface
      remote
      local
      ;
    mtu = lib.mkIf (tun.mtu != null) (lib.mkDefault tun.mtu);
    wireguard = lib.mkIf (tun.type == "wireguard") {
      privateKeyFile = lib.mkDefault tun.wireguard.private-key.path;
      peerPublicKey = lib.mkDefault tun.wireguard.peer-public-key;
      persistentKeepalive = lib.mkDefault tun.wireguard.persistent-keepalive;
    };
  };
}
