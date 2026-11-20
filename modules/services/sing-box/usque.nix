{
  config,
  lib,
  ...
}:
let
  cfg = config.infra.sing-box.usque;
  socksAddr = "127.0.0.1";
  socksPort = cfg.port;
in
{
  options.infra.sing-box.usque = {
    enable = lib.mkEnableOption "usque MASQUE-based WARP backend for sing-box";

    port = lib.mkOption {
      type = lib.types.port;
      default = 1080;
      description = "Local SOCKS5 port usque listens on (consumed by sing-box as outbound).";
    };

    ipv6 = lib.mkEnableOption "use IPv6 for MASQUE connection";
  };

  config = lib.mkIf (config.infra.sing-box.enable && cfg.enable) {
    assertions = [
      {
        assertion = !(config.infra.sing-box.warp-svc.enable && cfg.enable);
        message = "infra.sing-box.usque and infra.sing-box.warp-svc cannot both be enabled.";
      }
    ];

    # Wire usque's SOCKS5 as the sing-box "warp" outbound, reusing the same
    # outbound tag so default.nix route rules need no changes.
    infra.sing-box.settings.outbounds = lib.mkAfter [
      {
        type = "socks";
        tag = "warp";
        server = socksAddr;
        server_port = socksPort;
        version = "5";
      }
    ];

    services.usque = {
      enable = true;
      inherit (cfg) port ipv6;
    };
  };
}
