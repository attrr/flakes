{ self, ... }:
{
  imports = [
    "${self}/modules/profiles/container"
    "${self}/modules/ctx/server.nix"
  ];

  infra.container.runtime = "podman";
  infra.server.hostname = "debian";
  system.stateVersion = "26.05";
}
