#!/bin/zsh
# Quick tests, no windows and no real monitor (~30 s): script syntax, Swift type check, and the
# switching logic of monitor-switch against a fake m1ddc in a temporary HOME.
# Usage: scripts/test.sh
set -uo pipefail
cd -- "$(dirname "$0")/.."
ROOT="$PWD"
TMP="$(/usr/bin/mktemp -d)"
trap '/bin/rm -rf "$TMP"' EXIT
pass=0; fail=0
ok()  { pass=$(( pass + 1 )); print -r -- "  ✓ $1"; }
bad() { fail=$(( fail + 1 )); print -r -- "  ✖ $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

echo '▶ Syntax'
for f in setup.command install.command build-client.sh monitor-switch monitor-switch-ssh authorize-key.sh \
         client/install.command client/monitor-switch client/monitor-switch-update scripts/*.sh; do
  /bin/zsh -n "$f" 2>"$TMP/err" && ok "$f" || bad "$f: $(</"$TMP/err")"
done

echo '▶ Swift'
if /usr/bin/xcrun swiftc -parse-as-library -typecheck MonitorSwitcher.swift 2>"$TMP/err"; then ok 'MonitorSwitcher.swift type-checks'
else bad "MonitorSwitcher.swift: $(/usr/bin/head -5 "$TMP/err")"; fi

# --- Fake m1ddc --------------------------------------------------------------------------
# Displays in $FAKE/list, current input per display in $FAKE/in-<uuid>, every "set" logged to
# $FAKE/calls. $FAKE/ignore-<uuid> = how many commands that display ignores (power save).
# $FAKE/noread = the monitor can't report its input (reads 0). input-alt codes map like LG.
cat > "$TMP/m1ddc" <<'FAKE'
#!/bin/zsh
F="$FAKE_DDC"
[[ "$1" == display ]] || exit 1
if [[ "$2" == list ]]; then /bin/cat "$F/list"; exit 0; fi
id="$2"
grep -q "($id)" "$F/list" || { print 'The specified display does not exist.'; exit 1; }
case "$3 $4" in
  'get input')
    if [[ -e "$F/noread" ]]; then print 0; else /bin/cat "$F/in-$id" 2>/dev/null || print 0; fi ;;
  'set input'|'set input-alt')
    print -r -- "$id set $4 $5" >> "$F/calls"
    n="$(/bin/cat "$F/ignore-$id" 2>/dev/null || print 0)"
    if (( n > 0 )); then print $(( n - 1 )) > "$F/ignore-$id"; exit 0; fi
    v=$5
    [[ "$4" == input-alt ]] && case $v in 144) v=17 ;; 145) v=18 ;; 208) v=15 ;; 209) v=16 ;; 210) v=27 ;; esac
    print -n $v > "$F/in-$id" ;;
  *) exit 1 ;;
esac
FAKE
/bin/chmod 755 "$TMP/m1ddc"

MAIN=AAAAAAAA-0000-0000-0000-000000000001
SHARED=BBBBBBBB-0000-0000-0000-000000000002
n=0
new_case() {   # fresh HOME + fake monitors; shared monitor shows input $1; extra config lines in $2
  n=$(( n + 1 ))
  export HOME="$TMP/home$n" FAKE_DDC="$TMP/fake$n"
  /bin/mkdir -p "$HOME/.config/monitor-switch" "$FAKE_DDC"
  print -l "[1] TEST MAIN ($MAIN)" "[2] TEST SHARED ($SHARED)" > "$FAKE_DDC/list"
  print -n 15 > "$FAKE_DDC/in-$MAIN"; print -n "$1" > "$FAKE_DDC/in-$SHARED"; : > "$FAKE_DDC/calls"
  cat > "$HOME/.config/monitor-switch/config" <<CONF
MONITOR_NAME='TEST SHARED'
MONITOR_UUID='$SHARED'
INPUT_CMD=input
SERVER_INPUT=17
CLIENT_INPUT=18
SERVER_READ='17'
CLIENT_READ='18'
MAIN_UUID='$MAIN'
PROTECTED_UUIDS='$MAIN'
${2:-}
CONF
}
ms() { MONITOR_SWITCH_M1DDC="$TMP/m1ddc" /bin/zsh "$ROOT/monitor-switch" "$@" 2>"$TMP/stderr"; }
calls() { /usr/bin/wc -l < "$FAKE_DDC/calls" | /usr/bin/tr -d ' '; }
input() { /bin/cat "$FAKE_DDC/in-$SHARED"; }
real_home="$HOME"

echo '▶ monitor-switch (fake m1ddc)'
new_case 17
out="$(ms client)"; check 'server → laptops: one command, monitor on 18' '[[ "$out" == macbook && "$(input)" == 18 && "$(calls)" == 1 ]]'
out="$(ms toggle)"; check 'toggle back to the server' '[[ "$out" == mini && "$(input)" == 17 ]]'
out="$(ms status)"; check 'status reads the monitor' '[[ "$out" == mini ]]'
check 'main display never touched' '! /usr/bin/grep -q "$MAIN" "$FAKE_DDC/calls"'

new_case 18; print 1 > "$FAKE_DDC/ignore-$SHARED"
out="$(ms server)"; check 'power save: first command ignored, re-sent after the grace time' '[[ "$out" == mini && "$(input)" == 17 && "$(calls)" == 2 ]]'

new_case 17 "PROTECTED_UUIDS='$MAIN $SHARED'"
ms client >/dev/null; rc=$?
check 'protected display is refused' '(( rc != 0 )) && [[ "$(calls)" == 0 ]]'

new_case 17 $'INPUT_CMD=input-alt\nSERVER_INPUT=144\nCLIENT_INPUT=145'
out="$(ms client)"; check 'alternate addressing (input-alt 145, reads 18)' '[[ "$out" == macbook && "$(input)" == 18 ]] && /usr/bin/grep -q "set input-alt 145" "$FAKE_DDC/calls"'

new_case 17 $'SERVER_READ=\'\'\nCLIENT_READ=\'\''; : > "$FAKE_DDC/noread"
out="$(ms client)"; rc=$?
check 'monitor without read-back: one command, no waiting' '(( rc == 0 )) && [[ "$out" == macbook && "$(calls)" == 1 ]]'

new_case 17; /bin/rm "$HOME/.config/monitor-switch/config"
ms client >/dev/null; rc=$?
check 'not set up: clear error, nothing sent' '(( rc != 0 )) && [[ "$(calls)" == 0 ]] && /usr/bin/grep -q "setup.command" "$TMP/stderr"'
export HOME="$real_home"

echo
echo "$pass passed, $fail failed"
(( fail == 0 ))
