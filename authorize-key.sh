#!/bin/zsh
# Run on the server. Allows a public key to switch the shared monitor over SSH, and nothing else.
# Usage: ./authorize-key.sh "ssh-ed25519 AAAA... monitorswitch-<laptop>"
set -euo pipefail

KEY="${1:-}"
# A single line break at the very end (\n or \r\n, e.g. from copy and paste) is dropped silently.
if [[ "$KEY" == *$'\r\n' ]]; then
  KEY="${KEY%$'\r\n'}"
elif [[ "$KEY" == *$'\n' ]]; then
  KEY="${KEY%$'\n'}"
fi
# Exactly one line: any other line break could put a second line into authorized_keys without
# the restrictions below.
if [[ "$KEY" == *$'\n'* || "$KEY" == *$'\r'* ]]; then
  echo 'Pass exactly one public key on a single line (the text contains a line break).' >&2
  exit 1
fi
if [[ "$KEY" != ssh-ed25519\ * ]]; then
  echo 'Pass the public key in quotes, e.g.: ./authorize-key.sh "ssh-ed25519 AAAA... name"'
  exit 1
fi

# Rebuild the line from its fields (type, body, optional comment), like the app does.
parts=(${=KEY})
KEY_TYPE="$parts[1]"
KEY_BODY="${parts[2]:-}"
KEY_COMMENT="${(j: :)parts[3,-1]}"
BODY_RE='^[A-Za-z0-9+/]{60,}={0,2}$'
if [[ "$KEY_TYPE" != ssh-ed25519 ]] || ! [[ "$KEY_BODY" =~ $BODY_RE ]]; then
  echo 'That is not a valid public key. Pass the whole line, starting with "ssh-ed25519 AAAA...".' >&2
  exit 1
fi
LINE="$KEY_TYPE $KEY_BODY${KEY_COMMENT:+ $KEY_COMMENT}"

# ssh-keygen must read exactly one valid public key from it (temporary file, removed on exit).
TMP_KEY="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/authorize-key.XXXXXX")"
trap '/bin/rm -f "$TMP_KEY"' EXIT
print -r -- "$LINE" > "$TMP_KEY"
if ! FINGERPRINTS="$(/usr/bin/ssh-keygen -l -f "$TMP_KEY" 2>/dev/null)" \
   || [[ -z "$FINGERPRINTS" || "$FINGERPRINTS" == *$'\n'* ]]; then
  echo 'That is not a valid public key (ssh-keygen could not read exactly one key).' >&2
  exit 1
fi

AUTH="$HOME/.ssh/authorized_keys"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
touch "$AUTH" && chmod 600 "$AUTH"

# Same rules as the app: ours already (forced command) -> nothing to do; present without
# restrictions -> leave it alone and say so.
ours=0; unrestricted=0
while IFS= read -r l || [[ -n "$l" ]]; do
  [[ "$l" == *"$KEY_BODY"* ]] || continue
  if [[ "$l" == *monitor-switch-ssh* || "$l" == *dell-switch-ssh* ]]; then ours=1; else unrestricted=1; fi
done < "$AUTH"
if (( ours )); then
  echo 'This key has already been added.'
  exit 0
fi
if (( unrestricted )); then
  echo 'This key is already in authorized_keys without restrictions - leaving it unchanged.' >&2
  exit 1
fi

# 'restrict' = no shell, no port/agent forwarding; the command is forced.
print -r -- "command=\"$HOME/.local/bin/monitor-switch-ssh\",restrict $LINE" >> "$AUTH"
echo 'Key added: it can only switch the monitor.'
