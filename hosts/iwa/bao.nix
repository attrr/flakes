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

  systemd.sockets.caddy = {
    description = "Caddy Tailscale Sockets";
    wantedBy = [ "sockets.target" ];

    listenStreams = [
      "80"
      "443"
    ];
    listenDatagrams = [
      "443"
    ];

    socketConfig = {
      FreeBind = true;
      BindToDevice = "tailscale0";
      Service = "caddy.service";
    };
  };

  # 2. Wire the Caddy service to wait for the socket and Tailscale
  systemd.services.caddy = {
    wants = [ "caddy.socket" ];
    after = [
      "caddy.socket"
      "tailscaled.service"
    ];
  };
  services.caddy = {
    enable = true;
    virtualHosts."${bao.domain}" = {
      # listenAddresses = ctx.tailscale.ips;
      extraConfig = ''
        tls /var/lib/acme/${bao.domain}/cert.pem /var/lib/acme/${bao.domain}/key.pem
        reverse_proxy 127.0.0.1:8200
      '';
    };
    globalConfig = ''
      default_bind fd/4 {
        protocols h1 h2
      }

      # 3rd socket in the file caddy.socket
      default_bind fdgram/5 {
        protocols h3
      }
      admin localhost:2019
      auto_https disable_redirects
    '';
    extraConfig = ''
      http:// {
        # 1st socket in the file caddy.socket
        bind fd/3 {
          protocols h1
        }
        redir https://{host}{uri}
        log
      }
    '';
  };
  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPorts = [
      80
      443
    ];
    allowedUDPPorts = [ 443 ];
  };
}
