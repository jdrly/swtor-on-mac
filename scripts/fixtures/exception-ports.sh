# shellcheck shell=bash
# Fixture group exception-ports: the packaged hold-launcher starts its programs without the task
# exception ports it inherited for EXC_BAD_ACCESS, EXC_BAD_INSTRUCTION and EXC_BREAKPOINT (see
# hold_launcher.c). Rosetta sends each hardware exception of a translated process to the port the
# process inherited first; when that port is dead (its owner on the launcher's side is gone), the
# send fails with "rosetta error: failed to send exception: 0x10000003" and the program doesn't
# get past the fault. The probe (scripts/exception-ports-probe.c) starts a chain with dead ports and
# faults once in an x86_64 child. Needs clang and Rosetta; neither the official app nor Wine.
# Sourced; check and its counters come from lib.sh.
#
#   fx_exception_ports <app> <folder for the probe and its output>
#
# hold-launcher runs as its x86_64 slice (lipo -thin), as under the launcher's translated chain
# (/usr/bin/arch -x86_64 isn't used: under dead ports the translated program it starts hangs before
# its first line).
# Checks: through hold-launcher's x86_64 slice the fault
# is handled and nothing of Rosetta's appears; a fault nobody handles still ends the game the
# normal way (SIGSEGV, and hold-launcher's line says so); and the control: the same chain through
# the probe's own x86_64 exec in hold-launcher's place keeps the dead ports and fails with Rosetta's line, so
# the fixture sees the failure it guards against.
ep_kill_tree() {  # <pid>: it and its descendants (the probe, hold-launcher, the x86_64 child)
  local c
  for c in $(pgrep -P "$1" 2>/dev/null || true); do ep_kill_tree "$c"; done
  kill -KILL "$1" 2>/dev/null || true
}
ep_run() {  # <name> <command...>: runs it, 30 s at most; out/err/rc in $EP/<name>.*
  local n=$1 pid t=0; shift
  "$@" >"$EP/$n.out" 2>"$EP/$n.err" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$t" -lt 300 ]; do sleep 0.1; t=$((t + 1)); done
  if kill -0 "$pid" 2>/dev/null; then ep_kill_tree "$pid"; echo "(killed after 30 s)" >>"$EP/$n.err"; fi
  local rc=0
  wait "$pid" || rc=$?
  echo "$rc" >"$EP/$n.rc"
}
ep_build() {  # <hold-launcher>: the probe twice, and the x86_64 slice of that hold-launcher
  clang -O2 -Wall -arch arm64 -o "$EP/start" "$REPO/scripts/exception-ports-probe.c" &&
    clang -O0 -Wall -arch x86_64 -o "$EP/fault" "$REPO/scripts/exception-ports-probe.c" &&
    lipo -thin x86_64 "$1" -output "$EP/hold-launcher"
}
ep_rc() { [ "$(cat "$EP/$1.rc")" = "$2" ]; }
ep_has() { grep -qF -- "$3" "$EP/$1.$2"; }
fx_exception_ports() {
  local app=$1
  EP=$2
  mkdir -p "$EP"
  if ! command -v clang >/dev/null || ! command -v lipo >/dev/null || ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
    echo "  skip exception-ports: needs clang, lipo and Rosetta, not here"
    return 0
  fi
  check "exception-ports: the probe builds (native start, x86_64 fault) and hold-launcher's x86_64 slice" \
    ep_build "$app/Contents/Resources/helpers/hold-launcher"
  ep_run hl "$EP/start" start-dead -- "$EP/hold-launcher" --run-game "$EP/hold.log" fixture "$EP/fault" fault handler
  check "exception-ports: through hold-launcher the x86_64 child gets past its fault (exit 0)" ep_rc hl 0
  check "exception-ports: ... its handler ran" ep_has hl out "past the fault"
  check "exception-ports: ... no Rosetta error" eval '! grep -q "rosetta" "$EP/hl.err"'
  ep_run crash "$EP/start" start-dead -- "$EP/hold-launcher" --run-game "$EP/hold.log" fixture "$EP/fault" fault default
  check "exception-ports: an unhandled fault still ends the child by SIGSEGV (exit 139)" ep_rc crash 139
  check "exception-ports: ... hold-launcher's line says so" eval 'grep -q "signal 11 (SIGSEGV)" "$EP/hold.log"'
  check "exception-ports: ... no Rosetta error" eval '! grep -q "rosetta" "$EP/crash.err"'
  # the control: a translated process in hold-launcher's place that clears nothing keeps the dead ports
  ep_run control "$EP/start" start-dead -- "$EP/fault" exec -- "$EP/fault" fault handler
  check "exception-ports: control: without hold-launcher the same chain fails with Rosetta's line" \
    ep_has control err "failed to send exception: 0x10000003"
  check "exception-ports: control: ... and doesn't get past the fault" eval '! ep_has control out "past the fault" && ! ep_rc control 0'
}
