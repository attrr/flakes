{
  config,
  lib,
  ...
}:
let
  cfg = config.infra.openbao;
in
{
  options.infra.openbao = {
    enable = lib.mkEnableOption "OpenBao with Raft storage, static unseal, and Caddy";

    domain = lib.mkOption {
      type = lib.types.str;
      description = "Domain for OpenBao API, Caddy virtualHost, and ACME cert";
    };

    unsealKeyFile = lib.mkOption {
      type = lib.types.str;
      description = "Path to static unseal key file";
    };

    listenAddresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Addresses Caddy virtualHost listens on";
    };
  };

  config = lib.mkIf cfg.enable {
    # pin user for sops
    users.users.openbao = {
      isSystemUser = true;
      group = "openbao";
    };
    users.groups.openbao = { };

    services.openbao = {
      enable = true;
      settings = {
        ui = true;
        default_lease_ttl = "168h";
        max_lease_ttl = "720h";
        # api listener
        api_addr = "https://${cfg.domain}";
        listener.tcp = {
          type = "tcp";
          address = "127.0.0.1:8200";
          tls_disable = true;
          x_forwarded_for_authorized_addrs = "127.0.0.1/32";
          x_forwarded_for_hop_skips = 0;
          x_forwarded_for_reject_not_present = true;
        };
        # for raft
        cluster_addr = "http://127.0.0.1:8201";
        storage.raft.path = "/var/lib/openbao";
        # static unseal
        seal.static = {
          current_key_id = "primary";
          current_key = "file://${cfg.unsealKeyFile}";
        };
      };
    };

    infra.acme.certs."${cfg.domain}" = { };

    # Wire the Caddy service to wait for the socket and Tailscale
    services.caddy = {
      enable = true;
      virtualHosts."${cfg.domain}" = {
        listenAddresses = cfg.listenAddresses;
        useACMEHost = cfg.domain;
        extraConfig = ''
          reverse_proxy 127.0.0.1:8200
        '';
      };
    };

    networking.firewall.interfaces.tailscale0 = lib.mkIf config.services.tailscale.enable {
      allowedTCPPorts = [
        80
        443
      ];
      allowedUDPPorts = [ 443 ];
    };
  };
}
