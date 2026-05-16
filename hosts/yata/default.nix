/*
  To init:
  - nix build .\#sdimages.$hostname
  - flash sdcard image:
  -> sudo dd if=result/sd-image/nixos-image-sd-card-*-aarch64-linux.img of=/dev/path-to-usb bs=4M status=progress
  - generate age keys from living system's ssh public key
  -> ssh $hostname cat /etc/ssh/ssh_host_ed25519_key.pub | nix-shell -p ssh-to-age --run ssh-to-age
  - deploy full config again
*/
{
  imports = [
    ./profiles/full.nix
    ./hardware/arm.nix
  ];
}
