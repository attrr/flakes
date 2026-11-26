{
  ctx,
  registry,
  ...
}:
{
  imports = [
    ./restic-server.nix
    ./syncthing.nix
  ];

  infra.acme = {
    enable = true;
    api = registry.acme-dns.url;
    certs."${ctx.metadata.fdqn}".extraDomainNames = [
      "*.${ctx.metadata.fdqn}"
    ];
  };
}
