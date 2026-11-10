# The panel (an LG NT37280, command mode with DSC) and the GPU, both msm's
{
  # msm is built in and asks for the GPU's before / is mounted, as pmOS's
  # 30-gpu-firmware.files has it
  boot.initrd.extraFirmwarePaths = [
    "qcom/a630_gmu.bin"
    "qcom/a630_sqe.fw"
    "qcom/a640_gmu.bin"
    "qcom/sm8150/google/flame/a640_zap.mbn.zst"
  ];

  # the panel's vci, at stock's 3.0V: with the 1.704-3V range and no
  # voltage asked by the panel, the kernel drops it to 1.704V at boot,
  # under the panel ABL lit
  hardware.deviceTree.overlays = [
    {
      name = "flame-panel-vci";
      filter = "sm8150-google-flame.dtb";
      dtsText = ''
        /dts-v1/;
        /plugin/;

        / {
          compatible = "google,floral-sm8150";
        };

        &vreg_l4c_1p8 {
          regulator-min-microvolt = <3000000>;
          regulator-max-microvolt = <3000000>;
        };
      '';
    }
  ];
}
