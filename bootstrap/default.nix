# Bootstrap artifacts, exposed as legacyPackages.<system>.bootstrap:
#   rescue.default   generic rescue, keys only via ssh_key= on the cmdline
#   rescue.<host>    rescue preconfigured from ctx (+ ./hosts/<host>.nix if present)
#   images.<name>    flashable images, or scripts that write one into $PWD
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

  # Host identity kept sops-encrypted (admin only) in ctx/hosts/<dir>/identity,
  # decrypted to tmpfs at build time and copied into the disko image, so a
  # rebuilt machine keeps its ssh host key (= sops age key) and tailscale node.
  identityFiles = {
    "ssh_host_ed25519_key" = "/etc/ssh/ssh_host_ed25519_key";
    "ssh_host_ed25519_key.pub" = "/etc/ssh/ssh_host_ed25519_key.pub";
    "tailscaled.state" = "/var/lib/tailscale/tailscaled.state";
  };
  withIdentity =
    dir: nixos:
    let
      src = ../ctx/hosts/${dir}/identity;
      files = lib.filterAttrs (n: _: builtins.pathExists "${src}/${n}") identityFiles;
    in
    pkgs.writeShellApplication {
      name = "${nixos.config.networking.hostName}-image";
      runtimeInputs = [ pkgs.sops ];
      text = ''
        tmp=$(mktemp -d -p "''${XDG_RUNTIME_DIR:-/tmp}")
        trap 'rm -rf "$tmp"' EXIT
        umask 077
        ${lib.concatMapStrings (n: ''
          sops decrypt --input-type binary --output-type binary ${src}/${n} > "$tmp/${n}"
          ${lib.optionalString (lib.hasSuffix ".pub" n) ''chmod 644 "$tmp/${n}"''}
        '') (lib.attrNames files)}
        # disko copies without -p, so modes get masked again
        umask 022
        ${nixos.config.system.build.diskoImagesScript} ${
          lib.concatStringsSep " " (
            lib.mapAttrsToList (n: dst: "--post-format-files \"$tmp/${n}\" ${dst}") files
          )
        } "$@"
      '';
    };

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
      modules = [ ./ctx.nix ] ++ lib.optional (builtins.pathExists ./hosts/${name}.nix) ./hosts/${name}.nix;
    }
  ) hosts;

  images =
    lib.optionalAttrs (system == "aarch64-linux") {
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
    }
    // lib.optionalAttrs (system == "x86_64-linux") {
      # cold standby for yata: same identity, so never run both at once
      gateway = withIdentity "local/yata" self.nixosConfigurations.gateway;
    };
}
