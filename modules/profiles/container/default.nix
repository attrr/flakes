{
  includes = [
    ./capabilities.nix
    ./init.nix
    ./lustrate.nix
    ./openvz.nix
    ../server
  ];

  module = {
    nixos = ./nixos;
    finix = ./finix;
  };

  ctx = {
    common =
      { ctx, lib, ... }:
      let
        engine = ctx.metadata.engine.type;
        caps = ctx.metadata.engine.capabilities;
      in
      {
        infra.container = {
          runtime = lib.mkIf (builtins.elem engine [
            "lxc"
            "incus"
            "openvz"
            "podman"
            "docker"
          ]) (lib.mkDefault engine);

          capabilities = lib.mapAttrs (_: v: lib.mkDefault v) (
            lib.filterAttrs (_: v: v != null) {
              inherit (caps) sys_admin net_admin mknod;
            }
          );
        };
      };

    finix =
      { ctx, lib, ... }:
      let
        hasStatic = ctx.network.ipv4.addresses != [ ] || ctx.network.ipv6.addresses != [ ];
      in
      {
        infra.network.topology = lib.mkIf hasStatic (lib.mkDefault "static");
      };
  };
}
