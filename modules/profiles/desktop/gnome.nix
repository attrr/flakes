{
  pkgs,
  ...
}:
let
  # named "Terminal", with the generic icon
  ptyxis = pkgs.ptyxis.overrideAttrs (old: {
    mesonFlags = (old.mesonFlags or [ ]) ++ [ "-Dgeneric=terminal" ];
  });
in
{
  # enable
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  services.gnome.core-developer-tools.enable = true;

  # replace gnome-console with ptyxis
  environment.gnome.excludePackages = [ pkgs.gnome-console ];
  environment.systemPackages = [ ptyxis ];
  services.desktopManager.gnome = {
    extraGSettingsOverridePackages = [ ptyxis ];
    extraGSettingsOverrides = ''
      [org.gnome.Ptyxis]
      enable-a11y=true
      inhibit-logout=false
      interface-style='dark'
    '';
  };

  xdg.terminal-exec = {
    enable = true;
    settings.GNOME = [ "org.gnome.Ptyxis.desktop" ];
  };
  xdg.mime.defaultApplications."inode/directory" = "org.gnome.Nautilus.desktop";

  # nautilus' own "Open in Terminal" only knows Console; custom is labelled Terminal
  programs.nautilus-open-any-terminal = {
    enable = true;
    terminal = "custom";
  };

  programs.dconf.profiles.user.databases = [
    {
      settings."com/github/stunkymonkey/nautilus-open-any-terminal" = {
        custom-local-command = "ptyxis --new-window -d %s";
        custom-remote-command = "ptyxis --new-window -- %s";
      };
      lockAll = true;
    }
  ];
}
