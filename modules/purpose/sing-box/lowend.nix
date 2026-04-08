{
  config,
  lib,
  ...
}:
let
  cfg = config.core.server.sing-box;
  warp = cfg.warp;
in
{
  options.core.server.sing-box = {
    lowend = lib.mkEnableOption "enable lowend machine limitation";
  };

  config = lib.mkIf (cfg.enable && cfg.lowend) (
    lib.mkMerge [
      {
        systemd.services."container@sing-box" = {
          serviceConfig = {
            MemoryMax = "128M";
            MemoryHigh = "80%";
          };
        };
      }
      (lib.mkIf warp.enable {
        systemd.services.podman-warp = {
          serviceConfig = {
            MemoryMax = "120M";
            MemoryHigh = "100M";
          };
        };
        boot.kernel.sysctl = {
          "net.core.rmem_default" = lib.mkForce 262144;
          "net.core.rmem_max" = lib.mkForce 8388608;
        };
      })
    ]
  );

}
