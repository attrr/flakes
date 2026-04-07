{ ctx, ... }:

let
  ss = ctx.services.shadowsocks;
  hy2 = ctx.services.hysteria2;
in
{
  imports = [
    ../../modules/purpose/sing-box
  ];

  core.server.sing-box = {
    enable = true;
    shadowsocks = {
      enable = true;
      passwordPath = ss.password.path;
    };
    hysteria2 = {
      enable = true;
      port = hy2.port;
      passwordPath = hy2.password.path;
      tlsCertificatePath = hy2.tls.cert;
      tlsKeyPath = hy2.tls.key.path;
      echKeyPath = hy2.tls.ech-key.path;
    };
    warp.enable = true;
  };
}
