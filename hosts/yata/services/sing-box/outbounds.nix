{
  fn,
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
    };
  hysteriaAdapter =
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
      tls.server_name = outbound.tls.sni;
      tls.ech.config_path = outbound.tls.ech-config;
      tls.certificate_path = sb.ca;
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
      server_port = 443;
      uuid._secret = outbound.uuid.path;
      tls.server_name = outbound.server-name;
      tls.reality.public_key = outbound.public-key;
      tls.reality.short_id._secret = outbound.short-id.path;
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
        tagPrefix = "${namespace}-${outbound.tag}-${class}";
        tag = if i == 0 then tagPrefix else "${tagPrefix}-${i}";
      in
      {
        inherit tag outbound;
        address = addr;
      }
    ) addrs;

  mapMultiAddrOutbound =
    namespace: outbound:
    let
      results = lib.partition fn.network.isIPv4 outbound.addresses;
      ipv4 = results.right;
      ipv6 = results.wrong;
    in
    (mapClassedAddrOutbound namespace outbound "ipv4" ipv4)
    ++ (mapClassedAddrOutbound namespace outbound "ipv6" ipv6);

  shadowsocks = fn.sing.mkShadowsocks (
    map shadowsocksAdapter (lib.concatMap (mapMultiAddrOutbound "out") sb.outbounds.shadowsocks)
  );
  hysteria2 = fn.sing.mkHysteria2 (
    map hysteriaAdapter (lib.concatMap (mapMultiAddrOutbound "hy2") sb.outbounds.hysteria2)
  );
  vless = fn.sing.mkVless (
    map vlessAdapter (lib.concatMap (mapMultiAddrOutbound "vless") sb.outbounds.vless)
  );

in
{
  local.sing-box.settings = {
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
    outbounds = lib.mkOrder 300 (shadowsocks ++ hysteria2 ++ vless);
  };

  local.sing-box.tags = {
    shadowsocks = map (o: o.tag) shadowsocks;
    hysteria2 = map (o: o.tag) hysteria2;
    vless = map (o: o.tag) vless;
  };
}
