MESSAGE="$1"
unset GTK_IM_MODULE

if echo "$MESSAGE" | grep -qiE "PIN|ssh-tpm"; then
  zenity --password \
    --title="TPM PIN Required" \
    --text="$MESSAGE" \
    --icon="security-high-symbolic" \
    --width=400
elif echo "$MESSAGE" | grep -qiE "Allow use of key"; then
  zenity --question \
    --title="SSH Key Authorization" \
    --text="$MESSAGE\n\nAllow this operation?" \
    --ok-label="Allow" \
    --cancel-label="Deny" \
    --icon="security-high-symbolic" \
    --width=450
else
  if echo "$MESSAGE" | grep -qi "password"; then
    read -rs -p "$MESSAGE" response </dev/tty
    echo "" >/dev/tty
  else
    read -r -p "$MESSAGE" response </dev/tty
  fi
  echo "$response"
fi
