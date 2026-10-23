#!/bin/zsh
# Run on the server. Builds dist/MonitorSwitcher-client-<VERSION>.zip for the laptops, with the
# settings from setup.command and this server's SSH address. The app is universal and prebuilt,
# so the laptops need no developer tools. Normally run by setup.command.
# Usage: ./build-client.sh [user@host]
set -euo pipefail
cd -- "$(dirname "$0")"
VERSION="$(/bin/cat ./VERSION)"

CONFIG="$HOME/.config/monitor-switch/config"
[[ -r "$CONFIG" ]] && source "$CONFIG"
HOST="${1:-${SSH_HOST:-$USER@$(/usr/sbin/scutil --get LocalHostName).local}}"

OUT=dist/MonitorSwitcher-client
ZIP="MonitorSwitcher-client-$VERSION.zip"
/bin/rm -rf "$OUT" dist/MonitorSwitcher-client-*.zip(N)
/bin/mkdir -p "$OUT"

if [[ -d ./MonitorSwitcher.app ]]; then
  /usr/bin/ditto ./MonitorSwitcher.app "$OUT/MonitorSwitcher.app"     # prebuilt (server package)
else
  ./build-app.sh "$OUT/MonitorSwitcher.app"                        # from source (git repo)
fi
/usr/bin/xattr -dr com.apple.quarantine "$OUT/MonitorSwitcher.app" 2>/dev/null || true

/usr/bin/sed "s#__HOST__#$HOST#" ./client/monitor-switch > "$OUT/monitor-switch"
/bin/cp ./client/install.command ./client/monitor-switch-update ./client/INSTRUCTIONS.txt ./CHANGELOG.md ./LICENSE "$OUT/"
print -n "$VERSION" > "$OUT/VERSION"
# Monitor settings for the laptops (from setup.command).
cat > "$OUT/monitor-switch.conf" <<CONF
MONITOR_NAME=${(qq)MONITOR_NAME}
SERVER_LABEL=${(qq)${SERVER_LABEL:-Server}}
CLIENT_LABEL=${(qq)${CLIENT_LABEL:-Laptop}}
SERVER_INPUT_NAME=${(qq)${SERVER_INPUT_NAME:-HDMI 1}}
CLIENT_INPUT_NAME=${(qq)${CLIENT_INPUT_NAME:-HDMI 2}}
CONF
/bin/chmod 755 "$OUT/monitor-switch" "$OUT/install.command" "$OUT/monitor-switch-update"

(cd dist && /usr/bin/ditto -c -k --norsrc --noextattr --noqtn --keepParent MonitorSwitcher-client "$ZIP")
echo "Package: $PWD/dist/$ZIP  (version $VERSION, SSH target: $HOST)"
