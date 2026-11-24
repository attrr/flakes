# Glue from ctx -> container-minimal runtime, topology, and low-memory tuning.
{
  config,
  ctx,
  lib,
  ...
}:
let
  engine = ctx.metadata.engine.type;
  caps = ctx.metadata.engine.capabilities;
  memMb = ctx.metadata.specs.memory;
  lowMem = memMb != null && memMb <= 96;
  hasStatic = ctx.network.ipv4.addresses != [ ] || ctx.network.ipv6.addresses != [ ];
in
{
  infra.container = {
    runtime = lib.mkIf (builtins.elem engine [
      "lxc"
      "incus"
      "podman"
      "docker"
    ]) (lib.mkDefault engine);

    capabilities = lib.mapAttrs (_: v: lib.mkDefault v) (
      lib.filterAttrs (_: v: v != null) {
        inherit (caps) sys_admin net_admin mknod;
      }
    );
  };

  infra.network.topology = lib.mkIf hasStatic (lib.mkDefault "static");

  # Keep Go's memory target within tight container limits (`default` is 64MiB/48MiB).
  finit.services.sing-box.environment = lib.mkIf (config.services.sing-box.enable && lowMem) {
    GOMEMLIMIT = lib.mkOverride 900 "${toString (lib.max 16 (memMb * 7 / 16))}MiB";
    GOGC = lib.mkOverride 900 25;
  };
  finit.services.usque.environment = lib.mkIf (config.services.usque.enable && lowMem) {
    GOMEMLIMIT = lib.mkOverride 900 "${toString (lib.max 12 (memMb / 4))}MiB";
    GOGC = lib.mkOverride 900 25;
  };
}
