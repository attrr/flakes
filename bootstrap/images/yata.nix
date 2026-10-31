{
  pkgs,
  self,
  modulesPath,
  ...
}:
{
  imports = [
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"
    "${self}/modules/shim/sops.nix"
    "${self}/hosts/yata/hardware/arm.nix"
    "${self}/hosts/yata/profiles/base.nix"
  ];

  sdImage = {
    compressImage = false;
    postBuildCommands = ''
      echo "Injecting U-Boot into image..."
      dd if=${pkgs.ubootOrangePiZero3}/u-boot-sunxi-with-spl.bin of=$img bs=1024 seek=8 conv=notrunc
    '';
  };
}
