{
  lib,
  config,
  ...
}:
let
  cfg = config.allowUnfree;
in
{
  options.allowUnfree = {
    enable = lib.mkEnableOption "enable";
    packages = lib.mkOption {
      default = [ ];
      type = lib.types.listOf lib.types.package;
    };
    names = lib.mkOption {
      default = [ ];
      type = lib.types.listOf lib.types.str;
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.config.allowUnfreePredicate =
      pkg: builtins.elem (lib.getName pkg) (cfg.names ++ map lib.getName cfg.packages);
  };
}
