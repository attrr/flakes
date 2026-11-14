{
  lib,
  pkgs,
  pkgsUnstable,
  config,
  ...
}:
{
  config = lib.mkMerge [
    {
      home.packages = with pkgs; [
        # cli
        sops
        deploy-rs
        autossh
        rclone
        rclone-ssh
        google-cloud-sdk
        knot-dns
        gh
        qrencode
        wl-clipboard
        unzip
        unrar
        # gui
        google-chrome
        chromium
        thunderbird
        czkawka-full
        # 2.8 (qt6); the NixOS desktop profile has it system-wide too, for polkit
        pkgsUnstable.keepassxc
      ];
      allowUnfree.packages = [
        pkgs.google-chrome
        pkgs.unrar
      ];

      programs.direnv.enable = true;
      programs.direnv.nix-direnv.enable = true;
    }

    # Fedora has these as rpms
    (lib.mkIf config.os.isNixOS {
      home.packages = with pkgs; [
        xournalpp
        krita
        # gui
        calibre
        digikam
        (gimp-with-plugins.override { plugins = [ gimpPlugins.gmic ]; })
        gthumb
        geeqie
        sigil
        filezilla
        putty
        nicotine-plus
        uget
        thunar
        tor-browser
        gnome-tweaks
        # tools
        rlwrap
        ccache
        libarchive # bsdtar
        binutils # strings, objdump
        conntrack-tools
        git-repo
        android-tools # adb, fastboot
        libguestfs-with-appliance
        tpm2-tools
        libheif
        mecab
        tftp-hpa
        flex
        bison
        pkgsCross.aarch64-multiplatform.buildPackages.gcc
      ];
      home.sessionVariables.ELECTRON_OZONE_PLATFORM_HINT = "auto";
      programs.java.enable = true;
    })

    # what NixOS has system-wide
    (lib.mkIf (!config.os.isNixOS) {
      targets.genericLinux.enable = true;
      home.packages = with pkgs; [
        nixgl.nixGLIntel
        nix
        nixos-rebuild
      ];
    })
  ];
}
