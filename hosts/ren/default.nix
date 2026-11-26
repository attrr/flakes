{ ctx, pkgs, ... }:
{
  imports = [
    ./acme-dns.nix
    ./ntfy.nix
  ];

  # for services under ren's own name, like ntfy
  infra.acme.certs."${ctx.metadata.fdqn}" = {
    domain = ctx.metadata.fdqn;
    extraDomainNames = [
      "*.${ctx.metadata.fdqn}"
    ];
  };

  # acme-dns runs with DynamicUser, its state lives under /var/lib/private
  infra.restic.backups.acme-dns =
    let
      path = "/var/lib/acme-dns-backup";
    in
    {
      paths = [ path ];
      backupPrepareCommand = ''
        rm -rf ${path}
        mkdir -p ${path}
        ${pkgs.sqlite}/bin/sqlite3 /var/lib/private/acme-dns/acme-dns.db ".backup '${path}/acme-dns.db'"
      '';
      backupCleanupCommand = ''
        rm -rf ${path}
      '';
    };
}
