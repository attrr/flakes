# The Pixel's userdata, on top of nixosConfigurations.flame (bootstrap/default.nix):
# a 4K-sector GPT (UFS) with the ESP as systemd-boot would have installed it
{
  config,
  pkgs,
  lib,
  modulesPath,
  inputs,
  ...
}:
let
  toplevel = config.system.build.toplevel;
  registration = "/nix-path-registration";
  native = inputs.nixpkgs.legacyPackages.x86_64-linux;
in
{
  imports = [ "${modulesPath}/image/repart.nix" ];

  # systemd-repart runs under unshare, which binfmt's (multithreaded) qemu
  # can't do: build on x86, still for arm64
  system.build.image = lib.mkForce (
    config.image.repart.image.override {
      inherit (native.pkgsCross.aarch64-multiplatform) stdenvNoCC;
      inherit (native)
        runCommand
        python3
        black
        ruff
        mypy
        systemd
        fakeroot
        util-linux
        dosfstools
        mtools
        e2fsprogs
        ;
    }
  );

  image.repart = {
    name = "flame";
    sectorSize = 4096;
    partitions = {
      "10-esp" = {
        contents = {
          "/EFI/BOOT/BOOTAA64.EFI".source =
            "${config.systemd.package}/lib/systemd/boot/efi/systemd-bootaa64.efi";
          "/EFI/systemd/systemd-bootaa64.efi".source =
            "${config.systemd.package}/lib/systemd/boot/efi/systemd-bootaa64.efi";
          "/EFI/nixos/Image.efi".source =
            "${config.boot.kernelPackages.kernel}/${config.system.boot.loader.kernelFile}";
          "/EFI/nixos/initrd.efi".source =
            "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";
          "/EFI/nixos/flame.dtb".source =
            "${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name}";
          "/loader/entries/nixos-generation-1.conf".source = pkgs.writeText "nixos-generation-1.conf" ''
            title NixOS
            linux /EFI/nixos/Image.efi
            initrd /EFI/nixos/initrd.efi
            devicetree /EFI/nixos/flame.dtb
            options init=${toplevel}/init ${toString config.boot.kernelParams}
          '';
        };
        repartConfig = {
          Type = "esp";
          Label = "esp";
          Format = "vfat";
          SizeMinBytes = "512M";
        };
      };
      "20-root" = {
        storePaths = [ toplevel ];
        contents.${registration}.source = "${pkgs.closureInfo { rootPaths = [ toplevel ]; }}/registration";
        repartConfig = {
          Type = "root-arm64";
          Label = "nixos";
          Format = "ext4";
          Minimize = "guess";
        };
      };
    };
  };

  # as the sd image does it
  systemd.services.register-nix-paths = {
    description = "Register Nix Store Paths";
    unitConfig = {
      DefaultDependencies = false;
      ConditionPathExists = registration;
    };
    wantedBy = [ "sysinit.target" ];
    before = [
      "sysinit.target"
      "shutdown.target"
      "nix-daemon.socket"
      "nix-daemon.service"
    ];
    after = [ "local-fs.target" ];
    conflicts = [ "shutdown.target" ];
    restartIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${lib.getExe' config.nix.package.out "nix-store"} --load-db < ${registration}
      # nixos-rebuild also requires a "system" profile and an /etc/NIXOS tag
      touch /etc/NIXOS
      ${lib.getExe' config.nix.package.out "nix-env"} -p /nix/var/nix/profiles/system --set /run/current-system
      rm -f ${registration}
    '';
  };
}
