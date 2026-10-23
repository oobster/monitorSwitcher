#!/bin/zsh
# Builds the universal (arm64 + x86_64), ad-hoc signed MonitorSwitcher.app from source.
# Used by release.sh, and by install.command / build-client.sh when run from the git repo.
# Usage: ./build-app.sh <path>/MonitorSwitcher.app
set -euo pipefail
cd -- "$(dirname "$0")"

OUT_APP="${1:?Usage: ./build-app.sh <path>/MonitorSwitcher.app}"
/usr/bin/xcrun --find swiftc >/dev/null 2>&1 || {
  echo 'The Swift compiler is missing. Install the Command Line Tools: xcode-select --install'; exit 1; }

VERSION="$(/bin/cat ./VERSION)"
BUILD_NO="$(/usr/bin/git rev-list --count HEAD 2>/dev/null || echo 1)"
TMP="$(/usr/bin/mktemp -d)"
trap '/bin/rm -rf "$TMP"' EXIT

echo "Building Monitor Switcher $VERSION (arm64 + x86_64) …"
for arch in arm64 x86_64; do
  if ! /usr/bin/xcrun swiftc -O -parse-as-library -target "$arch-apple-macosx13.0" \
         ./MonitorSwitcher.swift -o "$TMP/MonitorSwitcher-$arch" 2>"$TMP/err-$arch"; then
    /bin/cat "$TMP/err-$arch" >&2; exit 1
  fi
done

/bin/rm -rf "$OUT_APP"
/bin/mkdir -p "$OUT_APP/Contents/MacOS"
/usr/bin/lipo -create "$TMP/MonitorSwitcher-arm64" "$TMP/MonitorSwitcher-x86_64" \
  -output "$OUT_APP/Contents/MacOS/MonitorSwitcher"
/usr/bin/sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NO/" ./Info.plist \
  > "$OUT_APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$OUT_APP" >/dev/null
