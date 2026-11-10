/*
  Pixel 4 (flame): modules/hardware/google-flame. To (re)flash it as flame,
  with its identity from ctx vars:
  - nix run .\#bootstrap.images.flame     (writes ./flame.img, contains flame's private keys)
  - fastboot flash userdata flame.img
  Reachable over USB (NCM) at 172.16.42.1
*/
{
  ctx,
  inputs,
  lib,
  self,
  ...
}:
let
  native = import inputs.nixpkgs {
    system = "x86_64-linux";
    overlays = [ self.overlays.default ];
    # pkgs/firmware-google-flame's blobs; not the NixOS config's, which
    # this set doesn't see
    config.allowUnfreePredicate = pkg: lib.getName pkg == "firmware-google-flame";
  };
  cross = native.pkgsCross.aarch64-multiplatform;
in
{
  imports = [
    "${self}/modules/profiles/base"
    "${self}/modules/hardware/google-flame"
    "${self}/modules/hardware/google-flame/debug.nix"
    ./phosh.nix
  ];

  # the device's own builds, natively on the x86 deployer instead of under
  # binfmt. After the flake's own overlay, which would put pkgs/'s back
  nixpkgs.overlays = lib.mkAfter [
    (_: _: {
      inherit (cross) firmware-google-flame linux-qcom-sm8150 u-boot-google-flame;
    })
  ];

  system.stateVersion = "26.05";

  networking.hostName = ctx.metadata.hostname;

  services.openssh = {
    enable = true;
    ports = ctx.ssh.ports;
    users.foo.authorizedKeys = ctx.ssh.auth-keys;
    lockRootLogin = true;
  };

  # USB gadget, as pmOS sets it up (its VID:PID)
  systemd.services.usb-gadget = {
    description = "USB network gadget";
    wantedBy = [ "multi-user.target" ];
    requires = [ "sys-kernel-config.mount" ];
    after = [ "sys-kernel-config.mount" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      g=/sys/kernel/config/usb_gadget/g1
      mkdir -p $g/strings/0x409 $g/functions/ncm.usb0 $g/configs/c.1
      echo 0x18d1 > $g/idVendor
      echo 0x4ee3 > $g/idProduct
      echo NixOS > $g/strings/0x409/manufacturer
      echo flame > $g/strings/0x409/product
      ln -sfn $g/functions/ncm.usb0 $g/configs/c.1/
      ls /sys/class/udc > $g/UDC
    '';
  };

  networking.useNetworkd = true;
  systemd.network.networks."10-usb" = {
    matchConfig.Name = "usb0";
    address = [ "172.16.42.1/24" ];
    networkConfig.DHCPServer = true;
    linkConfig.RequiredForOnline = "no";
  };
  networking.firewall.interfaces.usb0.allowedUDPPorts = [ 67 ];
  # NetworkManager comes with phosh; usb0 stays networkd's
  networking.networkmanager.unmanaged = [ "usb0" ];
}
