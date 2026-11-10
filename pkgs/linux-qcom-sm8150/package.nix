{
  lib,
  linuxManualConfig,
  fetchFromGitLab,
  # NixOS overrides the kernel with kernelPatches, features and randstructSeed;
  # not formals, or callPackage fills kernelPatches with pkgs.kernelPatches
  ...
}@args:

# pmaports' linux-postmarketos-qcom-sm8150 (7.0.0-r2, pmaports 80c363b5):
# its config and the one patch that isn't another device's dts. On top of the
# config: NFT_FIB_INET=m, for the NixOS firewall's reverse path filter, and
# NET_SCH_CAKE=m, TCP_CONG_BBR=m, for profiles/base's sysctls; SND_SOC_CS35L36=m,
# flame's speaker amps; INPUT_CS40L25_VIBRA=m, its vibrator
linuxManualConfig {
  version = "7.0.0";
  modDirVersion = "7.0.0-sm8150";

  src = fetchFromGitLab {
    domain = "gitlab.nura.eco";
    group = "soc";
    owner = "qualcomm-sm8150";
    repo = "linux";
    tag = "v7.0.0-sm8150";
    hash = "sha256-UNqp064EqWB05eywNYF/oZJVn7Ar3C7Vl8SymUa6qMI=";
  };

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
