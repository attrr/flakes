{ self, ... }:
{
  imports = [
    "${self}/modules/ctx/server.nix"
    "${self}/modules/ctx/proxy.nix"
    "${self}/modules/ctx/telemetry.nix"
  ];

  infra.container.runtime = "podman";
}
