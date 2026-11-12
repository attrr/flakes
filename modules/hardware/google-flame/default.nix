/*
  Pixel 4 (flame), on pkgs/linux-qcom-sm8150. Once, from fastboot: flash
  boot_a/boot_b with u-boot.img from pkgs/u-boot-google-flame; later ones
  go in as a capsule (./boot.nix). The system is a GPT (4K sectors) written
  into the userdata partition: bootstrap/images/flame.nix. ./debug.nix,
  for bring-up, is imported beside it when wanted
*/
{
  imports = [
    ./audio.nix
    ./battery.nix
    ./boot.nix
    ./charger.nix
    ./display.nix
    ./haptics.nix
    ./wireless.nix
  ];
}
