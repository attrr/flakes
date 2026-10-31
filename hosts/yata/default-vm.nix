/*
  Cold standby for yata (nixosConfigurations.gateway).
  It carries yata's ssh host key and tailscale state, so it IS yata:
  same static IP, tailscale node, wg and sops identity. Never run both.

  To init:
  - nix run .\#bootstrap.images.gateway   (writes ./main.raw, contains yata's private keys)
  - boot main.raw as a VM with a bridged NIC on the LAN, after yata is down
*/
{
  imports = [
    ./profiles/full.nix
    ./hardware/vm.nix
  ];
}
