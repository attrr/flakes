{ config, lib, ... }:
let
  cfg = config.infra.telemetry;
in
{
  imports = [ ../../../services/telemetry/agent.nix ];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.mode == "push";
        message = "${config.infra.server.hostname}: container-minimal infra.telemetry only supports mode = \"push\"";
      }
    ];

    services.prometheus.exporters.node.enabledCollectors = lib.mkDefault [ "runit" ];
    services.vmagent.extraArgs = [ "-remoteWrite.maxDiskUsagePerURL=16MB" ];
  };
}
