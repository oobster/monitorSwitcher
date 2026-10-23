#!/bin/zsh
# Run on the server. Allows a public key to switch the shared monitor over SSH, and nothing else.
# Usage: ./authorize-key.sh "ssh-ed25519 AAAA... monitorswitch-<laptop>"
set -euo pipefail

KEY="${1:-}"
if [[ "$KEY" != ssh-ed25519\ * ]]; then
  echo 'Pass the public key in quotes, e.g.: ./authorize-key.sh "ssh-ed25519 AAAA... name"'
  exit 1
fi

AUTH="$HOME/.ssh/authorized_keys"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
touch "$AUTH" && chmod 600 "$AUTH"

KEY_BODY="$(print -r -- "$KEY" | /usr/bin/awk '{print $2}')"
if /usr/bin/grep -qF "$KEY_BODY" "$AUTH"; then
  echo 'This key has already been added.'
  exit 0
fi

# 'restrict' = no shell, no port/agent forwarding; the command is forced.
print -r -- "command=\"$HOME/.local/bin/monitor-switch-ssh\",restrict $KEY" >> "$AUTH"
echo 'Key added: it can only switch the monitor.'
