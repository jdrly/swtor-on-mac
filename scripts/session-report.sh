#!/bin/bash
# Summary of one game session from d9mt's log lines in wine.log (Debug Logging on in Settings):
# frame rate, slow frames, hitches (d9mt's share vs the game's), shader/pipeline compile waits,
# memory peak, render passes and the attachment traffic d9mt's load/store optimization saved.
#
#   session-report.sh [--skip <s>] [--keep] [wine.log]   one session (default: the current
#                                                        ~/Library/Logs/SWTOR on Mac/wine.log)
#   session-report.sh [--skip <s>] --compare A.log B.log  two sessions side by side (before/after)
#
#   --skip <s>  leave out the first <s> seconds (loading screens, character select)
#   --keep      also save the log as ~/Library/Logs/SWTOR on Mac/sessions/wine-<date>-<version>.log:
#               wine.log starts afresh at every game start, so keep the sessions to compare
#
# Sources, all optional (SWTOR on Mac 0.0.5 logs have no STATS lines; then the frame numbers
# come from what there is):
#   STATS     once a second (d9mt 0.0.6 dev and later): fps, frame times, slow frames, passes,
#             attachment loads/stores, compiles, Metal's allocated memory
#   HITCH     each frame over 50 ms: d9mt's time in it and by what, or the game's
#   COMPILE   render-thread frames with compiles or over 33 ms (shader/pipeline waits)
#   DIAG MEM  every 256 frames: Metal's allocated memory
#   RESTORE   seconds with attachment re-clears (d9mt 0.0.6-dev.2 and later): what was
#             re-cleared (format, size, aspects), why, and the D3D9 call it came from;
#             RESTORE-SUMMARY when the game released its device (not every exit does)
# Also in Collect Logs (session-report.txt). Runs under macOS's /bin/bash 3.2 and awk.
set -euo pipefail

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

SKIP=0 KEEP="" COMPARE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --skip) [ $# -ge 2 ] || usage; SKIP=$2; shift 2 ;;
    --keep) KEEP=1; shift ;;
    --compare) COMPARE=1; shift ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) break ;;
  esac
done
case "$SKIP" in ''|*[!0-9]*) usage ;; esac

LOGS="${SWTOR_ON_MAC_ROOT:+$SWTOR_ON_MAC_ROOT/home}"
LOGS="${LOGS:-$HOME}/Library/Logs/SWTOR on Mac"

# analyze <log>: key=value lines
analyze() {
  LC_ALL=C awk -v skip="$SKIP" '
    function num(s) { return s + 0 }
    # value of key=... in this line ("" if none); stops at space
    function field(key,    p, s) {
      p = index($0, " " key "=")
      if (!p) return ""
      s = substr($0, p + length(key) + 2)
      sub(/[ |].*/, "", s)
      return s
    }
    # quicksort a[1..n]
    function qs(a, lo, hi,    i, last, t) {
      if (lo >= hi) return
      t = a[lo]; a[lo] = a[int((lo + hi) / 2)]; a[int((lo + hi) / 2)] = t
      last = lo
      for (i = lo + 1; i <= hi; i++) if (a[i] < a[lo]) { last++; t = a[last]; a[last] = a[i]; a[i] = t }
      t = a[lo]; a[lo] = a[last]; a[last] = t
      qs(a, lo, last - 1); qs(a, last + 1, hi)
    }
    function pct(a, n, p,    k) { if (!n) return ""; k = int((n - 1) * p + 0.5) + 1; return a[k] }

    /D9MT: pipeline wait budget/ { budget = $0; sub(/.*budget /, "", budget); sub(/ per frame.*/, "", budget) }
    /D9MT: attachment load\/store optimization off/ { attoff = 1 }
    /D9MT: memory profile/ { mp = $0; sub(/.*memory profile /, "", mp); sub(/:.*/, "", mp) }

    / STATS t=/ {
      t = num(field("t"))
      if (t < lastT) { resets++ }        # a second device: counted on
      lastT = t
      if (t <= skip) next
      fps = num(field("fps")); split(field("ms"), ms, "/")
      ns++; f[ns] = fps
      secs++; frames += fps; ftime += num(ms[1]) * fps
      if (fps < 58) below58++
      p99[ns] = num(ms[2]); if (num(ms[3]) > maxft) maxft = num(ms[3])
      s33 += num(field("slow33")); s50 += num(field("slow50"))
      rp += num(field("rp")) * fps; skp += num(field("skip")) * fps; cb += num(field("cb")) * fps
      dr += num(field("draws")) * fps; rst += num(field("restore")) * fps
      saved += num(field("savedMiB")) * fps
      sh += num(field("sh")); pso += num(field("pso"))
      split(field("wait"), w, "/"); waits += num(w[1]); waitMs += num(w[2])
      a = num(field("allocMiB")); if (a > memPeak) memPeak = a
      att = field("att")
      next
    }
    / HITCH frame=/ {
      nh++
      dt = num(field("dtMs")); hitchMs += dt
      in9 = num(field("inD9mtMs"))
      # the frame is d9mt'"'"'s when most of it was spent inside d9mt, or waiting on its render thread
      line = $0; cs = line; sub(/.*\| cs: /, "", cs)
      split(cs, cw, " "); rw = 0
      for (i in cw) if (cw[i] ~ /^renderWait=/) { v = cw[i]; sub(/.*\//, "", v); rw = num(v) }
      if (in9 + rw >= dt / 2) { nd++; dMs += dt } else { ng++; gMs += dt }
      # categories: "name=count/ms[/MiB]" between the first and the second "|"
      mid = line; sub(/^[^|]*\| /, "", mid); sub(/ \| cs:.*/, "", mid)
      nc = split(mid, parts, " ")
      for (i = 1; i <= nc; i++) {
        if (parts[i] !~ /=/) continue
        name = parts[i]; sub(/=.*/, "", name)
        v = parts[i]; sub(/^[^=]*=[0-9]*\//, "", v); sub(/ms.*/, "", v)
        if (name == "present" || name == "latencyWait") continue   # mostly vsync/latency waits
        cat[name] += num(v)
      }
      if (rw > 0) cat["renderWait(compiles)"] += rw
      next
    }
    / COMPILE frame=/ {
      nco++
      dt = num(field("dtMs")); if (dt > 33.4) c33++; if (dt > 50) c50++
      split(field("renderWait"), w, "/"); cwaits += num(w[1]); v = w[2]; sub(/ms/, "", v); cwaitMs += num(v)
      v = field("shaders"); sub(/\/.*/, "", v); csh += num(v)
      v = field("psos"); sub(/\/.*/, "", v); cpso += num(v)
      next
    }
    / RESTORE t=/ {
      if (num(field("t")) <= skip) next
      nrl++
      # " | 120x 2048x2048 Depth32Float_Stencil8 s sample@Draw | ... | +3 other"
      rl = $0; sub(/^[^|]*\| /, "", rl)
      nr = split(rl, rparts, / \| /)
      for (i = 1; i <= nr; i++) {
        p = rparts[i]
        if (p ~ /^\+[0-9]+ other/) { v = p; sub(/^\+/, "", v); sub(/ .*/, "", v); rc["(other: below a second'"'"'s top 5)"] += num(v); continue }
        if (p !~ /^[0-9]+x /) continue
        v = p; sub(/x .*/, "", v); k = p; sub(/^[0-9]+x /, "", k)
        rc[k] += num(v); rtot += num(v)
      }
      next
    }
    / RESTORE-SUMMARY frames=/ {
      rs = $0; sub(/.*RESTORE-SUMMARY /, "", rs); sub(/ \|.*/, "", rs)
      next
    }
    / DIAG MEM frame=/ {
      a = num(field("allocatedMiB")); if (a > diagPeak) diagPeak = a
      fr = num(field("frame")); if (fr > lastFrame) lastFrame = fr
      next
    }
    END {
      print "stats=" ns + 0
      if (ns) {
        qs(f, 1, ns); qs(p99, 1, ns)
        printf "duration=%d\n", secs
        printf "frames=%d\n", frames
        printf "fps_avg=%.1f\n", frames / secs
        printf "fps_median=%.1f\n", pct(f, ns, 0.5)
        printf "fps_p1=%.1f\n", pct(f, ns, 0.01)
        printf "below58=%.1f\n", 100 * below58 / ns
        printf "ft_avg=%.2f\n", ftime / (frames ? frames : 1)
        printf "ft_p99_median=%.1f\n", pct(p99, ns, 0.5)
        printf "ft_max=%.1f\n", maxft
        printf "slow33=%d\nslow50=%d\n", s33, s50
        if (frames) {
          printf "rp=%.1f\nskip=%.1f\ncb=%.1f\ndraws=%.0f\nrestore=%.2f\n", rp / frames, skp / frames, cb / frames, dr / frames, rst / frames
          printf "saved_mib_frame=%.1f\n", saved / frames
          printf "saved_gib=%.1f\n", saved / 1024
        }
        printf "compiles=%d shaders, %d pipelines\n", sh, pso
        printf "compile_waits=%d / %.0f ms\n", waits, waitMs
        if (memPeak) printf "mem_peak=%d\n", memPeak
        printf "att=%s\n", att
      } else {
        if (lastFrame) printf "frames=%d\n", lastFrame
        if (nco) {
          printf "slow33_rt=%d\nslow50_rt=%d\n", c33, c50
          printf "compiles=%d shaders, %d pipelines\n", csh, cpso
          printf "compile_waits=%d / %.0f ms\n", cwaits, cwaitMs
        }
        printf "att=%s\n", attoff ? "off" : "n/a"
      }
      if (diagPeak > memPeak) printf "mem_peak=%d\n", diagPeak
      printf "hitches=%d\n", nh
      if (nh) {
        printf "hitch_ms=%.0f\n", hitchMs
        printf "hitch_d9mt=%d (%.0f%% of hitch time)\n", nd, 100 * dMs / (hitchMs ? hitchMs : 1)
        printf "hitch_game=%d (%.0f%% of hitch time)\n", ng, 100 * gMs / (hitchMs ? hitchMs : 1)
        top = ""
        for (k = 0; k < 3; k++) {
          best = ""; bv = 0
          for (c in cat) if (!(c in used) && cat[c] > bv) { best = c; bv = cat[c] }
          if (best == "") break
          used[best] = 1
          top = top (top == "" ? "" : ", ") sprintf("%s %.0f ms", best, bv)
        }
        print "hitch_top=" (top == "" ? "-" : top)
      }
      if (nrl) {
        printf "restore_seconds=%d\n", nrl
        for (k = 1; k <= 8; k++) {
          best = ""; bv = 0
          for (c in rc) if (!(c in rused) && rc[c] > bv) { best = c; bv = rc[c] }
          if (best == "") break
          rused[best] = 1
          if (frames) printf "restore_cause_%d=%7.2f/frame %7dx  %s\n", k, bv / frames, bv, best
          else        printf "restore_cause_%d=%7dx  %s\n", k, bv, best
        }
      }
      if (rs != "") print "restore_summary=" rs
      if (mp != "") print "memory_profile=" mp
      if (budget != "") print "wait_budget=" budget
      if (resets) print "devices=" resets + 1
    }' "$1"
}

get() { sed -n "s/^$1=//p" "$2" | head -1; }

# label key [unit]: one line of the report from the analysis files A (and B)
row() {  # (left out when no log has it)
  local label=$1 key=$2 a b=""
  a=$(get "$key" "$A")
  [ -z "${B:-}" ] || b=$(get "$key" "$B")
  [ -n "$a$b" ] || return 0
  if [ -n "${B:-}" ]; then
    printf '  %-38s %-36s %s\n' "$label" "${a:-n/a}" "${b:-n/a}"
  else
    printf '  %-38s %s\n' "$label" "$a"
  fi
}

report() {
  [ "$SKIP" -gt 0 ] && echo "  (first $SKIP s left out)"
  row "Seconds with STATS lines" duration
  row "Frames" frames
  row "FPS: average" fps_avg
  row "FPS: median second" fps_median
  row "FPS: 1% low (worst seconds)" fps_p1
  row "Seconds below 58 fps (%)" below58
  row "Frame time: average (ms)" ft_avg
  row "Frame time: median 99th pct (ms)" ft_p99_median
  row "Frame time: worst (ms)" ft_max
  row "Frames over 33 ms" slow33
  row "Frames over 50 ms" slow50
  row "Render-thread frames > 33 ms" slow33_rt
  row "Render-thread frames > 50 ms" slow50_rt
  row "Hitches (frames over 50 ms)" hitches
  row "  total hitch time (ms)" hitch_ms
  row "  d9mt's" hitch_d9mt
  row "  the game's" hitch_game
  row "  top d9mt causes" hitch_top
  row "Compiles" compiles
  row "Render-thread compile waits" compile_waits
  row "Memory peak (Metal, MiB)" mem_peak
  row "Render passes per frame" rp
  row "  skipped (no-op) per frame" skip
  row "Command buffers per frame" cb
  row "Draws per frame" draws
  row "Attachment traffic saved (MiB/frame)" saved_mib_frame
  row "  over the session (GiB)" saved_gib
  row "  re-clears per frame" restore
  row "Attachment optimization" att
  row "Memory profile" memory_profile
  row "Pipeline wait budget" wait_budget
  causes "$A" "${B:+A: }"
  [ -z "${B:-}" ] || causes "$B" "B: "
}

# causes <analysis> <prefix>: the re-clears by cause, from the RESTORE lines
causes() {
  local k line n
  n=$(get restore_seconds "$1")
  [ -n "$n" ] || [ -n "$(get restore_summary "$1")" ] || return 0
  echo "  ${2}Re-clears by cause (RESTORE lines, ${n:-0} seconds with any):"
  for k in 1 2 3 4 5 6 7 8; do
    line=$(get "restore_cause_$k" "$1")
    [ -n "$line" ] && echo "    $line"
  done
  line=$(get restore_summary "$1")
  [ -z "$line" ] || echo "    session total at device release: $line"
}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

if [ -n "$COMPARE" ]; then
  [ $# -eq 2 ] || usage
  for f in "$1" "$2"; do [ -r "$f" ] || { echo "Cannot read $f" >&2; exit 1; }; done
  analyze "$1" >"$tmp/a"; analyze "$2" >"$tmp/b"
  A="$tmp/a" B="$tmp/b"
  echo "SWTOR on Mac session report: comparison"
  printf '  %-38s %-36s %s\n' "" "A: ${1##*/}" "B: ${2##*/}"
  report
  if [ "$(get stats "$A")" = 0 ] || [ "$(get stats "$B")" = 0 ]; then
    echo "  (n/a: no STATS lines in that log: Debug Logging was off, or the session ran a build"
    echo "   before 0.0.6-dev. Hitches and compile waits still compare.)"
  fi
  exit 0
fi

[ $# -le 1 ] || usage
LOG="${1:-$LOGS/wine.log}"
[ -r "$LOG" ] || { echo "Cannot read $LOG" >&2; exit 1; }
analyze "$LOG" >"$tmp/a"
A="$tmp/a" B=""
echo "SWTOR on Mac session report: $LOG"
report
if [ "$(get stats "$A")" = 0 ]; then
  echo "  (no STATS lines: Debug Logging was off, or the session ran a build before 0.0.6-dev;"
  echo "   frame numbers from HITCH/COMPILE/DIAG MEM lines only)"
fi
if [ -n "$KEEP" ]; then
  version=$(sed -n 's/^# SWTOR on Mac \([^:]*\):.*/\1/p' "$LOGS/../../Application Support/SWTOR on Mac/env" 2>/dev/null | head -1 || true)
  mkdir -p "$LOGS/sessions"
  dest="$LOGS/sessions/wine-$(date -r "$LOG" +%Y%m%d-%H%M)${version:+-$version}.log"
  cp "$LOG" "$dest"
  echo "Saved a copy: $dest"
fi
