# vmalert -> alertmanager -> alertmanager-ntfy (all local on daisy)
{
  config,
  ctx,
  lib,
  ...
}:
let
  cfg = config.daisy.observability;
  ntfyHookAddr = "127.0.0.1:8000";
in
lib.mkIf ctx.alerts.enable {
  sops.templates."alertmanager-ntfy.yml".content = ''
    ntfy:
      auth:
        token: "${ctx.alerts.token.ph}"
  '';

  services.vmalert.instances."" = {
    enable = true;
    settings = {
      "datasource.url" = "http://${cfg.vmAddr}";
      "httpListenAddr" = "127.0.0.1:8880";
      "remoteWrite.url" = "http://${cfg.vmAddr}";
      "notifier.url" = [ "http://${cfg.alertmanagerAddr}" ];
      evaluationInterval = cfg.scrapeInterval;
    };
    rules.groups = [
      {
        name = "node";
        rules = [
          {
            alert = "HostOffline";
            expr = "time() - max by (host, group) (timestamp(last_over_time(node_uname_info[7d]))) > 180";
            for = "3m";
            labels.severity = "critical";
            annotations = {
              summary = "{{ $labels.host }} offline";
              description = "No node_exporter metrics received from {{ $labels.host }} for > 3m.";
            };
          }
          {
            alert = "SystemdUnitFailed";
            expr = ''node_systemd_unit_state{state="failed"} == 1'';
            for = "2m";
            labels.severity = "warning";
            annotations = {
              summary = "{{ $labels.host }}: {{ $labels.name }} failed";
              description = "Systemd unit {{ $labels.name }} on {{ $labels.host }} is in failed state.";
            };
          }
          {
            alert = "ServiceDown";
            expr = "node_service_state == 0 and node_service_desired_state == 1";
            for = "2m";
            labels.severity = "warning";
            annotations = {
              summary = "{{ $labels.host }}: {{ $labels.service }} down";
              description = "{{ $labels.supervisor }} service {{ $labels.service }} on {{ $labels.host }} is down while desired up.";
            };
          }
          {
            alert = "DiskMayFillIn24Hours";
            expr = ''predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[3h], 86400) <= 0 and node_filesystem_readonly{mountpoint="/"} == 0'';
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "{{ $labels.host }} root disk may fill in 24h";
              description = "Root filesystem on {{ $labels.host }} is projected to fill within 24 hours.";
            };
          }
          {
            alert = "DiskSpaceLow";
            expr = ''node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs",mountpoint!="/boot"} < 536870912 and (node_filesystem_avail_bytes / node_filesystem_size_bytes) < 0.05 and node_filesystem_readonly == 0'';
            for = "5m";
            labels.severity = "warning";
            annotations = {
              summary = "{{ $labels.host }}: {{ $labels.mountpoint }} < 512MiB";
              description = "Filesystem {{ $labels.mountpoint }} on {{ $labels.host }} has less than 512MiB and 5% free space.";
            };
          }
          {
            alert = "OOMKillDetected";
            expr = "increase(node_vmstat_oom_kill[5m]) > 0";
            for = "0m";
            labels.severity = "warning";
            annotations = {
              summary = "{{ $labels.host }} OOM kill";
              description = "Kernel OOM killer triggered on {{ $labels.host }}.";
            };
          }
          {
            alert = "ProbeFailed";
            expr = "probe_success == 0";
            for = "3m";
            labels.severity = "critical";
            annotations = {
              summary = "Probe failed: {{ $labels.instance }}";
              description = "Blackbox probe failed for {{ $labels.instance }} for > 3m.";
            };
          }
          {
            alert = "TlsCertExpiringSoon";
            expr = "probe_ssl_earliest_cert_expiry - time() < 7 * 86400";
            for = "1h";
            labels.severity = "warning";
            annotations = {
              summary = "TLS cert expiring soon: {{ $labels.instance }}";
              description = "TLS certificate for {{ $labels.instance }} expires in less than 7 days.";
            };
          }
        ];
      }
    ];
  };

  services.prometheus.alertmanager = {
    enable = true;
    listenAddress = lib.head (lib.splitString ":" cfg.alertmanagerAddr);
    port = lib.toInt (lib.last (lib.splitString ":" cfg.alertmanagerAddr));
    configuration = {
      route = {
        receiver = "ntfy";
        group_by = [
          "alertname"
          "host"
        ];
        group_wait = "30s";
        group_interval = "5m";
        repeat_interval = "4h";
        routes = [
          {
            matchers = [ ''group="untrusted"'' ];
            group_by = [
              "alertname"
              "group"
            ];
            group_wait = "1m";
            group_interval = "15m";
            repeat_interval = "24h";
          }
        ];
      };
      receivers = [
        {
          name = "ntfy";
          webhook_configs = [
            {
              url = "http://${ntfyHookAddr}/hook";
              send_resolved = true;
            }
          ];
        }
      ];
    };
  };

  services.prometheus.alertmanager-ntfy = {
    enable = true;
    extraConfigFiles = [ config.sops.templates."alertmanager-ntfy.yml".path ];
    settings = {
      http.addr = ntfyHookAddr;
      ntfy = {
        baseurl = ctx.alerts.url;
        notification.topic = ctx.alerts.topic;
      };
    };
  };

  infra.alerts.units = [
    "victoriametrics.service"
    "vmalert.service"
    "alertmanager.service"
    "alertmanager-ntfy.service"
    "caddy.service"
    "prometheus-blackbox-exporter.service"
  ];
}
