# ctx -> core.server, for hosts tagged "server"
{ lib, ctx, ... }:
{
  core.server = {
    hostname = lib.mkDefault ctx.metadata.hostname;
    ssh-ports = lib.mkDefault ctx.ssh.ports;
    ssh-keys = lib.mkDefault ctx.ssh.auth-keys;
  };
}
