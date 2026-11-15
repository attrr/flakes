# Network topologies as NixOS modules: infra.network.topology selects a preset
# (e.g. "static"); each topology module gates itself on cfg.topology
# and adapts to config.networking.useNetworkd.
{ lib, ... }:
let
  topologyFiles = lib.filter (n: n != "default.nix" && lib.hasSuffix ".nix" n) (
    lib.attrNames (builtins.readDir ./.)
  );
  topologies = map (lib.removeSuffix ".nix") topologyFiles;

  stackType = lib.types.submodule {
    options = {
      addresses = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "CIDR addresses, e.g. \"192.0.2.1/24\".";
      };
      gateway = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
    };
  };
in
{
  imports = map (n: ./${n}) topologyFiles;

  options.infra.network = {
    topology = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum topologies);
      default = null;
    };
    interface = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    ipv4 = lib.mkOption {
      type = stackType;
      default = { };
    };
    ipv6 = lib.mkOption {
      type = stackType;
      default = { };
    };
  };
}
