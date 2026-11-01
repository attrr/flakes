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

        # small disks: a new generation has to fit next to the running one
        # podman & co (~200M) only when something runs containers (oci-containers
        # brings podman along by itself)
        infra.server.containers = lib.mkDefault false;
        # nixpkgs source (~200M) for the registry/NIX_PATH; `nix shell nixpkgs#x`
        # falls back to the global registry
        nixpkgs.flake = {
          setFlakeRegistry = lib.mkDefault false;
          setNixPath = lib.mkDefault false;
        };
        # weekly: generations older than two weeks; and nix collects garbage by
        # itself when a copy/build gets the disk below min-free
        nix.gc = {
          automatic = lib.mkDefault true;
          dates = lib.mkDefault "weekly";
          options = lib.mkDefault "--delete-older-than 14d";
          persistent = true;
          randomizedDelaySec = "1h";
        };
        nix.settings = {
          min-free = lib.mkDefault (512 * 1024 * 1024);
          max-free = lib.mkDefault (1024 * 1024 * 1024);
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
    ]
  );
}
