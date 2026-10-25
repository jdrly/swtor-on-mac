#!/bin/bash
# Fixture test of the check whether macOS ended what the launcher left running because it is not
# allowed in the background (som.sh btm-check), and of what uses it: the wrapper's notification
# after the Wine session's start ended leftover Wine processes (hold-launcher --start-session
# exit 3), and Collect Logs' line. No Wine, no official install, no game and never macOS's own
# log: the log is planted text (with the real lines of a field report), the wrapper's
# hold-launcher a stand-in, and hold-launcher's exit 3 is checked with dummy programs.
#
#   scripts/test-btm.sh [path/to/SWTOR on Mac.app]
#
# Without an app it tests src/ and builds hold-launcher from src/helpers into the test folder.
# Env: KEEP=1 leaves the test folder for a look afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
T="$(mktemp -d /tmp/som-btm.XXXXXX)"
T="$(cd "$T" && pwd -P)"
if [ -n "${1:-}" ]; then
  RES="$(cd "$1/Contents/Resources" && pwd)"
  HL="$RES/helpers/hold-launcher"
else
  RES="$PWD/src"
  HL="$T/hold-launcher"
  clang -O2 -o "$HL" src/helpers/hold-launcher/hold_launcher.c
fi
SOMSH="$RES/som.sh"
cleanup() {
  pkill -KILL -f "$T/" 2>/dev/null || true
  rm -f "/tmp/.wine-$(id -u)/swtor-on-mac-$(printf '%x-%x' "$(stat -f %d "$T/hl/prefix" 2>/dev/null || echo 0)" "$(stat -f %i "$T/hl/prefix" 2>/dev/null || echo 0)").lock"
  [ -n "${KEEP:-}" ] || rm -rf "$T"
}
trap cleanup EXIT
unset SWTOR_ON_MAC_ROOT SWTOR_ON_MAC_BTM_LOG SWTOR_ON_MAC_DRY_RUN

pass=0 fail=0
ok() { echo "  ok   $*"; pass=$((pass + 1)); }
bad() { echo "  FAIL $*"; fail=$((fail + 1)); }
check() { local what=$1; shift; if "$@"; then ok "$what"; else bad "$what"; fi; }
# btm <fixture> [window]: som.sh btm-check on a fixture (in a sandbox: never macOS's log);
# its output in $T/out, its status in $rc
btm() { rc=0; SWTOR_ON_MAC_ROOT="$T" SWTOR_ON_MAC_BTM_LOG="$1" /bin/bash "$SOMSH" btm-check ${2:+"$2"} >"$T/out" 2>&1 || rc=$?; }
# wait_for <seconds> <command...>: until the command succeeds, at most that long
wait_for() { local n=$(($1 * 10)); shift; while [ "$n" -gt 0 ]; do "$@" 2>/dev/null && return 0; sleep 0.1; n=$((n - 1)); done; return 1; }

# A launcher run on a Mac where the launcher is not allowed in the background: loginwindow's
# lines when it quit (field report 2026-10-25, redacted)
cat >"$T/not-allowed.log" <<'LOG'
Timestamp               Ty Process[PID:TID]
2026-10-25 18:04:56.641 I  loginwindow[458:4a665] [com.apple.launchservices:quitsupport] applicationDeath: app=0x0-0x11b11b "Star Wars - The Old Republic Launcher", has non-application coalition pids [ 66234/mac_wine, 66351/wineserver, 66362/services.exe, 66365/winedevice.exe, 66367/winedevice.exe, 66373/plugplay.exe, 66379/svchost.exe, 66428/SetStoreUpdateService, 66431/rpcss.exe, 66436/SetStoreUpdateService ], so this application stays in the running list.
2026-10-25 18:04:56.657 I  loginwindow[458:4a665] [com.apple.launchservices:quitsupport] askBTM: app=0x0-0x11b11b "Star Wars - The Old Republic Launcher" BTM said this application is not allowed to run background processes.
2026-10-25 18:04:56.657 I  loginwindow[458:4a665] [com.apple.launchservices:quitsupport] applicationDeath: app=0x0-0x11b11b "Star Wars - The Old Republic Launcher" was foreground, and still has subordinate processes, and is not allowed by BTM so scheduling its subordinates' termination.
2026-10-25 18:04:57.723 I  loginwindow[458:4a665] [com.apple.launchservices:quitsupport] applicationDeath: app=0x0-0x11b11b "Star Wars - The Old Republic Launcher" was foreground, and still had subordinate processes, and is not allowed by BTM so terminating its subordinates.
LOG
# ...and where it is allowed: the game and the Wine session stay
cat >"$T/allowed.log" <<'LOG'
Timestamp               Ty Process[PID:TID]
2026-10-25 21:38:12.104 I  loginwindow[401:2c1f] [com.apple.launchservices:quitsupport] applicationDeath: app=0x0-0x9e09e "Star Wars - The Old Republic Launcher", has non-application coalition pids [ 51234/mac_wine, 51301/wineserver, 51310/services.exe ], so this application stays in the running list.
LOG
# two launcher runs ended, another app's end, the text in another process's line
{
  cat "$T/not-allowed.log"
  echo '2026-10-24 09:10:11.500 I  loginwindow[458:4a665] [com.apple.launchservices:quitsupport] applicationDeath: app=0x0-0x22c22c "Some Other App" was foreground, and still had subordinate processes, and is not allowed by BTM so terminating its subordinates.'
  echo '2026-10-25 19:30:01.002 I  loginwindow[458:4a665] [com.apple.launchservices:quitsupport] applicationDeath: app=0x0-0x12f12f "Star Wars - The Old Republic Launcher" was foreground, and still had subordinate processes, and is not allowed by BTM so terminating its subordinates.'
  echo '2026-10-25 19:31:00.000 I  Console[999:1] quoting: loginwindow[1:1] "Star Wars - The Old Republic Launcher" is not allowed by BTM'
} >"$T/two.log"
: >"$T/empty.log"

echo "== som.sh btm-check"
btm "$T/not-allowed.log" 1h
check "the field report's lines: found (status $rc), its time once ($(tr '\n' ' ' <"$T/out"))" eval '[ "$rc" = 0 ] && [ "$(cat "$T/out")" = "2026-10-25 18:04:57" ]'
btm "$T/allowed.log"
check "the launcher allowed: none (status $rc), nothing printed" eval '[ "$rc" = 1 ] && [ ! -s "$T/out" ]'
btm "$T/empty.log" 7d
check "an empty log: none (status $rc)" test "$rc" = 1
btm "$T/two.log" 24h
check "two launcher runs: both, oldest first; not another app's, not another process's line ($(tr '\n' ' ' <"$T/out"))" \
  test "$(tr '\n' ' ' <"$T/out")" = "2026-10-25 18:04:57 2026-10-25 19:30:01 "
btm "$T/missing.log"
check "an unreadable log: error (status $rc)" eval '[ "$rc" = 2 ] && grep -q "^@error " "$T/out"'
for w in 1x h 0h 24 1.5h -1h; do
  btm "$T/not-allowed.log" "$w"
  check "window '$w' refused (status $rc)" test "$rc" = 2
done
rc=0; SWTOR_ON_MAC_ROOT="$T" /bin/bash "$SOMSH" btm-check 1h >"$T/out" 2>&1 || rc=$?
check "a sandbox without a fixture: macOS's log not read, error (status $rc)" eval '[ "$rc" = 2 ] && grep -q "not read in a sandbox" "$T/out"'

echo "== the wrapper: the check only after the session's start ended leftover Wine processes"
W="$T/wrapper"
mkdir -p "$W/bin" "$W/bin-real" "$W/engine/bin" "$W/prefix" "$W/logs"
printf '#!/bin/bash\necho "$*" >>"%s/wine-args"\n' "$W" >"$W/engine/bin/wine"
printf '#!/bin/bash\nexit 0\n' >"$W/engine/bin/wineserver"
# hold-launcher's stand-in: the exit status in $W/hl-rc; setsid-exec's: logs what it starts
printf '#!/bin/bash\nexit "$(cat "%s/hl-rc")"\n' "$W" >"$W/bin-real/hold-launcher"
printf '#!/bin/bash\necho "$*" >>"%s/setsid-args"\n' "$W" >"$W/bin-real/setsid-exec"
chmod +x "$W/engine/bin/wine" "$W/engine/bin/wineserver" "$W/bin-real/hold-launcher" "$W/bin-real/setsid-exec"
cat >"$W/env" <<ENV
SWTOR_ENGINE="$W/engine"
SWTOR_PREFIX="$W/prefix"
SWTOR_LOG_DIR="$W/logs"
SWTOR_NOTIFY_LOG="$W/notifications.log"
SWTOR_ON_MAC_ROOT="$T"
SWTOR_SOM_SH="$SOMSH"
SWTOR_ON_MAC_BTM_LOG="$W/fixture"
ENV
sed "s|@CONF@|$W/env|" "$RES/wine-wrapper.sh" >"$W/bin/wine64-preloader"; chmod +x "$W/bin/wine64-preloader"
call() { "$W/bin/wine64-preloader" "$W/bin/wine64" reg query 'HKCU\Software\Broadsword' >/dev/null 2>&1; }
notes() { if [ -f "$W/notifications.log" ]; then wc -l <"$W/notifications.log" | tr -d ' '; else echo 0; fi; }
checks_running() { pgrep -f "$SOMSH btm-check" >/dev/null; }

# exit 3 and the launcher's end in the log. The fixture is a FIFO: the check waits on it until
# the test writes, so the Wine call must have returned without waiting for the check.
mkfifo "$W/fixture"; echo 3 >"$W/hl-rc"
t0=$SECONDS; call; dt=$((SECONDS - t0))
check "exit 3: the Wine call ran ($(tail -1 "$W/wine-args" 2>/dev/null))" eval 'tail -1 "$W/wine-args" | grep -qF "reg query HKCU\\Software\\Broadsword"'
check "exit 3: it did not wait for the check ($dt s; the check is still waiting)" eval '[ "$dt" -le 1 ] && checks_running && [ "$(notes)" = 0 ]'
# (the write waits for the check to open the FIFO: at most 5 s, so a wrapper without the check
# fails here instead of hanging)
cat "$T/not-allowed.log" >"$W/fixture" & writer=$!
check "exit 3: then a notification with the setting" wait_for 5 grep -q "Login Items & Extensions, turn on the launcher under Allow in the Background" "$W/notifications.log"
kill "$writer" 2>/dev/null || true
wait "$writer" 2>/dev/null || true
check "exit 3: hold.log says what happened" grep -q "macOS ended the last Wine session when the launcher quit" "$W/logs/hold.log"
check "exit 3: nothing of the check left running" wait_for 3 eval '! checks_running'
check "exit 3: no fallback wineserver" test ! -e "$W/setsid-args"
rm -f "$W/fixture"
cat "$T/allowed.log" >"$W/fixture"; n=$(notes); call; sleep 1.5
check "exit 3, the launcher allowed: no notification" eval '[ "$(notes)" = "$n" ] && ! checks_running'
cat "$T/not-allowed.log" >"$W/fixture"; echo 0 >"$W/hl-rc"; call; sleep 1.5
check "exit 0 (nothing ended): no check, no notification" eval '[ "$(notes)" = "$n" ] && ! checks_running'
echo 1 >"$W/hl-rc"; call; sleep 1.5
check "exit 1 (no wineserver): the wrapper starts one itself, no check" eval 'grep -q "engine/bin/wineserver -p10" "$W/setsid-args" && [ "$(notes)" = "$n" ]'
echo 3 >"$W/hl-rc"; sed -i '' "s|^SWTOR_SOM_SH=.*|SWTOR_SOM_SH=\"$T/gone/som.sh\"|" "$W/env"
# shellcheck disable=SC2034 # (used in check's eval strings)
calls=$(wc -l <"$W/wine-args"); call; sleep 1.5
check "exit 3, the app moved (no som.sh there): the Wine call ran, no notification" eval '[ "$(wc -l <"$W/wine-args")" -gt "$calls" ] && [ "$(notes)" = "$n" ]'
check "the wrapper: nothing left running" eval '! pgrep -f "$W/" >/dev/null'

echo "== hold-launcher --start-session: exit 3 when it ended leftover Wine processes (dummy programs)"
L="$T/hl"
mkdir -p "$L/engine/bin" "$L/engine/lib/wine/x86_64-unix" "$L/prefix/drive_c/windows" "$L/logs"
printf '#include <stdlib.h>\n#include <unistd.h>\nint main(int c, char **v) { sleep(c > 1 ? atoi(v[1]) : 30); return 0; }\n' >"$T/sleep.c"
clang -o "$L/engine/lib/wine/x86_64-unix/wine" "$T/sleep.c"   # the engine's loader: a dummy
printf '#!/bin/bash\nexit "$(cat "%s/ws-rc")"\n' "$L" >"$L/engine/bin/wineserver"
printf '#!/bin/bash\nexit 0\n' >"$L/engine/bin/wine"
chmod +x "$L/engine/bin/wineserver" "$L/engine/bin/wine"
alive() { local s; s=$(ps -o stat= -p "$1" 2>/dev/null | tr -d ' '); [ -n "$s" ] && [ "${s#Z}" = "$s" ]; }
# a leftover of the prefix's session: the engine's loader working in its C:\windows
leftover() { ( cd "$L/prefix/drive_c/windows" || exit 1; "$L/engine/lib/wine/x86_64-unix/wine" 60 </dev/null >/dev/null 2>&1 & echo $! >"$L/left.pid" ); cat "$L/left.pid"; }
start_session() { rc=0; SWTOR_ENGINE="$L/engine" WINEPREFIX="$L/prefix" "$HL" --start-session "$L/logs/ws.log" 2>>"$L/logs/hold.log" || rc=$?; }
echo 0 >"$L/ws-rc"
# shellcheck disable=SC2034 # (used in check's eval strings)
p=$(leftover); sleep 0.3
start_session
check "a leftover ended, the session started: exit 3 (status $rc)" eval '[ "$rc" = 3 ] && ! alive "$p" && grep -q "ended leftover Wine process $p " "$L/logs/hold.log"'
start_session
check "nothing to end: exit 0 (status $rc)" test "$rc" = 0
# shellcheck disable=SC2034 # (used in check's eval strings)
p2=$(leftover); sleep 0.3; echo 1 >"$L/ws-rc"
start_session
check "a leftover ended but no wineserver: exit 1, the wrapper starts one (status $rc)" eval '[ "$rc" = 1 ] && ! alive "$p2"'

echo "== Collect Logs: the last 7 days in system-info.txt"
C="$T/collect"
mkdir -p "$C/home/Desktop"
collect() { # <fixture or ""> [timeout]: system-info.txt's line in $T/line
  local zip
  rm -rf "$C/zip" && mkdir -p "$C/zip"
  zip=$(SWTOR_ON_MAC_ROOT="$C" SWTOR_ON_MAC_BTM_LOG="$1" SWTOR_ON_MAC_BTM_TIMEOUT="${2:-90}" /bin/bash "$RES/collect-logs.sh" "$C/zip" 2>/dev/null) || true
  unzip -p "$zip" '*/system-info.txt' 2>/dev/null | grep '^Launcher not allowed in the background' >"$T/line" || true
}
collect "$T/two.log"
check "the times found ($(cat "$T/line"))" grep -qx "Launcher not allowed in the background, macOS ended what it left running (the last 7 days): 2026-10-25 18:04:57, 2026-10-25 19:30:01" "$T/line"
collect "$T/allowed.log"
check "none ($(cat "$T/line"))" grep -q "(the last 7 days): none\$" "$T/line"
collect ""
check "not read in a sandbox ($(cat "$T/line"))" grep -q "(the last 7 days): not read\$" "$T/line"
mkfifo "$C/never"
t0=$SECONDS; collect "$C/never" 2; dt=$((SECONDS - t0))
check "a check that doesn't end: stopped after the limit ($dt s), said so ($(cat "$T/line"))" eval 'grep -q "not read (ran out of time)\$" "$T/line" && [ "$dt" -lt 30 ]'
check "Collect Logs: nothing of the check left running" eval '! pgrep -f "$SOMSH btm-check" >/dev/null && ! pgrep -f "$C/never" >/dev/null'

echo "== $pass passed, $fail failed"
[ "$fail" = 0 ]
