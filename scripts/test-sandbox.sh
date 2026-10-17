#!/bin/bash
# End-to-end test of the installer (Resources/som.sh of a built app) in a sandbox, without
# touching the real system: a fake official install made of APFS clones of this Mac's real one
# (the app and Broadsword's Wine folder, not the game data), put back to stock if a wrapper is
# installed, under $SANDBOX (SWTOR_ON_MAC_ROOT). Downloads the real engine and runs Wine
# (wineboot, reg) on the sandbox prefix only, then checks that no Wine process is left.
# Then the way from and back to 0.0.6 (sections 11-13, with OLD_APP): an install of 0.0.6
# upgraded by this one (and a failed upgrade rolled back), this one replaced by 0.0.6 again
# (Reinstall of the older app), and upgraded once more.
#
#   scripts/test-sandbox.sh [path/to/SWTOR on Mac.app]
#
# Needs the official SWTOR Mac app installed on this Mac (it is only read). Quit SWTOR first.
# Env: SANDBOX (default /tmp/som-sandbox), KEEP=1 (leave the sandbox for a look afterwards),
#      OLD_APP (default release/0.0.6/SWTOR on Mac.app; missing: sections 11-13 are skipped)
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$(cd "${1:-dist/SWTOR on Mac.app}" && pwd)"
SOMSH="$APP/Contents/Resources/som.sh"
[ -x "$SOMSH" ] || { echo "no $SOMSH; run ./build.sh" >&2; exit 1; }
HL_APP="$APP/Contents/Resources/helpers/hold-launcher"
OLD_APP="${OLD_APP:-release/0.0.6/SWTOR on Mac.app}"
[ ! -d "$OLD_APP" ] || OLD_APP="$(cd "$OLD_APP" && pwd)"
REPO="$PWD"
SANDBOX="${SANDBOX:-/tmp/som-sandbox}"
REAL_APP="/Applications/Star Wars - The Old Republic.app"
REAL_WINE="$HOME/Library/Application Support/com.broadsword.swtor/Star Wars - The Old Republic/swtor-precompiled/Libraries/Wine"
H="$SANDBOX/home"
BS_APP="$SANDBOX/Applications/Star Wars - The Old Republic.app"
BS_WINE="$H/Library/Application Support/com.broadsword.swtor/Star Wars - The Old Republic/swtor-precompiled/Libraries/Wine"
SOM="$H/Library/Application Support/SWTOR on Mac"
LOGS="$H/Library/Logs/SWTOR on Mac"
export SWTOR_ON_MAC_ROOT="$SANDBOX"
unset SWTOR_ON_MAC_DRY_RUN SWTOR_ON_MAC_FORCE

pass=0 fail=0
ok() { echo "  ok   $*"; pass=$((pass + 1)); }
bad() { echo "  FAIL $*"; fail=$((fail + 1)); }
check() { local what=$1; shift; if "$@"; then ok "$what"; else bad "$what"; fi; }
som() { "$SOMSH" "$@"; }
st() { som status | sed -n "s/^$1=//p"; }
# what the window's Play button would do (the app's own resolution; nothing is opened)
play_target() { "$APP/Contents/MacOS/SWTORonMac" --play-target 2>/dev/null; }
is_macho() { file -b "$1" | grep -q '^Mach-O'; }
# reg_has <key as in user.reg, with \\> <value line>: the value is set under that key
reg_has() {
  K="[$1]" V="$2" awk 'BEGIN { k = ENVIRON["K"]; v = ENVIRON["V"] }
    index($0, "[") == 1 { inkey = (substr($0, 1, length(k)) == k && substr($0, length(k) + 1, 1) == " ") }
    inkey && $0 == v { found = 1 }
    END { exit !found }' "$SOM/prefix/user.reg"
}
# Fingerprint of a tree: every path with type, mode, file size, symlink target, and file
# contents. The game settings in Broadsword's prefix are left out (Uninstall copies them back,
# with a backup next to them, on purpose; checked on their own).
snap() {
  ( cd "$1" && find . -path '*/AppData/Local/SWTOR/swtor/settings*' -prune -o -print0 | sort -z |
      xargs -0 stat -f '%N|%HT|%Sp|%z|%Y' | awk -F'|' -v OFS='|' '$2 == "Directory" { $4 = "" } { print }' &&
    find . -path '*/AppData/Local/SWTOR/swtor/settings*' -prune -o -type f -print0 | sort -z | xargs -0 shasum -a 256 )
}
AGENT_PLIST="$H/Library/LaunchAgents/cz.jandrly.swtoronmac.watch.plist"
# the watch job as launchd would start it (the sandbox never loads it into launchd)
watch() { SWTOR_ON_MAC_SETTLE="${SETTLE:-1}" /bin/bash "$SOM/agent/som.sh" watch; }
notes() { if [ -f "$LOGS/notifications.log" ]; then wc -l <"$LOGS/notifications.log" | tr -d ' '; else echo 0; fi; }
# the engine's loader: lib/wine/x86_64-unix/wine (CrossOver 26), or bin/wine-preloader (0.0.x)
loader_of() { if [ -f "$1/bin/wine-preloader" ]; then echo "$1/bin/wine-preloader"; else echo "$1/lib/wine/x86_64-unix/wine"; fi; }
# Wine processes of the sandbox (its engine, or anything with the sandbox in its path), "<pid>
# <program>": by real executable (Wine 11 shows C:\... names in ps) and by ps's name
sandbox_wine() {
  local tag=/nonexistent/ pre
  pre=$(loader_of "$SOM/engine")
  [ -f "$pre" ] && tag="/winetemp-$(stat -f '%i-%z' "$pre")-"
  { "$HL_APP" --paths 2>/dev/null; ps -axww -o pid=,comm= | sed 's/^ *//'; } |
    grep -F -e "$SANDBOX/" -e "$tag" | grep -v -e grep -e "$$ " | awk '!seen[$1]++' || true
}
# sbx_wine <args>: Wine of the sandbox's engine with its env file (0.0.x's needs its libraries)
sbx_wine() {
  ( set -a; [ ! -f "$SOM/env" ] || . "$SOM/env"; set +a; unset WINEDLLPATH
    export WINEPREFIX="$SOM/prefix" WINEDEBUG=-all DYLD_FALLBACK_LIBRARY_PATH="$SOM/frameworks:/usr/lib"
    exec "$SOM/engine/bin/wine" "$@" )
}
cleanup_wine() {
  local ws="$SOM/engine/bin/wineserver"
  [ -x "$ws" ] && WINEPREFIX="$SOM/prefix" DYLD_FALLBACK_LIBRARY_PATH="$SOM/frameworks:/usr/lib" "$ws" -k 2>/dev/null || true
  sleep 1
  sandbox_wine | awk '{ print $1 }' | xargs kill -9 2>/dev/null || true
}
trap cleanup_wine EXIT

echo "== sandbox $SANDBOX"
[ -d "$REAL_APP" ] && [ -d "$REAL_WINE" ] || { echo "official SWTOR install not found" >&2; exit 1; }
if [ -d "$SANDBOX" ]; then cleanup_wine; chmod -R u+w "$SANDBOX" 2>/dev/null || true; rm -rf "$SANDBOX"; fi
mkdir -p "$SANDBOX"
# the real path (/tmp is /private/tmp), as ps shows it
SANDBOX="$(cd "$SANDBOX" && pwd -P)"
H="$SANDBOX/home"
BS_APP="$SANDBOX/Applications/Star Wars - The Old Republic.app"
BS_WINE="$H/Library/Application Support/com.broadsword.swtor/Star Wars - The Old Republic/swtor-precompiled/Libraries/Wine"
SOM="$H/Library/Application Support/SWTOR on Mac"
LOGS="$H/Library/Logs/SWTOR on Mac"
AGENT_PLIST="$H/Library/LaunchAgents/cz.jandrly.swtoronmac.watch.plist"
export SWTOR_ON_MAC_ROOT="$SANDBOX"
mkdir -p "$SANDBOX/Applications" "$(dirname "$BS_WINE")" "$SANDBOX/usertmp"
cp -c -R -P "$REAL_APP" "$SANDBOX/Applications/"
cp -c -R -P "$REAL_WINE" "$(dirname "$BS_WINE")/"
# back to stock: Broadsword's real preloaders into bin, no bin-real
if [ -d "$BS_WINE/bin-real" ]; then
  for b in wine-preloader wine64-preloader; do
    [ -f "$BS_WINE/bin-real/$b" ] && is_macho "$BS_WINE/bin-real/$b" && mv -f "$BS_WINE/bin-real/$b" "$BS_WINE/bin/$b"
  done
  rm -rf "$BS_WINE/bin-real"
fi
# a copy of whatever wrapper the real install has (for the conflict test), from the real tree
# (SWTOR on Mac's own wrapper there does not count: then a made-up one stands in for it)
PERSONAL_WRAPPER="$SANDBOX/personal-wrapper"
mkdir -p "$PERSONAL_WRAPPER"
if ! is_macho "$REAL_WINE/bin/wine64-preloader" && ! grep -q SWTOR_ON_MAC_WRAPPER "$REAL_WINE/bin/wine64-preloader"; then
  cp -p "$REAL_WINE/bin/wine64-preloader" "$REAL_WINE/bin/wine-preloader" "$PERSONAL_WRAPPER/"
  cp -p "$REAL_WINE/bin-real/hold-launcher" "$REAL_WINE/bin-real/setsid-exec" "$PERSONAL_WRAPPER/" 2>/dev/null || true
else
  for b in wine64-preloader wine-preloader; do
    printf '#!/bin/bash\n# another Wine wrapper (test)\nexec "$(dirname "$0")/../bin-real/$(basename "$0")" "$@"\n' >"$PERSONAL_WRAPPER/$b"
    chmod 755 "$PERSONAL_WRAPPER/$b"
  done
fi
STOCK="$(snap "$BS_WINE")"
printf '%s\n' "$STOCK" >"$SANDBOX/snap-stock.txt"
# like_stock <name>: Broadsword's folder is as it was (else the difference is in <name>.diff)
like_stock() {
  local now; now="$(snap "$BS_WINE")"
  [ "$STOCK" = "$now" ] && return 0
  printf '%s\n' "$now" | diff "$SANDBOX/snap-stock.txt" - >"$SANDBOX/$1.diff"
  return 1
}
check "fake official install is stock" test "$(st wrapper)" = stock
check "status: official app found" test "$(st official_app)" = yes
check "status: not installed" test "$(st installed)" = no
check "play: unavailable before install ($(play_target))" test "$(play_target)" = "unavailable Install SWTOR on Mac first."

echo "== 1. dry run changes nothing"
SWTOR_ON_MAC_DRY_RUN=1 som install >"$SANDBOX/dry-run.txt" 2>&1 || { cat "$SANDBOX/dry-run.txt"; bad "dry run exit"; }
check "dry run: official install unchanged" test "$STOCK" = "$(snap "$BS_WINE")"
check "dry run: no app files" test ! -e "$SOM"
check "dry run: lists the wrapper change" grep -q 'write .*bin/wine64-preloader' "$SANDBOX/dry-run.txt"

echo "== 2. refuses while the launcher runs"
# a tiny program of our own (a copy of /bin/sleep, a platform binary, is not allowed to run)
printf '#include <unistd.h>\nint main(void) { sleep(30); return 0; }\n' >"$SANDBOX/sleep.c"
clang -o "$BS_APP/Contents/MacOS/test-sleep" "$SANDBOX/sleep.c"
"$BS_APP/Contents/MacOS/test-sleep" 30 &
sleeper=$!
sleep 0.5
if som install >"$SANDBOX/running.txt" 2>&1; then bad "install while running"; else
  check "running: refused with a message" grep -q '@error Quit the SWTOR launcher' "$SANDBOX/running.txt"
fi
kill "$sleeper" 2>/dev/null || true; wait "$sleeper" 2>/dev/null || true
rm -f "$BS_APP/Contents/MacOS/test-sleep"

echo "== 2b. leftover Wine processes of the engine (dummy programs; only those may end)"
# One dummy program for every part: as .../wineserver it is a Wine server (writes ws.pid next
# to itself; "wineserver -k" sends that one SIGTERM and returns at once, and it lingers
# $FAKE_LINGER s before it exits); anything else sleeps argv[1] seconds (default 60).
cat >"$SANDBOX/fake.c" <<'C'
#include <libgen.h>
#include <mach-o/dyld.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
static volatile sig_atomic_t term;
static void on_term(int s) { (void)s; term = 1; }
int main(int argc, char **argv)
{
    char dir[1024], pidf[1100];
    uint32_t size = sizeof(dir);
    if (_NSGetExecutablePath(dir, &size) != 0) return 2;  /* (argv[0] may be a bare name) */
    snprintf(pidf, sizeof(pidf), "%s/ws.pid", dirname(dir));
    const char *base = strrchr(argv[0], '/');
    base = base ? base + 1 : argv[0];
    if (!strcmp(base, "wineserver")) {
        if (argc > 1 && !strcmp(argv[1], "-k")) {
            FILE *f = fopen(pidf, "r");
            int pid = 0;
            if (f) { if (fscanf(f, "%d", &pid) != 1) pid = 0; fclose(f); }
            return pid > 1 && kill(pid, SIGTERM) == 0 ? 0 : 1;
        }
        FILE *f = fopen(pidf, "w");
        if (f) { fprintf(f, "%d\n", getpid()); fclose(f); }
        signal(SIGTERM, on_term);
        for (int i = 0; i < 60 && !term; i++) sleep(1);
        if (term && getenv("FAKE_LINGER")) sleep(atoi(getenv("FAKE_LINGER")));
        return 0;
    }
    sleep(argc > 1 ? atoi(argv[1]) : 60);
    return 0;
}
C
clang -o "$SANDBOX/fake" "$SANDBOX/fake.c"
# orphan <program> [args]: runs it detached (parent launchd, like Wine's orphans); prints its pid
orphan() { ( "$@" </dev/null >/dev/null 2>&1 & echo $! >"$SANDBOX/orphan.pid" ); cat "$SANDBOX/orphan.pid"; }
# alive <pid>: running (not gone, not a zombie)
alive() { local s; s=$(ps -o stat= -p "$1" 2>/dev/null | tr -d ' '); [ -n "$s" ] && [ "${s#Z}" = "$s" ]; }
all_alive() { local p; for p; do alive "$p" || return 1; done; }
all_gone() { local p; for p; do ! alive "$p" || return 1; done; }
# (the engine's layout: the loader lib/wine/x86_64-unix/wine, bin/wineserver)
EB="$SOM/engine/bin"
EL="$SOM/engine/lib/wine/x86_64-unix/wine"
mkdir -p "$EB" "${EL%/*}"
cp "$SANDBOX/fake" "$EL"
cp "$SANDBOX/fake" "$EB/wineserver"
# CrossOver's start names: hard links of the loader in winetemp-<inode>-<size>-...
WT="$SANDBOX/usertmp/winetemp-$(stat -f '%i-%z' "$EL")-1-2"
mkdir -p "$WT" && ln "$EL" "$WT/winedevice.exe"
# orphan_as <argv0> <program> [args]: like orphan, with argv[0] rewritten as Wine 11 does (ps
# then shows C:\windows\...)
orphan_as() { ( bash -c 'exec -a "$0" "$@"' "$@" </dev/null >/dev/null 2>&1 & echo $! >"$SANDBOX/orphan.pid" ); cat "$SANDBOX/orphan.pid"; }
# decoys: the same program elsewhere (another file, also in a winetemp-like folder)
mkdir -p "$SANDBOX/decoy/winetemp-1-2-3-4"
cp "$SANDBOX/fake" "$SANDBOX/decoy/wine-preloader"
cp "$SANDBOX/fake" "$SANDBOX/decoy/winetemp-1-2-3-4/winedevice.exe"
d1=$(orphan "$SANDBOX/decoy/wine-preloader")
d2=$(orphan_as 'C:\windows\system32\winedevice.exe' "$SANDBOX/decoy/winetemp-1-2-3-4/winedevice.exe")
l1=$(orphan_as 'C:\windows\system32\winedevice.exe' "$WT/winedevice.exe")
l2=$(orphan_as 'C:\windows\system32\services.exe' "$EL")
# one whose parent still runs and is not Wine (a winedevice.exe whose services.exe is alive)
( "$EL" & echo $! >"$SANDBOX/child.pid"; "$SANDBOX/decoy/wine-preloader" 60 ) </dev/null >/dev/null 2>&1 &
p3=$!
sleep 0.5
l3=$(cat "$SANDBOX/child.pid")
check "leftovers: status busy=leftovers" test "$(st busy)" = leftovers
check "leftovers: not counted as running" test "$(st running)" = no
check "leftovers: names ($(st busy_detail))" eval 'st busy_detail | grep -q winedevice.exe'
check "leftovers: settings running=no" test "$(som settings | sed -n 's/^running=//p')" = no
s1=$(orphan "$EB/wineserver"); sleep 0.3
check "session: status busy=session" test "$(st busy)" = session
check "session: running=yes" test "$(st running)" = yes
check "session: end-leftovers refuses" eval '! som end-leftovers >"$SANDBOX/end1.txt" 2>&1'
check "session: install refuses with a message" eval '! som install >"$SANDBOX/session.txt" 2>&1 && grep -q "^@error SWTOR on Mac.s Wine is still running" "$SANDBOX/session.txt"'
check "session: nothing ended" all_alive "$l1" "$l2" "$l3" "$s1"
kill "$s1"; sleep 0.5
som end-leftovers >"$SANDBOX/end2.txt" 2>&1 || bad "end-leftovers exit"
sleep 0.3
check "end-leftovers: @done" grep -q '^@done Ended the leftover' "$SANDBOX/end2.txt"
check "end-leftovers: the engine's processes ended (any parent)" all_gone "$l1" "$l2" "$l3"
check "end-leftovers: decoys left alone" all_alive "$d1" "$d2"
check "end-leftovers: the non-Wine parent left alone" alive "$p3"
check "end-leftovers: logged" grep -q 'Ended leftover Wine processes' "$LOGS/install.log"
check "end-leftovers: status busy=none" test "$(st busy)" = none
# the game and Broadsword's Wine are not leftovers, and keep leftovers from ending
cp "$SANDBOX/fake" "$SANDBOX/decoy/game"
g=$(orphan_as 'C:\Program Files\SWTOR\retailclient\swtor.exe' "$SANDBOX/decoy/game"); l4=$(orphan "$WT/winedevice.exe"); sleep 0.3
check "game: status busy=game" test "$(st busy)" = game
check "game: end-leftovers refuses" eval '! som end-leftovers >/dev/null 2>&1'
check "game: nothing ended" all_alive "$l4" "$g"
check "game: install refuses" eval '! som install >"$SANDBOX/game.txt" 2>&1 && grep -q "^@error Quit the game first" "$SANDBOX/game.txt"'
kill "$g"
cp "$SANDBOX/fake" "$BS_WINE/test-wine"
w=$(orphan "$BS_WINE/test-wine"); sleep 0.3
check "Broadsword's Wine: status busy=wine" test "$(st busy)" = wine
check "Broadsword's Wine: install refuses" eval '! som install >"$SANDBOX/wine.txt" 2>&1 && grep -q "Broadsword.s Wine is still running" "$SANDBOX/wine.txt"'
check "Broadsword's Wine: the leftover not ended" alive "$l4"
kill "$w"; sleep 0.3; rm -f "$BS_WINE/test-wine"
kill "$p3" "$d1" "$d2" 2>/dev/null || true; wait "$p3" 2>/dev/null || true
pkill -f "$SANDBOX/decoy/" 2>/dev/null || true
rm -f "$EB/wineserver" "$EB/ws.pid"
# l4 is still running: the next (failed) install ends it first

echo "== 3. failed install rolls back (bin not writable)"
chmod a-w "$BS_WINE/bin"
if som install >"$SANDBOX/fail.txt" 2>&1; then bad "install with read-only bin succeeded"; fi
chmod u+w "$BS_WINE/bin"
check "install: ended the leftover first, logged" grep -q "^Ended leftover Wine processes" "$SANDBOX/fail.txt"
check "install: the leftover is gone" all_gone "$l4"
rm -rf "$WT"
check "fail: official install unchanged" test "$STOCK" = "$(snap "$BS_WINE")"
check "fail: no engine/prefix left" test ! -e "$SOM/engine" -a ! -e "$SOM/prefix" -a ! -e "$SOM/install-manifest.json"
check "fail: no engine download left half-done" eval '! ls -d "$SOM"/*.new >/dev/null 2>&1'
check "fail: no Wine left running" test -z "$(sandbox_wine)"

echo "== 4. install"
t0=$SECONDS
som install >"$SANDBOX/install.txt" 2>&1 || { tail -20 "$SANDBOX/install.txt"; bad "install exit"; }
echo "  (install took $((SECONDS - t0)) s)"
check "install: @done" grep -q '^@done' "$SANDBOX/install.txt"
check "install: wrapper is ours" test "$(st wrapper)" = ours
check "install: installed=yes" test "$(st installed)" = yes
for b in wine-preloader wine64-preloader; do
  check "install: bin/$b is the wrapper" grep -q SWTOR_ON_MAC_WRAPPER "$BS_WINE/bin/$b"
  check "install: bin-real/$b is Mach-O" is_macho "$BS_WINE/bin-real/$b"
done
check "install: wrapper reads the sandbox env" grep -qF "CONF=\"$SOM/env\"" "$BS_WINE/bin/wine64-preloader"
check "install: helpers" test -x "$BS_WINE/bin-real/hold-launcher" -a -x "$BS_WINE/bin-real/setsid-exec"
check "install: bridge .so" cmp -s "$APP/Contents/Resources/d9mt/winemetal.so" "$SOM/engine/lib/wine/x86_64-unix/winemetal.so"
check "install: bridge .dll" cmp -s "$APP/Contents/Resources/d9mt/winemetal.dll" "$SOM/engine/lib/wine/x86_64-windows/winemetal.dll"
check "install: the dxgi/dxmt tree's winemetal.so is the bridge too" cmp -s "$APP/Contents/Resources/d9mt/winemetal.so" "$SOM/engine/lib/wine/dxgi/dxmt/x86_64-unix/winemetal.so"
check "install: engine $(sed -n 's/^ENGINE_NAME=//p' "$SOMSH") (Wine $(sbx_wine --version 2>/dev/null))" test "$(sbx_wine --version 2>/dev/null)" = wine-11.0
check "install: engine without its SDK (include, tests)" test ! -e "$SOM/engine/include" -a ! -e "$SOM/engine/lib/wine/tests"
check "install: no engine libraries folder (self-contained engine)" test ! -e "$SOM/frameworks"
check "install: manifest engine_id cx26" test "$(plutil -extract engine_id raw -o - "$SOM/install-manifest.json")" = cx26
sys="$SOM/prefix/drive_c/windows/system32"
check "install: d9mt d3d9.dll" cmp -s "$APP/Contents/Resources/d9mt/d3d9.dll" "$sys/d3d9.dll"
check "install: Wine's d3d9 kept ($(dd if="$sys/d3d9.dll.wine" bs=1 skip=64 count=20 2>/dev/null))" eval 'dd if="$sys/d3d9.dll.wine" bs=1 skip=64 count=20 2>/dev/null | grep -q -e "Wine builtin" -e "Wine placeholder"'
check "install: RetinaMode=y" reg_has 'Software\\Wine\\Mac Driver' '"RetinaMode"="y"'
WM="$SOM/engine/lib/wine/x86_64-unix"
WL="$SOM/engine/lib/wine"
WM_STOCK=$(sed -n 's/^ENGINE_WINEMAC_SHA256=//p' "$SOMSH")
WM_STOCK64=$(sed -n 's/^ENGINE_WINEMAC_PE64_SHA256=//p' "$SOMSH")
WM_STOCK32=$(sed -n 's/^ENGINE_WINEMAC_PE32_SHA256=//p' "$SOMSH")
wm_sha() { shasum -a 256 "$WM/winemac.so" | cut -d" " -f1; }
# the engine's Mac driver, all three files: the app's build (app) or the engine's own (stock)
wm_is() {
  local r="$APP/Contents/Resources/wine"
  if [ "$1" = app ]; then
    cmp -s "$r/winemac.so" "$WM/winemac.so" && cmp -s "$r/x86_64-windows/winemac.drv" "$WL/x86_64-windows/winemac.drv" &&
      cmp -s "$r/i386-windows/winemac.drv" "$WL/i386-windows/winemac.drv"
  else
    test "$(wm_sha)" = "$WM_STOCK" && test "$(shasum -a 256 "$WL/x86_64-windows/winemac.drv" | cut -d" " -f1)" = "$WM_STOCK64" &&
      test "$(shasum -a 256 "$WL/i386-windows/winemac.drv" | cut -d" " -f1)" = "$WM_STOCK32"
  fi
}
check "install: the app's Mac driver, all three files (raw mouse-look on by default)" wm_is app
check "install: the engine's own kept as .stock" eval 'test "$(shasum -a 256 "$WM/winemac.so.stock" | cut -d" " -f1)" = "$WM_STOCK" && test "$(shasum -a 256 "$WL/x86_64-windows/winemac.drv.stock" | cut -d" " -f1)" = "$WM_STOCK64" && test "$(shasum -a 256 "$WL/i386-windows/winemac.drv.stock" | cut -d" " -f1)" = "$WM_STOCK32"'
check "install: PhysicalKeyboard=n" reg_has 'Software\\Wine\\AppDefaults\\swtor.exe\\Mac Driver' '"PhysicalKeyboard"="n"'
check "install: RawMouseWhenCursorHidden=y" reg_has 'Software\\Wine\\AppDefaults\\swtor.exe\\Mac Driver' '"RawMouseWhenCursorHidden"="y"'
check "install: RawMouseGameControllerScale=1" reg_has 'Software\\Wine\\AppDefaults\\swtor.exe\\Mac Driver' '"RawMouseGameControllerScale"="1"'
check "install: ThreadCpuStats=y (THREADCPU lines from swtor.exe only)" reg_has 'Software\\Wine\\AppDefaults\\swtor.exe\\Mac Driver' '"ThreadCpuStats"="y"'
check "install: no raw mouse-look for other programs" eval '! reg_has "Software\\\\Wine\\\\Mac Driver" "\"RawMouseWhenCursorHidden\"=\"y\""'
check "install: manifest winemac app" test "$(plutil -extract winemac raw -o - "$SOM/install-manifest.json")" = app
check "install: GrabPointer=n" reg_has 'Software\\Wine\\AppDefaults\\swtor.exe\\X11 Driver' '"GrabPointer"="n"'
check "install: d3d9 override" reg_has 'Software\\Wine\\AppDefaults\\swtor.exe\\DllOverrides' '"d3d9"="native,builtin"'
check "install: gamemode exe = engine loader" cmp -s "$SOM/engine/lib/wine/x86_64-unix/wine" "$SOM/gamemode/SWTOR.app/Contents/MacOS/swtor.exe"
check "install: gamemode ntdll.so link (relative) to the engine's" eval 'cmp -s "$SOM/gamemode/SWTOR.app/Contents/MacOS/ntdll.so" "$SOM/engine/lib/wine/x86_64-unix/ntdll.so" && [ "$(readlink "$SOM/gamemode/SWTOR.app/Contents/MacOS/ntdll.so")" = ../../../../engine/lib/wine/x86_64-unix/ntdll.so ]'
check "install: gamemode plist" plutil -lint -s "$SOM/gamemode/SWTOR.app/Contents/Info.plist"
check "install: env" grep -q '^SWTOR_ENGINE=' "$SOM/env"
check "install: env engine id, no engine libraries" eval 'grep -qx SWTOR_ENGINE_ID=cx26 "$SOM/env" && ! grep -q "^SWTOR_FRAMEWORKS" "$SOM/env"'
check "install: env compatdb rule (DXGI on wined3d)" eval '(set -a; . "$SOM/env"; [ "$WINE_COMPATDB" = "$(printf "v=5\nname=swtor-on-mac;exe=*;dxgi=wined3d")" ])'
check "install: dxvk.conf" grep -q 'presentInterval = 1' "$SOM/dxvk.conf"
check "install: manifest is JSON" plutil -convert json -o /dev/null "$SOM/install-manifest.json"
check "install: manifest records the real preloader" test "$(plutil -extract original_preloaders_sha256.wine64-preloader raw -o - "$SOM/install-manifest.json")" = "$(shasum -a 256 "$BS_WINE/bin-real/wine64-preloader" | cut -d" " -f1)"
check "install: game settings user crossover" test -d "$SOM/prefix/drive_c/users/crossover"
check "install: download cache removed" test ! -e "$H/Library/Caches/SWTOR on Mac/downloads"
check "install: log" test -s "$LOGS/install.log"
check "install: no Wine left running" test -z "$(sandbox_wine)"
check "install: settings.conf" grep -qx 'memory=auto' "$SOM/settings.conf"
check "install: env memory profile" grep -qx 'D9MT_MEMORY_PROFILE=auto' "$SOM/env"
CHANNEL=$(sed -n 's/^channel=//p' "$APP/Contents/Resources/app.properties")
APPV=$(sed -n 's/^version=//p' "$APP/Contents/Resources/app.properties")
if [ "$CHANNEL" = dev ]; then
  check "install: env update check off (development build)" grep -qx 'SWTOR_UPDATE_CHECK=0' "$SOM/env"
  check "install: Debug Logging on (development build)" eval 'grep -qx debug=on "$SOM/settings.conf" && grep -qx D9MT_PROFILE=1 "$SOM/env"'
  check "install: development defaults recorded" grep -qx "debug-on=$APPV" "$SOM/dev-defaults"
  check "install: d9mt flags file in the prefix (Debug Logging)" test -f "$SOM/prefix/drive_c/d9mt/flags.txt"
  check "install: the game's Wine debug channels (Debug Logging)" grep -qx 'SWTOR_GAME_WINEDEBUG=-all,warn+rawmouse,warn+threadcpu' "$SOM/env"
else
  check "install: env update check" grep -qx 'SWTOR_UPDATE_CHECK=1' "$SOM/env"
  check "install: Debug Logging off" grep -qx 'debug=off' "$SOM/settings.conf"
fi
check "install: env feed" grep -q '^SWTOR_UPDATE_FEED="https://github.com/jdrly/swtor-on-mac/releases/latest/download/appcast.xml"$' "$SOM/env"
check "install: env notifications to a file (sandbox)" grep -q '^SWTOR_NOTIFY_LOG=' "$SOM/env"
check "install: env HUD off" grep -q '^#MTL_HUD_ENABLED=1' "$SOM/env"
check "install: env Game Mode on" grep -q '^SWTOR_GAMEMODE_APP=' "$SOM/env"
check "install: launchd job written" plutil -lint -s "$AGENT_PLIST"
check "install: launchd job watches Wine/bin" test "$(plutil -extract WatchPaths.0 raw -o - "$AGENT_PLIST")" = "$BS_WINE/bin"
check "install: launchd job not at load" test "$(plutil -extract RunAtLoad raw -o - "$AGENT_PLIST")" = false
check "install: launchd job throttled" test "$(plutil -extract ThrottleInterval raw -o - "$AGENT_PLIST")" = 30
check "install: launchd job runs the agent copy" test "$(plutil -extract ProgramArguments.1 raw -o - "$AGENT_PLIST")" = "$SOM/agent/som.sh"
check "install: agent copy" test -f "$SOM/agent/som.sh" -a -f "$SOM/agent/wine-wrapper.sh" -a -x "$SOM/agent/helpers/hold-launcher"
# (a real install's job may be loaded: it must not be the sandbox's)
check "install: launchd job not loaded (sandbox)" eval '! launchctl print "gui/$(id -u)/cz.jandrly.swtoronmac.watch" 2>/dev/null | grep -qF "$SOM/"'
check "install: status watch_agent" test "$(st watch_agent)" = yes
check "install: manifest settings user" test -n "$(plutil -extract settings_user raw -o - "$SOM/install-manifest.json")"
check "play: opens the sandbox's official app ($(play_target))" test "$(play_target)" = "launch $BS_APP"
# without it the button is off: never the real app in /Applications (Launch Services' lookup
# by bundle id is only for the real system)
mv "$BS_APP" "$SANDBOX/official-app-away"
check "play: sandbox app gone, not the real one ($(play_target))" eval 'play_target | grep -q "^unavailable The official SWTOR app was not found"'
mv "$SANDBOX/official-app-away" "$BS_APP"

echo "== 4b. settings"
check "settings: listed" test "$(som settings | sed -n 's/^vsync=//p')" = on
som set hud on >/dev/null && check "set hud: MTL_HUD_ENABLED=1" grep -qx 'MTL_HUD_ENABLED=1' "$SOM/env"
som set vsync off >/dev/null && check "set vsync off: presentInterval unset" eval '! grep -q "^d3d9.presentInterval" "$SOM/dxvk.conf"'
check "set vsync off: other options kept" grep -q '^d3d9.allowOutOfRangeVsDefs = True' "$SOM/dxvk.conf"
som set debug on >/dev/null && check "set debug: info + profile + memstats" eval 'grep -qx DXVK_LOG_LEVEL=info "$SOM/env" && grep -qx D9MT_PROFILE=1 "$SOM/env" && grep -qx D9MT_MEMSTATS=1 "$SOM/env"'
FLAGS="$SOM/prefix/drive_c/d9mt/flags.txt"
check "set debug: D9MT_DEBUG_FILE names the flags file" eval '(set -a; . "$SOM/env"; [ "$D9MT_DEBUG_FILE" = "C:\\d9mt\\flags.txt" ])'
check "set debug: flags file written, all flags off" eval 'grep -q "^# att_trace" "$FLAGS" && ! grep -q "^[a-z]" "$FLAGS"'
echo att_trace >>"$FLAGS"
som set debug on >/dev/null && check "set debug: flags file edits kept" grep -qx att_trace "$FLAGS"
som set memory high >/dev/null && check "set memory high" grep -qx 'D9MT_MEMORY_PROFILE=high' "$SOM/env"
som set gamemode off >/dev/null && check "set gamemode off" grep -q '^#SWTOR_GAMEMODE_APP=' "$SOM/env"
som set updates off >/dev/null && check "set updates off" grep -qx 'SWTOR_UPDATE_CHECK=0' "$SOM/env"
check "set: bad value refused" eval '! som set memory huge >/dev/null 2>&1'
check "set: bad key refused" eval '! som set foo on >/dev/null 2>&1'
cp "$SANDBOX/fake" "$SOM/engine/bin/test-leftover"; l5=$(orphan "$SOM/engine/bin/test-leftover"); sleep 0.3
som set retina off >/dev/null && check "set retina off: user.reg" reg_has 'Software\\Wine\\Mac Driver' '"RetinaMode"="n"'
out=$(sbx_wine reg query 'HKCU\Software\Wine\Mac Driver' /v RetinaMode 2>/dev/null | tr -d '\r' || true)
cleanup_wine
check "set retina: ended a leftover first" all_gone "$l5"
rm -f "$SOM/engine/bin/test-leftover"
check "set retina off: Wine reads n ($(echo "$out" | awk '/RetinaMode/ { print $NF }'))" test "$(echo "$out" | awk '/RetinaMode/ { print $NF }')" = n
check "set retina: no Wine left running" test -z "$(sandbox_wine)"
printf '#include <unistd.h>\nint main(void) { sleep(30); return 0; }\n' >"$SANDBOX/sleep2.c"
clang -o "$BS_APP/Contents/MacOS/test-sleep2" "$SANDBOX/sleep2.c"
"$BS_APP/Contents/MacOS/test-sleep2" & sleeper=$!; sleep 0.5
check "set retina: refused while the launcher runs" eval '! som set retina on >/dev/null 2>&1'
check "play: shows the launcher while it runs ($(play_target))" test "$(play_target)" = "show launcher"
check "set hud: allowed while the launcher runs" eval 'som set hud off >/dev/null'
kill "$sleeper" 2>/dev/null || true; wait "$sleeper" 2>/dev/null || true; rm -f "$BS_APP/Contents/MacOS/test-sleep2"
som set retina on >/dev/null && check "set retina on again" reg_has 'Software\\Wine\\Mac Driver' '"RetinaMode"="y"'
check "settings: physkeys off by default" test "$(som settings | sed -n 's/^physkeys=//p')" = off
check "settings: rawmouse on, mousespeed 1 by default" test "$(som settings | sed -n 's/^rawmouse=//p')/$(som settings | sed -n 's/^mousespeed=//p')" = on/1
som set rawmouse off >/dev/null && check "set rawmouse off (physkeys off): the engine's own Mac driver, all three files" wm_is stock
check "set rawmouse off: RawMouseWhenCursorHidden=n" reg_has 'Software\\Wine\\AppDefaults\\swtor.exe\\Mac Driver' '"RawMouseWhenCursorHidden"="n"'
check "set rawmouse off: manifest stock" test "$(plutil -extract winemac raw -o - "$SOM/install-manifest.json")" = stock
som set physkeys on >/dev/null && check "set physkeys on: the app's Mac driver" wm_is app
check "set physkeys on: PhysicalKeyboard=y" reg_has 'Software\\Wine\\AppDefaults\\swtor.exe\\Mac Driver' '"PhysicalKeyboard"="y"'
check "set physkeys on: manifest" test "$(plutil -extract winemac raw -o - "$SOM/install-manifest.json")" = app
som set rawmouse on >/dev/null && check "set rawmouse on: the app's Mac driver stays" wm_is app
check "set rawmouse on: RawMouseWhenCursorHidden=y" reg_has 'Software\\Wine\\AppDefaults\\swtor.exe\\Mac Driver' '"RawMouseWhenCursorHidden"="y"'
som set mousespeed 1.5 >/dev/null && check "set mousespeed 1.5" eval 'reg_has "Software\\\\Wine\\\\AppDefaults\\\\swtor.exe\\\\Mac Driver" "\"RawMouseGameControllerScale\"=\"1.5\"" && grep -qx mousespeed=1.5 "$SOM/settings.conf"'
check "set mousespeed: 4 refused" eval '! som set mousespeed 4 >/dev/null 2>&1'
check "set mousespeed: empty refused" eval '! som set mousespeed "" >/dev/null 2>&1'
out=$(sbx_wine reg query 'HKCU\Software\Wine\AppDefaults\swtor.exe\Mac Driver' /v RawMouseGameControllerScale 2>/dev/null | tr -d '\r' || true)
cleanup_wine
check "set mousespeed: Wine reads 1.5 ($(echo "$out" | awk '/RawMouseGameControllerScale/ { print $NF }'))" test "$(echo "$out" | awk '/RawMouseGameControllerScale/ { print $NF }')" = 1.5
som set mousespeed 1 >/dev/null
check "set physkeys on: manifest sha" test "$(plutil -extract winemac_sha256 raw -o - "$SOM/install-manifest.json")" = "$(wm_sha)"
check "set physkeys on: RetinaMode kept" reg_has 'Software\\Wine\\Mac Driver' '"RetinaMode"="y"'
out=$(sbx_wine reg query 'HKCU\Software\Wine\AppDefaults\swtor.exe\Mac Driver' /v PhysicalKeyboard 2>/dev/null | tr -d '\r' || true)
cleanup_wine
check "set physkeys on: Wine reads y ($(echo "$out" | awk '/PhysicalKeyboard/ { print $NF }'))" test "$(echo "$out" | awk '/PhysicalKeyboard/ { print $NF }')" = y
clang -o "$BS_APP/Contents/MacOS/test-sleep2" "$SANDBOX/sleep2.c" && { "$BS_APP/Contents/MacOS/test-sleep2" & sleeper=$!; sleep 0.5; }
check "set physkeys: refused while the launcher runs" eval '! som set physkeys off >/dev/null 2>&1'
check "set rawmouse: refused while the launcher runs" eval '! som set rawmouse off >/dev/null 2>&1'
check "set mousespeed: refused while the launcher runs" eval '! som set mousespeed 2 >/dev/null 2>&1'
check "set physkeys, rawmouse: driver unchanged while refused" wm_is app
kill "$sleeper" 2>/dev/null || true; wait "$sleeper" 2>/dev/null || true; rm -f "$BS_APP/Contents/MacOS/test-sleep2"

echo "== 4c. game keys by keyboard position: what the game sees (a probe program as swtor.exe)"
if command -v x86_64-w64-mingw32-gcc >/dev/null; then
  mkdir -p "$SANDBOX/probe"
  x86_64-w64-mingw32-gcc -O2 -o "$SANDBOX/probe/swtor.exe" scripts/kbprobe.c
  # probe <input source ID>: the driver reads that keyboard layout (WINEMAC_TEST_KEYBOARD_LAYOUT,
  # the patch's test hook), not the Mac's current one; the input source is never changed
  probe() {
    WINEMAC_TEST_KEYBOARD_LAYOUT="$1" sbx_wine "$SANDBOX/probe/swtor.exe" 2>/dev/null | tr -d '\r'
  }
  line() { sed -n "s/^$1: //p" <<<"$2"; }
  cz=$(probe com.apple.keylayout.Czech); de=$(probe com.apple.keylayout.German); us=$(probe com.apple.keylayout.US)
  cur=$(probe "")   # the Mac's current keyboard layout
  echo "  Czech, on:  names $(line numrow-name "$cz") | typed $(line numrow-plain "$cz") | Shift $(line numrow-shift "$cz")"
  check "keys on, Czech: number row named 1-0" test "$(line numrow-name "$cz")" = "1 2 3 4 5 6 7 8 9 0"
  check "keys on, Czech: number row is VK_1-VK_0" test "$(line numrow-vk "$cz")" = "1 2 3 4 5 6 7 8 9 0"
  check "keys on, Czech: types + ě š č ř ž ý á í é" test "$(line numrow-plain "$cz")" = "+ ě š č ř ž ý á í é"
  check "keys on, Czech: Shift types 1-0" test "$(line numrow-shift "$cz")" = "1 2 3 4 5 6 7 8 9 0"
  check "keys on, Czech: dead key ´ + e = é" grep -q "^0x0d .*(dead)+e=é" <<<"$cz"
  check "keys on, German: key at US Y is VK_Y named Y, types z" test "$(line key-0x15 "$de")" = "vk Y name Y plain z"
  check "keys on, US: number row" test "$(line numrow-name "$us")/$(line numrow-plain "$us")" = "1 2 3 4 5 6 7 8 9 0/1 2 3 4 5 6 7 8 9 0"
  check "keys on, current layout: number row named 1-0" test "$(line numrow-name "$cur")" = "1 2 3 4 5 6 7 8 9 0"
  # the probes' Wine session ends by itself a few seconds later (wineserver's linger), as after
  # a game; until then the setting refuses (Wine keeps the registry in its wineserver)
  WINEPREFIX="$SOM/prefix" "$SOM/engine/bin/wineserver" -w 2>/dev/null || true
  som set physkeys off >/dev/null && check "set physkeys off (rawmouse on): the app's Mac driver stays" wm_is app
  check "keys off, the app's driver: number row named by what the layout types" eval 'cur_app=$(probe ""); [ "$(line numrow-name "$cur_app")" = "$(line numrow-plain "$cur_app")" ]'
  WINEPREFIX="$SOM/prefix" "$SOM/engine/bin/wineserver" -w 2>/dev/null || true
  som set rawmouse off >/dev/null && check "set rawmouse off too: the engine's own Mac driver" wm_is stock
  check "set physkeys off: PhysicalKeyboard=n" reg_has 'Software\\Wine\\AppDefaults\\swtor.exe\\Mac Driver' '"PhysicalKeyboard"="n"'
  # the engine's own driver has no test hook: the Mac's current layout only
  cur_off=$(probe "")
  echo "  current layout, off: names $(line numrow-name "$cur_off") | typed $(line numrow-plain "$cur_off") | Shift $(line numrow-shift "$cur_off")"
  echo "  current layout, on:  names $(line numrow-name "$cur") | typed $(line numrow-plain "$cur") | Shift $(line numrow-shift "$cur")"
  check "keys off: number row named by what the layout types (Wine's own)" test "$(line numrow-name "$cur_off")" = "$(line numrow-plain "$cur_off")"
  check "keys off and on: the same text" test "$(line numrow-plain "$cur_off")/$(line numrow-shift "$cur_off")" = "$(line numrow-plain "$cur")/$(line numrow-shift "$cur")"
  # The PE side of the app's driver with the engine's own unix side (what an installer that
  # swaps only winemac.so, 0.1.0-dev.1's, leaves after a downgrade): the input thread is not
  # started (it would call a unix function the old side lacks), and the driver works
  WINEPREFIX="$SOM/prefix" "$SOM/engine/bin/wineserver" -w 2>/dev/null || true
  cp "$APP/Contents/Resources/wine/x86_64-windows/winemac.drv" "$WL/x86_64-windows/winemac.drv"
  mixed=$(probe "")
  check "the app's PE side, the engine's unix side: the driver works" test "$(line numrow-plain "$mixed")" = "$(line numrow-plain "$cur_off")"
  cp "$WL/x86_64-windows/winemac.drv.stock" "$WL/x86_64-windows/winemac.drv"
  cleanup_wine
  check "keyboard probe: no Wine left running" test -z "$(sandbox_wine)"
  som set rawmouse on >/dev/null
  som set physkeys on >/dev/null
else
  echo "  (skipped: no x86_64-w64-mingw32-gcc for the probe program)"
fi

echo "== 5. the wrapper hands Wine calls to the app's engine"
out=$("$BS_WINE/bin/wine64-preloader" "$BS_WINE/bin/wine64" --version 2>&1 || true)
check "wrapper: engine wine answers ($out)" test "$out" = wine-11.0
cleanup_wine
check "wrapper: no Wine left running" test -z "$(sandbox_wine)"

echo "== 6. reinstall is idempotent"
ino=$(stat -f %i "$SOM/engine/lib/wine/x86_64-unix/wine")
som install >"$SANDBOX/reinstall.txt" 2>&1 || { tail -20 "$SANDBOX/reinstall.txt"; bad "reinstall exit"; }
check "reinstall: engine kept" test "$ino" = "$(stat -f %i "$SOM/engine/lib/wine/x86_64-unix/wine")"
check "reinstall: prefix kept" grep -q 'Updating the existing Wine prefix' "$SANDBOX/reinstall.txt"
check "reinstall: wrapper ours" test "$(st wrapper)" = ours
check "reinstall: no Wine left running" test -z "$(sandbox_wine)"
check "reinstall: settings kept" eval 'grep -qx memory=high "$SOM/settings.conf" && grep -qx D9MT_MEMORY_PROFILE=high "$SOM/env" && grep -qx DXVK_LOG_LEVEL=info "$SOM/env"'
check "reinstall: vsync stays off" eval '! grep -q "^d3d9.presentInterval" "$SOM/dxvk.conf"'
check "reinstall: Retina stays on" reg_has 'Software\\Wine\\Mac Driver' '"RetinaMode"="y"'
check "reinstall: the app's Mac driver stays" wm_is app
check "reinstall: PhysicalKeyboard stays y" reg_has 'Software\\Wine\\AppDefaults\\swtor.exe\\Mac Driver' '"PhysicalKeyboard"="y"'
check "reinstall: RawMouseWhenCursorHidden stays y" reg_has 'Software\\Wine\\AppDefaults\\swtor.exe\\Mac Driver' '"RawMouseWhenCursorHidden"="y"'
check "reinstall: manifest winemac app" test "$(plutil -extract winemac raw -o - "$SOM/install-manifest.json")" = app
som set physkeys off >/dev/null && check "set physkeys off again: the app's driver (raw mouse-look on)" wm_is app
som set vsync on >/dev/null; som set debug off >/dev/null; som set memory auto >/dev/null
som set gamemode on >/dev/null; som set updates on >/dev/null
check "settings: back to the defaults" test "$(som settings | sed -n 's/^debug=//p')" = off

echo "== 6b. the wrapper's daily update check (stub engine; the game is never started)"
U="$SANDBOX/update-check"
mkdir -p "$U/bin" "$U/bin-real" "$U/engine/bin" "$U/app"
cp "$BS_WINE/bin-real/setsid-exec" "$BS_WINE/bin-real/hold-launcher" "$U/bin-real/"
printf '#!/bin/bash\necho "$@" >>"%s/wine-args"\n' "$U" >"$U/engine/bin/wine"
printf '#!/bin/bash\nexit 0\n' >"$U/engine/bin/wineserver"
chmod +x "$U/engine/bin/wine" "$U/engine/bin/wineserver"
feed() { # <version>: an appcast like generate_appcast's
  printf '<?xml version="1.0" standalone="yes"?>\n<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">\n<channel><item>\n<sparkle:version>%s</sparkle:version>\n<sparkle:shortVersionString>%s</sparkle:shortVersionString>\n</item></channel></rss>\n' "$1" "$1" >"$U/appcast.xml"
}
cat >"$U/env" <<ENV
SWTOR_ENGINE="$U/engine"
SWTOR_PREFIX="$U/prefix"
SWTOR_LOG_DIR="$U/logs"
SWTOR_ON_MAC_VERSION=0.0.1
SWTOR_APP_DIR="$U/app"
SWTOR_UPDATE_FEED="file://$U/appcast.xml"
SWTOR_UPDATE_CHECK=1
SWTOR_NOTIFY_LOG="$U/notifications.log"
ENV
sed "s|@CONF@|$U/env|" "$APP/Contents/Resources/wine-wrapper.sh" >"$U/bin/wine64-preloader"; chmod +x "$U/bin/wine64-preloader"
game() { "$U/bin/wine64-preloader" "$U/bin/wine64" 'C:\swtor\retailclient\swtor.exe' -set username TESTACCOUNT >/dev/null 2>&1; sleep 1.5; }
mkdir -p "$U/engine/lib/wine/x86_64-unix"
cp "$SANDBOX/fake" "$U/engine/lib/wine/x86_64-unix/wine"
UWT="$SANDBOX/usertmp/winetemp-$(stat -f '%i-%z' "$U/engine/lib/wine/x86_64-unix/wine")-7-8"
mkdir -p "$UWT" && ln "$U/engine/lib/wine/x86_64-unix/wine" "$UWT/winedevice.exe"
l6=$(orphan "$UWT/winedevice.exe"); d6=$(orphan "$SANDBOX/fake" 60); sleep 0.3
feed 0.0.2; game
check "wrapper: ended a leftover of the engine before starting Wine" all_gone "$l6"
check "wrapper: logged it" grep -q "ended leftover Wine process $l6 (winedevice.exe" "$U/logs/hold.log"
check "wrapper: left the same program elsewhere alone" alive "$d6"
kill "$d6" 2>/dev/null || true
check "update check: notification for 0.0.2" grep -q 'update available (0.0.2)' "$U/notifications.log"
check "update check: update-available for the app" test "$(cat "$U/app/update-available" 2>/dev/null)" = 0.0.2
check "update check: the game started anyway" grep -q swtor.exe "$U/wine-args"
n=$(wc -l <"$U/notifications.log"); feed 0.0.3; game
check "update check: at most once a day" test "$(wc -l <"$U/notifications.log")" = "$n"
touch -t 202001010000 "$U/app/last-update-check"; rm -f "$U/app/update-available"; feed 0.0.1; game
check "update check: same version, no notification" test "$(wc -l <"$U/notifications.log")" = "$n"
# a development build: the release before it is older, its own release newer
sed -i '' 's|^SWTOR_ON_MAC_VERSION=.*|SWTOR_ON_MAC_VERSION=0.0.6-dev.1|' "$U/env"
touch -t 202001010000 "$U/app/last-update-check"; feed 0.0.5; game
check "update check: 0.0.5 is not newer than 0.0.6-dev.1" test "$(wc -l <"$U/notifications.log")" = "$n" -a ! -e "$U/app/update-available"
touch -t 202001010000 "$U/app/last-update-check"; feed 0.0.6; game
check "update check: 0.0.6 is newer than 0.0.6-dev.1" test "$(cat "$U/app/update-available" 2>/dev/null)" = 0.0.6
sed -i '' 's|^SWTOR_ON_MAC_VERSION=.*|SWTOR_ON_MAC_VERSION=0.1.0-dev.1|' "$U/env"
rm -f "$U/app/update-available"; n=$(wc -l <"$U/notifications.log")
touch -t 202001010000 "$U/app/last-update-check"; feed 0.0.6; game
check "update check: 0.0.6 is not newer than 0.1.0-dev.1" test "$(wc -l <"$U/notifications.log")" = "$n" -a ! -e "$U/app/update-available"
touch -t 202001010000 "$U/app/last-update-check"; feed 0.1.0; game
check "update check: 0.1.0 is newer than 0.1.0-dev.1" test "$(cat "$U/app/update-available" 2>/dev/null)" = 0.1.0
sed -i '' 's|^SWTOR_ON_MAC_VERSION=.*|SWTOR_ON_MAC_VERSION=0.0.1|' "$U/env"
n=$(wc -l <"$U/notifications.log"); rm -f "$U/app/update-available"
touch -t 202001010000 "$U/app/last-update-check"; sed -i '' 's|^SWTOR_UPDATE_FEED=.*|SWTOR_UPDATE_FEED="http://127.0.0.1:9/appcast.xml"|' "$U/env"
t0=$SECONDS; game
check "update check: offline is silent" test "$(wc -l <"$U/notifications.log")" = "$n" -a ! -e "$U/app/update-available"
check "update check: the game does not wait ($((SECONDS - t0)) s incl. 1.5 s pause)" test $((SECONDS - t0)) -le 3
check "update check: no account in the logs" eval '! grep -rq TESTACCOUNT "$U/logs"'
check "wrapper: no start line for the game" eval '! grep -q "wine start: swtor.exe" "$U/logs/hold.log"'
"$U/bin/wine64-preloader" "$U/bin/wine64" 'C:\windows\system32\reg.exe' add 'HKCU\Software\Broadsword' /v Token /d SECRETTOKEN >/dev/null 2>&1
check "wrapper: one line per other Wine start, the command's first word" eval 'test "$(grep -c "wine start: reg.exe (parent $$ " "$U/logs/hold.log")" = 1'
check "wrapper: nothing else of the command logged" eval '! grep -rq SECRETTOKEN "$U/logs"'

echo "== 6d. hold-launcher ends what is left of the engine's Wine once the launcher quits (dummies)"
T="$SANDBOX/hold-test"
TE="$T/engine/bin"
TL="$T/engine/lib/wine/x86_64-unix/wine"   # the engine's loader
FL="$T/Fake.app/Contents/MacOS/Star Wars - The Old Republic Launcher"
HL="$APP/Contents/Resources/helpers/hold-launcher"
mkdir -p "$TE" "${TL%/*}" "${FL%/*}" "$T/logs"
cp "$SANDBOX/fake" "$TL"
cp "$SANDBOX/fake" "$TE/wineserver"
TWT="$SANDBOX/usertmp/winetemp-$(stat -f '%i-%z' "$TL")-5-6"
mkdir -p "$TWT" && ln "$TL" "$TWT/winedevice.exe" && ln "$TL" "$TWT/services.exe"
mkdir -p "$SANDBOX/decoy/winetemp-1-2-3-4"
cp "$SANDBOX/fake" "$SANDBOX/decoy/winetemp-1-2-3-4/winedevice.exe"
d7=$(orphan "$SANDBOX/decoy/winetemp-1-2-3-4/winedevice.exe")
# --reap (what the wrapper runs): nothing while a wineserver of the engine runs
srv=$(orphan "$TE/wineserver"); r1=$(orphan "$TWT/winedevice.exe"); r2=$(orphan_as 'C:\windows\system32\services.exe' "$TL"); sleep 0.3
SWTOR_ENGINE="$T/engine" "$HL" --reap 2>>"$T/logs/reap.log"
check "hold --reap: leaves a running session alone" all_alive "$r1" "$r2" "$srv"
kill "$srv"; sleep 0.3
SWTOR_ENGINE="$T/engine" "$HL" --reap 2>>"$T/logs/reap.log"; sleep 0.3
check "hold --reap: ended the leftovers" all_gone "$r1" "$r2"
check "hold --reap: logged each" test "$(grep -c 'ended leftover Wine process' "$T/logs/reap.log")" = 2
check "hold --reap: decoy left alone" alive "$d7"
# A whole game: a fake launcher (its executable named like the real one) starts the "game"
# (a script that runs hold-launcher, then becomes the engine's program for 3 s) and, once
# resumed, the "last Wine call" that leaves a session behind: a new wineserver, an orphaned
# winedevice.exe, a services.exe whose parent is still alive. The servers linger 3 s after
# "wineserver -k" (the old hold-launcher gave up on that: it saw the server and left all).
printf '#include <stdlib.h>\n#include <sys/wait.h>\n#include <unistd.h>\nint main(int argc, char **argv) { if (argc < 2) return 2; pid_t p = fork(); if (p == 0) { execv(argv[1], argv + 1); _exit(127); } int st; waitpid(p, &st, 0); if (getenv("FAKE_AFTER")) system(getenv("FAKE_AFTER")); return 0; }\n' >"$T/launcher.c"
clang -o "$FL" "$T/launcher.c"
printf '#!/bin/bash\n"%s" $$ </dev/null >/dev/null 2>>"%s"\nexec "%s" 3\n' "$HL" "$T/logs/hold.log" "$TL" >"$T/game.sh"
cat >"$T/after.sh" <<AFTER
#!/bin/bash
( "$TE/wineserver" </dev/null >/dev/null 2>&1 & )
( "$TWT/winedevice.exe" </dev/null >/dev/null 2>&1 & echo \$! >"$T/orphan.pid" )
( "$TWT/services.exe" & echo \$! >"$T/svc.pid"; "$SANDBOX/decoy/winetemp-1-2-3-4/winedevice.exe" 60 ) </dev/null >/dev/null 2>&1 &
echo \$! >"$T/svc-parent.pid"
sleep 0.3
AFTER
chmod +x "$T/game.sh" "$T/after.sh"
s1=$(FAKE_LINGER=3 orphan "$TE/wineserver")
t0=$SECONDS
FAKE_LINGER=3 FAKE_AFTER="$T/after.sh" SWTOR_ENGINE="$T/engine" WINEPREFIX="$T/prefix" "$FL" "$T/game.sh" </dev/null >/dev/null 2>&1 &
fl=$!
for _ in $(seq 40); do
  grep -q -e 'ended leftover' -e 'no leftover' -e 'leaving the engine' "$T/logs/hold.log" 2>/dev/null && break
  sleep 1
done
sleep 0.5
echo "  (hold-launcher done after $((SECONDS - t0)) s)"
sed 's/^/    hold.log: /' "$T/logs/hold.log"
check "hold: held the launcher, then resumed it" eval 'grep -q "stopped, waiting for game" "$T/logs/hold.log" && grep -q "resumed (game exited)" "$T/logs/hold.log"'
check "hold: the launcher quit" all_gone "$fl"
check "hold: both sessions' wineservers gone" eval 'all_gone "$s1" && test -z "$(ps -axww -o comm= | grep -Fx "$TE/wineserver")"'
o=$(cat "$T/orphan.pid"); sv=$(cat "$T/svc.pid"); sp=$(cat "$T/svc-parent.pid")
check "hold: ended the orphaned winedevice.exe" all_gone "$o"
check "hold: logged it (parent 1)" grep -q "ended leftover Wine process $o (winedevice.exe, parent 1)" "$T/logs/hold.log"
check "hold: ended services.exe although its parent runs" all_gone "$sv"
check "hold: logged it" grep -q "ended leftover Wine process $sv (services.exe" "$T/logs/hold.log"
check "hold: left the non-Wine parent alone" alive "$sp"
check "hold: left the decoy alone" alive "$d7"
check "hold: nothing of the engine left" test -z "$(ps -axww -o comm= | grep -F -e "$T/" -e "${TWT##*/}/")"
kill "$sp" "$d7" 2>/dev/null || true
pkill -f "$SANDBOX/decoy/" 2>/dev/null || true
wait "$fl" 2>/dev/null || true

echo "== 6e. hold-launcher after the launcher quit: Broadsword's mac_wine and a Wine call that comes back (dummies)"
# The launcher's last Wine calls come from Broadsword's mac_wine, which outlives it: a dummy
# mac_wine (its executable named like the real one) makes a Wine call (a child process) that
# starts a session 2 s after the launcher quit, then exits a second later; another one stays,
# idle, with its finished call unreaped (as seen with the real one); 7.5 s after the launcher
# quit another Wine call brings a wineserver back. hold-launcher must wait for the busy
# mac_wine only (and never touch either), end the session, end it again when it comes back,
# and end the leftovers once it stays gone.
MW="$T/Fake.app/Contents/MacOS/mac_wine"
printf '#include <stdlib.h>\n#include <stdio.h>\n#include <sys/wait.h>\n#include <unistd.h>\nint main(void) {\n  if (getenv("MW_IDLE")) { if (fork() == 0) _exit(0); sleep(60); return 0; }\n  pid_t c = fork(); if (c == 0) { sleep(2); _exit(system(getenv("MW_CMD")) ? 1 : 0); }\n  int st; waitpid(c, &st, 0); sleep(1);\n  FILE *f = fopen(getenv("MW_DONE"), "w"); if (f) fclose(f); return 0; }\n' >"$T/macwine.c"
clang -o "$MW" "$T/macwine.c"
cat >"$T/after2.sh" <<AFTER
#!/bin/bash
( MW_IDLE=1 "$MW" </dev/null >/dev/null 2>&1 & echo \$! >"$T/mac_wine_idle.pid" )
( MW_CMD='( FAKE_LINGER=3 "$TE/wineserver" </dev/null >/dev/null 2>&1 & ); ( "$TWT/winedevice.exe" </dev/null >/dev/null 2>&1 & echo \$! >"$T/orphan2.pid" )' \
  MW_DONE="$T/mac_wine.done" "$MW" </dev/null >/dev/null 2>&1 & echo \$! >"$T/mac_wine.pid" )
( sleep 7.5; FAKE_LINGER=3 "$TE/wineserver" </dev/null >/dev/null 2>&1 & ) </dev/null >/dev/null 2>&1 &
AFTER
chmod +x "$T/after2.sh"
rm -f "$T/mac_wine.done" "$T/orphan2.pid" "$TE/ws.pid"
: >"$T/logs/hold.log"
t0=$SECONDS
FAKE_AFTER="$T/after2.sh" SWTOR_ENGINE="$T/engine" WINEPREFIX="$T/prefix" "$FL" "$T/game.sh" </dev/null >/dev/null 2>&1 &
fl=$!
for _ in $(seq 60); do
  grep -q -e 'ended leftover' -e 'no leftover' -e 'leaving the engine' "$T/logs/hold.log" 2>/dev/null && break
  sleep 1
done
sleep 0.5
echo "  (hold-launcher done after $((SECONDS - t0)) s)"
sed 's/^/    hold.log: /' "$T/logs/hold.log"
check "hold, mac_wine: waited for the mac_wine with a Wine call" grep -q 'mac_wine running a Wine call ([0-9]*): waiting for it' "$T/logs/hold.log"
check "hold, mac_wine: not for the idle one" grep -q 'mac_wine running without a Wine call ([0-9]*): not waiting' "$T/logs/hold.log"
check "hold, mac_wine: left mac_wine alone (it finished by itself)" test -f "$T/mac_wine.done"
mwi=$(cat "$T/mac_wine_idle.pid" 2>/dev/null || echo 0)
check "hold, mac_wine: left the idle mac_wine alone" alive "$mwi"
kill "$mwi" 2>/dev/null || true
check "hold, mac_wine: ended the session that came back" grep -q 'came back' "$T/logs/hold.log"
check "hold, mac_wine: done once no wineserver for 3 s" grep -q 'no wineserver for 3.0 s' "$T/logs/hold.log"
check "hold, mac_wine: no wineserver left" test -z "$(ps -axww -o comm= | grep -Fx "$TE/wineserver")"
o2=$(cat "$T/orphan2.pid" 2>/dev/null || echo 0)
check "hold, mac_wine: ended mac_wine's orphaned winedevice.exe" all_gone "$o2"
check "hold, mac_wine: logged it" grep -q "ended leftover Wine process $o2 (winedevice.exe" "$T/logs/hold.log"
check "hold, mac_wine: nothing of the engine left" test -z "$(ps -axww -o comm= | grep -F -e "$T/" -e "${TWT##*/}/")"
wait "$fl" 2>/dev/null || true

echo "== 6c. the launchd job (simulated: run as launchd would)"
watch; check "watch: wrapper in place, nothing to do" test "$(st wrapper)" = ours
check "watch: logged" grep -q 'the wrapper is in place' "$LOGS/watch.log"
rm -f "$BS_WINE/bin-real/setsid-exec"; watch
check "watch: missing helper restored" test -x "$BS_WINE/bin-real/setsid-exec"

echo "== 7. a launcher update replaced the wrapper"
launcher_update() {
  cp -p "$BS_WINE/bin-real/wine64-preloader" "$BS_WINE/bin/.x" && mv -f "$BS_WINE/bin/.x" "$BS_WINE/bin/wine64-preloader"
  cp -p "$BS_WINE/bin-real/wine-preloader" "$BS_WINE/bin/.x" && mv -f "$BS_WINE/bin/.x" "$BS_WINE/bin/wine-preloader"
}
launcher_update
check "update: status replaced" test "$(st wrapper)" = replaced
check "play: off until the hook is repaired" eval 'play_target | grep -q "^unavailable A launcher update removed the hook"'
som install >"$SANDBOX/reinstall2.txt" 2>&1 || bad "reinstall after update"
check "update: wrapper back" test "$(st wrapper)" = ours
echo "== 7b. ...and the launchd job puts it back by itself"
launcher_update; n=$(notes)
mkdir "$SOM/.lock"; watch; rmdir "$SOM/.lock"
check "watch: leaves a running install alone" test "$(st wrapper)" = replaced
t0=$SECONDS; SETTLE=3 watch
check "watch: waited for Wine/bin to settle ($((SECONDS - t0)) s)" test $((SECONDS - t0)) -ge 2
check "watch: wrapper back" test "$(st wrapper)" = ours
check "watch: notified" test "$(notes)" -gt "$n"
check "watch: manifest has the new preloader" test "$(plutil -extract original_preloaders_sha256.wine64-preloader raw -o - "$SOM/install-manifest.json")" = "$(shasum -a 256 "$BS_WINE/bin-real/wine64-preloader" | cut -d" " -f1)"
check "watch: manifest still JSON" plutil -convert json -o /dev/null "$SOM/install-manifest.json"
n=$(notes); watch
check "watch: idempotent (no second notification)" test "$(notes)" = "$n"
# a launcher half way through its update: a preloader missing
launcher_update; mv "$BS_WINE/bin/wine-preloader" "$SANDBOX/wp.tmp"; n=$(notes); watch
check "watch: half-updated folder only notified" test "$(notes)" -gt "$n" -a ! -e "$BS_WINE/bin/wine-preloader"
check "watch: half-updated folder untouched" is_macho "$BS_WINE/bin/wine64-preloader"
mv "$SANDBOX/wp.tmp" "$BS_WINE/bin/wine-preloader"; watch
check "watch: complete again, wrapper back" test "$(st wrapper)" = ours

echo "== 8. uninstall restores the official install byte for byte, and copies the game settings back"
GS_REL="AppData/Local/SWTOR/swtor/settings"
GS_USER=$(plutil -extract settings_user raw -o - "$SOM/install-manifest.json")
GS_APP="$SOM/prefix/drive_c/users/crossover/$GS_REL"
GS_BS="$BS_WINE/drive_c/users/$GS_USER/$GS_REL"
if [ -d "$GS_APP" ]; then
  echo "test-change $(date +%s)" >"$GS_APP/client_settings_test.ini"
  echo "context" >"$GS_APP/ContextError.ini.new" && mv -f "$GS_APP/ContextError.ini.new" "$GS_APP/ContextError.ini"
fi
# Collect Logs (sandbox: the zip goes to the sandbox's Desktop)
echo "2026-10-16 launch: swtor.exe -set username SECRETACCOUNT -set password hunter2 $HOME/x" >>"$LOGS/install.log"
zip=$("$APP/Contents/Resources/collect-logs.sh" 2>"$SANDBOX/collect.err" || true)
check "logs: zip on the sandbox Desktop" test -f "$zip" -a "${zip#"$H/Desktop/"}" != "$zip"
if [ -f "$zip" ]; then
  mkdir -p "$SANDBOX/zip" && unzip -q -o "$zip" -d "$SANDBOX/zip"
  check "logs: install.log, env, manifest, system info" test -f "$SANDBOX"/zip/*/logs/install.log -a -f "$SANDBOX"/zip/*/env -a -f "$SANDBOX"/zip/*/install-manifest.json -a -f "$SANDBOX"/zip/*/system-info.txt
  check "logs: no -set values" eval '! grep -rq -e SECRETACCOUNT -e hunter2 "$SANDBOX/zip"'
  check "logs: no user name in paths" eval '! grep -rq "/Users/$(id -un)/" "$SANDBOX/zip"'
  check "logs: system info has the Mac" grep -q '^Mac: ' "$SANDBOX"/zip/*/system-info.txt
fi
# the Game Mode links the wrapper would have made at game start ("wine", or "swtor.exe" for a
# start.exe command)
pre="$SOM/engine/lib/wine/x86_64-unix/wine"; m=$(stat -f '%Fm' "$pre")
link="$SANDBOX/usertmp/winetemp-$(stat -f '%i-%z' "$pre")-${m%.*}-$((10#${m#*.}))/wine"
mkdir -p "$(dirname "$link")" && ln -sf "$SOM/gamemode/SWTOR.app/Contents/MacOS/swtor.exe" "$link" &&
  ln -sf "$SOM/gamemode/SWTOR.app/Contents/MacOS/swtor.exe" "${link%/*}/swtor.exe"
cp "$SANDBOX/fake" "$SOM/engine/bin/test-leftover"; l8=$(orphan "$SOM/engine/bin/test-leftover"); sleep 0.3
check "before uninstall: status shows the leftover" test "$(st busy)" = leftovers
som uninstall >"$SANDBOX/uninstall.txt" 2>&1 || { tail -20 "$SANDBOX/uninstall.txt"; bad "uninstall exit"; }
check "uninstall: ended the leftover first, logged" grep -q "^Ended leftover Wine processes.*test-leftover" "$SANDBOX/uninstall.txt"
check "uninstall: the leftover is gone" all_gone "$l8"
check "uninstall: @done" grep -q '^@done' "$SANDBOX/uninstall.txt"
check "uninstall: official install identical to stock" like_stock uninstall
check "uninstall: status stock" test "$(st wrapper)" = stock
check "play: unavailable after uninstall" test "$(play_target)" = "unavailable Install SWTOR on Mac first."
for c in engine frameworks prefix gamemode env dxvk.conf install-manifest.json; do
  check "uninstall: $c removed" test ! -e "$SOM/$c"
done
check "uninstall: Game Mode links removed" test ! -L "$link" -a ! -L "${link%/*}/swtor.exe"
check "uninstall: launchd job removed" test ! -e "$AGENT_PLIST" -a ! -e "$SOM/agent"
if [ -d "$GS_BS" ]; then
  check "uninstall: game settings copied back" grep -q test-change "$GS_BS/client_settings_test.ini"
  check "uninstall: ContextError.ini not copied" eval '! grep -qx context "$GS_BS/ContextError.ini" 2>/dev/null'
  check "uninstall: backup of the previous settings" test -n "$(ls -d "$GS_BS"-backup-* 2>/dev/null)"
  check "uninstall: backup has no test file" eval '! ls "$GS_BS"-backup-*/client_settings_test.ini >/dev/null 2>&1'
fi
check "uninstall: logs kept" test -s "$LOGS/install.log"
check "uninstall: no Wine left running" test -z "$(sandbox_wine)"

if [ -d "$PERSONAL_WRAPPER" ]; then
  echo "== 9. another wrapper (copy of this Mac's real one) is left alone"
  mkdir -p "$BS_WINE/bin-real"
  for b in wine-preloader wine64-preloader; do
    mv "$BS_WINE/bin/$b" "$BS_WINE/bin-real/$b"
    cp -p "$PERSONAL_WRAPPER/$b" "$BS_WINE/bin/$b"
  done
  for h in hold-launcher setsid-exec; do
    [ -f "$PERSONAL_WRAPPER/$h" ] && cp -p "$PERSONAL_WRAPPER/$h" "$BS_WINE/bin-real/$h"
  done
  OTHER="$(snap "$BS_WINE")"
  state=$(st wrapper)
  check "other: detected ($state)" test "$state" = personal -o "$state" = foreign
  if som install >"$SANDBOX/other.txt" 2>&1; then bad "other: install went ahead"; fi
  check "other: refused with a message" grep -q '^@error .*different Wine wrapper' "$SANDBOX/other.txt"
  check "other: untouched by install" test "$OTHER" = "$(snap "$BS_WINE")"
  if som uninstall >"$SANDBOX/other-un.txt" 2>&1; then bad "other: uninstall went ahead"; fi
  check "other: untouched by uninstall" test "$OTHER" = "$(snap "$BS_WINE")"
  echo "== 10. ...unless confirmed: take over, then uninstall to stock"
  SWTOR_ON_MAC_FORCE=1 som install >"$SANDBOX/force.txt" 2>&1 || { tail -20 "$SANDBOX/force.txt"; bad "forced install"; }
  check "force: wrapper ours" test "$(st wrapper)" = ours
  check "force: backup of the other wrapper" test -n "$(ls "$SOM/backup" 2>/dev/null)"
  check "force: no Wine left running" test -z "$(sandbox_wine)"
  som uninstall >"$SANDBOX/force-un.txt" 2>&1 || bad "uninstall after takeover"
  check "force: uninstall gives stock" like_stock force-uninstall
fi

if [ -x "$OLD_APP/Contents/Resources/som.sh" ]; then
  OLDSOM="$OLD_APP/Contents/Resources/som.sh"
  OLDV=$(sed -n 's/^version=//p' "$OLD_APP/Contents/Resources/app.properties")
  oldsom() { "$OLDSOM" "$@"; }
  oldst() { oldsom status | sed -n "s/^$1=//p"; }
  # The engines' downloads, verified, from the repository's cache (fetched once): the installs
  # below take them from the sandbox's download cache instead of downloading them each time.
  cached() { # <url> <sha256>: the path of the verified download in .cache
    local f="$REPO/.cache/$2/${1##*/}"
    if [ ! -f "$f" ]; then mkdir -p "${f%/*}"; curl -fsSL -o "$f.part" "$1" && mv "$f.part" "$f"; fi
    [ "$(shasum -a 256 "$f" | cut -d' ' -f1)" = "$2" ] && echo "$f"
  }
  val() { sed -n "s/^$1=//p" "$2" | head -1; }
  OLD_ENGINE=$(cached "$(val ENGINE_URL "$OLDSOM")" "$(val ENGINE_SHA256 "$OLDSOM")")
  OLD_FW=$(cached "$(val FW_URL "$OLDSOM")" "$(val FW_SHA256 "$OLDSOM")")
  NEW_ENGINE=$(cached "$(val ENGINE_URL "$SOMSH")" "$(val ENGINE_SHA256 "$SOMSH")")
  DLC="$H/Library/Caches/SWTOR on Mac/downloads"
  seed() { mkdir -p "$DLC"; cp -c "$@" "$DLC/"; }
  # shellcheck disable=SC2034 # (used in check's eval strings)
  OLD_SHA=$(val ENGINE_SHA256 "$OLDSOM")
  GS="$SOM/prefix/drive_c/users/crossover/AppData/Local/SWTOR/swtor/settings"
  echo "== 11. upgrade from $OLDV: an install of $OLDV ($OLD_APP), then this version over it"
  seed "$OLD_ENGINE" "$OLD_FW"
  t0=$SECONDS
  oldsom install >"$SANDBOX/old-install.txt" 2>&1 || { tail -20 "$SANDBOX/old-install.txt"; bad "$OLDV install exit"; }
  echo "  ($OLDV install took $((SECONDS - t0)) s)"
  check "$OLDV: installed, CrossOver 24.0.7 with its libraries" test -f "$SOM/engine/bin/wine-preloader" -a -d "$SOM/frameworks" -a "$(oldst installed_version)" = "$OLDV"
  oldsom set physkeys on >/dev/null; oldsom set memory high >/dev/null; oldsom set retina off >/dev/null
  check "$OLDV: settings changed (physkeys on, memory high, Retina off)" eval 'grep -qx physkeys=on "$SOM/settings.conf" && grep -qx memory=high "$SOM/settings.conf" && reg_has "Software\\\\Wine\\\\Mac Driver" "\"RetinaMode\"=\"n\""'
  mkdir -p "$GS" && echo "keybinds-from-$OLDV" >"$GS/upgrade-marker.ini"
  check "$OLDV: no Wine left running" test -z "$(sandbox_wine)"
  check "this version sees the old engine (engine_current=$(st engine_current), installed_engine=$(st installed_engine))" test "$(st engine_current)" = no -a "$(st installed_engine)" = WS12WineCX24.0.7_7
  check "settings refused until Reinstall" eval '! som set hud on >"$SANDBOX/set-old.txt" 2>&1 && grep -q "Click Reinstall" "$SANDBOX/set-old.txt" && grep -q "^SWTOR_FRAMEWORKS=" "$SOM/env"'
  OLD_STATE="$(cd "$SOM" && shasum -a 256 env settings.conf dxvk.conf prefix/system.reg prefix/user.reg prefix/userdef.reg engine/.som-source)"

  echo "== 11b. a failed upgrade puts $OLDV back (bin not writable: fails after wineboot, at the wrapper)"
  seed "$NEW_ENGINE"
  chmod a-w "$BS_WINE/bin"
  if som install >"$SANDBOX/upgrade-fail.txt" 2>&1; then bad "upgrade with read-only bin succeeded"; fi
  chmod u+w "$BS_WINE/bin"
  check "failed upgrade: got as far as the prefix update" grep -q "Updating the prefix for the new engine" "$SANDBOX/upgrade-fail.txt"
  check "failed upgrade: the old prefix was kept as a clone" grep -q "Keeping the prefix as it is" "$SANDBOX/upgrade-fail.txt"
  check "failed upgrade: engine, libraries, env, settings and prefix as before" test "$OLD_STATE" = "$(cd "$SOM" && shasum -a 256 env settings.conf dxvk.conf prefix/system.reg prefix/user.reg prefix/userdef.reg engine/.som-source 2>&1)"
  check "failed upgrade: CrossOver 24.0.7 back, with its libraries" test -f "$SOM/engine/bin/wine-preloader" -a -d "$SOM/frameworks" -a ! -e "$SOM/upgrade-backup"
  check "failed upgrade: Game Mode bundle is the old preloader again" cmp -s "$SOM/engine/bin/wine-preloader" "$SOM/gamemode/SWTOR.app/Contents/MacOS/swtor.exe"
  check "failed upgrade: $OLDV's wrapper still in place" test "$(oldst wrapper)" = ours
  out=$("$BS_WINE/bin/wine64-preloader" "$BS_WINE/bin/wine64" --version 2>&1 || true)
  check "failed upgrade: the wrapper runs CrossOver 24.0.7 ($out)" test "${out#*9.0}" != "$out"
  out=$(sbx_wine reg query 'HKCU\Software\Wine\Mac Driver' /v RetinaMode 2>/dev/null | tr -d '\r' || true)
  cleanup_wine
  check "failed upgrade: Wine 9 reads the prefix (RetinaMode $(echo "$out" | awk '/RetinaMode/ { print $NF }'))" test "$(echo "$out" | awk '/RetinaMode/ { print $NF }')" = n
  check "failed upgrade: no Wine left running" test -z "$(sandbox_wine)"

  echo "== 11c. upgrade"
  seed "$NEW_ENGINE"
  t0=$SECONDS
  som install >"$SANDBOX/upgrade.txt" 2>&1 || { tail -20 "$SANDBOX/upgrade.txt"; bad "upgrade exit"; }
  echo "  (upgrade took $((SECONDS - t0)) s)"
  check "upgrade: @done" grep -q '^@done' "$SANDBOX/upgrade.txt"
  check "upgrade: said so" grep -q "^Upgrading SWTOR on Mac $OLDV" "$SANDBOX/upgrade.txt"
  check "upgrade: the new engine (engine_current=$(st engine_current), installed_engine=$(st installed_engine))" test "$(st engine_current)" = yes -a "$(st installed_engine)" = "$(val ENGINE_NAME "$SOMSH")"
  check "upgrade: Wine $(sbx_wine --version 2>/dev/null)" test "$(sbx_wine --version 2>/dev/null)" = wine-11.0
  check "upgrade: old engine, its libraries and the copies removed" test ! -e "$SOM/engine/bin/wine-preloader" -a ! -e "$SOM/frameworks" -a ! -e "$SOM/upgrade-backup"
  check "upgrade: manifest version $APPV, engine_id cx26" test "$(plutil -extract version raw -o - "$SOM/install-manifest.json")/$(plutil -extract engine_id raw -o - "$SOM/install-manifest.json")" = "$APPV/cx26"
  check "upgrade: settings kept" eval 'grep -qx physkeys=on "$SOM/settings.conf" && grep -qx memory=high "$SOM/settings.conf" && grep -qx retina=off "$SOM/settings.conf" && grep -qx D9MT_MEMORY_PROFILE=high "$SOM/env"'
  check "upgrade: RetinaMode=n kept" reg_has 'Software\\Wine\\Mac Driver' '"RetinaMode"="n"'
  check "upgrade: PhysicalKeyboard=y kept, the app's Mac driver" eval 'reg_has "Software\\\\Wine\\\\AppDefaults\\\\swtor.exe\\\\Mac Driver" "\"PhysicalKeyboard\"=\"y\"" && cmp -s "$APP/Contents/Resources/wine/winemac.so" "$WM/winemac.so"'
  check "upgrade: raw mouse-look on (the new setting's default), the app's Mac driver, all three files" eval 'grep -qx rawmouse=on "$SOM/settings.conf" && reg_has "Software\\\\Wine\\\\AppDefaults\\\\swtor.exe\\\\Mac Driver" "\"RawMouseWhenCursorHidden\"=\"y\"" && wm_is app'
  check "upgrade: GrabPointer=n and the d3d9 override kept" eval 'reg_has "Software\\\\Wine\\\\AppDefaults\\\\swtor.exe\\\\X11 Driver" "\"GrabPointer\"=\"n\"" && reg_has "Software\\\\Wine\\\\AppDefaults\\\\swtor.exe\\\\DllOverrides" "\"d3d9\"=\"native,builtin\""'
  check "upgrade: game settings kept" grep -qx "keybinds-from-$OLDV" "$GS/upgrade-marker.ini"
  check "upgrade: d9mt's d3d9.dll" cmp -s "$APP/Contents/Resources/d9mt/d3d9.dll" "$sys/d3d9.dll"
  check "upgrade: bridge in the new engine" cmp -s "$APP/Contents/Resources/d9mt/winemetal.so" "$SOM/engine/lib/wine/x86_64-unix/winemetal.so"
  check "upgrade: Game Mode bundle from the new loader" eval 'cmp -s "$SOM/engine/lib/wine/x86_64-unix/wine" "$SOM/gamemode/SWTOR.app/Contents/MacOS/swtor.exe" && test -e "$SOM/gamemode/SWTOR.app/Contents/MacOS/ntdll.so"'
  check "upgrade: env for the new engine" eval 'grep -qx SWTOR_ENGINE_ID=cx26 "$SOM/env" && grep -q "^WINE_COMPATDB=" "$SOM/env" && ! grep -q "^SWTOR_FRAMEWORKS" "$SOM/env"'
  check "upgrade: wrapper and helpers of this version" eval 'cmp -s "$APP/Contents/Resources/helpers/hold-launcher" "$BS_WINE/bin-real/hold-launcher" && diff -q <(sed "s|@CONF@|$SOM/env|" "$APP/Contents/Resources/wine-wrapper.sh") "$BS_WINE/bin/wine64-preloader" >/dev/null'
  out=$("$BS_WINE/bin/wine64-preloader" "$BS_WINE/bin/wine64" --version 2>&1 || true)
  check "upgrade: the wrapper runs the new engine ($out)" test "$out" = wine-11.0
  out=$(sbx_wine reg query 'HKCU\Software\Wine\Mac Driver' /v RetinaMode 2>/dev/null | tr -d '\r' || true)
  cleanup_wine
  check "upgrade: Wine 11 reads the prefix (RetinaMode $(echo "$out" | awk '/RetinaMode/ { print $NF }'))" test "$(echo "$out" | awk '/RetinaMode/ { print $NF }')" = n
  check "upgrade: settings can change again" eval 'som set hud on >/dev/null && som set hud off >/dev/null'
  check "upgrade: download cache removed" test ! -e "$DLC"
  check "upgrade: no Wine left running" test -z "$(sandbox_wine)"

  echo "== 12. downgrade: $OLDV's Reinstall over this version"
  seed "$OLD_ENGINE" "$OLD_FW"
  t0=$SECONDS
  oldsom install >"$SANDBOX/downgrade.txt" 2>&1 || { tail -20 "$SANDBOX/downgrade.txt"; bad "downgrade exit"; }
  echo "  (downgrade took $((SECONDS - t0)) s)"
  check "downgrade: @done" grep -q '^@done' "$SANDBOX/downgrade.txt"
  check "downgrade: CrossOver 24.0.7 with its libraries again" eval 'test -f "$SOM/engine/bin/wine-preloader" -a -d "$SOM/frameworks" && [ "$(cat "$SOM/engine/.som-source")" = "$OLD_SHA" ]'
  check "downgrade: manifest $OLDV" test "$(plutil -extract version raw -o - "$SOM/install-manifest.json")" = "$OLDV"
  check "downgrade: Wine $(sbx_wine --version 2>/dev/null)" eval 'sbx_wine --version 2>/dev/null | grep -q "^wine-9.0"'
  check "downgrade: settings kept" eval 'grep -qx physkeys=on "$SOM/settings.conf" && grep -qx memory=high "$SOM/settings.conf" && grep -qx retina=off "$SOM/settings.conf"'
  check "downgrade: $OLDV's Mac driver (game keys by position)" cmp -s "$OLD_APP/Contents/Resources/wine/winemac.so" "$SOM/engine/lib/wine/x86_64-unix/winemac.so"
  check "downgrade: game settings kept" grep -qx "keybinds-from-$OLDV" "$GS/upgrade-marker.ini"
  check "downgrade: d9mt's d3d9.dll" cmp -s "$OLD_APP/Contents/Resources/d9mt/d3d9.dll" "$sys/d3d9.dll"
  check "downgrade: Game Mode bundle from the old preloader" cmp -s "$SOM/engine/bin/wine-preloader" "$SOM/gamemode/SWTOR.app/Contents/MacOS/swtor.exe"
  out=$("$BS_WINE/bin/wine64-preloader" "$BS_WINE/bin/wine64" --version 2>&1 || true)
  check "downgrade: the wrapper runs CrossOver 24.0.7 ($out)" test "${out#*9.0}" != "$out"
  out=$(sbx_wine reg query 'HKCU\Software\Wine\Mac Driver' /v RetinaMode 2>/dev/null | tr -d '\r' || true)
  check "downgrade: Wine 9 reads the prefix Wine 11 updated (RetinaMode $(echo "$out" | awk '/RetinaMode/ { print $NF }'))" test "$(echo "$out" | awk '/RetinaMode/ { print $NF }')" = n
  out=$(sbx_wine cmd /c echo downgrade-ok 2>/dev/null | tr -d '\r' || true)
  check "downgrade: Wine 9 runs a program in it (cmd: $out)" test "$out" = downgrade-ok
  if [ -f "$SANDBOX/probe/swtor.exe" ]; then
    out=$(WINEMAC_TEST_KEYBOARD_LAYOUT=com.apple.keylayout.Czech sbx_wine "$SANDBOX/probe/swtor.exe" 2>/dev/null | tr -d '\r' | sed -n 's/^numrow-name: //p')
    check "downgrade: $OLDV's game keys by position work (Czech number row: $out)" test "$out" = "1 2 3 4 5 6 7 8 9 0"
  fi
  cleanup_wine
  check "downgrade: no Wine left running" test -z "$(sandbox_wine)"

  echo "== 13. upgrade again (a prefix Wine 11, then Wine 9 updated), then uninstall"
  seed "$NEW_ENGINE"
  som install >"$SANDBOX/upgrade2.txt" 2>&1 || { tail -20 "$SANDBOX/upgrade2.txt"; bad "second upgrade exit"; }
  check "upgrade again: @done, the new engine" eval 'grep -q "^@done" "$SANDBOX/upgrade2.txt" && [ "$(st engine_current)" = yes ] && [ ! -e "$SOM/frameworks" ]'
  out=$(sbx_wine cmd /c echo upgrade-ok 2>/dev/null | tr -d '\r' || true)
  check "upgrade again: Wine 11 runs a program in it (cmd: $out)" test "$out" = upgrade-ok
  if [ -f "$SANDBOX/probe/swtor.exe" ]; then
    out=$(WINEMAC_TEST_KEYBOARD_LAYOUT=com.apple.keylayout.Czech sbx_wine "$SANDBOX/probe/swtor.exe" 2>/dev/null | tr -d '\r' | sed -n 's/^numrow-name: //p')
    check "upgrade again: game keys by position (Czech number row: $out)" test "$out" = "1 2 3 4 5 6 7 8 9 0"
  fi
  cleanup_wine
  check "upgrade again: no Wine left running" test -z "$(sandbox_wine)"
  som uninstall >"$SANDBOX/uninstall2.txt" 2>&1 || { tail -20 "$SANDBOX/uninstall2.txt"; bad "uninstall after upgrade"; }
  check "uninstall after upgrade: official install identical to stock" like_stock uninstall2
  check "uninstall after upgrade: app files gone" eval 'for c in engine frameworks upgrade-backup prefix gamemode env install-manifest.json; do [ ! -e "$SOM/$c" ] || exit 1; done'

  echo "== 14. this version's Uninstall of a $OLDV install (app updated, not reinstalled)"
  seed "$OLD_ENGINE" "$OLD_FW"
  oldsom install >"$SANDBOX/old-install2.txt" 2>&1 || bad "$OLDV install exit"
  som uninstall >"$SANDBOX/uninstall3.txt" 2>&1 || { tail -20 "$SANDBOX/uninstall3.txt"; bad "uninstall of $OLDV"; }
  check "uninstall of $OLDV: official install identical to stock" like_stock uninstall3
  check "uninstall of $OLDV: engine and its libraries gone" test ! -e "$SOM/engine" -a ! -e "$SOM/frameworks" -a ! -e "$SOM/install-manifest.json"
  check "uninstall of $OLDV: no Wine left running" test -z "$(sandbox_wine)"
else
  echo "== 11-14 skipped: no older app at $OLD_APP (OLD_APP)"
fi

cleanup_wine
check "end: no Wine process of the sandbox" test -z "$(sandbox_wine)"
echo "== $pass passed, $fail failed"
if [ -z "${KEEP:-}" ] && [ "$fail" = 0 ]; then chmod -R u+w "$SANDBOX" 2>/dev/null || true; rm -rf "$SANDBOX"; fi
[ "$fail" = 0 ]
