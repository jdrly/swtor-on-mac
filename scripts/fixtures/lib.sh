# shellcheck shell=bash
# The checks' helpers, shared by scripts/test-sandbox.sh and scripts/test-fixtures.sh (sourced;
# the fixture groups in this folder use them). The caller sets the counters, pass=0 fail=0.

ok() { echo "  ok   $*"; pass=$((pass + 1)); }
bad() { echo "  FAIL $*"; fail=$((fail + 1)); }
check() {
  local what=$1 why; shift
  if why=$(stand_in_not_ready); then bad "$what (not checked: $why)"; return; fi
  if "$@"; then ok "$what"; else bad "$what"; fi
}
# stand_in_not_ready: the stand-ins that scripts/fixtures/orphan.sh noted as not ready
# ($SANDBOX/orphan.notready, "<pid> <what>" lines), and false if there are none. A check would
# test nothing without its stand-in, so every check fails while one still runs something else,
# and the first one after it ended; then its note goes
stand_in_not_ready() {
  local f=${SANDBOX:-}/orphan.notready pid what s keep="" why=""
  [ -s "$f" ] || return 1
  while read -r pid what; do
    why="$why${why:+; }$what"
    s=$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -z "$s" ] || [ "${s#Z}" != "$s" ] || keep="$keep$pid $what
"
  done <"$f"
  printf '%s' "$keep" >"$f"
  echo "$why"
}
# piped <grep options and patterns>: grep -q for a pipe's end. It reads all of its input: grep -q
# would stop at the first match, and the writer then dies of SIGPIPE, which under pipefail fails
# the pipe (a check that should pass fails at random) or, after a !, passes it (one that should
# fail passes)
piped() { grep "$@" >/dev/null; }
# under_job_runner: a job runner runs this, and owns the run's outputs (it sets JOB_ID and JOB_ROOT)
under_job_runner() { [ -n "${JOB_ID:-}" ] && [ -n "${JOB_ROOT:-}" ]; }
# owned_path <variable> <its value>: under a job runner, the run's output folder must be named (no
# default) and lie in an existing folder outside the temporary ones (/tmp, /var/folders, $TMPDIR),
# which no job owns and which nothing keeps; else a message and false
owned_path() {
  local name=$1 p=$2 d real t
  [ -n "$p" ] || { echo "$name: under a job runner, name a folder in the job's run directory (no default)" >&2; return 1; }
  case $(basename "$p") in .|..|/) echo "$name=$p: name a folder of its own" >&2; return 1 ;; esac
  d=$(dirname "$p")
  [ -d "$d" ] || { echo "$name=$p: $d does not exist" >&2; return 1; }
  real="$(cd "$d" && pwd -P)/$(basename "$p")"
  [ ! -d "$p" ] || real=$(cd "$p" && pwd -P)
  for t in /private/tmp /private/var/folders "$(cd "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P)"; do
    case $t in ''|/) continue ;; esac
    case "$real/" in "$t"/*)
      echo "$name=$p is in a temporary folder ($t): under a job runner, name a folder in the job's run directory" >&2
      return 1 ;;
    esac
  done
}
