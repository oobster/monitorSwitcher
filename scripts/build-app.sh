#!/bin/zsh
# Builds the universal (arm64 + x86_64) MonitorSwitcher.app from source.
#
# Signing: with a "Developer ID Application" identity in the keychain the app is signed with it
# (hardened runtime) and notarized with the notarytool profile AC_NOTARY, so it opens on any Mac
# without warnings. Without that identity it is signed ad-hoc – anyone can build it from source.
# Overrides: SIGN_IDENTITY="…" (or "-" for ad-hoc), NOTARY_PROFILE=name, --no-notarize.
#
# Used by scripts/build.sh, and by install.command / build-client.sh when run from the repository.
# Usage: scripts/build-app.sh <path>/MonitorSwitcher.app [--no-notarize]
set -euo pipefail

OUT_APP="${1:?Usage: scripts/build-app.sh <path>/MonitorSwitcher.app [--no-notarize]}"
[[ "$OUT_APP" == /* ]] || OUT_APP="$PWD/$OUT_APP"
NOTARIZE=1; [[ "${2:-}" == --no-notarize ]] && NOTARIZE=0
cd -- "$(dirname "$0")/.."

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

IDENTITY="${SIGN_IDENTITY-$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null \
  | /usr/bin/awk -F'"' '/Developer ID Application/ { print $2; exit }')}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"

if [[ -z "$IDENTITY" || "$IDENTITY" == - ]]; then
  /usr/bin/codesign --force --sign - "$OUT_APP" >/dev/null
  echo 'Signed ad-hoc (no Developer ID identity in the keychain).'
  exit 0
fi

/usr/bin/codesign --force --options runtime --timestamp --sign "$IDENTITY" "$OUT_APP"
/usr/bin/codesign --verify --strict "$OUT_APP"
echo "Signed: $IDENTITY"

(( NOTARIZE )) || { echo 'Not notarized (--no-notarize).'; exit 0; }
if ! /usr/bin/xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "Not notarized: notarytool profile '$NOTARY_PROFILE' is missing." >&2
  exit 0
fi
echo 'Notarizing (usually 1–5 minutes) …'
/usr/bin/ditto -c -k --keepParent "$OUT_APP" "$TMP/notarize.zip"
if /usr/bin/xcrun notarytool submit "$TMP/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait \
     > "$TMP/notary.log" 2>&1 && /usr/bin/grep -q 'status: Accepted' "$TMP/notary.log"; then
  /usr/bin/xcrun stapler staple -q "$OUT_APP"
  /usr/sbin/spctl --assess --type execute "$OUT_APP"
  echo 'Notarized and stapled.'
else
  /bin/cat "$TMP/notary.log" >&2
  echo 'Notarization failed (see above; details: xcrun notarytool log <id> --keychain-profile …).' >&2
  exit 1
fi
