# yata itself, on any hardware: default.nix (the Pi) and default-vm.nix (cold standby)
{
  lib,
  ctx,
  self,
  ...
}:
{
  imports = [
    "${self}/modules/profiles/server"
    "${self}/modules/ctx/server.nix"
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

  services.tailscale = {
    enable = true;
    # Prevent direct WAN UDP hole-punching so overseas peers use DERP.
    openFirewall = lib.mkForce false;
  };

  networking.nftables = {
    enable = true;
    tables.ts-no-wan-udp = {
      family = "inet";
      content = ''
        chain output {
          type filter hook output priority filter; policy accept;
          oifname "e*" udp sport 41641 ip daddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } drop
          oifname "e*" udp sport 41641 ip6 daddr != { fc00::/7, fe80::/10 } drop
        }
      '';
    };
  };

  services.pooper-scooper = {
    enable = true;
    doh_url = "https://223.5.5.5/resolve";
  };
}
