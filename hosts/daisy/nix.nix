{
  config,
  ctx,
  lib,
  ...
}:
let
  harmonia = ctx.services.harmonia;
in
{
  boot.binfmt.emulatedSystems = [ "x86_64-linux" ];

  services.harmonia.cache = {
    enable = true;
    signKeyPaths = [ ctx.vars.harmonia-key.secret.path ];
    settings.bind = "127.0.0.1:${toString harmonia.port}";
  };

  infra.acme.certs.${harmonia.domain} = { };

  services.caddy = {
    enable = true;
    virtualHosts.${harmonia.domain} = {
      listenAddresses = ctx.tailscale.ips;
      useACMEHost = harmonia.domain;
      extraConfig = ''
        reverse_proxy 127.0.0.1:${toString harmonia.port}
      '';
    };
  };

  networking.firewall.interfaces.tailscale0 = lib.mkIf config.services.tailscale.enable {
    allowedTCPPorts = [
      80
      443
    ];
    allowedUDPPorts = [ 443 ];
  };

  nix.sshServe = {
    enable = true;
    protocol = "ssh-ng";
    trusted = true;
    keys = ctx.services.nix-builder.authorized-keys;
  };

  services.openssh.settings.AllowUsers = [ "nix-ssh" ];

  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";
  systemd.services.nix-daemon.serviceConfig = {
    MemoryHigh = "8G";
    MemoryMax = "9G";
  };
}
