{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.virtualisation.quadlet;

  mkSystemd = utils.systemdUtils.lib.settingsToSections;

  mkQuadlet =
    n: v:
    mkSystemd (
      # FIXME: improve merge logic
      lib.recursiveUpdate {
        Unit.PartOf = [ "quadlet-trigger-${n}.service" ];
      } v
    );

  mkQuadletKind =
    kind: units:
    lib.mapAttrs' (
      n: v:
      let
        path = "containers/systemd/${n}.${kind}";
        unitName = if kind == "container" then n else "${n}-${kind}";
      in
      lib.nameValuePair path { text = mkQuadlet unitName v; }
    ) units;

  mkTriggerKind =
    kind: units:
    lib.mapAttrs' (
      n: v:
      let
        unit = if kind == "container" then n else "${n}-${kind}";
      in
      lib.nameValuePair "quadlet-trigger-${unit}" {
        description = "NixOS Trigger for Quadlet ${unit}.service";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.coreutils}/bin/true";
        };
        restartTriggers = [
          (builtins.hashString "sha256" (mkSystemd v))
        ];

        wantedBy = [ "multi-user.target" ];
      }
    ) units;

in
{
  options.virtualisation.quadlet = {
    containers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.unspecified);
      default = { };
      description = "Podman Quadlet container definitions (.container)";
    };
    pods = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.unspecified);
      default = { };
      description = "Podman Quadlet pod definitions (.pod)";
    };
    networks = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.unspecified);
      default = { };
      description = "Podman Quadlet network definitions (.network)";
    };
    volumes = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.unspecified);
      default = { };
      description = "Podman Quadlet volume definitions (.volume)";
    };
  };

  config =
    let
      kinds = [
        "container"
        "pod"
        "network"
        "volume"
      ];
    in
    {
      environment.etc = lib.pipe kinds [
        (map (kind: mkQuadletKind kind cfg."${kind}s"))
        (lib.foldl' lib.recursiveUpdate { })
      ];
      systemd.services = lib.pipe kinds [
        (map (kind: mkTriggerKind kind cfg."${kind}s"))
        (lib.foldl' lib.recursiveUpdate { })
      ];
    };
}
