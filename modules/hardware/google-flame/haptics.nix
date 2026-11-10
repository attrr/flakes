# The vibrator: a CS40L25A on i2c15, through pkgs/linux-qcom-sm8150's
# cs40l25-vibra (force feedback). Its node and boost values are the stock
# dtbo's (sm8150-floral-haptics.dtsi); its firmware, stock's REMAP one, is
# in pkgs/firmware-google-flame
{ pkgs, ... }:
{
  # feedbackd knows its vibrators by their input device's name. Before
  # 73-seat-late, whose uaccess gives the session its ACL as the device
  # comes up: tagged later (as in extraRules' 99, or feedbackd's own 90),
  # only logind's next session change does, and the vibrator probes about
  # when phosh's session starts
  services.udev.packages = [
    (pkgs.writeTextDir "lib/udev/rules.d/70-flame-haptics.rules" ''
      SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT}=="1", SUBSYSTEMS=="input", ATTRS{name}=="cs40l25_vibra", TAG+="uaccess", ENV{FEEDBACKD_TYPE}="vibra"
    '')
  ];

  hardware.deviceTree.overlays = [
    {
      name = "flame-haptics";
      filter = "sm8150-google-flame.dtb";
      dtsText = ''
        /dts-v1/;
        /plugin/;

        #include <dt-bindings/gpio/gpio.h>
        #include <dt-bindings/interrupt-controller/irq.h>

        / {
          compatible = "google,floral-sm8150";
        };

        &tlmm {
          haptics_default: haptics-default-state {
            reset-pins {
              pins = "gpio152";
              function = "gpio";
              drive-strength = <2>;
              bias-disable;
            };
            irq-pins {
              pins = "gpio129";
              function = "gpio";
              bias-disable;
            };
          };
        };

        /* the 32 kHz clock out to the chip's GPIO2, its PLL's reference
         * outside the audio path */
        &pm8150_gpios {
          haptics_clk_default: haptics-clk-default-state {
            pins = "gpio3";
            function = "func1";
            bias-disable;
            power-source = <0>;
            output-low;
            input-disable;
          };
        };

        /* stock's 1 MHz (sm8150-floral-qup.dtsi), for the amps too: at
         * 100 kHz, cs_dsp's one write of the firmware's 18 KB program
         * outlasts geni's 1 s transfer timeout */
        &i2c15 {
          #address-cells = <1>;
          #size-cells = <0>;
          clock-frequency = <1000000>;

          haptics@43 {
            compatible = "cirrus,cs40l25a";
            reg = <0x43>;
            reset-gpios = <&tlmm 152 GPIO_ACTIVE_LOW>;
            interrupts-extended = <&tlmm 129 IRQ_TYPE_LEVEL_LOW>;
            pinctrl-0 = <&haptics_default>, <&haptics_clk_default>;
            pinctrl-names = "default";

            firmware-name = "cs40l25a.wmfw";
            cirrus,boost-peak-microamp = <4500000>;
            cirrus,boost-ctl-microvolt = <10000000>;
            cirrus,boost-ovp-microvolt = <11000000>;
          };
        };
      '';
    }
  ];
}
