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
  classModules = {
    nixos = moduleList.common ++ moduleList.os ++ moduleList.nixos;
    finix = moduleList.common ++ moduleList.os ++ moduleList.finix;
    homeManager = moduleList.common ++ moduleList.homeManager;
  };

  forClass =
    class: base: lib.mapAttrs (_: aspectLib.asModule class) (profiles // { default = base; });
in
{
  nixosModules.default.imports = aspectLib.resolveModule "nixos" classModules.nixos;
  finixModules.default.imports = aspectLib.resolveModule "finix" classModules.finix;
  modules = lib.mapAttrs forClass classModules;
}
