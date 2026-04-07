{ lib, ... }:
{
  options.boot.kernel.sysctl = lib.mkOption { type = lib.types.attrsOf lib.types.unspecified; default = {}; };
  options.networking.firewall = {
    allowedTCPPorts = lib.mkOption { type = lib.types.listOf lib.types.port; default = []; };
    allowedUDPPorts = lib.mkOption { type = lib.types.listOf lib.types.port; default = []; };
  };
  options.systemd = lib.mkOption { type = lib.types.unspecified; };
  options.users = lib.mkOption { type = lib.types.unspecified; };
  options.virtualisation = lib.mkOption { type = lib.types.unspecified; };
  options.containers = lib.mkOption { type = lib.types.unspecified; };
  options.system = lib.mkOption { type = lib.types.unspecified; };
}
