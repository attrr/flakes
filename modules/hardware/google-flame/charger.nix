# Off-mode charging. Plugged in while off, ABL boots with androidboot.mode
# charger, which pkgs/u-boot-google-flame passes on as /chosen's
# u-boot,abl-mode; a generator then makes flame-charger.target the default:
# no phosh, the battery as text on tty1. As AOSP's charger
# (healthd_mode_charger): the screen goes off after 10 s, the power key
# shows it, held 2 s it boots on (to graphical.target), and 10 s unplugged
# it powers off. Unlike it, a press with the screen on turns it off; a port
# disabled for overheating shows, and keeps it on until it's unplugged
{ pkgs, ... }:
let
  generator = pkgs.writeShellScript "flame-charger-generator" ''
    read -r -d "" mode 2>/dev/null < /proc/device-tree/chosen/u-boot,abl-mode
    [ "$mode" = charger ] && ${pkgs.coreutils}/bin/ln -sf /etc/systemd/system/flame-charger.target "$2/default.target"
    exit 0
  '';

  charger = pkgs.writeShellScript "flame-charger" ''
    PATH=${pkgs.evtest}/bin:${pkgs.util-linux}/bin:${pkgs.kbd}/bin:/run/current-system/sw/bin
    key=/dev/input/by-path/platform-c440000.spmi-platform-c440000.spmi:pmic@0:pon@800:pwrkey-event
    bat=/sys/class/power_supply/max1720x
    # 1 while the port is disabled for overheating (battery.nix)
    overheat=/sys/bus/platform/devices/c440000.spmi:pmic@2:typec@1500/overheat
    # the charger's own online is its power path's, off while the charge
    # limit runs the phone from the battery; the port's is VBUS
    until [ -e $key ] && [ -e $bat/capacity ] && usb=$(echo /sys/class/power_supply/tcpm-source-psy-*/online) && [ -e $usb ]; do
      sleep 1
    done

    dmesg -D
    setfont ${pkgs.terminus_font}/share/consolefonts/ter-v32b.psf.gz
    printf '\e[?25l'
    # grabbed: logind, if anything starts it, would power off on a press
    coproc evtest --grab $key 2>/dev/null

    show() {
      read -r capacity < $bat/capacity
      read -r status < $bat/status
      printf '\e[H\e[J\n\n\n\n   %s%%\n   %s\n' "$capacity" "$status"
      [ "$hot" = 1 ] && printf '\n   USB port hot,\n   disabled:\n   unplug it\n'
    }
    on=1 off_at=$((SECONDS + 10)) pressed= was_on= unplugged= hot=
    show
    while :; do
      if read -r -t 1 line <&"''${COPROC[0]}"; then
        case $line in
          *KEY_POWER*", value 1")
            pressed=$SECONDS
            was_on=$on
            off_at=$((SECONDS + 10))
            [ -z "$on" ] && on=1 && setterm --blank poke
            ;;
          # a press (not held to boot) turns it off again
          *KEY_POWER*", value 0")
            pressed=
            [ -n "$was_on" ] && off_at=0
            ;;
        esac
      fi
      if [ -n "$pressed" ] && [ $((SECONDS - pressed)) -ge 2 ]; then
        printf '\e[H\e[J'
        dmesg -E
        exec systemctl isolate --no-block graphical.target
      fi
      # a hot port shows, and keeps the phone on until it's unplugged
      was_hot=$hot
      read -r hot < $overheat || hot=
      if [ "$hot" = 1 ] && [ "$was_hot" != 1 ]; then
        off_at=$((SECONDS + 10))
        [ -z "$on" ] && on=1 && setterm --blank poke
      fi
      read -r online < $usb
      if [ "$online" = 1 ] || [ "$hot" = 1 ]; then
        unplugged=
      elif [ -z "$unplugged" ]; then
        unplugged=$SECONDS
      elif [ $((SECONDS - unplugged)) -ge 10 ]; then
        exec systemctl poweroff
      fi
      if [ -n "$on" ]; then
        show
        if [ $SECONDS -ge $off_at ]; then
          on=
          setterm --blank force
        fi
      fi
    done
  '';
in
{
  systemd.generators.flame-charger = generator;

  systemd.targets.flame-charger = {
    description = "Off-mode charging";
    requires = [ "basic.target" ];
    after = [ "basic.target" ];
    wants = [ "flame-charger.service" ];
    unitConfig.AllowIsolate = true;
  };

  systemd.services.flame-charger = {
    description = "Off-mode charging screen";
    after = [ "systemd-vconsole-setup.service" ];
    serviceConfig = {
      ExecStart = charger;
      StandardInput = "tty";
      StandardOutput = "tty";
      StandardError = "journal";
      TTYPath = "/dev/tty1";
      TTYReset = true;
    };
    environment.TERM = "linux";
  };
}
