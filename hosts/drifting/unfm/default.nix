{ self, ... }:
{
  imports = [
    "${self}/modules/ctx/server.nix"
    "${self}/modules/ctx/proxy.nix"
  ];

  infra.container.runtime = "podman";
}
