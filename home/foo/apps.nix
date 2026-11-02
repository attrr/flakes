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
        deploy-rs
        zsh-completions
        nix-zsh-completions
        autossh
        rclone-ssh
        google-cloud-sdk
        knot-dns
        gh
        # gui
        google-chrome
        chromium
        thunderbird
        czkawka-full
        # 2.8 (qt6)
        pkgsUnstable.keepassxc
      ];
      allowUnfree.packages = [ pkgs.google-chrome ];

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
        git-lfs
        rlwrap
        ccache
        libarchive # bsdtar
        conntrack-tools
        git-repo
        libguestfs-with-appliance
        temurin-bin-25
        tpm2-tools
        libheif
        mecab
        tftp-hpa
        flex
        bison
        pkgsCross.aarch64-multiplatform.buildPackages.gcc
      ];
      home.sessionVariables.ELECTRON_OZONE_PLATFORM_HINT = "auto";
    })

    # what NixOS has system-wide
    (lib.mkIf (!config.os.isNixOS) {
      targets.genericLinux.enable = true;
      home.packages = with pkgs; [
        nixgl.nixGLIntel
        nix
        sops
        nixos-rebuild
      ];
    })
  ];
}
