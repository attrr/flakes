{
  lib,
  pkgs,
  ctx,
  ...
}:
let
  wg = ctx.services.wireguard;
  lan = ctx.network;
  direct = lan.ipv4.category.direct;

  # downloaders' netns: LAN macvlan, plus a veth for caddy
  veth = {
    host = "10.200.0.1";
    ns = "10.200.0.2";
  };

  inDirect =
    c:
    lib.recursiveUpdate {
      Unit = {
        Requires = [ "netns-direct.service" ];
        After = [ "netns-direct.service" ];
      };
      Container = {
        Network = "ns:/run/netns/direct";
        # the host's resolver is 127.0.0.53, out of reach in there
        DNS = lan.ipv4.gateway;
      };
    } c;

  # ids inside the containers, they're all UserNS=auto
  linuxserver = [
    "PUID=972"
    "PGID=972"
    "UMASK=002"
    "TZ=Etc/UTC"
  ];
in
{
  infra.containers.enable = true;

  systemd.services.netns-direct = {
    description = "LAN netns outside wg0";
    bindsTo = [ "sys-subsystem-net-devices-${lan.interface}.device" ];
    after = [ "sys-subsystem-net-devices-${lan.interface}.device" ];
    wantedBy = [ "multi-user.target" ];
    # recreating it strands the containers in the old one
    restartIfChanged = false;
    path = [ pkgs.iproute2 ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ip netns add direct
      ip -n direct link set lo up

      ip link add direct-lan link ${lan.interface} address ${direct.mac-address} netns direct type macvlan mode bridge
      ip -n direct addr add ${builtins.head direct.addresses}${direct.subnet} dev direct-lan
      ip -n direct link set direct-lan up
      ip -n direct route add default via ${lan.ipv4.gateway}

      ip link add direct-host type veth peer name host netns direct
      ip addr add ${veth.host}/30 dev direct-host
      ip link set direct-host up
      ip -n direct addr add ${veth.ns}/30 dev host
      ip -n direct link set host up
    '';
    # removes the macvlan and veth too
    postStop = "ip netns del direct || true";
  };
  networking.networkmanager.unmanaged = [ "direct-host" ];

  virtualisation.quadlet = {
    enable = true;
    containers = {
      forgejo = {
        Unit = {
          # git ssh listens on the wg address
          Wants = [ "wireguard-wg0.service" ];
          After = [ "wireguard-wg0.service" ];
        };
        Container = {
          Image = "codeberg.org/forgejo/forgejo:14";
          PublishPort = [
            "127.0.0.1:3000:3000/tcp"
            "${wg.ipv4}:22:22/tcp"
          ];
          UserNS = "auto";
          Volume = "/mnt/git:/data:idmap";
          AutoUpdate = "registry";
        };
        Install.WantedBy = [ "mnt.mount" ];
      };

      jellyfin = {
        Container = {
          Image = "docker.io/jellyfin/jellyfin:preview";
          PublishPort = "127.0.0.1:8096:8096/tcp";
          UserNS = "auto";
          Volume = [
            "jellyfin-config:/config:U"
            "jellyfin-cache:/cache:U"
            "/mnt/media:/media:idmap"
          ];
          AddDevice = "/dev/dri/renderD128";
          # render inside the container; the node itself is 0666
          GroupAdd = "105";
          Environment = [
            "PUID=972"
            "PGID=972"
          ];
          AutoUpdate = "registry";
        };
        Service.Restart = "always";
        Install.WantedBy = [ "mnt.mount" ];
      };

      # web ui on 8080
      qbittorrent-direct = inDirect {
        Container = {
          Image = "docker.io/qbittorrentofficial/qbittorrent-nox:5.1.4-2";
          UserNS = "auto";
          Volume = [
            "qbittorrent-direct-config:/config:U"
            "/mnt/media:/downloads:idmap"
          ];
          Environment = linuxserver ++ [ "QBT_EULA=accept" ];
          AutoUpdate = "registry";
        };
        Service.TimeoutStartSec = "infinity";
        Install.WantedBy = [ "mnt.mount" ];
      };

      # web ui on 9091
      transmission = inDirect {
        Container = {
          Image = "lscr.io/linuxserver/transmission:4.0.5";
          UserNS = "auto";
          Volume = [
            "transmission-config:/config:idmap"
            # alternative webui
            "trguing:/webui"
            "/mnt/media:/downloads:idmap"
          ];
          Environment = linuxserver ++ [ "TRANSMISSION_WEB_HOME=/webui" ];
          EnvironmentFile = ctx.vars.transmission-env.env.path;
          AutoUpdate = "registry";
        };
        Service.TimeoutStartSec = "infinity";
        Install.WantedBy = [ "mnt.mount" ];
      };

      # web ui on 8082; timing out on Fedora too
      sabnzbd = inDirect {
        Container = {
          Image = "lscr.io/linuxserver/sabnzbd:latest";
          UserNS = "auto";
          Volume = [
            "sabnzbd-config:/config:U"
            "/mnt/media:/downloads:idmap"
          ];
          Environment = linuxserver;
          AutoUpdate = "registry";
        };
        Install.WantedBy = [ "mnt.mount" ];
      };
    };
  };
}
