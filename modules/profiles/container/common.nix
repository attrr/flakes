# Shared container runtime presets and capabilities options (NixOS and finix).
{ config, lib, ... }:
let
  cfg = config.infra.container;

  presets = {
    lxc = {
      sys_admin = true;
      net_admin = true;
      mknod = true;
    };
    incus = presets.lxc;
    podman = {
      sys_admin = false;
      net_admin = false;
      mknod = false;
    };
    docker = presets.podman;
  };
in
{
  options.infra.container = {
    runtime = lib.mkOption {
      type = lib.types.enum (builtins.attrNames presets);
      default = "podman";
      description = "Container runtime preset seeding default capabilities.";
    };

    capabilities = {
      sys_admin = lib.mkEnableOption "CAP_SYS_ADMIN (mount /run/* tmpfs and service capabilities)";
      net_admin = lib.mkEnableOption "CAP_NET_ADMIN (configure NICs, routes, and DNS)";
      mknod = lib.mkEnableOption "CAP_MKNOD (create device nodes like /dev/net/tun)";
    };
  };

  config.infra.container.capabilities = lib.mapAttrs (_: lib.mkDefault) presets.${cfg.runtime};
}
