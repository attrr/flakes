{
  ctx,
  global,
  lib,
  ...
}:
let
  acme = ctx.services.acme-dns;
  knot = ctx.services.knot;
in
{
  sops.secrets."${knot.tsig-key.name}".owner = "knot";
  # acme-dns for DNS-01
  services.acme-dns = {
    enable = true;
    settings = {
      general = {
        # use ns. domain to avoid loop
        listen = "${lib.head ctx.network.ipv4.addresses}:53";
        domain = acme.ns-domain;
        nsname = acme.ns-domain;
        nsadmin = "hostmaster.${global.domain.main}";
        records = [
          "${acme.ns-domain}. A  ${lib.head ctx.network.ipv4.addresses}"
          "${acme.ns-domain}. NS ${acme.ns-domain}."
        ];
      };
      api = {
        ip = "127.0.0.1";
        port = acme.port;
        tls = "none";
        use_header = true;
        header_name = "X-Forwarded-For";
        disable_registration = false;
      };
    };
  };

  core.acme.certs."${acme.domain}" = {
    reloadServices = [ "caddy.service" ];
  };
  services.caddy = {
    enable = true;
    virtualHosts."${acme.domain}" = {
      listenAddresses = ctx.tailscale.ips;
      extraConfig = ''
        tls /var/lib/acme/${acme.domain}/cert.pem /var/lib/acme/${acme.domain}/key.pem
        reverse_proxy 127.0.0.1:${toString acme.port}
      '';
    };
  };

  # Authorize DNS server
  services.knot =
    let
      listenAddrs = map (s: s + "@53") ctx.tailscale.ips;
      slavsIPs = knot.slave-ips;
    in
    {
      enable = true;
      keyFiles = [ knot.tsig-key.path ];

      settings = {

        server = {
          listen = listenAddrs;
          user = "knot";
        };
        log = [
          {
            target = "syslog";
            any = "info";
          }
        ];

        policy = [
          {
            id = "standard";
            algorithm = "ed25519";
            ksk-lifetime = "365d";
            zsk-lifetime = "30d";
            propagation-delay = "1h";
          }
        ];

        mod-rrl = [
          {
            id = "default";
            rate-limit = 100; # 100 resp/s
            slip = 2;
          }
        ];
        mod-cookies = [
          {
            id = "default";
            secret-lifetime = "30h";
            badcookie-slip = 3;
          }
        ];

        template.default = {
          global-module = [
            "mod-rrl/default"
            "mod-cookies/default"
          ];
          storage = "/var/lib/knot/zones";
          serial-policy = "dateserial";
          default-ttl = 3600;
          dnssec-signing = "on";
          dnssec-policy = "standard";
          semantic-checks = "on";
        };

        zone = [
          {
            domain = global.domain.main;
            file = "${global.domain.main}.zone";
            notify = [ "slave" ];
            acl = [ "allow-transfer" ];
            zonefile-load = "difference";
          }
        ];

        # slave
        remote = [
          {
            id = "slave";
            address = slavsIPs;
            key = "transfer-key";
          }
        ];
        acl = [
          {
            id = "allow-transfer";
            address = slavsIPs;
            action = "transfer"; # Allow AXFR/IXFR
            key = [ "transfer-key" ]; # Only allow if IP matches AND the TSIG key is valid
          }
        ];
      };
    };

  networking.firewall = {
    # acme-dns public facing ns
    allowedUDPPorts = [ 53 ];
    interfaces.tailscale0 = {
      allowedTCPPorts = [
        53
        80
        443
      ];
      allowedUDPPorts = [
        53
        443
      ];
    };
  };
}
