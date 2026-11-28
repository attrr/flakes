{
  nixos =
    { config, ... }:
    {
      assertions = [
        {
          assertion = config.infra.container.runtime != "openvz";
          message = "OpenVZ 7 (Linux 3.10) is incompatible with NixOS/systemd; use finix (metadata.minimal = true).";
        }
      ];
    };

  finix =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.infra.container;
      cap = cfg.capabilities;
      coreutils = config.programs.coreutils.package;
      infraNet = config.infra.network;
      iface = if infraNet.interface != null then infraNet.interface else "venet0";

      # ifupdown-ng's `gateway` always emits `via <ip>`, so gateway-less P2P venet0 needs explicit `up` routes.
      deviceRoutes =
        lib.optional (
          infraNet.ipv4.addresses != [ ] && infraNet.ipv4.gateway == null
        ) "${pkgs.iproute2}/bin/ip -4 route replace default dev ${iface}"
        ++ lib.optional (
          infraNet.ipv6.addresses != [ ] && infraNet.ipv6.gateway == null
        ) "${pkgs.iproute2}/bin/ip -6 route replace default dev ${iface}";

      # OpenVZ 7 invokes /bin/bash via vzctl before PID 1 starts to inject distro network/hostname scripts.
      # Link directly to a store wrapper so it works before /run/current-system exists and silently no-ops vzctl.
      openvzBash = pkgs.writeScript "openvz-bash" ''
        #!${coreutils}/bin/sh
        if [ -r /proc/1/cmdline ] && ${coreutils}/bin/tr -d '\0' < /proc/1/cmdline | ${coreutils}/bin/grep -q vzctl; then
          exit 0
        fi
        exec ${config.programs.bash.package}/bin/bash "$@"
      '';
    in
    {
      config = lib.mkIf (cfg.runtime == "openvz") {
        infra.finix.legacyInotify = lib.mkDefault true;
        infra.container.bashWrapper = lib.mkDefault openvzBash;
        infra.network.interface = lib.mkDefault "venet0";

        # OpenVZ 7 runs a backported 3.10 nf_tables that rejects concat/interval sets in nixos-fw & scanner-blocklist.
        services.nftables.enable = lib.mkOverride 900 false;
        providers.firewall.backend = lib.mkOverride 900 "none";

        programs.ifupdown-ng.iface.${iface} =
          lib.mkIf (cap.net_admin && infraNet.topology == "static" && deviceRoutes != [ ])
            {
              up = deviceRoutes;
            };

        finit.run.vzfifo = {
          enable = true;
          description = "signal OpenVZ host that container boot completed";
          runlevel = "2";
          script = ''
            [ -p /.vzfifo ] && ${coreutils}/bin/touch /.vzfifo || true
          '';
        };
      };
    };
}
