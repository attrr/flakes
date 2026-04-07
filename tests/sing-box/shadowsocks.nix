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
          shadowsocks = {
            enable = true;
            port = 1234;
            passwordPath = "/secrets/ss.txt";
          };
          hysteria2.enable = false;
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
      assertion = builtins.elem "/secrets/ss.txt" cfg.secrets;
      message = "Secrets should contain passwordPath";
    }
    {
      assertion = builtins.elem 1234 cfg.tcpPorts;
      message = "TCP ports should contain 1234";
    }
    {
      assertion = builtins.elem 1234 cfg.udpPorts;
      message = "UDP ports should contain 1234";
    }
    {
      assertion = builtins.elem 1234 eval.config.networking.firewall.allowedTCPPorts;
      message = "Firewall TCP ports should contain 1234";
    }
    {
      assertion = builtins.elem 1234 eval.config.networking.firewall.allowedUDPPorts;
      message = "Firewall UDP ports should contain 1234";
    }
    {
      assertion = builtins.elem {
        type = "shadowsocks";
        tag = "ss";
        method = "2022-blake3-aes-128-gcm";
        password._secret = "/secrets/ss.txt";
        listen = "0.0.0.0";
        listen_port = 1234;
        multiplex.enabled = true;
      } cfg.settings.inbounds;
      message = "Inbounds should contain expected shadowsocks object";
    }
  ];

  failedTests = builtins.filter (x: !x.assertion) tests;
  
in
if builtins.length failedTests > 0 then
  abort (builtins.head failedTests).message
else
  pkgs.runCommand "eval-sing-box-shadowsocks-test" {} "touch $out"
