{
  helpers,
  lib,
  ctx,
  ...
}:
let
  wg = ctx.services.wireguard;
  sb = ctx.services.sing-box;

  shadowsocksAdapter =
    {
      tag,
      address,
      outbound,
    }:
    {
      inherit tag;
      server = address;
      server_port = outbound.port;
      password._secret = outbound.password.path;
      _tags = outbound.tags;
    };
  hysteriaAdapter =
    {
      tag,
      address,
      outbound,
    }:
    let
      # Proxy traffic traverses both server ingress (down-mbps) and egress (up-mbps),
      # so either direction is bounded by the server's slower link.
      proxyMbps = lib.min outbound.up-mbps outbound.down-mbps;
    in
    {
      inherit tag;
      server = address;
      server_port = outbound.port;
      up_mbps = lib.min 30 proxyMbps;
      down_mbps = lib.min 100 proxyMbps;
      password._secret = outbound.password.path;
      tls.server_name = outbound.tls.sni;
      tls.ech.config_path = outbound.tls.ech-config;
      tls.certificate_path = sb.ca;
      _tags = outbound.tags;
    };
  vlessAdapter =
    {
      tag,
      address,
      outbound,
    }:
    {
      inherit tag;
      server = address;
      server_port = outbound.port;
      uuid._secret = outbound.uuid.path;
      tls.server_name = outbound.server-name;
      tls.reality.public_key = outbound.public-key;
      tls.reality.short_id._secret = outbound.short-id.path;
      _tags = outbound.tags;
    };

  wireguardPeerAdapter = peer: {
    allowed_ips = peer.addresses;
    public_key = peer.public-key;
    pre_shared_key._secret = peer.pre-shared-key.path;
  };

  mapClassedAddrOutbound =
    namespace: outbound: class: addrs:
    lib.imap0 (
      i: addr:
      let
        tagPrefix = "${namespace}-${outbound.name}-${class}";
        tag = if i == 0 then tagPrefix else "${tagPrefix}-${toString i}";
      in
      {
        inherit tag outbound;
        address = addr;
      }
    ) addrs;

  mapMultiAddrOutbound =
    namespace: outbound:
    let
      results = lib.partition helpers.network.isIPv4 outbound.addresses;
      ipv4 = results.right;
      ipv6 = results.wrong;
    in
    (mapClassedAddrOutbound namespace outbound "v4" ipv4)
    ++ (mapClassedAddrOutbound namespace outbound "v6" ipv6);

  shadowsocks = helpers.sing.mkShadowsocks (
    map shadowsocksAdapter (lib.concatMap (mapMultiAddrOutbound "out") sb.outbounds.shadowsocks)
  );
  hysteria2 = helpers.sing.mkHysteria2 (
    map hysteriaAdapter (lib.concatMap (mapMultiAddrOutbound "hy2") sb.outbounds.hysteria2)
  );
  vless = helpers.sing.mkVless (
    map vlessAdapter (lib.concatMap (mapMultiAddrOutbound "vless") sb.outbounds.vless)
  );
  allOutbounds = shadowsocks ++ hysteria2 ++ vless;
  byTag = lib.zipAttrsWith (_: lib.concatLists) (
    map (o: lib.genAttrs o._tags (_: [ o.tag ])) allOutbounds
  );

in
{
  yata.sing-box.settings = {
    endpoints = [
      {
        type = "wireguard";
        tag = "wg";
        system = true;
        mtu = 1420;
        address = wg.addresses;
        private_key._secret = wg.private-key.path;
        listen_port = 51820;
        peers = (map wireguardPeerAdapter wg.peers);
      }
    ];
    outbounds = lib.mkOrder 300 (map (lib.filterAttrs (n: _: !lib.hasPrefix "_" n)) allOutbounds);
  };

  yata.sing-box.tags = byTag // {
    shadowsocks = map (o: o.tag) shadowsocks;
    hysteria2 = map (o: o.tag) hysteria2;
    vless = map (o: o.tag) vless;
  };
}
