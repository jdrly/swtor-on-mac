#!/bin/bash
# Fixture checks without the official SWTOR app or Wine: the app's packaged scripts on planted
# inputs, in a root of their own with an empty home and an empty sandbox (SWTOR_ON_MAC_ROOT), no
# official app and no engine. The groups are in scripts/fixtures/<group>.sh; scripts/test-sandbox.sh
# runs the same groups in its sections, with no copy of their checks.
#
#   scripts/test-fixtures.sh [path/to/SWTOR on Mac.app] [group...]
#
# Groups (default: all): session-report (the suite's section 6f: the packaged session-report.sh on
# a sample log); job-sandbox (the suite's end under a job runner, on planted sandboxes, with copies
# that fail; only here, so the suite's counts stay); orphan-as (the suite's orphan_as: argv[0]
# rewritten, and never on the rewriting shell's command line; only here, too); is-launcher (the
# suite's section 2b call by executable isn't the running launcher to a process scan); eval-exit
# (no check's eval string calls exit outside a subshell, the suite's section 14a; and its "app
# files gone" checks on a planted file count a FAIL and go on); bridge (the suite's section 14d:
# sections 15 and 16 accept a changed d9mt bridge only with the pin, as this app's); self (this
# script's own promises, each on a run of its own: a wrong session report fails the checks, a
# check that starts Wine or the app fails the run, the cleanup removes the root and nothing beside
# it).
# Env: FIXTURE_ROOT (default: a new folder in $TMPDIR; it must not exist yet; under a job runner
#      it must be named, outside the temporary folders), KEEP=1 (leave the root for a look; it
#      also stays when a check failed)
# wine, wine64, wineserver, wineboot, open and osascript on the PATH are stand-ins: a check that
# starts one fails the run, which names the command. A program started by its full path isn't
# caught that way; in the empty root there is no engine and no official app to start.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$PWD"
# ok, bad, check, piped and the job runner's rules (owned_path)
# shellcheck source=scripts/fixtures/lib.sh
. scripts/fixtures/lib.sh
pass=0 fail=0
# shellcheck source=scripts/fixtures/session-report.sh
. scripts/fixtures/session-report.sh
# shellcheck source=scripts/fixtures/job-sandbox.sh
. scripts/fixtures/job-sandbox.sh
# shellcheck source=scripts/fixtures/orphan.sh
. scripts/fixtures/orphan.sh
# shellcheck source=scripts/fixtures/launcher.sh
. scripts/fixtures/launcher.sh
# shellcheck source=scripts/fixtures/eval-exit.sh
. scripts/fixtures/eval-exit.sh
# shellcheck source=scripts/fixtures/bridge.sh
. scripts/fixtures/bridge.sh
# shellcheck source=scripts/fixtures/self.sh
. scripts/fixtures/self.sh
APP="dist/SWTOR on Mac.app"
if [ $# -gt 0 ] && [ -d "$1" ]; then APP=$1; shift; fi
APP="$(cd "$APP" 2>/dev/null && pwd)" || { echo "no app at $APP; run ./build.sh" >&2; exit 1; }
[ -x "$APP/Contents/Resources/session-report.sh" ] || { echo "no session-report.sh in $APP" >&2; exit 1; }
FX_ALL="session-report job-sandbox orphan-as is-launcher eval-exit bridge self"
FX_GROUPS="${*:-$FX_ALL}"
for g in $FX_GROUPS; do
  case " $FX_ALL " in *" $g "*) ;; *) echo "unknown group $g (groups: $FX_ALL)" >&2; exit 2 ;; esac
done

if under_job_runner; then owned_path FIXTURE_ROOT "${FIXTURE_ROOT:-}" || exit 64; fi
if [ -n "${FIXTURE_ROOT:-}" ]; then
  # a folder of its own: the cleanup removes it, so never one that is already there
  [ ! -e "$FIXTURE_ROOT" ] && [ ! -L "$FIXTURE_ROOT" ] || { echo "FIXTURE_ROOT=$FIXTURE_ROOT exists: name a new folder" >&2; exit 2; }
  mkdir "$FIXTURE_ROOT"
  ROOT="$(cd "$FIXTURE_ROOT" && pwd -P)"
else
  ROOT="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/som-fixtures.XXXXXX")" && pwd -P)"
fi
echo "== fixtures in $ROOT ($APP)"
# the empty world: a home, a sandbox root, nothing installed, and the stand-ins first on the PATH
mkdir -p "$ROOT/home" "$ROOT/root" "$ROOT/stand-ins"
for p in wine wine64 wineserver wineboot open osascript; do
  printf '#!/bin/bash\necho "%s $*" >>%q\necho "test-fixtures: a check started %s (a stand-in, nothing ran): $*" >&2\nexit 127\n' \
    "$p" "$ROOT/started.txt" "$p" >"$ROOT/stand-ins/$p"
  chmod 755 "$ROOT/stand-ins/$p"
done
export HOME="$ROOT/home" SWTOR_ON_MAC_ROOT="$ROOT/root" PATH="$ROOT/stand-ins:$PATH"
unset SWTOR_ON_MAC_DRY_RUN SWTOR_ON_MAC_FORCE

for g in $FX_GROUPS; do
  echo "== $g"
  case $g in
    session-report) fx_session_report "$APP/Contents/Resources/session-report.sh" "$ROOT/session-report" ;;
    job-sandbox) fx_job_sandbox "$ROOT/job-sandbox" ;;
    orphan-as) fx_orphan_as "$ROOT/orphan-as" ;;
    is-launcher) fx_is_launcher ;;
    eval-exit) fx_eval_exit "$REPO/scripts/test-sandbox.sh" "$ROOT/eval-exit" ;;
    bridge) fx_bridge "$APP" "$ROOT/bridge" ;;
    self) fx_self "$REPO/scripts/test-fixtures.sh" "$APP" "$ROOT/self" ;;
  esac
done

echo "== the end"
[ ! -s "$ROOT/started.txt" ] || sed 's/^/  started: /' "$ROOT/started.txt"
check "end: no check started Wine or the app" test ! -s "$ROOT/started.txt"
echo "== $pass passed, $fail failed"
if [ -z "${KEEP:-}" ] && [ "$fail" = 0 ]; then chmod -R u+w "$ROOT"; rm -rf "$ROOT"; else echo "(the root stays: $ROOT)"; fi
[ "$fail" = 0 ]
