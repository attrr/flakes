{ ctx, ... }:
let
  bao = ctx.services.openbao;
in
{
  # pin user for sops
  users.users.openbao = {
    isSystemUser = true;
    group = "openbao";
  };
  users.groups.openbao = { };
  sops.secrets."${bao.unseal-key.name}".owner = "openbao";

  services.openbao = {
    enable = true;
    settings = {
      ui = true;
      default_lease_ttl = "168h";
      max_lease_ttl = "720h";
      # api listener
      api_addr = "https://${bao.domain}";
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
        current_key = "file://${bao.unseal-key.path}";
      };
    };
  };

  core.acme.certs."${bao.domain}" = {
    reloadServices = [ "caddy.service" ];
  };

  # Wire the Caddy service to wait for the socket and Tailscale
  services.caddy = {
    enable = true;
    virtualHosts."${bao.domain}" = {
      listenAddresses = ctx.tailscale.ips;
      extraConfig = ''
        tls /var/lib/acme/${bao.domain}/cert.pem /var/lib/acme/${bao.domain}/key.pem
        reverse_proxy 127.0.0.1:8200
      '';
    };
  };

  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPorts = [
      80
      443
    ];
    allowedUDPPorts = [ 443 ];
  };
}
