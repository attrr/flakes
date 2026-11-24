{ lib }:
let
  aspectLib = import ../lib/aspects.nix { inherit lib; };

  discover =
    dir:
    lib.concatMapAttrs (
      name: type:
      if type == "regular" && lib.hasSuffix ".nix" name then
        { ${lib.removeSuffix ".nix" name} = dir + "/${name}"; }
      else if type == "directory" && builtins.pathExists (dir + "/${name}/default.nix") then
        { ${name} = dir + "/${name}"; }
      else
        { }
    ) (builtins.readDir dir);

  profiles = discover ./profiles;
in
{
  nixosModules.default = {
    imports = aspectLib.resolveModule "nixos" (import ./module-list.nix);
  };

  modules = lib.genAttrs [
    "nixos"
    "finix"
    "homeManager"
  ] (c: lib.mapAttrs (_: aspectLib.asModule c) profiles);
}
