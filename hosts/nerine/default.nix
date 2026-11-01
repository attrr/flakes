{
  modulesPath,
  ctx,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/profiles/headless.nix")
    (modulesPath + "/profiles/minimal.nix")
    ./tgu.nix
  ];

  infra.disko = {
    layout = "btrfs-subvol";
    device = "/dev/vda";
    espSize = "500M";
  };
  system.stateVersion = "25.11";
  boot.loader.grub.enable = true;

  infra.server = {
    auto-resize = true;
    serial = true;
    lowend = {
      enable = true;
      zram-percent = 50;
    };
  };

  # networking
  networking.useNetworkd = true;
  systemd.network.networks."10-default" = {
    matchConfig.Name = "e*";
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
  };
}
