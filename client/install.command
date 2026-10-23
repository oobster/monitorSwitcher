#!/bin/zsh
# Installs Monitor Switcher on a Mac that switches the shared monitor through the server (SSH).
# Run in Terminal:  zsh install.command
# (--update: non-interactive, used by "Update from Server" / monitor-switch-update)
set -euo pipefail
cd -- "$(dirname "$0")"
UPDATE=0; [[ "${1:-}" == --update ]] && UPDATE=1

mkdir -p "$HOME/.local/bin" "$HOME/Applications" "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# --- Migrate a laptop install from before 2.0 (then called Dell Switcher) ----------------
OLD_D=si.obal.dellswitcher
D=si.obal.monitorswitcher
/usr/bin/pkill -x DellSwitcher 2>/dev/null || true
/bin/rm -rf "$HOME/Applications/DellSwitcher.app"
/bin/rm -f "$HOME/.local/bin/dell-switch"
for ext in '' .pub; do      # keep the same key, so the server keeps accepting this laptop
  if [[ -f "$HOME/.ssh/dellswitch_ed25519$ext" && ! -e "$HOME/.ssh/monitorswitch_ed25519$ext" ]]; then
    /bin/mv "$HOME/.ssh/dellswitch_ed25519$ext" "$HOME/.ssh/monitorswitch_ed25519$ext"
  fi
done
if [[ -d "$HOME/.local/state/dell-switch" && ! -e "$HOME/.local/state/monitor-switch" ]]; then
  /bin/mv "$HOME/.local/state/dell-switch" "$HOME/.local/state/monitor-switch"
fi
for k in autoTakeover autoRelease; do   # keep the user's menu choices
  if v="$(/usr/bin/defaults read $OLD_D $k 2>/dev/null)"; then
    [[ "$v" == 1 ]] && /usr/bin/defaults write $D $k -bool true || /usr/bin/defaults write $D $k -bool false
  fi
done
/usr/bin/defaults delete $OLD_D >/dev/null 2>&1 || true

cp ./monitor-switch ./monitor-switch-update "$HOME/.local/bin/"
chmod 755 "$HOME/.local/bin/monitor-switch" "$HOME/.local/bin/monitor-switch-update"

APP="$HOME/Applications/MonitorSwitcher.app"
echo "Installing Monitor Switcher $(/bin/cat ./VERSION 2>/dev/null) …"
/usr/bin/pkill -x MonitorSwitcher 2>/dev/null || true
rm -rf "$APP"
/usr/bin/ditto ./MonitorSwitcher.app "$APP"
/usr/bin/xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

KEY="$HOME/.ssh/monitorswitch_ed25519"
if [[ ! -f "$KEY" ]]; then
  /usr/bin/ssh-keygen -q -t ed25519 -N '' -C "monitorswitch-$(/usr/sbin/scutil --get LocalHostName)" -f "$KEY"
fi

echo
if (( UPDATE )); then
  echo "Updated to $(/bin/cat ./VERSION 2>/dev/null)."
elif "$HOME/.local/bin/monitor-switch" status >/dev/null 2>&1; then
  echo '✅ Connected to the server. Plug in the shared monitor and it switches to this computer;'
  echo '   unplug it or put this computer to sleep and it goes back to the server.'
else
  /usr/bin/pbcopy < "$KEY.pub"
  echo 'One more step: send this public key (already on the clipboard) to whoever runs the server.'
  echo 'On the server, paste it into: menu bar icon → Laptop Keys … → Add.'
  echo
  cat "$KEY.pub"
  echo
  echo 'Once it is added, switching works – no need to reinstall.'
fi

# Laptop mode: claim the monitor automatically when its cable is plugged in.
/usr/bin/defaults write $D role client
# Monitor settings from the server (setup.command).
if [[ -r ./monitor-switch.conf ]]; then
  source ./monitor-switch.conf
  /usr/bin/defaults write $D displayName     "$MONITOR_NAME"
  /usr/bin/defaults write $D serverLabel     "$SERVER_LABEL"
  /usr/bin/defaults write $D clientLabel     "$CLIENT_LABEL"
  /usr/bin/defaults write $D serverInputName "$SERVER_INPUT_NAME"
  /usr/bin/defaults write $D clientInputName "$CLIENT_INPUT_NAME"
fi

open "$APP"
