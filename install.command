#!/bin/zsh
# Installs Monitor Switcher on the server (the Mac the shared monitor is connected to).
# Normally run by setup.command. Uses the prebuilt MonitorSwitcher.app from the server package;
# in the git repo (no prebuilt app) it builds the app from source first.
set -euo pipefail
cd -- "$(dirname "$0")"
VERSION="$(/bin/cat ./VERSION)"

if [[ ! -x /opt/homebrew/bin/m1ddc && ! -x /usr/local/bin/m1ddc ]]; then
  echo 'm1ddc is missing. First run: brew install m1ddc'
  exit 1
fi

# Pass the monitor settings (setup.command) on to the app.
apply_settings() {
  local D=si.obal.monitorswitcher
  /usr/bin/defaults write $D displayName     "$MONITOR_NAME"
  /usr/bin/defaults write $D serverLabel     "$SERVER_LABEL"
  /usr/bin/defaults write $D clientLabel     "$CLIENT_LABEL"
  /usr/bin/defaults write $D serverInputName "$SERVER_INPUT_NAME"
  /usr/bin/defaults write $D clientInputName "$CLIENT_INPUT_NAME"
}

# --- Migrate a server install from before 2.0 (then called Dell Switcher) ---------------
for pair in .config .local/state; do
  if [[ -d "$HOME/$pair/dell-switch" && ! -e "$HOME/$pair/monitor-switch" ]]; then
    /bin/mv "$HOME/$pair/dell-switch" "$HOME/$pair/monitor-switch"
  fi
done
AUTH="$HOME/.ssh/authorized_keys"
if [[ -f "$AUTH" ]] && /usr/bin/grep -q '/\.local/bin/dell-switch-ssh"' "$AUTH"; then
  /bin/cp -p "$AUTH" "$AUTH.before-monitor-switch"            # backup, just in case
  /usr/bin/sed -i '' 's#/\.local/bin/dell-switch-ssh"#/.local/bin/monitor-switch-ssh"#' "$AUTH"
  /bin/chmod 600 "$AUTH"
  echo 'Laptop keys migrated to Monitor Switcher.'
fi
/usr/bin/pkill -x DellSwitcher 2>/dev/null || true
/bin/rm -rf "$HOME/Applications/DellSwitcher.app"
/bin/rm -f "$HOME/.local/bin/dell-switch"
/usr/bin/defaults delete si.obal.dellswitcher >/dev/null 2>&1 || true

/bin/mkdir -p "$HOME/.local/bin" "$HOME/Applications"
/bin/cp ./monitor-switch "$HOME/.local/bin/monitor-switch"
/bin/cp ./monitor-switch-ssh "$HOME/.local/bin/monitor-switch-ssh"
/bin/chmod 755 "$HOME/.local/bin/monitor-switch" "$HOME/.local/bin/monitor-switch-ssh"
# Old forced-command path keeps working for any key line that still points to it.
/bin/ln -sf monitor-switch-ssh "$HOME/.local/bin/dell-switch-ssh"

TMPD="$(/usr/bin/mktemp -d)"
trap '/bin/rm -rf "$TMPD"' EXIT
if [[ -d ./MonitorSwitcher.app ]]; then
  SRC_APP=./MonitorSwitcher.app                       # prebuilt (server package)
else
  SRC_APP="$TMPD/MonitorSwitcher.app"                 # from source (git repo)
  ./build-app.sh "$SRC_APP"
fi

APP="$HOME/Applications/MonitorSwitcher.app"
/usr/bin/pkill -x MonitorSwitcher 2>/dev/null || true
/bin/rm -rf "$APP"
/usr/bin/ditto "$SRC_APP" "$APP"
/usr/bin/xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

CONFIG="$HOME/.config/monitor-switch/config"
if [[ -r "$CONFIG" ]]; then
  source "$CONFIG"
  apply_settings
fi

echo "Installed: $APP (version $VERSION)"
echo "CLI: $HOME/.local/bin/monitor-switch toggle|server|client|status"
echo "Monitor: ${MONITOR_NAME:-(not set – run setup.command)}, ${SERVER_LABEL:-Server} = ${SERVER_INPUT_NAME:-?}, ${CLIENT_LABEL:-Laptop} = ${CLIENT_INPUT_NAME:-?}"
echo 'Shortcut: ⌃⌥⌘M switches to the other computer'
/usr/bin/open "$APP"
