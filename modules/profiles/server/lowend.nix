{
  lib,
  config,
  ...
}:
let
  cfg = config.infra.server.lowend;
in
{

  options.infra.server.lowend = {
    enable = lib.mkEnableOption "toggle lowend";
    zram-percent = lib.mkOption {
      type = lib.types.int;
      default = 100;
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        zramSwap.memoryPercent = cfg.zram-percent;
        infra.server.auto-resize = true;
      }
      (lib.mkIf config.services.tailscale.enable {
        systemd.services.tailscaled = {
          environment = {
            GOMEMLIMIT = "80MiB";
            GOGC = "50";
          };

          serviceConfig = {
            MemoryMax = "150M";
            OOMPolicy = "continue";
          };
        };

        systemd.timers.tailscaled-restart = {
          description = "Daily restart timer for tailscaled";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = true;
          };
        };

        systemd.services.tailscaled-restart = {
          description = "Restart tailscaled service";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${config.systemd.package}/bin/systemctl restart tailscaled.service";
          };
        };
      })
    ]
  );
}
