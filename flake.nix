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

      hosts = ctx.cluster.hosts;

      # <host> from hosts/<host>/default.nix, <host>+<variant> from
      # hosts/<host>/default-<variant>.nix (same ctx entry, so same identity)
      mkSystem =
        hostname: entry:
        let
          lib = nixpkgs.lib;
          host = hosts.${hostname};
          # profiles/<tag> and its ctx glue ctx/<tag>.nix, for the host's tags
          byTag =
            dir:
            lib.filter builtins.pathExists (
              lib.concatMap (t: [
                (dir + "/${t}")
                (dir + "/${t}.nix")
              ]) host.metadata.tags
            );
        in
        lib.nixosSystem {
          modules = [
            self.nixosModules.default
            sops-nix.nixosModules.sops
            disko.nixosModules.disko
            ctx.nixosModules.${hostname}
            ./lib/default.nix
            ./modules/ctx/host.nix
            ./modules/ctx/proxy.nix
            { nixpkgs.overlays = [ self.overlays.default ]; }
          ]
          ++ byTag ./modules/profiles
          ++ byTag ./modules/ctx
          ++ lib.optional (
            host.metadata.provider != null
          ) ./modules/ctx/providers/${host.metadata.provider}.nix
          ++ lib.optional (builtins.pathExists entry) entry;
          specialArgs = {
            inherit inputs self;
          };
        };

      variants =
        hostname:
        let
          dir = ./hosts/${hostname};
        in
        nixpkgs.lib.optionalAttrs (builtins.pathExists dir) (
          nixpkgs.lib.concatMapAttrs (
            f: _:
            let
              m = builtins.match "default-(.+)\\.nix" f;
            in
            nixpkgs.lib.optionalAttrs (m != null) {
              "${hostname}+${builtins.head m}" = mkSystem hostname (dir + "/${f}");
            }
          ) (builtins.readDir dir)
        );

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

      mkDeployNode =
        name: host:
        let
          system = self.nixosConfigurations.${name}.pkgs.stdenv.hostPlatform.system;
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
        {
          inherit (host.deploy) hostname;
          sshUser = host.deploy.user;
          profiles.system = {
            user = "root";
            path = deployPkgs.deploy-rs.lib.activate.nixos self.nixosConfigurations.${name};
          };
        }
        // nixpkgs.lib.optionalAttrs host.deploy.fast-connection { fastConnection = true; };
    in
    {
      # every ctx host, plus its variants
      nixosConfigurations = nixpkgs.lib.concatMapAttrs (
        name: _: { ${name} = mkSystem name ./hosts/${name}/default.nix; } // variants name
      ) hosts;

      deploy.nodes = nixpkgs.lib.mapAttrs mkDeployNode hosts;

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

      # nix run .#deploy -- [--checks] <selector>... [-- <deploy-rs args>]: a
      # selector is a host, a ctx group, tag or provider, or "all". Skips the
      # flake checks (every host's evaluation) unless --checks
      apps = forAllSystems (
        system:
        let
          lib = nixpkgs.lib;
          pkgs = nixpkgs.legacyPackages.${system};
          selectors = lib.zipAttrsWith (_: lib.concatLists) (
            [ { all = lib.attrNames hosts; } ]
            ++ lib.mapAttrsToList (
              name: h:
              {
                ${name} = [ name ];
              }
              // lib.genAttrs (
                h.metadata.tags
                ++ lib.filter (x: x != null) [
                  h.metadata.group
                  h.metadata.provider
                ]
              ) (_: [ name ])
            ) hosts
          );
        in
        {
          deploy = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "deploy-selected" ''
                declare -A sel=(${
                  lib.concatStrings (
                    lib.mapAttrsToList (
                      n: hs: "[${lib.escapeShellArg n}]=${lib.escapeShellArg (toString (lib.unique hs))} "
                    ) selectors
                  )
                })
                targets=()
                checks=(--skip-checks)
                while [ $# -gt 0 ] && [ "$1" != -- ]; do
                  if [ "$1" = --checks ]; then
                    checks=()
                    shift
                    continue
                  fi
                  if [ -z "''${sel[$1]+x}" ]; then
                    echo "unknown selector '$1', one of: ''${!sel[*]}" >&2
                    exit 1
                  fi
                  for h in ''${sel[$1]}; do targets+=(".#$h"); done
                  shift
                done
                [ "''${1:-}" = -- ] && shift
                [ ''${#targets[@]} -gt 0 ] || { echo "usage: nix run .#deploy -- [--checks] <selector>... [-- <deploy-rs args>]" >&2; exit 1; }
                mapfile -t targets < <(printf '%s\n' "''${targets[@]}" | sort -u)
                echo "deploying: ''${targets[*]#.#}" >&2
                exec ${
                  deploy-rs.packages.${system}.default
                }/bin/deploy "''${checks[@]}" --targets "''${targets[@]}" "$@"
              ''
            );
          };
        }
      );

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
