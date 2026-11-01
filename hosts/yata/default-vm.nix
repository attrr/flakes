/*
  Cold standby for yata (nixosConfigurations."yata+vm").
  It carries yata's ssh host key and tailscale state, so it IS yata:
  same static IP, tailscale node, wg and sops identity. Never run both.

  To init:
  - nix run .\#bootstrap.images.yata+vm   (writes ./yata+vm.qcow2, contains yata's private keys)
  - boot it as a VM with a bridged NIC on the LAN, after yata is down
*/
{
  imports = [
    ./system.nix
    ./hardware/vm.nix
  ];
}
