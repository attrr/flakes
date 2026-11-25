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
  moduleList = import ./module-list.nix;
in
{
  nixosModules.default = {
    imports = aspectLib.resolveModule "nixos" (moduleList.common ++ moduleList.nixos);
  };

  finixModules.default = {
    imports = aspectLib.resolveModule "finix" (moduleList.common ++ moduleList.finix);
  };

  modules = lib.genAttrs [
    "nixos"
    "finix"
    "homeManager"
  ] (c: lib.mapAttrs (_: aspectLib.asModule c) profiles);
}
