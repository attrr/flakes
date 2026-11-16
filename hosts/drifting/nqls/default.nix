{ self, ... }:
{
  imports = [
    "${self}/modules/ctx/server.nix"
  ];

  infra.network.topology = "static";
}
