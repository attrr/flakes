# Bootstrap artifacts, exposed as legacyPackages.<system>.bootstrap:
#   rescue.default   generic rescue, keys only via ssh_key= on the cmdline
#   rescue.<host>    rescue preconfigured from ctx (+ ./hosts/<host>.nix if present)
#   images.<name>    flashable images
{
  nixpkgs,
  self,
  ctx,
  system,
}:
let
  inherit (nixpkgs) lib;

  # shared by stage0 (to find the squashfs) and stage1 (to touch disks)
  kernelModules = [
    "ext4"
    "xfs"
    "vfat"
    "nls_cp437"
    "nls_iso8859_1"
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "ata_piix"
    "ata_generic"
    "sd_mod"
    "sr_mod"
    "nvme"
  ];

  mkRescue =
    {
      modules ? [ ],
      specialArgs ? { },
      kernelPackages ? (p: p.linuxPackages),
    }:
    let
      common =
        { pkgs, ... }:
        {
          nixpkgs.hostPlatform = system;
          boot.kernelPackages = kernelPackages pkgs;
          system.stateVersion = lib.trivial.release;
        };

      stage1 = lib.nixosSystem {
        inherit specialArgs;
        modules = [
          common
          ./rescue.nix
          { boot.initrd.availableKernelModules = kernelModules; }
        ]
        ++ modules;
      };

      stage0 = lib.nixosSystem {
        modules = [
          common
          ./stage0
          {
            stage0 = {
              inherit kernelModules;
              stage1Initrd = stage1.config.system.build.initialRamdisk;
            };
          }
        ];
      };
    in
    stage0.config.system.build.rescue;

  hosts = lib.filterAttrs (_: c: c.metadata.arch == system) (
    lib.mapAttrs (_: m: m._module.args.ctx) (removeAttrs ctx.nixosModules [ "default" ])
  );
in
{
  inherit mkRescue;

  rescue = {
    default = mkRescue { };
  }
  // lib.mapAttrs (
    name: c:
    mkRescue {
      specialArgs.ctx = c;
      modules = [ ./ctx.nix ] ++ lib.optional (builtins.pathExists ./hosts/${name}.nix) ./hosts/${name}.nix;
    }
  ) hosts;

  images = lib.optionalAttrs (system == "aarch64-linux") {
    yata =
      (lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          ./images/yata.nix
          ctx.nixosModules.yata
          self.nixosModules.default
        ];
        specialArgs = { inherit self; };
      }).config.system.build.sdImage;
  };
}
