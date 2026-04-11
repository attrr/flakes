{
  lib,
  pkgs,
  host,
  inputs,
  config,
  ...
}:

let
  rclone-ssh = pkgs.callPackage ../../pkgs/rclone-ssh { };
in
{
  imports = [
    ./emacs.nix
    ../../modules/purpose/unfree.nix
    ./i18n.nix
    ./ide.nix
    ./ssh.nix
    ./htop.nix
  ];
  config = lib.mkMerge [
    (lib.mkIf (host == "nixos") {
      home.sessionVariables = {
        ELECTRON_OZONE_PLATFORM_HINT = "auto";
      };
      home.packages = with pkgs; [
        antigravity
        xournalpp
        krita
      ];
    })
    (lib.mkIf (host == "fedora") {
      home.packages = with pkgs; [
        nix
        sops
        nixos-rebuild
      ];
    })
    {
      home.username = "foo";
      home.homeDirectory = "/home/foo";
      home.stateVersion = "25.11"; # Please read the comment before changing.
      fonts.fontconfig.enable = true;

      home.file.".zshenv".source = "${inputs.dotfiles}/.zshenv";
      home.file.".config" = {
        source = "${inputs.dotfiles}/.config";
        recursive = true;
      };
      home.file.".local" = {
        source = "${inputs.dotfiles}/.local";
        recursive = true;
      };

      allowUnfree.enable = true;
      home.packages = with pkgs; [
        nerd-fonts.symbols-only
        nerd-fonts.jetbrains-mono
        # misc
        zsh-completions
        nix-zsh-completions
        autossh
        rclone-ssh
        google-cloud-sdk
      ];

      # Home Manager is pretty good at managing dotfiles. The primary way to manage
      # plain files is through 'home.file'.
      home.file = {
        # # Building this configuration will create a copy of 'dotfiles/screenrc' in
        # # the Nix store. Activating the configuration will then make '~/.screenrc' a
        # # symlink to the Nix store copy.
        # ".screenrc".source = dotfiles/screenrc;

        # # You can also set the file content immediately.
        # ".gradle/gradle.properties".text = ''
        #   org.gradle.console=verbose
        #   org.gradle.daemon.idletimeout=3600000
        # '';
      };

      # Home Manager can also manage your environment variables through
      # 'home.sessionVariables'. These will be explicitly sourced when using a
      # shell provided by Home Manager. If you don't want to manage your shell
      # through Home Manager then you have to manually source 'hm-session-vars.sh'
      # located at either
      #
      #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
      #
      # or
      #
      #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
      #
      # or
      #
      #  /etc/profiles/per-user/foo/etc/profile.d/hm-session-vars.sh
      #

      # Let Home Manager install and manage itself.
      programs.home-manager.enable = true;

      _module.args.pkgsUnstable = import inputs.nixpkgs-unstable {
        inherit (pkgs.stdenv.hostPlatform) system;
        inherit (config.nixpkgs) config;
      };
    }
  ];
}
