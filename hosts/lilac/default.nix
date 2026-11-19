{
  ctx,
  registry,
  ...
}:
{
  imports = [
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
