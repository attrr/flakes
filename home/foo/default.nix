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
  options = {
    os.isNixOS = lib.mkOption {
      type = lib.types.bool;
      description = "Whether the home is switched on NixOS.";
    };

    secrets.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.os.isNixOS;
      description = "Whether to decrypt user-scoped sops secrets on this machine.";
    };
  };

  imports = [
    self.modules.homeManager.default
    ./agents
    ./apps.nix
    ./cli.nix
    ./emacs
    ./git.nix
    ./gnome.nix
    ./hydroxide.nix
    ./i18n.nix
    ./ide.nix
    ./mpv.nix
    ./ssh.nix
    ./zsh
    ./script.nix
  ];

  config = {
    home.username = "foo";
    home.homeDirectory = "/home/foo";
    home.stateVersion = "25.11"; # Please read the comment before changing.
    programs.home-manager.enable = true;
    xdg.enable = true;

    nixpkgs.allowUnfree.enable = true;

    sops.age.keyFile = lib.mkIf config.secrets.enable (
      lib.mkDefault "${config.xdg.configHome}/sops/age/home.txt"
    );

    _module.args.pkgsUnstable = import inputs.nixpkgs-unstable {
      inherit (pkgs.stdenv.hostPlatform) system;
      inherit (config.nixpkgs) config;
    };
  };
}
