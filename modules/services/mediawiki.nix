{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.infra.mediawiki;
  extensions = pkgs.mediawiki-extensions;

  user = "mediawiki";
  group = config.services.httpd.group;
  state-dir = "/var/lib/mediawiki";
  uploads-dir = state-dir + "/uploads";

  sitesList = lib.mapAttrsToList (domain: site: { inherit domain; } // site) cfg.sites;
  dbNames = lib.unique (map (s: s.dbName) sitesList);

  target-config = {
    listenAddresses = cfg.listenAddresses;
    useACMEHost = cfg.domain;
    extraConfig = ''
      reverse_proxy 127.0.0.1:${toString cfg.httpdPort}
    '';
  };

  phpAssoc = attrs: lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "        '${k}' => '${v}',") attrs);
in
{
  options.infra.mediawiki = {
    enable = lib.mkEnableOption "MediaWiki with MariaDB, Caddy, and multi-site dispatch";

    domain = lib.mkOption {
      type = lib.types.str;
      description = "Primary wiki domain (used for ACME wildcard cert)";
    };

    sites = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            dbName = lib.mkOption {
              type = lib.types.str;
              description = "MariaDB database name for this wiki site";
            };
            sitename = lib.mkOption {
              type = lib.types.str;
              description = "MediaWiki $wgSitename";
            };
          };
        }
      );
      default = {
        "${cfg.domain}" = {
          dbName = "main";
          sitename = "MainWiki";
        };
      };
      description = "Map of wiki domain -> database and sitename";
    };

    adminPasswordFile = lib.mkOption {
      type = lib.types.str;
      description = "Path to initial MediaWiki admin password file";
    };

    listenAddresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Addresses Caddy virtualHosts listen on";
    };

    httpdPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Internal Apache/httpd port proxied by Caddy";
    };

    backup.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable restic backup for MediaWiki when infra.restic is enabled";
    };
  };

  config = lib.mkIf cfg.enable {
    # resolve conflict with minimal profile
    services.logrotate.enable = lib.mkForce true;

    # ensure database
    services.mysql = {
      enable = true;
      package = pkgs.mariadb;
      ensureDatabases = dbNames;
      ensureUsers = [
        {
          name = "mediawiki";
          ensurePermissions = lib.listToAttrs (
            map (db: lib.nameValuePair "${db}.*" "ALL PRIVILEGES") dbNames
          );
        }
      ];
    };

    # reverse proxy
    infra.acme.certs."${cfg.domain}" = {
      inherit (cfg) domain;
      extraDomainNames = [
        "*.${cfg.domain}"
      ];
    };
    services.caddy = {
      enable = true;
      virtualHosts = lib.genAttrs (lib.attrNames cfg.sites) (_: target-config);
    };
    networking.firewall.interfaces.tailscale0 = lib.mkIf config.services.tailscale.enable {
      allowedTCPPorts = [
        80
        443
      ];
      allowedUDPPorts = [ 443 ];
    };

    # the module only orders itself after mysql with createLocally; without it,
    # a switch that restarts both runs init before the socket exists
    systemd.services.mediawiki-init = {
      after = [ "mysql.service" ];
      requires = [ "mysql.service" ];
    };

    # wiki
    services.mediawiki.httpd.virtualHost = {
      listen = [
        {
          ip = "127.0.0.1";
          port = cfg.httpdPort;
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

      passwordFile = cfg.adminPasswordFile;
      passwordSender = "no-reply@localhost";
      extraConfig = ''
        $wgScriptPath = "";
        $wgArticlePath = "/wiki/$1";
        $wgGroupPermissions['sysop']['deleterevision'] = true;
        # relative link at mainpage
        $wgNamespacesWithSubpages[NS_MAIN] = true;

        # theme
        $wgDefaultSkin = 'vector-2022';
        $wgDefaultMobileSkin = 'minerva';
        $wgAllowSiteCSSOnRestrictedPages = true;

        # provide lua binary
        $wgScribuntoDefaultEngine = 'luastandalone';
        $wgScribuntoEngineConf['luastandalone']['luaPath'] = '${pkgs.lua5_1}/bin/lua';

        # cache
        $wgMainCacheType = CACHE_ACCEL;
        $wgSessionCacheType = CACHE_DB;

        # resource
        $wgFileExtensions[] = 'svg';
        $wgAllowTitlesInSVG = true;
        $wgSVGConverter = 'rsvg';
        $wgSVGConverterPath = "${pkgs.librsvg}/bin/";
        $wgUseInstantCommons = true;

        # disable anonymous users
        $wgGroupPermissions['*']['edit'] = false;
        $wgGroupPermissions['*']['createaccount'] = false;

        # default logo
        $wgFavicon = '/resources/assets/mediawiki_compact.svg';
        $wgLogos = [
            '1x'  => '/resources/assets/mediawiki.png',
            'svg' => '/resources/assets/mediawiki.png',
            'icon' => '/resources/assets/mediawiki.png',
        ];

        # determine db name
        $wikis = [
        ${phpAssoc (lib.mapAttrs (_: s: s.dbName) cfg.sites)}
        ];
        if ( defined( 'MW_DB' ) ) {
          // Automatically set from --wiki option to maintenance scripts
          $wgDBname = MW_DB;
        } else {
          // Use MW_DB environment variable or map the domain name
          if (PHP_SAPI === 'cli') {
              $wgDBname = getenv('MW_DB') ?: 'main';
          } else {
              $wgDBname = $_SERVER['MW_DB'] ?? $wikis[ $_SERVER['HTTP_HOST'] ?? ''' ] ?? null;
          }
          if ( !$wgDBname ) {
              die( "Unknown wiki. Host: " . ($_SERVER['HTTP_HOST'] ?? 'CLI') );
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
        ${phpAssoc (lib.listToAttrs (map (s: lib.nameValuePair s.dbName s.sitename) sitesList))}
            ],
            'wgUploadDirectory' => [
        ${phpAssoc (lib.listToAttrs (map (s: lib.nameValuePair s.dbName "${uploads-dir}/${s.dbName}") sitesList))}
            ],
            'wgUploadPath' => [
        ${phpAssoc (lib.listToAttrs (map (s: lib.nameValuePair s.dbName "/images/${s.dbName}") sitesList))}
            ],
            'wgLanguageCode' => [
                // 'foowiki' => 'pt',
            ],
        ];
        extract( $wgConf->getAll( $wgDBname ) );
      '';

      extensions = {
        # base
        OATHAuth = null;
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
        Cite = null;
        CiteThisPage = null;

        # utils
        Gadgets = null;
        ImageMap = null;
        InputBox = null;
        PageImages = null;
        TextExtracts = null;
        PdfHandler = null;

        # management
        Nuke = null;
        ReplaceText = null;
        SpamBlacklist = null;

        inherit (extensions)
          Cargo
          CSS
          NoTitle
          Popups
          Mermaid
          MobileFrontend
          ;
      };

      skins = {
        inherit (extensions) MinervaNeue;
      };
    };

    systemd.tmpfiles.rules = lib.concatMap (db: [
      "d '${uploads-dir}/${db}' 0750 ${user} ${group} - -"
      "Z '${uploads-dir}/${db}' 0750 ${user} ${group} - -"
    ]) dbNames;

    # backups
    infra.restic.backups.mediawiki = lib.mkIf (cfg.backup.enable && config.infra.restic.enable) (
      let
        mysql-backup-dir = "/var/backup/mysql";
        mysql-backup-paths = map (db: "${mysql-backup-dir}/${db}.sql") dbNames;
        rm-mysql-paths = "rm -f ${lib.concatStringsSep " " mysql-backup-paths}";
      in
      {
        paths = [ uploads-dir ] ++ mysql-backup-paths;
        backupPrepareCommand = ''
          mkdir -p ${mysql-backup-dir}
          ${rm-mysql-paths}
          ${lib.concatMapStringsSep "\n          " (
            db: "${pkgs.mariadb}/bin/mysqldump ${db} > ${mysql-backup-dir}/${db}.sql"
          ) dbNames}
        '';
        backupCleanupCommand = ''
          ${rm-mysql-paths}
        '';
      }
    );
  };
}
