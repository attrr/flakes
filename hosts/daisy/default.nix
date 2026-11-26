{
  ctx,
  registry,
  ...
}:
{
  imports = [
    ./forgejo.nix
    ./nix.nix
    ./observability
  ];

  infra.acme = {
    enable = true;
    api = registry.acme-dns.url;
    certs."${ctx.metadata.fdqn}".extraDomainNames = [
      "*.${ctx.metadata.fdqn}"
    ];
  };

  infra.restic =
    let
      restic = ctx.services.restic;
    in
    {
      enable = true;
      s3.bucketName = restic.bucket-name;
      environmentFile = restic.env.path;
      passwordFile = restic.password.path;

      backups.infra.paths = [ "/var/lib/acme" ];
    };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
    persistent = true;
    randomizedDelaySec = "1h";
  };
  nix.settings = {
    min-free = 5 * 1024 * 1024 * 1024;
    max-free = 15 * 1024 * 1024 * 1024;
  };
}
