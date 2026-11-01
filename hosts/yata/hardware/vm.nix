{ modulesPath, ... }:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/profiles/minimal.nix")
  ];

  infra.disko = {
    layout = "ext4-plain";
    device = "/dev/sda";
    imageSize = "10G";
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  boot.loader.grub.enable = true;
}
