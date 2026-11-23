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

  secretNames =
    lib.optional shadowsocks.enable shadowsocks.password.name
    ++ lib.optionals hysteria2.enable [
      hysteria2.password.name
      hysteria2.tls.key.name
      hysteria2.tls.ech-key.name
    ]
    ++ lib.optionals vless.enable [
      vless.uuid.name
      vless.private-key.name
      vless.short-id.name
    ];
in
{
  sops.secrets = lib.genAttrs secretNames (_: {
    owner = lib.mkDefault "sing-box";
  });

  infra.sing-box = lib.mkIf (shadowsocks.enable || hysteria2.enable || vless.enable) {
    enable = lib.mkDefault true;
    usque = {
      enable = lib.mkDefault true;
      ipv6 = lib.mkDefault (builtins.elem "ipv6-only" ctx.metadata.tags);
      http2 = lib.mkDefault ctx.services.usque.http2;
    };

    shadowsocks = {
      enable = lib.mkDefault shadowsocks.enable;
      port = lib.mkIf shadowsocks.enable shadowsocks.port;
      passwordPath = lib.mkIf shadowsocks.enable shadowsocks.password.path;
    };

    hysteria2 = lib.mkIf hysteria2.enable {
      enable = true;
      port = hysteria2.port;
      upMbps = hysteria2.up-mbps;
      downMbps = hysteria2.down-mbps;
      passwordPath = hysteria2.password.path;
      tlsCertificatePath = hysteria2.tls.cert;
      tlsKeyPath = hysteria2.tls.key.path;
      echKeyPath = hysteria2.tls.ech-key.path;
    };

    vless = lib.mkIf vless.enable {
      enable = true;
      port = vless.port;
      uuidPath = vless.uuid.path;
      privateKey = vless.private-key.path;
      shortIdPath = vless.short-id.path;
      serverName = vless.server-name;
    };
  };
}
