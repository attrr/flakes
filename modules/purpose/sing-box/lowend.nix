{
  config,
  lib,
  ...
}:
let
  cfg = config.infra.sing-box;
  warp = cfg.warp;
in
{
  options.infra.sing-box = {
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
        boot.kernel.sysctl = {
          "net.core.rmem_max" = lib.mkForce 8388608;
          "net.core.wmem_max" = lib.mkForce 8388608;
          "net.ipv4.tcp_max_syn_backlog" = lib.mkForce 2048;
          "net.core.somaxconn" = lib.mkForce 2048;
          "net.netfilter.nf_conntrack_max" = lib.mkForce 65536;
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
        };
      })
    ]
  );

}
