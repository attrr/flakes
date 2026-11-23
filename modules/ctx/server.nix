# ctx -> infra.server, for hosts tagged "server" (with profiles/server) or container-minimal
{
  lib,
  ctx,
  options,
  ...
}:
{
  infra.server = {
    hostname = lib.mkDefault ctx.metadata.hostname;
    ssh-ports = lib.mkDefault ctx.ssh.ports;
    ssh-keys = lib.mkDefault ctx.ssh.auth-keys;
  }
  // lib.optionalAttrs (options.infra.server ? lowend) {
    lowend.enable = lib.mkIf (
      ctx.metadata.specs.memory != null && ctx.metadata.specs.memory <= 1024
    ) (lib.mkDefault true);
  };
}
