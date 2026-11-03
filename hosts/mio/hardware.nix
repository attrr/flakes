{
  config,
  lib,
  ctx,
  modulesPath,
  ...
}:
let
  # shared with Fedora
  pool = "/dev/disk/by-uuid/9e4c180f-4d14-46a1-a0f7-d52c74885044";
  btrfs = subvol: {
    device = pool;
    fsType = "btrfs";
    options = [
      "subvol=${subvol}"
      "compress=zstd"
      "noatime"
      "discard=async"
    ];
  };
in
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usb_storage"
    "usbhid"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ "amdgpu" ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  boot.initrd.luks.devices.root = {
    device = "/dev/disk/by-uuid/d676ff53-dc71-4202-a0c6-109247987f82";
    allowDiscards = true;
  };

  # Fedora's root is @fedora
  fileSystems."/" = btrfs "@";
  fileSystems."/nix" = btrfs "@nix";
  fileSystems."/home" = btrfs "@home";
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/035C-F92A";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };

  # asks for the key if the secret is missing
  environment.etc.crypttab.text = ''
    storage UUID=5d4b173e-5b6b-4147-b5b6-b90f03504486 ${ctx.vars.storage-key.key.path} keyfile-timeout=20s,x-systemd.device-timeout=5,timeout=5,nofail
  '';
  fileSystems."/mnt" = {
    device = "/dev/mapper/storage";
    fsType = "btrfs";
    options = [
      "compress=zstd"
      "noatime"
      "nofail"
    ];
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
