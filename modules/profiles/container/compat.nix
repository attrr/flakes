# Workarounds for LXC containers running on older host kernels (< 5.10, e.g. RHEL 8 4.18)
# pinned to nixos-25.11 instead of importing the full 26.05 module-list.
{
  inputs,
  lib,
  pkgs,
  pkgsMainline,
  self,
  ...
}:
{
  imports = [
    ./.
    "${self}/modules/network"
    "${self}/modules/services/alerts.nix"
    "${self}/modules/services/sing-box"
    "${self}/modules/services/tunnelbroker"
    "${self}/modules/services/ssh.nix"
    "${self}/modules/services/unfree.nix"
  ];

  # Satisfy profiles/server's `infra.containers.enable` without importing services/containers.nix.
  options.infra.containers.enable = lib.mkEnableOption "containers (shim)";

  config = {
    system.stateVersion = lib.mkDefault "25.11";

    # Pin sing-box and usque to mainline nixpkgs so modules/services/sing-box/ stays on one schema/CLI.
    nixpkgs.overlays = [
      (_: _: {
        inherit (pkgsMainline) sing-box usque;
      })
    ];

    # sops-nix follows mainline nixpkgs (go >= 1.26), which 25.11's go cannot build.
    sops.package = inputs.sops-nix.packages.${pkgs.stdenv.hostPlatform.system}.sops-install-secrets;

    # Kernel < 5.3 lacks RTM_GETNEXTHOP; systemd-networkd >= 258 exits with EOPNOTSUPP.
    networking.useNetworkd = lib.mkOverride 900 false;
  };
}
