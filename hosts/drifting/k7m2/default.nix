{ self, ... }:
{
  imports = [
    "${self}/modules/ctx/server.nix"
    "${self}/modules/ctx/proxy.nix"
    "${self}/modules/ctx/telemetry.nix"
  ];

  infra.container.runtime = "podman";

  finit.services.sing-box.environment = {
    GOMEMLIMIT = "28MiB";
    GOGC = 25;
  };
  finit.services.usque.environment = {
    GOMEMLIMIT = "16MiB";
    GOGC = 25;
  };
}
