{
  ctx,
  registry,
  ...
}:
{
  imports = [
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
