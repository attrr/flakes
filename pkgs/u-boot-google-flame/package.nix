{
  lib,
  buildUBoot,
  buildPackages,
  applyPatches,
  linux-qcom-sm8150,
  xxd,
}:

# Pixel 4 (flame), chainloaded by ABL: fastboot flash boot_a/boot_b u-boot.img
# It boots EFI from a GPT image written into the userdata partition, per
# https://wiki.nura.eco/wiki/Google_Pixel_4_(google-flame)
let
  # upstream has the SoC but not this board: its dts/upstream follows
  # mainline Linux, and flame's DT is only in the patched kernel tree, so
  # take it, and the dtsi it includes, from there
  kernelDts = "${
    applyPatches {
      name = "linux-qcom-sm8150-src";
      inherit (linux-qcom-sm8150) src;
      patches = map (p: p.patch) linux-qcom-sm8150.kernelPatches;
    }
  }/arch/arm64/boot/dts/qcom";
in
(buildUBoot {
  pname = "u-boot-google-flame";

  defconfig = "qcom_defconfig qcom-phone.config";
  extraConfig = ''
    CONFIG_DEFAULT_DEVICE_TREE="qcom/sm8150-google-flame"
    # ABL won't jump to a kernel linked below its own load address
    CONFIG_TEXT_BASE=0x80080000
    # preboot's userdata disk
    CONFIG_BLKMAP=y
    CONFIG_CMD_BLKMAP=y
    CONFIG_CMD_PART=y
    # volume up is a gpio-keys key on pm8150's GPIO 6 (volume down is
    # PON's RESIN): the menus' up, sd-boot's too through button-kbd
    CONFIG_BUTTON_GPIO=y
    # fdt_fixup, and setexpr's sub for it
    CONFIG_OF_ENV_SETUP=y
    CONFIG_REGEX=y
  '';

  # and with its pull-up: the PMIC GPIO driver dropped an input's pull and
  # had no bias-pull-up, so the active-low key floated
  extraPatches = [ ./0001-gpio-qcom_pmic-keep-an-input-s-pull-bias-pull-up.patch ];

  # (buildUBoot's own postPatch patches the scripts' shebangs)
  preConfigure = ''
    for f in sm8150-google-flame.dts sm8150.dtsi pm8150.dtsi pm8150b.dtsi pm8150l.dtsi; do
      install -m644 ${kernelDts}/$f dts/upstream/src/arm64/qcom/$f
    done

    # map userdata (on LUN 0) as a whole disk, so the GPT inside it is scanned
    substituteInPlace board/qualcomm/qcom-phone.env --replace-fail \
      'preboot=scsi scan' \
      'preboot=scsi scan; part start scsi 0 userdata userdata_start; part size scsi 0 userdata userdata_size; blkmap create root; blkmap map root 0 0x''${userdata_size} linear scsi 0 0x''${userdata_start}; run get_abl_mode'
    # fdt has no working tree until fdt addr; ABL's bootargs are in the control one
    substituteInPlace board/qualcomm/qcom-phone.env --replace-fail \
      'bootmenu_9=Dump bootargs=fdt print /chosen bootargs; pause' \
      'bootmenu_9=Dump bootargs=fdt addr ''${fdtcontroladdr}; fdt print /chosen bootargs; pause'

    # ABL's androidboot.mode, charger when it was powered on by a plug-in,
    # is passed on as /chosen's u-boot,abl-mode. fdt_fixup runs on every
    # devicetree booted, sd-boot's included (its EFI DT fixup)
    cat >> board/qualcomm/qcom-phone.env <<'EOF'
    get_abl_mode=fdt addr ''${fdtcontroladdr}; if fdt get value abl_mode /chosen bootargs && setexpr abl_mode sub "^.*androidboot.mode=" ""; then setexpr abl_mode sub " .*" ""; else setenv abl_mode; fi
    fdt_fixup=if test -n "''${abl_mode}"; then fdt set /chosen u-boot,abl-mode "''${abl_mode}"; fi
    EOF
  '';

  filesToInstall = [
    "u-boot-nodtb.bin"
    "dts/upstream/src/arm64/qcom/sm8150-google-flame.dtb"
  ];

  # ABL takes a gzipped kernel with the dtb appended. The capsule is the same
  # image for U-Boot's capsule-on-disk, which writes it over the active boot
  # slot; its GUID is the one U-Boot derives from the dtb (its ESRT entry)
  postInstall = ''
    dtb=dts/upstream/src/arm64/qcom/sm8150-google-flame.dtb
    gzip -9n -c u-boot-nodtb.bin | cat - $dtb > u-boot-dtb
    ${lib.getExe buildPackages.mkbootimg-osm0sis} --base 0 --kernel_offset 0x8000 --pagesize 4096 \
      --kernel u-boot-dtb -o $out/u-boot.img

    guid=$(${buildPackages.ubootTools}/bin/mkeficapsule guidgen $dtb UBOOT_BOOT_PARTITION \
      | sed -n 's/^UBOOT_BOOT_PARTITION: //p')
    ${buildPackages.ubootTools}/bin/mkeficapsule --index 1 --guid "$guid" \
      $out/u-boot.img $out/u-boot.capsule
  '';

  extraMeta.platforms = [ "aarch64-linux" ];
}).overrideAttrs (old: {
  # CONFIG_ENV_DEFAULT_ENV_TEXT_FILE is embedded with xxd
  nativeBuildInputs = old.nativeBuildInputs ++ [ xxd ];
})
