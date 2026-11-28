{
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
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    finix.url = "github:finix-community/finix";
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
      finix,
      ...
    }@inputs:
    let
      inherit (nixpkgs) lib;

      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = lib.genAttrs supportedSystems;

      # private submodule
      ctx = (import ./ctx/flake.nix).outputs { inherit nixpkgs; };
      hosts = ctx.cluster.hosts;
      isContainerMinimal = name: hosts.${name}.metadata.minimal;
      minimalHosts = lib.filterAttrs (n: _: isContainerMinimal n) hosts;
      normalHosts = lib.filterAttrs (n: _: !isContainerMinimal n) hosts;

      aspectLib = import ./lib/aspects.nix { inherit lib; };
      modules = import ./modules { inherit lib; };

      localPkgs =
        final: prev:
        lib.packagesFromDirectoryRecursive {
          callPackage = lib.callPackageWith (final // { inherit prev; });
          directory = ./pkgs;
        };

      providerModules =
        class: host:
        let
          p = ./modules/providers/${toString host.metadata.provider}.nix;
        in
        lib.optionals (host.metadata.provider != null && builtins.pathExists p) (
          aspectLib.resolve class [ p ]
        );

      # <host> from hosts/<host>/default.nix, <host>+<variant> from
      # hosts/<host>/default-<variant>.nix (same ctx entry, so same identity)
      mkSystem =
        hostname: entry:
        lib.nixosSystem {
          specialArgs = { inherit inputs self; };
          modules = [
            self.modules.nixos.default
            sops-nix.nixosModules.sops
            disko.nixosModules.disko
            ctx.nixosModules.${hostname}
            ./lib/default.nix
            { nixpkgs.overlays = [ self.overlays.default ]; }
            # as in home/foo
            (
              { pkgs, config, ... }:
              {
                _module.args.pkgsUnstable = import inputs.nixpkgs-unstable {
                  inherit (pkgs.stdenv.hostPlatform) system;
                  inherit (config.nixpkgs) config;
                };
              }
            )
          ]
          ++ providerModules "nixos" hosts.${hostname}
          ++ lib.optional (builtins.pathExists entry) entry;
        };

      mkContainerMinimal =
        hostname: entry:
        lib.evalModules {
          specialArgs = { inherit inputs self finix; };
          modules = [
            self.modules.finix.default
            ctx.nixosModules.${hostname}
            self.modules.finix.container
            { nixpkgs.overlays = [ self.overlays.default ]; }
          ]
          ++ providerModules "finix" hosts.${hostname}
          ++ lib.optional (builtins.pathExists entry) entry;
        };

      hostDir =
        hostname:
        if builtins.pathExists ./hosts/drifting/${hostname} then
          ./hosts/drifting/${hostname}
        else
          ./hosts/${hostname};

      variants =
        builder: hostname:
        let
          dir = hostDir hostname;
        in
        lib.optionalAttrs (builtins.pathExists dir) (
          lib.concatMapAttrs (
            f: _:
            let
              m = builtins.match "default-(.+)\\.nix" f;
            in
            lib.optionalAttrs (m != null) {
              "${hostname}+${builtins.head m}" = builder hostname (dir + "/${f}");
            }
          ) (builtins.readDir dir)
        );

      mkHosts =
        builder:
        lib.concatMapAttrs (
          name: _: { ${name} = builder name (hostDir name + "/default.nix"); } // variants builder name
        );

      # <user>: NixOS; <user>+generic: other distros
      mkHomes = lib.mapAttrs (
        name: value:
        let
          parts = lib.splitString "+" name;
          user = builtins.head parts;
          variant = if builtins.length parts > 1 then builtins.elemAt parts 1 else null;
        in
        assert lib.assertMsg (lib.elem variant [
          null
          "generic"
        ]) "home ${name}: the only variant is +generic";
        home-manager.lib.homeManagerConfiguration (
          lib.recursiveUpdate value {
            pkgs = value.pkgs or nixpkgs.legacyPackages.x86_64-linux;
            extraSpecialArgs = {
              inherit inputs self;
              ctx = {
                inherit (ctx.cluster) global registry hosts;
              };
            }
            // (value.extraSpecialArgs or { });
            modules = [
              sops-nix.homeManagerModules.sops
              (./home + "/${user}/default.nix")
              {
                nixpkgs.overlays = [
                  self.overlays.default
                  nixgl.overlay
                ];
                os.isNixOS = variant == null;
              }
            ]
            ++ (value.modules or [ ]);
          }
        )
      );

      deployPkgs = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        import nixpkgs {
          inherit system;
          overlays = [
            deploy-rs.overlays.default
            (_: super: {
              deploy-rs = {
                inherit (pkgs) deploy-rs;
                lib = super.deploy-rs.lib;
              };
            })
          ];
        }
      );

      mkDeployNode =
        name: host:
        let
          system = self.nixosConfigurations.${name}.pkgs.stdenv.hostPlatform.system;
        in
        {
          inherit (host.deploy) hostname;
          sshUser = host.deploy.user;
          profiles.system = {
            user = "root";
            path = deployPkgs.${system}.deploy-rs.lib.activate.nixos self.nixosConfigurations.${name};
          };
        }
        // lib.optionalAttrs host.deploy.fast-connection { fastConnection = true; };
    in
    {
      # every ctx host, plus its variants
      nixosConfigurations = (mkHosts mkSystem normalHosts) // (mkHosts mkContainerMinimal minimalHosts);

      deploy.nodes = lib.mapAttrs mkDeployNode normalHosts;

      homeConfigurations = mkHomes {
        foo = { };
        "foo+generic" = { };
      };

      overlays.default = localPkgs;

      apps = forAllSystems (
        import ./lib/apps.nix {
          inherit
            nixpkgs
            ctx
            deploy-rs
            hosts
            isContainerMinimal
            ;
        }
      );

      legacyPackages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        localPkgs (pkgs.extend localPkgs) pkgs
        // {
          bootstrap = import ./bootstrap {
            inherit
              nixpkgs
              self
              ctx
              system
              ;
          };
          prewarm = import ./lib/prewarm.nix {
            inherit
              self
              nixpkgs
              disko
              system
              ;
          };
        }
      );

      inherit (modules) nixosModules finixModules modules;

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);

      checks = forAllSystems (
        import ./lib/checks.nix {
          inherit
            self
            inputs
            nixpkgs
            disko
            deploy-rs
            finix
            ;
        }
      );
    };
}
