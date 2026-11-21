{ config, lib, ... }:
let
  cfg = config.infra.telemetry;
in
{
  imports = [
    ./agent.nix
    ./relay.nix
  ];

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        services.prometheus.exporters.node.enabledCollectors = lib.mkDefault [ "systemd" ];
      }

      (lib.mkIf (cfg.mode == "push") {
        services.vmagent.extraArgs = [ "-remoteWrite.maxDiskUsagePerURL=100MB" ];
      })

      (lib.mkIf (cfg.mode == "pull") {
        assertions = [
          {
            assertion = config.services.tailscale.enable;
            message = "infra.telemetry (pull) requires services.tailscale.enable";
          }
        ];
        systemd.services.prometheus-node-exporter = {
          after = [ "tailscaled.service" ];
          wants = [ "tailscaled.service" ];
        };
        networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ cfg.port ];
      })
    ]
  );
}
