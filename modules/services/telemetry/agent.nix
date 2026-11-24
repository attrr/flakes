# NixOS node_exporter + vmagent push implementation for infra.telemetry.
{ config, lib, ... }:
let
  cfg = config.infra.telemetry;
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        services.prometheus.exporters.node = {
          enable = lib.mkDefault true;
          port = lib.mkDefault cfg.port;
          listenAddress = lib.mkDefault (if cfg.mode == "pull" then cfg.pull.address else "127.0.0.1");
        };
      }

      (lib.mkIf (cfg.mode == "push") {
        services.vmagent = {
          enable = lib.mkDefault true;
          remoteWrite = {
            url = lib.mkDefault cfg.push.url;
            basicAuthUsername = lib.mkDefault cfg.push.username;
            basicAuthPasswordFile = lib.mkDefault cfg.push.tokenFile;
          };
          extraArgs = [
            "-httpListenAddr=127.0.0.1:8429"
            "-memory.allowedPercent=10"
          ];
          prometheusConfig = {
            global.scrape_interval = "60s";
            scrape_configs = [
              {
                job_name = "node";
                static_configs = [
                  {
                    targets = [ "127.0.0.1:${toString cfg.port}" ];
                    labels = {
                      inherit (cfg.labels) host group;
                    };
                  }
                ];
                relabel_configs = [
                  {
                    source_labels = [ "host" ];
                    target_label = "instance";
                  }
                ];
                # Some providers deny sethostname(2), so pin nodename to the logical host.
                metric_relabel_configs = [
                  {
                    source_labels = [ "__name__" ];
                    regex = "node_uname_info";
                    target_label = "nodename";
                    replacement = cfg.labels.host;
                  }
                ];
              }
            ];
          };
        };
      })
    ]
  );
}
