# Builds the two-stage RAM rescue initrd (stage0 squashfs loader + stage1 systemd initrd).
{ nixpkgs, system }:
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
in
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
      ./stage1
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
stage0.config.system.build.rescue
