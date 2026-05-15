{
  self,
  modulesPath,
  ctx,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/profiles/headless.nix")
    (modulesPath + "/profiles/minimal.nix")
    (import "${self}/modules/disko/btrfs-subvol-deprecated.nix" {
      device = "/dev/vda";
      espSize = "500M";
    })
    "${self}/modules/host/lowend"
    "${self}/modules/ctx/proxy.nix"
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.11";
  boot.loader.grub = true;

  core.server = {
    inherit (ctx.metadata) hostname;
    ssh-ports = ctx.ssh.ports;
    ssh-keys = ctx.ssh.auth-keys;
    auto-resize = true;
    serial = true;
    zram-percent = 50;
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
