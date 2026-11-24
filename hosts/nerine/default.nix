{
  modulesPath,
  self,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/profiles/headless.nix")
    (modulesPath + "/profiles/minimal.nix")
    self.modules.nixos.server
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

  infra.network.topology = "static";
}
