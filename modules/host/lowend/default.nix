{
  lib,
  config,
  failoverModule,
  ...
}:
let
  cfg = config.core.server;
in
{
  imports = [
    ./disko.nix
    ../server.nix
    failoverModule
  ];

  options.core.server = {
    zram-percent = lib.mkOption {
      type = lib.types.int;
      default = 100;
    };
  };

  config = lib.mkMerge [
    {
      zramSwap.memoryPercent = cfg.zram-percent;
      core.server.auto-resize = true;

      services.failover = {
        enable = true;
        rescue.ssh.authorizedKeys = cfg.ssh-keys;
      };

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
  ];
}
