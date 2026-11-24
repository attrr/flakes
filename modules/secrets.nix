# Backend-agnostic `infra.secrets` declarations + sops adapter.
{
  common =
    { config, lib, ... }:
    let
      prefix = "/run/secrets/";
      entries = builtins.filter (
        e: e.path != null && lib.hasPrefix prefix (toString e.path)
      ) config.infra.secrets;
    in
    {
      options.infra.secrets = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              path = lib.mkOption {
                type = lib.types.nullOr (lib.types.either lib.types.path lib.types.str);
                default = null;
              };
              owner = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
              reloadUnits = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
              };
              restartUnits = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
              };
            };
          }
        );
        default = [ ];
      };

      config.sops.secrets = lib.mkMerge (
        map (e: {
          ${lib.removePrefix prefix (toString e.path)} =
            lib.optionalAttrs (e.owner != null) { owner = lib.mkDefault e.owner; }
            // lib.optionalAttrs (e.reloadUnits != [ ]) { inherit (e) reloadUnits; }
            // lib.optionalAttrs (e.restartUnits != [ ]) { inherit (e) restartUnits; };
        }) entries
      );
    };
}
