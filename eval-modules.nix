let
  flake = builtins.getFlake "git+file://${toString ./.}";
  nixpkgs = flake.inputs.nixpkgs;
  hm = flake.inputs.home-manager;
  finix = flake.inputs.finix;

  pkgs = import nixpkgs { system = "x86_64-linux"; };
  lib = nixpkgs.lib.extend (
    self: super: {
      hm = hm.lib.hm;
    }
  );

  specialArgs = {
    inherit lib pkgs finix;
    inputs = flake.inputs;
    modulesPath = nixpkgs + "/nixos/modules";
    self = ./.;
  };

  aspectLib = import ./lib/aspects.nix { inherit lib; };
  evalOpts =
    modules:
    (lib.evalModules {
      modules = modules ++ [ { _module.check = false; } ];
      inherit specialArgs;
    }).options;

  profileModules =
    let
      dir = ./modules/profiles;
      isProfile =
        name: type:
        name != "container-minimal"
        && name != "host.nix"
        && (
          (type == "regular" && lib.hasSuffix ".nix" name)
          || (type == "directory" && builtins.pathExists (dir + "/${name}/default.nix"))
        );
    in
    aspectLib.resolveModule "nixos" (
      map (name: dir + "/${name}") (builtins.attrNames (lib.filterAttrs isProfile (builtins.readDir dir)))
    );

  ctxOptionModule =
    { lib, ... }:
    {
      options.ctx = lib.mkOption {
        type = lib.types.submoduleWith {
          modules = [ ./ctx/modules/perhost ];
          specialArgs.fn = import ./ctx/lib/default.nix { inherit lib; };
        };
        default = { };
      };
    };

  customModules = lib.flatten [
    (import ./modules { inherit lib; }).nixosModules.default
    flake.inputs.disko.nixosModules.disko
    flake.inputs.sops-nix.nixosModules.sops
    (aspectLib.resolveModule "nixos" [ ./modules/secrets.nix ])
    ctxOptionModule
    ./lib/default.nix
    profileModules
  ];

  finixModules =
    aspectLib.resolveModule "finix" [
      ./modules/profiles/container-minimal
      ./modules/profiles/server
      ./modules/network
      ./modules/services/sing-box
      ./modules/services/usque
      ./modules/services/tunnelbroker
      ./modules/services/telemetry
      ./modules/secrets.nix
    ]
    ++ [ ctxOptionModule ];

  hmModules =
    (import (hm + "/modules/modules.nix") {
      inherit pkgs lib;
      check = false;
    })
    ++ [ flake.inputs.sops-nix.homeManagerModules.sops ];

  nixosBase = import (nixpkgs + "/nixos/modules/module-list.nix");

  mkClassOpt =
    modules:
    lib.mkOption {
      type = lib.types.submoduleWith {
        modules = modules ++ [ { _module.check = false; } ];
        inherit specialArgs;
      };
      default = { };
    };

  classOptions = {
    common = mkClassOpt customModules;
    nixos = mkClassOpt (nixosBase ++ customModules);
    finix = mkClassOpt finixModules;
    homeManager = mkClassOpt hmModules;
  };
  classMapType = lib.types.submodule { options = classOptions; };
in
{
  nixos = evalOpts nixosBase;
  home-manager = evalOpts hmModules;
  custom = evalOpts customModules;
  finix = evalOpts finixModules;
  ctx =
    (lib.evalModules {
      modules = [
        ./ctx/modules/perhost
        ./ctx/modules/cluster/global.nix
        { _module.check = false; }
      ];
      specialArgs = {
        inherit lib pkgs;
        modulesPath = nixpkgs + "/nixos/modules";
        fn = import ./ctx/lib/default.nix { inherit lib; };
      };
    }).options;
  aspect = evalOpts [
    {
      options = classOptions // {
        includes = lib.mkOption {
          type = lib.types.listOf lib.types.anything;
          default = [ ];
        };
        module = lib.mkOption {
          type = classMapType;
          default = { };
        };
        ctx = lib.mkOption {
          type = classMapType;
          default = { };
        };
      };
    }
  ];
}
