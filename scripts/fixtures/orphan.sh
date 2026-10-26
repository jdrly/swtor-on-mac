# shellcheck shell=bash
# The suite's detached stand-ins (scripts/test-sandbox.sh, sourced), and fixture group orphan-as,
# which checks orphan_as (scripts/test-fixtures.sh only: a helper of the suite, not the app). The
# helpers write the started pid to $SANDBOX/orphan.pid.

# orphan <program> [args]: runs it detached (parent launchd, like Wine's orphans); prints its pid
orphan() { ( "$@" </dev/null >/dev/null 2>&1 & echo $! >"$SANDBOX/orphan.pid" ); cat "$SANDBOX/orphan.pid"; }
# orphan_as <argv0> <program> [args]: like orphan, with argv[0] rewritten as Wine 11 does (ps
# then shows C:\windows\...). argv[0] reaches the shell that rewrites it in the environment
# (ORPHAN_ARGV0, unset before the exec), never on its command line: a game path there would make
# that shell a game for tools/swtor-running.sh and the job runner until its exec, and the runner
# would stop the job (tools/job/runner/README.md, "Command lines that name the game")
orphan_as() {
  ( ORPHAN_ARGV0=$1; export ORPHAN_ARGV0; shift
    bash -c 'a=$ORPHAN_ARGV0; unset ORPHAN_ARGV0; exec -a "$a" "$@"' orphan_as "$@" </dev/null >/dev/null 2>&1 &
    echo $! >"$SANDBOX/orphan.pid" )
  cat "$SANDBOX/orphan.pid"
}

# fx_orphan_as <folder>: orphan_as through a bash stand-in on the PATH that records its arguments,
# then runs the real bash. The probe's argv[0] is no game path, so tools/swtor-running.sh never
# matches it while the group runs.
fx_orphan_as() {
  local SANDBOX=$1 a0='C:\fixture\orphan-as\probe.exe' pid cmd
  mkdir -p "$SANDBOX/bin"
  printf '#!/bin/bash\nprintf "%%s\\n" "$@" >>%q\nexec /bin/bash "$@"\n' "$SANDBOX/bash-argv.txt" >"$SANDBOX/bin/bash"
  chmod 755 "$SANDBOX/bin/bash"
  pid=$(PATH="$SANDBOX/bin:$PATH" orphan_as "$a0" /bin/sleep 30)
  # ready once the rewriting shell has exec'd the program (up to 5 s): a fixed delay sometimes
  # still sees the shell on a busy Mac
  for _ in $(seq 1 50); do
    cmd=$(ps -o command= -p "$pid" 2>/dev/null || true)
    [ "$cmd" != "$a0 30" ] || break
    sleep 0.1
  done
  check "orphan-as: the program runs with argv[0] rewritten ($cmd)" test "$cmd" = "$a0 30"
  check "orphan-as: the rewriting shell ran (the stand-in bash recorded it)" test -s "$SANDBOX/bash-argv.txt"
  check "orphan-as: argv[0] never on the shell's command line" eval '! grep -F -x -q -- "$a0" "$SANDBOX/bash-argv.txt"'
  kill "$pid" 2>/dev/null || true
  # the program's environment, as it writes it itself (ps -E shows none on current macOS)
  PATH="$SANDBOX/bin:$PATH" orphan_as "$a0" /bin/bash -c 'env >"$1.new" && mv "$1.new" "$1"' env "$SANDBOX/env.txt" >/dev/null
  for _ in $(seq 1 50); do [ -s "$SANDBOX/env.txt" ] && break; sleep 0.1; done
  check "orphan-as: the program's environment was written" grep -q '^PATH=' "$SANDBOX/env.txt"
  check "orphan-as: ORPHAN_ARGV0 doesn't reach the program" eval '! grep -q "^ORPHAN_ARGV0=" "$SANDBOX/env.txt"'
}
