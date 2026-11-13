# Phosh, as foo; its lock screen takes foo's password on a keypad, so
# ctx's ssh.hashed-password is a PIN here
{
  config,
  ctx,
  lib,
  pkgs,
  ...
}:
let
  # what programs.gdk-pixbuf.modulePackages builds, with JPEG XL
  pixbufLoaders = pkgs.gnome._gdkPixbufCacheBuilder_DO_NOT_USE {
    extraLoaders = [
      pkgs.librsvg
      pkgs.libjxl
    ];
  };
in
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
    # GNOME's wallpapers are JPEG XL, and phosh's wrapper pins librsvg's
    # loaders.cache, which has no JXL loader: the background comes out
    # black
    package = pkgs.phosh.overrideAttrs (old: {
      # after an idle suspend that ends without input, gsd-power stayed in
      # its sleep mode and never suspended again
      patches = old.patches or [ ] ++ [ ./patches/phosh-idle-reset-fires-active-watches.patch ];
      preFixup = old.preFixup + ''
        gappsWrapperArgs+=(--set GDK_PIXBUF_MODULE_FILE ${pixbufLoaders})
      '';
    });
  };
  # what the module leaves out: GNOME's apps, stevia's completion dictionary
  services.gnome.core-apps.enable = true;
  environment.systemPackages = [ pkgs.hunspellDicts.en_US ];
  programs.dconf.profiles.user.databases = [
    {
      settings = {
        # phosh shows stevia only with this set
        "org/gnome/desktop/a11y/applications".screen-keyboard-enabled = true;
        # gsd-power warns of its idle suspend in a critical notification,
        # which phosh woke the screen for: that reset the idle time, so it
        # never suspended
        "sm/puri/phosh/notifications".wakeup-screen-triggers = lib.gvariant.mkEmptyArray lib.gvariant.type.string;
      };
    }
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
