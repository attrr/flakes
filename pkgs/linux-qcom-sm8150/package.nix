{
  lib,
  buildLinux,
  linux_7_3,
  applyPatches,
  # NixOS overrides the kernel with kernelPatches, features and randstructSeed;
  # not formals, or callPackage fills kernelPatches with pkgs.kernelPatches
  ...
}@args:

# Mainline stable, nixpkgs' source (its point releases come with nixpkgs),
# with ./patches: nura's sm8150 tree for what flame needs of it (its DT,
# panel, touchscreen, SMB5 charger, sound card), and flame's own.
#
# Config: ./defconfig.aarch64, then nixpkgs' common config, what NixOS's
# modules need, on top; nothing else is built as a module. The defconfig is
# savedefconfig of the config it started as: pmaports'
# linux-postmarketos-qcom-sm8150 (7.0.0-r2, pmaports 80c363b5), through 7.3
# with SND_SOC_CS35L36=m, flame's speaker amps, and INPUT_CS40L25_VIBRA=m,
# its vibrator. A new driver is in only once it's added there
buildLinux {
  inherit (linux_7_3) version;
  # where the kernel's make finds defconfigs
  src = applyPatches {
    name = "linux-${linux_7_3.version}-flame-src";
    inherit (linux_7_3) src;
    postPatch = ''
      cp ${./defconfig.aarch64} arch/arm64/configs/flame_defconfig
    '';
  };
  modDirVersion = "${linux_7_3.version}-sm8150";
  defconfig = "flame_defconfig";
  autoModules = false;
  # the common config asks for much that this one has no base for (PCI
  # NICs, other SoCs); generic.nix only checks it on generic platforms
  ignoreConfigErrors = true;
  randstructSeed = args.randstructSeed or "";
  features = args.features or { };

  structuredExtraConfig = with lib.kernel; {
    # the PMIC's RTC is read-only and counts from 1970: setting the clock
    # from it took it back every boot. Until the RTC has an offset in a free
    # SDAM cell, as sc8280xp's; then they're back
    RTC_HCTOSYS = lib.mkForce no;
    RTC_SYSTOHC = lib.mkForce no;
  };

  # nixpkgs' own, then the series, format-patch of the branch it's kept on,
  # in its order
  kernelPatches =
    linux_7_3.kernelPatches
    ++ map
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
