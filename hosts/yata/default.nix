{
  pkgs,
  ctx,
  ...
}:
{
  imports = [
    ./sing-box
    ./loadbalance
    ./caddy.nix
    ./dns.nix
    ../../modules/host/server.nix
    ../../modules/purpose/pooper-scooper
  ];

  cloud.server = {
    hostname = ctx.metadata.hostname;
    ssh-ports = ctx.ssh.ports;
    ssh-keys = ctx.ssh.auth-keys;
  };

  boot.kernel.sysctl = {
    # ip forwarding for wg peers
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  networking.hostName = "yata";
  networking.useDHCP = true;
  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "wg0" ];
    allowedUDPPorts = [ 51820 ];
  };
  services.tailscale.enable = true;

  services.pooper-scooper = {
    enable = true;
    doh_url = "https://223.5.5.5/resolve";
  };
  services.sing-box.enable = true;
  services.loadbalance.enable = true;

  # Pi specific hardware config
  boot.kernelPackages = pkgs.linuxPackages_latest;
  hardware.deviceTree.name = "allwinner/sun50i-h618-orangepi-zero3.dtb";
  boot.kernelParams = [ "console=ttyS0,115200n8" ];
  boot.loader.grub.enable = false;
  hardware.deviceTree.enable = true;
  boot.loader.generic-extlinux-compatible.enable = true;
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };

  system.stateVersion = "25.11";
}
