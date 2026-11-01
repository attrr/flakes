# yata itself, on any hardware: default.nix (the Pi) and default-vm.nix (cold standby)
{
  lib,
  ctx,
  ...
}:
{
  imports = [
    ./services/sing-box
    ./services/loadbalance
    ./services/caddy.nix
    ./services/dns.nix
  ];

  system.stateVersion = "25.11";
  boot.supportedFilesystems.zfs = lib.mkForce false;

  networking.useNetworkd = true;
  systemd.network.networks."10-default" = {
    matchConfig.Name = "e*";
    address = ctx.network.ipv4.cidr;
    gateway = [ ctx.network.ipv4.gateway ];
    dns = [ ctx.network.ipv4.gateway ];

    networkConfig = {
      IPv6AcceptRA = true;
      IPv6PrivacyExtensions = "yes";
    };

    ipv6AcceptRAConfig = {
      UseAutonomousPrefix = true;
      UseGateway = true;
      Token = "prefixstable";
    };
  };

  boot.kernel.sysctl = {
    # ip forwarding for wg peers
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    # network
    "net.ipv4.tcp_timestamps" = 1;
    "net.ipv4.tcp_tw_reuse" = 1;
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
  };

  yata.sing-box.enable = true;
  yata.loadbalance.enable = true;

  services.tailscale.enable = true;
  services.pooper-scooper = {
    enable = true;
    doh_url = "https://223.5.5.5/resolve";
  };
}
