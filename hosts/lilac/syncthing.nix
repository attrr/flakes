{
  ctx,
  ...
}:
{
  services.syncthing = {
    enable = true;
    overrideDevices = false;
    overrideFolders = false;
    settings.options = {
      urAccepted = -1;
      globalAnnounceEnabled = false;
      localAnnounceEnabled = false;
      relaysEnabled = false;
      natEnabled = false;
      listenAddresses = [ "tcp://0.0.0.0:22000" ];
    };
  };

  services.caddy = {
    enable = true;
    virtualHosts."syncthing.${ctx.metadata.fdqn}" = {
      listenAddresses = ctx.tailscale.ips;
      useACMEHost = ctx.metadata.fdqn;
      extraConfig = ''
        reverse_proxy 127.0.0.1:8384 {
          header_up Host localhost:8384
        }
      '';
    };
  };

  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPorts = [
      80
      443
      22000
    ];
    allowedUDPPorts = [ 443 ];
  };
}
