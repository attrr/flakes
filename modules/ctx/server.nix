# ctx -> infra.server, for hosts tagged "server" (with profiles/server)
{ lib, ctx, ... }:
{
  infra.server = {
    hostname = lib.mkDefault ctx.metadata.hostname;
    ssh-ports = lib.mkDefault ctx.ssh.ports;
    ssh-keys = lib.mkDefault ctx.ssh.auth-keys;
  };
}
