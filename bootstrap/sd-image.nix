# sd-image.nix
{ pkgs, modulesPath, ... }:
{
  imports = [
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"
  ];

  nixpkgs.crossSystem.system = "aarch64-linux";
  sdImage = {
    compressImage = false;
    postBuildCommands = ''
      echo "Injecting U-Boot into image..."
      dd if=${pkgs.ubootOrangePiZero3}/u-boot-sunxi-with-spl.bin of=$img bs=1024 seek=8 conv=notrunc
    '';
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;
  hardware.deviceTree.name = "allwinner/sun50i-h618-orangepi-zero3.dtb";
  boot.kernelParams = [ "console=ttyS0,115200n8" ];

  system.stateVersion = "25.11";
  networking.useDHCP = true;
  services.openssh.enable = true;
  users.users.root.password = "nixos";
  services.openssh.settings.PermitRootLogin = "yes";
}
