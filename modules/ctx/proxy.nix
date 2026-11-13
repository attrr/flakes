# ctx proxy services -> a sing-box server
{
  ctx,
  lib,
  ...
}:

let
  shadowsocks = ctx.services.shadowsocks;
  hysteria2 = ctx.services.hysteria2;
  vless = ctx.services.vless;
in
{
  infra.sing-box = lib.mkIf (shadowsocks.enable || hysteria2.enable || vless.enable) {
    enable = lib.mkDefault true;
    usque = {
      enable = lib.mkDefault true;
      ipv6 = lib.mkDefault (builtins.elem "ipv6-only" ctx.metadata.tags);
    };

    shadowsocks = {
      enable = lib.mkDefault shadowsocks.enable;
      port = lib.mkIf shadowsocks.enable shadowsocks.port;
      passwordPath = lib.mkIf shadowsocks.enable shadowsocks.password.path;
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
