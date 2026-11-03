# GNOME workstation; ctx parts in modules/ctx/desktop.nix
{ pkgs, ... }:
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
  environment.systemPackages = [ pkgs.ptyxis ];
  xdg.terminal-exec = {
    enable = true;
    settings.GNOME = [ "org.gnome.Ptyxis.desktop" ];
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
