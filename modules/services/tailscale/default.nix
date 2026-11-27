{
  module.nixos =
    { config, lib, ... }:
    let
      cfg = config.services.tailscale;
    in
    {
      options.services.tailscale = {
        blockDirectWan = lib.mkEnableOption "block direct WAN UDP hole-punching so non-LAN peers use DERP";
        lowMemory = lib.mkEnableOption "cap tailscaled memory usage with a daily restart";
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            services.tailscale = {
              openFirewall = lib.mkDefault (!cfg.blockDirectWan);
              # disable firewall bypassing
              extraSetFlags = [ "--netfilter-mode=nodivert" ];
            };
          }
          (lib.mkIf cfg.blockDirectWan {
            networking.nftables = {
              enable = lib.mkDefault true;
              tables.ts-no-wan-udp = {
                family = "inet";
                content = ''
                  chain output {
                    type filter hook output priority filter; policy accept;
                    oifname != { "lo", "${cfg.interfaceName}" } udp sport ${toString cfg.port} ip daddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } drop
                    oifname != { "lo", "${cfg.interfaceName}" } udp sport ${toString cfg.port} ip6 daddr != { fc00::/7, fe80::/10 } drop
                  }
                '';
              };
            };
          })
          (lib.mkIf cfg.lowMemory {
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
    };

  ctx.nixos =
    { config, ctx, ... }:
    {
      # untrusted machines stay off the tailnet
      assertions = [
        {
          assertion = ctx.metadata.group != "untrusted" || !config.services.tailscale.enable;
          message = "${ctx.metadata.hostname} is in group untrusted, it must not run tailscale";
        }
      ];
    };
}
