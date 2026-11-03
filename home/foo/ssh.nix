{ lib, pkgs, ... }:
let
  # askpass for the agents: tpm pin and key confirmation dialogs
  ssh-confirm = pkgs.writeShellApplication {
    name = "ssh-confirm";
    runtimeInputs = with pkgs; [
      zenity
      gnugrep
    ];
    text = builtins.readFile ./ssh-confirm.sh;
  };
  askpass = {
    SSH_ASKPASS = lib.getExe ssh-confirm;
    SSH_ASKPASS_REQUIRE = "force";
  };
in
{
  home.sessionVariables = askpass // {
    SSH_AUTH_SOCK = lib.mkForce "$XDG_RUNTIME_DIR/ssh-agent.socket";
  };
  # else ssh-tpm-agent points SSH_AUTH_SOCK at itself in the shell rc
  sshAuthSock.initialization = lib.mkForce null;

  # the agents run under systemd, not the login shell
  systemd.user.sessionVariables = askpass // {
    TPM2_PKCS11_BACKEND = "esysdb";
    TSS2_LOG = "fapi+NONE";
  };

  services.ssh-tpm-agent = {
    enable = true;
  };

  services.ssh-agent = {
    enable = true;
    socket = "ssh-agent.socket";
  };
}
