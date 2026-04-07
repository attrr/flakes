{ pkgs ? import <nixpkgs> {} }:
let
  lib = pkgs.lib;
  eval = lib.evalModules {
    modules = [
      (pkgs.path + "/nixos/modules/misc/assertions.nix")
      ./stub.nix
      ../../modules/purpose/sing-box/default.nix
      {
        core.server.sing-box = {
          enable = true;
          shadowsocks.passwordPath = "/dummy";
          warp = {
            enable = true;
            lowend = true;
          };
        };
      }
    ];
    specialArgs = { inherit pkgs; };
  };
  
  cfg = eval.config.core.server.sing-box;
  
  failedAssertions = builtins.filter (x: !x.assertion) eval.config.assertions;

  tests = [
    {
      assertion = builtins.length failedAssertions == 0;
      message = "Module assertions failed: ${builtins.toJSON (builtins.map (x: x.message) failedAssertions)}";
    }
    {
      assertion = cfg.settings.route.final == "warp";
      message = "Route final mismatch, expected warp";
    }
    {
      assertion = builtins.hasAttr "warp" eval.config.virtualisation.oci-containers.containers;
      message = "Missing warp container configuration";
    }
    {
      assertion = builtins.elem "--cap-add=NET_ADMIN" eval.config.virtualisation.oci-containers.containers.warp.extraOptions;
      message = "Warp container missing NET_ADMIN capability";
    }
    {
      assertion = builtins.hasAttr "podman-network-restore" eval.config.systemd.services;
      message = "Missing podman-network-restore systemd service";
    }
    {
      assertion = eval.config.boot.kernel.sysctl."net.core.rmem_default" == 262144;
      message = "Missing or incorrect net.core.rmem_default sysctl override for lowend warp";
    }
  ];

  failedTests = builtins.filter (x: !x.assertion) tests;
  
in
if builtins.length failedTests > 0 then
  abort (builtins.head failedTests).message
else
  pkgs.runCommand "eval-sing-box-warp-test" {} "touch $out"
