{
  lib,
  ctx,
  self,
  pkgs,
  ...
}:
{
  imports = [
    "${self}/modules/profiles/server"
  ];

  system.stateVersion = "25.11";
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.supportedFilesystems.zfs = lib.mkForce false;

  networking.useNetworkd = true;
  systemd.network.networks."10-default" = {
    matchConfig.Name = "e*";
    address = ctx.network.ipv4.cidr;
    gateway = [ ctx.network.ipv4.gateway ];
    dns = [ ctx.network.ipv4.gateway ];

    networkConfig = {
      IPv6AcceptRA = true;
      IPv6PrivacyExtensions = "yes";
    };

    ipv6AcceptRAConfig = {
      UseAutonomousPrefix = true;
      UseGateway = true;
      Token = "prefixstable";
    };
  };

  core.server = {
    hostname = ctx.metadata.hostname;
    ssh-ports = ctx.ssh.ports;
    ssh-keys = ctx.ssh.auth-keys;
  };
}
