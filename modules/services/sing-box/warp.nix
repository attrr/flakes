{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.infra.sing-box.warp;
in
{
  options.infra.sing-box.warp = {
    enable = lib.mkEnableOption "enable warp container";

    port = lib.mkOption {
      type = lib.types.port;
      default = 1080;
      description = "Port the warp container's Shadowsocks inbound listens on.";
    };
  };

  config = lib.mkIf (config.infra.sing-box.enable && cfg.enable) {
    systemd.services.podman-warp = {
      serviceConfig = {
        Type = lib.mkForce "exec";
      };
    };
    virtualisation.oci-containers.containers.warp = {
      image = "warp:latest";
      imageStream = pkgs.warp-podman;
      autoStart = true;

      ports = [
        "127.0.0.1:${toString cfg.port}:1080/tcp"
        "127.0.0.1:${toString cfg.port}:1080/udp"
      ];

      extraOptions = [
        "--userns=auto"
        "--cap-add=NET_ADMIN"
        "--device=/dev/net/tun:/dev/net/tun"
        "--sysctl=net.ipv4.conf.all.src_valid_mark=1"
        "--sysctl=net.ipv6.conf.all.disable_ipv6=0"
      ];
    };

    # Shadowsocks outbound to the warp container's sing-box SS inbound.
    infra.sing-box.settings.outbounds = lib.mkAfter [
      {
        type = "shadowsocks";
        tag = "warp";
        method = "none";
        server = "127.0.0.1";
        server_port = cfg.port;
      }
    ];
  };
}
