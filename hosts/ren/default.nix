{ ctx, pkgs, ... }:
{
  imports = [
    ./acme-dns.nix
    ./dns.nix
  ];

  infra.restic =
    let
      restic = ctx.services.restic;
    in
    {
      enable = true;
      s3.bucketName = restic.bucket-name;
      environmentFile = restic.env.path;
      passwordFile = restic.password.path;

      backups.infra = {
        paths = [
          "/var/lib/acme"
        ];
      };

      # acme-dns runs with DynamicUser, its state lives under /var/lib/private
      backups.acme-dns =
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
    };
}
