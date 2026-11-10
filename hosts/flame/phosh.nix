# Phosh, as foo; its lock screen takes foo's password on a keypad, so
# ctx's ssh.hashed-password is a PIN here
{
  config,
  ctx,
  lib,
  pkgs,
  ...
}:
{
  assertions = [
    {
      assertion = config.users.users.foo.hashedPassword != null;
      message = "${ctx.metadata.hostname}: set ssh.hashed-password in ctx";
    }
  ];
  users.users.foo = {
    isNormalUser = true;
    hashedPassword = ctx.ssh.hashed-password;
  };

  services.xserver.desktopManager.phosh = {
    enable = true;
    user = "foo";
    group = "users";
    # the module pins DSI-1 to scale 2; the panel reports its real size
    # (62x130mm), so phoc can work the scale out itself
    phocConfig.outputs = { };
  };
  # what the module leaves out: GNOME's apps, stevia's completion dictionary
  services.gnome.core-apps.enable = true;
  environment.systemPackages = [ pkgs.hunspellDicts.en_US ];
  # phosh shows stevia only with this set
  programs.dconf.profiles.user.databases = [
    { settings."org/gnome/desktop/a11y/applications".screen-keyboard-enabled = true; }
  ];
  # gnome's core-os-services turns on ibus, whose GTK_IM_MODULE sends GTK's
  # input to it instead of text-input, so stevia never sees a focused field
  i18n.inputMethod.enable = false;
  # phosh's battery indicator asks it
  services.upower.enable = true;

  # phosh takes tty1 and conflicts with its getty; without a display manager,
  # getty.target wants that one, so every switch would start it and stop phosh
  systemd.targets.getty.wants = lib.mkForce [ ];
}
