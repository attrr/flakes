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
          # Disable shadowsocks to isolate hysteria2
          shadowsocks.enable = false;
          hysteria2 = {
            enable = true;
            port = 5678;
            passwordPath = "/secrets/hy2_pw";
            tlsKeyPath = "/secrets/hy2_key";
            tlsCertificatePath = "/secrets/hy2_cert";
            echKeyPath = "/secrets/hy2_ech";
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
      assertion = builtins.elem "/secrets/hy2_pw" cfg.secrets;
      message = "Secrets missing hy2_pw";
    }
    {
      assertion = builtins.elem "/secrets/hy2_cert" cfg.secrets;
      message = "Secrets missing hy2_cert";
    }
    {
      assertion = builtins.elem 5678 cfg.udpPorts;
      message = "UDP ports missing 5678";
    }
    {
      assertion = ! builtins.elem 5678 cfg.tcpPorts;
      message = "TCP ports should not have hy2 port";
    }
    {
      assertion = builtins.elem 5678 eval.config.networking.firewall.allowedUDPPorts;
      message = "Firewall UDP ports missing 5678";
    }
    {
      assertion = ! builtins.elem 5678 eval.config.networking.firewall.allowedTCPPorts;
      message = "Firewall TCP ports should not have hy2 port";
    }
    {
      assertion = builtins.elem {
        type = "hysteria2";
        tag = "hy2";
        listen = "::";
        listen_port = 5678;
        up_mbps = 100;
        down_mbps = 100;
        users = [
          {
            name = "whoami";
            password._secret = "/secrets/hy2_pw";
          }
        ];
        tls = {
          enabled = true;
          alpn = [ "h3" ];
          key_path = "/secrets/hy2_key";
          certificate_path = "/secrets/hy2_cert";
          ech = {
            enabled = true;
            key_path = "/secrets/hy2_ech";
          };
        };
      } cfg.settings.inbounds;
      message = "Inbounds missing expected hysteria2 object";
    }
  ];

  failedTests = builtins.filter (x: !x.assertion) tests;
  
in
if builtins.length failedTests > 0 then
  abort (builtins.head failedTests).message
else
  pkgs.runCommand "eval-sing-box-hysteria2-test" {} "touch $out"
