# disk layouts as options: infra.disko.layout picks ./<layout>.nix, called
# with device, espSize, imageSize (when set) and extraArgs
{ lib, config, ... }:
let
  cfg = config.infra.disko;
  layouts = map (lib.removeSuffix ".nix") (
    lib.filter (n: n != "default.nix" && lib.hasSuffix ".nix" n) (lib.attrNames (builtins.readDir ./.))
  );
in
{
  options.infra.disko = {
    layout = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum layouts);
      default = null;
    };
    device = lib.mkOption {
      type = lib.types.str;
    };
    espSize = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    imageSize = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    extraArgs = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Layout specific arguments, e.g. home, compress, swapSize.";
    };
  };

  # not mkIf: that still evaluates the import, for its attribute names
  config.disko =
    if cfg.layout == null then
      { }
    else
      (import ./${cfg.layout}.nix (
        {
          inherit (cfg) device;
        }
        // lib.filterAttrs (_: v: v != null) { inherit (cfg) espSize imageSize; }
        // cfg.extraArgs
      )).disko;
}
