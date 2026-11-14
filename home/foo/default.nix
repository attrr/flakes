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
    ./agents
    ./apps.nix
    ./emacs
    ./git.nix
    ./gnome.nix
    ./htop.nix
    ./hydroxide.nix
    ./i18n.nix
    ./ide.nix
    ./mpv.nix
    ./ssh.nix
    ./zsh
  ];

  config = {
    home.username = "foo";
    home.homeDirectory = "/home/foo";
    home.stateVersion = "25.11"; # Please read the comment before changing.
    programs.home-manager.enable = true;
    xdg.enable = true;

    allowUnfree.enable = true;

    _module.args.pkgsUnstable = import inputs.nixpkgs-unstable {
      inherit (pkgs.stdenv.hostPlatform) system;
      inherit (config.nixpkgs) config;
    };
  };
}
