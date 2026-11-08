/*
  The Pi. To (re)flash it as yata, with its identity from ctx vars:
  - nix run .\#bootstrap.images.yata      (writes ./yata.img, contains yata's private keys)
  - dd it to the sd card: sudo dd if=yata.img of=/dev/<card> bs=4M status=progress
*/
{
  inputs,
  self,
  lib,
  ...
}:
let
  native = inputs.nixpkgs.legacyPackages.x86_64-linux.extend self.overlays.default;
  cross = native.pkgsCross.aarch64-multiplatform;

  # a cross build's go-modules has the target as a name suffix, so a store path
  # of its own and no cache; take the native one, from the final src/vendorHash
  # (a mismatch still fails on the hash)
  crossGo =
    name:
    cross.${name}.overrideAttrs (
      finalAttrs: _: {
        goModules =
          (native.${name}.overrideAttrs {
            inherit (finalAttrs) version src vendorHash;
            postPatch = finalAttrs.postPatch or "";
          }).goModules;
      }
    );
in
{
  imports = [
    ./system.nix
    ./hardware/arm.nix
  ];

  # the Go builds, natively on the x86 deployer instead of under binfmt
  nixpkgs.overlays = lib.mkAfter [
    (_: _: {
      sing-box = crossGo "sing-box";
      loadbalance = crossGo "loadbalance";
    })
  ];
}
