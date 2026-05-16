{ lib, ... }:
{
  options.sops = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
  };
}
