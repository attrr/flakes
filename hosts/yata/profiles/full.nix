{ ... }:
{
  imports = [
    ./base.nix
    ../services/sing-box
    ../services/loadbalance
    ../services/caddy.nix
    ../services/dns.nix
  ];

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

  local.sing-box.enable = true;
  local.loadbalance.enable = true;

  services.tailscale.enable = true;
  services.pooper-scooper = {
    enable = true;
    doh_url = "https://223.5.5.5/resolve";
  };
}
