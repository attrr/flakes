{ ctx, lib, ... }:

let
  shadowsocks = ctx.services.shadowsocks;
  hysteria2 = ctx.services.hysteria2;
  vless = ctx.services.vless;
in
{
  imports = [
    ../../modules/purpose/sing-box
  ];

  core.server.sing-box = {
    enable = lib.mkDefault true;
    warp.enable = true;
    shadowsocks = lib.mkIf shadowsocks.enable {
      enable = true;
      port = shadowsocks.port;
      passwordPath = shadowsocks.password.path;
    };
    hysteria2 = lib.mkIf hysteria2.enable {
      enable = true;
      port = hysteria2.port;
      passwordPath = hysteria2.password.path;
      tlsCertificatePath = hysteria2.tls.cert;
      tlsKeyPath = hysteria2.tls.key.path;
      echKeyPath = hysteria2.tls.ech-key.path;
    };
    vless = lib.mkIf vless.enable {
      enable = true;
      uuidPath = vless.uuid.path;
      privateKey = vless.private-key.path;
      shortIdPath = vless.short-id.path;
      serverName = vless.server-name;
    };
  };
}
