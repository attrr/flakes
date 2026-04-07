{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.core.server.sing-box.warp;
  warp-podman = pkgs.callPackage ../../../pkgs/warp-podman/default.nix { };
in
{
  options.core.server.sing-box.warp = {
    enable = lib.mkEnableOption "enable warp container";
    lowend = lib.mkEnableOption "enable warp sysctl fix";
  };

  config = lib.mkIf (config.core.server.sing-box.enable && cfg.enable) {
    virtualisation.oci-containers.containers.warp = {
      image = "warp:latest";
      imageStream = warp-podman;
      autoStart = true;

      ports = [
        "127.0.0.1:1080:1080/tcp"
        "127.0.0.1:1080:1080/udp"
      ];

      extraOptions = [
        "--userns=auto"
        "--cap-add=NET_ADMIN"
        "--device=/dev/net/tun:/dev/net/tun"
        "--sysctl=net.ipv4.conf.all.src_valid_mark=1"
        "--sysctl=net.ipv6.conf.all.disable_ipv6=0"
      ];
    };

    systemd.services.podman-network-restore = {
      description = "Restore Podman networking after sysctl overwrites";
      # Bind directly to the sysctl service
      partOf = [ "systemd-sysctl.service" ];
      wantedBy = [ "systemd-sysctl.service" ];
      after = [ "systemd-sysctl.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.podman}/bin/podman network reload --all";
      };
    };

    boot.kernel.sysctl = lib.mkIf cfg.lowend {
      "net.core.rmem_default" = lib.mkForce 262144;
      "net.core.rmem_max"     = lib.mkForce 8388608;
    };
  };
}
