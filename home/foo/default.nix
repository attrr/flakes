{
  self,
  inputs,
  lib,
  pkgs,
  config,
  ...
}:
{
  # set by the flake: foo is NixOS, foo+generic anything else
  options.os.isNixOS = lib.mkOption {
    type = lib.types.bool;
    description = "Whether the home is switched on NixOS.";
  };

  imports = [
    "${self}/modules/services/unfree.nix"
    ./apps.nix
    ./emacs.nix
    ./gnome.nix
    ./htop.nix
    ./hydroxide.nix
    ./i18n.nix
    ./ide.nix
    ./ssh.nix
  ];

  config = {
    home.username = "foo";
    home.homeDirectory = "/home/foo";
    home.stateVersion = "25.11"; # Please read the comment before changing.
    programs.home-manager.enable = true;

    # shell and app configs live in the dotfiles repo
    home.file = {
      ".zshenv".source = "${inputs.dotfiles}/.zshenv";
      ".config" = {
        source = "${inputs.dotfiles}/.config";
        recursive = true;
      };
      ".local" = {
        source = "${inputs.dotfiles}/.local";
        recursive = true;
      };
    };

    allowUnfree.enable = true;

    _module.args.pkgsUnstable = import inputs.nixpkgs-unstable {
      inherit (pkgs.stdenv.hostPlatform) system;
      inherit (config.nixpkgs) config;
    };
  };
}
