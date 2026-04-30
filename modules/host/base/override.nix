# put general purpose override for config here
{ lib, config, ... }:
{
  config = lib.mkMerge [
    {
      services.tailscale = lib.mkIf config.services.tailscale.enable {
        openFirewall = true;
        # disable firewall bypassing
        extraSetFlags = [ "--netfilter-mode=nodivert" ];
      };
    }
    (lib.mkIf (config.services.caddy.enable && config.services.tailscale.enable) {
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
    })
  ];
}
