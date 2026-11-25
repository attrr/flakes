{
  lib,
  pkgs,
  cfg,
  runtimeTools,
}:
pkgs.writeShellApplication {
  name = "nano-exporter-push";
  runtimeInputs = runtimeTools ++ [
    cfg.package
    pkgs.curlMinimal
  ];
  runtimeEnv = {
    NANO_EXPORTER_URL = cfg.push.url;
    NANO_EXPORTER_NODENAME = lib.optionalString (cfg.nodename != null) cfg.nodename;
    NANO_EXPORTER_USER = lib.optionalString (
      cfg.push.basicAuthUsername != null
    ) cfg.push.basicAuthUsername;
    NANO_EXPORTER_PASSWORD_FILE = lib.optionalString (cfg.push.basicAuthPasswordFile != null) (
      toString cfg.push.basicAuthPasswordFile
    );
    NANO_EXPORTER_EXTRA_FLAGS = cfg.extraFlags;
    NANO_EXPORTER_COLLECTORS = map toString cfg.extraCollectors;
  };
  text = builtins.readFile ./push.sh;
}
