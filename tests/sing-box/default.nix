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
          shadowsocks.passwordPath = "/secrets/dummy";
          # Test merging custom outbound
          settings.outbounds = [
            { type = "testing"; tag = "testing"; }
          ];
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
      assertion = builtins.length cfg.settings.outbounds == 3;
      message = "Should have 3 outbounds (2 default + 1 custom), got: ${builtins.toJSON cfg.settings.outbounds}";
    }
    {
      assertion = builtins.elem { type = "testing"; tag = "testing"; } cfg.settings.outbounds;
      message = "Custom outbound missing";
    }
    {
      assertion = cfg.settings.route.final == "direct";
      message = "Default route final mismatch";
    }
    {
      assertion = eval.config.users.users.sing-box.uid == cfg.uid;
      message = "User sing-box has incorrect UID";
    }
    {
      assertion = eval.config.users.groups.sing-box.gid == cfg.gid;
      message = "Group sing-box has incorrect GID";
    }
    {
      assertion = eval.config.containers.sing-box.autoStart == true;
      message = "Container sing-box not set to autoStart";
    }
    {
      assertion = eval.config.containers.sing-box.ephemeral == true;
      message = "Container sing-box not set to ephemeral";
    }
    {
      assertion = eval.config.containers.sing-box.privateNetwork == false;
      message = "Container sing-box set to privateNetwork";
    }
    {
      assertion = builtins.hasAttr "/secrets/dummy" eval.config.containers.sing-box.bindMounts;
      message = "Container sing-box bindMounts missing expected secret";
    }
  ];

  failedTests = builtins.filter (x: !x.assertion) tests;
  
in
{
  eval-sing-box-default = if builtins.length failedTests > 0 then
    abort (builtins.head failedTests).message
  else
    pkgs.runCommand "eval-sing-box-default-test" {} "touch $out";

  eval-sing-box-shadowsocks = import ./shadowsocks.nix { inherit pkgs; };
  eval-sing-box-hysteria2 = import ./hysteria2.nix { inherit pkgs; };
  eval-sing-box-warp = import ./warp.nix { inherit pkgs; };
}
