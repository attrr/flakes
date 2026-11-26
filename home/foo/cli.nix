{
  pkgs,
  lib,
  config,
  ...
}:
lib.mkMerge [
  (lib.mkIf (!config.os.isNixOS) {
    targets.genericLinux.enable = true;
    home.packages = with pkgs; [
      nixgl.nixGLIntel
      nix
      nixos-rebuild
    ];
  })

  {
    home.packages = with pkgs; [
      # maintainance
      unzip
      unrar
      knot-dns # for kdig
      libarchive # bsdtar
      binutils # strings, objdump
      android-tools # adb, fastboot
      conntrack-tools
      libguestfs-with-appliance

      # deploy
      sops
      deploy-rs
      autossh
      rclone
      rclone-ssh

      # extra
      gh
      gitleaks
      rlwrap
      libheif
      tpm2-tools
      qrencode
      wl-clipboard
      google-cloud-sdk
      tftp-hpa # openwrt bootstrap
    ];
    nixpkgs.allowUnfree.packages = [ pkgs.unrar ];

    programs.java.enable = true;
    programs.direnv.enable = true;
    programs.direnv.nix-direnv.enable = true;
  }
]
