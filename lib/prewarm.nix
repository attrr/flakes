{
  self,
  nixpkgs,
  disko,
  system,
}:
let
  inherit (nixpkgs) lib;
  aspectLib = import ./aspects.nix { inherit lib; };

  basePkgs = nixpkgs.legacyPackages.${system};
  pkgs = import nixpkgs {
    inherit system;
    overlays = [ self.overlays.default ];
  };

  customPkgs = lib.packagesFromDirectoryRecursive {
    callPackage = lib.callPackageWith (pkgs // { prev = basePkgs; });
    directory = ../pkgs;
  };

  # private git+ssh, unfree, or x86_64-only (rea -> aapt)
  excludedPkgs = [
    "tgu"
    "firmware-google-flame"
    "warp-podman"
  ]
  ++ lib.optionals (system != "x86_64-linux") [ "rea" ];

  buildablePkgs = lib.filterAttrs (
    name: pkg:
    !(lib.elem name excludedPkgs)
    && lib.isDerivation pkg
    && !(pkg.meta.broken or false)
    && !(pkg.meta.unfree or false)
    && lib.meta.availableOn pkgs.stdenv.hostPlatform pkg
  ) customPkgs;

  mkShim =
    extraModules:
    (lib.nixosSystem {
      inherit system;
      modules = [
        self.nixosModules.default
        disko.nixosModules.disko
        {
          nixpkgs.overlays = [ self.overlays.default ];
          system.stateVersion = "26.05";
          fileSystems."/" = {
            device = "/dev/null";
            fsType = "ext4";
          };
        }
      ]
      ++ extraModules;
    }).config.system.build.toplevel;

  serverShim = mkShim (
    aspectLib.resolveModule "nixos" [ ../modules/profiles/server ]
    ++ [
      {
        boot.loader.grub.enable = false;
        services.tailscale.enable = true;
        infra.server.ssh-keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIprewarmshimdummykey000000000000000000000000 prewarm"
        ];
      }
    ]
  );

  desktopShim = mkShim (
    aspectLib.resolveModule "nixos" [ ../modules/profiles/desktop ]
    ++ [
      ../modules/hardware/kled.nix
      {
        boot.loader.systemd-boot.enable = true;
        services.xserver.enable = true;
        users.allowNoPasswordLogin = true;
        users.users.foo.isNormalUser = true;
        infra.desktop = {
          enableLibvirtd = true;
          printing = {
            hp = true;
            epson = true;
          };
        };
      }
    ]
  );

  targets =
    buildablePkgs
    // {
      nixos-server = serverShim;
    }
    // lib.optionalAttrs (system == "x86_64-linux") {
      nixos-desktop = desktopShim;
    };
in
pkgs.linkFarm "prewarm-${system}" (lib.mapAttrsToList (name: path: { inherit name path; }) targets)
