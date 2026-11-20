{
  config,
  options,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.sops;
  upstream = import "${inputs.sops-nix}/modules/sops/default.nix" {
    inherit
      config
      options
      lib
      pkgs
      ;
  };
  secretList = lib.attrValues cfg.secrets;
  secretDst = s: "/var/lib/secrets/${lib.removePrefix "/run/secrets/" s.path}";
  secretUser = s: if s.owner != null then s.owner else toString s.uid;
  secretGroup = s: if s.group != null then s.group else toString s.gid;
in
{
  inherit (upstream) options;

  config = lib.mkIf (cfg.secrets != { }) {
    finit.tmpfiles.rules = [
      "d /var/lib/secrets 0751 - -"
      "L+ /run/secrets - - - - /var/lib/secrets"
    ]
    ++ map (s: "z ${secretDst s} ${s.mode} ${secretUser s} ${secretGroup s}") secretList;
  };
}
