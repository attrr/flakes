{
  lib,
  ctx,
  global,
  ...
}:
let
  wiki = ctx.services.mediawiki or { enable = false; };
  wikiDomain = "wiki." + global.domain.main;
in
lib.mkIf wiki.enable {
  sops.secrets.${wiki.admin-password.name}.owner = "mediawiki";

  infra.mediawiki = {
    enable = true;
    domain = lib.mkDefault wikiDomain;
    sites."${wikiDomain}" = {
      dbName = lib.mkDefault "main";
      sitename = lib.mkDefault "MainWiki";
    };
    adminPasswordFile = lib.mkDefault wiki.admin-password.path;
    listenAddresses = lib.mkDefault ctx.tailscale.ips;
  };
}
