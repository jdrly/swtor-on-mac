# shellcheck shell=bash
# The suite's detached stand-ins (scripts/test-sandbox.sh, sourced), and fixture group orphan-as,
# which checks orphan and orphan_as (scripts/test-fixtures.sh only: helpers of the suite, not the
# app). The helpers write the started pid to $SANDBOX/orphan.pid.

# orphan_ready <pid> <command> [tries]: waits until the process runs <command>, as ps shows its
# command line (after the exec, and for orphan_as after the rewrite), or has ended; tries of 0.1 s
# (default 50). A check right after the start sometimes still sees the shell before the exec
# (#68). False, with a note on stderr, if it still runs something else.
orphan_ready() {
  local c n=${3:-50}
  while :; do
    c=$(ps -ww -o command= -p "$1" 2>/dev/null) || return 1
    [ "$c" != "$2" ] || return 0
    n=$((n - 1))
    [ "$n" -gt 0 ] || { echo "orphan_ready: pid $1 runs '$c', not '$2'" >&2; return 1; }
    sleep 0.1
  done
}
# orphan_maps <pid> <file> [tries]: waits until the process maps <file>, as a Wine process maps
# its server's files; tries of 0.1 s (default 50). False, with a note on stderr, if it doesn't
orphan_maps() {
  local f
  f="$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")"
  for _ in $(seq 1 "${3:-50}"); do
    lsof -a -p "$1" -Fn 2>/dev/null | piped -x -F "n$f" && return 0
    sleep 0.1
  done
  echo "orphan_maps: pid $1 doesn't map $f" >&2
  return 1
}

# orphan <program> [args]: runs it detached (parent launchd, like Wine's orphans); prints its pid
# once it runs the program
orphan() {
  ( "$@" </dev/null >/dev/null 2>&1 & echo $! >"$SANDBOX/orphan.pid" )
  orphan_ready "$(cat "$SANDBOX/orphan.pid")" "$*" || true
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
  orphan_ready "$(cat "$SANDBOX/orphan.pid")" "$a0${*:+ $*}" || true
  cat "$SANDBOX/orphan.pid"
}

# fx_orphan_as <folder>: orphan_as through a bash stand-in on the PATH that records its arguments,
# then runs the real bash, and through a slow one (0.5 s before its exec); orphan; orphan_ready
# and orphan_maps on their own. The probe's argv[0] is no game path, so tools/swtor-running.sh
# never matches it while the group runs.
fx_orphan_as() {
  local SANDBOX=$1 a0='C:\fixture\orphan-as\probe.exe' pid cmd
  mkdir -p "$SANDBOX/bin" "$SANDBOX/slow"
  printf '#!/bin/bash\nprintf "%%s\\n" "$@" >>%q\nexec /bin/bash "$@"\n' "$SANDBOX/bash-argv.txt" >"$SANDBOX/bin/bash"
  printf '#!/bin/bash\nsleep 0.5\nexec /bin/bash "$@"\n' >"$SANDBOX/slow/bash"
  chmod 755 "$SANDBOX/bin/bash" "$SANDBOX/slow/bash"
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
  # orphan_ready itself: a late exec, a program that never comes, an ended process
  /bin/bash -c 'sleep 0.5; exec "$0" "$@"' /bin/sleep 30 </dev/null >/dev/null 2>&1 & pid=$!
  check "orphan_ready: waits for a late exec" eval 'orphan_ready "$pid" "/bin/sleep 30" && [ "$(ps -ww -o command= -p "$pid")" = "/bin/sleep 30" ]'
  check "orphan_ready: false for another program (after its tries)" eval '! orphan_ready "$pid" "/bin/sleep 31" 3 2>/dev/null'
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
  check "orphan_ready: false at once for an ended process" eval '! orphan_ready "$pid" "/bin/sleep 30" 2>/dev/null'
  # orphan_maps: a process that maps a file of its own after 0.5 s (perl's mmap is a module, so
  # the mapping is a sleep's executable: its text is mapped from the moment it runs)
  /bin/bash -c 'sleep 0.5; exec /bin/sleep 30' </dev/null >/dev/null 2>&1 & pid=$!
  check "orphan_maps: waits until the process maps the file" orphan_maps "$pid" /bin/sleep
  check "orphan_maps: false for a file it doesn't map" eval '! orphan_maps "$pid" /bin/cat 3 2>/dev/null'
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
  # the program's environment, as it writes it itself (ps -E shows none on current macOS)
  PATH="$SANDBOX/bin:$PATH" orphan_as "$a0" /bin/bash -c 'env >"$1.new" && mv "$1.new" "$1"' env "$SANDBOX/env.txt" >/dev/null
  for _ in $(seq 1 50); do [ -s "$SANDBOX/env.txt" ] && break; sleep 0.1; done
  check "orphan-as: the program's environment was written" grep -q '^PATH=' "$SANDBOX/env.txt"
  check "orphan-as: ORPHAN_ARGV0 doesn't reach the program" eval '! grep -q "^ORPHAN_ARGV0=" "$SANDBOX/env.txt"'
}
