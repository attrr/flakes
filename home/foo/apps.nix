{
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkMerge [
    {
      home.packages = with pkgs; [
        # system
        gnome-tweaks

        # essential
        chromium
        google-chrome
        thunderbird
        telegram-desktop
        calibre
        filezilla
        keepassxc
        sigil
        (gimp-with-plugins.override { plugins = [ gimpPlugins.gmic ]; })

        # extra
        putty # serial
        uget
        moonlight-qt
        czkawka-full
        tor-browser
        nicotine-plus
        xournalpp
        krita
      ];
      nixpkgs.allowUnfree.packages = [ pkgs.google-chrome ];

      programs.anki.enable = true;
    }
  ];
}
