/*
  To init:
  nix build .\#nixosConfigurations.${hostname}.config.system.build.diskoImagesScript
  ./result --post-format-files path-to-age.key /var/lib/sops-nix/keys.txt
*/
{
  imports = [
    ./profiles/full.nix
    ./hardware/vm.nix
  ];

  sops.age.keyFile = "/var/lib/sops-nix/keys.txt";
}
