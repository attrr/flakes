{ ctx, ... }:
let
  acme = ctx.services.acme-dns;
  local-port = 8080;
  local-url = "http://127.0.0.1:${toString local-port}";
in
{
  imports = [
    ../../modules/purpose/acme.nix
  ];

  # acme-dns for DNS-01
  services.acme-dns = {
    enable = true;
    settings = {
      general = {
        # prepend ns. domain to avoid loop
        listen = "[${acme.address}]:53";
        domain = acme.ns-domain;
        nsname = acme.ns-domain;
        nsadmin = acme.ns-admin;
        records = [
          "${acme.ns-domain}. A  ${acme.address}"
          "${acme.ns-domain}. NS ${acme.ns-domain}."
        ];
      };
      api = {
        ip = "127.0.0.1";
        port = local-port;
        tls = "none";
        use_header = true;
        header_name = "X-Forwarded-For";
        disable_registration = false;
      };
    };
  };

  core.acme = {
    enable = true;
    # use local url to avoid chicken egg problem
    api = local-url;
    certs."${acme.domain}" = {
      reloadServices = [ "caddy.service" ];
    };
  };

  services.caddy = {
    enable = true;
    virtualHosts."${acme.domain}" = {
      listenAddresses = ctx.tailscale.ips;
      extraConfig = ''
        tls /var/lib/acme/${acme.domain}/cert.pem /var/lib/acme/${acme.domain}/key.pem
        reverse_proxy 127.0.0.1:${toString local-port}
      '';
    };
  };

  networking.firewall.allowedUDPPorts = [ 53 ];
  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPorts = [
      80
      443
    ];
    allowedUDPPorts = [ 443 ];
  };
}
