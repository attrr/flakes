# Nix cache (harmonia) + remote builders feature (NixOS only).
{
  ctx.nixos =
    {
      config,
      ctx,
      lib,
      registry,
      ...
    }:
    let
      cache = registry.harmonia or null;
      machines = ctx.nix.build-machines;
      hasBuilders = machines != [ ];
      useCache =
        cache != null
        && cache.publicKey != ""
        && !ctx.services.harmonia.enable
        && (config.services.tailscale.enable || hasBuilders);
    in
    {
      nix = {
        distributedBuilds = lib.mkIf hasBuilders true;

        settings = {
          extra-substituters = lib.mkIf useCache [ cache.url ];
          extra-trusted-public-keys = lib.mkIf useCache [ cache.publicKey ];
          builders-use-substitutes = lib.mkIf hasBuilders true;
        };

        buildMachines = map (b: {
          inherit (b) hostName systems maxJobs;
          protocol = "ssh-ng";
          sshUser = "nix-ssh";
          sshKey = b.sshKey.path;
          speedFactor = 2;
          supportedFeatures = b.features;
        }) machines;
      };

      programs.ssh = lib.mkIf hasBuilders {
        knownHosts = lib.listToAttrs (
          map (b: {
            name = b.hostName;
            value.publicKey = b.publicHostKey;
          }) (builtins.filter (b: b.publicHostKey != "") machines)
        );
        extraConfig = lib.concatMapStringsSep "\n" (b: ''
          Match host ${b.hostName} user nix-ssh
            Port ${toString b.port}
        '') machines;
      };
    };
}
