# The speakers: two CS35L36 amps on i2c15 (Top, the earpiece end, and
# Bottom), fed by the ADSP over tertiary TDM. Their nodes and boost values
# are the stock dtbo's; the TDM is its 6.144 MHz short-sync one, which
# pkgs/linux-qcom-sm8150's tertiary TDM patch sets up
{ pkgs, ... }:
let
  # alsa-ucm-conf has no sm8150 card, and alsa-lib links its copy in at
  # build time, so PipeWire gets it plus this card's through the environment
  ucm = pkgs.runCommand "alsa-ucm-conf-flame" { } ''
    cp -rs --no-preserve=mode ${pkgs.alsa-ucm-conf}/share/alsa/ucm2 $out
    mkdir -p $out/conf.d/sm8150 $out/Google/flame
    cat > $out/conf.d/sm8150/google-GooglePixel4.conf <<'EOF'
    Syntax 3

    SectionUseCase."HiFi" {
    	File "/Google/flame/HiFi.conf"
    	Comment "HiFi quality Music."
    }
    EOF
    cat > $out/Google/flame/HiFi.conf <<'EOF'
    SectionVerb {
    	# stock's dt amp settings, which mainline has as controls:
    	# amp-gain-zc, ldm-mode-select (the noise gate), pdm-ldm-enter/exit
    	EnableSequence [
    		cset "name='Top Amp Gain Zero-Cross Switch' 1"
    		cset "name='Bottom Amp Gain Zero-Cross Switch' 1"
    		cset "name='Top LDM Select Switch' 1"
    		cset "name='Bottom LDM Select Switch' 1"
    		cset "name='Top PDM LDM Enter Ramp Switch' 1"
    		cset "name='Bottom PDM LDM Enter Ramp Switch' 1"
    		cset "name='Top PDM LDM Exit Ramp Switch' 1"
    		cset "name='Bottom PDM LDM Exit Ramp Switch' 1"
    		cset "name='TERT_TDM_RX_0 Audio Mixer MultiMedia1' 1"
    	]
    	DisableSequence [
    		cset "name='TERT_TDM_RX_0 Audio Mixer MultiMedia1' 0"
    	]
    	Value {
    		TQ "HiFi"
    	}
    }

    # Top (the earpiece end) left, Bottom right, at stock's media gain (its
    # mixer_paths' "speaker"). Without stock's speaker protection, the amps
    # stay 6 dB under full scale: Digital PCM Volume is 0.125 dB a step from
    # -102 dB, so 816 is 0 dB and 768 is -6 dB
    SectionDevice."Speaker" {
    	Comment "Speakers"
    	ConflictingDevice [
    		"Earpiece"
    	]

    	EnableSequence [
    		cset "name='Top Channel Mux' RX1"
    		cset "name='Bottom Channel Mux' RX2"
    		cset "name='Top Analog PCM Volume' 17"
    		cset "name='Bottom Analog PCM Volume' 17"
    		cset "name='Top Digital PCM Volume' 768"
    		cset "name='Bottom Digital PCM Volume' 768"
    		cset "name='Top PCM Soft Ramp' 4ms"
    		cset "name='Bottom PCM Soft Ramp' 4ms"
    		cset "name='Top BOOST Enable Switch' 1"
    		cset "name='Bottom BOOST Enable Switch' 1"
    		cset "name='Top AMP Enable Switch' 1"
    		cset "name='Bottom AMP Enable Switch' 1"
    	]
    	DisableSequence [
    		cset "name='Top AMP Enable Switch' 0"
    		cset "name='Bottom AMP Enable Switch' 0"
    		cset "name='Top BOOST Enable Switch' 0"
    		cset "name='Bottom BOOST Enable Switch' 0"
    	]

    	Value {
    		PlaybackPriority 100
    		PlaybackPCM "hw:''${CardId},0"
    		PlaybackChannels 2
    	}
    }

    # the top amp alone at its lowest gain, as stock's "handset" path
    SectionDevice."Earpiece" {
    	Comment "Earpiece"
    	ConflictingDevice [
    		"Speaker"
    	]

    	EnableSequence [
    		cset "name='Top Channel Mux' RX1"
    		cset "name='Top Analog PCM Volume' 0"
    		cset "name='Top Digital PCM Volume' 768"
    		cset "name='Top PCM Soft Ramp' 4ms"
    		cset "name='Top BOOST Enable Switch' 1"
    		cset "name='Top AMP Enable Switch' 1"
    	]
    	DisableSequence [
    		cset "name='Top AMP Enable Switch' 0"
    		cset "name='Top BOOST Enable Switch' 0"
    	]

    	Value {
    		PlaybackPriority 50
    		PlaybackPCM "hw:''${CardId},0"
    		PlaybackChannels 2
    	}
    }
    EOF
  '';
in
{
  systemd.user.services.pipewire.environment.ALSA_CONFIG_UCM2 = "${ucm}";
  systemd.user.services.wireplumber.environment.ALSA_CONFIG_UCM2 = "${ucm}";
  environment.variables.ALSA_CONFIG_UCM2 = "${ucm}";
  # PipeWire picks S24_LE, which the DSP takes as left-aligned in its 32
  # bits, about 48 dB down; S16_LE plays at full scale
  services.pipewire.wireplumber.extraConfig."51-flame-speakers" = {
    "monitor.alsa.rules" = [
      {
        matches = [ { "node.name" = "~alsa_output.platform-sound.*"; } ];
        actions.update-props."audio.format" = "S16LE";
      }
    ];
  };

  hardware.deviceTree.overlays = [
    {
      name = "flame-speakers";
      filter = "sm8150-google-flame.dtb";
      dtsText = ''
        /dts-v1/;
        /plugin/;

        #include <dt-bindings/gpio/gpio.h>
        #include <dt-bindings/interrupt-controller/irq.h>
        #include <dt-bindings/sound/qcom,q6afe.h>
        #include <dt-bindings/sound/qcom,q6asm.h>

        / {
          compatible = "google,floral-sm8150";
        };

        &tlmm {
          /* gpio132 is the bottom amp's irq, so of ter_mi2s's
           * pins, the ones stock muxes: the clocks and both data lines */
          tert_tdm_active: tert-tdm-active-state {
            pins = "gpio131", "gpio133", "gpio134", "gpio135";
            function = "ter_mi2s";
            drive-strength = <8>;
            bias-disable;
          };

          amp_top_default: amp-top-default-state {
            reset-pins {
              pins = "gpio35";
              function = "gpio";
              drive-strength = <2>;
              bias-disable;
            };
            irq-pins {
              pins = "gpio36";
              function = "gpio";
              drive-strength = <2>;
              bias-pull-up;
            };
          };

          amp_bottom_default: amp-bottom-default-state {
            reset-pins {
              pins = "gpio148";
              function = "gpio";
              drive-strength = <2>;
              bias-disable;
            };
            irq-pins {
              pins = "gpio132";
              function = "gpio";
              drive-strength = <2>;
              bias-pull-up;
            };
          };
        };

        &i2c15 {
          #address-cells = <1>;
          #size-cells = <0>;

          amp_bottom: amplifier@40 {
            compatible = "cirrus,cs35l36";
            reg = <0x40>;
            #sound-dai-cells = <0>;
            sound-name-prefix = "Bottom";
            reset-gpios = <&tlmm 148 GPIO_ACTIVE_HIGH>;
            interrupts-extended = <&tlmm 132 IRQ_TYPE_LEVEL_LOW>;
            pinctrl-0 = <&amp_bottom_default>;
            pinctrl-names = "default";

            cirrus,boost-ind-nanohenry = <1000>;
            cirrus,boost-ctl-select = <1>;
            cirrus,boost-ctl-millivolt = <10000>;
            cirrus,boost-peak-milliamp = <3700>;
            cirrus,temp-warn-threshold = <1>;
            cirrus,multi-amp-mode;
            cirrus,irq-drive-select = <0>;
            cirrus,irq-gpio-select = <0>;
          };

          amp_top: amplifier@41 {
            compatible = "cirrus,cs35l36";
            reg = <0x41>;
            #sound-dai-cells = <0>;
            sound-name-prefix = "Top";
            reset-gpios = <&tlmm 35 GPIO_ACTIVE_HIGH>;
            interrupts-extended = <&tlmm 36 IRQ_TYPE_LEVEL_LOW>;
            pinctrl-0 = <&amp_top_default>;
            pinctrl-names = "default";

            cirrus,boost-ind-nanohenry = <1000>;
            cirrus,boost-ctl-select = <1>;
            cirrus,boost-ctl-millivolt = <10000>;
            cirrus,boost-peak-milliamp = <3700>;
            cirrus,temp-warn-threshold = <1>;
            cirrus,multi-amp-mode;
            cirrus,irq-drive-select = <0>;
            cirrus,irq-gpio-select = <0>;
          };
        };

        &q6afedai {
          dai@38 {
            reg = <TERTIARY_TDM_RX_0>;
            qcom,tdm-sync-mode = <0>;
            qcom,tdm-sync-src = <1>;
            qcom,tdm-data-out = <0>;
            qcom,tdm-invert-sync = <0>;
            qcom,tdm-data-delay = <1>;
            qcom,tdm-data-align = <0>;
          };
        };

        /* reversed too: q6asm-dai numbers its DAIs in child order, and the
         * links pick them by that index */
        &q6asmdai {
          dai@1 {
            reg = <1>;
          };
          dai@0 {
            reg = <0>;
          };
        };

        &sound {
          compatible = "qcom,sm8150-sndcard";
          model = "Google Pixel 4";
          pinctrl-0 = <&tert_tdm_active>;
          pinctrl-names = "default";

          /* an overlay's new subnodes land in reverse, and the card probes
           * its links' components in order: the front ends' q6asm-dai has
           * to come before the routing that refers to its widgets */
          speaker-dai-link {
            link-name = "Speaker Playback";
            cpu {
              sound-dai = <&q6afedai TERTIARY_TDM_RX_0>;
            };
            platform {
              sound-dai = <&q6routing>;
            };
            codec {
              sound-dai = <&amp_top>, <&amp_bottom>;
            };
          };

          mm2-dai-link {
            link-name = "MultiMedia2";
            cpu {
              sound-dai = <&q6asmdai MSM_FRONTEND_DAI_MULTIMEDIA2>;
            };
          };

          mm1-dai-link {
            link-name = "MultiMedia1";
            cpu {
              sound-dai = <&q6asmdai MSM_FRONTEND_DAI_MULTIMEDIA1>;
            };
          };
        };
      '';
    }
  ];
}
