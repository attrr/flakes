{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.vmagent;
  settingsFormat = pkgs.formats.yaml { };

  startCLIList = [
    (lib.getExe cfg.package)
  ]
  ++ lib.optionals (cfg.remoteWrite.url != null) [
    "-remoteWrite.url=${cfg.remoteWrite.url}"
    "-remoteWrite.tmpDataPath=/var/cache/vmagent/remote_write_tmp"
  ]
  ++ lib.optional (
    cfg.remoteWrite.basicAuthUsername != null
  ) "-remoteWrite.basicAuth.username=${cfg.remoteWrite.basicAuthUsername}"
  ++ lib.optional (
    cfg.remoteWrite.basicAuthPasswordFile != null
  ) "-remoteWrite.basicAuth.passwordFile=${cfg.remoteWrite.basicAuthPasswordFile}"
  ++ cfg.extraArgs;

  checkedConfig =
    file:
    if cfg.checkConfig then
      pkgs.runCommand "checked-vmagent-config" { nativeBuildInputs = [ cfg.package ]; } ''
        ln -s ${file} $out
        ${lib.getExe cfg.package} -promscrape.config=${file} -dryRun
      ''
    else
      file;

  prometheusConfigYml = checkedConfig (
    settingsFormat.generate "prometheusConfig.yaml" cfg.prometheusConfig
  );
in
{
  options.services.vmagent = {
    enable = lib.mkEnableOption "VictoriaMetrics vmagent";

    package = lib.mkPackageOption pkgs "vmagent" { };

    remoteWrite = {
      url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Endpoint for Prometheus-compatible remote_write.";
      };
      basicAuthUsername = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Basic Auth username used to connect to remote_write endpoint.";
      };
      basicAuthPasswordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "File that contains the Basic Auth password used to connect to remote_write endpoint.";
      };
    };

    prometheusConfig = lib.mkOption {
      type = lib.types.submodule { freeformType = settingsFormat.type; };
      default = { };
      description = "Config for Prometheus-style scrape targets.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open the firewall for vmagent HTTP port (8429).";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra args to pass to vmagent.";
    };

    checkConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Check configuration at build time with vmagent -dryRun.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.vmagent = {
      group = "vmagent";
      description = "VictoriaMetrics vmagent daemon";
    };
    users.groups.vmagent = { };

    providers.firewall.allowedTCPPorts = lib.mkIf (
      cfg.openFirewall && config.providers.firewall.backend != "none"
    ) [ 8429 ];

    finit.services.vmagent = {
      description = "VictoriaMetrics vmagent";
      user = "vmagent";
      group = "vmagent";
      cache-dir = "vmagent";
      cache-dir-mode = "0700";
      environment = {
        GOMEMLIMIT = "48MiB";
        GOGC = 50;
      };
      command = lib.escapeShellArgs (
        startCLIList
        ++ lib.optionals (cfg.prometheusConfig != { }) [ "-promscrape.config=${prometheusConfigYml}" ]
      );
      reload-triggers = lib.optional (cfg.prometheusConfig != { }) prometheusConfigYml;
    };
  };
}
