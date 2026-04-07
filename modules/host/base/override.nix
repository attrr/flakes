# put general purpose override for config here
{ lib, config, ... }:
{
  services.tailscale = lib.mkIf config.services.tailscale.enable {
    openFirewall = true;
    # disable firewall bypassing
    extraSetFlags = [ "--netfilter-mode=nodivert" ];
  };
}
