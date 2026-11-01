# What every host takes from its ctx entry. flake.nix (mkSystem) also picks
# imports from it: profiles/<tag> + ./<tag>.nix per tag, ./providers/<provider>.nix.
{ lib, ctx, ... }:
{
  nixpkgs.hostPlatform = lib.mkDefault ctx.metadata.arch;
}
