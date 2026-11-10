# Bootstrap artifacts, exposed as legacyPackages.<system>.bootstrap:
#   rescue.default   generic rescue, keys only via ssh_key= on the cmdline
#   rescue.<host>    rescue preconfigured from ctx (+ ./hosts/<host>.nix if present)
#   images.<name>    scripts that write <name>'s image into $PWD, as its host (./identity-image.nix)
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

  pkgs = nixpkgs.legacyPackages.${system};

  identityImage = import ./identity-image.nix { inherit lib pkgs; };

  hosts = lib.filterAttrs (_: a: a.ctx.metadata.arch == system) (
    lib.mapAttrs (_: m: { inherit (m._module.args) ctx global; }) (
      removeAttrs ctx.nixosModules [ "default" ]
    )
  );
in
{
  inherit mkRescue;

  rescue = {
    default = mkRescue { };
  }
  // lib.mapAttrs (
    name: args:
    mkRescue {
      specialArgs = args;
      modules = lib.filter builtins.pathExists [
        ./ctx.nix
        ./hosts/${name}.nix
      ];
    }
  ) hosts;

  # every config whose host has an ssh host key in ctx vars, as that host;
  # <host>+<variant> configs included (same identity), so never run both at once
  images =
    let
      hostKey = cfg: ../ctx/vars + "/${cfg.config.networking.hostName}/ssh-host-key/ssh_host_ed25519_key";
      vars = cfg: ../ctx/vars + "/${cfg.config.networking.hostName}";
      disko = lib.filterAttrs (
        _: cfg: (cfg.config.disko.devices.disk or { }) != { } && builtins.pathExists (hostKey cfg)
      ) self.nixosConfigurations;
    in
    lib.mapAttrs (
      name: cfg:
      identityImage.disko {
        inherit name;
        nixos = cfg;
        vars = vars cfg;
        # <host>+vm configs run as VMs, the rest get dd'ed from rescue
        format = if lib.hasSuffix "+vm" name then "qcow2" else "raw.zst";
      }
    ) disko
    // {
      # the Pi boots an sd image instead
      yata = identityImage.sd {
        name = "yata";
        nixos = self.nixosConfigurations.yata.extendModules { modules = [ ./images/yata.nix ]; };
        vars = vars self.nixosConfigurations.yata;
      };
      # the Pixel's userdata, a repart image
      flame =
        let
          nixos = self.nixosConfigurations.flame.extendModules { modules = [ ./images/flame.nix ]; };
        in
        identityImage.sd {
          name = "flame";
          inherit nixos;
          vars = vars self.nixosConfigurations.flame;
          image = "${nixos.config.system.build.image}/${nixos.config.image.filePath}";
          sectorSize = 4096;
        };
    };
}
