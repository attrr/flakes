{
  lib,
  config,
  ...
}:
let
  cfg = config.nixpkgs.allowUnfree;
in
{
  options.nixpkgs.allowUnfree = {
    enable = lib.mkEnableOption "allowlist-based unfree package predicate";
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
