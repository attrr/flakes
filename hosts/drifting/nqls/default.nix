{ self, ... }:
{
  imports = [
    "${self}/modules/ctx/server.nix"
    "${self}/modules/ctx/network.nix"
    "${self}/modules/ctx/proxy.nix"
  ];

  infra.container.runtime = "lxc";
  infra.network.topology = "static";
}
