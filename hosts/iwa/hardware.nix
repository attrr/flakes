{ modulesPath, pkgs, ... }:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/profiles/headless.nix")
  ];

  boot.initrd.systemd.enable = true;

  boot.initrd.kernelModules = [ "virtio_scsi" ];
  boot.kernelModules = [
    "virtio_pci"
    "virtio_net"
  ];
  networking.interfaces.eth0.mtu = 1460;
  networking.timeServers = [ "metadata.google.internal" ];
  networking.extraHosts = ''
    169.254.169.254 metadata.google.internal metadata
  '';
  services.udev.packages = [ pkgs.google-guest-configs ];
  environment.etc."sysctl.d/60-gce-network-security.conf".source =
    "${pkgs.google-guest-configs}/etc/sysctl.d/60-gce-network-security.conf";

  # Enable GRUB for serial port
  boot.loader.grub = {
    extraConfig = ''
      serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1
      terminal_input serial console
      terminal_output serial console
    '';
  };
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "earlyprintk=ttyS0,115200"
    "rd.systemd.show_status=auto"
  ];
  systemd.services."serial-getty@ttyS0" = {
    enable = true;
    wantedBy = [ "getty.target" ];
    serviceConfig.Restart = "always";
  };
}
