{
  config,
  lib,
  pkgs,
  ctx,
  global,
  fn,
  ...
}@args:
let

  # 1. Main Infrastructure Config
  mainConfig = (import ./main.nix args).mainConfig;
  # 2. Concrete Outbounds Config (Nodes)
  outboundConfig = (import ./outbounds.nix args).outboundConfig;
  # 3. Routing Logic Config (Selectors, Rules)
  logicConfig = (import ./logic.nix args).logicConfig;

  # 4. Final Merge
  finalSettings = {
    inherit (mainConfig)
      log
      dns
      inbounds
      experimental
      ;

    # Merge endpoints (WireGuard)
    endpoints = outboundConfig.endpoints or [ ];

    # Merge Logic:
    # Outbounds = Main(Infra) + Outbounds(Nodes) + Logic(Selectors)
    outbounds =
      (mainConfig.outbounds or [ ])
      ++ (outboundConfig.outbounds or [ ])
      ++ (logicConfig.outbounds or [ ]);

    # Route:
    # Rules = Logic.Rules
    # RuleSet = Logic.RuleSet
    route = {
      inherit (logicConfig.route) rules rule_set final;
    };
  };
in
{
  config = lib.mkIf config.services.sing-box.enable {
    # Use sops templates to inject secrets
    sops.templates."sing-box.json" = {
      content = builtins.toJSON finalSettings;
      owner = "sing-box";
    };

    systemd.services.sing-box.serviceConfig.ExecStart = [
      ""
      "${lib.getExe config.services.sing-box.package} run -c ${
        config.sops.templates."sing-box.json".path
      }"
    ];
  };
}
