#!/bin/zsh
# Quick tests, no windows and no real monitor (~30 s): script syntax, Swift type check, the
# switching logic of monitor-switch against a fake m1ddc in a temporary HOME, and authorize-key.sh
# with throwaway keys in a temporary HOME.
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

# --- authorize-key.sh: throwaway keys, fake HOME (the real ~/.ssh is never touched) ----------
echo '▶ authorize-key.sh (fake HOME)'
/bin/mkdir -p "$TMP/keys"
HOME="$TMP/keys" /usr/bin/ssh-keygen -q -t ed25519 -N '' -C laptop-a -f "$TMP/keys/a" </dev/null
HOME="$TMP/keys" /usr/bin/ssh-keygen -q -t ed25519 -N '' -C laptop-b -f "$TMP/keys/b" </dev/null
KA="$(<"$TMP/keys/a.pub")"; KB="$(<"$TMP/keys/b.pub")"
ak_case() { AK_HOME="$TMP/ak$(( ++n ))"; /bin/mkdir -p "$AK_HOME"; AK="$AK_HOME/.ssh/authorized_keys"; }
ak() { HOME="$AK_HOME" /bin/zsh "$ROOT/authorize-key.sh" "$@" >/dev/null 2>"$TMP/stderr"; }
ak_lines() { [[ -f "$AK" ]] || { print 0; return 0; }; /usr/bin/wc -l < "$AK" | /usr/bin/tr -d ' '; }
ak_unrestricted() {   # lines without the forced command + restrict prefix (grep -c prints 0 and exits 1)
  [[ -f "$AK" ]] || { print 0; return 0; }
  /usr/bin/grep -c -v '^command="[^"]*monitor-switch-ssh",restrict ssh-ed25519 ' "$AK"; return 0
}

ak_case; ak "$KA"; rc=$?
check 'one key: added with forced command + restrict' '(( rc == 0 )) && [[ "$(ak_lines)" == 1 && "$(ak_unrestricted)" == 0 ]]'
ak "$KA"; rc=$?
check 'same key again: nothing added' '(( rc == 0 )) && [[ "$(ak_lines)" == 1 ]]'

ak_case; ak "$KA"$'\n'"$KB"; rc=$?
check 'two keys with a newline: refused, nothing written' '(( rc != 0 )) && [[ "$(ak_lines)" == 0 ]]'
ak_case; ak "$KA"$'\r'"$KB"; rc=$?
check 'two keys with a carriage return: refused, nothing written' '(( rc != 0 )) && [[ "$(ak_lines)" == 0 ]]'
ak_exact() {   # the only line is exactly the restricted form of $1
  [[ -f "$AK" && "$(ak_lines)" == 1 ]] || return 1
  [[ "$(<"$AK")" == "command=\"$AK_HOME/.local/bin/monitor-switch-ssh\",restrict $1" ]]
}
ak_case; ak "$KA"$'\n'; rc=$?
check 'one trailing newline: dropped, key added with forced command + restrict' '(( rc == 0 )) && ak_exact "$KA"'
ak_case; ak "$KA"$'\r\n'; rc=$?
check 'one trailing CRLF: dropped, key added with forced command + restrict' '(( rc == 0 )) && ak_exact "$KA"'
ak_case; ak "$KA"$'\n\n'; rc=$?
check 'two trailing newlines: refused, nothing written' '(( rc != 0 )) && [[ "$(ak_lines)" == 0 ]]'
ak_case; ak "$KA"$'\r'; rc=$?
check 'trailing bare carriage return: refused, nothing written' '(( rc != 0 )) && [[ "$(ak_lines)" == 0 ]]'
ak_case; ak "${KA% *}"$'\n'" ${KA##* }"; rc=$?
check 'newline inside one key: refused, nothing written' '(( rc != 0 )) && [[ "$(ak_lines)" == 0 ]]'
ak_case; ak "$KA"$'\n'"$KB"$'\n'; rc=$?
check 'two keys plus trailing newline: refused, nothing written' '(( rc != 0 )) && [[ "$(ak_lines)" == 0 ]]'

ak_case; ak "ssh-ed25519 ${${KA#ssh-ed25519 }[1,40]}xx not-a-key"; rc=$?
check 'malformed key body: refused' '(( rc != 0 )) && [[ "$(ak_lines)" == 0 ]]'
ak_case; ak "${KA% *} $KB"; rc=$?
check 'second key glued on one line: never an unrestricted line' '(( rc != 0 )) || [[ "$(ak_unrestricted)" == 0 ]]'

ak_case; /bin/mkdir -p "$AK_HOME/.ssh"; print -r -- "$KA" > "$AK"
ak "$KA"; rc=$?
check 'key already present without restrictions: left unchanged, error' '(( rc != 0 )) && [[ "$(ak_lines)" == 1 && "$(ak_unrestricted)" == 1 ]]'

# --- Take-over / release order: the real TakeoverSequencer on a virtual clock ----------------
echo '▶ take-over / release order (simulated, no SSH)'
SIM="$TMP/sim"; /bin/mkdir -p "$SIM"
{ print 'import Foundation'
  /usr/bin/sed -n '/^\/\/ >>> TakeoverSequencer/,/^\/\/ <<< TakeoverSequencer/p' MonitorSwitcher.swift
} > "$SIM/Sequencer.swift"
/bin/cp scripts/takeover-sim.swift "$SIM/main.swift"
if ! /usr/bin/grep -q '^final class TakeoverSequencer' "$SIM/Sequencer.swift"; then
  bad 'TakeoverSequencer block not found in MonitorSwitcher.swift'
elif ! /usr/bin/xcrun swiftc -o "$SIM/sim" "$SIM/Sequencer.swift" "$SIM/main.swift" 2>"$TMP/err"; then
  bad "take-over simulation does not build: $(/usr/bin/head -5 "$TMP/err")"
else
  "$SIM/sim" > "$SIM/out" 2>"$SIM/log"
  while read -r st name; do
    [[ "$st" == PASS ]] && ok "$name" || bad "$name"
  done < "$SIM/out"
  [[ -s "$SIM/out" ]] || bad 'take-over simulation printed nothing'
  [[ -s "$SIM/log" ]] && /usr/bin/sed 's/^/  /' "$SIM/log"
fi

echo
echo "$pass passed, $fail failed"
(( fail == 0 ))
