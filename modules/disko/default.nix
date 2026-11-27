# disk layouts as options: infra.disko.layout picks ./<layout>.nix, called
# with device, espSize, imageSize (when set) and extraArgs
{ lib, config, ... }:
let
  cfg = config.infra.disko;
  layouts = map (lib.removeSuffix ".nix") (
    lib.filter (n: n != "default.nix" && lib.hasSuffix ".nix" n) (lib.attrNames (builtins.readDir ./.))
  );
  autoResize = cfg.layout != null && cfg.layout != "luks-lvm-btrfs-subvol";
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

  config = {
    # not mkIf: that still evaluates the import, for its attribute names
    disko =
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

    boot.growPartition = lib.mkIf autoResize (lib.mkDefault true);
    fileSystems."/".autoResize = lib.mkIf autoResize (lib.mkDefault true);
  };
}
