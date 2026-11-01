{
  self,
  modulesPath,
  ctx,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (import "${self}/modules/disko/btrfs-subvol-deprecated.nix" {
      device = "/dev/vda";
      espSize = "500M";
    })
  ];
  system.stateVersion = "25.11";

  core.server = {
    auto-resize = true;
    serial = true;
    lowend.is = true;
  };

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = true;

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
