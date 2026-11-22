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
  secretsWithRestart = lib.filter (s: s.restartUnits != [ ]) secretList;
in
{
  inherit (upstream) options;

  config = lib.mkIf (cfg.secrets != { }) {
    finit.tmpfiles.rules = [
      "d /var/lib/secrets 0751 - -"
      "L+ /run/secrets - - - - /var/lib/secrets"
    ]
    ++ map (s: "z ${secretDst s} ${s.mode} ${secretUser s} ${secretGroup s}") secretList;

    system.activation.scripts.sopsRestartUnits = lib.mkIf (secretsWithRestart != [ ]) {
      deps = [
        "tmpfiles-z"
      ];
      text = ''
        mkdir -p /run/sops-hashes
        _sops_restart_units=""

        check_secret() {
          _dst=$1
          _stamp=$2
          shift 2
          [ -f "$_dst" ] || return 0
          _cur=$(sha256sum "$_dst" | cut -d' ' -f1)
          _prev=""
          [ -f "$_stamp" ] && _prev=$(cat "$_stamp")
          [ "$_cur" != "$_prev" ] || return 0
          printf '%s\n' "$_cur" > "$_stamp"
          for _u in "$@"; do
            case " $_sops_restart_units " in
              *" $_u "*) ;;
              *) _sops_restart_units="$_sops_restart_units $_u" ;;
            esac
          done
        }

        ${lib.concatMapStringsSep "\n" (
          s:
          let
            dst = secretDst s;
            stamp = "/run/sops-hashes/${builtins.hashString "sha256" dst}";
            units = lib.escapeShellArgs (map (lib.removeSuffix ".service") s.restartUnits);
          in
          "check_secret ${lib.escapeShellArg dst} ${stamp} ${units}"
        ) secretsWithRestart}

        for _u in $_sops_restart_units; do
          if [ -S /run/finit/socket ]; then
            ${config.finit.package}/bin/initctl restart "$_u" || true
          fi
        done
      '';
    };
  };
}
