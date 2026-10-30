#!/bin/bash
# End-to-end test of the installer (Resources/som.sh of a built app) in a sandbox, without
# touching the real system: a fake official install under $SANDBOX (SWTOR_ON_MAC_ROOT), a
# stand-in for the official app with its Info.plist and an APFS clone of Broadsword's Wine
# folder (not the game data), put back to stock if a wrapper is installed. Downloads the real engine and runs Wine
# (wineboot, reg) on the sandbox prefix only, then checks that no Wine process is left.
# Then the way from and back to 0.0.6 (sections 11-13, with OLD_APP): an install of 0.0.6
# upgraded by this one (and a failed upgrade rolled back), this one replaced by 0.0.6 again
# (Reinstall of the older app), and upgraded once more. Then the way from and back to the
# previous release on the same engine (section 15, with PREV_APP): what this version's
# Reinstall changes over it (d9mt's d3d9.dll in the prefix and the env lines, nothing in the
# engine), and the previous release's Reinstall over this one. A release build then goes on from
# a development build (section 16, with DEV_APP): its A/B switches and test caches removed, the
# rest kept, and uninstall to stock.
#
#   scripts/test-sandbox.sh [path/to/SWTOR on Mac.app]
#
# Needs the official SWTOR Mac app installed on this Mac (it is only read). Quit SWTOR first.
# Env: SANDBOX (default /tmp/som-sandbox), KEEP=1 (leave the sandbox for a look afterwards),
#      OLD_APP (default release/0.0.6/SWTOR on Mac.app; missing: sections 11-14 are skipped),
#      PREV_APP (default release/0.1.0/SWTOR on Mac.app; missing: section 15 is skipped),
#      DEV_APP (default release/0.1.1-dev.1/SWTOR on Mac.app; release builds only, missing:
#      section 16 is skipped)
# Under a job runner (JOB_ID and JOB_ROOT set) the sandbox is the job's: SANDBOX must be named and
# lie outside the temporary folders (else exit 64; the job's adapter puts it in the job's run
# directory), and at the end the text output stays there whatever the result: after a failure
# with the reproducer set in repro/ (keep_repro; home/ itself if that copy fails), while the heavy
# children (home/, prev-engine/, dev-engine/) go. KEEP has no effect there: the job's manifest
# decides what stays.
set -euo pipefail
cd "$(dirname "$0")/.."
# ok, bad, check, piped and the job runner's rules (owned_path)
# shellcheck source=scripts/fixtures/lib.sh
. scripts/fixtures/lib.sh
pass=0 fail=0
APP="$(cd "${1:-dist/SWTOR on Mac.app}" && pwd)"
SOMSH="$APP/Contents/Resources/som.sh"
[ -x "$SOMSH" ] || { echo "no $SOMSH; run ./build.sh" >&2; exit 1; }
HL_APP="$APP/Contents/Resources/helpers/hold-launcher"
OLD_APP="${OLD_APP:-release/0.0.6/SWTOR on Mac.app}"
[ ! -d "$OLD_APP" ] || OLD_APP="$(cd "$OLD_APP" && pwd)"
PREV_APP="${PREV_APP:-release/0.1.0/SWTOR on Mac.app}"
[ ! -d "$PREV_APP" ] || PREV_APP="$(cd "$PREV_APP" && pwd)"
DEV_APP="${DEV_APP:-release/0.1.1-dev.1/SWTOR on Mac.app}"
[ ! -d "$DEV_APP" ] || DEV_APP="$(cd "$DEV_APP" && pwd)"
REPO="$PWD"
# Under a job runner the sandbox is the job's: SANDBOX is named, and never a temporary folder
JOB_SANDBOX=""
if under_job_runner; then owned_path SANDBOX "${SANDBOX:-}" || exit 64; JOB_SANDBOX=1; fi
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

som() { "$SOMSH" "$@"; }
st() { som status | sed -n "s/^$1=//p"; }
# what the window's Play button would do (the app's own resolution; nothing is opened)
play_target() { "$APP/Contents/MacOS/SWTORonMac" --play-target 2>/dev/null; }
# what a press would do: the hook check first (som.sh rehook), then the fresh status
play_check() { "$APP/Contents/MacOS/SWTORonMac" --play-check 2>/dev/null; }
is_macho() { file -b "$1" | piped '^Mach-O'; }
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
# the app's launcher hook check (som.sh rehook, when the app opens and before Play); its answer
# in $SANDBOX/rehook.txt. SETTLE: how recent a change in Wine/bin counts as an update still
# writing (0: none does)
rehook() { SWTOR_ON_MAC_SETTLE="${SETTLE:-0}" som rehook >"$SANDBOX/rehook.txt" 2>&1; }
said() { grep -qx "$1" "$SANDBOX/rehook.txt"; }
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
# envv <name>: the variable as the wrapper gets it from the sandbox's env file ("<unset>" if not)
envv() { ( set -a; . "$SOM/env"; set +a; eval "printf '%s' \"\${$1-<unset>}\"" ); }
# macho_same <a> <b>: the same Mach-O code: equal once their code signatures and the space
# codesign reserves for one (__LINKEDIT's vmsize) are left out
macho_same() {
  local t r
  t=$(mktemp -d)
  cp "$1" "$t/a" && cp "$2" "$t/b" || { rm -rf "$t"; return 1; }
  codesign --remove-signature "$t/a" 2>/dev/null || true
  codesign --remove-signature "$t/b" 2>/dev/null || true
  python3 -I -c '
import struct, sys
def norm(p):
    b = bytearray(open(p, "rb").read())
    if struct.unpack_from("<I", b, 0)[0] != 0xfeedfacf:
        sys.exit(1)
    off = 32
    for _ in range(struct.unpack_from("<I", b, 16)[0]):
        cmd, size = struct.unpack_from("<II", b, off)
        if cmd == 0x19 and bytes(b[off + 8:off + 24]).rstrip(b"\0") == b"__LINKEDIT":
            struct.pack_into("<Q", b, off + 32, 0)
        off += size
    return bytes(b)
sys.exit(0 if norm(sys.argv[1]) == norm(sys.argv[2]) else 1)' "$t/a" "$t/b"
  r=$?
  rm -rf "$t"
  return $r
}
cleanup_wine() {
  local ws="$SOM/engine/bin/wineserver"
  [ -x "$ws" ] && WINEPREFIX="$SOM/prefix" DYLD_FALLBACK_LIBRARY_PATH="$SOM/frameworks:/usr/lib" "$ws" -k 2>/dev/null || true
  sleep 1
  sandbox_wine | awk '{ print $1 }' | xargs kill -9 2>/dev/null || true
}
# Under a job runner (JOB_SANDBOX): keep_repro and job_sandbox_end, the end of the job's sandbox
# shellcheck source=scripts/fixtures/job-sandbox.sh
. scripts/fixtures/job-sandbox.sh
SANDBOX_MADE="" SANDBOX_ENDED=""
# (a run that ends before its end, by an error or a signal, is a failure)
on_exit() {
  set +e
  cleanup_wine
  [ -z "$JOB_SANDBOX" ] || [ -z "$SANDBOX_MADE" ] || [ -n "$SANDBOX_ENDED" ] || job_sandbox_end 1
}
trap on_exit EXIT

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
SANDBOX_MADE=1
# the run's inputs, to repeat it: the apps (version, CDHash), the official app's version, the
# commit of these scripts, macOS
app_line() { # <name> <app>
  if [ -d "$2" ]; then
    echo "$1 $2 version=$(sed -n 's/^version=//p' "$2/Contents/Resources/app.properties") cdhash=$(codesign -dvvv "$2" 2>&1 | sed -n 's/^CDHash=//p')"
  else echo "$1 $2 (missing)"; fi
}
{ app_line app "$APP"; app_line old "$OLD_APP"; app_line prev "$PREV_APP"; app_line dev "$DEV_APP"
  echo "official $(plutil -extract CFBundleShortVersionString raw -o - "$REAL_APP/Contents/Info.plist")"
  echo "scripts $(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)$([ -z "$(git -C "$REPO" status --porcelain 2>/dev/null)" ] || echo " (with changes)")"
  echo "macos $(sw_vers -productVersion) $(uname -m)"
} >"$SANDBOX/inputs.txt"
mkdir -p "$SANDBOX/Applications" "$(dirname "$BS_WINE")" "$SANDBOX/usertmp"
# The sandbox's official app: a bundle of its own with the real one's Info.plist (its bundle id,
# by which the window finds the launcher running), not a copy. The tests run stand-ins for the
# launcher from inside it, and a program added to a copy of Broadsword's signed app breaks its
# seal, which Gatekeeper reports in a dialog as a damaged app. This one has its stand-ins
# (tiny programs of our own: a copy of /bin/sleep, a platform binary, is not allowed to run)
# from the start and an ad-hoc signature that stays valid; the real app is only read.
mkdir -p "$BS_APP/Contents/MacOS"
cp "$REAL_APP/Contents/Info.plist" "$BS_APP/Contents/Info.plist"
printf '#include <stdlib.h>\n#include <unistd.h>\nint main(int c, char **v) { sleep(c > 1 ? atoi(v[1]) : 30); return 0; }\n' >"$SANDBOX/sleep.c"
for p in "$(plutil -extract CFBundleExecutable raw -o - "$REAL_APP/Contents/Info.plist")" test-sleep test-sleep2 test-sleep3 mac_wine; do
  clang -o "$BS_APP/Contents/MacOS/$p" "$SANDBOX/sleep.c"
done
codesign --force --sign - "$BS_APP" 2>/dev/null
codesign --verify --strict "$BS_APP" || { echo "the sandbox's official app is not validly signed" >&2; exit 1; }
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
# (a stand-in for the launcher, built into the sandbox's official app)
"$BS_APP/Contents/MacOS/test-sleep" 30 &
sleeper=$!
sleep 0.5
if som install >"$SANDBOX/running.txt" 2>&1; then bad "install while running"; else
  check "running: refused with a message" grep -q '@error Quit the SWTOR launcher' "$SANDBOX/running.txt"
fi
kill "$sleeper" 2>/dev/null || true; wait "$sleeper" 2>/dev/null || true

echo "== 2b. leftover Wine processes of the engine (dummy programs; only those may end)"
# One dummy program for every part: as .../wineserver it is a Wine server (writes ws.pid next
# to itself; "wineserver -k" sends that one SIGTERM and returns at once, and it lingers
# $FAKE_LINGER s before it exits); with -p<n> (as hold-launcher starts it) it daemonizes like
# Wine's: exit 0 once the server runs, 2 if one already does, with WINEPREFIX set holding the
# lock in /tmp/.wine-<uid>/server-<dev>-<ino> as Wine's does, and records its arguments
# (ws.args) and the fds it inherited (ws.fds); it serves $FAKE_SERVER_SECS (60) s. Anything
# else sleeps argv[1] seconds (default 60), with $FAKE_MAP mapped (a file of a session's
# server directory, as Wine processes map them), or for as long as process $FAKE_UNTIL_PID
# lives (a system process of a session).
cat >"$SANDBOX/fake.c" <<'C'
#include <fcntl.h>
#include <libgen.h>
#include <mach-o/dyld.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
static volatile sig_atomic_t term;
static void on_term(int s) { (void)s; term = 1; }
/* the prefix's server lock, as Wine's server takes it: its fd, -1 without WINEPREFIX, -2 held */
static int take_lock(void)
{
    const char *p = getenv("WINEPREFIX");
    struct stat st;
    char d[1024], l[1100];
    if (!p || stat(p, &st) != 0) return -1;
    snprintf(d, sizeof(d), "/tmp/.wine-%u", getuid());
    mkdir(d, 0700);
    snprintf(d, sizeof(d), "/tmp/.wine-%u/server-%llx-%llx", getuid(),
             (unsigned long long)st.st_dev, (unsigned long long)st.st_ino);
    mkdir(d, 0700);
    snprintf(l, sizeof(l), "%s/lock", d);
    int fd = open(l, O_RDWR | O_CREAT, 0600);
    struct flock fl = { .l_type = F_WRLCK, .l_whence = SEEK_SET, .l_start = 0, .l_len = 1 };
    if (fd < 0 || fcntl(fd, F_SETLK, &fl) != 0) return -2;
    return fd;
}
static void serve(const char *pidf, int secs)
{
    FILE *f = fopen(pidf, "w");
    if (f) { fprintf(f, "%d\n", getpid()); fclose(f); }
    signal(SIGTERM, on_term);
    for (int i = 0; i < secs * 10 && !term; i++) usleep(100000);
    if (term && getenv("FAKE_LINGER")) sleep(atoi(getenv("FAKE_LINGER")));
}
int main(int argc, char **argv)
{
    char dir[1024], pidf[1100], f2[1100];
    uint32_t size = sizeof(dir);
    if (_NSGetExecutablePath(dir, &size) != 0) return 2;  /* (argv[0] may be a bare name) */
    char *d = dirname(dir);
    snprintf(pidf, sizeof(pidf), "%s/ws.pid", d);
    const char *base = strrchr(argv[0], '/');
    base = base ? base + 1 : argv[0];
    if (!strcmp(base, "wineserver")) {
        if (argc > 1 && !strcmp(argv[1], "-k")) {
            FILE *f = fopen(pidf, "r");
            int pid = 0;
            if (f) { if (fscanf(f, "%d", &pid) != 1) pid = 0; fclose(f); }
            return pid > 1 && kill(pid, SIGTERM) == 0 ? 0 : 1;
        }
        int secs = getenv("FAKE_SERVER_SECS") ? atoi(getenv("FAKE_SERVER_SECS")) : 60;
        if (argc > 1 && !strncmp(argv[1], "-p", 2)) {
            snprintf(f2, sizeof(f2), "%s/ws.fds", d);
            FILE *ff = fopen(f2, "a");
            if (ff) {
                for (int fd = 3; fd < 256; fd++)
                    if (fd != fileno(ff) && fcntl(fd, F_GETFD) != -1) fprintf(ff, "%d ", fd);
                fputc('\n', ff);
                fclose(ff);
            }
            snprintf(f2, sizeof(f2), "%s/ws.args", d);
            if ((ff = fopen(f2, "a"))) {
                for (int i = 1; i < argc; i++) fprintf(ff, "%s%s", i > 1 ? " " : "", argv[i]);
                fputc('\n', ff);
                fclose(ff);
            }
            int p[2];
            if (pipe(p) != 0) return 1;
            pid_t c = fork();
            if (c == 0) {
                setsid();
                close(p[0]);
                if (take_lock() == -2) _exit(2);
                char x = 0;
                if (write(p[1], &x, 1) != 1) _exit(1);
                close(p[1]);
                serve(pidf, secs);
                _exit(0);
            }
            close(p[1]);
            char x;
            if (read(p[0], &x, 1) == 1) return 0;
            int st = 0;
            waitpid(c, &st, 0);
            return WIFEXITED(st) ? WEXITSTATUS(st) : 1;
        }
        if (take_lock() == -2) return 2;
        serve(pidf, secs);
        return 0;
    }
    const char *map = getenv("FAKE_MAP");
    if (map) {
        int fd = open(map, O_RDWR | O_CREAT, 0600);
        if (fd >= 0 && ftruncate(fd, 4096) == 0) (void)mmap(NULL, 4096, PROT_READ, MAP_SHARED, fd, 0);
    }
    int secs = argc > 1 ? atoi(argv[1]) : 60;
    const char *until = getenv("FAKE_UNTIL_PID");
    for (int i = 0; i < secs * 10; i++) {
        if (until && kill(atoi(until), 0) != 0) break;
        usleep(100000);
    }
    return 0;
}
C
clang -o "$SANDBOX/fake" "$SANDBOX/fake.c"
# orphan and orphan_as: detached stand-ins (argv[0] rewritten for the second); they print the pid
# shellcheck source=scripts/fixtures/orphan.sh
. scripts/fixtures/orphan.sh
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
stand_in "(the loader's child)" orphan_ready "$l3" "$EL"
check "leftovers: status busy=leftovers" test "$(st busy)" = leftovers
check "leftovers: not counted as running" test "$(st running)" = no
check "leftovers: names ($(st busy_detail))" eval 'st busy_detail | piped winedevice.exe'
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
# a game outside the sandbox (another sandbox's test run, the real game) does not count here
OUTSIDE=$(mktemp -d /tmp/som-outside.XXXXXX)
cp "$SANDBOX/fake" "$OUTSIDE/game"
og=$(orphan_as 'C:\Program Files\SWTOR\retailclient\swtor.exe' "$OUTSIDE/game"); sleep 0.3
check "game outside the sandbox: not this sandbox's (busy=$(st busy))" test "$(st busy)" = leftovers
kill "$og" 2>/dev/null || true; rm -rf "$OUTSIDE"
# Broadsword's Wine: with its wineserver, a session of it (wait); without, its processes are
# leftovers like the engine's (e.g. of a game start while the hook was not active)
mkdir -p "$BS_WINE/test-bin"
cp "$SANDBOX/fake" "$BS_WINE/test-bin/wineserver"
cp "$SANDBOX/fake" "$BS_WINE/test-wine"
ws=$(orphan "$BS_WINE/test-bin/wineserver"); w=$(orphan_as 'C:\windows\system32\winedevice.exe' "$BS_WINE/test-wine"); sleep 0.3
check "Broadsword's Wine: status busy=wine" test "$(st busy)" = wine
check "Broadsword's Wine: install refuses" eval '! som install >"$SANDBOX/wine.txt" 2>&1 && grep -q "Broadsword.s Wine is still running" "$SANDBOX/wine.txt"'
check "Broadsword's Wine: the leftover not ended" alive "$l4"
check "Broadsword's Wine: its own process not ended" alive "$w"
kill "$ws"; sleep 0.3
# Broadsword's mac_wine (the stand-in in the sandbox's official app) outlives the launcher:
# neither the launcher nor anything to end
mw=$(orphan "$BS_APP/Contents/MacOS/mac_wine" 30); sleep 0.3
check "Broadsword's Wine without its wineserver: busy=leftovers ($(st busy))" test "$(st busy)" = leftovers
check "Broadsword's Wine leftover: named ($(st busy_detail))" eval 'st busy_detail | piped winedevice.exe'
check "mac_wine: not taken for the launcher" eval '! som status | piped -x busy=launcher'
som end-leftovers >"$SANDBOX/end3.txt" 2>&1 || bad "end-leftovers (Broadsword's) exit"
sleep 0.3
check "end-leftovers: Broadsword's Wine leftover ended" all_gone "$w" "$l4"
check "end-leftovers: mac_wine left alone" alive "$mw"
check "end-leftovers: busy=none" test "$(st busy)" = none
kill "$mw" 2>/dev/null || true
rm -rf "$BS_WINE/test-wine" "$BS_WINE/test-bin"
l4=$(orphan "$WT/winedevice.exe"); sleep 0.3
kill "$p3" "$d1" "$d2" 2>/dev/null || true; wait "$p3" 2>/dev/null || true
pkill -f "$SANDBOX/decoy/" 2>/dev/null || true
rm -f "$EB/wineserver" "$EB/ws.pid"
# l4 is still running: the next (failed) install ends it first

echo "== 2b. what the app takes for the official launcher (by bundle id, else its executable)"
# (launcher 7.2.207 changed the bundle id from Solid State Networks' to BioWare's)
# is_launcher, and LAUNCHER_EXE: the launcher's file name outside any app's Contents/MacOS
# shellcheck source=scripts/fixtures/launcher.sh
. scripts/fixtures/launcher.sh
check "launcher: BioWare's bundle id (7.2.207 and later)" test "$(is_launcher com.bioware.starwars-theoldrepubliclauncher /x/y)" = launcher
check "launcher: Solid State Networks' bundle id (before 7.2.207)" test "$(is_launcher com.solidstatenetworks.host /x/y)" = launcher
check "launcher: by its executable, whatever the id" test "$(is_launcher org.example.other "$LAUNCHER_EXE")" = launcher
check "launcher: not another app" test "$(is_launcher com.apple.Safari /Applications/Safari.app/Contents/MacOS/Safari)" = "not launcher"
check "launcher: the stand-in official app's id is one of them ($(plutil -extract CFBundleIdentifier raw -o - "$BS_APP/Contents/Info.plist" 2>/dev/null))" \
  test "$(is_launcher "$(plutil -extract CFBundleIdentifier raw -o - "$BS_APP/Contents/Info.plist" 2>/dev/null)" /x/y)" = launcher

echo "== 2c. what the app takes for the game (it brings the game to the front when it starts)"
# Launch Services knows the game by the path CrossOver starts it from: winetemp-<...>/wine, a
# link to the Game Mode bundle's swtor.exe, no bundle id (T2 2026-10-20); with Game Mode off a
# hard link of the loader, whose process Wine shows as .../retailclient/swtor.exe (argv[0])
is_game() { "$APP/Contents/MacOS/SWTORonMac" --is-game "$@" 2>/dev/null; }
GT="$SANDBOX/usertmp/winetemp-9-8-7-6"
mkdir -p "$GT" "$SANDBOX/gm/SWTOR.app/Contents/MacOS"
cp "$SANDBOX/fake" "$SANDBOX/gm/SWTOR.app/Contents/MacOS/swtor.exe"
ln -sf "$SANDBOX/gm/SWTOR.app/Contents/MacOS/swtor.exe" "$GT/wine"
cp "$SANDBOX/fake" "$GT/loader" && ln -f "$GT/loader" "$GT/wine2"
check "game: the Game Mode link (no bundle id)" test "$(is_game - "$GT/wine" 0)" = game
g1=$(orphan_as '/Games/SWTOR/retailclient/swtor.exe' "$GT/wine2")
g2=$(orphan_as 'C:\windows\explorer.exe' "$GT/wine2"); sleep 0.3
check "game: a winetemp loader whose argv[0] is swtor.exe (Game Mode off)" test "$(is_game - "$GT/wine2" "$g1")" = game
check "game: not another Wine program from the same loader" test "$(is_game - "$GT/wine2" "$g2")" = "not game"
check "game: the Game Mode bundle id" test "$(is_game cz.jandrly.swtoronmac.game /x/y 0)" = game
check "game: not another app" test "$(is_game com.apple.Safari /Applications/Safari.app/Contents/MacOS/Safari 1)" = "not game"
kill "$g1" "$g2" 2>/dev/null || true
rm -rf "$GT" "$SANDBOX/gm"

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
check "install: Wine's d3d9 kept ($(dd if="$sys/d3d9.dll.wine" bs=1 skip=64 count=20 2>/dev/null))" eval 'dd if="$sys/d3d9.dll.wine" bs=1 skip=64 count=20 2>/dev/null | piped -e "Wine builtin" -e "Wine placeholder"'
check "install: RetinaMode=y" reg_has 'Software\\Wine\\Mac Driver' '"RetinaMode"="y"'
WM="$SOM/engine/lib/wine/x86_64-unix"
WL="$SOM/engine/lib/wine"
WM_STOCK=$(sed -n 's/^ENGINE_WINEMAC_SHA256=//p' "$SOMSH")
WM_STOCK64=$(sed -n 's/^ENGINE_WINEMAC_PE64_SHA256=//p' "$SOMSH")
WM_STOCK32=$(sed -n 's/^ENGINE_WINEMAC_PE32_SHA256=//p' "$SOMSH")
wm_sha() { shasum -a 256 "$WM/winemac.so" | cut -d" " -f1; }
# the engine's ntdll.so is the app's build, its own kept as ntdll.so.stock
ntdll_is_apps() {
  cmp -s "$APP/Contents/Resources/wine/ntdll.so" "$WM/ntdll.so" &&
    [ "$(shasum -a 256 "$WM/ntdll.so.stock" | cut -d" " -f1)" = "$(sed -n 's/^ENGINE_NTDLL_SHA256=//p' "$SOMSH")" ]
}
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
check "install: the app's ntdll.so (msync fix), the engine's own kept as .stock" ntdll_is_apps
check "install: the Game Mode bundle gets the app's ntdll.so" cmp -s "$APP/Contents/Resources/wine/ntdll.so" "$SOM/gamemode/SWTOR.app/Contents/MacOS/ntdll.so"
check "install: manifest ntdll app" test "$(plutil -extract ntdll raw -o - "$SOM/install-manifest.json")" = app
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
check "install: env d9mt state cache in the per-user cache dir ($(envv D9MT_STATE_CACHE))" test "$(envv D9MT_STATE_CACHE)" = "$SANDBOX/usercache/d9mt/state"
CHANNEL=$(sed -n 's/^channel=//p' "$APP/Contents/Resources/app.properties")
APPV=$(sed -n 's/^version=//p' "$APP/Contents/Resources/app.properties")
if [ "$CHANNEL" = dev ]; then
  check "install: env update check off (development build)" grep -qx 'SWTOR_UPDATE_CHECK=0' "$SOM/env"
  check "install: Debug Logging on (development build)" eval 'grep -qx debug=on "$SOM/settings.conf" && grep -qx D9MT_PROFILE=1 "$SOM/env"'
  check "install: development defaults recorded" grep -qx "debug-on=$APPV" "$SOM/dev-defaults"
  check "install: d9mt flags file in the prefix (Debug Logging)" test -f "$SOM/prefix/drive_c/d9mt/flags.txt"
  check "install: the game's Wine debug channels (Debug Logging)" grep -qx 'SWTOR_GAME_WINEDEBUG=-all,warn+rawmouse,warn+threadcpu' "$SOM/env"
  check "install: d9mt-ab.sh in the app, env reads its switches (development build)" eval 'test -x "$APP/Contents/Resources/d9mt-ab.sh" && grep -qF "[ ! -f \"$SOM/d9mt-ab.env\" ] || . \"$SOM/d9mt-ab.env\"" "$SOM/env"'
else
  check "install: env update check" grep -qx 'SWTOR_UPDATE_CHECK=1' "$SOM/env"
  check "install: Debug Logging off" grep -qx 'debug=off' "$SOM/settings.conf"
  check "install: no d9mt-ab.sh, env never reads d9mt-ab.env (release build)" eval 'test ! -e "$APP/Contents/Resources/d9mt-ab.sh" && ! grep -q d9mt-ab "$SOM/env"'
fi
check "install: env feed" grep -q '^SWTOR_UPDATE_FEED="https://github.com/jdrly/swtor-on-mac/releases/latest/download/appcast.xml"$' "$SOM/env"
check "install: env notifications to a file (sandbox)" grep -q '^SWTOR_NOTIFY_LOG=' "$SOM/env"
check "install: env HUD off" grep -q '^#MTL_HUD_ENABLED=1' "$SOM/env"
check "install: env Game Mode on" grep -q '^SWTOR_GAMEMODE_APP=' "$SOM/env"
# no background helper: nothing of SWTOR on Mac runs while the app is closed (the app checks the
# hook when it opens: som.sh rehook)
check "install: no launchd job, no agent copy" test ! -e "$AGENT_PLIST" -a ! -e "$SOM/agent"
# (a real install of 0.1.3 or older may have its job loaded: it must not be the sandbox's)
check "install: no launchd job of the sandbox loaded" eval '! launchctl print "gui/$(id -u)/cz.jandrly.swtoronmac.watch" 2>/dev/null | piped -F "$SOM/"'
check "install: status says nothing of a launchd job" eval '! som status | piped -e "^watch_agent=" -e "^launch_agent="'
check "install: manifest names no launchd job" eval '! grep -q launch_agent "$SOM/install-manifest.json"'
check "install: manifest settings user" test -n "$(plutil -extract settings_user raw -o - "$SOM/install-manifest.json")"
check "play: opens the sandbox's official app ($(play_target))" test "$(play_target)" = "launch $BS_APP"
# without it the button is off: never the real app in /Applications (Launch Services' lookup
# by bundle id is only for the real system)
mv "$BS_APP" "$SANDBOX/official-app-away"
check "play: sandbox app gone, not the real one ($(play_target))" eval 'play_target | piped "^unavailable The official SWTOR app was not found"'
mv "$SANDBOX/official-app-away" "$BS_APP"

echo "== 4b. settings"
check "settings: listed" test "$(som settings | sed -n 's/^vsync=//p')" = on
som set hud on >/dev/null && check "set hud: MTL_HUD_ENABLED=1" grep -qx 'MTL_HUD_ENABLED=1' "$SOM/env"
check "hudpos: top center by default, MTL_HUD_ALIGNMENT=topcenter with the HUD on" eval '[ "$(som settings | sed -n "s/^hudpos=//p")" = topcenter ] && grep -qx MTL_HUD_ALIGNMENT=topcenter "$SOM/env"'
som set hudpos bottomleft >/dev/null && check "set hudpos bottomleft: settings.conf and env" eval 'grep -qx hudpos=bottomleft "$SOM/settings.conf" && grep -qx MTL_HUD_ALIGNMENT=bottomleft "$SOM/env" && [ "$(grep -c "^MTL_HUD_ALIGNMENT=" "$SOM/env")" = 1 ]'
check "set hudpos: a value libMTLHud doesn't know refused, the setting kept" eval '! som set hudpos middle >/dev/null 2>&1 && grep -qx hudpos=bottomleft "$SOM/settings.conf"'
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
check "settings: Frame Rate Limit off, only on battery off by default" test "$(som settings | sed -n 's/^fpslimit=//p')/$(som settings | sed -n 's/^fpsbattery=//p')" = off/off
check "settings: no limit in the env by default" eval 'grep -qx SWTOR_FPS_LIMIT=0 "$SOM/env" && grep -qx SWTOR_FPS_LIMIT_BATTERY=0 "$SOM/env"'
som set fpslimit 30 >/dev/null && check "set fpslimit 30" eval 'grep -qx SWTOR_FPS_LIMIT=30 "$SOM/env" && grep -qx fpslimit=30 "$SOM/settings.conf"'
som set fpsbattery on >/dev/null && check "set fpsbattery on" eval 'grep -qx SWTOR_FPS_LIMIT_BATTERY=1 "$SOM/env" && grep -qx fpsbattery=on "$SOM/settings.conf"'
for v in 40 45 60; do som set fpslimit $v >/dev/null; done
check "set fpslimit 40, 45, 60" grep -qx SWTOR_FPS_LIMIT=60 "$SOM/env"
check "set fpslimit: 25 refused" eval '! som set fpslimit 25 >/dev/null 2>&1 && grep -qx SWTOR_FPS_LIMIT=60 "$SOM/env"'
check "set fpslimit: empty refused" eval '! som set fpslimit "" >/dev/null 2>&1'
# (two allowed values with a space between would become a command in env)
check "set: two values in one refused (fpslimit '30 40', 'off 30'; hudpos, mousespeed), env unchanged" \
  eval '! som set fpslimit "30 40" >/dev/null 2>&1 && ! som set fpslimit "off 30" >/dev/null 2>&1 && ! som set hudpos "topleft topcenter" >/dev/null 2>&1 && ! som set mousespeed "0.5 0.75" >/dev/null 2>&1 && grep -qx SWTOR_FPS_LIMIT=60 "$SOM/env"'
som set fpslimit 45 >/dev/null
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
"$BS_APP/Contents/MacOS/test-sleep2" & sleeper=$!; sleep 0.5
check "set retina: refused while the launcher runs" eval '! som set retina on >/dev/null 2>&1'
check "play: shows the launcher while it runs ($(play_target))" test "$(play_target)" = "show launcher"
check "set hud: allowed while the launcher runs" eval 'som set hud off >/dev/null'
check "set hudpos: allowed while the launcher runs" eval 'som set hudpos bottomleft >/dev/null'
check "set hud off: no HUD lines in env, the position kept in settings.conf" eval '! grep -q "^MTL_HUD_" "$SOM/env" && grep -qx hudpos=bottomleft "$SOM/settings.conf"'
kill "$sleeper" 2>/dev/null || true; wait "$sleeper" 2>/dev/null || true
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
"$BS_APP/Contents/MacOS/test-sleep3" & sleeper=$!; sleep 0.5
check "set physkeys: refused while the launcher runs" eval '! som set physkeys off >/dev/null 2>&1'
check "set rawmouse: refused while the launcher runs" eval '! som set rawmouse off >/dev/null 2>&1'
check "set mousespeed: refused while the launcher runs" eval '! som set mousespeed 2 >/dev/null 2>&1'
check "set physkeys, rawmouse: driver unchanged while refused" wm_is app
kill "$sleeper" 2>/dev/null || true; wait "$sleeper" 2>/dev/null || true

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

echo "== 4e. the game's end through the wrapper on the engine (a probe program as swtor.exe that waits)"
if command -v x86_64-w64-mingw32-gcc >/dev/null; then
  # (no update check: it would look at the real feed; Settings' defaults come back in 6. Game
  # Mode on for the probe: 4b turned it off)
  som set updates off >/dev/null; som set gamemode on >/dev/null
  mkdir -p "$SANDBOX/probe-end"
  printf '#include <windows.h>\n#include <stdlib.h>\nint main(int c, char **v) { Sleep(atoi(v[c - 1])); return 7; }\n' >"$SANDBOX/probe-end/probe.c"
  x86_64-w64-mingw32-gcc -O2 -o "$SANDBOX/probe-end/swtor.exe" "$SANDBOX/probe-end/probe.c"
  # pe_start <ms>: the probe as the launcher starts the game (the pid of the launcher's child in pe_pid)
  pe_start() {
    "$BS_WINE/bin/wine64-preloader" "$BS_WINE/bin/wine64" "$SANDBOX/probe-end/swtor.exe" -set username PROBEACCOUNT -set lang en-us "$1" </dev/null >/dev/null 2>&1 &
    pe_pid=$!
  }
  # pe_game: "<pid> <real path>" of the probe once it runs from the Game Mode link (the
  # winetemp link, or the bundle's swtor.exe it resolves to) among the launcher child's
  # descendants; the probe's parent in pe_ppid. Nothing found: the tree, for the log.
  pe_game() {
    local i kids
    for i in $(seq 100); do
      kids=$(pgrep -P "$pe_pid" | tr '\n' ' '); for k in $kids; do kids="$kids $(pgrep -P "$k" | tr '\n' ' ')"; done
      "$HL_APP" --paths 2>/dev/null | awk -v k=" $kids " -v b="$SOM/gamemode/SWTOR.app/Contents/MacOS/swtor.exe" \
        'index(k, " " $1 " ") && (index($0, "/winetemp-") || index($0, b))' | head -1 | grep . && return 0
      sleep 0.1
    done
    ps -o pid=,ppid=,comm= -g "$(ps -o pgid= -p "$pe_pid" | tr -d ' ')" 2>/dev/null | sed 's/^/  (tree) /' >&2
    return 1
  }
  pe_start 6000
  g=$(pe_game || true); gpid=${g%% *}
  # shellcheck disable=SC2034 # (used in check's eval strings)
  gpath=${g#* }
  echo "  game: $g"
  check "game end: the game runs from the Game Mode link, as hold-launcher's child" eval '[ -n "$g" ] && [ "$(realpath "$gpath")" = "$(realpath "$SOM/gamemode/SWTOR.app/Contents/MacOS/swtor.exe")" ] && [ "$(ps -o comm= -p "$pe_pid" | sed "s|.*/||")" = hold-launcher ] && [ "$(ps -o ppid= -p "$gpid" | tr -d " ")" = "$pe_pid" ]'
  check "game end: gamemode.log names the link" eval 'tail -1 "$LOGS/gamemode.log" | piped -F -- "/wine -> $SOM/gamemode/SWTOR.app/Contents/MacOS/swtor.exe (command: swtor.exe ...)"'
  st=0; wait "$pe_pid" || st=$?
  check "game end: the launcher's child ends with the game, with its exit code (7: $st)" eval '[ "$st" = 7 ] && { [ -z "$gpid" ] || ! alive "$gpid"; }'
  check "game end: hold.log: run time, language, exit code" eval 'grep "game ended" "$LOGS/hold.log" | tail -1 | piped -E "game ended after 0:00:0[5-9] \(lang=en-us\): exit code 7\$"'
  # TERM to the launcher's child: the game gets it and ends, nothing of it stays
  pe_start 60000
  g=$(pe_game || true); gpid=${g%% *}
  kill -TERM "$pe_pid" 2>/dev/null || true
  for i in $(seq 100); do alive "$pe_pid" || break; sleep 0.1; done
  check "game end: TERM to the launcher's child ends the game, nothing left ($g)" eval '[ -n "$gpid" ] && ! alive "$pe_pid" && ! alive "$gpid" && grep "game ended" "$LOGS/hold.log" | tail -1 | piped "(lang=en-us): "'
  kill -KILL "$pe_pid" "$gpid" 2>/dev/null || true; wait "$pe_pid" 2>/dev/null || true
  check "game end: no account name in the logs" eval '! grep -rq PROBEACCOUNT "$LOGS"'
  cleanup_wine
  check "game end: no Wine left running" test -z "$(sandbox_wine)"
  # the Game Mode link the wrapper made in this user's temporary folder (the sandbox engine's)
  gm=$(sed -n 's|^game mode: \(.*/winetemp-[^/]*\)/wine -> .*|\1|p' "$LOGS/gamemode.log" 2>/dev/null | tail -1 || true)
  case "$gm" in "$(getconf DARWIN_USER_TEMP_DIR)"winetemp-*) rm -rf "$gm" ;; esac
  som set gamemode off >/dev/null
else
  echo "  (skipped: no x86_64-w64-mingw32-gcc for the probe program)"
fi

if [ "$CHANNEL" = dev ]; then
  echo "== 4d. d9mt A/B switches (d9mt-ab.sh, development builds)"
  AB="$APP/Contents/Resources/d9mt-ab.sh"
  "$AB" gpu-old vsync-off repro state-off cold=t1 >"$SANDBOX/ab1.txt" 2>&1 || bad "d9mt-ab.sh exit"
  check "ab: the switches named ($(envv SWTOR_D9MT_AB))" test "$(envv SWTOR_D9MT_AB)" = "pfv barrier-all clear-keep vsync-off repro state-off cold=t1"
  check "ab: gpu-old: D9MT_TEX_PFV=1, D9MT_PASS_BARRIER=all, D9MT_CLEAR_DISCARD=0" test "$(envv D9MT_TEX_PFV)/$(envv D9MT_PASS_BARRIER)/$(envv D9MT_CLEAR_DISCARD)" = 1/all/0
  check "ab: state-off wins over env's D9MT_STATE_CACHE" test "$(envv D9MT_STATE_CACHE)" = 0
  check "ab: DXVK_CONFIG ($(envv DXVK_CONFIG))" test "$(envv DXVK_CONFIG)" = "d3d9.presentInterval=0;d3d9.reproducibleCommandStream=True"
  check "ab: cold caches in the sandbox's Library/Caches" eval '[ "$(envv D9MT_AIR_CACHE)" = "$H/Library/Caches/SWTOR on Mac/d9mt-ab/t1/air-cache.sqlite3" ] && [ "$(envv D9MT_PSO_ARCHIVE_DIR)" = "$H/Library/Caches/SWTOR on Mac/d9mt-ab/t1/pso" ]'
  check "ab: says when they take effect" grep -q 'next time the game starts' "$SANDBOX/ab1.txt"
  som set hud on >/dev/null
  check "ab: kept when Settings rewrite env" eval '[ "$(envv D9MT_TEX_PFV)" = 1 ] && grep -qx MTL_HUD_ENABLED=1 "$SOM/env"'
  som set hud off >/dev/null
  "$AB" pfv >/dev/null
  check "ab: each call sets exactly its switches" eval '[ "$(envv D9MT_TEX_PFV)/$(envv D9MT_PASS_BARRIER)/$(envv DXVK_CONFIG)/$(envv D9MT_AIR_CACHE)" = "1/<unset>/<unset>/<unset>" ] && [ "$(envv D9MT_STATE_CACHE)" = "$SANDBOX/usercache/d9mt/state" ]'
  check "ab: an unknown switch refused, the switches kept" eval '! "$AB" turbo >/dev/null 2>&1 && [ "$(envv D9MT_TEX_PFV)" = 1 ]'
  check "ab: a bad cold name refused" eval '! "$AB" "cold=../x" >/dev/null 2>&1 && [ "$(envv SWTOR_D9MT_AB)" = pfv ]'
  check "ab: status names them" eval '"$AB" | grep "for the next game start: pfv$" >/dev/null'
  "$AB" cap=30 cap-noalign dxvkcap=40 >/dev/null
  check "ab: cap=30 cap-noalign dxvkcap=40" eval '[ "$(envv D9MT_FPS_CAP)/$(envv D9MT_FPS_CAP_ALIGN)/$(envv DXVK_CONFIG)" = "30/0/d3d9.maxFrameRate=40" ]'
  check "ab: cap=10 and cap=x refused, the switches kept" eval '! "$AB" cap=10 >/dev/null 2>&1 && ! "$AB" cap=x >/dev/null 2>&1 && [ "$(envv D9MT_FPS_CAP)" = 30 ]'
  mkdir -p "$H/Library/Caches/SWTOR on Mac/d9mt-ab/t1"
  check "ab: a cold name used before: warned" eval '"$AB" cold=t1 | grep "used before" >/dev/null'
  "$AB" reset --clean >/dev/null
  check "ab: reset --clean: no switches, no cold caches" eval '[ ! -e "$SOM/d9mt-ab.env" ] && [ ! -e "$H/Library/Caches/SWTOR on Mac/d9mt-ab" ] && [ "$(envv D9MT_TEX_PFV)" = "<unset>" ]'
  check "ab: status with none" eval '"$AB" | grep "switches: none" >/dev/null'
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
check "reinstall: Frame Rate Limit 45 only on battery stays" eval 'grep -qx SWTOR_FPS_LIMIT=45 "$SOM/env" && grep -qx SWTOR_FPS_LIMIT_BATTERY=1 "$SOM/env"'
check "reinstall: Retina stays on" reg_has 'Software\\Wine\\Mac Driver' '"RetinaMode"="y"'
check "reinstall: the app's Mac driver stays" wm_is app
check "reinstall: PhysicalKeyboard stays y" reg_has 'Software\\Wine\\AppDefaults\\swtor.exe\\Mac Driver' '"PhysicalKeyboard"="y"'
check "reinstall: RawMouseWhenCursorHidden stays y" reg_has 'Software\\Wine\\AppDefaults\\swtor.exe\\Mac Driver' '"RawMouseWhenCursorHidden"="y"'
check "reinstall: manifest winemac app" test "$(plutil -extract winemac raw -o - "$SOM/install-manifest.json")" = app
check "reinstall: the HUD position kept (bottomleft)" grep -qx hudpos=bottomleft "$SOM/settings.conf"
som set hud on >/dev/null && check "reinstall: with the HUD on, MTL_HUD_ALIGNMENT=bottomleft" grep -qx MTL_HUD_ALIGNMENT=bottomleft "$SOM/env"
som set hud off >/dev/null; som set hudpos topcenter >/dev/null
som set physkeys off >/dev/null && check "set physkeys off again: the app's driver (raw mouse-look on)" wm_is app
som set vsync on >/dev/null; som set debug off >/dev/null; som set memory auto >/dev/null
som set gamemode on >/dev/null; som set updates on >/dev/null
som set fpslimit off >/dev/null; som set fpsbattery off >/dev/null
check "settings: back to the defaults" eval '[ "$(som settings | sed -n "s/^debug=//p")" = off ] && grep -qx SWTOR_FPS_LIMIT=0 "$SOM/env"'

echo "== 6b. the wrapper's daily update check (stub engine; the game is never started)"
U="$SANDBOX/update-check"
mkdir -p "$U/bin" "$U/bin-real" "$U/engine/bin" "$U/app" "$U/prefix"
cp "$BS_WINE/bin-real/setsid-exec" "$BS_WINE/bin-real/hold-launcher" "$U/bin-real/"
# (the game, swtor.exe: its pid and parent in game-pids; game-exit: it ends with that code,
# game-signal: of that signal, game-sleep: it runs that many seconds)
cat >"$U/engine/bin/wine" <<STUB
#!/bin/bash
echo "\$@" >>"$U/wine-args"
case " \$* " in
  *swtor.exe*)
    echo "\$\$ \$PPID" >"$U/game-pids"
    [ ! -f "$U/game-closefd" ] || { exec 3>&-; exec /bin/sleep 3; }
    [ ! -f "$U/game-sleep" ] || exec /bin/sleep "\$(cat "$U/game-sleep")"
    [ ! -f "$U/game-signal" ] || kill -s "\$(cat "$U/game-signal")" \$\$
    [ ! -f "$U/game-exit" ] || exit "\$(cat "$U/game-exit")" ;;
esac
STUB
printf '#!/bin/bash\necho "$@" >>"%s/ws-args"\nexit 0\n' "$U" >"$U/engine/bin/wineserver"
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
# a leftover of this prefix's session (Wine's system processes work in C:\windows), and one
# of the engine that belongs to no session of this prefix (another prefix's: left alone)
mkdir -p "$U/prefix/drive_c/windows"
l6=$(cd "$U/prefix/drive_c/windows" && orphan "$UWT/winedevice.exe"); d6=$(orphan "$SANDBOX/fake" 60)
o6=$(orphan "$UWT/winedevice.exe"); sleep 0.3
feed 0.0.2; game
check "wrapper: ended a leftover of the prefix before starting Wine" all_gone "$l6"
check "wrapper: left the engine's process of no session of this prefix alone" alive "$o6"
kill "$o6" 2>/dev/null || true
check "wrapper: logged it" grep -q "ended leftover Wine process $l6 (winedevice.exe" "$U/logs/hold.log"
check "wrapper: left the same program elsewhere alone" alive "$d6"
kill "$d6" 2>/dev/null || true
check "update check: notification for 0.0.2" grep -q 'update available (0.0.2)' "$U/notifications.log"
check "update check: update-available for the app" test "$(cat "$U/app/update-available" 2>/dev/null)" = 0.0.2
check "update check: the game started anyway" grep -q swtor.exe "$U/wine-args"
check "wrapper: the engine's wineserver with -p10 (ends by itself; '-p 10' is forever)" grep -qx -- '-p10' "$U/ws-args"
check "wrapper: a new session's system processes from a bootstrap Wine call" grep -qxF 'reg query HKCU\Software\Wine /v SWTORonMacSession' "$U/wine-args"
check "wrapper: the session start logged" grep -q 'Wine session started (wineserver' "$U/logs/hold.log"
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
printf 'SWTOR_LOG_FILTER=.\nSWTOR_D9MT_AB="pfv cold=x"\n' >>"$U/env"; game
check "wrapper: wine.log's second line names the A/B switches" eval 'sed -n 2p "$U/logs/wine.log" | piped -x "SWTOR on Mac d9mt-ab: pfv cold=x"'
sed -i '' '/^SWTOR_D9MT_AB=/d' "$U/env"; game
check "wrapper: no A/B line without switches" eval '! grep -q "d9mt-ab" "$U/logs/wine.log"'
# Frame Rate Limit: D9MT_FPS_CAP for the game; with only on battery, by the power source at the
# game's start (a stand-in for pmset -g ps)
cat >"$U/pmset" <<'PMSET'
#!/bin/bash
[ "$*" = "-g ps" ] || exit 1
echo "Now drawing from '$(cat "$(dirname "$0")/power")'"
echo " -InternalBattery-0 (id=1234)	80%; discharging; 3:00 remaining present: true"
PMSET
chmod +x "$U/pmset"
fx() { sed -n 's/^D9MT_FPS_CAP=//p' "$U/logs/effective-env.txt"; }
printf 'SWTOR_FPS_LIMIT=30\nSWTOR_FPS_LIMIT_BATTERY=0\nSWTOR_PMSET="%s/pmset"\n' "$U" >>"$U/env"; echo "AC Power" >"$U/power"; game
check "wrapper: Frame Rate Limit 30: D9MT_FPS_CAP=30 for the game ($(fx))" test "$(fx)" = 30
check "wrapper: wine.log names the limit" grep -qx "SWTOR on Mac frame rate limit: 30 fps" "$U/logs/wine.log"
sed -i '' 's/^SWTOR_FPS_LIMIT_BATTERY=0$/SWTOR_FPS_LIMIT_BATTERY=1/' "$U/env"; game
check "wrapper: only on battery, on AC power: no cap" eval '[ -z "$(fx)" ] && grep -qx "SWTOR on Mac frame rate limit: off (only on battery: on AC power)" "$U/logs/wine.log"'
echo "Battery Power" >"$U/power"; game
check "wrapper: only on battery, on battery: D9MT_FPS_CAP=30" eval '[ "$(fx)" = 30 ] && grep -qx "SWTOR on Mac frame rate limit: 30 fps (only on battery: on battery)" "$U/logs/wine.log"'
echo "UPS Power" >"$U/power"; game
check "wrapper: only on battery, on UPS power: no cap, not taken for AC" eval '[ -z "$(fx)" ] && grep -qx "SWTOR on Mac frame rate limit: off (only on battery: battery power not confirmed)" "$U/logs/wine.log"'
rm -f "$U/pmset"; game
check "wrapper: only on battery, no answer from pmset: no cap, said so" eval '[ -z "$(fx)" ] && grep -qx "SWTOR on Mac frame rate limit: off (only on battery: battery power not confirmed)" "$U/logs/wine.log"'
sed -i '' 's/^SWTOR_FPS_LIMIT=30$/SWTOR_FPS_LIMIT=0/' "$U/env"; game
check "wrapper: limit off: no D9MT_FPS_CAP, no line" eval '[ -z "$(fx)" ] && ! grep -q "frame rate limit" "$U/logs/wine.log"'
check "wrapper: other Wine starts get no cap" eval '! grep -q D9MT_FPS_CAP "$U/logs/hold.log"'
# The game's end: one hold.log line (run time, exit code or signal, its language), the
# launcher sees the game's status, and the last starts' wine.log are kept (a start that failed,
# then one that works)
rm -f "$U"/logs/wine.log*
start_game() { LANG=de_DE.UTF-8 LC_TIME=de_DE.UTF-8 "$U/bin/wine64-preloader" "$U/bin/wine64" 'C:\swtor\retailclient\swtor.exe' \
  -set username TESTACCOUNT -set password SECRETTOKEN -set lang de-de -set torsets main,de-de >/dev/null 2>&1; }
echo 5 >"$U/game-exit"; st=0; start_game || st=$?
check "wrapper: the launcher sees the game's exit code (5: $st)" test "$st" = 5
check "wrapper: hold.log: the game's run time, language and exit code" eval 'tail -1 "$U/logs/hold.log" | piped -E "game ended after 0:00:0[0-3] \(lang=de-de torsets=main,de-de\): exit code 5\$"'
check "wrapper: the game's parent wrote that line (hold-launcher, in the wrapper's place)" eval 'grep -q "\[$(cut -d" " -f2 "$U/game-pids")\] game ended" "$U/logs/hold.log"'
check "wrapper: effective-env.txt: the locale and the game's language" eval 'grep -qx LANG=de_DE.UTF-8 "$U/logs/effective-env.txt" && grep -qx LC_TIME=de_DE.UTF-8 "$U/logs/effective-env.txt" && grep -qx "game language (from the launcher): lang=de-de torsets=main,de-de" "$U/logs/effective-env.txt"'
rm -f "$U/game-exit"; game
check "wrapper: the failed start's wine.log kept as wine.log.1, the new one in wine.log" eval 'grep -qx "SWTOR on Mac game language: lang=de-de torsets=main,de-de, LANG=de_DE.UTF-8" "$U/logs/wine.log.1" && grep -q "^SWTOR on Mac game language: not given, " "$U/logs/wine.log"'
check "wrapper: hold.log: the working start's exit code 0" eval 'tail -1 "$U/logs/hold.log" | piped -E "game ended after 0:00:0[0-3] \(not given\): exit code 0\$"'
echo USR1 >"$U/game-signal"; st=0; start_game || st=$?; rm -f "$U/game-signal"
check "wrapper: a game ended by a signal: logged, and the launcher sees it (158: $st)" eval '[ "$st" = 158 ] && tail -1 "$U/logs/hold.log" | piped -E "\): signal 30 \(SIGUSR1\)\$"'
for i in 1 2 3 4; do game; done
check "wrapper: the last 4 starts before this one kept, no more" eval '[ "$(cd "$U/logs" && ls wine.log*)" = "$(printf "wine.log\nwine.log.1\nwine.log.2\nwine.log.3\nwine.log.4")" ] && grep -q "lang=de-de" "$U/logs/wine.log.4" && ! grep -q "lang=de-de" "$U/logs/wine.log.3"'
check "wrapper: no account name or token in the logs" eval '! grep -rq -e TESTACCOUNT -e SECRETTOKEN "$U/logs"'
# TERM, INT, HUP and QUIT for the launcher's child (hold-launcher) go on to the game; killed by
# TERM, it ends and leaves nothing behind
echo 30 >"$U/game-sleep"; rm -f "$U/game-pids"
# (the wrapper itself in the background, not a function: $! is then the launcher's child)
"$U/bin/wine64-preloader" "$U/bin/wine64" 'C:\swtor\retailclient\swtor.exe' -set username TESTACCOUNT >/dev/null 2>&1 & wp=$!
for i in $(seq 50); do [ -s "$U/game-pids" ] && break; sleep 0.1; done
# shellcheck disable=SC2034 # (used in check's eval strings)
gp=$(cut -d" " -f1 "$U/game-pids" 2>/dev/null || true)
check "wrapper: the launcher's child is hold-launcher, the game its child" eval '[ "$(ps -o comm= -p "$wp" | sed "s|.*/||")" = hold-launcher ] && [ "$(cut -d" " -f2 "$U/game-pids")" = "$wp" ]'
kill -TERM "$wp"; st=0; wait "$wp" || st=$?; sleep 0.2
check "wrapper: TERM to the launcher's child ends the game, nothing is left (status $st)" eval '[ "$st" = 143 ] && [ -n "$gp" ] && ! alive "$gp" && tail -1 "$U/logs/hold.log" | piped -E "\): signal 15 \(SIGTERM\)\$"'
rm -f "$U/game-sleep"
# a pipe the game closes ends for its other side while the game still runs: hold-launcher
# keeps no copy of the caller's fds (as when the game was the launcher's child itself)
touch "$U/game-closefd"; rm -f "$U/eof"
( "$U/bin/wine64-preloader" "$U/bin/wine64" 'C:\swtor\retailclient\swtor.exe' 3>&1 >/dev/null 2>&1 | { cat >/dev/null; : >"$U/eof"; } ) & pp=$!
sleep 1.5
check "wrapper: a pipe the game closes ends while the game runs (no copy left in hold-launcher)" test -e "$U/eof"
wait "$pp" || true; rm -f "$U/game-closefd"
# an older hold-launcher (no --run-game): the game in the wrapper's process, as before, no line
cp "$U/bin-real/hold-launcher" "$U/hold-launcher.new"
printf '#!/bin/bash\nexit 1\n' >"$U/bin-real/hold-launcher"
n=$(grep -c "game ended" "$U/logs/hold.log"); echo 6 >"$U/game-exit"; st=0; start_game || st=$?; rm -f "$U/game-exit"
check "wrapper: with an older hold-launcher the game still starts, in the wrapper's place ($st)" eval '[ "$st" = 6 ] && [ "$(grep -c "game ended" "$U/logs/hold.log")" = "$n" ]'
mv -f "$U/hold-launcher.new" "$U/bin-real/hold-launcher"
check "pmset -g ps names the power source as the wrapper reads it" eval '/usr/bin/pmset -g ps | sed -n 1p | piped -E "^Now drawing from '"'"'(AC|Battery|UPS) Power'"'"'"'

echo "== 6g. the launcher not allowed in the background: som.sh btm-check, the wrapper's notification, Collect Logs (scripts/test-btm.sh, planted log text)"
check "install: env names this app's som.sh for the wrapper's btm-check" test "$(envv SWTOR_SOM_SH)" = "$SOMSH"
check "test-btm.sh passes (its output: $SANDBOX/test-btm.txt)" eval 'scripts/test-btm.sh "$APP" >"$SANDBOX/test-btm.txt" 2>&1'

echo "== 6f. session-report.sh: the lines of d9mt 6fa5df7 (a sample log)"
# (scripts/test-fixtures.sh runs the same group without the official app or Wine)
# shellcheck source=scripts/fixtures/session-report.sh
. scripts/fixtures/session-report.sh
fx_session_report "$APP/Contents/Resources/session-report.sh" "$SANDBOX/report"

echo "== 6d. the Wine session: up holding nothing of the caller's, one start at a time, leftovers of its prefix only (dummies)"
T="$SANDBOX/session-test"
TE="$T/engine/bin"
TL="$T/engine/lib/wine/x86_64-unix/wine"   # the engine's loader
HL="$APP/Contents/Resources/helpers/hold-launcher"
P1="$T/prefix" P2="$T/other"
mkdir -p "$TE" "${TL%/*}" "$T/logs" "$T/bin" "$T/bin-real" "$T/srv2" "$P1/drive_c/windows" "$P2/drive_c/windows"
cp "$SANDBOX/fake" "$TL"
cp "$SANDBOX/fake" "$TE/wineserver"
cp "$SANDBOX/fake" "$T/srv2/wineserver"
cp "$HL" "$APP/Contents/Resources/helpers/setsid-exec" "$T/bin-real/"
# The engine's wine: logs its command; the first Wine process of a session starts a "system
# process" that keeps its stdout and stderr for as long as the session runs, as Wine's
# wineboot --init does (services.exe, winedevice.exe, ...)
cat >"$TE/wine" <<WINE
#!/bin/bash
echo "\$*" >>"$T/wine-args"
srv=\$(cat "$TE/ws.pid" 2>/dev/null)
if [ -n "\$srv" ] && [ "\$(cat "$T/booted" 2>/dev/null)" != "\$srv" ]; then
  echo "\$srv" >"$T/booted"
  ( cd "$P1/drive_c/windows" && FAKE_UNTIL_PID=\$srv exec "$TL" 60 ) & echo \$! >"$T/sys.pid"
fi
WINE
chmod +x "$TE/wine"
printf 'SWTOR_ENGINE="%s"\nSWTOR_PREFIX="%s"\nSWTOR_LOG_DIR="%s"\n' "$T/engine" "$P1" "$T/logs" >"$T/env"
sed "s|@CONF@|$T/env|" "$APP/Contents/Resources/wine-wrapper.sh" >"$T/bin/wine64-preloader"; chmod +x "$T/bin/wine64-preloader"
# sd <prefix>: its session's server directory, as Wine names it
sd() { printf '/tmp/.wine-%s/server-%x-%x' "$(id -u)" "$(stat -f %d "$1")" "$(stat -f %i "$1")"; }
# a Wine call as Broadsword's mac_wine makes them: its output read to EOF (Rust's Command::output)
macwine_call() { "$T/bin/wine64-preloader" "$T/bin/wine64" reg query 'HKCU\Software\Broadsword' 2>&1 | cat >/dev/null; }
exec 7>"$T/caller-fd"   # a file of the caller's, which nothing of the session may keep open
t0=$SECONDS; macwine_call; dt=$((SECONDS - t0))
exec 7>&-
sp=$(cat "$T/sys.pid" 2>/dev/null || echo 0)
check "session: mac_wine's Wine call that started it returns at once ($dt s; it used to wait for the session's end)" test "$dt" -le 3
check "session: a bootstrap Wine call first" test "$(head -1 "$T/wine-args")" = 'reg query HKCU\Software\Wine /v SWTORonMacSession'
check "session: then mac_wine's call" test "$(sed -n 2p "$T/wine-args")" = 'reg query HKCU\Software\Broadsword'
check "session: wineserver -p10" test "$(cat "$TE/ws.args")" = -p10
check "session: the wineserver inherited no fds" test -z "$(tr -d ' \n' <"$TE/ws.fds")"
check "session: its system process has /dev/null as stdout and stderr" eval 'test "$(lsof -a -p "$sp" -d 1,2 -Fn 2>/dev/null | grep -c "^n/dev/null")" = 2'
check "session: and nothing of the caller's" eval '! lsof -p "$sp" 2>/dev/null | piped caller-fd'
macwine_call
check "session: a second Wine call joins it (no second bootstrap)" test "$(grep -c SWTORonMacSession "$T/wine-args")" = 1
check "session: one start logged" test "$(grep -c 'Wine session started' "$T/logs/hold.log")" = 1
kill "$(cat "$TE/ws.pid")"
for _ in $(seq 20); do alive "$sp" || break; sleep 0.2; done
check "session: its system process went with its server" all_gone "$sp"
macwine_call & macwine_call & wait
check "session: two Wine calls at once start it once" test "$(grep -c SWTORonMacSession "$T/wine-args")" = 2
kill "$(cat "$TE/ws.pid")"; sleep 0.5
# --reap: leftovers of this prefix's session, by their working directory in its drive_c (Wine's
# system processes) or a mapped file of its server directory (every Wine process); another
# prefix's are not touched, and nothing while the session's wineserver runs
l1=$(cd "$P1/drive_c/windows" && orphan_as 'C:\windows\system32\winedevice.exe' "$TL")
l2=$(FAKE_MAP="$(sd "$P1")/tmpmap-test" orphan_as 'C:\windows\system32\svchost.exe' "$TL")
stand_in "(mapping its server file, what --reap finds it by)" orphan_maps "$l2" "$(sd "$P1")/tmpmap-test"
o1=$(cd "$P2/drive_c/windows" && orphan_as 'C:\windows\system32\winedevice.exe' "$TL")
cp "$SANDBOX/fake" "$T/decoy-wine"
dd=$(cd "$P1/drive_c/windows" && orphan "$T/decoy-wine")
WINEPREFIX="$P2" "$T/srv2/wineserver" -p10
sleep 0.3
SWTOR_ENGINE="$T/engine" WINEPREFIX="$P1" "$HL" --reap 2>"$T/logs/reap.log"; sleep 0.3
check "reap: a leftover by its working directory" all_gone "$l1"
check "reap: a leftover by a mapped file of the server directory" all_gone "$l2"
check "reap: logged each" test "$(grep -c 'ended leftover Wine process' "$T/logs/reap.log")" = 2
check "reap: another prefix's Wine process left alone" alive "$o1"
check "reap: not the engine's program, left alone" alive "$dd"
WINEPREFIX="$P1" "$TE/wineserver" -p10; sleep 0.2
l3=$(cd "$P1/drive_c/windows" && orphan "$TL")
SWTOR_ENGINE="$T/engine" WINEPREFIX="$P1" "$HL" --reap 2>>"$T/logs/reap.log"; sleep 0.3
check "reap: nothing while the session's wineserver runs" alive "$l3"
kill "$(cat "$T/srv2/ws.pid")"; sleep 0.3
SWTOR_ENGINE="$T/engine" WINEPREFIX="$P2" "$HL" --reap 2>>"$T/logs/reap.log"; sleep 0.3
check "reap: the other prefix's leftover, for its own prefix" all_gone "$o1"
check "reap: and still not the running session's" alive "$l3"
# 0.1.1's wrappers call hold-launcher with the game's pid: nothing happens
check "hold-launcher <pid> (0.1.1's wrapper): nothing to do" eval '"$HL" $$ 2>"$T/logs/old.log" && grep -q "not holding the launcher" "$T/logs/old.log"'
check "hold-launcher: no AppKit (never an app of the launcher's)" eval '! nm -u "$HL" | piped -e NSApplication -e _objc_'
kill "$(cat "$TE/ws.pid")" "$l3" "$dd" 2>/dev/null || true
sleep 0.3
check "session test: nothing of it left" test -z "$("$HL" --paths | grep -F "$T/")"
rm -rf "$(sd "$P1")" "$(sd "$P2")"
rm -f "/tmp/.wine-$(id -u)/swtor-on-mac-$(printf '%x-%x' "$(stat -f %d "$P1")" "$(stat -f %i "$P1")").lock"

echo "== 6c. the launcher hook check when the app opens (som.sh rehook)"
rehook; check "rehook: wrapper in place, nothing to do, said so" eval '[ "$(st wrapper)" = ours ] && said "@done in place"'
check "rehook: logged" grep -q 'the wrapper is in place' "$LOGS/rehook.log"
rm -f "$BS_WINE/bin-real/setsid-exec"; rehook
check "rehook: missing helper restored" test -x "$BS_WINE/bin-real/setsid-exec"
# a helper repair is a change too: only with the lock, and not while the launcher writes
rm -f "$BS_WINE/bin-real/setsid-exec"; mkdir "$SOM/.lock"; rehook; rmdir "$SOM/.lock"
check "rehook: a missing helper left alone while an install runs, said so" eval 'said "@notice busy" && [ ! -e "$BS_WINE/bin-real/setsid-exec" ]'
touch "$BS_WINE/bin/wine64"; SETTLE=60 rehook
check "rehook: a missing helper left alone right after a change in Wine/bin, said so" eval 'said "@notice changing" && [ ! -e "$BS_WINE/bin-real/setsid-exec" ]'
rehook
check "rehook: then restored" eval 'said "@done in place" && [ -x "$BS_WINE/bin-real/setsid-exec" ]'
# an older version's launchd job, with a stand-in for launchctl (in a sandbox none is called
# otherwise): it stays, files and all, if it can't be unloaded, and goes once it can
FL="$SANDBOX/fake-launchctl"; mkdir -p "$FL"
cat >"$FL/launchctl" <<'FAKE'
#!/bin/bash
d="${0%/*}"; echo "$*" >>"$d/calls"
case "$1" in
  print) [ -e "$d/broken" ] && exit 5; [ -e "$d/loaded" ] && exit 0; exit 113 ;;
  bootout) [ -e "$d/stuck" ] && exit 5; rm -f "$d/loaded" ;;
  *) exit 2 ;;
esac
FAKE
chmod +x "$FL/launchctl"
old_job() { mkdir -p "${AGENT_PLIST%/*}" "$SOM/agent" && echo plist >"$AGENT_PLIST" && echo old >"$SOM/agent/som.sh" && : >"$FL/loaded"; }
old_job; : >"$FL/stuck"
# shellcheck disable=SC2034 # (used in check's eval strings)
m0=$(shasum -a 256 "$SOM/install-manifest.json" "$SOM/env")
SWTOR_ON_MAC_LAUNCHCTL="$FL/launchctl" som install >"$SANDBOX/agent-stuck.txt" 2>&1 && bad "install with a stuck old job went ahead"
check "old launchd job that won't stop: Install refuses before changing anything, says what to run" eval 'grep -q "^@error The launcher-update guard of an older SWTOR on Mac .* could not be stopped (loaded), so nothing was changed. Run this in Terminal, then try again: launchctl bootout gui/" "$SANDBOX/agent-stuck.txt" && [ "$(shasum -a 256 "$SOM/install-manifest.json" "$SOM/env")" = "$m0" ] && [ -f "$AGENT_PLIST" ] && [ -d "$SOM/agent" ] && [ ! -d "$SOM/.lock" ]'
SWTOR_ON_MAC_LAUNCHCTL="$FL/launchctl" som uninstall >"$SANDBOX/agent-stuck-un.txt" 2>&1 && bad "uninstall with a stuck old job went ahead"
check "old launchd job that won't stop: Uninstall refuses before changing anything" eval 'grep -q "^@error The launcher-update guard of an older SWTOR on Mac" "$SANDBOX/agent-stuck-un.txt" && [ "$(st wrapper)" = ours ] && [ -f "$SOM/install-manifest.json" ] && [ -f "$AGENT_PLIST" ] && [ -d "$SOM/agent" ]'
rm -f "$FL/stuck"; : >"$FL/broken"
SWTOR_ON_MAC_LAUNCHCTL="$FL/launchctl" som install >"$SANDBOX/agent-broken.txt" 2>&1 && bad "install with launchctl failing went ahead"
check "launchctl can't tell whether the old job runs: Install refuses, nothing changed, its files kept" eval 'grep -q "^@error SWTOR on Mac could not check whether the launcher-update guard of an older version .* still runs (unknown (launchctl print: status 5)), so nothing was changed" "$SANDBOX/agent-broken.txt" && [ "$(shasum -a 256 "$SOM/install-manifest.json" "$SOM/env")" = "$m0" ] && [ -f "$AGENT_PLIST" ] && [ -d "$SOM/agent" ]'
rm -f "$FL/broken"
SWTOR_ON_MAC_LAUNCHCTL="$FL/launchctl" som install >"$SANDBOX/agent-unload.txt" 2>&1 || bad "install with a loaded old job"
check "old launchd job loaded: unloaded, then its files removed, said so" eval 'grep -qx "bootout gui/$(id -u)/cz.jandrly.swtoronmac.watch" "$FL/calls" && [ ! -e "$FL/loaded" ] && [ ! -e "$AGENT_PLIST" ] && [ ! -e "$SOM/agent" ] && grep -q "^Removed the launcher-update guard of an older version" "$SANDBOX/agent-unload.txt"'
SWTOR_ON_MAC_LAUNCHCTL="$FL/launchctl" som install >"$SANDBOX/agent-none.txt" 2>&1 || bad "install with no old job"
# (bootouts so far: the stuck Install's, the stuck Uninstall's, the successful one's)
check "no old launchd job: nothing to unload or remove" eval '[ "$(grep -c bootout "$FL/calls")" = 3 ] && ! grep -q -e "launcher-update guard" "$SANDBOX/agent-none.txt"'

echo "== 7. a launcher update replaced the wrapper"
launcher_update() {
  cp -p "$BS_WINE/bin-real/wine64-preloader" "$BS_WINE/bin/.x" && mv -f "$BS_WINE/bin/.x" "$BS_WINE/bin/wine64-preloader"
  cp -p "$BS_WINE/bin-real/wine-preloader" "$BS_WINE/bin/.x" && mv -f "$BS_WINE/bin/.x" "$BS_WINE/bin/wine-preloader"
}
launcher_update
check "update: status replaced" test "$(st wrapper)" = replaced
check "play: off until the hook is repaired" eval 'play_target | piped "^unavailable A launcher update removed the hook"'
# a press checks the hook first, whatever the window last saw: while the launcher still writes
# it waits, after that it hooks back in and opens the official app
check "press while the launcher still writes: wait, the hook left alone" eval '[ "$(SWTOR_ON_MAC_SETTLE=60 play_check)" = "unavailable SWTOR'"'"'s launcher is changing its Wine right now. Wait until it has finished, then press Play SWTOR again." ] && [ "$(st wrapper)" = replaced ]'
check "press after the update: hooked back in, then the official app" eval '[ "$(SWTOR_ON_MAC_SETTLE=0 play_check)" = "launch $BS_APP" ] && [ "$(st wrapper)" = ours ]'
launcher_update
som install >"$SANDBOX/reinstall2.txt" 2>&1 || bad "reinstall after update"
check "update: wrapper back" test "$(st wrapper)" = ours
echo "== 7b. ...and the app's check when it opens puts it back (no background helper)"
launcher_update; n=$(notes)
mkdir "$SOM/.lock"; rehook; rmdir "$SOM/.lock"
check "rehook: leaves a running install alone, said so" eval '[ "$(st wrapper)" = replaced ] && said "@notice busy"'
SETTLE=60 rehook
check "rehook: Wine/bin changed just now (an update still writing): left alone, said so, no waiting" eval '[ "$(st wrapper)" = replaced ] && said "@notice changing"'
# between rehook's first look and its lock (staged with SWTOR_ON_MAC_TEST_BETWEEN): an install
# took the lock, or an uninstall finished; either way nothing is changed
SWTOR_ON_MAC_TEST_BETWEEN='mkdir "$SOM/.lock"' rehook; rmdir "$SOM/.lock"
check "rehook: an install that started after its first look: left alone, said so" eval '[ "$(st wrapper)" = replaced ] && said "@notice busy"'
# (the command runs inside som.sh, which has $SOM but not $SANDBOX)
SWTOR_ON_MAC_TEST_BETWEEN='mv "$SOM/install-manifest.json" "$SOM/manifest.moved"; mv "$SOM/env" "$SOM/env.moved"' rehook
check "rehook: an uninstall that finished after its first look: nothing hooked in, said so" eval 'said "@done not installed" && is_macho "$BS_WINE/bin/wine64-preloader" && is_macho "$BS_WINE/bin/wine-preloader"'
mv "$SOM/manifest.moved" "$SOM/install-manifest.json"; mv "$SOM/env.moved" "$SOM/env"
rehook
check "rehook: wrapper back, said so" eval '[ "$(st wrapper)" = ours ] && said "@done rehooked"'
check "rehook: manifest has the new preloader" test "$(plutil -extract original_preloaders_sha256.wine64-preloader raw -o - "$SOM/install-manifest.json")" = "$(shasum -a 256 "$BS_WINE/bin-real/wine64-preloader" | cut -d" " -f1)"
check "rehook: manifest still JSON" plutil -convert json -o /dev/null "$SOM/install-manifest.json"
rehook
check "rehook: idempotent" eval '[ "$(st wrapper)" = ours ] && said "@done in place"'
# a launcher half way through its update: a preloader missing
launcher_update; mv "$BS_WINE/bin/wine-preloader" "$SANDBOX/wp.tmp"; rehook
check "rehook: half-updated folder left alone, said so" eval 'said "@notice changing" && [ ! -e "$BS_WINE/bin/wine-preloader" ]'
check "rehook: half-updated folder untouched" is_macho "$BS_WINE/bin/wine64-preloader"
mv "$SANDBOX/wp.tmp" "$BS_WINE/bin/wine-preloader"; rehook
check "rehook: complete again, wrapper back" eval '[ "$(st wrapper)" = ours ] && said "@done rehooked"'
check "rehook: no system notification (the app is open and shows the hook)" test "$(notes)" = "$n"

echo "== 7c. the wrapper template copied by hand (@CONF@ not filled in: it would run Broadsword's Wine)"
raw_wrapper() { # [<env path>]: the template, or the template filled in for another env
  local b
  for b in wine-preloader wine64-preloader; do
    sed "s|@CONF@|${1:-@CONF@}|" "$APP/Contents/Resources/wine-wrapper.sh" >"$BS_WINE/bin/.x" && chmod 755 "$BS_WINE/bin/.x" &&
      mv -f "$BS_WINE/bin/.x" "$BS_WINE/bin/$b"
  done
}
raw_wrapper
check "raw wrapper: status replaced, not ours" test "$(st wrapper)" = replaced
check "raw wrapper: play off until the hook is repaired" eval 'play_target | piped "^unavailable "'
zip=$("$APP/Contents/Resources/collect-logs.sh" 2>/dev/null || true)
check "raw wrapper: Collect Logs says it is not filled in" eval 'unzip -p "$zip" "*/system-info.txt" | piped "wine64-preloader: .*NOT FILLED IN"'
rm -f "$zip"
som install >"$SANDBOX/reinstall-raw.txt" 2>&1 || bad "reinstall over a raw wrapper"
check "raw wrapper: Reinstall repairs it" eval '[ "$(st wrapper)" = ours ] && grep -qxF "CONF=\"$SOM/env\"" "$BS_WINE/bin/wine64-preloader" && grep -qxF "CONF=\"$SOM/env\"" "$BS_WINE/bin/wine-preloader"'
raw_wrapper; rehook
check "raw wrapper: the app's check repairs it" eval '[ "$(st wrapper)" = ours ] && ! grep -q "@CONF@" "$BS_WINE/bin/wine64-preloader"'
raw_wrapper "$SANDBOX/elsewhere/env"
check "wrapper of another install (another env): status replaced" test "$(st wrapper)" = replaced
rehook
check "wrapper of another install: the app's check repairs it" test "$(st wrapper)" = ours

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
# Crash reports: fakes in the sandbox's DiagnosticReports (the real ones are never read), from
# the newest: the game's, three large Wine ones (8.7 MB together), one over the 10 MB total,
# the launcher's over 3 MB, Metal's compiler for Wine and for another app, another app's, a
# .txt, then 20 small ones (only 15 fit in the 20 reports) and one 8 days old.
DIAG="$H/Library/Logs/DiagnosticReports"
mkdir -p "$DIAG"
fake_report() { # <name> <minutes ago> [<bytes> | <responsibleProc>]
  local f="$DIAG/$1"
  case "${3:-}" in
    [0-9]*) python3 -I -c 'import sys; n = int(sys.argv[2]); l = b"a line of a large crash report\n"; open(sys.argv[1], "wb").write((l * (n // len(l) + 1))[:n])' "$f" "$3" ;;
    *) printf '{"app_name":"%s","timestamp":"2026-10-18"}\n{\n  "procPath" : "%s/Library/Application Support/SWTOR on Mac/engine/bin/wine",\n  "responsibleProc" : "%s",\n  "crashReporterKey" : "SECRETKEY123",\n  "userEmail" : "player@example.com",\n  "path" : "/Users/%s/Desktop"\n}\n' \
         "${1%%-*}" "$HOME" "${3:-wine}" "$(id -un)" >"$f" ;;
  esac
  touch -t "$(date -v-"$2"M +%Y%m%d%H%M)" "$f"
}
fake_report swtor.exe-2026-10-18-120000.ips 1
for i in 1 2 3; do fake_report "wine-2026-10-18-11000$i.ips" $((1 + i)) 2900000; done
fake_report wineserver-2026-10-18-110004.ips 5 2900000
fake_report "Star Wars - The Old Republic Launcher-2026-10-18-110005.ips" 6 3500000
fake_report MTLCompilerService-2026-10-18-110006.ips 7 wine
fake_report MTLCompilerService-2026-10-18-110007.ips 8 Xcode
fake_report Safari-2026-10-18-110008.ips 9
fake_report wine-notes.txt 10
small="mac_wine-2026-10-18-100000.crash SWTORonMac-2026-10-18-100001.hang hold-launcher-2026-10-18-100002.ips"
small="$small setsid-exec-2026-10-18-100003.spin wineserver-2026-10-18-100004.diag"
for i in 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24; do small="$small wine-2026-10-18-0900$i.ips"; done
crash_want="swtor.exe-2026-10-18-120000.ips wine-2026-10-18-110001.ips wine-2026-10-18-110002.ips wine-2026-10-18-110003.ips"
crash_want="$crash_want MTLCompilerService-2026-10-18-110006.ips"
n=20; for f in $small; do
  fake_report "$f" "$n"
  [ "$n" -ge 35 ] || crash_want="$crash_want $f"
  n=$((n + 1))
done
fake_report wine-2026-10-10-090000.ips $((8 * 24 * 60))
# GPU errors: a fake unified log ($SANDBOX/bin/log, which collect-logs.sh reads in a sandbox):
# the game's and Wine's page faults, another app's (its name must stay out), Metal's full
# shader cache, the GPU driver's own lines (one naming another app and someone's folder, one
# naming Wine: only their time, sender and kind come through), and 30 other Metal errors
mkdir -p "$SANDBOX/bin"
cat >"$SANDBOX/bin/log" <<EOF
#!/bin/bash
[ "\$1 \$2 \$3" = "show --last 2h" ] || exit 2
echo "Timestamp               Ty Process[PID:TID]"
echo "2026-10-20 19:04:10.100 E  wine[4242:1a] (IOGPU) IOGPUMetalError: <private>"
echo "2026-10-20 19:04:10.101 E  wine[4242:1a] (IOGPU) IOGPUMetalError: <private>"
echo "2026-10-20 19:05:00.000 E  swtor.exe[4300:1b] (IOGPU) IOGPUMetalError: <private>"
echo "2026-10-20 19:05:01.000 E  Secret Diary[777:1c] (IOGPU) IOGPUMetalError: <private>"
echo "2026-10-20 19:06:00.000 E  wine[4242:1e] (Metal) mdb_txn_commit error: MDB_MAP_FULL: Environment mapsize limit reached"
echo "2026-10-20 19:07:00.000 Df kernel[0:2f] (AGXG14X) GPU restart, $HOME/x"
echo "2026-10-20 19:07:01.000 E  kernel[0:2f] (AGXG14X) AGX: page fault in Secret Diary[777], /Users/AnotherPerson/private-project"
echo "2026-10-20 19:07:02.000 E  kernel[0:2f] (AGX) IOGPUMetalError: timeout of wine64-preloader[4242]"
for i in \$(seq 10 39); do echo "2026-10-20 19:08:00.\$i E  wine[4242:1f] (Metal) error \$i"; done
EOF
chmod +x "$SANDBOX/bin/log"
# Metal's caches of the engine's processes in the sandbox's user cache dir: two gpuarchiver
# folders of 1 MB each, no com.apple.metal (so no archive usage index; a full one comes later)
GA="$SANDBOX/usercache/com.codeweavers.CrossOver.wineloader/com.apple.gpuarchiver"
mkdir -p "$GA/a" "$GA/b" && dd if=/dev/zero of="$GA/a/x" bs=1024 count=1024 2>/dev/null && cp "$GA/a/x" "$GA/b/x"
# The official launcher's own logs, with what they hold of the player: the account name and
# session token on the game's command line, the Mac's name (a planted one, and this Mac's own),
# its addresses, the launcher's machine and session ids, the home folder. None of it may reach
# the zip. A token in quotes, which the redaction doesn't take, is for the leak check: that log
# is left out.
LL="$H/Library/Logs/Star Wars - The Old Republic Launcher"
mkdir -p "$LL"
ACCT=PlantedAcct77 JWT=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJwbGFudGVkIn0.c2lnbmF0dXJlNzc REGTOKEN=PLANTEDREGTOKEN77
MACNAME=PlantedMac77 THISMAC=$(scutil --get ComputerName 2>/dev/null || true)
# (a model's own name, "MacBook Pro", stays: it says nothing about the player)
case "$(printf '%s' "$THISMAC" | tr '[:upper:]' '[:lower:]')" in mac|imac|macbook|"macbook air"|"macbook pro"|"mac mini"|"mac studio"|"mac pro") THISMAC="" ;; esac
cat >"$LL/host.developer.log" <<EOF
2026-10-24 16:00:40 Launcher 7.2.207 starting. Version: 7.2.207.0
Machine Name: $MACNAME
Machine Id: 0f1e2d3c-4b5a-6978-machine
Session Id: 9a8b7c6d-5e4f-session
User Home: $HOME
Intranet IP: 192.168.77.23
2026-10-24 16:00:41 Bonjour name: $THISMAC, host $MACNAME.local
2026-10-24 16:00:41 Launching game: '"C:\swtor\retailclient\swtor.exe" -set username \\$ACCT -set password $JWT -set lang de-de -set torsets main,de-de @swtor_dual.icb'
2026-10-24 16:00:41 mac_wine: reg add HKCU\Software\Broadsword --registry-token -t $REGTOKEN --session="ab cd"
2026-10-24 16:00:42 connected to 10.11.12.13:443 (en0 aa:bb:cc:dd:ee:77, fe80::1c2b:3a4d:5e6f:7a77)
2026-10-24 16:00:43 user $ACCT logged in, files in $HOME/Library/Caches and /Users/SomeoneElse77/x
2026-10-24 16:00:44 {"cmd": "mac_wine --registry-token -t \\"QUOTEDTOKEN77\\" --session=\\"PLANTEDSESSION77\\"", "arg": "--session='PLANTEDSESSION78'"}
2026-10-24 16:00:45 connected to server 192.168.77.24:443 and 2001:db8::77, fe80::1%en0; std::string, 16:00:45
Machine Name: Rex
2026-10-24 16:00:46 running on Rex (Index 3)
EOF
# (a JWT's header, cut off: the redaction doesn't know it as a token, the leak check does)
printf '2026-10-24 16:00:41 auth eyJhbGciOiJIUzI1NiJ9 (cut off)\n' >"$LL/host.cut.log"
# two game starts in SWTOR on Mac's logs: one that ended after 3 s, then one that ran
printf '2026-10-24 16:00:45 [4711] game ended after 0:00:03 (lang=de-de torsets=main,de-de): exit code 5\n2026-10-24 18:10:00 [4800] game ended after 2:05:10 (lang=en-us torsets=main,en-us): exit code 0\n' >>"$LOGS/hold.log"
echo "SWTOR on Mac game language: lang=de-de torsets=main,de-de, LANG=de_DE.UTF-8" >"$LOGS/wine.log.1"
# a self-update of the launcher that did not finish (taken out again below: it breaks the
# stand-in's seal)
mkdir -p "$BS_APP/Contents/Frameworks" && echo x >"$BS_APP/Contents/Frameworks/Launcher.dylib.solidpartial"
zip=$("$APP/Contents/Resources/collect-logs.sh" 2>"$SANDBOX/collect.err" || true)
rm -rf "$BS_APP/Contents/Frameworks"
check "logs: the stand-in official app's signature valid again" codesign --verify --strict "$BS_APP"
check "logs: zip on the sandbox Desktop" test -f "$zip" -a "${zip#"$H/Desktop/"}" != "$zip"
if [ -f "$zip" ]; then
  mkdir -p "$SANDBOX/zip" && unzip -q -o "$zip" -d "$SANDBOX/zip"
  check "logs: install.log, env, manifest, system info" test -f "$SANDBOX"/zip/*/logs/install.log -a -f "$SANDBOX"/zip/*/env -a -f "$SANDBOX"/zip/*/install-manifest.json -a -f "$SANDBOX"/zip/*/system-info.txt
  check "logs: no -set values" eval '! grep -rq -e SECRETACCOUNT -e hunter2 "$SANDBOX/zip"'
  check "logs: no user name in paths" eval '! grep -rq "/Users/$(id -un)/" "$SANDBOX/zip"'
  check "logs: system info has the Mac" grep -q '^Mac: ' "$SANDBOX"/zip/*/system-info.txt
  # shellcheck disable=SC2034 # (used in check's eval strings)
  LZ=$(echo "$SANDBOX"/zip/*/launcher-logs) ZD=$(echo "$SANDBOX"/zip/*) SI=$(echo "$SANDBOX"/zip/*/system-info.txt)
  check "logs: the launcher's logs, redacted (the version kept, the game's command line left out)" eval 'grep -q "Version: 7.2.207.0" "$LZ/host.developer.log" && grep -qx "Machine Name: NAME" "$LZ/host.developer.log" && grep -q -- "swtor.exe\" \[SWTOR on Mac: the rest of the game.s command line, from its account name on, left out\]\$" "$LZ/host.developer.log" && ! grep -q -- "-set password" "$LZ/host.developer.log"'
  check "logs: no planted account name, token, session, Mac name (also a short one), IP or id anywhere in the zip; the rest of the line kept" eval '! LC_ALL=C grep -r -i -q -F -e "$ACCT" -e "$JWT" -e "$REGTOKEN" -e "$MACNAME" -e 192.168.77.23 -e 192.168.77.24 -e 10.11.12.13 -e aa:bb:cc:dd:ee:77 -e fe80::1 -e 2001:db8 -e 0f1e2d3c -e 9a8b7c6d -e SomeoneElse77 -e QUOTEDTOKEN77 -e PLANTEDSESSION77 -e PLANTEDSESSION78 -e "$HOME" "$ZD" && ! LC_ALL=C grep -r -w -q -F Rex "$ZD" && grep -q "running on NAME (Index 3)" "$LZ/host.developer.log" && grep -q "std::string, 16:00:45" "$LZ/host.developer.log"'
  check "logs: this Mac's own name not in the zip" eval '[ ${#THISMAC} -lt 4 ] || ! LC_ALL=C grep -r -i -q -F -e "$THISMAC" "$ZD"'
  check "logs: the leak check left out only the launcher log with a cut-off token, and says so" eval '[ -e "$LZ/host.developer.log" ] && [ ! -e "$LZ/host.cut.log" ] && ! grep -rq eyJhbGciOiJIUzI1NiJ9 "$ZD" && [ "$(cat "$ZD/left-out.txt")" = "$(printf "Left out: a name, home folder or token the redaction missed was still in these files\n  launcher-logs/host.cut.log")" ]'
  check "logs: system info: the official app (version, bundle id, owner, signature, the half-written files)" eval 'grep -q "^  version .*, bundle id $(plutil -extract CFBundleIdentifier raw -o - "$BS_APP/Contents/Info.plist")\$" "$SI" && grep -q "^  owner you, group [a-z]" "$SI" && grep -q "^  signature (codesign --verify --deep --strict): " "$SI" && grep -qx "    Contents/Frameworks/Launcher.dylib.solidpartial" "$SI"'
  check "logs: system info: how each game start ended, the earlier start's wine.log in the zip" eval 'grep -q "^  .*game ended after 0:00:03 (lang=de-de torsets=main,de-de): exit code 5\$" "$SI" && grep -q "^  .*game ended after 2:05:10 (lang=en-us torsets=main,en-us): exit code 0\$" "$SI" && grep -q "lang=de-de" "$ZD/logs/wine.log.1"'
  # a name that is also the redaction's marker ("Name"): no clean file is left out for it
  printf 'Machine Name: Name\n2026-10-24 16:00:47 hello from Name\n' >"$LL/host.name.log"
  # shellcheck disable=SC2034 # (used in check's eval strings)
  zn=$("$APP/Contents/Resources/collect-logs.sh" "$SANDBOX/zip-name" 2>>"$SANDBOX/collect.err" || true)
  check "logs: a name like the marker (Name): only the cut-off token's log left out" eval 'unzip -l "$zn" | piped "launcher-logs/host.name.log" && [ "$(unzip -p "$zn" "*/left-out.txt" | sed 1d)" = "  launcher-logs/host.cut.log" ] && ! unzip -p "$zn" "*/launcher-logs/host.name.log" | piped -w Name'
  rm -f "$LL/host.name.log"
  # shellcheck disable=SC2034 # (used in check's eval strings)
  CR=$(echo "$SANDBOX"/zip/*/crash-reports) SI=$(echo "$SANDBOX"/zip/*/system-info.txt)
  check "logs: crash reports: the newest 20 of the game, Wine and the app, within 3 MB each and 10 MB together, only the sandbox's" \
    eval '[ "$(ls "$CR" | sort)" = "$(echo $crash_want | tr " " "\n" | sort)" ]'
  check "logs: crash reports redacted (home, user name, keys, e-mail)" eval '! grep -rq -e "$HOME" -e "/Users/$(id -un)/" -e SECRETKEY123 -e player@example.com "$CR" && grep -q "\"procPath\" : \"~/Library/Application Support/SWTOR on Mac/engine/bin/wine\"" "$CR/swtor.exe-2026-10-18-120000.ips"'
  check "logs: system info lists the crash reports, the newest first" eval '[ "$(sed -n "/^Crash reports/,/^\$/p" "$SI" | sed -n "2s/^  \([^ ]*\) .*/\1/p")" = swtor.exe-2026-10-18-120000.ips ] && [ "$(grep -c "^  [^l].*KB)\$" "$SI")" = 20 ]'
  check "logs: system info names the ones left out and why" eval 'grep -q "^  left out: wineserver-2026-10-18-110004.ips (over 10 MB together)" "$SI" && grep -q "^  left out: Star Wars - The Old Republic Launcher-2026-10-18-110005.ips (3500 KB, too large)" "$SI" && [ "$(grep -c "(more than 20 reports)" "$SI")" = 5 ]'
  # shellcheck disable=SC2034 # (used in check's eval strings)
  GE=$(echo "$SANDBOX"/zip/*/gpu-errors.txt)
  check "logs: GPU errors counted per game and Wine process, other apps only as a number" eval 'grep -q "^IOGPUMetalError .*: 3 in the game and Wine, 1 in other apps\$" "$GE" && grep -q "^  wine (pid 4242): 2, " "$GE" && grep -q "^  swtor.exe (pid 4300): 1, " "$GE" && ! grep -q "Secret Diary" "$GE"'
  check "logs: GPU errors: the fault lines, the last 20 other Metal errors, the full shader cache only counted" eval '[ "$(grep -c "IOGPUMetalError: <private>" "$GE")" = 3 ] && [ "$(grep -c "(Metal) error " "$GE")" = 20 ] && grep -q "(Metal) error 39\$" "$GE" && ! grep -q "(Metal) error 19\$" "$GE" && ! grep -q "mdb_txn" "$GE" && grep -q "^Metal.s archive usage index full (MDB_MAP_FULL) in the game and Wine: 1 lines; compiled shaders are still cached\$" "$GE"'
  check "logs: GPU errors: the GPU driver's lines only as time, sender and kind (no other app, no folder)" eval 'grep -qx "2026-10-20 19:07:00.000 Df kernel (AGXG14X): GPU restart" "$GE" && grep -qx "2026-10-20 19:07:01.000 E kernel (AGXG14X): GPU fault" "$GE" && grep -qx "2026-10-20 19:07:02.000 E kernel (AGX): GPU timeout, names the game or Wine" "$GE" && ! grep -q -e AnotherPerson -e private-project -e "~/x" "$GE"'
  check "logs: system info has the GPU error count" grep -q "^  IOGPUMetalError .*: 3 in the game and Wine, 1 in other apps\$" "$SI"
  check "logs: system info has the sizes of Metal's caches for the engine (2 archives of 2 MB, no com.apple.metal)" eval 'grep -qx "  com.apple.gpuarchiver: 2.0 MB, 2 entries" "$SI" && grep -qx "  com.apple.metal: none" "$SI" && grep -qx "  archive usage index (com.apple.metal/archiveUsage.db): none" "$SI" && grep -q "shared with other CrossOver-based apps, whose processes count too" "$SI"'
fi
# Metal's archive usage index: its size, and the MDB_MAP_FULL events of the window beside it,
# never "full" (the size alone doesn't say so, the one that failed on 2026-10-18 was 1,044,480
# bytes, and the events can be an older index's): the failing size with an event, a fresh 32 KiB
# index with an older event, 1 MiB without events (only "near its map's size"), and a small one
MI="$SANDBOX/usercache/com.codeweavers.CrossOver.wineloader/com.apple.metal/archiveUsage.db"
for c in 1044480:1 32768:1 1048576:0 524288:0; do
  sz=${c%%:*} lines=${c#*:}
  mkdir -p "$MI" && dd if=/dev/zero of="$MI/data.mdb" bs=1024 count=$((sz / 1024)) 2>/dev/null
  { echo '#!/bin/bash'; echo 'echo "Timestamp               Ty Process[PID:TID]"'
    [ "$lines" = 0 ] || echo 'echo "2026-10-20 19:06:00.000 E  wine[4242:1e] (Metal) mdb_txn_commit error: MDB_MAP_FULL: Environment mapsize limit reached"'
  } >"$SANDBOX/bin/log"; chmod +x "$SANDBOX/bin/log"
  mkdir -p "$SANDBOX/zip-mdb-$sz"
  zm=$("$APP/Contents/Resources/collect-logs.sh" "$SANDBOX/zip-mdb-$sz" 2>>"$SANDBOX/collect.err" || true)
  im=$(unzip -p "$zm" "*/system-info.txt" 2>/dev/null | grep "archive usage index" || true)
  case $sz in
    1044480|32768) check "logs: system info: the index's size and the MDB_MAP_FULL events side by side, its fullness now unknown ($sz bytes: $im)" test "$im" = "  archive usage index (com.apple.metal/archiveUsage.db): $sz bytes; 1 MDB_MAP_FULL events in game/Wine processes during the last 2 hours; current index fullness unknown (compiled shaders are still cached)" ;;
    1048576) check "logs: system info: 1 MiB without MDB_MAP_FULL events is not called full ($im)" test "$im" = "  archive usage index (com.apple.metal/archiveUsage.db): 1048576 bytes, near its map's size (about 1 MB; no MDB_MAP_FULL events in the last 2 hours)" ;;
    *) check "logs: system info: a small index only by its size ($im)" test "$im" = "  archive usage index (com.apple.metal/archiveUsage.db): 524288 bytes" ;;
  esac
done
rm -rf "$MI"
# a query that ignores TERM: ended with KILL after the limit and the grace time, and said so
cat >"$SANDBOX/bin/log" <<'EOF'
#!/bin/bash
trap '' TERM
echo $$ >"${0%/*}/log.pid"
echo "2026-10-20 19:04:10.100 E  wine[4242:1a] (IOGPU) IOGPUMetalError: <private>"
exec sleep 60
EOF
mkdir -p "$SANDBOX/zip-timeout"
t0=$(date +%s)
zip=$(SWTOR_ON_MAC_GPU_TIMEOUT=2 "$APP/Contents/Resources/collect-logs.sh" "$SANDBOX/zip-timeout" 2>>"$SANDBOX/collect.err" || true)
t1=$(date +%s)
check "logs: a query that ignores TERM is ended (2 s limit + 5 s grace: $((t1 - t0)) s)" test -f "$zip" -a $((t1 - t0)) -lt 30
if [ -f "$zip" ]; then
  unzip -q -o "$zip" -d "$SANDBOX/zip-timeout"
  # shellcheck disable=SC2034 # (used in check's eval strings)
  GE=$(echo "$SANDBOX"/zip-timeout/*/gpu-errors.txt)
  check "logs: GPU errors say the query ran out of time, with what came until then" eval 'grep -qx "(the query ran out of time: what came until then)" "$GE" && grep -q "^IOGPUMetalError .*: 1 in the game and Wine\$" "$GE"'
fi
check "logs: no query left running" eval '[ -s "$SANDBOX/bin/log.pid" ] && ! kill -0 "$(cat "$SANDBOX/bin/log.pid")" 2>/dev/null'
# a query that ends with status 0 on TERM: still out of time (what it wrote may be cut short)
cat >"$SANDBOX/bin/log" <<'EOF'
#!/bin/bash
trap 'kill "$s"; exit 0' TERM
echo "2026-10-20 19:04:10.100 E  wine[4242:1a] (IOGPU) IOGPUMetalError: <private>"
sleep 60 & s=$!
wait "$s"
EOF
mkdir -p "$SANDBOX/zip-term0"
zip=$(SWTOR_ON_MAC_GPU_TIMEOUT=2 "$APP/Contents/Resources/collect-logs.sh" "$SANDBOX/zip-term0" 2>>"$SANDBOX/collect.err" || true)
if [ -f "$zip" ]; then
  unzip -q -o "$zip" -d "$SANDBOX/zip-term0"
  # shellcheck disable=SC2034 # (used in check's eval strings)
  GE=$(echo "$SANDBOX"/zip-term0/*/gpu-errors.txt)
fi
check "logs: a query that ends with status 0 on TERM: GPU errors say it ran out of time" eval '[ -f "$zip" ] && grep -qx "(the query ran out of time: what came until then)" "$GE"'
# a query that ends while the watchdog hasn't started its sleep yet (an exported sleep function
# holds it for 3 s first): the watchdog is ended too, at once, and the file has no time-out note
cat >"$SANDBOX/bin/log" <<'EOF'
#!/bin/bash
echo "2026-10-20 19:04:10.100 E  wine[4242:1a] (IOGPU) IOGPUMetalError: <private>"
EOF
mkdir -p "$SANDBOX/zip-early"
t0=$(date +%s)
# shellcheck disable=SC2016 # (the function is the inner bash's)
zip=$(SWTOR_ON_MAC_GPU_TIMEOUT=47 bash -c 'sleep() { local end=$((SECONDS + 3)); while [ "$SECONDS" -lt "$end" ]; do :; done; command sleep "$@"; }
  export -f sleep; exec "$@"' - "$APP/Contents/Resources/collect-logs.sh" "$SANDBOX/zip-early" 2>>"$SANDBOX/collect.err" || true)
t1=$(date +%s)
check "logs: a query that ends before the watchdog's sleep starts ends the watchdog too ($((t1 - t0)) s, limit 47 s)" test -f "$zip" -a $((t1 - t0)) -lt 30
if [ -f "$zip" ]; then
  unzip -q -o "$zip" -d "$SANDBOX/zip-early"
  # shellcheck disable=SC2034 # (used in check's eval strings)
  GE=$(echo "$SANDBOX"/zip-early/*/gpu-errors.txt)
  check "logs: GPU errors complete, no time-out note" eval '! grep -q "ran out of time" "$GE" && grep -q "^IOGPUMetalError .*: 1 in the game and Wine\$" "$GE"'
fi
check "logs: no watchdog sleep left" eval '! pgrep -fx "sleep 47" >/dev/null'
# the Game Mode links the wrapper would have made at game start ("wine", or "swtor.exe" for a
# start.exe command)
pre="$SOM/engine/lib/wine/x86_64-unix/wine"; m=$(stat -f '%Fm' "$pre")
link="$SANDBOX/usertmp/winetemp-$(stat -f '%i-%z' "$pre")-${m%.*}-$((10#${m#*.}))/wine"
mkdir -p "$(dirname "$link")" && ln -sf "$SOM/gamemode/SWTOR.app/Contents/MacOS/swtor.exe" "$link" &&
  ln -sf "$SOM/gamemode/SWTOR.app/Contents/MacOS/swtor.exe" "${link%/*}/swtor.exe"
if [ "$CHANNEL" = dev ]; then
  "$APP/Contents/Resources/d9mt-ab.sh" pfv cold=u1 >/dev/null
  mkdir -p "$H/Library/Caches/SWTOR on Mac/d9mt-ab/u1/pso"
fi
cp "$SANDBOX/fake" "$SOM/engine/bin/test-leftover"; l8=$(orphan "$SOM/engine/bin/test-leftover"); sleep 0.3
check "before uninstall: status shows the leftover" test "$(st busy)" = leftovers
som uninstall >"$SANDBOX/uninstall.txt" 2>&1 || { tail -20 "$SANDBOX/uninstall.txt"; bad "uninstall exit"; }
check "uninstall: ended the leftover first, logged" grep -q "^Ended leftover Wine processes.*test-leftover" "$SANDBOX/uninstall.txt"
check "uninstall: the leftover is gone" all_gone "$l8"
check "uninstall: @done" grep -q '^@done' "$SANDBOX/uninstall.txt"
check "uninstall: official install identical to stock" like_stock uninstall
check "uninstall: status stock" test "$(st wrapper)" = stock
check "play: unavailable after uninstall" test "$(play_target)" = "unavailable Install SWTOR on Mac first."
for c in engine frameworks prefix gamemode env dxvk.conf install-manifest.json d9mt-ab.env; do
  check "uninstall: $c removed" test ! -e "$SOM/$c"
done
check "uninstall: SWTOR on Mac's caches removed (with d9mt-ab's)" test ! -e "$H/Library/Caches/SWTOR on Mac"
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

# The engines' downloads, verified, from the repository's cache (fetched once): the installs
# below take them from the sandbox's download cache instead of downloading them each time.
cached() { # <url> <sha256>: the path of the verified download in .cache
  local f="$REPO/.cache/$2/${1##*/}"
  if [ ! -f "$f" ]; then mkdir -p "${f%/*}"; curl -fsSL -o "$f.part" "$1" && mv "$f.part" "$f"; fi
  [ "$(shasum -a 256 "$f" | cut -d' ' -f1)" = "$2" ] && echo "$f"
}
val() { sed -n "/^$1=/{s/^$1=//p;q;}" "$2"; }   # (the first one; no pipe to head, see has)
DLC="$H/Library/Caches/SWTOR on Mac/downloads"
seed() { mkdir -p "$DLC"; cp -c "$@" "$DLC/"; }
NEW_ENGINE=$(cached "$(val ENGINE_URL "$SOMSH")" "$(val ENGINE_SHA256 "$SOMSH")")

echo "== 10b. the engine download (a local server that misbehaves; som.sh fetch-engine, no Wine)"
# What a captive portal, a proxy or a broken connection does to the 235 MB download: the
# messages, what is logged, a resume where it stopped, and the second address (GitHub's API,
# here /assets/<mode>, which answers only with Accept: application/octet-stream). (curl alone
# reports success for a page sent with HTTP 200 and for a transfer without a length that
# breaks off.)
FPORT=$((18000 + $$ % 1000))
python3 -I "$REPO/scripts/fetch-test-server.py" "$NEW_ENGINE" "$FPORT" >"$SANDBOX/fetch-server.log" 2>&1 &
fserver=$!
sleep 1
ILOG="$LOGS/install.log"
ENGINE_FILE=$(basename "$NEW_ENGINE")
# shellcheck disable=SC2034 # (used in check's eval strings)
ESHA=$(val ENGINE_SHA256 "$SOMSH")
fetch_mode() { # <mode> <API mode> <name>: som.sh fetch-engine from the local server; output in <name>.txt, its log lines in <name>.log
  local n
  n=$(wc -l <"$ILOG" 2>/dev/null || echo 0)
  SWTOR_ON_MAC_ENGINE_URL="http://127.0.0.1:$FPORT/$1/$ENGINE_FILE" SWTOR_ON_MAC_ENGINE_API_URL="http://127.0.0.1:$FPORT/assets/$2" \
    som fetch-engine >"$SANDBOX/$3.txt" 2>&1 || true
  tail -n +"$((n + 1))" "$ILOG" >"$SANDBOX/$3.log"
}
rm -rf "$DLC"
fetch_mode html html fetch-html
check "download: a web page with HTTP 200 is named as such (both addresses), nothing kept" eval 'grep -q "^@error The download of Wine engine brought a web page instead of the file" "$SANDBOX/fetch-html.txt" && [ "$(grep -c "starting with: <!DOCTYPE html>" "$SANDBOX/fetch-html.log")" = 2 ] && [ -z "$(ls -A "$DLC" 2>/dev/null)" ]'
fetch_mode dropnolen ok fetch-dropnolen
check "download: a transfer without a length that breaks off is resumed and verified (no second address)" eval 'grep -q "^@done " "$SANDBOX/fetch-dropnolen.txt" && grep -q "resuming at 33554432 of" "$SANDBOX/fetch-dropnolen.log" && grep -q " verified " "$SANDBOX/fetch-dropnolen.log" && ! grep -q "other address" "$SANDBOX/fetch-dropnolen.log"'
rm -rf "$DLC"
fetch_mode droplen ok fetch-droplen
check "download: a dropped connection is resumed (twice) and verified" eval 'grep -q "^@done " "$SANDBOX/fetch-droplen.txt" && [ "$(grep -c "resuming at" "$SANDBOX/fetch-droplen.log")" = 2 ] && [ "$(shasum -a 256 "$DLC/$ENGINE_FILE" | cut -d" " -f1)" = "$ESHA" ]'
rm -rf "$DLC"
fetch_mode norange ok fetch-norange
check "download: a server that can't resume: started over, verified" eval 'grep -q "^@done " "$SANDBOX/fetch-norange.txt" && grep -q "can.t resume; starting over" "$SANDBOX/fetch-norange.log"'
rm -rf "$DLC"
fetch_mode changed ok fetch-second
check "download: a changed file at the release URL, the right one through GitHub's API address (with Accept: application/octet-stream): verified" eval 'grep -q "^@done " "$SANDBOX/fetch-second.txt" && grep -q "sha256 [0-9a-f]\{64\} (expected $ESHA)" "$SANDBOX/fetch-second.log" && grep -q "trying GitHub.s other address" "$SANDBOX/fetch-second.log" && [ "$(shasum -a 256 "$DLC/$ENGINE_FILE" | cut -d" " -f1)" = "$ESHA" ] && ! grep -q "without Accept" "$SANDBOX/fetch-server.log"'
rm -rf "$DLC"
fetch_mode changed changed fetch-changed
check "download: changed at both addresses: the message names the size and both checksums, nothing kept" eval 'grep -q "^@error The download of Wine engine is not the expected file: got 224 MB of 224 MB, sha256 [0-9a-f]\{12\}… (expected ${ESHA:0:12}…), also through GitHub.s second address" "$SANDBOX/fetch-changed.txt" && [ "$(grep -c "sha256 [0-9a-f]\{64\} (expected $ESHA)" "$SANDBOX/fetch-changed.log")" = 2 ] && [ -z "$(ls -A "$DLC" 2>/dev/null)" ]'
fetch_mode alwaysdrop alwaysdrop fetch-stopped
check "download: a connection that keeps dropping (both addresses): stopped at 192 of 224 MB, the part kept" eval 'grep -q "^@error The download of Wine engine stopped at 192 of 224 MB" "$SANDBOX/fetch-stopped.txt" && [ "$(stat -f %z "$DLC/$ENGINE_FILE.part")" = 201326592 ]'
fetch_mode ok ok fetch-resumed
check "download: the next try continues where it stopped" eval 'grep -q "^@done " "$SANDBOX/fetch-resumed.txt" && grep -q "resuming at 201326592 of" "$SANDBOX/fetch-resumed.log" && [ ! -e "$DLC/$ENGINE_FILE.part" ]'
# (outside the sandbox: against the real home, as a dry run; what it said is kept in
# fetch-real.txt with the time, for a look if it fails)
(unset SWTOR_ON_MAC_ROOT; date '+%F %T'; SWTOR_ON_MAC_DRY_RUN=1 SWTOR_ON_MAC_ENGINE_URL=http://127.0.0.1:1/x/y "$SOMSH" fetch-engine 2>&1 && echo "status 0" || echo "status $?") >"$SANDBOX/fetch-real.txt" 2>&1 || true
check "download: only the sandbox may name another server (the real one stays on the pinned URLs)" grep -q "verified download in the cache\|download $(val ENGINE_URL "$SOMSH")" "$SANDBOX/fetch-real.txt"
kill "$fserver" 2>/dev/null || true; wait "$fserver" 2>/dev/null || true
rm -rf "$DLC"

if [ -x "$OLD_APP/Contents/Resources/som.sh" ]; then
  OLDSOM="$OLD_APP/Contents/Resources/som.sh"
  OLDV=$(sed -n 's/^version=//p' "$OLD_APP/Contents/Resources/app.properties")
  oldsom() { "$OLDSOM" "$@"; }
  oldst() { oldsom status | sed -n "s/^$1=//p"; }
  OLD_ENGINE=$(cached "$(val ENGINE_URL "$OLDSOM")" "$(val ENGINE_SHA256 "$OLDSOM")")
  OLD_FW=$(cached "$(val FW_URL "$OLDSOM")" "$(val FW_SHA256 "$OLDSOM")")
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
  old_agent=$([ -f "$AGENT_PLIST" ] && echo yes || echo no)
  t0=$SECONDS
  som install >"$SANDBOX/upgrade.txt" 2>&1 || { tail -20 "$SANDBOX/upgrade.txt"; bad "upgrade exit"; }
  echo "  (upgrade took $((SECONDS - t0)) s)"
  check "upgrade: @done" grep -q '^@done' "$SANDBOX/upgrade.txt"
  check "upgrade: $OLDV's launchd job and agent copy removed ($OLDV had one: $old_agent)" test ! -e "$AGENT_PLIST" -a ! -e "$SOM/agent"
  check "upgrade: said so" grep -q "^Upgrading SWTOR on Mac $OLDV" "$SANDBOX/upgrade.txt"
  check "upgrade: the new engine (engine_current=$(st engine_current), installed_engine=$(st installed_engine))" test "$(st engine_current)" = yes -a "$(st installed_engine)" = "$(val ENGINE_NAME "$SOMSH")"
  check "upgrade: Wine $(sbx_wine --version 2>/dev/null)" test "$(sbx_wine --version 2>/dev/null)" = wine-11.0
  check "upgrade: old engine, its libraries and the copies removed" test ! -e "$SOM/engine/bin/wine-preloader" -a ! -e "$SOM/frameworks" -a ! -e "$SOM/upgrade-backup"
  check "upgrade: manifest version $APPV, engine_id cx26" test "$(plutil -extract version raw -o - "$SOM/install-manifest.json")/$(plutil -extract engine_id raw -o - "$SOM/install-manifest.json")" = "$APPV/cx26"
  check "upgrade: settings kept" eval 'grep -qx physkeys=on "$SOM/settings.conf" && grep -qx memory=high "$SOM/settings.conf" && grep -qx retina=off "$SOM/settings.conf" && grep -qx D9MT_MEMORY_PROFILE=high "$SOM/env"'
  check "upgrade: the HUD position, new to $OLDV's settings, top center" grep -qx hudpos=topcenter "$SOM/settings.conf"
  check "upgrade: RetinaMode=n kept" reg_has 'Software\\Wine\\Mac Driver' '"RetinaMode"="n"'
  check "upgrade: PhysicalKeyboard=y kept, the app's Mac driver" eval 'reg_has "Software\\\\Wine\\\\AppDefaults\\\\swtor.exe\\\\Mac Driver" "\"PhysicalKeyboard\"=\"y\"" && cmp -s "$APP/Contents/Resources/wine/winemac.so" "$WM/winemac.so"'
  check "upgrade: raw mouse-look on (the new setting's default), the app's Mac driver, all three files" eval 'grep -qx rawmouse=on "$SOM/settings.conf" && reg_has "Software\\\\Wine\\\\AppDefaults\\\\swtor.exe\\\\Mac Driver" "\"RawMouseWhenCursorHidden\"=\"y\"" && wm_is app'
  check "upgrade: GrabPointer=n and the d3d9 override kept" eval 'reg_has "Software\\\\Wine\\\\AppDefaults\\\\swtor.exe\\\\X11 Driver" "\"GrabPointer\"=\"n\"" && reg_has "Software\\\\Wine\\\\AppDefaults\\\\swtor.exe\\\\DllOverrides" "\"d3d9\"=\"native,builtin\""'
  check "upgrade: game settings kept" grep -qx "keybinds-from-$OLDV" "$GS/upgrade-marker.ini"
  check "upgrade: d9mt's d3d9.dll" cmp -s "$APP/Contents/Resources/d9mt/d3d9.dll" "$sys/d3d9.dll"
  check "upgrade: the app's ntdll.so in the new engine" ntdll_is_apps
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
  check "downgrade: Wine $(sbx_wine --version 2>/dev/null)" eval 'sbx_wine --version 2>/dev/null | piped "^wine-9.0"'
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
  check "uninstall after upgrade: app files gone" eval '( for c in engine frameworks upgrade-backup prefix gamemode env install-manifest.json; do [ ! -e "$SOM/$c" ] || exit 1; done )'

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

# the prefix's tree with the registry files' timestamps left out (every Reinstall rewrites
# them), without the dll<hex>.tmp files wineboot -u leaves in system32 and syswow64 at every
# run (any version), and of dosdevices only c: and z: (wineboot maps the other letters to
# whatever volumes are mounted at the time); in the registry also without the values every
# wineboot -u sets anew (PendingFileRenameOperations for those .tmp files, the input devices'
# ContainerId), and without the monitors the display driver enumerates (while the Mac's display
# sleeps, wineboot adds virtual ones: Enum\DISPLAY, the monitor class and interface keys, and
# the display adapter class, which gains a link to them)
prefix_snap() {  # [prefix folder, default $SOM/prefix]
  local p="${1:-$SOM/prefix}"
  snap "$p" | grep -v -e '\.reg$' -e '\.reg|' -e '/dll[0-9a-f]*\.tmp$' -e '/dll[0-9a-f]*\.tmp|' \
    -e '^\./dosdevices/[a-y]:' -e '^\./dosdevices/z::'
  for r in system.reg user.reg userdef.reg; do
    printf '%s ' "$r"; sed -e 's/^\(\[.*\]\) [0-9]*$/\1/' -e '/^#time=/d' -e '/^"PendingFileRenameOperations"=/d' -e '/^"ContainerId"=/d' "$p/$r" |
      awk 'index($0, "[") == 1 { skip = index($0, "\\\\Enum\\\\DISPLAY\\\\") || index($0, "{E6F07B5F-EE97-4A90-B076-33F57BF4EAA7}") ||
             index($0, "\\\\Class\\\\{4D36E96E-E325-11CE-BFC1-08002BE10318}") || index($0, "\\\\Class\\\\{4D36E968-E325-11CE-BFC1-08002BE10318}") } !skip' |
      shasum -a 256 | cut -d' ' -f1
  done
}
# prefix_changes <prefix_snap file> [prefix folder] [file for the snapshot now]: what differs in
# the prefix now, one a line: a file's path (its metadata or its checksum), a registry file's
# name (system.reg ...), and any other differing snapshot line as it is, so that nothing drops
# out unnoticed. (Sections 15 and 16 keep both snapshots, so the comparison can be repeated.)
prefix_changes() {
  { prefix_snap "${2:-}" | tee "${3:-/dev/null}" | diff "$1" - || true; } | awk '
    !/^[<>] / { next }
    { l = substr($0, 3) }
    l ~ /^\.\/[^|]*\|/ { sub(/\|.*/, "", l); print l; next }
    l ~ /^[0-9a-f]+  \.\// && index(l, "  ") == 65 { print substr(l, 67); next }
    l ~ /^(system|user|userdef)\.reg [0-9a-f]+$/ { sub(/ .*/, "", l); print l; next }
    { print l }' | sort -u
}
# engine_same <name>: the engine's files that differ from $SANDBOX/<name>-engine (listed in
# $SANDBOX/<name>-engine.diff) are the same code, but for ntdll.so and ntdll.so.stock (the
# app's build and the engine's own, checked by ntdll_is_apps) and the app's Mac driver where
# this version's build differs from the other's (winemac.so and its PE sides: then exactly this
# app's files). A Developer ID build of either side signs its Mach-O files, winemetal.so and
# winemac.so, with signatures of their own: those may differ, their code not.
engine_same() {
  local f
  while IFS= read -r f; do
    case "$f" in ""|./lib/wine/x86_64-unix/ntdll.so|./lib/wine/x86_64-unix/ntdll.so.stock) continue ;; esac
    case "$f" in
      ./lib/wine/x86_64-unix/winemac.so)
        ! cmp -s "$APP/Contents/Resources/wine/winemac.so" "$SOM/engine/$f" || continue ;;
      ./lib/wine/x86_64-windows/winemac.drv|./lib/wine/i386-windows/winemac.drv)
        ! cmp -s "$APP/Contents/Resources/wine/${f#./lib/wine/}" "$SOM/engine/$f" || continue ;;
    esac
    macho_same "$SANDBOX/$1-engine/$f" "$SOM/engine/$f" || { echo "  differs: $f"; return 1; }
  done <"$SANDBOX/$1-engine.diff"
}

# prefix_changes itself (sections 15 and 16 allow only d3d9.dll to change): on a fake prefix,
# a changed registry value, another file next to d3d9.dll and a new file are each reported,
# a changed d3d9.dll alone gives just its path
# piped itself (every check that greps a pipe uses it; a name of its own, as has is the session
# report's): under pipefail, a match early in a long
# output passes, and the same check negated fails (with grep -q both go wrong: the writer dies
# of SIGPIPE once grep has stopped reading)
echo "== 14a. a check on a pipe reads all of it"
check "pipes: a match early in a long output passes" eval 'seq 1 200000 | piped -x 1'
check "pipes: the same check negated fails" eval '! ( ! seq 1 200000 | piped -x 1 )'
check "pipes: no check greps a pipe with grep -q" eval '! cat "$REPO/scripts/test-sandbox.sh" "$REPO"/scripts/fixtures/*.sh | grep -n "| *grep -q" | grep -v "^[0-9]*: *#" | piped .'
check "pipes: no helper is defined twice (a later one would replace the earlier for every check after it)" \
  eval '[ -z "$(grep -h -o -E "^ *[A-Za-z_][A-Za-z0-9_]*\\(\\) *\\{" "$REPO/scripts/test-sandbox.sh" "$REPO"/scripts/fixtures/*.sh | sed -E "s/^ *//; s/\\(\\).*//" | sort | uniq -d)" ]'
# (eval_exits: the lines whose eval string calls exit outside a subshell; check runs eval in this
# shell, so the exit would end the suite with no FAIL line and no counts)
# shellcheck source=scripts/fixtures/eval-exit.sh
. scripts/fixtures/eval-exit.sh
check "checks: no eval string calls exit outside a subshell (it would end the suite uncounted)" test -z "$(eval_exits "$REPO/scripts/test-sandbox.sh" "$REPO"/scripts/fixtures/*.sh)"

echo "== 14b. the prefix comparison sees what changed"
FP="$SANDBOX/fake-prefix"; rm -rf "$FP"; mkdir -p "$FP/drive_c/windows/system32"
echo dll >"$FP/drive_c/windows/system32/d3d9.dll"; echo x >"$FP/drive_c/windows/system32/d3d9Xdll"
for r in system.reg user.reg userdef.reg; do printf 'WINE REGISTRY Version 2\n\n[Software\\\\Test] 1\n"A"="1"\n' >"$FP/$r"; done
prefix_snap "$FP" >"$SANDBOX/fake-prefix.txt"
echo dll2 >"$FP/drive_c/windows/system32/d3d9.dll"
check "prefix comparison: a changed d3d9.dll alone gives just its path" eval '[ "$(prefix_changes "$SANDBOX/fake-prefix.txt" "$FP")" = ./drive_c/windows/system32/d3d9.dll ]'
sed -i '' 's/"A"="1"/"A"="2"/' "$FP/user.reg"
check "prefix comparison: a changed registry value is reported (user.reg)" eval 'prefix_changes "$SANDBOX/fake-prefix.txt" "$FP" | piped -x user.reg'
sed -i '' 's/"A"="2"/"A"="1"/' "$FP/user.reg"; echo y >"$FP/drive_c/windows/system32/d3d9Xdll"
check "prefix comparison: a file named like d3d9.dll is reported and not taken for it" eval '[ -n "$(prefix_changes "$SANDBOX/fake-prefix.txt" "$FP" | grep -F -v -x -- ./drive_c/windows/system32/d3d9.dll)" ]'
echo new >"$FP/drive_c/new.txt"
check "prefix comparison: a new file is reported" eval 'prefix_changes "$SANDBOX/fake-prefix.txt" "$FP" | piped -x ./drive_c/new.txt'
rm -rf "$FP"

# engine_same itself (sections 15 and 16): on fake engines, this app's Mac driver over another
# build passes; a Mac driver that isn't this app's, or another changed file, fails
echo "== 14c. the engine comparison allows only this app's Mac driver"
FE="$SANDBOX/fake-som"; rm -rf "$FE" "$SANDBOX/fake-engine"
mkdir -p "$FE/engine/lib/wine/x86_64-unix" "$SANDBOX/fake-engine/lib/wine/x86_64-unix"
cp "$APP/Contents/Resources/wine/winemac.so" "$FE/engine/lib/wine/x86_64-unix/winemac.so"
echo older >"$SANDBOX/fake-engine/lib/wine/x86_64-unix/winemac.so"
echo ./lib/wine/x86_64-unix/winemac.so >"$SANDBOX/fake-engine.diff"
check "engine comparison: this app's Mac driver over another build passes" eval '( SOM="$FE"; engine_same fake )'
echo other >"$FE/engine/lib/wine/x86_64-unix/winemac.so"
check "engine comparison: a Mac driver that isn't this app's fails" eval '! ( SOM="$FE"; engine_same fake ) >/dev/null 2>&1'
cp "$APP/Contents/Resources/wine/winemac.so" "$FE/engine/lib/wine/x86_64-unix/winemac.so"
echo a >"$SANDBOX/fake-engine/lib/wine/x86_64-unix/other.so"; echo b >"$FE/engine/lib/wine/x86_64-unix/other.so"
echo ./lib/wine/x86_64-unix/other.so >>"$SANDBOX/fake-engine.diff"
check "engine comparison: another changed file fails" eval '! ( SOM="$FE"; engine_same fake ) >/dev/null 2>&1'
rm -rf "$FE" "$SANDBOX/fake-engine" "$SANDBOX/fake-engine.diff"

if [ -x "$PREV_APP/Contents/Resources/som.sh" ]; then
  PREVSOM="$PREV_APP/Contents/Resources/som.sh"
  PREVV=$(sed -n 's/^version=//p' "$PREV_APP/Contents/Resources/app.properties")
  prevsom() { "$PREVSOM" "$@"; }
  echo "== 15. from $PREVV (the same engine) and back: what this version's Reinstall changes"
  [ "$(val ENGINE_SHA256 "$PREVSOM")" = "$(val ENGINE_SHA256 "$SOMSH")" ] || bad "$PREVV has another engine than this version"
  rm -rf "$SOM" "$H/Library/Caches/SWTOR on Mac"
  seed "$NEW_ENGINE"
  prevsom install >"$SANDBOX/prev-install.txt" 2>&1 || { tail -20 "$SANDBOX/prev-install.txt"; bad "$PREVV install exit"; }
  # Debug Logging on as a development build has it, and another setting; then a Reinstall of
  # $PREVV, so both sides of the comparison come from a Reinstall
  prevsom set debug on >/dev/null; prevsom set memory high >/dev/null
  prevsom install >"$SANDBOX/prev-reinstall.txt" 2>&1 || { tail -20 "$SANDBOX/prev-reinstall.txt"; bad "$PREVV reinstall exit"; }
  check "$PREVV: installed" eval 'grep -q "^@done" "$SANDBOX/prev-reinstall.txt" && [ "$(plutil -extract version raw -o - "$SOM/install-manifest.json")" = "$PREVV" ]'
  # env without comments, versions, the lines this version adds and (development builds) the
  # update check, which they turn off. The longer version goes first: one that extends the other
  # (0.1.5.1 over 0.1.5) would otherwise be left as V.1
  envnorm() {
    local a=$PREVV b=$APPV
    [ ${#a} -ge ${#b} ] || { a=$APPV; b=$PREVV; }
    sed -e "s/$a/V/g; s/$b/V/g" -e 's/^SWTOR_D9MT=.*/SWTOR_D9MT=H/' "$1" |
      { if [ "$CHANNEL" = dev ]; then sed 's/^SWTOR_UPDATE_CHECK=.*/SWTOR_UPDATE_CHECK=X/'; else cat; fi; } |
      grep -v -e '^#' -e '^$' -e '^D9MT_STATE_CACHE=' -e 'd9mt-ab\.env' -e '^SWTOR_FPS_LIMIT=' -e '^SWTOR_FPS_LIMIT_BATTERY=' \
        -e '^SWTOR_SOM_SH=' -e '^SWTOR_ON_MAC_ROOT='
  }
  echo SWTOR_ON_MAC_VERSION=0.1.5 >"$SANDBOX/envnorm-short"; echo SWTOR_ON_MAC_VERSION=0.1.5.1 >"$SANDBOX/envnorm-long"
  check "env comparison: 0.1.5 and 0.1.5.1 come out alike, either one as this version" eval '( PREVV=0.1.5 APPV=0.1.5.1; diff <(envnorm "$SANDBOX/envnorm-short") <(envnorm "$SANDBOX/envnorm-long") ) >/dev/null && ( PREVV=0.1.5.1 APPV=0.1.5; diff <(envnorm "$SANDBOX/envnorm-short") <(envnorm "$SANDBOX/envnorm-long") ) >/dev/null'
  rm -f "$SANDBOX/envnorm-short" "$SANDBOX/envnorm-long"
  prefix_snap >"$SANDBOX/prev-prefix.txt"
  snap "$SOM/engine" >"$SANDBOX/prev-engine.txt"
  rm -rf "$SANDBOX/prev-engine" && cp -c -R -p "$SOM/engine" "$SANDBOX/prev-engine"
  cp "$SOM/env" "$SANDBOX/prev-env"; cp "$SOM/settings.conf" "$SANDBOX/prev-settings.conf"; cp "$SOM/dxvk.conf" "$SANDBOX/prev-dxvk.conf"
  check "$PREVV: env has the D9MT_STATE_CACHE line exactly if $PREVV writes it" eval '[ "$(grep -c "^D9MT_STATE_CACHE=" "$SOM/env")" = "$(grep -q "^D9MT_STATE_CACHE=" "$PREVSOM" && echo 1 || echo 0)" ]'
  check "$PREVV: no Wine left running" test -z "$(sandbox_wine)"

  # (0.1.3 and older set up a launchd job for launcher updates; in a sandbox it is written, never loaded)
  prev_agent=$([ -f "$AGENT_PLIST" ] && [ -d "$SOM/agent" ] && echo yes || echo no)
  som install >"$SANDBOX/prev-upgrade.txt" 2>&1 || { tail -20 "$SANDBOX/prev-upgrade.txt"; bad "install over $PREVV exit"; }
  check "over $PREVV: its launchd job and agent copy removed, said so ($PREVV had one: $prev_agent)" eval '[ ! -e "$AGENT_PLIST" ] && [ ! -e "$SOM/agent" ] && { grep -q "^Removed the launcher-update guard of an older version" "$SANDBOX/prev-upgrade.txt" || [ "$prev_agent" = no ]; }'
  check "over $PREVV: @done, manifest $APPV" eval 'grep -q "^@done" "$SANDBOX/prev-upgrade.txt" && [ "$(plutil -extract version raw -o - "$SOM/install-manifest.json")" = "$APPV" ]'
  check "over $PREVV: the engine already in place, no download" eval 'grep -q "is already in place" "$SANDBOX/prev-upgrade.txt" && ! grep -q "Unpacking the Wine engine" "$SANDBOX/prev-upgrade.txt"'
  prefix_changes "$SANDBOX/prev-prefix.txt" "" "$SANDBOX/prev-prefix-after.txt" >"$SANDBOX/prev-prefix.diff"
  # (a previous release with this version's d3d9.dll, 0.1.2 for 0.1.3: nothing changes)
  check "over $PREVV: in the prefix at most d9mt's d3d9.dll changed ($(tr '\n' ' ' <"$SANDBOX/prev-prefix.diff"))" eval '[ -z "$(grep -F -v -x -- ./drive_c/windows/system32/d3d9.dll "$SANDBOX/prev-prefix.diff")" ]'
  check "over $PREVV: the prefix's d3d9.dll is this app's" cmp -s "$APP/Contents/Resources/d9mt/d3d9.dll" "$sys/d3d9.dll"
  { snap "$SOM/engine" | diff "$SANDBOX/prev-engine.txt" - || true; } | sed -n 's/^[<>] \(\.[^|]*\)|.*/\1/p; s/^[<>] [0-9a-f]\{64\}  \(.*\)/\1/p' | sort -u >"$SANDBOX/prev-engine.diff"
  check "over $PREVV: the engine unchanged, signatures aside, but ntdll.so and this app's Mac driver ($(tr '\n' ' ' <"$SANDBOX/prev-engine.diff"))" engine_same prev
  # ($PREVV's ntdll.so: the engine's own, or, from 0.1.2 on, the app's build in its own signature)
  check "over $PREVV: the app's ntdll.so, the engine's own kept as .stock" eval 'ntdll_is_apps && { cmp -s "$SANDBOX/prev-engine/lib/wine/x86_64-unix/ntdll.so" "$WM/ntdll.so.stock" || macho_same "$SANDBOX/prev-engine/lib/wine/x86_64-unix/ntdll.so" "$WM/ntdll.so"; }'
  check "over $PREVV: winemetal.so is $PREVV's code (LC_UUID $(dwarfdump -u "$WM/winemetal.so" | awk '{ print $2 }'))" eval 'macho_same "$PREV_APP/Contents/Resources/d9mt/winemetal.so" "$WM/winemetal.so" && [ "$(dwarfdump -u "$WM/winemetal.so" | awk "{ print \$2 }")" = "$(dwarfdump -u "$PREV_APP/Contents/Resources/d9mt/winemetal.so" | awk "{ print \$2 }")" ]'
  check "over $PREVV: winemetal.dll byte for byte $PREVV's" cmp -s "$PREV_APP/Contents/Resources/d9mt/winemetal.dll" "$SOM/engine/lib/wine/x86_64-windows/winemetal.dll"
  # (settings.conf: this version writes every setting it knows, so the ones $PREVV does not know,
  # hudpos, fpslimit and fpsbattery, come in with their defaults)
  check "over $PREVV: settings.conf unchanged but for settings new since $PREVV (hudpos=topcenter, fpslimit=off, fpsbattery=off), dxvk.conf unchanged" eval 'diff <(grep -v -e "^hudpos=" -e "^fpslimit=" -e "^fpsbattery=" "$SANDBOX/prev-settings.conf") <(grep -v -e "^hudpos=" -e "^fpslimit=" -e "^fpsbattery=" "$SOM/settings.conf") >/dev/null && grep -qx hudpos=topcenter "$SOM/settings.conf" && grep -qx fpslimit=off "$SOM/settings.conf" && grep -qx fpsbattery=off "$SOM/settings.conf" && cmp -s "$SANDBOX/prev-dxvk.conf" "$SOM/dxvk.conf"'
  check "over $PREVV: env: the state cache line, the Frame Rate Limit lines (off), the btm-check lines$([ "$CHANNEL" = dev ] && echo " and the A/B include") added, the rest as before (versions aside)" eval 'diff <(envnorm "$SANDBOX/prev-env") <(envnorm "$SOM/env") >"$SANDBOX/prev-env.diff" && [ "$(envv D9MT_STATE_CACHE)" = "$SANDBOX/usercache/d9mt/state" ] && [ "$(envv SWTOR_FPS_LIMIT)/$(envv SWTOR_FPS_LIMIT_BATTERY)" = 0/0 ] && [ "$(envv SWTOR_SOM_SH)/$(envv SWTOR_ON_MAC_ROOT)" = "$SOMSH/$SANDBOX" ]'
  check "over $PREVV: no Wine left running" test -z "$(sandbox_wine)"
  [ "$CHANNEL" != dev ] || "$APP/Contents/Resources/d9mt-ab.sh" pfv >/dev/null

  prevsom install >"$SANDBOX/prev-downgrade.txt" 2>&1 || { tail -20 "$SANDBOX/prev-downgrade.txt"; bad "$PREVV over this version exit"; }
  check "back to $PREVV: @done, manifest $PREVV" eval 'grep -q "^@done" "$SANDBOX/prev-downgrade.txt" && [ "$(plutil -extract version raw -o - "$SOM/install-manifest.json")" = "$PREVV" ]'
  check "back to $PREVV: the prefix as $PREVV left it" eval 'prefix_snap | diff "$SANDBOX/prev-prefix.txt" - >"$SANDBOX/prev-back.diff"'
  # ($PREVV without an ntdll.so of its own, 0.1.0/0.1.1, checks it only when it unpacks the
  # engine: it keeps this version's, the fix; one with its own, 0.1.2 on, puts its own back)
  if [ -f "$PREV_APP/Contents/Resources/wine/ntdll.so" ]; then
    check "back to $PREVV: the engine as $PREVV left it (its own ntdll.so back)" eval 'snap "$SOM/engine" | diff -q "$SANDBOX/prev-engine.txt" - >/dev/null && cmp -s "$PREV_APP/Contents/Resources/wine/ntdll.so" "$WM/ntdll.so"'
  else
    check "back to $PREVV: the engine as $PREVV left it, but ntdll.so this version's (and the engine's own as .stock)" eval '[ "$({ snap "$SOM/engine" | diff "$SANDBOX/prev-engine.txt" - || true; } | sed -n "s/^[<>] \(\.[^|]*\)|.*/\1/p; s/^[<>] [0-9a-f]\{64\}  \(.*\)/\1/p" | sort -u | tr "\n" " ")" = "./lib/wine/x86_64-unix/ntdll.so ./lib/wine/x86_64-unix/ntdll.so.stock " ] && ntdll_is_apps'
  fi
  out=$(sbx_wine cmd /c echo prev-ok 2>/dev/null | tr -d '\r' || true)
  check "back to $PREVV: Wine runs a program with it (cmd: $out)" test "$out" = prev-ok
  check "back to $PREVV: env byte for byte as $PREVV wrote it (no state cache line, no A/B switches)" eval 'cmp -s "$SANDBOX/prev-env" "$SOM/env" && [ "$(envv D9MT_TEX_PFV)" = "<unset>" ]'
  out=$("$BS_WINE/bin/wine64-preloader" "$BS_WINE/bin/wine64" --version 2>&1 || true)
  check "back to $PREVV: the wrapper runs the engine ($out)" test "$out" = wine-11.0
  cleanup_wine
  check "back to $PREVV: no Wine left running" test -z "$(sandbox_wine)"
  som uninstall >"$SANDBOX/uninstall4.txt" 2>&1 || { tail -20 "$SANDBOX/uninstall4.txt"; bad "uninstall of $PREVV"; }
  check "this version's uninstall of $PREVV: official install identical to stock" like_stock uninstall4
  check "this version's uninstall of $PREVV: app files gone (d9mt-ab.env too)" eval '( for c in engine prefix gamemode env install-manifest.json d9mt-ab.env; do [ ! -e "$SOM/$c" ] || exit 1; done )'
else
  echo "== 15 skipped: no previous release at $PREV_APP (PREV_APP)"
fi

DEVV=$(sed -n 's/^version=//p' "$DEV_APP/Contents/Resources/app.properties" 2>/dev/null || true)
if [ "$CHANNEL" = release ] && [ -x "$DEV_APP/Contents/Resources/som.sh" ] && [ -x "$DEV_APP/Contents/Resources/d9mt-ab.sh" ]; then
  devsom() { "$DEV_APP/Contents/Resources/som.sh" "$@"; }
  COLD="$H/Library/Caches/SWTOR on Mac/d9mt-ab"
  echo "== 16. from the development build $DEVV to this release: its leftovers go, the rest stays"
  rm -rf "$SOM" "$H/Library/Caches/SWTOR on Mac"
  seed "$NEW_ENGINE"
  devsom install >"$SANDBOX/dev-install.txt" 2>&1 || { tail -20 "$SANDBOX/dev-install.txt"; bad "$DEVV install exit"; }
  devsom set memory high >/dev/null
  # a Reinstall of $DEVV, so both sides of the prefix comparison come from a Reinstall
  devsom install >"$SANDBOX/dev-reinstall0.txt" 2>&1 || { tail -20 "$SANDBOX/dev-reinstall0.txt"; bad "$DEVV reinstall exit"; }
  "$DEV_APP/Contents/Resources/d9mt-ab.sh" pfv state-off cold=d1 >/dev/null
  mkdir -p "$COLD/d1/pso" && echo cold >"$COLD/d1/air-cache.sqlite3"
  check "$DEVV: installed, Debug Logging on, the A/B switches read ($(envv SWTOR_D9MT_AB))" eval 'grep -q "^@done" "$SANDBOX/dev-install.txt" && grep -qx debug=on "$SOM/settings.conf" && [ "$(envv D9MT_TEX_PFV)/$(envv D9MT_STATE_CACHE)" = 1/0 ] && [ -f "$SOM/d9mt-ab.env" ]'
  check "$DEVV: no Wine left running" test -z "$(sandbox_wine)"
  prefix_snap >"$SANDBOX/dev-prefix.txt"
  snap "$SOM/engine" >"$SANDBOX/dev-engine.txt"
  rm -rf "$SANDBOX/dev-engine" && cp -c -R -p "$SOM/engine" "$SANDBOX/dev-engine"
  cp "$SOM/settings.conf" "$SANDBOX/dev-settings.conf"

  dev_agent=$([ -f "$AGENT_PLIST" ] && [ -d "$SOM/agent" ] && echo yes || echo no)
  som install >"$SANDBOX/dev-upgrade.txt" 2>&1 || { tail -20 "$SANDBOX/dev-upgrade.txt"; bad "install over $DEVV exit"; }
  check "over $DEVV: its launchd job and agent copy removed ($DEVV had one: $dev_agent)" test ! -e "$AGENT_PLIST" -a ! -e "$SOM/agent"
  check "over $DEVV: @done, manifest $APPV" eval 'grep -q "^@done" "$SANDBOX/dev-upgrade.txt" && [ "$(plutil -extract version raw -o - "$SOM/install-manifest.json")" = "$APPV" ]'
  check "over $DEVV: the A/B switches removed, said so" eval '[ ! -e "$SOM/d9mt-ab.env" ] && grep -q "^Removed a development build.s d9mt A/B switches" "$SANDBOX/dev-upgrade.txt"'
  check "over $DEVV: the cold test caches removed, said so" eval '[ ! -e "$COLD" ] && grep -q "^Removed a development build.s d9mt test caches" "$SANDBOX/dev-upgrade.txt"'
  check "over $DEVV: env as a release writes it (no A/B include, state cache on, update check on)" eval '! grep -q d9mt-ab "$SOM/env" && [ "$(envv D9MT_TEX_PFV)/$(envv SWTOR_D9MT_AB)" = "<unset>/<unset>" ] && [ "$(envv D9MT_STATE_CACHE)" = "$SANDBOX/usercache/d9mt/state" ] && grep -qx SWTOR_UPDATE_CHECK=1 "$SOM/env"'
  # (this version writes every setting it knows: the Frame Rate Limit's two, which $DEVV does
  # not know, come in with their defaults; everything else byte for byte)
  check "over $DEVV: settings kept (Debug Logging on as the user left it, memory high), only fpslimit=off and fpsbattery=off added" \
    eval '! grep -q -e "^fpslimit=" -e "^fpsbattery=" "$SANDBOX/dev-settings.conf" && [ "$(grep -c "^fpslimit=" "$SOM/settings.conf")" = 1 ] && grep -qx fpslimit=off "$SOM/settings.conf" && [ "$(grep -c "^fpsbattery=" "$SOM/settings.conf")" = 1 ] && grep -qx fpsbattery=off "$SOM/settings.conf" && cmp -s "$SANDBOX/dev-settings.conf" <(perl -ne "print unless /^(fpslimit|fpsbattery)=/" "$SOM/settings.conf")'
  prefix_changes "$SANDBOX/dev-prefix.txt" "" "$SANDBOX/dev-prefix-after.txt" >"$SANDBOX/dev-prefix.diff"
  # (a development build with this version's d3d9.dll, 0.1.2-dev.3 for 0.1.2 and 0.1.3: nothing
  # changes; with an older pin, d3d9.dll)
  check "over $DEVV: in the prefix at most d9mt's d3d9.dll changed ($(tr '\n' ' ' <"$SANDBOX/dev-prefix.diff"))" eval '[ -z "$(grep -F -v -x -- ./drive_c/windows/system32/d3d9.dll "$SANDBOX/dev-prefix.diff")" ]'
  check "over $DEVV: the prefix's d3d9.dll is this app's" cmp -s "$APP/Contents/Resources/d9mt/d3d9.dll" "$sys/d3d9.dll"
  { snap "$SOM/engine" | diff "$SANDBOX/dev-engine.txt" - || true; } | sed -n 's/^[<>] \(\.[^|]*\)|.*/\1/p; s/^[<>] [0-9a-f]\{64\}  \(.*\)/\1/p' | sort -u >"$SANDBOX/dev-engine.diff"
  check "over $DEVV: the engine unchanged, signatures aside, but ntdll.so and this app's Mac driver ($(tr '\n' ' ' <"$SANDBOX/dev-engine.diff"))" engine_same dev
  # ($DEVV's ntdll.so: the engine's own, or, from 0.1.2-dev.1 on, the app's build in its own
  # signature, its code ours)
  check "over $DEVV: the app's ntdll.so, the engine's own kept as .stock ($DEVV had $(cmp -s "$SANDBOX/dev-engine/lib/wine/x86_64-unix/ntdll.so" "$WM/ntdll.so.stock" && echo "the engine's" || echo "the app's build"))" eval 'ntdll_is_apps && { cmp -s "$SANDBOX/dev-engine/lib/wine/x86_64-unix/ntdll.so" "$WM/ntdll.so.stock" || macho_same "$SANDBOX/dev-engine/lib/wine/x86_64-unix/ntdll.so" "$WM/ntdll.so"; }'
  check "over $DEVV: no Wine left running" test -z "$(sandbox_wine)"
  som install >"$SANDBOX/dev-reinstall.txt" 2>&1 || bad "reinstall after $DEVV exit"
  check "over $DEVV: a Reinstall after it has nothing more to remove" eval 'grep -q "^@done" "$SANDBOX/dev-reinstall.txt" && ! grep -q -e "^Removed a development build" -e "^Removed the launcher-update guard" "$SANDBOX/dev-reinstall.txt"'
  som uninstall >"$SANDBOX/uninstall5.txt" 2>&1 || { tail -20 "$SANDBOX/uninstall5.txt"; bad "uninstall after $DEVV"; }
  check "uninstall after $DEVV: official install identical to stock" like_stock uninstall5
  check "uninstall after $DEVV: app files and caches gone" eval '( for c in engine prefix gamemode env settings.conf install-manifest.json d9mt-ab.env dev-defaults; do [ ! -e "$SOM/$c" ] || exit 1; done ) && [ ! -e "$H/Library/Caches/SWTOR on Mac" ]'
elif [ "$CHANNEL" = release ]; then
  echo "== 16 skipped: no development build at $DEV_APP (DEV_APP)"
fi

cleanup_wine
check "end: no Wine process of the sandbox" test -z "$(sandbox_wine)"
echo "== $pass passed, $fail failed"
if [ -n "$JOB_SANDBOX" ]; then job_sandbox_end 0
elif [ -z "${KEEP:-}" ] && [ "$fail" = 0 ]; then chmod -R u+w "$SANDBOX" 2>/dev/null || true; rm -rf "$SANDBOX"; fi
[ "$fail" = 0 ]
