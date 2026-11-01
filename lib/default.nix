# helpers for host configs, as the `helpers` module arg
{
  config,
  pkgs,
  lib,
  ...
}@args:
{
  _module.args.helpers = {
    sing = import ./sing.nix args;
    network = import ./network.nix args;
  };
}
