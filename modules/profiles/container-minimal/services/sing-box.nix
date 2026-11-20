{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.sing-box;
  coreutils = config.programs.coreutils.package;
  jsonFormat = pkgs.formats.json { };
  nixosUtils = import "${inputs.nixpkgs}/nixos/lib/utils.nix" {
    inherit lib config pkgs;
  };

  singBoxWrapper = pkgs.writeShellScript "sing-box-start" ''
    set -euo pipefail
    umask 0077

    ${nixosUtils.genJqSecretsReplacementSnippet cfg.settings "/run/sing-box/config.json"}
    ${coreutils}/bin/chown sing-box:sing-box /var/lib/sing-box /run/sing-box /run/sing-box/config.json
    ${coreutils}/bin/chmod 0600 /run/sing-box/config.json

    exec ${coreutils}/bin/chpst -u sing-box:sing-box \
      ${lib.getExe cfg.package} -D /var/lib/sing-box -C /run/sing-box run
  '';
in
{
  options.services.sing-box = {
    enable = lib.mkEnableOption "sing-box universal proxy platform";

    package = lib.mkPackageOption pkgs "sing-box-minimal" { };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = jsonFormat.type;
      };
      default = { };
      description = "Declarative sing-box configuration rendered to JSON.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.sing-box = {
      group = "sing-box";
      home = "/var/lib/sing-box";
      description = "sing-box proxy daemon";
    };
    users.groups.sing-box = { };

    environment.systemPackages = [ cfg.package ];

    finit.services.sing-box = {
      description = "sing-box universal proxy platform";
      state-dir = "sing-box";
      state-dir-mode = "0700";
      runtime-dir = "sing-box";
      runtime-dir-mode = "0700";
      environment = {
        GOMEMLIMIT = "64MiB";
        GOGC = 50;
      };
      command = "${singBoxWrapper}";
      reload-triggers = [ singBoxWrapper ];
    };
  };
}
