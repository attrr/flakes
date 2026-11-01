{
  description = "NixOS Declarative Configuration";

  inputs = {
    self.submodules = true;
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
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixgl = {
      url = "github:nix-community/nixGL";
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
      nixgl,
      deploy-rs,
      ...
    }@inputs:
    let
      # private submodule
      ctx = (import ./ctx/flake.nix).outputs { inherit nixpkgs; };

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
                  nixpkgs.overlays = [
                    self.overlays.default
                  ];
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
                    nixpkgs.overlays = [
                      self.overlays.default
                      nixgl.overlay
                    ];
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
        "yata+vm" = {
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
        shiro.hostname = "shiro.";
        reisi.hostname = "reisi.";
        iwa.hostname = "iwa";
        neko = {
          sshUser = "foo";
          hostname = "neko";
          fastConnection = true;
        };
        kamo.hostname = "kamo.";
        koto.hostname = "koto.";
        ren.hostname = "ren.";
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
          bootstrap = import ./bootstrap {
            inherit
              nixpkgs
              self
              ctx
              system
              ;
          };
        }
      );

      nixosModules = import ./modules;

      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
