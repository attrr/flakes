{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.prometheus.exporters.node;
  args = [
    (lib.getExe cfg.package)
    "--web.listen-address=${cfg.listenAddress}:${toString cfg.port}"
  ]
  ++ map (c: "--collector.${c}") cfg.enabledCollectors
  ++ map (c: "--no-collector.${c}") cfg.disabledCollectors
  ++ cfg.extraFlags;
in
{
  options.services.prometheus.exporters.node = {
    enable = lib.mkEnableOption "Prometheus node_exporter";

    package = lib.mkPackageOption pkgs "prometheus-node-exporter" { };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9100;
      description = "Port to listen on.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Address to listen on.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open port in firewall for incoming connections.";
    };

    enabledCollectors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Collectors to enable in addition to the default ones.";
    };

    disabledCollectors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Collectors to disable which are enabled by default.";
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra commandline options when launching node_exporter.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.node-exporter = {
      group = "node-exporter";
      description = "Prometheus node_exporter daemon";
    };
    users.groups.node-exporter = { };

    providers.firewall.allowedTCPPorts = lib.mkIf (
      cfg.openFirewall && config.providers.firewall.backend != "none"
    ) [ cfg.port ];

    finit.services.prometheus-node-exporter = {
      description = "Prometheus node_exporter";
      user = "node-exporter";
      group = "node-exporter";
      environment = {
        GOMEMLIMIT = "32MiB";
        GOGC = 50;
      };
      command = lib.escapeShellArgs args;
    };
  };
}
