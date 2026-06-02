{
  description = "NixOS Declarative Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
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
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dotfiles = {
      url = "git+ssh://git@github.com/attrr/dotfiles.git";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      disko,
      sops-nix,
      home-manager,
      ctx,
      stage1-dd,
      deploy-rs,
      ...
    }@inputs:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      commonModules = [
        sops-nix.nixosModules.sops
        disko.nixosModules.disko
      ];
      stardustModules = commonModules ++ [
        ./modules/ctx/stardust.nix
      ];

      mkSystem =
        n: v:
        let
          lib = nixpkgs.lib;
          defaultPath = ./hosts + "/${n}/default.nix";
          modules = v.modules or [ ];
          hostname = v.hostname or n;
        in
        lib.nixosSystem (
          lib.recursiveUpdate (builtins.removeAttrs v [ "hostname" ]) {
            system = v.system or "x86_64-linux";
            modules = [
              self.nixosModules.default
              ctx.nixosModules.${hostname}
              ./lib/default.nix
              (
                { ... }:
                {
                  nixpkgs.overlays = [ self.overlays.default ];
                }
              )
            ]
            ++ modules
            ++ lib.optional (builtins.pathExists defaultPath) defaultPath;
            specialArgs = {
              inherit inputs self;
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
            modules = value.modules or [ ];
          in
          home-manager.lib.homeManagerConfiguration (
            lib.recursiveUpdate value {
              pkgs = value.pkgs or nixpkgs.legacyPackages.x86_64-linux;
              extraSpecialArgs = {
                inherit inputs host self;
              }
              // (value.extraSpecialArgs or { });
              modules = [
                (./home + "/${user}/default.nix")
                (
                  { ... }:
                  {
                    nixpkgs.overlays = [ self.overlays.default ];
                  }
                )
              ]
              ++ modules;
            }
          )
        ) attrs;

      mkDeployNodes =
        let
          lib = nixpkgs.lib;
        in
        attrs:
        lib.mapAttrs (
          name: value:
          let
            system = self.nixosConfigurations.${name}.config.nixpkgs.system;
            pkgs = import nixpkgs { inherit system; };
            deployPkgs = import nixpkgs {
              inherit system;
              overlays = [
                deploy-rs.overlays.default
                (self: super: {
                  deploy-rs = {
                    inherit (pkgs) deploy-rs;
                    lib = super.deploy-rs.lib;
                  };
                })
              ];
            };
          in
          lib.recursiveUpdate {
            sshUser = "sysadm";
            profiles.system = {
              user = "root";
              path = deployPkgs.deploy-rs.lib.activate.nixos self.nixosConfigurations.${name};
            };
          } value
        ) attrs;
    in
    {
      nixosConfigurations = mkSystems {
        yata = {
          system = "aarch64-linux";
          modules = [ sops-nix.nixosModules.sops ];
        };
        gateway = {
          hostname = "yata";
          modules = [
            ./hosts/yata/default-vm.nix
          ]
          ++ commonModules;
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
        nerine.modules = commonModules;
      };

      deploy.nodes = mkDeployNodes {
        yata = {
          hostname = "yata";
          fastConnection = true;
        };
        shiro.hostname = "shiro-gfw";
        reisi.hostname = "reisi-gfw";
        iwa.hostname = "iwa";
        neko = {
          sshUser = "foo";
          hostname = "neko";
          fastConnection = true;
        };
        kamo.hostname = "kamo-gfw";
        koto.hostname = "koto-gfw";
        ren.hostname = "ren-gfw";
        eric.hostname = "eric";
        nerine.hostname = "nerine";
      };

      homeConfigurations = mkHomes {
        "foo@fedora" = { };
        "foo@nixos" = { };
      };

      overlays.default =
        final: prev:
        prev.lib.packagesFromDirectoryRecursive {
          inherit (prev) callPackage;
          directory = ./pkgs;
        };

      legacyPackages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.lib.packagesFromDirectoryRecursive {
          inherit (pkgs) callPackage;
          directory = ./pkgs;
        }
        // {
          sdimages.yata =
            (nixpkgs.lib.nixosSystem {
              system = "aarch64-linux";
              modules = [
                ./hosts/yata/init.nix
                ctx.nixosModules.yata
                self.nixosModules.default
              ];
              specialArgs = { inherit self; };
            }).config.system.build.sdImage;
        }
      );

      nixosModules = import ./modules;

      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
