{
  pkgs,
  ctx,
  lib,
  ...
}:
let
  wiki = ctx.services.mediawiki;
  domain = "wiki." + ctx.metadata.fdqn;
in
{
  # resolve conflict with minimal profile
  services.logrotate.enable = lib.mkForce true;

  sops.secrets.${wiki.admin-password.name}.owner = "mediawiki";
  services.mediawiki = {
    enable = true;
    name = "Wiki";
    httpd.virtualHost.listen = [
      {
        ip = "127.0.0.1";
        port = 8080;
        ssl = false;
      }
    ];
    httpd.virtualHost.extraConfig = ''
      RewriteEngine On
      RewriteRule ^/wiki(/.*)?$ /index.php [L,QSA]
    '';

    passwordFile = wiki.admin-password.path;
    passwordSender = "no-reply@localhost";
    extraConfig = ''
      $wgServer = "https://${domain}";
      $wgScriptPath = "";
      $wgArticlePath = "/wiki/$1";
      $wgGroupPermissions['sysop']['deleterevision'] = true;

      # provide lua binary
      $wgScribuntoDefaultEngine = 'luastandalone';
      $wgScribuntoEngineConf['luastandalone']['luaPath'] = '${pkgs.lua5_1}/bin/lua';

      # Disable anonymous users
      $wgGroupPermissions['*']['edit'] = false;
      $wgGroupPermissions['*']['createaccount'] = false;
    '';

    extensions = {
      ParserFunctions = null;
      Scribunto = null;

      # editor
      WikiEditor = null;
      CodeEditor = null;
      TemplateData = null;

      Math = null;
      Interwiki = null;
      SyntaxHighlight_GeSHi = null;
      Cite = null;
      CiteThisPage = null;
      ConfirmEdit = null;
      Gadgets = null;
      ImageMap = null;
      InputBox = null;
      Nuke = null;
      Poem = null;

      Cargo = pkgs.fetchzip {
        url = "https://github.com/wikimedia/mediawiki-extensions-Cargo/archive/refs/heads/REL1_44.zip";
        hash = "sha256-F1vPo9Tmb+D4AMU77CTm7w3jfJ8Ra2U0133XODWpEjI=";
      };
      CSS = pkgs.fetchzip {
        url = "https://github.com/wikimedia/mediawiki-extensions-CSS/archive/refs/heads/REL1_44.zip";
        hash = "sha256-+Jjt5c1cEObQN9/s1ipPxviAfGeoq2vSHSjwzbiR5PI=";
      };
      NoTitle = pkgs.fetchzip {
        url = "https://github.com/wikimedia/mediawiki-extensions-NoTitle/archive/refs/heads/REL1_44.zip";
        hash = "sha256-7DAFNTJWthas5n2haUEzKu/nNsEGuFbaFCgTHFg9UkQ=";
      };
    };
  };

  services.mysql = {
    enable = true;
    package = pkgs.mariadb;
  };

  core.acme.certs."${ctx.metadata.fdqn}" = {
    reloadServices = [ "caddy.service" ];
  };

  services.caddy.virtualHosts."${domain}" = {
    listenAddresses = ctx.tailscale.ips;
    extraConfig = ''
      tls /var/lib/acme/${ctx.metadata.fdqn}/cert.pem /var/lib/acme/${ctx.metadata.fdqn}/key.pem
      reverse_proxy 127.0.0.1:8080
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
