{ modulesPath, ctx, ... }:
let
  stable-network = {
    matchConfig.Name = "en*";
    address = ctx.network.ipv4.cidr ++ ctx.network.ipv6.cidr;
    gateway = [
      ctx.network.ipv4.gateway
      ctx.network.ipv6.gateway
    ];
    # since no dhcp
    networkConfig.DNS = [
      "1.1.1.1"
      "8.8.8.8"
      "2606:4700:4700::1111"
    ];
    # prevent boot hangs
    linkConfig.RequiredForOnline = "routable";
  };
in
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/profiles/headless.nix")
    (modulesPath + "/profiles/minimal.nix")
    ../../modules/host/lowend
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.11";

  cloud.server = {
    inherit (ctx.metadata) hostname;
    ssh-ports = ctx.ssh.ports;
    ssh-keys = ctx.ssh.auth-keys;
    auto-resize = true;
    serial = true;
    disko.efi = false;
    disko.device = "/dev/sda";
  };

  # networking
  networking.useNetworkd = true;
  services.failover.rescue.networkConfig.networks."10-default" = stable-network;
  systemd.network.networks."10-default" = stable-network;
}
