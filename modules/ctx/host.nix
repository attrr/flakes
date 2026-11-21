# What every host takes from its ctx entry. flake.nix (mkSystem) also adds
# ./proxy.nix for every host and ./providers/<provider>.nix when set.
{
  lib,
  config,
  ctx,
  ...
}:
{
  imports = [
    ./knot.nix
    ./librechat.nix
    ./mediawiki.nix
    ./telemetry.nix
    ./network.nix
    ./nix.nix
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
