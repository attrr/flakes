# Charge to 80% and hold there: past it the charger stops charging but keeps
# running the phone from USB (pkgs/linux-qcom-sm8150's smbx patch), and it
# charges again from 75%, or on plug-in. By max17201's capacity, the gauge
# stock shows, as the only battery: it changes on every percent and as the
# charger does (whose charging enable is reset at probe); a timer, as stock's
# poll, in case one is missed. Every 2 weeks it charges in full once, for the
# gauge to learn the battery's capacity at a full charge, which holding at 80
# keeps from it, then runs the phone from the battery, though plugged in, back
# to 80
{ pkgs, ... }:
let
  limit = pkgs.writeShellScript "flame-charge-limit" ''
    capacity=$(cat /sys/class/power_supply/max1720x/capacity) || exit 0
    behaviour=/sys/class/power_supply/pm8150b-charger/charge_behaviour
    # the last full charge; counting from the first run
    full=/var/lib/flame-charge-limit/full
    mkdir -p "''${full%/*}"
    { [ "$capacity" -ge 100 ] || [ ! -e $full ]; } && touch $full
    # to charge in full, or test the charger, until reboot: touch it
    [ -e /run/flame-charge-limit-off ] && exit 0
    due=
    [ $(( $(date +%s) - $(stat -c %Y $full) )) -ge $((14 * 86400)) ] && due=1
    draining=
    case $(cat $behaviour) in *"[force-discharge]"*) draining=1 ;; esac
    # a plug-in charges to 80 whatever was left inhibited before it
    plugged=
    if [ "$POWER_SUPPLY_NAME" = pm8150b-charger ]; then
      online=/run/flame-charger-online
      [ "$POWER_SUPPLY_ONLINE" = 1 ] && [ "$(cat $online 2>/dev/null)" != 1 ] && plugged=1
      echo "$POWER_SUPPLY_ONLINE" > $online
    fi
    if [ -n "$due" ]; then
      to=auto
    elif [ "$capacity" -ge 100 ] || { [ -n "$draining" ] && [ "$capacity" -gt 80 ]; }; then
      to=force-discharge
    elif [ "$capacity" -ge 80 ]; then
      to=inhibit-charge
    elif [ "$capacity" -le 75 ] || [ -n "$plugged" ] || [ -n "$draining" ]; then
      to=auto
    else
      exit 0
    fi
    # writing it is a change of its own: only when it is one
    case $(cat $behaviour) in
      *"[$to]"*) ;;
      *) echo $to > $behaviour ;;
    esac
  '';
in
{
  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", KERNEL=="max1720x|pm8150b-charger", ACTION=="add|change", RUN+="${limit}"
  '';

  systemd.services.flame-charge-limit = {
    description = "Hold the battery at 80%";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = limit;
    };
  };
  systemd.timers.flame-charge-limit = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
    };
  };

  hardware.deviceTree.overlays = [
    {
      name = "flame-battery";
      filter = "sm8150-google-flame.dtb";
      dtsText = ''
        /dts-v1/;
        /plugin/;

        #include <dt-bindings/usb/pd.h>

        / {
          compatible = "google,floral-sm8150";
        };

        /* As stock: max17201 is the battery, its status the charger's, its
         * alert waking; pm8150b's gauge goes on in hardware, unread */
        &max17201 {
          power-supplies = <&pm8150b_charger>;
          wakeup-source;
        };

        &pm8150b_fg {
          status = "disabled";
        };

        /* The charger's input limit from the port's PD contract or Rp. Its
         * charging by stock's table (sm8150-floral-battery.dtsi), from
         * max17201's temperature, as the PMIC's JEITA can't see the battery's
         * thermistor: in tenths of a degree C, its rows; per row, a current
         * in hundredths of 2800mAh to each voltage; 0 doesn't charge past
         * the voltage before, nor at all under 0 or from 55 degrees */
        &pm8150b_charger {
          power-supplies = <&pm8150b_typec>;
          google,chg-temp-limits = <0 100 200 420 460 480 550>;
          google,chg-cv-limits = <4200000 4300000 4400000>;
          google,chg-cc-limits = <
             30  10   0
             50  30  30
            100  70  50
             80  50  50
             50  50   0
             30   0   0
          >;

          /* As stock's cooling devices (google_charger's charge currents,
           * then overheat_mitigation's no USB input at all), bound below */
          #cooling-cells = <2>;
          google,thermal-mitigation = <3700000 1850000 925000 500000 0>;
        };

        /* As stock's backup-charge zone (sm8150-flame-thermal.dtsi), on the
         * same sdm_therm */
        &{/thermal-zones/sdm-therm} {
          polling-delay-passive = <1000>;

          trips {
            charge_lv1: charge-lv1 {
              temperature = <39000>;
              hysteresis = <1000>;
              type = "passive";
            };
            charge_lv2: charge-lv2 {
              temperature = <41000>;
              hysteresis = <1000>;
              type = "passive";
            };
            charge_lv3: charge-lv3 {
              temperature = <43000>;
              hysteresis = <1000>;
              type = "passive";
            };
            charge_lv4: charge-lv4 {
              temperature = <48000>;
              hysteresis = <2000>;
              type = "passive";
            };
          };

          cooling-maps {
            charge-lv1 {
              trip = <&charge_lv1>;
              cooling-device = <&pm8150b_charger 1 1>;
            };
            charge-lv2 {
              trip = <&charge_lv2>;
              cooling-device = <&pm8150b_charger 2 2>;
            };
            charge-lv3 {
              trip = <&charge_lv3>;
              cooling-device = <&pm8150b_charger 3 3>;
            };
            charge-lv4 {
              trip = <&charge_lv4>;
              cooling-device = <&pm8150b_charger 4 4>;
            };
          };
        };

        /* As stock's usbc-therm-adc: no USB input from 55 degrees at the
         * port until under 45 */
        &{/thermal-zones/usbc-therm} {
          polling-delay-passive = <1000>;

          trips {
            usb_overheat: usb-overheat {
              temperature = <55000>;
              hysteresis = <10000>;
              type = "passive";
            };
          };

          cooling-maps {
            usb-overheat {
              trip = <&usb_overheat>;
              cooling-device = <&pm8150b_charger 5 5>;
            };
          };
        };

        /* tcpm wants sink-vdos-v1, the PD 2.0 identity, wherever sink-vdos is,
         * and fails the port without it. As stock, 9V at up to 2.2A, which
         * the table's 1C at 4.2V takes */
        &pm8150b_typec {
          connector {
            sink-vdos-v1 = <VDO_IDH(1, 1, IDH_PTYPE_PERIPH, 0, 0, 0, 0x18d1)
                            VDO_CERT(0x0)
                            VDO_PRODUCT(0x4ee1, 0x0)>;
          };
        };
      '';
    }
  ];
}
