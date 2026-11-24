{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.infra.desktop;
  pcfg = cfg.printing;
in
{
  options.infra.desktop.printing = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable CUPS printing support.";
    };

    hp = lib.mkEnableOption "HP printer and scanner support (unfree hplipWithPlugin)";
    epson = lib.mkEnableOption "Epson scanner support (unfree epkowa)";
  };

  config = lib.mkMerge [
    (lib.mkIf pcfg.enable {
      services.printing.enable = true;
      hardware.sane.enable = true;
      users.users."${cfg.primaryUser}".extraGroups = [
        "lp"
        "scanner"
      ];
    })

    (lib.mkIf pcfg.hp {
      nixpkgs.allowUnfree = {
        enable = true;
        packages = [ pkgs.hplipWithPlugin ];
      };

      # run on first setup: sudo hp-setup -i -a
      services.printing.drivers = [ pkgs.hplipWithPlugin ];
      environment.systemPackages = [ pkgs.hplipWithPlugin ];
      hardware.sane.extraBackends = [ pkgs.hplipWithPlugin ];
    })

    (lib.mkIf pcfg.epson {
      nixpkgs.allowUnfree = {
        enable = true;
        packages = [ pkgs.epkowa ] ++ lib.attrValues pkgs.epkowa.plugins;
        names = [ "iscan-data" ];
      };

      hardware.sane.extraBackends = [ pkgs.epkowa ];
    })
  ];
}
