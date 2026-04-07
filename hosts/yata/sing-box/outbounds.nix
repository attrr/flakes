{
  fn,
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
            tag = outbound.tag;
            server = builtins.head outbound.addresses;
            server_port = outbound.port;
            password = outbound.password.ph;
          };
          hysteriaCtxToSing = outbound: {
            tag = outbound.tag;
            server =  builtins.head outbound.addresses;
            server_port = outbound.port;
            password = outbound.password.ph;
            tls.server_name = outbound.tls.sni;
            tls.ech.config_path = outbound.tls.ech-config;
            tls.certificate_path = sb.ca;
          };
        in
        fn.sing.mkShadowsocks (map shadowsocksCtxToSing sb.outbounds.shadowsocks)
        ++ fn.sing.mkHysteria2 (map hysteriaCtxToSing sb.outbounds.hysteria2);
    };
}
