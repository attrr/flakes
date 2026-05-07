{
  fn,
  lib,
  ctx,
  ...
}:
let
  wg = ctx.services.wireguard;
  sb = ctx.services.sing-box;
in
{
  outboundConfig =
    let
      wgCtxToSing = peer: {
        allowed_ips = peer.addresses;
        public_key = peer.public-key;
        pre_shared_key = peer.pre-shared-key.ph;
      };
    in
    {
      endpoints = [
        {
          type = "wireguard";
          tag = "wg";
          system = true;
          address = wg.addresses;
          private_key = wg.private-key.ph;
          listen_port = 51820;
          peers = (map wgCtxToSing wg.peers);
        }
      ];
      outbounds =
        let
          shadowsocksCtxToSing = outbound: {
            tag = "out-${outbound.tag}";
            server = builtins.head outbound.addresses;
            server_port = outbound.port;
            password = outbound.password.ph;
          };
          hysteriaCtxToSing = outbound: {
            tag = "hy2-${outbound.tag}";
            server = builtins.head outbound.addresses;
            server_port = outbound.port;
            password = outbound.password.ph;
            tls.server_name = outbound.tls.sni;
            tls.ech.config_path = outbound.tls.ech-config;
            tls.certificate_path = sb.ca;
          };
          vlessCtxToSing =
            outbound:
            map (
              address:
              let
                basetag = "vless-${outbound.tag}";
                tag = if (fn.network.isIPv4 address) then "${basetag}-ipv4" else "${basetag}-ipv6";
              in
              {
                inherit tag;
                server = address;
                server_port = 443;
                uuid = outbound.uuid.ph;
                tls.server_name = outbound.server-name;
                tls.reality.public_key = outbound.public-key;
                tls.reality.short_id = outbound.short-id.ph;
              }
            ) outbound.addresses;
        in
        fn.sing.mkShadowsocks (map shadowsocksCtxToSing sb.outbounds.shadowsocks)
        ++ fn.sing.mkHysteria2 (map hysteriaCtxToSing sb.outbounds.hysteria2)
        ++ fn.sing.mkVless (lib.concatMap vlessCtxToSing sb.outbounds.vless);
    };
}
