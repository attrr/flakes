# Blackbox HTTP/TLS probes for core internal & public endpoints.
{
  ctx,
  lib,
  pkgs,
  registry,
  ...
}:
let
  obs = ctx.services.observability;
  blackboxPort = 9115;
  blackboxAddr = "127.0.0.1:${toString blackboxPort}";

  optionalUrl = url: lib.optional (url != null && url != "") url;

  probes = {
    http_2xx = {
      job = "blackbox_http";
      codes = [
        200
        204
        301
        302
      ];
      targets = [
        "https://${obs.grafana.domain}"
        "https://${obs.victoriametrics.domain}/health"
      ]
      ++ optionalUrl (registry.harmonia.url or null)
      ++ optionalUrl (registry.forgejo.url or null)
      ++ optionalUrl (registry.ntfy.url or null);
    };

    http_api = {
      job = "blackbox_api";
      # API-only endpoints reject GET / with 403/404/405.
      codes = [
        200
        204
        401
        403
        404
        405
      ];
      targets = optionalUrl (registry.acme-dns.url or null) ++ optionalUrl registry.telemetry.relay.url;
    };
  };

  activeProbes = lib.filterAttrs (_: p: p.targets != [ ]) probes;
in
{
  services.prometheus.exporters.blackbox = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = blackboxPort;
    configFile = (pkgs.formats.yaml { }).generate "blackbox.yml" {
      modules = lib.mapAttrs (_: p: {
        prober = "http";
        timeout = "10s";
        http = {
          valid_status_codes = p.codes;
          preferred_ip_protocol = "ip4";
        };
      }) activeProbes;
    };
  };

  services.victoriametrics.prometheusConfig.scrape_configs = lib.mapAttrsToList (module: p: {
    job_name = p.job;
    metrics_path = "/probe";
    params.module = [ module ];
    static_configs = [ { inherit (p) targets; } ];
    relabel_configs = [
      {
        source_labels = [ "__address__" ];
        target_label = "__param_target";
      }
      {
        source_labels = [ "__param_target" ];
        target_label = "instance";
      }
      {
        target_label = "__address__";
        replacement = blackboxAddr;
      }
    ];
  }) activeProbes;
}
