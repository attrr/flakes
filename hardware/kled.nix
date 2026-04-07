{
  pkgs,
  ...
}:
let
  alsa-kled-ucm = pkgs.callPackage ../pkgs/alsa-ucm-conf-kled-full/default.nix { };
in
{
  # For Hibernation
  systemd.sleep.extraConfig = ''
    HibernateDelaySec=1m
    SuspendState=mem
  '';
  boot.kernelParams = [
    "mem_sleep_default=deep"
    "i915.enable_guc=3"
  ];

  services.power-profiles-daemon.enable = true;
  # suspend first then hibernate when closing the lid
  services.logind.settings.Login.LidSwitch = "suspend-then-hibernate";
  # hibernate on power button pressed
  services.logind.settings.Login.PowerKey = "hibernate";
  services.logind.settings.Login.PowerKeyLongPress = "poweroff";

  # For Audio
  boot.kernelModules = [
    "snd-sof-pci"
    "snd-sof-pci-intel-cnl"
    "snd-soc-sof-rt5682"
    "snd-soc-rt5682"
    "snd-soc-max98357a"
  ];
  boot.kernelPackages = pkgs.linuxPackages_latest;
  hardware.firmware = [
    pkgs.sof-firmware
  ];
  boot.extraModprobeConfig = ''
    options snd-intel-dspcfg dsp_driver=3
  '';

  # alsa
  environment.variables.ALSA_CONFIG_UCM2 = "${alsa-kled-ucm}/share/alsa/ucm2";
  environment.systemPackages = [ pkgs.alsa-utils ];

  # pipewire
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # wireplumber headroom
  environment.etc."wireplumber/wireplumber.conf.d/51-increase-headroom.conf".text = ''
    monitor.alsa.rules = [
      {
        matches = [
          {
            node.name = "~alsa_output.*"
          }
        ]
        actions = {
          update-props = {
            api.alsa.headroom = 2048
          }
        }
      }
    ]
  '';

  # Screen Rotation
  hardware.sensor.iio.enable = true;

  # Hardware Acceleration
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # For Broadwell (2014) or newer processors. LIBVA_DRIVER_NAME=iHD
      intel-vaapi-driver # For older processors. LIBVA_DRIVER_NAME=i965
      libvdpau-va-gl
    ];
  };
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
  };

  # Key Mapping
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings = {
        main = {
          leftmeta = "overload(overlay,leftmeta)";
        };
        overlay = {
          backspace = "delete";
          left = "home";
          right = "end";
          up = "pageup";
          down = "pagedown";

          # restore media key
          f1 = "back";
          f2 = "forward";
          f3 = "refresh";
          f4 = "f11";
          f5 = "scale";
          f6 = "brightnessdown";
          f7 = "brightnessup";
          f8 = "mute";
          f9 = "volumedown";
          f10 = "volumeup";
          f13 = "f12";

          # direction key
          h = "left";
          j = "down";
          k = "up";
          l = "right";
        };
      };
    };
  };
}
