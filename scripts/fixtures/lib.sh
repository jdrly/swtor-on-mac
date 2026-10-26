# shellcheck shell=bash
# The checks' helpers, shared by scripts/test-sandbox.sh and scripts/test-fixtures.sh (sourced;
# the fixture groups in this folder use them). The caller sets the counters, pass=0 fail=0.

ok() { echo "  ok   $*"; pass=$((pass + 1)); }
bad() { echo "  FAIL $*"; fail=$((fail + 1)); }
check() { local what=$1; shift; if "$@"; then ok "$what"; else bad "$what"; fi; }
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
