# Glue from ctx.network -> infra.network defaults.
{ ctx, lib, ... }:
{
  infra.network = {
    interface = lib.mkIf (ctx.network.interface != null) (lib.mkDefault ctx.network.interface);
    ipv4 = {
      addresses = lib.mkDefault ctx.network.ipv4.cidr;
      gateway = lib.mkDefault ctx.network.ipv4.gateway;
    };
    ipv6 = {
      addresses = lib.mkDefault ctx.network.ipv6.cidr;
      gateway = lib.mkDefault ctx.network.ipv6.gateway;
    };
  };
}
