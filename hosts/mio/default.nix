{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  # for VM passthrough
  vfioIds = [
    "10de:1380"
    "10de:0fbc"
  ];
in
{
  imports = [
    inputs.lanzaboote.nixosModules.lanzaboote
    ./hardware.nix
    ./disko.nix
    ./network.nix
    ./containers.nix
    ./caddy.nix
  ];

  # secure boot with our own keys, enrolled alongside Microsoft's
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
    configurationLimit = 10;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.systemd.enable = true;

  boot.initrd.kernelModules = [
    "vfio_pci"
    "vfio"
    "vfio_iommu_type1"
  ];
  boot.kernelParams = [
    "amd_iommu=on"
    "vfio-pci.ids=${lib.concatStringsSep "," vfioIds}"
  ];
  virtualisation.libvirtd = {
    enable = true;
    qemu.swtpm.enable = true;
  };
  programs.virt-manager.enable = true;

  # forgejo has 22 on the wg address
  services.endlessh.enable = false;

  users.groups.foo.gid = 1000;
  users.users.foo = {
    # matches Fedora, for the shared /home
    uid = 1000;
    group = "foo";
    extraGroups = [
      "libvirtd"
      "tss"
    ];
  };

  # ssh-tpm-agent keys are sealed in the TPM
  security.tpm2.enable = true;

  environment.systemPackages = [
    pkgs.sbctl
    pkgs.gnomeExtensions.freon
  ];
  # state shared with Fedora; devices and folders set in the gui
  services.syncthing = {
    enable = true;
    user = "foo";
    group = "foo";
    dataDir = "/home/foo";
    configDir = "/home/foo/.local/state/syncthing";
    overrideDevices = false;
    overrideFolders = false;
    openDefaultPorts = true;
  };
  services.flatpak.enable = true;
  hardware.bluetooth.enable = true;

  # for prebuilt binaries in the shared /home (vscode extensions)
  programs.nix-ld.enable = true;

  # with `nix run .#gcroots`, gc keeps every host's build graph
  nix.settings.keep-outputs = true;

  # debug vm; secrets don't work in it
  virtualisation.vmVariant = {
    boot.initrd.luks.devices = lib.mkForce { };
    environment.etc.crypttab.enable = false;
    virtualisation = {
      memorySize = 8192;
      cores = 4;
    };
  };
  security.sudo.wheelNeedsPassword = false;
  system.stateVersion = "26.05";
}
