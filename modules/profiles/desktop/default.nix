# GNOME workstation; ctx parts in modules/ctx/desktop.nix
{ pkgs, ... }:
let
  # as Fedora builds it: named "Terminal", with the generic icon
  ptyxis = pkgs.ptyxis.overrideAttrs (old: {
    mesonFlags = (old.mesonFlags or [ ]) ++ [ "-Dgeneric=terminal" ];
  });
in
{
  imports = [
    ../base
    ./boot.nix
    ./i18n.nix
  ];

  programs.git.package = pkgs.git;

  time.timeZone = "UTC";

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  # Ptyxis instead of Console, as in Fedora
  environment.gnome.excludePackages = [ pkgs.gnome-console ];
  environment.systemPackages = [ ptyxis ];
  xdg.terminal-exec = {
    enable = true;
    settings.GNOME = [ "org.gnome.Ptyxis.desktop" ];
  };

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

  # Fedora's org.gnome.Ptyxis.fedora.gschema.override
  services.desktopManager.gnome = {
    extraGSettingsOverridePackages = [ ptyxis ];
    extraGSettingsOverrides = ''
      [org.gnome.Ptyxis]
      enable-a11y=true
      inhibit-logout=false
      interface-style='dark'
    '';
  };

  networking.networkmanager.enable = true;
  services.printing.enable = true;
  programs.firefox.enable = true;

  users.users.foo.shell = pkgs.zsh;
  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
  };
}
