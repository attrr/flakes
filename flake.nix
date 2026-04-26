{
  description = "NixOS Declarative Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ctx = {
      url = "git+ssh://git@github.com/attrr/ctx.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    stage1-dd = {
      url = "github:attrr/stage1-dd";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dotfiles = {
      url = "git+ssh://git@github.com/attrr/dotfiles.git";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      disko,
      sops-nix,
      home-manager,
      ctx,
      stage1-dd,
      ...
    }@inputs:
    let
      mkPackages =
        path:
        let
          system = "x86_64-linux";
          pkgs = import nixpkgs { inherit system; };
        in
        nixpkgs.lib.mapAttrs (name: _: pkgs.callPackage (path + "/${name}") { }) (builtins.readDir path);

      commonModules = [
        sops-nix.nixosModules.sops
        disko.nixosModules.disko
      ];
      stardustModules = commonModules ++ [
        ./modules/ctx/stardust.nix
      ];
      mkSystem =
        host: attr:
        let
          lib = nixpkgs.lib;
        in
        lib.nixosSystem (
          let
            defaultPath = ./hosts + "/${host}/default.nix";
          in
          lib.recursiveUpdate attr {
            system = attr.system or "x86_64-linux";
            modules =
              (attr.modules or [ ])
              ++ [
                ctx.nixosModules.${host}
                ./lib/default.nix
              ]
              ++ lib.optional (builtins.pathExists defaultPath) defaultPath;
            specialArgs = {
              inherit inputs;
              failoverModule = stage1-dd.nixosModules.failover;
            };
          }
        );
      mkSystems = attrs: nixpkgs.lib.mapAttrs (n: v: mkSystem n v) attrs;

      mkHomes =
        let
          lib = nixpkgs.lib;
        in
        attrs:
        lib.mapAttrs (
          tag: value:
          let
            parts = lib.splitString "@" tag;
            user = builtins.elemAt parts 0;
            host = builtins.elemAt parts 1;
          in
          home-manager.lib.homeManagerConfiguration (
            lib.recursiveUpdate value {
              pkgs = value.pkgs or nixpkgs.legacyPackages.x86_64-linux;
              extraSpecialArgs = {
                inherit inputs host;
              }
              // (value.extraSpecialArgs or { });
              modules = [ (./home + "/${user}/default.nix") ] ++ (value.modules or [ ]);
            }
          )
        ) attrs;
    in
    {
      packages.x86_64-linux = mkPackages ./pkgs;
      nixosConfigurations =
        mkSystems {
          yata = {
            system = "aarch64-linux";
            modules = [ sops-nix.nixosModules.sops ];
          };
          shiro.modules = commonModules;
          reisi.modules = commonModules;
          iwa.modules = commonModules;
          neko.modules = commonModules;
          # stardust
          kamo.modules = stardustModules;
          koto.modules = stardustModules;
          ren.modules = stardustModules;
          # lowend
          eric.modules = commonModules;
        }
        // {
          yata-bootstrap = nixpkgs.lib.nixosSystem {
            system = "aarch64-linux";
            modules = [ ./bootstrap/sd-image.nix ];
          };
        };

      homeConfigurations = mkHomes {
        "foo@fedora" = { };
        "foo@nixos" = { };
      };

      checks =
        let
          system = "x86_64-linux";
          pkgs = import nixpkgs { inherit system; };
        in
        {
          ${system} = import ./tests/sing-box { inherit pkgs; };
        };
    };
}
