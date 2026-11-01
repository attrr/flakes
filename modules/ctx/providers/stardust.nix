{
  modulesPath,
  ctx,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  infra.disko = {
    layout = "btrfs-subvol-deprecated";
    device = "/dev/vda";
    espSize = "500M";
  };
  system.stateVersion = "25.11";

  infra.server = {
    auto-resize = true;
    serial = true;
    lowend.enable = true;
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
