{
  lib,
  config,
  pkgs,
  ...
}:
{
  boot.kernel.sysctl = {
    "net.core.default_qdisc" = lib.mkDefault "cake";
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.ipv4.tcp_slow_start_after_idle" = 0;
    "net.ipv4.tcp_mtu_probing" = 1;
  };

  networking.nftables = {
    enable = lib.mkDefault true;
    tables.scanner-blocklist = {
      family = "inet";
      content = ''
        include "${pkgs.scanner-blocklist-nft}"
      '';
    };
  };

  services.tailscale = lib.mkIf config.services.tailscale.enable {
    openFirewall = true;
    # disable firewall bypassing
    extraSetFlags = [ "--netfilter-mode=nodivert" ];
  };
}
