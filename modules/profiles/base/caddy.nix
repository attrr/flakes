{ lib, config, ... }:
{
  # caddy bound to (tailscale) addresses fails while they don't exist yet;
  # one listening everywhere doesn't need to wait
  config =
    lib.mkIf
      (
        config.services.caddy.enable
        && config.services.tailscale.enable
        && lib.any (v: v.listenAddresses != [ ]) (lib.attrValues config.services.caddy.virtualHosts)
      )
      {
        systemd.services.caddy = {
          after = [
            "tailscaled.service"
            "sys-devices-virtual-net-tailscale0.device"
          ];
          requires = [
            "tailscaled.service"
            "sys-devices-virtual-net-tailscale0.device"
          ];
          # FIXME: remove this when caddy support listen on device or freebind
          serviceConfig = {
            RestartPreventExitStatus = lib.mkForce "";
            StartLimitBurst = lib.mkForce 5;
            StartLimitIntervalSec = lib.mkForce 60;
          };
        };
      };
}
