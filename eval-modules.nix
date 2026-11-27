let
  flake = builtins.${"getFlake"} "git+file://${toString ./.}";
  inherit (flake) inputs;
  inherit (inputs)
    nixpkgs
    home-manager
    finix
    disko
    sops-nix
    ;

  pkgs = import nixpkgs { system = "x86_64-linux"; };
  lib = nixpkgs.lib.extend (_: _: { hm = home-manager.lib.hm; });

  aspectLib = import ./lib/aspects.nix { inherit lib; };
  modExports = import ./modules { inherit lib; };

  specialArgs = {
    inherit
      inputs
      lib
      pkgs
      finix
      ;
    modulesPath = "${nixpkgs}/nixos/modules";
    fn = import ./ctx/lib/default.nix { inherit lib; };
    self = ./.;
  };

  evalOpts =
    modules:
    (lib.evalModules {
      inherit specialArgs;
      modules = modules ++ [ { _module.check = false; } ];
    }).options;

  mkClassOpt =
    modules:
    lib.mkOption {
      type = lib.types.submoduleWith {
        inherit specialArgs;
        modules = modules ++ [ { _module.check = false; } ];
      };
      default = { };
    };

  ctxOption = {
    options.ctx = lib.mkOption {
      type = lib.types.submoduleWith {
        modules = [ ./ctx/modules/perhost ];
        specialArgs.fn = specialArgs.fn;
      };
      default = { };
    };
  };

  nixosBase = import "${nixpkgs}/nixos/modules/module-list.nix";

  nixosProfiles =
    let
      entries = builtins.readDir ./modules/profiles;
    in
    aspectLib.resolveModule "nixos" (
      map (name: ./modules/profiles + "/${name}") (builtins.attrNames entries)
    );

  customModules = [
    modExports.nixosModules.default
    disko.nixosModules.disko
    sops-nix.nixosModules.sops
    ctxOption
    ./lib/default.nix
  ]
  ++ nixosProfiles;

  finixModules = [
    modExports.finixModules.default
    ctxOption
  ]
  ++ aspectLib.resolveModule "finix" [ ./modules/profiles/container ];

  hmModules =
    (import "${home-manager}/modules/modules.nix" {
      inherit pkgs lib;
      check = false;
    })
    ++ [ sops-nix.homeManagerModules.sops ];

  classOptions = {
    common = mkClassOpt customModules;
    os = mkClassOpt customModules;
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
  ctx = evalOpts [
    ./ctx/modules/perhost
    ./ctx/modules/cluster/global.nix
  ];
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
