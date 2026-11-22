{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  cfg = config.infra.telemetry;
  coreutils = config.programs.coreutils.package;

  importUrl =
    if cfg.push.url != null then
      "${lib.removeSuffix "/api/v1/write" cfg.push.url}/api/v1/import/prometheus"
    else
      "";

  pushScript = pkgs.writeShellApplication {
    name = "telemetry-push";
    runtimeInputs = [
      coreutils
      pkgs.nano-exporter2
      pkgs.curlMinimal
    ];
    runtimeEnv = {
      TELEMETRY_HOST = cfg.labels.host;
      TELEMETRY_USER = cfg.push.username;
      TELEMETRY_TOKEN_FILE = toString cfg.push.tokenFile;
      TELEMETRY_URL = importUrl;
    };
    text = builtins.readFile ./push.sh;
  };
in
{
  imports = [ "${self}/modules/services/telemetry/agent.nix" ];

  options.services = {
    prometheus.exporters.node = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      internal = true;
    };
    vmagent = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      internal = true;
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.mode == "push";
        message = "${config.infra.server.hostname}: container-minimal infra.telemetry only supports mode = \"push\"";
      }
    ];

    users.users.telemetry = {
      group = "telemetry";
      description = "Lightweight telemetry pusher";
    };
    users.groups.telemetry = { };

    providers.scheduler.tasks.telemetry-push = {
      interval = "minutely";
      user = "telemetry";
      command = pushScript;
    };
  };
}
