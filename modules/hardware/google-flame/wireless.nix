# The modem, and Wi-Fi and Bluetooth (a WCN3990), which go through it or
# beside it
{ config, pkgs, ... }:
{
  # The modem's userspace, as pmOS's soc-qcom-modem: rmtfs serves it the EFS
  # partitions (modemst1/2, fsg, fsc) and boots it, tqftpserv serves it
  # wlanmdsp.mbn from the firmware path, which Wi-Fi runs on
  systemd.services.rmtfs = {
    description = "Qualcomm remotefs service";
    wantedBy = [ "multi-user.target" ];
    before = [ "NetworkManager.service" ];
    serviceConfig = {
      # -r: never write the EFS back to the partitions
      ExecStart = "${pkgs.rmtfs}/bin/rmtfs -r -P -s";
      Restart = "always";
      RestartSec = 1;
    };
  };

  systemd.services.tqftpserv = {
    description = "QRTR TFTP service";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.tqftpserv}/bin/tqftpserv";
      Restart = "always";
    };
  };

  # Wi-Fi stays associated through suspend, as on stock. Without WoWLAN,
  # mac80211's suspend deauths and powers the WCN3990 down, and with the
  # modem's rail unvoted (mss at 0) that kills the modem: its watchdog
  # fires a second after. 12: disconnect | magic
  networking.networkmanager.connectionConfig."wifi.wake-on-wlan" = 12;

  # bluetooth's uart13 has only a sleep pinctrl state, so its pins stay
  # GPIOs and the WCN3990 never answers. The pulls are trogdor's (sc7180,
  # also a WCN3990 on a QUP uart)
  hardware.deviceTree.overlays = [
    {
      name = "flame-bluetooth";
      filter = "sm8150-google-flame.dtb";
      dtsText = ''
        /dts-v1/;
        /plugin/;

        / {
          compatible = "google,floral-sm8150";
        };

        &tlmm {
          qup_uart13_default: qup-uart13-default-state {
            cts-pins {
              pins = "gpio43";
              function = "qup13";
              bias-pull-down;
            };
            rts-pins {
              pins = "gpio44";
              function = "qup13";
              drive-strength = <2>;
              bias-disable;
            };
            tx-pins {
              pins = "gpio45";
              function = "qup13";
              drive-strength = <2>;
              bias-disable;
            };
            rx-pins {
              pins = "gpio46";
              function = "qup13";
              bias-pull-up;
            };
          };
        };

        /*
         * sm8150's QUP nodes have no interconnects, so with the NoCs
         * synced only the QUP0 BCM's active-only keepalive holds the
         * serial engines' clock: once the CPUs collapse, the sleep set
         * stops uart13 under the WCN3990's in-band sleep, and the wake
         * acks are lost. Stock votes QUP_2 in both sets while an engine
         * is on. qcom,sm8150.h: MASTER_QUP_2 4, SLAVE_QUP_2 31,
         * MASTER_AMPSS_M0 0
         */
        &uart13 {
          pinctrl-0 = <&qup_uart13_default>;
          interconnects = <&aggre2_noc 4 0 &config_noc 31 0>,
                          <&gem_noc 0 0 &config_noc 31 0>;
          interconnect-names = "qup-core", "qup-config";
        };
      '';
    }
  ];

  # the WCN3990 only has its NVM's placeholder address, so hci0 comes up
  # unconfigured. The phone's own is bt_addr in the factory data, a dtb
  # 36 bytes into cdt; read here, so it stays out of the repo
  systemd.services.bluetooth-address = {
    description = "Factory Bluetooth address";
    wantedBy = [ "sys-subsystem-bluetooth-devices-hci0.device" ];
    bindsTo = [ "sys-subsystem-bluetooth-devices-hci0.device" ];
    after = [ "sys-subsystem-bluetooth-devices-hci0.device" ];
    path = [
      pkgs.dtc
      config.hardware.bluetooth.package
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "bluetooth-address";
    };
    # hci0 is there before its firmware is, and mgmt only has its index
    # after: a second or so
    script = ''
      dtb=$RUNTIME_DIRECTORY/cdt.dtb
      tail -c +37 /dev/disk/by-partlabel/cdt | head -c 4096 > "$dtb"
      addr=$(fdtget -ts "$dtb" / bt_addr)
      rm "$dtb"
      for _ in $(seq 20); do
        btmgmt --index 0 public-addr "$addr" && exit 0
        sleep 0.5
      done
      exit 1
    '';
  };
}
