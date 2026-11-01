# What every host takes from its ctx entry. flake.nix (mkSystem) also picks
# imports from it: profiles/server + ./server.nix for the "server" tag,
# ./proxy.nix when a proxy service is enabled.
{ lib, ctx, ... }:
{
  nixpkgs.hostPlatform = lib.mkDefault ctx.metadata.arch;
}
