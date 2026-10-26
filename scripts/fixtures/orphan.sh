# shellcheck shell=bash
# The suite's detached stand-ins (scripts/test-sandbox.sh, sourced), and fixture group orphan-as,
# which checks orphan and orphan_as (scripts/test-fixtures.sh only: helpers of the suite, not the
# app). The helpers write the started pid to $SANDBOX/orphan.pid. A stand-in that isn't ready is
# noted in $SANDBOX/orphan.notready, which fails the checks after it (lib.sh's check).

# orphan_ready <pid> <command> [tries]: waits until the process runs <command>, as ps shows its
# command line (after the exec, and for orphan_as after the rewrite); tries of 0.1 s (default
# $ORPHAN_TRIES, else 50). A check right after the start sometimes still sees the shell before
# the exec (#68). False if it ended first, or still runs something else.
orphan_ready() {
  local c n=${3:-${ORPHAN_TRIES:-50}}
  while :; do
    c=$(ps -ww -o command= -p "$1" 2>/dev/null) || return 1
    [ "$c" != "$2" ] || return 0
    n=$((n - 1))
    [ "$n" -gt 0 ] || return 1
    sleep 0.1
  done
}
# orphan_maps <pid> <file> [tries]: waits until the process maps <file> (an mmap, lsof's "txt"
# records: an open descriptor alone isn't one), as a Wine process maps its server's files and
# --reap finds it by them; tries as orphan_ready's. False if it ended first, or doesn't.
orphan_maps() {
  local f
  f="$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")"
  for _ in $(seq 1 "${3:-${ORPHAN_TRIES:-50}}"); do
    ps -o pid= -p "$1" >/dev/null 2>&1 || return 1
    lsof -a -p "$1" -Ffn 2>/dev/null | awk -v n="n$f" '/^f/ {fd = $0} $0 == n && fd == "ftxt" {m = 1} END {exit !m}' && return 0
    sleep 0.1
  done
  return 1
}
# stand_in <what> <wait command...>: runs a readiness wait; if it fails, notes the stand-in (the
# wait's first argument is its pid) as not ready, on stderr and in $SANDBOX/orphan.notready
stand_in() {
  local what=$1; shift
  "$@" && return 0
  echo "$2 $what not ready" >>"$SANDBOX/orphan.notready"
  echo "stand-in: pid $2 $what not ready" >&2
  return 0
}

# orphan <program> [args]: runs it detached (parent launchd, like Wine's orphans); prints its pid
# once it runs the program (ORPHAN_ENDS=1: a program that ends by itself, not waited for)
orphan() {
  ( "$@" </dev/null >/dev/null 2>&1 & echo $! >"$SANDBOX/orphan.pid" )
  [ -n "${ORPHAN_ENDS:-}" ] || stand_in "($*)" orphan_ready "$(cat "$SANDBOX/orphan.pid")" "$*"
  cat "$SANDBOX/orphan.pid"
}
# orphan_as <argv0> <program> [args]: like orphan, with argv[0] rewritten as Wine 11 does (ps
# then shows C:\windows\...). argv[0] reaches the shell that rewrites it in the environment
# (ORPHAN_ARGV0, unset before the exec), never on its command line: a game path there would make
# that shell a game for tools/swtor-running.sh and the job runner until its exec, and the runner
# would stop the job (tools/job/runner/README.md, "Command lines that name the game")
orphan_as() {
  local a0=$1
  ( ORPHAN_ARGV0=$1; export ORPHAN_ARGV0; shift
    bash -c 'a=$ORPHAN_ARGV0; unset ORPHAN_ARGV0; exec -a "$a" "$@"' orphan_as "$@" </dev/null >/dev/null 2>&1 &
    echo $! >"$SANDBOX/orphan.pid" )
  shift 2
  [ -n "${ORPHAN_ENDS:-}" ] || stand_in "($a0${*:+ $*})" orphan_ready "$(cat "$SANDBOX/orphan.pid")" "$a0${*:+ $*}"
  cat "$SANDBOX/orphan.pid"
}

# fx_orphan_as <folder>: orphan_as through a bash stand-in on the PATH that records its arguments,
# then runs the real bash; through a slow one (0.5 s before its exec), and one that never runs the
# program; orphan, also of a program that ends at once; the checks after a stand-in that isn't
# ready; orphan_ready and orphan_maps on their own. The probe's argv[0] is no game path, so
# tools/swtor-running.sh never matches it while the group runs.
fx_orphan_as() {
  local SANDBOX=$1 a0='C:\fixture\orphan-as\probe.exe' pid cmd t o1 o2 o3 o4 o5
  mkdir -p "$SANDBOX/bin" "$SANDBOX/slow" "$SANDBOX/never"
  printf '#!/bin/bash\nprintf "%%s\\n" "$@" >>%q\nexec /bin/bash "$@"\n' "$SANDBOX/bash-argv.txt" >"$SANDBOX/bin/bash"
  printf '#!/bin/bash\nsleep 0.5\nexec /bin/bash "$@"\n' >"$SANDBOX/slow/bash"
  printf '#!/bin/bash\nexec /bin/sleep 20\n' >"$SANDBOX/never/bash"
  chmod 755 "$SANDBOX/bin/bash" "$SANDBOX/slow/bash" "$SANDBOX/never/bash"
  pid=$(PATH="$SANDBOX/bin:$PATH" orphan_as "$a0" /bin/sleep 30)
  cmd=$(ps -ww -o command= -p "$pid" 2>/dev/null || true)
  check "orphan-as: returns once the program runs with argv[0] rewritten ($cmd)" test "$cmd" = "$a0 30"
  check "orphan-as: the rewriting shell ran (the stand-in bash recorded it)" test -s "$SANDBOX/bash-argv.txt"
  check "orphan-as: argv[0] never on the shell's command line" eval '! grep -F -x -q -- "$a0" "$SANDBOX/bash-argv.txt"'
  kill "$pid" 2>/dev/null || true
  pid=$(PATH="$SANDBOX/slow:$PATH" orphan_as "$a0" /bin/sleep 30)
  cmd=$(ps -ww -o command= -p "$pid" 2>/dev/null || true)
  check "orphan-as: a slow rewriting shell too ($cmd)" test "$cmd" = "$a0 30"
  kill "$pid" 2>/dev/null || true
  pid=$(orphan /bin/sleep 30)
  cmd=$(ps -ww -o command= -p "$pid" 2>/dev/null || true)
  check "orphan: returns once the program runs ($cmd)" test "$cmd" = "/bin/sleep 30"
  kill "$pid" 2>/dev/null || true
  # a stand-in that never runs its program, and one that ended at once: the checks after them
  # fail without testing (in subshells here, so the group's counts stay), while it runs something
  # else and once after it ended; then checks run again
  pid=$(ORPHAN_TRIES=5 PATH="$SANDBOX/never:$PATH" orphan_as "$a0" /bin/sleep 30 2>/dev/null)
  o1=$(check "probe" true)
  kill "$pid" 2>/dev/null || true
  for _ in $(seq 1 50); do ps -o pid= -p "$pid" >/dev/null || break; sleep 0.1; done
  o2=$(check "probe" true)
  o3=$(check "probe" true)
  pid=$(orphan /usr/bin/false 2>/dev/null)
  o4=$(check "probe" true)
  o5=$(check "probe" true)
  check "stand-in never ready: the check after it fails, not run (${o1# })" eval '[ "${o1#  FAIL probe (not checked: }" != "$o1" ]'
  check "stand-in never ready: still failed once after it ended (${o2# })" eval '[ "${o2#  FAIL probe (not checked: }" != "$o2" ]'
  check "stand-in never ready: then checks run again ($o3)" test "$o3" = "  ok   probe"
  check "stand-in ended at once: the check after it fails, then they run ($o4 / $o5)" \
    eval '[ "${o4#  FAIL probe (not checked: }" != "$o4" ] && [ "$o5" = "  ok   probe" ]'
  # orphan_ready itself: a late exec, a program that never comes, an ended process
  /bin/bash -c 'sleep 0.5; exec "$0" "$@"' /bin/sleep 30 </dev/null >/dev/null 2>&1 & pid=$!
  check "orphan_ready: waits for a late exec" eval 'orphan_ready "$pid" "/bin/sleep 30" && [ "$(ps -ww -o command= -p "$pid")" = "/bin/sleep 30" ]'
  check "orphan_ready: false for another program (after its tries)" eval '! orphan_ready "$pid" "/bin/sleep 31" 3'
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
  check "orphan_ready: false at once for an ended process" eval '! orphan_ready "$pid" "/bin/sleep 30"'
  # orphan_maps: a mapping (a sleep's executable, mapped from the moment it runs after 0.5 s), an
  # open descriptor that is no mapping (fd 3 on /bin/cat, kept through the exec), an ended process
  /bin/bash -c 'sleep 0.5; exec 3</bin/cat; exec /bin/sleep 30' </dev/null >/dev/null 2>&1 & pid=$!
  check "orphan_maps: waits until the process maps the file" orphan_maps "$pid" /bin/sleep
  check "orphan_maps: an open descriptor alone isn't a mapping" eval '! orphan_maps "$pid" /bin/cat 3'
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
  # shellcheck disable=SC2034 # (used in check's eval strings)
  t=$SECONDS
  check "orphan_maps: false at once for an ended process" eval '! orphan_maps "$pid" /bin/sleep && [ $((SECONDS - t)) -le 1 ]'
  # the program's environment, as it writes it itself (ps -E shows none on current macOS); it
  # ends by itself, so it isn't waited for
  ORPHAN_ENDS=1 PATH="$SANDBOX/bin:$PATH" orphan_as "$a0" /bin/bash -c 'env >"$1.new" && mv "$1.new" "$1"' env "$SANDBOX/env.txt" >/dev/null
  for _ in $(seq 1 50); do [ -s "$SANDBOX/env.txt" ] && break; sleep 0.1; done
  check "orphan-as: the program's environment was written" grep -q '^PATH=' "$SANDBOX/env.txt"
  check "orphan-as: ORPHAN_ARGV0 doesn't reach the program" eval '! grep -q "^ORPHAN_ARGV0=" "$SANDBOX/env.txt"'
}
