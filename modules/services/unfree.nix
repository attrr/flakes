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
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.config.allowUnfreePredicate =
      pkg: builtins.elem (lib.getName pkg) (map lib.getName cfg.packages);
  };
}
