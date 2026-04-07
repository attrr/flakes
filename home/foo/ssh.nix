{ pkgs, ... }:
{
  home.file.".local/bin/ssh-confirm" = {
    executable = true;
    text = ''
      #!/bin/bash
      MESSAGE="$1"
      unset GTK_IM_MODULE

      if echo "$MESSAGE" | grep -qiE "PIN|ssh-tpm|passphrase"; then
        ${pkgs.zenity}/bin/zenity --password \
          --title="TPM PIN Required" \
          --text="$MESSAGE" \
          --icon="security-high-symbolic" \
          --width=400
      else
        ${pkgs.zenity}/bin/zenity --question \
          --title="SSH Key Authorization" \
          --text="$MESSAGE\n\nAllow this operation?" \
          --ok-label="Allow" \
          --cancel-label="Deny" \
          --icon="security-high-symbolic" \
          --width=450
      fi
    '';
  };

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
