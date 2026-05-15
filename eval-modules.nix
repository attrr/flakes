let
  flake = builtins.getFlake "git+file://${toString ./.}";
  nixpkgs = flake.inputs.nixpkgs;
  hm = flake.inputs.home-manager;

  pkgs = import nixpkgs { system = "x86_64-linux"; };
  lib = nixpkgs.lib.extend (
    self: super: {
      hm = hm.lib.hm;
    }
  );

  specialArgs = {
    inherit lib pkgs;
    modulesPath = nixpkgs + "/nixos/modules";
    self = ./.;
  };
  profileModules =
    let
      dir = ./modules/profiles;
      entries = builtins.readDir dir;
      isProfile =
        name: type:
        (type == "regular" && lib.hasSuffix ".nix" name)
        || (type == "directory" && builtins.pathExists (dir + "/${name}/default.nix"));
    in
    if builtins.pathExists dir then
      map (name: dir + "/${name}") (builtins.attrNames (lib.filterAttrs isProfile entries))
    else
      [ ];

in
{
  nixos =
    (lib.evalModules {
      modules = (import (nixpkgs + "/nixos/modules/module-list.nix")) ++ [ { _module.check = false; } ];
      inherit specialArgs;
    }).options;

  home-manager =
    (lib.evalModules {
      modules =
        (import (hm + "/modules/modules.nix") {
          inherit pkgs lib;
          check = false;
        })
        ++ [ { _module.check = false; } ];
      inherit specialArgs;
    }).options;

  custom =
    (lib.evalModules {
      modules = [
        flake.nixosModules.default
      ]
      ++ profileModules
      ++ [
        flake.inputs.disko.nixosModules.disko
        flake.inputs.sops-nix.nixosModules.sops
        (
          { lib, ... }:
          {
            options.ctx = lib.mkOption {
              type = lib.types.submodule {
                imports = [ flake.inputs.ctx.nixosModules.default ];
              };
              default = { };
            };
          }
        )
        ./lib/default.nix
        { _module.check = false; }
      ];
      inherit specialArgs;
    }).options;
}
