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
    failoverModule = {};
  };

  filterModules = file: lib.hasSuffix ".nix" (toString file) && baseNameOf file != "default.nix";
  moduleFiles =
    let
      dir = ./modules;
    in
    if builtins.pathExists dir then
      lib.filter filterModules (lib.filesystem.listFilesRecursive dir)
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
      modules = moduleFiles ++ [
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
