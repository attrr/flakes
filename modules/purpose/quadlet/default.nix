{
  config,
  lib,
  utils,
  ...
}:
let
  inherit (lib) mkOption types mapAttrs' nameValuePair;

  # Use NixOS's systemd generator for consistent serialization
  mkQuadlet = utils.systemdUtils.lib.settingsToSections;
in
{
  options.virtualisation.quadlet = {
    containers = mkOption {
      type = types.attrsOf (types.attrsOf types.unspecified);
      default = { };
      description = "Podman Quadlet container definitions (.container)";
    };
    pods = mkOption {
      type = types.attrsOf (types.attrsOf types.unspecified);
      default = { };
      description = "Podman Quadlet pod definitions (.pod)";
    };
    networks = mkOption {
      type = types.attrsOf (types.attrsOf types.unspecified);
      default = { };
      description = "Podman Quadlet network definitions (.network)";
    };
    volumes = mkOption {
      type = types.attrsOf (types.attrsOf types.unspecified);
      default = { };
      description = "Podman Quadlet volume definitions (.volume)";
    };
  };

  config.environment.etc =
    (mapAttrs' (
      name: value: nameValuePair "containers/systemd/${name}.container" { text = mkQuadlet value; }
    ) config.virtualisation.quadlet.containers)
    // (mapAttrs' (
      name: value: nameValuePair "containers/systemd/${name}.pod" { text = mkQuadlet value; }
    ) config.virtualisation.quadlet.pods)
    // (mapAttrs' (
      name: value: nameValuePair "containers/systemd/${name}.network" { text = mkQuadlet value; }
    ) config.virtualisation.quadlet.networks)
    // (mapAttrs' (
      name: value: nameValuePair "containers/systemd/${name}.volume" { text = mkQuadlet value; }
    ) config.virtualisation.quadlet.volumes);
}
