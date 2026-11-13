# What every host takes from its ctx entry. flake.nix (mkSystem) also picks
# imports from it: profiles/<tag> + ./<tag>.nix per tag, ./providers/<provider>.nix.
{
  lib,
  config,
  ctx,
  ...
}:
{
  imports = [
    ./librechat.nix
    ./mediawiki.nix
    ./openbao.nix
  ];

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
}
