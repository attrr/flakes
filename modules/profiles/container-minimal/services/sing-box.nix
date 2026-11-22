{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.sing-box;
  jsonFormat = pkgs.formats.json { };
  nixosUtils = import "${inputs.nixpkgs}/nixos/lib/utils.nix" {
    inherit lib config pkgs;
  };

  singBoxPreStart = pkgs.writeShellScript "sing-box-pre-start" ''
    set -euo pipefail
    umask 0077

    ${nixosUtils.genJqSecretsReplacementSnippet cfg.settings "/run/sing-box/config.json"}
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
      user = "sing-box";
      group = "sing-box";
      runtime-dir = "sing-box";
      runtime-dir-mode = "0700";
      state-dir = "sing-box";
      state-dir-mode = "0700";
      reload-signal = "none";
      environment = {
        GOMEMLIMIT = lib.mkDefault "64MiB";
        GOGC = lib.mkDefault 50;
      };
      exec-start-pre = "${singBoxPreStart}";
      command = "${lib.getExe cfg.package} -D /var/lib/sing-box -C /run/sing-box run";
    };
  };
}
