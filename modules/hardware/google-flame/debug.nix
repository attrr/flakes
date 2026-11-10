# Bring-up debugging, imported beside the profile when wanted. ramoops (./boot.nix
# moves it out of ABL's carveout) keeps the console, the last panic and
# /dev/pmsg0 through any reset, power-key ones included; systemd-pstore moves
# them to /var/lib/systemd/pstore on the next boot
{
  # what reaches the console, so ramoops' copy of it: up to info
  boot.consoleLogLevel = 7;
  boot.kernelParams = [
    # userspace's /dev/kmsg writes too, unthrottled
    "printk.devkmsg=on"
    # a panic reboots, with its log in ramoops
    "panic=10"
    # a hang becomes a panic where it can: a CPU stuck with preemption off
    # (softlockup), or with interrupts off (hardlockup, seen by another CPU)
    "softlockup_panic=1"
    # and a task stuck in D for 120 s: storage gone, say, while PID 1 still
    # pets the watchdog
    "hung_task_panic=1"
  ];
  # systemd-pstore overwrites last boot's console-ramoops-0 with this one's,
  # so a boot that hung is gone two boots later: keep each boot's, numbered
  # (the clock isn't set this early), the last 30
  systemd.services.pstore-keep = {
    after = [ "systemd-pstore.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      k=/var/lib/pstore-keep
      mkdir -p $k
      n=$(ls $k | grep -E '^[0-9]{4}-' | tail -1 | cut -c1-4)
      d=$k/$(printf %04d $((10#''${n:-0} + 1)))-$(head -c8 /proc/sys/kernel/random/boot_id)
      mkdir $d
      cp -a /var/lib/systemd/pstore/. $d/
      ls -d $k/* | head -n -30 | xargs -r rm -rf
    '';
  };

  boot.kernel.sysctl = {
    "kernel.sysrq" = 1;
    "kernel.panic" = 10;
  };

  # and one stuck so that no CPU runs the lockup detectors, while one still
  # takes interrupts: qcom_wdt's bark is a pretimeout, its default governor
  # panics. Its bite, without that, freezes the SoC rather than resetting it
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "30s";
    RuntimeWatchdogPreSec = "10s";
  };

  # a boot entry for a boot that hangs: everything to the console, and
  # each initcall, so its last lines say where
  specialisation.debug.configuration.boot.kernelParams = [
    "ignore_loglevel"
    "initcall_debug"
    # msm's DBG(): its clock rates, PLL and DSI state
    "drm.debug=0x2"
  ];
  # and one without the display, to come back up, ssh-able, with that
  # boot's ramoops, after a warm reset that the display doesn't
  specialisation.nodisplay.configuration.boot.kernelParams = [ "msm.modeset=0" ];
}
