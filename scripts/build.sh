#!/bin/zsh
# Builds dist/MonitorSwitcher-server-<VERSION>.zip: everything the server needs, with a prebuilt
# universal app (signed and notarized when the Developer ID identity is available). On the server
# you unzip it and run setup.command, which installs the server and builds the laptop package.
#
# A build needs a clean, committed tree and creates the tag v<VERSION>, so every version can be
# rebuilt from its tag. Only the last two versions are kept in dist/.
# Usage: scripts/build.sh            release build (clean tree, new version, tag)
#        scripts/build.sh --dirty    local test of uncommitted changes (no tag, not for release)
set -euo pipefail
cd -- "$(dirname "$0")/.."

DIRTY=0; [[ "${1:-}" == --dirty ]] && DIRTY=1
VERSION="$(/bin/cat ./VERSION)"
TAG="v$VERSION"
if (( ! DIRTY )); then
  [[ -z "$(/usr/bin/git status --porcelain)" ]] || { echo 'Uncommitted changes – commit first, or use --dirty.'; exit 1; }
  if /usr/bin/git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "Tag $TAG already exists – bump VERSION."; exit 1
  fi
fi

NAME="MonitorSwitcher-server-$VERSION"; (( DIRTY )) && NAME="$NAME-dirty"
OUT="dist/$NAME"
/bin/rm -rf "$OUT" "dist/$NAME.zip"
/bin/mkdir -p "$OUT/client"

NOTARIZE_ARG=(); (( DIRTY )) && NOTARIZE_ARG=(--no-notarize)
scripts/build-app.sh "$OUT/MonitorSwitcher.app" "${NOTARIZE_ARG[@]}"

/bin/cp ./setup.command ./install.command ./build-client.sh \
        ./monitor-switch ./monitor-switch-ssh ./authorize-key.sh \
        ./VERSION ./CHANGELOG.md ./README.md ./LICENSE "$OUT/"
/bin/cp ./server/INSTRUCTIONS.txt "$OUT/INSTRUCTIONS.txt"
/bin/cp ./client/monitor-switch ./client/monitor-switch-update ./client/install.command ./client/INSTRUCTIONS.txt "$OUT/client/"
/bin/chmod 755 "$OUT"/*.command "$OUT"/*.sh "$OUT/monitor-switch" "$OUT/monitor-switch-ssh" \
               "$OUT/client/monitor-switch" "$OUT/client/install.command" "$OUT/client/monitor-switch-update"

(cd dist && /usr/bin/ditto -c -k --norsrc --noextattr --noqtn --keepParent "$NAME" "$NAME.zip")
/bin/rm -rf "$OUT"

if (( ! DIRTY )); then
  /usr/bin/git tag -a "$TAG" -m "Monitor Switcher $VERSION"
  echo "Tag $TAG created (push: git push --follow-tags)."
fi

# Keep the last two versions locally; older ones can be rebuilt from their tags.
/bin/ls -t dist/MonitorSwitcher-server-*.zip(N) | /usr/bin/tail -n +3 | /usr/bin/xargs -r /bin/rm -f
/bin/ls -t dist/MonitorSwitcher-client-*.zip(N) | /usr/bin/tail -n +3 | /usr/bin/xargs -r /bin/rm -f

echo "Server package: $PWD/dist/$NAME.zip"
echo 'Install on the server: scripts/deploy.sh (or unzip it there and run: zsh setup.command)'
