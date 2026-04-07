{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.core.acme;
in
{
  options.core.acme = {
    enable = lib.mkEnableOption "Enable acme services over acme-dns server";
    api = lib.mkOption {
      type = lib.types.str;
      description = "The base URL for the acme-dns API.";
    };
    certs = lib.mkOption {
      default = { };
      # submodule+freeformType for args passing
      type = lib.types.attrsOf (
        lib.types.submodule {
          freeformType = lib.types.attrsOf lib.types.anything;
          options = { }; # current empty
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    security.acme = {
      acceptTerms = true;
      defaults.email = "";
      certs = lib.mapAttrs (
        name: value:
        value
        // {
          dnsProvider = "acme-dns";
          environmentFile = pkgs.writeText "acme-env-${name}" ''
            ACME_DNS_API_BASE=${cfg.api}
            ACME_DNS_STORAGE_PATH=/var/lib/acme/${name}/accounts.json
          '';
          extraLegoFlags = [ "--dns.propagation-disable-ans" ] ++ (value.extraLegoFlags or [ ]);
          # default to caddy
          group = value.group or config.services.caddy.group;
        }
      ) cfg.certs;
    };
  };
}
