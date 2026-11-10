{
  lib,
  linuxManualConfig,
  linux_7_3,
  # NixOS overrides the kernel with kernelPatches, features and randstructSeed;
  # not formals, or callPackage fills kernelPatches with pkgs.kernelPatches
  ...
}@args:

# Mainline stable, nixpkgs' source (its point releases come with nixpkgs),
# with ./patches: nura's sm8150 tree for what flame needs of it (its DT,
# panel, touchscreen, SMB5 charger, sound card), and flame's own. The config
# started as pmaports' linux-postmarketos-qcom-sm8150 (7.0.0-r2, pmaports
# 80c363b5); on top of it: NFT_FIB_INET=m, for the NixOS firewall's reverse
# path filter, and NET_SCH_CAKE=m, TCP_CONG_BBR=m, for profiles/base's
# sysctls; SND_SOC_CS35L36=m, flame's speaker amps; INPUT_CS40L25_VIBRA=m,
# its vibrator
linuxManualConfig rec {
  inherit (linux_7_3) version src;
  modDirVersion = "${version}-sm8150";

  configfile = ./config.aarch64;
  randstructSeed = args.randstructSeed or "";
  # CONFIG_EFI_STUB, booted by systemd-boot
  features = {
    efiBootStub = true;
  }
  // args.features or { };

  # the series, format-patch of the branch it's kept on, in its order
  kernelPatches =
    map
      (file: {
        name = lib.removeSuffix ".patch" file;
        patch = ./patches + "/${file}";
      })
      (
        builtins.filter (lib.hasSuffix ".patch") (builtins.attrNames (builtins.readDir ./patches))
      )
    ++ args.kernelPatches or [ ];

  extraMeta.platforms = [ "aarch64-linux" ];
}
