#!/bin/bash
# nfprobe.sh [--out <dir>] [--display] [--control-without-toggle]
# Builds scripts/nfprobe.m with clang and runs its modes one after another, each with a time limit:
# control, a, b, a-opts, b-opts, and with --display the second-display mode (start it with a second
# display attached; once the window is in its Space, take that display away within 60 s).
# Run it in a logged-in GUI session: each run takes the screen for a few seconds.
# Output: <dir>/<run>.txt per run (stdout and stderr), <dir>/summary.txt with each run's verdict
# line; default <dir> is $TMPDIR/nfprobe-<date>.
# --control-without-toggle runs the control without its toggleFullScreen: call (the failing control):
# it must print "no verdict" and this script must exit 1.
# Exit status: 0 the control entered and left, and every run gave a verdict; 1 the control has no
# verdict (this Mac can't judge; the other runs are skipped); 2 a run had to be killed; 70 the build
# failed. Needs no Wine, no game files and no network.
set -u
here=$(cd "$(dirname "$0")" && pwd)
out="" display=0 notoggle=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) [ $# -ge 2 ] || { sed -n '2,14p' "$0" >&2; exit 64; }; out=$2; shift 2 ;;
    --display) display=1; shift ;;
    --control-without-toggle) notoggle=--no-toggle; shift ;;
    *) sed -n '2,14p' "$0" >&2; exit 64 ;;
  esac
done
out=${out:-${TMPDIR:-/tmp}/nfprobe-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$out" || exit 70
clang -fobjc-arc -O2 -Wall -framework AppKit -framework Metal -framework QuartzCore \
  -o "$out/nfprobe" "$here/nfprobe.m" || exit 70
{ sw_vers; sysctl -n hw.model machdep.cpu.brand_string; } > "$out/machine.txt" 2>&1
: > "$out/summary.txt"
killed=0

# probe <run> <limit s> [args...]: one run, killed after <limit> seconds if it hasn't ended by then
probe() {
  local name=$1 limit=$2 pid w rc
  shift 2
  echo "== $name"
  "$out/nfprobe" "$name" "$@" > "$out/$name.txt" 2>&1 &
  pid=$!
  ( sleep "$limit"; kill -TERM "$pid" 2>/dev/null; sleep 3; kill -KILL "$pid" 2>/dev/null ) 2>/dev/null &
  w=$!
  wait "$pid"; rc=$?
  pkill -P "$w" sleep 2>/dev/null; kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
  if ! grep -q '^verdict ' "$out/$name.txt"; then
    echo "verdict run=$name result=failed exit=- (killed by nfprobe.sh after $limit s, status $rc)" >> "$out/$name.txt"
    killed=1
  fi
  grep '^verdict ' "$out/$name.txt" | tee -a "$out/summary.txt"
  sleep 2 # let the Dock finish with the Space before the next run
}

probe control 75 ${notoggle:+"$notoggle"}
if ! grep -q '^verdict run=control result=entered exit=exited$' "$out/summary.txt"; then
  for r in a b a-opts b-opts; do echo "verdict run=$r result=no verdict exit=- (the control didn't enter and leave)"; done | tee -a "$out/summary.txt"
  echo "no verdict: this session can't do a fullscreen transition; output in $out"
  exit 1
fi
for r in a b a-opts b-opts; do probe "$r" 75; done
[ "$display" = 0 ] || probe display 135 --wait 60
echo "output in $out"
[ "$killed" = 0 ] || exit 2
exit 0
