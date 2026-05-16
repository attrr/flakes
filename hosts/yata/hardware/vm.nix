{ self, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/profiles/minimal.nix")
    (import "${self}/modules/disko/ext4-plain.nix" {
      device = "/dev/sda";
      imageSize = "10G";
    })
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  boot.loader.grub.enable = true;
}
