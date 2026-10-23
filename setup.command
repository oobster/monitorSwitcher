#!/bin/zsh
# Monitor Switcher setup – run on the server: the Mac the shared monitor is connected to.
# Shows the displays, asks which one is main and which one may be switched, which inputs the
# server and the laptops use, saves the settings (incl. this Mac's own SSH address), installs
# the server side and builds a separate client zip for the laptops (AirDrop it to them).
#
#   zsh setup.command          interactive (Enter accepts the suggestion in [brackets])
#   zsh setup.command --yes    accept all suggestions (e.g. re-run with the same monitors)
#   options: --main N  --shared N  --server-input CODE  --client-input CODE  --input-alt
#            --host user@host   (CODE = standard DDC input code, see the list setup prints)
set -euo pipefail
cd -- "$(dirname "$0")"

YES=0; OPT_MAIN=''; OPT_SHARED=''; OPT_SERVER=''; OPT_CLIENT=''; OPT_HOST=''; OPT_ALT=0
while (( $# )); do
  case "$1" in
    --yes|-y)       YES=1 ;;
    --input-alt)    OPT_ALT=1 ;;
    --main)         OPT_MAIN="$2"; shift ;;
    --shared)       OPT_SHARED="$2"; shift ;;
    --server-input) OPT_SERVER="$2"; shift ;;
    --client-input) OPT_CLIENT="$2"; shift ;;
    --host)         OPT_HOST="$2"; shift ;;
    -h|--help)      /usr/bin/sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1 (see --help)"; exit 2 ;;
  esac
  shift
done

die() { print -u2 -- "✖ $*"; exit 1; }

ask() {   # ask "question" "suggestion"  -> $REPLY
  if (( YES )); then REPLY="$2"; print -r -- "$1 [$2]: $2"; return 0; fi
  read -r "REPLY?$1 [$2]: " || true
  [[ -z "$REPLY" ]] && REPLY="$2"
  return 0
}

# Standard DDC/CI (MCCS) input codes, as monitors report them; 27 is the usual USB-C code.
input_name() {
  case "$1" in
    1) print 'VGA 1' ;;           2) print 'VGA 2' ;;           3) print 'DVI 1' ;;
    4) print 'DVI 2' ;;           5) print 'Composite 1' ;;     6) print 'Composite 2' ;;
    7) print 'S-Video 1' ;;       8) print 'S-Video 2' ;;       9) print 'Tuner 1' ;;
    10) print 'Tuner 2' ;;        11) print 'Tuner 3' ;;        12) print 'Component 1' ;;
    13) print 'Component 2' ;;    14) print 'Component 3' ;;    15) print 'DisplayPort 1' ;;
    16) print 'DisplayPort 2' ;;  17) print 'HDMI 1' ;;         18) print 'HDMI 2' ;;
    27) print 'USB-C' ;;
    # alternate addressing (input-alt, e.g. LG)
    144) print 'HDMI 1' ;;        145) print 'HDMI 2' ;;        208) print 'DisplayPort 1' ;;
    209) print 'DisplayPort 2' ;; 210) print 'USB-C / DisplayPort 3' ;;
    *) print "input $1" ;;
  esac
}
# Standard code -> code for alternate addressing (input-alt), where known.
to_alt() {
  case "$1" in 15) print 208 ;; 16) print 209 ;; 17) print 144 ;; 18) print 145 ;; 27) print 210 ;; *) print "$1" ;; esac
}
INPUTS_HELP='15 DisplayPort 1 · 16 DisplayPort 2 · 17 HDMI 1 · 18 HDMI 2 · 27 USB-C · 3 DVI 1 · 1 VGA 1'

# --- Requirements ------------------------------------------------------------------------
if   [[ -x /opt/homebrew/bin/m1ddc ]]; then M1DDC=/opt/homebrew/bin/m1ddc
elif [[ -x /usr/local/bin/m1ddc ]];    then M1DDC=/usr/local/bin/m1ddc
else die 'm1ddc is missing. First run: brew install m1ddc'; fi
# The server package ships a prebuilt app; only the git repo needs the Swift compiler.
[[ -d ./MonitorSwitcher.app ]] || /usr/bin/xcrun --find swiftc >/dev/null 2>&1 \
  || die 'Swift is missing. Run: xcode-select --install (or use the MonitorSwitcher-server zip)'

# Previous answers become the suggestions.
CONFIG_DIR="$HOME/.config/monitor-switch"
# Settings from before 2.0 (Dell Switcher) become the suggestions.
if [[ -d "$HOME/.config/dell-switch" && ! -e "$CONFIG_DIR" ]]; then
  /bin/mv "$HOME/.config/dell-switch" "$CONFIG_DIR"
fi
CONFIG="$CONFIG_DIR/config"
MONITOR_NAME=''; MONITOR_UUID=''; SERVER_INPUT=''; CLIENT_INPUT=''
SERVER_LABEL=''; CLIENT_LABEL=''; SSH_HOST=''; MAIN_UUID=''; PROTECTED_UUIDS=''
INPUT_CMD=''; SERVER_READ=''; CLIENT_READ=''
[[ -r "$CONFIG" ]] && source "$CONFIG"
PREV_NAME="$MONITOR_NAME"

# --- Displays ----------------------------------------------------------------------------
names=(); uuids=()
for line in "${(@f)$("$M1DDC" display list 2>/dev/null)}"; do
  if [[ "$line" =~ '^\[([0-9]+)\] (.*) \(([0-9A-Fa-f-]+)\)$' ]]; then
    names+=("$match[2]"); uuids+=("$match[3]")
  fi
done
(( ${#names} )) || die 'm1ddc does not see any external display.'

# Where the menu bar is (macOS main display) – only a suggestion, the user decides.
MAIN_SYS="$(/usr/sbin/system_profiler SPDisplaysDataType 2>/dev/null | /usr/bin/awk '
  /^        [^ ].*:$/ { n = $0; sub(/^ +/, "", n); sub(/:$/, "", n) }
  /Main Display: Yes/   { print n; exit }')"

n=${#names}
menubar_i=0; prev_main_i=0; prev_shared_i=0; inputs=()
for i in {1..$n}; do
  [[ "$names[i]" == "$MAIN_SYS" && $menubar_i == 0 ]] && menubar_i=$i
  [[ -n "$MAIN_UUID"    && "$uuids[i]" == "$MAIN_UUID"    ]] && prev_main_i=$i
  [[ -n "$MONITOR_UUID" && "$uuids[i]" == "$MONITOR_UUID" ]] && prev_shared_i=$i
  v="$("$M1DDC" display "$uuids[i]" get input 2>/dev/null | /usr/bin/tr -dc '0-9' || true)"
  [[ "$v" == <1-> ]] || v=''    # some monitors report 0 when they don't expose the current input
  inputs+=("$v")
done

echo
echo "Displays found ($n):"
for i in {1..$n}; do
  notes=()
  (( i == menubar_i ))     && notes+=('menu bar')
  (( i == prev_main_i ))   && notes+=('was: main')
  (( i == prev_shared_i )) && notes+=('was: shared')
  in="${inputs[i]:-?}"; [[ -n "$inputs[i]" ]] && in="$in, $(input_name $inputs[i])"
  printf '  %d) %-16s input %-18s %s\n' $i "$names[i]" "$in" "${(j:, :)notes}"
done

while true; do
  echo
  # Main display: stays with the server, never switched.
  def_main=${prev_main_i:#0}; def_main=${def_main:-${menubar_i:#0}}; def_main=${def_main:-1}
  if (( n == 1 )); then
    main_i=0
    echo 'Only one external display found – it will be the shared one; there is no external main display.'
  else
    if [[ -n "$OPT_MAIN" ]]; then REPLY="$OPT_MAIN"
    else ask 'Which display is the MAIN one (stays with this server, never switched)?' "$def_main"; fi
    [[ "$REPLY" == <1-> ]] && (( REPLY <= n )) || die "There is no display number '$REPLY'."
    main_i=$REPLY
  fi

  # Shared display: the one that may be switched to the laptops.
  def_shared=${prev_shared_i:#0}
  (( def_shared == main_i )) && def_shared=''
  if [[ -z "$def_shared" ]]; then for i in {1..$n}; do (( i != main_i )) && { def_shared=$i; break; }; done; fi
  if [[ -n "$OPT_SHARED" ]]; then REPLY="$OPT_SHARED"
  elif (( n == 1 )); then REPLY=1
  else ask 'Which display MAY be switched to the laptops (shared)?' "$def_shared"; fi
  [[ "$REPLY" == <1-> ]] && (( REPLY <= n )) || die "There is no display number '$REPLY'."
  shared_i=$REPLY
  (( shared_i != main_i )) || die 'The main display must never be switched – choose a different display as the shared one.'

  echo
  echo 'Summary:'
  for i in {1..$n}; do
    if   (( i == shared_i )); then role='SHARED – switched between this server and the laptops'
    elif (( i == main_i ));   then role='main – stays with this server, never switched'
    else                           role='never switched'; fi
    printf '  %d) %-16s %s\n' $i "$names[i]" "$role"
  done
  ask 'Is this correct? (y/n)' 'y'
  [[ "$REPLY" == [dDyY]* ]] && break
  (( YES )) && die 'Cancelled.'
  OPT_MAIN=''; OPT_SHARED=''; prev_main_i=0; prev_shared_i=0
done

SHARED_NAME="$names[shared_i]"; SHARED_UUID="$uuids[shared_i]"
MAIN_NAME=''; MAIN_UUID_NEW=''
(( main_i )) && { MAIN_NAME="$names[main_i]"; MAIN_UUID_NEW="$uuids[main_i]"; }
protected=()
for i in {1..$n}; do (( i != shared_i )) && protected+=("$uuids[i]"); done

# --- Inputs ------------------------------------------------------------------------------
# Current input of the shared monitor as it reports it (empty: unknown or not visible right now).
read_shared() {
  local v
  v="$("$M1DDC" display "$SHARED_UUID" get input 2>/dev/null | /usr/bin/tr -dc '0-9' || true)"
  [[ "$v" == <1-> ]] && print -r -- "$v"
  return 0
}

# Switch the shared monitor to the server with "$1" (input|input-alt) value "$2" and check that it
# then reports "$3". Sends at most twice (the first command may only wake the monitor).
try_switch() {
  local cmd=$1 val=$2 want=$3 t
  for t in 1 2; do
    "$M1DDC" display "$SHARED_UUID" set "$cmd" "$val" >/dev/null 2>&1 || true
    for n_try in {1..8}; do sleep 1; [[ "$(read_shared)" == "$want" ]] && return 0; done
  done
  return 1
}

CUR="$(read_shared)"
echo
echo "Shared display: $SHARED_NAME – current input: ${CUR:-? (the monitor does not report it)}$([[ -n "$CUR" ]] && print " ($(input_name $CUR))")"
echo "Common inputs: $INPUTS_HELP"

def_server="${CUR:-${SERVER_READ:-${SERVER_INPUT:-17}}}"
if [[ -n "$OPT_SERVER" ]]; then REPLY="$OPT_SERVER"
else ask 'Which input is this server on? (the monitor should be showing this server now)' "$def_server"; fi
[[ "$REPLY" == <1-> ]] || die "Invalid input '$REPLY'."
SERVER_IN=$REPLY

prev_client="${CLIENT_READ:-$CLIENT_INPUT}"
if [[ -n "$prev_client" && "$prev_client" != "$SERVER_IN" ]]; then def_client=$prev_client
elif (( SERVER_IN == 17 )); then def_client=18
else def_client=17; fi

MODE="${INPUT_CMD:-input}"; (( OPT_ALT )) && MODE=input-alt
TESTED=0
if [[ -n "$OPT_CLIENT" ]]; then
  REPLY="$OPT_CLIENT"
elif (( YES )) || [[ -z "$CUR" ]]; then
  ask 'Which input are the laptops on?' "$def_client"
else
  ask 'Laptops: press Enter to detect their input (recommended), or type its code' 'detect'
fi

if [[ "$REPLY" == detect ]]; then
  echo
  echo '  1) Connect a laptop to the shared monitor (laptop awake).'
  echo "  2) With the monitor's own buttons, switch it to the laptop's input."
  read -r "?  3) Press Enter here once the monitor shows the laptop … " || true
  echo -n '  Reading the input'
  REPLY=''
  for n_try in {1..30}; do
    v="$(read_shared)"
    if [[ -n "$v" && "$v" != "$SERVER_IN" ]]; then REPLY=$v; break; fi
    echo -n '.'; sleep 2
  done
  echo
  if [[ -z "$REPLY" ]]; then
    echo "  Could not read the laptop's input. Switch the monitor back to this server with its buttons."
    ask 'Which input are the laptops on?' "$def_client"
  else
    echo "  Laptop input: $REPLY ($(input_name $REPLY))"
    echo '  Switching the monitor back to this server over DDC (test) …'
    if try_switch input "$SERVER_IN" "$SERVER_IN"; then
      MODE=input; TESTED=1; echo '  ✓ Works (standard addressing).'
    elif [[ "$(to_alt $SERVER_IN)" != "$SERVER_IN" ]] && try_switch input-alt "$(to_alt $SERVER_IN)" "$SERVER_IN"; then
      MODE=input-alt; TESTED=1; echo '  ✓ Works with alternate addressing (input-alt, as on LG monitors).'
    else
      echo '  ✖ The monitor did not switch back. Check that DDC/CI is on in the monitor menu and that'
      echo "    this Mac is not on the built-in HDMI port of an M1 / entry M2 Mac. Switch back with the buttons."
      die 'DDC switching does not work with this monitor connection.'
    fi
  fi
fi
[[ "$REPLY" == <1-> ]] || die "Invalid input '$REPLY'."
(( REPLY != SERVER_IN )) || die 'The laptops must be on a different input than the server.'
CLIENT_IN=$REPLY

# Values to set (alternate addressing uses its own codes) and to expect when reading back.
if [[ "$MODE" == input-alt ]]; then
  SERVER_SET="$(to_alt $SERVER_IN)"; CLIENT_SET="$(to_alt $CLIENT_IN)"
else
  SERVER_SET=$SERVER_IN; CLIENT_SET=$CLIENT_IN
fi
if [[ -n "$CUR" ]]; then SERVER_RD=$SERVER_IN; CLIENT_RD=$CLIENT_IN
else SERVER_RD=''; CLIENT_RD=''; fi    # monitor can't report its input: no read-back

# --- Names and address -------------------------------------------------------------------
ask 'Name of this computer in the menu' "${SERVER_LABEL:-Server}";  S_LABEL="$REPLY"
ask 'Name for the laptops in the menu'  "${CLIENT_LABEL:-Laptop}";   C_LABEL="$REPLY"
# This Mac's own address, always detected on the machine setup runs on (so a new server
# computer writes its own address, never the previous one).
HOST="${OPT_HOST:-$USER@$(/usr/sbin/scutil --get LocalHostName).local}"
[[ -n "$SSH_HOST" && "$SSH_HOST" != "$HOST" ]] && echo "Server address: $HOST (was: $SSH_HOST)"

# --- Save --------------------------------------------------------------------------------
/bin/mkdir -p "$CONFIG_DIR"
cat > "$CONFIG" <<CONF
# Monitor Switcher settings, written by setup.command on $(/bin/date '+%F %T').
# To change them, run again: zsh setup.command
MONITOR_NAME=${(qq)SHARED_NAME}
MONITOR_UUID=${(qq)SHARED_UUID}
# Inputs: *_INPUT is the value that is set, *_READ the value the monitor reports (empty: none).
INPUT_CMD=$MODE
SERVER_INPUT=$SERVER_SET
CLIENT_INPUT=$CLIENT_SET
SERVER_READ=${(qq)SERVER_RD}
CLIENT_READ=${(qq)CLIENT_RD}
SERVER_INPUT_NAME=${(qq)$(input_name $SERVER_IN)}
CLIENT_INPUT_NAME=${(qq)$(input_name $CLIENT_IN)}
SERVER_LABEL=${(qq)S_LABEL}
CLIENT_LABEL=${(qq)C_LABEL}
SSH_HOST=${(qq)HOST}
# The main display and every display except the shared one: monitor-switch never touches them.
MAIN_NAME=${(qq)MAIN_NAME}
MAIN_UUID=${(qq)MAIN_UUID_NEW}
PROTECTED_UUIDS=${(qq)${(j: :)protected}}
CONF

echo
echo '──────── Settings ────────'
echo "  Shared display : $SHARED_NAME ($SHARED_UUID)"
[[ -n "$MAIN_NAME" ]] && echo "  Main display   : $MAIN_NAME – never switched"
echo "  Protected      : ${#protected} display(s), never switched"
echo "  $S_LABEL : $(input_name $SERVER_IN) ($SERVER_IN)"
echo "  $C_LABEL : $(input_name $CLIENT_IN) ($CLIENT_IN)"
echo "  Addressing     : $MODE$([[ "$MODE" == input-alt ]] && print " (set $SERVER_SET / $CLIENT_SET)")$( (( TESTED )) && print ', tested')$([[ -z "$SERVER_RD" ]] && print ', no read-back')"
echo "  SSH address    : $HOST"
echo "  Saved to       : $CONFIG"
echo

if ! /usr/bin/nc -z -G 2 localhost 22 2>/dev/null; then
  echo '⚠ Remote Login is off: turn it on in System Settings → General → Sharing,'
  echo '  otherwise the laptops cannot switch.'
  echo
fi

# --- Install the server side and build the laptop package ------------------------------
echo '▶ Installing on this Mac …'
./install.command
echo
echo '▶ Building the laptop package …'
./build-client.sh "$HOST"
ZIP="$(/bin/ls -t dist/MonitorSwitcher-client-*.zip | /usr/bin/head -1)"

# Publish it, so laptops can update from the menu: "Update from Server".
PKG_DIR="$HOME/.local/share/monitor-switch/client"
/bin/mkdir -p "$PKG_DIR"
/bin/cp "$ZIP" "$PKG_DIR/MonitorSwitcher-client.zip"
/bin/cp ./VERSION "$PKG_DIR/VERSION"
echo "Published for laptops: version $(/bin/cat ./VERSION)"

echo
echo '✅ Done.'
echo "   Laptop package: $PWD/$ZIP  (shown in Finder)"
echo '   Laptops that already have Monitor Switcher: menu → Update from Server (on this network).'
echo '   New laptop: AirDrop the zip, unzip it and run: zsh install.command'
if [[ -n "$PREV_NAME" && "$PREV_NAME" != "$SHARED_NAME" ]]; then
  echo "   (The monitor changed – $PREV_NAME → $SHARED_NAME – so the laptops need the new package.)"
fi
echo '   A new laptop prints its key when installed: add it via the menu bar icon → Laptop Keys …'
echo '   (Keys already added stay valid.)'
/usr/bin/open -R "$ZIP" 2>/dev/null || true
