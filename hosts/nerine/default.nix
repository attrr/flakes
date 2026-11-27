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
    espSize = "500M";
  };
  system.stateVersion = "25.11";
  boot.loader.grub.enable = true;

  infra.server.lowend = true;
  zramSwap.memoryPercent = 50;
  boot.serial.enable = true;

  infra.network.topology = "static";
}
