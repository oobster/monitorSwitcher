#!/bin/zsh
# Run in the git repo. Builds dist/MonitorSwitcher-server-<VERSION>.zip: everything the server needs,
# with a prebuilt universal app (the server needs no developer tools). On the server you unzip it
# and run setup.command, which installs the server and builds the client zip for the laptops.
# Usage: ./release.sh
set -euo pipefail
cd -- "$(dirname "$0")"

VERSION="$(/bin/cat ./VERSION)"
NAME="MonitorSwitcher-server-$VERSION"
OUT="dist/$NAME"

/bin/rm -rf "$OUT" "dist/$NAME.zip"
/bin/mkdir -p "$OUT/client"

./build-app.sh "$OUT/MonitorSwitcher.app"

/bin/cp ./setup.command ./install.command ./build-client.sh \
        ./monitor-switch ./monitor-switch-ssh ./authorize-key.sh \
        ./VERSION ./CHANGELOG.md ./README.md ./LICENSE "$OUT/"
/bin/cp ./server/INSTRUCTIONS.txt "$OUT/INSTRUCTIONS.txt"
/bin/cp ./client/monitor-switch ./client/monitor-switch-update ./client/install.command ./client/INSTRUCTIONS.txt "$OUT/client/"
/bin/chmod 755 "$OUT"/*.command "$OUT"/*.sh "$OUT/monitor-switch" "$OUT/monitor-switch-ssh" \
               "$OUT/client/monitor-switch" "$OUT/client/install.command" "$OUT/client/monitor-switch-update"

(cd dist && /usr/bin/ditto -c -k --norsrc --noextattr --noqtn --keepParent "$NAME" "$NAME.zip")
/bin/rm -rf "$OUT"
echo "Server package: $PWD/dist/$NAME.zip"
echo 'On the server: unzip it, then in Terminal: zsh setup.command'
