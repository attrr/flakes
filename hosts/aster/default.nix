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
    device = "/dev/sda";
  };
  system.stateVersion = "26.05";
  boot.loader.grub.enable = true;

  zramSwap.memoryPercent = 50;

  infra.network.topology = "static";
}
