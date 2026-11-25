let
  moduleList = import ../module-list.nix;
in
{
  includes = moduleList.common;

  module = {
    nixos =
      { lib, ... }:
      {
        imports = (import ../../lib/aspects.nix { inherit lib; }).resolve "nixos" (
          moduleList.nixos ++ [ ../nix.nix ]
        );
      };
    finix =
      { lib, ... }:
      {
        imports = (import ../../lib/aspects.nix { inherit lib; }).resolve "finix" moduleList.finix;
      };
  };

  ctx.nixos =
    {
      lib,
      config,
      ctx,
      ...
    }:
    {
      nixpkgs.hostPlatform = lib.mkDefault ctx.metadata.arch;

      infra.alerts = lib.mkIf ctx.alerts.enable {
        enable = true;
        inherit (ctx.alerts) url topic;
        tokenFile = ctx.alerts.token.path;
      };

      # untrusted machines stay off the tailnet
      assertions = [
        {
          assertion = ctx.metadata.group != "untrusted" || !config.services.tailscale.enable;
          message = "${ctx.metadata.hostname} is in group untrusted, it must not run tailscale";
        }
      ];
    };
}
