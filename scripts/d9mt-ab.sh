#!/bin/bash
# d9mt A/B switches for the next game starts, in development builds of SWTOR on Mac
# (Resources/d9mt-ab.sh; release builds have neither this script nor the line that reads its
# file). It writes ~/Library/Application Support/SWTOR on Mac/d9mt-ab.env, which a development
# build's env reads after its own settings (som.sh write_env), so Settings and Reinstall keep it.
# Each call sets exactly the switches it is given, the others go off; they stay until the next
# call. The game's wine.log names them in its second line ("d9mt-ab: ..."), and
# session-report.sh shows them with what d9mt says it does.
#
#   d9mt-ab.sh                    what the next game start gets
#   d9mt-ab.sh <switch>...        set exactly these switches
#   d9mt-ab.sh reset [--clean]    no switches (--clean: also delete the cold caches below)
#
# Switches:
#   state-off     D9MT_STATE_CACHE=0: no pipeline state cache (no prewarm, nothing recorded)
#   pfv           D9MT_TEX_PFV=1: PixelFormatView on every texture (no lossless compression)
#   barrier-all   D9MT_PASS_BARRIER=all: the end-of-pass barrier before all stages
#   clear-keep    D9MT_CLEAR_DISCARD=0: a clear that ends a pass keeps the pass's stores
#   gpu-old       pfv barrier-all clear-keep: d9mt's GPU path as in SWTOR on Mac 0.1.0
#   vsync-off     DXVK_CONFIG d3d9.presentInterval=0 (vsync off, whatever Settings says)
#   repro         DXVK_CONFIG d3d9.reproducibleCommandStream=True (no implicit mid-frame
#                 submits: the split counters without them)
#   cap=<fps>     D9MT_FPS_CAP=<fps> (20-1000): d9mt's frame cap, as Settings' Frame Rate Limit
#                 sets it (that one wins while it is on)
#   cap-noalign   D9MT_FPS_CAP_ALIGN=0: the cap's timer only, presents not aligned to vsync
#   dxvkcap=<fps> DXVK_CONFIG d3d9.maxFrameRate=<fps>: DXVK's frame limiter (busy-waits the last
#                 4+ ms of every sleep), the cap before 0.1.3, for comparison
#   unwritten-off D9MT_UNWRITTEN_NULL=0: a texture sampled before its first write shows its
#                 memory again, as before d9mt #105 (the magenta icons on an M4)
#   pso-async     D9MT_PSO_ASYNC_FLUSH=1: d9mt writes its pipeline archive on a thread at a quiet
#                 moment instead of in the build that makes it due (d9mt #114); no archive write
#                 at exit, so the last pipelines of a session aren't kept
#   flush-cap     D9MT_FLUSH_CAP=1: weak flush hints don't submit a command buffer mid-frame
#                 (upstream DXVK's cap on tiling GPUs, d9mt #113), as Settings' Fewer GPU
#                 Batches sets it
#   flush-cap-off D9MT_FLUSH_CAP=0: no flush cap, also with Fewer GPU Batches on in Settings
#                 (these switches win over that setting)
#   compile-maxconc D9MT_COMPILE_MAXCONC=1: asks Metal to compile more pipelines at once
#                 (d9mt #117)
#   cold=<name>   an empty shader cache and pipeline archives of their own for this run, in
#                 ~/Library/Caches/SWTOR on Mac/d9mt-ab/<name> (D9MT_AIR_CACHE,
#                 D9MT_PSO_ARCHIVE_DIR): the game starts as after an update that changed
#                 d9mt's shader compiler. d9mt's own caches are not touched, and the state
#                 cache stays the normal one (add state-off for a run without it). A name
#                 that was used before is warm: take a new one for every cold run.
#
# SWTOR_ON_MAC_ROOT=/abs/dir: a sandbox (as for som.sh).
set -euo pipefail
H="${SWTOR_ON_MAC_ROOT:+$SWTOR_ON_MAC_ROOT/home}"
H="${H:-$HOME}"
SOM="$H/Library/Application Support/SWTOR on Mac"
FILE="$SOM/d9mt-ab.env"
COLD="$H/Library/Caches/SWTOR on Mac/d9mt-ab"

usage() { sed -n '2,/^# SWTOR_ON_MAC_ROOT/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 2; }

# What the next game start gets
status() {
  if [ -f "$FILE" ]; then
    echo "d9mt A/B switches for the next game start: $(sed -n 's/^SWTOR_D9MT_AB="\(.*\)"$/\1/p' "$FILE")"
    grep -v -e '^#' -e '^SWTOR_D9MT_AB=' "$FILE" | sed 's/^/  /'
  else
    echo "d9mt A/B switches: none (the next game start runs as installed)"
  fi
  if [ ! -f "$SOM/env" ]; then
    echo "Note: SWTOR on Mac is not installed here ($SOM)."
  elif ! grep -qF 'd9mt-ab.env' "$SOM/env"; then
    echo "Note: the installed SWTOR on Mac does not read these switches (only development builds"
    echo "do): click Reinstall (or Update to ...) in a development build of the app first."
  fi
  if [ -d "$COLD" ] && [ -n "$(ls -A "$COLD" 2>/dev/null)" ]; then
    echo "Cold caches: $(ls "$COLD" | tr '\n' ' ')($(du -sh "$COLD" 2>/dev/null | cut -f1); reset --clean deletes them)"
  fi
}

case "${1:-}" in
  "") status; exit 0 ;;
  -h|--help) usage ;;
  reset)
    case "${2:-}" in "") ;; --clean) rm -rf "$COLD"; echo "Deleted the cold caches ($COLD)" ;; *) usage ;; esac
    rm -f "$FILE"
    status
    exit 0 ;;
esac

[ -d "$SOM" ] || { echo "SWTOR on Mac is not installed ($SOM)" >&2; exit 1; }
names="" vars="" config="" cold=""
add() { case " $names " in *" $1 "*) ;; *) names="${names:+$names }$1" ;; esac; }
var() { case "$vars" in *"$1"*) ;; *) vars="$vars$1
" ;; esac; }
for a in "$@"; do
  case "$a" in
    state-off) add "$a"; var 'D9MT_STATE_CACHE=0' ;;
    pfv) add "$a"; var 'D9MT_TEX_PFV=1' ;;
    barrier-all) add "$a"; var 'D9MT_PASS_BARRIER=all' ;;
    clear-keep) add "$a"; var 'D9MT_CLEAR_DISCARD=0' ;;
    gpu-old) for s in pfv barrier-all clear-keep; do add "$s"; done
      var 'D9MT_TEX_PFV=1'; var 'D9MT_PASS_BARRIER=all'; var 'D9MT_CLEAR_DISCARD=0' ;;
    vsync-off) add "$a"; case "$config" in *presentInterval*) ;; *) config="${config:+$config;}d3d9.presentInterval=0" ;; esac ;;
    repro) add "$a"; case "$config" in *reproducible*) ;; *) config="${config:+$config;}d3d9.reproducibleCommandStream=True" ;; esac ;;
    cap=*|dxvkcap=*)
      n=${a#*=}
      case "$n" in ''|*[!0-9]*) echo "$a: a frame rate, 20 to 1000" >&2; exit 2 ;; esac
      [ "$n" -ge 20 ] && [ "$n" -le 1000 ] || { echo "$a: a frame rate, 20 to 1000" >&2; exit 2; }
      add "$a"
      case "$a" in
        cap=*) var "D9MT_FPS_CAP=$n" ;;
        *) case "$config" in *maxFrameRate*) ;; *) config="${config:+$config;}d3d9.maxFrameRate=$n" ;; esac ;;
      esac ;;
    cap-noalign) add "$a"; var 'D9MT_FPS_CAP_ALIGN=0' ;;
    unwritten-off) add "$a"; var 'D9MT_UNWRITTEN_NULL=0' ;;
    pso-async) add "$a"; var 'D9MT_PSO_ASYNC_FLUSH=1' ;;
    flush-cap|flush-cap-off)
      v=$([ "$a" = flush-cap ] && echo 1 || echo 0)
      case "$vars" in *"D9MT_FLUSH_CAP=$((1 - v))"*) echo "flush-cap and flush-cap-off: only one of them" >&2; exit 2 ;; esac
      add "$a"; var "D9MT_FLUSH_CAP=$v" ;;
    compile-maxconc) add "$a"; var 'D9MT_COMPILE_MAXCONC=1' ;;
    cold=*)
      n=${a#cold=}
      case "$n" in ''|*[!A-Za-z0-9._-]*|.*) echo "cold=<name>: letters, digits, . _ - only" >&2; exit 2 ;; esac
      [ -z "$cold" ] || [ "$cold" = "$n" ] || { echo "Only one cold=<name> at a time" >&2; exit 2; }
      cold=$n; add "$a" ;;
    *) echo "Unknown switch: $a" >&2; usage ;;
  esac
done
if [ -n "$cold" ] && [ -e "$COLD/$cold" ]; then
  echo "Note: $COLD/$cold was used before, so it is not cold any more (take a new name, or reset --clean)."
fi

tmp="$FILE.new.$$"
{
  echo "# d9mt A/B switches for the next game starts, set by d9mt-ab.sh on $(date '+%Y-%m-%d %H:%M')."
  echo "# The env of a development build reads this file; d9mt-ab.sh reset removes it."
  echo "SWTOR_D9MT_AB=\"$names\""
  printf '%s' "$vars"
  [ -z "$config" ] || echo "DXVK_CONFIG=\"$config\""
  if [ -n "$cold" ]; then
    echo "D9MT_AIR_CACHE=\"$COLD/$cold/air-cache.sqlite3\""
    echo "D9MT_PSO_ARCHIVE_DIR=\"$COLD/$cold/pso\""
  fi
} >"$tmp"
mv -f "$tmp" "$FILE"
status
echo "They take effect the next time the game starts."
