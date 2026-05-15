{ self, modulesPath, ctx, ... }:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (import "${self}/modules/disko/btrfs-subvol-deprecated.nix" {
      device = "/dev/vda";
      espSize = "500M";
    })
    "${self}/modules/host/lowend"
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.11";

  core.server = {
    inherit (ctx.metadata) hostname;
    ssh-ports = ctx.ssh.ports;
    ssh-keys = ctx.ssh.auth-keys;
    auto-resize = true;
    serial = true;
    disko.efi = true;
  };

  # networking
  networking.useNetworkd = true;
  systemd.network.networks."10-default" = {
    matchConfig.Name = "en*";
    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = true;
    };
    address = ctx.network.ipv6.cidr;
    routes = [
      {
        Gateway = ctx.network.ipv6.gateway;
        GatewayOnLink = true;
      }
    ];
  };
  services.tailscale.enable = true;
}
