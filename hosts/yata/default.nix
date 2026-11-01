/*
  The Pi. To (re)flash it as yata, with its identity from ctx vars:
  - nix run .\#bootstrap.images.yata      (writes ./yata.img, contains yata's private keys)
  - dd it to the sd card: sudo dd if=yata.img of=/dev/<card> bs=4M status=progress
*/
{
  imports = [
    ./system.nix
    ./hardware/arm.nix
  ];
}
