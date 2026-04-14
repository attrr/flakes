{
  pkgs,
  config,
  global,
  ctx,
  lib,
  ...
}:
let
  wiki = ctx.services.mediawiki;
  domain = "wiki." + global.domain.main;
  domain-lobba = "lobba." + domain;
  extensions = pkgs.callPackage ../../pkgs/mediawiki-extensions { };

  user = "mediawiki";
  group = config.services.httpd.group;
  state-dir = "/var/lib/mediawiki";
  uploads-dir = state-dir + "/uploads";
in
{
  # resolve conflict with minimal profile
  services.logrotate.enable = lib.mkForce true;

  # ensure database
  services.mysql = {
    enable = true;
    package = pkgs.mariadb;
    ensureDatabases = [
      "lobba"
      "main"
    ];
    ensureUsers = [
      {
        name = "mediawiki";
        ensurePermissions = {
          "lobba.*" = "ALL PRIVILEGES";
          "main.*" = "ALL PRIVILEGES";
        };
      }
    ];
  };

  # reverse proxy
  core.acme.certs."${domain}" = {
    inherit domain;
    extraDomainNames = [
      "*.${domain}"
    ];
    reloadServices = [ "caddy.service" ];
  };
  services.caddy.virtualHosts =
    let
      target-config = {
        listenAddresses = ctx.tailscale.ips;
        extraConfig = ''
          reverse_proxy 127.0.0.1:8080
          tls /var/lib/acme/${domain}/cert.pem /var/lib/acme/${domain}/key.pem
        '';
      };
    in
    {
      "${domain}" = target-config;
      "${domain-lobba}" = target-config;
    };
  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPorts = [
      80
      443
    ];
    allowedUDPPorts = [ 443 ];
  };

  # wiki
  sops.secrets.${wiki.admin-password.name}.owner = "mediawiki";
  services.mediawiki.httpd.virtualHost = {
    listen = [
      {
        ip = "127.0.0.1";
        port = 8080;
        ssl = false;
      }
    ];
    extraConfig = ''
      RewriteEngine On
      RewriteRule ^/wiki(/.*)?$ /index.php [L,QSA]
    '';
  };

  services.mediawiki = {
    enable = true;
    name = "Wiki";
    database = {
      name = "main";
      user = "mediawiki";
      socket = "/run/mysqld/mysqld.sock";
      createLocally = false;
    };

    passwordFile = wiki.admin-password.path;
    passwordSender = "no-reply@localhost";
    extraConfig = ''
      $wgScriptPath = "";
      $wgArticlePath = "/wiki/$1";
      $wgDefaultMobileSkin = 'minerva';
      $wgGroupPermissions['sysop']['deleterevision'] = true;
      # relative link at mainpage
      $wgNamespacesWithSubpages[NS_MAIN] = true;

      # provide lua binary
      $wgScribuntoDefaultEngine = 'luastandalone';
      $wgScribuntoEngineConf['luastandalone']['luaPath'] = '${pkgs.lua5_1}/bin/lua';

      # disable anonymous users
      $wgGroupPermissions['*']['edit'] = false;
      $wgGroupPermissions['*']['createaccount'] = false;

      # default logo
      $wgLogos = [
          '1x'  => '/resources/assets/mediawiki.png',
          'svg' => '/resources/assets/mediawiki.png',
          'icon' => '/resources/assets/mediawiki.png',
      ];

      # determine db name
      $wikis = [
        '${domain}' => 'main',
        '${domain-lobba}' => 'lobba',
      ];
      if ( defined( 'MW_DB' ) ) {
        // Automatically set from --wiki option to maintenance scripts
        $wgDBname = MW_DB;
      } else {
        // Use MW_DB environment variable or map the domain name
          $wgDBname = $_SERVER['MW_DB'] ?? $wikis[ $_SERVER['HTTP_HOST'] ?? ''' ] ?? null;
        if ( !$wgDBname ) {
            die( 'Unknown wiki.' );
        }
      }

      # per-site config dispatcher
      $wgConf->settings = [
          'wgServer' => [
              'default' => 'https://' . $_SERVER['HTTP_HOST'],
          ],
          'wgArticlePath' => [
              'default' => '/wiki/$1',
          ],
          'wgSitename' => [
              'lobba' => 'LobbaWiki',
              'main' => 'MainWiki',
          ],
          'wgUploadDirectory' => [
              'lobba' => '${uploads-dir}/lobba',
              'main'  => '${uploads-dir}/main',
          ],
          'wgUploadPath' => [
              'lobba' => '/images/lobba',
              'main'  => '/images/main',
          ],
          'wgLanguageCode' => [
              // 'foowiki' => 'pt',
          ],
      ];
      extract( $wgConf->getAll( $wgDBname ) );
    '';

    extensions = {
      ParserFunctions = null;
      Scribunto = null;

      # editor
      WikiEditor = null;
      CodeEditor = null;
      VisualEditor = null;
      TemplateData = null;

      # ui
      CategoryTree = null;
      MultimediaViewer = null;

      # format
      Math = null;
      Poem = null;
      TemplateStyles = null;
      SyntaxHighlight_GeSHi = null;

      # ref
      Interwiki = null;
      Cite = null;
      CiteThisPage = null;

      # utils
      Nuke = null;
      Gadgets = null;
      ImageMap = null;
      InputBox = null;

      inherit (extensions)
        Cargo
        CSS
        NoTitle
        MobileFrontend
        ;
    };

    skins = {
      inherit (extensions) MinervaNeue;
    };
  };

  systemd.tmpfiles.rules =
    lib.concatMap
      (dir: [
        "d '${dir}' 0750 ${user} ${group} - -"
        "Z '${dir}' 0750 ${user} ${group} - -"
      ])
      [
        "${uploads-dir}/main"
        "${uploads-dir}/lobba"
      ];
}
