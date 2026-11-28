{
  modulesPath,
  self,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    self.modules.nixos.server
  ];

  infra.disko = {
    layout = "btrfs-subvol";
    device = "/dev/vda";
  };
  system.stateVersion = "26.05";
  boot.loader.grub.enable = true;

  infra.server.lowend = true;
  zramSwap.memoryPercent = 50;

  infra.network.topology = "static";
  # Upstream RA provides the link-local IPv6 gateway (fe80::...) and advertises MTU 9214.
  systemd.network.networks."10-default" = {
    networkConfig.IPv6AcceptRA = true;
    ipv6AcceptRAConfig.UseMTU = false;
  };
}
