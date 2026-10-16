#!/bin/bash
# End-to-end test of the installer (Resources/som.sh of a built app) in a sandbox, without
# touching the real system: a fake official install made of APFS clones of this Mac's real one
# (the app and Broadsword's Wine folder, not the game data), put back to stock if a wrapper is
# installed, under $SANDBOX (SWTOR_ON_MAC_ROOT). Downloads the real engine and runs Wine
# (wineboot, reg) on the sandbox prefix only, then checks that no Wine process is left.
#
#   scripts/test-sandbox.sh [path/to/SWTOR on Mac.app]
#
# Needs the official SWTOR Mac app installed on this Mac (it is only read). Quit SWTOR first.
# Env: SANDBOX (default /tmp/som-sandbox), KEEP=1 (leave the sandbox for a look afterwards)
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$(cd "${1:-dist/SWTOR on Mac.app}" && pwd)"
SOMSH="$APP/Contents/Resources/som.sh"
[ -x "$SOMSH" ] || { echo "no $SOMSH; run ./build.sh" >&2; exit 1; }
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
is_macho() { file -b "$1" | grep -q '^Mach-O'; }
# reg_has <key as in user.reg, with \\> <value line>: the value is set under that key
reg_has() {
  K="[$1]" V="$2" awk 'BEGIN { k = ENVIRON["K"]; v = ENVIRON["V"] }
    index($0, "[") == 1 { inkey = (substr($0, 1, length(k)) == k && substr($0, length(k) + 1, 1) == " ") }
    inkey && $0 == v { found = 1 }
    END { exit !found }' "$SOM/prefix/user.reg"
}
# Fingerprint of a tree: every path with type, mode, symlink target, and file contents
snap() {
  ( cd "$1" && find . -print0 | sort -z | xargs -0 stat -f '%N %HT %Sp %z %Y' &&
    find . -type f -print0 | sort -z | xargs -0 shasum -a 256 )
}
# Wine processes of the sandbox (its engine, or anything with the sandbox in its path)
sandbox_wine() {
  local tag=/nonexistent/
  [ -f "$SOM/engine/bin/wine-preloader" ] && tag="/winetemp-$(stat -f '%i-%z' "$SOM/engine/bin/wine-preloader")-"
  ps -axww -o pid=,comm= | grep -F -e "$SANDBOX/" -e "$tag" | grep -v grep || true
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
PERSONAL_WRAPPER="$SANDBOX/personal-wrapper"
if ! is_macho "$REAL_WINE/bin/wine64-preloader"; then
  mkdir -p "$PERSONAL_WRAPPER"
  cp -p "$REAL_WINE/bin/wine64-preloader" "$REAL_WINE/bin/wine-preloader" "$PERSONAL_WRAPPER/"
  cp -p "$REAL_WINE/bin-real/hold-launcher" "$REAL_WINE/bin-real/setsid-exec" "$PERSONAL_WRAPPER/" 2>/dev/null || true
fi
STOCK="$(snap "$BS_WINE")"
check "fake official install is stock" test "$(st wrapper)" = stock
check "status: official app found" test "$(st official_app)" = yes
check "status: not installed" test "$(st installed)" = no

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

echo "== 3. failed install rolls back (bin not writable)"
chmod a-w "$BS_WINE/bin"
if som install >"$SANDBOX/fail.txt" 2>&1; then bad "install with read-only bin succeeded"; fi
chmod u+w "$BS_WINE/bin"
check "fail: official install unchanged" test "$STOCK" = "$(snap "$BS_WINE")"
check "fail: no engine/prefix left" test ! -e "$SOM/engine" -a ! -e "$SOM/prefix" -a ! -e "$SOM/install-manifest.json"
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
sys="$SOM/prefix/drive_c/windows/system32"
check "install: d9mt d3d9.dll" cmp -s "$APP/Contents/Resources/d9mt/d3d9.dll" "$sys/d3d9.dll"
check "install: Wine's d3d9 kept" test "$(dd if="$sys/d3d9.dll.wine" bs=1 skip=64 count=12 2>/dev/null)" = "Wine builtin"
check "install: RetinaMode=y" reg_has 'Software\\Wine\\Mac Driver' '"RetinaMode"="y"'
check "install: GrabPointer=n" reg_has 'Software\\Wine\\AppDefaults\\swtor.exe\\X11 Driver' '"GrabPointer"="n"'
check "install: d3d9 override" reg_has 'Software\\Wine\\AppDefaults\\swtor.exe\\DllOverrides' '"d3d9"="native,builtin"'
check "install: gamemode exe = engine preloader" cmp -s "$SOM/engine/bin/wine-preloader" "$SOM/gamemode/SWTOR.app/Contents/MacOS/swtor.exe"
check "install: gamemode plist" plutil -lint -s "$SOM/gamemode/SWTOR.app/Contents/Info.plist"
check "install: env" grep -q '^SWTOR_ENGINE=' "$SOM/env"
check "install: dxvk.conf" grep -q 'presentInterval = 1' "$SOM/dxvk.conf"
check "install: manifest" plutil -lint -s "$SOM/install-manifest.json"
check "install: game settings user crossover" test -d "$SOM/prefix/drive_c/users/crossover"
check "install: download cache removed" test ! -e "$H/Library/Caches/SWTOR on Mac/downloads"
check "install: log" test -s "$LOGS/install.log"
check "install: no Wine left running" test -z "$(sandbox_wine)"

echo "== 5. the wrapper hands Wine calls to the app's engine"
out=$("$BS_WINE/bin/wine64-preloader" "$BS_WINE/bin/wine64" --version 2>&1 || true)
check "wrapper: engine wine answers ($out)" test "${out#*9.0}" != "$out"
cleanup_wine
check "wrapper: no Wine left running" test -z "$(sandbox_wine)"

echo "== 6. reinstall is idempotent"
ino=$(stat -f %i "$SOM/engine/bin/wine-preloader")
som install >"$SANDBOX/reinstall.txt" 2>&1 || { tail -20 "$SANDBOX/reinstall.txt"; bad "reinstall exit"; }
check "reinstall: engine kept" test "$ino" = "$(stat -f %i "$SOM/engine/bin/wine-preloader")"
check "reinstall: prefix kept" grep -q 'Updating the existing Wine prefix' "$SANDBOX/reinstall.txt"
check "reinstall: wrapper ours" test "$(st wrapper)" = ours
check "reinstall: no Wine left running" test -z "$(sandbox_wine)"

echo "== 7. a launcher update replaced the wrapper"
cp -p "$BS_WINE/bin-real/wine64-preloader" "$BS_WINE/bin/.x" && mv -f "$BS_WINE/bin/.x" "$BS_WINE/bin/wine64-preloader"
cp -p "$BS_WINE/bin-real/wine-preloader" "$BS_WINE/bin/.x" && mv -f "$BS_WINE/bin/.x" "$BS_WINE/bin/wine-preloader"
check "update: status replaced" test "$(st wrapper)" = replaced
som install >"$SANDBOX/reinstall2.txt" 2>&1 || bad "reinstall after update"
check "update: wrapper back" test "$(st wrapper)" = ours

echo "== 8. uninstall restores the official install byte for byte"
# the Game Mode link the wrapper would have made at game start
pre="$SOM/engine/bin/wine-preloader"; m=$(stat -f '%Fm' "$pre")
link="$SANDBOX/usertmp/winetemp-$(stat -f '%i-%z' "$pre")-${m%.*}-$((10#${m#*.}))/swtor.exe"
mkdir -p "$(dirname "$link")" && ln -sf "$SOM/gamemode/SWTOR.app/Contents/MacOS/swtor.exe" "$link"
som uninstall >"$SANDBOX/uninstall.txt" 2>&1 || { tail -20 "$SANDBOX/uninstall.txt"; bad "uninstall exit"; }
check "uninstall: @done" grep -q '^@done' "$SANDBOX/uninstall.txt"
check "uninstall: official install identical to stock" test "$STOCK" = "$(snap "$BS_WINE")"
check "uninstall: status stock" test "$(st wrapper)" = stock
for c in engine frameworks prefix gamemode env dxvk.conf install-manifest.json; do
  check "uninstall: $c removed" test ! -e "$SOM/$c"
done
check "uninstall: Game Mode link removed" test ! -L "$link"
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
  check "force: uninstall gives stock" test "$STOCK" = "$(snap "$BS_WINE")"
fi

cleanup_wine
check "end: no Wine process of the sandbox" test -z "$(sandbox_wine)"
echo "== $pass passed, $fail failed"
if [ -z "${KEEP:-}" ] && [ "$fail" = 0 ]; then chmod -R u+w "$SANDBOX" 2>/dev/null || true; rm -rf "$SANDBOX"; fi
[ "$fail" = 0 ]
