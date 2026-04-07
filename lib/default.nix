{
  config,
  pkgs,
  lib,
  ...
}@args:
let
  fn = {
    sing = import ./sing.nix args;
    general = import ./general.nix args;
  };
in
{
  _module.args.fn = fn;
}
