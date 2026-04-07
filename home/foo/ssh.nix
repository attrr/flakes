{ ... }:
{
  home.sessionVariables = {
    SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/ssh-agent.socket";
    SSH_ASKPASS = "$HOME/.local/bin/ssh-confirm";
    SSH_ASKPASS_REQUIRE = "force";
  };

  systemd.user.sessionVariables = {
    TPM2_PKCS11_BACKEND = "esysdb";
    TSS2_LOG = "fapi+NONE";
  };

  services.ssh-agent = {
    enable = true;
    socket = "ssh-agent.socket";
  };
}
