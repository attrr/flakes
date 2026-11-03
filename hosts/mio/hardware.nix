{
  config,
  lib,
  ctx,
  modulesPath,
  ...
}:
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
