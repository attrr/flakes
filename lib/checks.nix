# Flake checks (`nix flake check`): deploy-rs, nixfmt, deadnix, and module boundary tests.
{
  self,
  nixpkgs,
  disko,
  deploy-rs,
}:
system:
let
  inherit (nixpkgs) lib;
  pkgs = nixpkgs.legacyPackages.${system};

  nixSrc = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.difference (lib.fileset.fileFilter (f: f.hasExt "nix") ../.) ../ctx;
  };

  pureNixos = lib.nixosSystem {
    inherit system;
    modules = [
      self.nixosModules.default
      disko.nixosModules.disko
      {
        system.stateVersion = "26.05";
        fileSystems."/" = {
          device = "/dev/null";
          fsType = "ext4";
        };
        boot.loader.grub.enable = false;
      }
    ];
  };

  nixosContainer = self.nixosConfigurations.koto.extendModules {
    modules = [ self.modules.nixos.container ];
  };
in
(deploy-rs.lib.${system}.deployChecks self.deploy)
// {
  format = pkgs.runCommand "check-format" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
    nixfmt --check ${nixSrc}
    touch $out
  '';

  deadnix = pkgs.runCommand "check-deadnix" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
    deadnix --fail --no-lambda-pattern-names ${nixSrc}
    touch $out
  '';

  pure-nixos-modules =
    assert builtins.isString pureNixos.config.system.build.toplevel.drvPath;
    pkgs.runCommand "check-pure-nixos-modules" { } ''
      touch $out
    '';

  nixos-container-profile =
    assert nixosContainer.config.infra.container.runtime == "lxc";
    assert builtins.isString nixosContainer.config.system.activationScripts.containerLustrate;
    pkgs.runCommand "check-nixos-container-profile" { } ''
      touch $out
    '';
}
