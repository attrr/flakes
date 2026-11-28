{
  self,
  inputs,
  nixpkgs,
  disko,
  deploy-rs,
  finix,
}:
system:
let
  inherit (nixpkgs) lib;
  pkgs = nixpkgs.legacyPackages.${system};
  aspectLib = import ./aspects.nix { inherit lib; };

  nixSrc = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.difference (lib.fileset.fileFilter (f: f.hasExt "nix") ../.) ../ctx;
  };

  pureNixos = lib.nixosSystem {
    inherit system;
    modules = [
      self.nixosModules.default
      disko.nixosModules.disko
      {
        system.stateVersion = "26.05";
        fileSystems."/" = {
          device = "/dev/null";
          fsType = "ext4";
        };
        boot.loader.grub.enable = false;
      }
    ];
  };

  nixosContainer = self.nixosConfigurations.koto.extendModules {
    modules = [ self.modules.nixos.container ];
  };

  nixosContainerPodman = self.nixosConfigurations.koto.extendModules {
    modules = [
      self.modules.nixos.container
      {
        infra.container.runtime = "podman";
        services.resolved.enable = true;
      }
    ];
  };

  nixosContainerOpenvz = self.nixosConfigurations.koto.extendModules {
    modules = [
      self.modules.nixos.container
      { infra.container.runtime = "openvz"; }
    ];
  };

  finixContainerOpenvz = lib.evalModules {
    specialArgs = { inherit inputs self finix; };
    modules = [
      self.finixModules.default
    ]
    ++ aspectLib.resolveModule "finix" [ ../modules/profiles/container ]
    ++ [
      {
        nixpkgs.hostPlatform = system;
        nixpkgs.overlays = [ self.overlays.default ];
        networking.hostName = "openvz-check";
        infra.container.runtime = "openvz";
        infra.network = {
          topology = "static";
          ipv4.addresses = [ "10.0.0.2/24" ];
        };
      }
    ];
  };
in
(deploy-rs.lib.${system}.deployChecks self.deploy)
// {
  format = pkgs.runCommand "check-format" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
    nixfmt --check ${nixSrc}
    touch $out
  '';

  deadnix = pkgs.runCommand "check-deadnix" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
    deadnix --fail --no-lambda-pattern-names ${nixSrc}
    touch $out
  '';

  pure-nixos-modules =
    assert builtins.isString pureNixos.config.system.build.toplevel.drvPath;
    pkgs.runCommand "check-pure-nixos-modules" { } ''
      touch $out
    '';

  nixos-container-profile =
    assert nixosContainer.config.infra.container.runtime == "lxc";
    assert builtins.isString nixosContainer.config.system.activationScripts.containerLustrate;
    assert !nixosContainerPodman.config.services.resolved.enable;
    assert !nixosContainerPodman.config.networking.nftables.enable;
    assert
      nixosContainerPodman.config.services.endlessh.enable
      ->
        !nixosContainerPodman.config.systemd.services.endlessh.serviceConfig.DynamicUser
        && nixosContainerPodman.config.systemd.services.endlessh.serviceConfig.RootDirectory == "";
    assert builtins.isString nixosContainerPodman.config.system.build.toplevel.drvPath;
    assert lib.any (a: !a.assertion) nixosContainerOpenvz.config.assertions;
    pkgs.runCommand "check-nixos-container-profile" { } ''
      touch $out
    '';

  finix-container-openvz =
    let
      cfg = finixContainerOpenvz.config;
    in
    assert cfg.infra.finix.legacyInotify;
    assert !cfg.services.nftables.enable;
    assert cfg.providers.firewall.backend == "none";
    assert cfg.infra.network.interface == "venet0";
    assert (cfg.programs.ifupdown-ng.iface.venet0.up or [ ]) != [ ];
    assert cfg.finit.run.vzfifo.enable;
    assert
      cfg.infra.container.bashWrapper != null && cfg.infra.container.bashWrapper.name == "openvz-bash";
    assert builtins.isString cfg.system.topLevel.drvPath;
    pkgs.runCommand "check-finix-container-openvz" { } ''
      touch $out
    '';
}
