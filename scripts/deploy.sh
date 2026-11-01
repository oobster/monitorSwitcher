#!/bin/zsh
# Installs (or updates) the server on THIS Mac from a built server package, publishes the laptop
# package for "Update from Server" and checks the result. Uses the saved settings (setup --yes).
# Usage: scripts/deploy.sh [dist/MonitorSwitcher-server-X.Y.Z.zip]   (default: newest in dist/)
set -euo pipefail
cd -- "$(dirname "$0")/.."

ZIP="${1:-$(/bin/ls -t dist/MonitorSwitcher-server-*.zip(N) 2>/dev/null | /usr/bin/head -1)}"
[[ -f "$ZIP" ]] || { echo 'No server package – run scripts/build.sh first.'; exit 1; }
NAME="$(/usr/bin/basename "$ZIP" .zip)"
VERSION="${NAME#MonitorSwitcher-server-}"
[[ -r "$HOME/.config/monitor-switch/config" ]] \
  || { echo 'Not set up on this Mac yet: unzip the package and run zsh setup.command once.'; exit 1; }

TMP="$(/usr/bin/mktemp -d)"
trap '/bin/rm -rf "$TMP"' EXIT
/usr/bin/ditto -x -k "$ZIP" "$TMP"
echo "▶ Deploying $NAME …"
/bin/zsh "$TMP/$NAME/setup.command" --yes

/bin/cp "$TMP/$NAME/dist/MonitorSwitcher-client-${VERSION%-dirty}.zip" dist/ 2>/dev/null || true

echo
echo '▶ Checking …'
sleep 3
APP="$HOME/Applications/MonitorSwitcher.app"
HAVE="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ok=1
[[ "$HAVE" == "${VERSION%-dirty}" ]] && echo "  ✓ app version $HAVE" || { echo "  ✖ app version $HAVE (expected $VERSION)"; ok=0; }
/usr/bin/pgrep -qx MonitorSwitcher && echo '  ✓ app running' || { echo '  ✖ app not running'; ok=0; }
if /usr/sbin/spctl --assess --type execute "$APP" 2>/dev/null; then echo '  ✓ Gatekeeper: accepted (notarized)'
else echo '  • Gatekeeper: not notarized (ad-hoc or --dirty build)'; fi
PUB="$(/bin/cat "$HOME/.local/share/monitor-switch/client/VERSION" 2>/dev/null || true)"
[[ "$PUB" == "${VERSION%-dirty}" ]] && echo "  ✓ published for laptops: $PUB" || { echo "  ✖ published for laptops: ${PUB:-none}"; ok=0; }
NOW="$("$HOME/.local/bin/monitor-switch" status 2>&1)" && echo "  ✓ monitor-switch status: $NOW" || { echo "  ✖ monitor-switch: $NOW"; ok=0; }
(( ok )) && echo "Deployed $VERSION." || { echo 'Deploy finished with problems (see above).'; exit 1; }
