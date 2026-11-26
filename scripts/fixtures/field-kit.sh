# shellcheck shell=bash
# Fixture group field-kit (scripts/test-fixtures.sh only): what a before/after field test reads.
# session-report.sh on made-up logs: frame times over 200 ms, the session's p99 and true 1% low
# reported as missing, the measurement (instrumented or ordinary play), the interval after the
# mark (--mark), gaps and suppressed lines, a log without its start, 3 to 5 sessions side by
# side and the A/B/A over the last three, the display limit from d9mt's SCREEN-INFO lines; the
# wrapper's settings, conditions (memory too) and d9mt files lines on stand-ins, and its memory
# read on this Mac's own sysctl; Collect Logs on planted logs: one zip with every kept game start side by side,
# each start's first lines kept when its log is cut, and no account name, home folder or path in
# what this adds; the game's graphics settings, only client_settings.ini's [Renderer] section,
# and one line when there is no section or no file; the same of the DirectX 12 client's
# client_settings_DX12.ini; the display limit the app passes and memory now, each with its line
# when it is missing. Needs neither the official app nor Wine.
# Sourced; check, piped and the counters come from lib.sh.
#
#   fx_field_kit <app> <wine-wrapper.sh> <folder>

# fk_st <t> <fps> [<ms avg/p99/max> <slow33> <slow50>]: a STATS line; fk_vis <from> <to> [at]: a
# visibility change; fk_hitch <ms>: a HITCH line; fk_head <version> <d9mt> <started> [settings]
# [d3d9.dll hash] [energy mode]: the wrapper's lines at the start; fk_scr <t> <hz>: a SCREEN line
fk_st() {
  printf 'warn:  STATS t=%s fps=%s ms=%s slow33=%s slow50=%s | rp=1.0 skip=0.0 cb=1.0 draws=1500 | ld=0.0 clr=0.0 ldDc=0.0 st=0.0 stDc=0.0 rsv=0.0 restore=0.0 savedMiB=0.0 attMs=0.1 clrFold=0.0 clrPass=0.0 | sh=0 pso=0 wait=0/0.0ms | allocMiB=100 att=on\n' \
    "$1" "$2" "${3:-16.7/17.0/17.5}" "${4:-0}" "${5:-0}"
}
fk_vis() { printf 'warn:  MtlPresenter: %s visibility 0x%s -> 0x%s (visible=0 activeSpace=0 miniaturized=0)%s\n' "${3:-20:00:00.000}" "$1" "$2" "${4:-}"; }
fk_hitch() { printf 'warn:  HITCH frame=1 dtMs=%s inD9mtMs=1.0 (1%%) texMiB created=0.0 uploaded=0.0 csBehind=0 | texCreate=1/1.0ms/0.0MiB | cs: renderWait=0/0.0ms shaders=0/0.0ms psos=0/0.0ms\n' "$1"; }
fk_scr() { printf 'warn:  SCREEN t=%s shown=30 dropped=0 pend=2 lost=0 onscreen=33.3/0.20/34.0 refreshes=0/29/0 late=0 req=33.3 lat=30.1/32.0 hz=%s\n' "$1" "$2"; }
fk_pace() { printf 'warn:  PACE t=%s n=60 present=15.2/16.7/18.4 sd=0.61 | d9mt=4.1/5.0/7.9 wait=1.2 game=9.0/11.7/13.0 | cpu=%s d9mtBusy=230 gameCpu=582\n' "$1" "$2"; }
fk_head() {
  echo "SWTOR on Mac $1: engine cx26 cx-26.3.0-8, d9mt $2, started $3"
  echo "SWTOR on Mac game language: lang=en-us torsets=main,en-us, LANG=en_US.UTF-8"
  echo "SWTOR on Mac settings: ${4:-debug-logging=on hud=on game-mode=on D9MT_PROFILE=1 MTL_HUD_ENABLED=1}"
  echo "SWTOR on Mac conditions: power AC Power, energy mode ${6:-automatic}, thermal warnings none, memory pressure normal (40 % free), swap 0 MB used of 0 MB"
  echo "SWTOR on Mac d9mt files: d3d9.dll ${5:-0123456789ab}, winemetal.so ba9876543210"
}
# fk_arm <fps after the mark> [cpu]: a session of 85 s: 3 s of loading with 250 ms frames, a
# hitch before the mark, the mark (Cmd-Tab away and back) at second 10, then steady frames
fk_arm() {
  local t
  for t in 1 2 3; do fk_st "$t" 4.0 250.0/250.0/250.0 4 4; fk_hitch 250.0; done
  for t in 4 5 6 7 8; do fk_st "$t" 60.0; done
  fk_hitch 120.0; fk_st 9 55.0 18.0/120.0/120.0 1 1
  fk_vis 3 0 20:01:00.000; fk_st 10 20.0; fk_vis 0 3 20:01:01.500
  for t in $(seq 11 85); do fk_st "$t" "$1"; fk_pace "$t" "${2:-800}"; done
}
# fk_in <file> <regex>: a line of the report matches (grep -E)
fk_in() { grep -qE -- "$2" "$1"; }

fx_field_kit() {
  local app=$1 wrapper=$2 R=$3 SR="$1/Contents/Resources/session-report.sh" t
  mkdir -p "$R"

  # 1. Frame times over 200 ms; what STATS can't give is "missing"; instrumented
  { fk_head 0.1.7-dev.3 73511be "2026-11-01 20:00:00"; fk_arm 60.0; } >"$R/a.log"
  "$SR" "$R/a.log" >"$R/a.txt" 2>&1 || true
  check "field: the worst frame over 200 ms" fk_in "$R/a.txt" '^  Frame time: worst \(ms\) +250\.0$'
  check "field: the 250 ms frames counted over 50 ms (not the hidden second 9's)" fk_in "$R/a.txt" '^  Frames over 50 ms +12$'
  check "field: the session's p99 is missing, not a per-second number" fk_in "$R/a.txt" "^  Frame time: the session's p99 +missing \(see below\)$"
  check "field: the true 1% low is missing" fk_in "$R/a.txt" '^  FPS: 1% low \(slowest 1% of frames\) +missing \(see below\)$'
  check "field: the per-second numbers named as such" eval 'fk_in "$R/a.txt" "^  FPS: worst 1% of seconds +4\.0$" && fk_in "$R/a.txt" "^  Frame time: median second.s p99 \(ms\) +17\.0$" && fk_in "$R/a.txt" "the session.s p99 and true 1% low are not in the log"'
  check "field: profiled numbers labelled instrumented" fk_in "$R/a.txt" '^  Measurement +instrumented: Debug Logging on'
  check "field: the start's build, settings, conditions and files" eval 'fk_in "$R/a.txt" "^  Game start +2026-11-01 20:00:00$" && fk_in "$R/a.txt" "^  Settings at the start +debug-logging=on hud=on game-mode=on D9MT_PROFILE=1" && fk_in "$R/a.txt" "^  Power, thermal, memory at the start +power AC Power, energy mode automatic, thermal warnings none, memory pressure normal \(40 % free\), swap 0 MB used of 0 MB$" && fk_in "$R/a.txt" "^  d9mt files \(SHA-256\) +d3d9\.dll 0123456789ab, winemetal\.so ba9876543210$"'
  check "field: no mark asked, the whole session, nothing lost" eval 'fk_in "$R/a.txt" "^  Interval +the whole session$" && fk_in "$R/a.txt" "^  Data +nothing left out or lost$"'

  # 2. --mark: 60 s from 5 s after the return (in second 11, the one STATS t=11 closes): seconds
  # 16-75, the loading and the
  # hitch before the mark left out
  "$SR" --mark 60 "$R/a.log" >"$R/a-mark.txt" 2>&1 || true
  check "field: the interval after the mark" fk_in "$R/a-mark.txt" '^  Interval +STATS t 16-75, 60 s from 5 s after the mark at 20:01:01\.500; 60 lines$'
  check "field: only the interval's seconds and frames" eval 'fk_in "$R/a-mark.txt" "^  Seconds with STATS lines +60$" && fk_in "$R/a-mark.txt" "^  Frames +3600$" && fk_in "$R/a-mark.txt" "^  Frame time: worst \(ms\) +17\.5$"'
  check "field: no hitch from before the mark" fk_in "$R/a-mark.txt" '^  Hitches \(frames over 50 ms\) +0$'
  check "field: PACE seconds of the interval only" fk_in "$R/a-mark.txt" '^  PACE seconds +60$'
  "$SR" --mark 100 "$R/a.log" >"$R/a-short.txt" 2>&1 || true
  check "field: a short interval says so" eval 'fk_in "$R/a-short.txt" "^  Interval +STATS t 16-85, 70 s of the 100 asked \(the session ended\), from 5 s after the mark at 20:01:01\.500; 70 lines$" && fk_in "$R/a-short.txt" "^  Data +the interval is short$"'
  { fk_head 0.1.7-dev.3 73511be "2026-11-01 20:00:00"; for t in 1 2 3 4 5; do fk_st "$t" 60.0; done; } >"$R/nomark.log"
  "$SR" --mark 60 "$R/nomark.log" >"$R/nomark.txt" 2>&1 || true
  check "field: no mark: the whole session, and Data says so" eval 'fk_in "$R/nomark.txt" "^  Interval +the whole session: no mark" && fk_in "$R/nomark.txt" "^  Data +no mark$"'

  # the interval by elapsed time, not by lines: STATS lines 12-14 missing (a 4 s window before
  # the interval) leave it at t 16-75, Data names the gap after the mark; lines 30-32 missing
  # inside it: still t 16-75, 57 lines, the gap's seconds named; a second device before its end
  # (seconds 76-78 at 30 fps: an interval counted by lines would take them in)
  grep -v -E " (STATS|PACE) t=1[234] " "$R/a.log" | sed -E 's/ STATS t=(7[678]) fps=60\.0 / STATS t=\1 fps=30.0 /' >"$R/settle-gap.log"
  "$SR" --mark 60 "$R/settle-gap.log" >"$R/settle-gap.txt" 2>&1 || true
  check "field: lines lost before the interval don't move it" eval 'fk_in "$R/settle-gap.txt" "^  Interval +STATS t 16-75, 60 s from 5 s after the mark at 20:01:01\.500; 60 lines$" && fk_in "$R/settle-gap.txt" "^  FPS: average +60\.0$" && fk_in "$R/settle-gap.txt" "^  Data +.*a STATS window of 2 s or more in the 5 s after the mark"'
  grep -v -E " (STATS|PACE) t=3[012] " "$R/a.log" >"$R/inner-gap.log"
  "$SR" --mark 60 "$R/inner-gap.log" >"$R/inner-gap.txt" 2>&1 || true
  check "field: lines lost inside the interval: the same seconds, the gap named" eval 'fk_in "$R/inner-gap.txt" "^  Interval +STATS t 16-75, 60 s from 5 s after the mark at 20:01:01\.500; 57 lines$" && fk_in "$R/inner-gap.txt" "^  Data +1 STATS window of 2 s or more, 4 s of the interval \(the longest 4 s"'
  { sed -n '1,/ STATS t=40 /p' "$R/a.log"; for t in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70; do fk_st "$t" 60.0; done; } >"$R/device.log"
  "$SR" --mark 60 "$R/device.log" >"$R/device.txt" 2>&1 || true
  check "field: a second device before the interval ends: no interval" eval 'fk_in "$R/device.txt" "^  Interval +none: a second device started before the 60 s after the mark at 20:01:01\.500 ended$" && fk_in "$R/device.txt" "^  Data +.*no interval: a second device after the mark" && ! fk_in "$R/device.txt" "FPS: average"'

  # a return, then hidden again at once: the interval's hidden seconds named in Data
  { fk_head 0.1.7-dev.3 73511be "2026-11-01 20:00:00"
    for t in 1 2 3; do fk_st "$t" 60.0; done
    fk_vis 3 0; fk_st 4 30.0; fk_vis 0 3 20:00:04.500; fk_vis 3 0 20:00:05.000
    for t in $(seq 5 80); do fk_st "$t" 30.0; done
  } >"$R/flicker.log"
  "$SR" --mark 60 "$R/flicker.log" >"$R/flicker.txt" 2>&1 || true
  check "field: hidden seconds in the interval named" eval 'fk_in "$R/flicker.txt" "^  Data +60 s of the interval hidden or switching \(left out\)$" && ! fk_in "$R/flicker.txt" "FPS: average"'

  # 3. Gaps: a STATS window of 4 s, visibility lines d9mt suppressed, a second device
  { fk_head 0.1.7-dev.3 73511be "2026-11-01 20:00:00"
    for t in 1 2 3 4 5; do fk_st "$t" 60.0; done
    fk_st 9 15.0 66.0/2000.0/2000.0 1 1
    fk_vis 3 0; fk_st 10 30.0; fk_vis 0 3 20:00:10.000 ' [3 earlier lines suppressed]'
    for t in 11 12 13; do fk_st "$t" 60.0; done
    fk_st 1 60.0; fk_st 2 60.0
  } >"$R/gaps.log"
  "$SR" "$R/gaps.log" >"$R/gaps.txt" 2>&1 || true
  check "field: a gap between STATS lines" fk_in "$R/gaps.txt" '^  Data +.*1 STATS window of 2 s or more \(the longest 4 s'
  check "field: suppressed visibility lines" fk_in "$R/gaps.txt" '^  Data +.*3 visibility or throttle lines suppressed by d9mt'
  check "field: a second device" fk_in "$R/gaps.txt" '^  Data +.*a second device \(its seconds counted from 0 again\)'

  # 4. Ordinary play (Debug Logging off: no STATS) and a log without its start
  { fk_head 0.1.7-dev.3 73511be "2026-11-01 20:30:00" "debug-logging=off hud=on game-mode=on MTL_HUD_ENABLED=1"
    fk_vis 3 0; fk_vis 0 3; } >"$R/ordinary.log"
  "$SR" "$R/ordinary.log" >"$R/ordinary.txt" 2>&1 || true
  check "field: ordinary play has no frame times, says so" eval 'fk_in "$R/ordinary.txt" "^  Measurement +ordinary play \(Debug Logging off\): no frame times in the log, the Metal HUD only$" && ! fk_in "$R/ordinary.txt" "FPS: average|missing"'
  tail -n +6 "$R/a.log" >"$R/headless.log"
  "$SR" "$R/headless.log" >"$R/headless.txt" 2>&1 || true
  check "field: a log without its start says so" fk_in "$R/headless.txt" "^  Data +no SWTOR on Mac line at the start"

  # 5. A/B/A: A (73511be), B (another build, 2 fps more, less CPU), A again; the identity of each
  { fk_head 0.1.7-dev.4 9999999 "2026-11-01 20:10:00" "" fedcba987654; fk_arm 62.0 700; } >"$R/b.log"
  sed 's/started 2026-11-01 20:00:00/started 2026-11-01 20:20:00/; s/fps=60\.0 ms=16\.7/fps=59.0 ms=16.9/' "$R/a.log" >"$R/a2.log"
  "$SR" --mark 60 --compare "$R/a.log" "$R/b.log" "$R/a2.log" >"$R/aba.txt" 2>&1 || true
  check "field: each arm in a block of its own" eval 'fk_in "$R/aba.txt" "^  A: a\.log$" && fk_in "$R/aba.txt" "^  B: b\.log$" && fk_in "$R/aba.txt" "^  C: a2\.log$" && fk_in "$R/aba.txt" "^    SWTOR on Mac, Wine engine, d9mt +0\.1\.7-dev\.4 cx-26\.3\.0-8 d9mt 9999999$" && fk_in "$R/aba.txt" "^    Game start +2026-11-01 20:20:00$"'
  check "field: three columns" fk_in "$R/aba.txt" '^  FPS: average +60\.0 +62\.0 +59\.0$'
  check "field: A/B/A drift and B against the A mean" eval 'fk_in "$R/aba.txt" "^The last three as A/B/A \(A, B, C: a\.log, b\.log, a2\.log\):$" && fk_in "$R/aba.txt" "^  FPS: average +A 60\.0, A again 59\.0 \(drift -1\.00\); B 62\.0: \+2\.50 against the A mean \(\+4\.2%\)$" && fk_in "$R/aba.txt" "^  Process CPU \(PACE, ms/s, median\) +A 800, A again 800 \(drift \+0\.00\); B 700: -100\.00 against the A mean"'
  check "field: no significance claimed" fk_in "$R/aba.txt" 'one sitting: no significance test'
  "$SR" --mark 60 --compare "$R/a.log" "$R/b.log" "$R/b.log" >"$R/notaba.txt" 2>&1 || true
  check "field: first and last differ: not an A/B/A, no numbers" eval 'fk_in "$R/notaba.txt" "the first and the last differ in build: not an A/B/A" && ! fk_in "$R/notaba.txt" "drift"'
  "$SR" --mark 60 --compare "$R/a.log" "$R/ordinary.log" "$R/a2.log" >"$R/mixed.txt" 2>&1 || true
  check "field: an ordinary arm among instrumented ones" eval 'fk_in "$R/mixed.txt" "^  B \(ordinary\.log\): no frame times \(Debug Logging off\); the interval is not whole" && fk_in "$R/mixed.txt" "^  no A/B/A numbers" && ! fk_in "$R/mixed.txt" "drift"'
  # arms the A/B/A can't use: no wrapper lines (headless), no mark, a short one, a hidden one
  tail -n +6 "$R/a2.log" >"$R/a2-headless.log"
  "$SR" --mark 60 --compare "$R/headless.log" "$R/b.log" "$R/a2-headless.log" >"$R/unknown-aba.txt" 2>&1 || true
  check "field: arms without build, settings or files: no numbers" eval 'fk_in "$R/unknown-aba.txt" "^  A \(headless\.log\): no build, settings, d9mt_files line \(a log before 0\.1\.7, or its start is missing\)$" && fk_in "$R/unknown-aba.txt" "^  C \(a2-headless\.log\): no build, settings, d9mt_files line" && ! fk_in "$R/unknown-aba.txt" "drift"'
  "$SR" --mark 60 --compare "$R/a.log" "$R/nomark.log" "$R/a2.log" >"$R/nomark-aba.txt" 2>&1 || true
  check "field: an arm without a mark: no numbers" eval 'fk_in "$R/nomark-aba.txt" "^  B \(nomark\.log\): the interval is not whole \(Interval: the whole session: no mark" && ! fk_in "$R/nomark-aba.txt" "drift"'
  "$SR" --mark 75 --compare "$R/a.log" "$R/b.log" "$R/a2.log" >"$R/short-aba.txt" 2>&1 || true
  check "field: short arms: no numbers" eval 'fk_in "$R/short-aba.txt" "^  A \(a\.log\): the interval is not whole \(Interval: STATS t 16-85, 70 s of the 75 asked" && ! fk_in "$R/short-aba.txt" "drift"'
  sed 's/^warn:  STATS t=40 /warn:  MtlPresenter: 20:01:40.000 visibility 0x3 -> 0x0 (visible=0 activeSpace=0 miniaturized=0)\
warn:  STATS t=40 /' "$R/b.log" >"$R/b-hidden.log"
  "$SR" --mark 60 --compare "$R/a.log" "$R/b-hidden.log" "$R/a2.log" >"$R/hidden-aba.txt" 2>&1 || true
  check "field: an arm hidden in its interval: no numbers" eval 'fk_in "$R/hidden-aba.txt" "^  B \(b-hidden\.log\): the interval is not whole .*of the interval hidden or switching" && ! fk_in "$R/hidden-aba.txt" "drift"'
  # the d9mt files not verified: the wrapper's "unknown" (its deadline) in both A arms, a
  # missing file in B; the build's "?"
  sed 's/^SWTOR on Mac d9mt files: .*/SWTOR on Mac d9mt files: unknown/' "$R/a.log" >"$R/a-unknown.log"
  sed 's/^SWTOR on Mac d9mt files: .*/SWTOR on Mac d9mt files: unknown/' "$R/a2.log" >"$R/a2-unknown.log"
  sed 's/^SWTOR on Mac d9mt files: .*/SWTOR on Mac d9mt files: d3d9.dll missing, winemetal.so ba9876543210/' "$R/b.log" >"$R/b-missing.log"
  "$SR" --mark 60 --compare "$R/a-unknown.log" "$R/b-missing.log" "$R/a2-unknown.log" >"$R/unverified-aba.txt" 2>&1 || true
  check "field: d9mt files unknown or missing: not verified, no numbers" eval 'fk_in "$R/unverified-aba.txt" "^  A \(a-unknown\.log\): the d9mt files not verified \(unknown\)$" && fk_in "$R/unverified-aba.txt" "^  B \(b-missing\.log\): the d9mt files not verified \(d3d9\.dll missing, winemetal\.so ba9876543210\)$" && fk_in "$R/unverified-aba.txt" "^  C \(a2-unknown\.log\): the d9mt files not verified" && fk_in "$R/unverified-aba.txt" "^  FPS: average +60\.0 +62\.0 +59\.0$" && ! fk_in "$R/unverified-aba.txt" "drift"'
  sed 's/^SWTOR on Mac 0\.1\.7-dev\.4: engine cx26 cx-26\.3\.0-8, d9mt 9999999,/SWTOR on Mac ?: engine cx26 cx-26.3.0-8, d9mt ?,/' "$R/b.log" >"$R/b-nobuild.log"
  "$SR" --mark 60 --compare "$R/a.log" "$R/b-nobuild.log" "$R/a2.log" >"$R/nobuild-aba.txt" 2>&1 || true
  check "field: a build named ?: not known, no numbers" eval 'fk_in "$R/nobuild-aba.txt" "^  B \(b-nobuild\.log\): the build not known" && ! fk_in "$R/nobuild-aba.txt" "drift"'
  # --skip with --mark: refused (the skip would take seconds out of the interval unseen)
  t=0; "$SR" --skip 60 --mark 60 --compare "$R/a.log" "$R/b.log" "$R/a2.log" >"$R/skip-mark.txt" 2>&1 || t=$?
  check "field: --skip with --mark refused ($t)" eval '[ "$t" = 2 ] && fk_in "$R/skip-mark.txt" "^--skip and --mark don.t go together" && ! fk_in "$R/skip-mark.txt" "drift"'

  # a zero baseline: no relative change, the difference in percentage points
  sed 's/fps=62\.0 ms=16\.7\/17\.0\/17\.5/fps=50.0 ms=20.0\/21.0\/21.0/' "$R/b.log" >"$R/b-slow.log"
  "$SR" --mark 60 --compare "$R/a.log" "$R/b-slow.log" "$R/a2.log" >"$R/zero-aba.txt" 2>&1 || true
  check "field: a zero A mean: relative n/a, percentage points" fk_in "$R/zero-aba.txt" '^  Seconds below 58 fps \(%\) +A 0\.0, A again 0\.0 \(drift \+0\.00 pp\); B 100\.0: \+100\.00 pp against the A mean \(relative: n/a, the A mean is 0\)$'
  "$SR" --mark 60 --compare "$R/nomark.log" "$R/a.log" "$R/a.log" "$R/b.log" "$R/a2.log" >"$R/five.txt" 2>&1 || true
  check "field: five sessions, the A/B/A over the last three, an arm without a mark named" eval 'fk_in "$R/five.txt" "^The last three as A/B/A \(C, D, E: a\.log, b\.log, a2\.log\):$" && fk_in "$R/five.txt" "^  FPS: average +60\.0 +60\.0 +60\.0 +62\.0 +59\.0$" && fk_in "$R/five.txt" "^    Data +no mark$"'
  "$SR" --mark 60 --compare "$R/a.log" "$R/a.log" "$R/a2.log" >"$R/aa.txt" 2>&1 || true
  check "field: B the same as A: an A/A" fk_in "$R/aa.txt" 'B ran the same build, d9mt files, switches and settings as A: an A/A'
  check "field: six sessions refused" eval '! "$SR" --compare "$R/a.log" "$R/a.log" "$R/a.log" "$R/a.log" "$R/a.log" "$R/a.log" >/dev/null 2>&1'

  # (a long steady session: 9000 seconds of the same numbers; the sort before the heapsort
  # recursed once per equal value and crashed awk)
  { fk_head 0.1.7-dev.3 73511be "2026-11-01 17:00:00"; for t in $(seq 1 9000); do fk_st "$t" 60.0; done; } >"$R/long.log"
  "$SR" "$R/long.log" >"$R/long.txt" 2>&1 || true
  check "field: a 2.5-hour steady session" eval 'fk_in "$R/long.txt" "^  FPS: median second +60\.0$" && ! grep -q "Segmentation\|awk:" "$R/long.txt"'

  # 5b. The display limit (d9mt's SCREEN-INFO, Debug Logging only): "?" until AppKit answered,
  # then 30 fps, in Low Power Mode, Wine's display mode not known (hz=0.0: the SCREEN lines' 60
  # is d9mt's fallback, not read). The FPS read against 28, not 58: 3 of 20 seconds below it. A
  # limit of 60 keeps the 58, with Wine's mode when SCREEN-INFO has it; one that changes, also to
  # "?" or 0 and back, says so and keeps it too, and so does a log without its start. No
  # SCREEN-INFO (an older d9mt): no display limit.
  fk_info() { printf 'warn:  SCREEN-INFO displaySync=1 drawables=3 interval=1 cap=off hz=%s %s nsFullscreen=0 d3dWindowed=0 forceComposited=0\n' "${2:-0.0}" "$1"; }
  { fk_head 0.1.9 9b64581 "2026-11-02 20:00:00" "" "" "low power"
    fk_info "screenMaxFps=? refreshInterval=?"; fk_scr 1 60
    fk_info "screenMaxFps=30 refreshInterval=33.3-33.3"
    for t in $(seq 1 20); do fk_st "$t" "$([ "$t" -le 3 ] && echo 20.0 || echo 30.0)" 33.3/34.0/35.0; fk_scr "$t" 60; done
  } >"$R/limit30.log"
  "$SR" "$R/limit30.log" >"$R/limit30.txt" 2>&1 || true
  check "field: the display limit and the energy mode side by side, no mode from d9mt's fallback" fk_in "$R/limit30.txt" "^  Display limit +30 fps \(macOS; energy mode low power\)$"
  check "field: at a limit of 30 the seconds below 28 fps, not 58" eval 'fk_in "$R/limit30.txt" "^  Seconds below the display limit \(%\) +15\.0 \(below 28 fps\)$" && ! fk_in "$R/limit30.txt" "below 58 fps"'
  sed 's/hz=0\.0 screenMaxFps=30 refreshInterval=33\.3-33\.3/hz=60.0 screenMaxFps=60 refreshInterval=16.7-16.7/; s/energy mode low power/energy mode automatic/' "$R/limit30.log" >"$R/limit60.log"
  "$SR" "$R/limit60.log" >"$R/limit60.txt" 2>&1 || true
  check "field: a limit of 60: named with Wine's mode, the seconds below 58 fps kept" eval 'fk_in "$R/limit60.txt" "^  Display limit +60 fps \(macOS; Wine.s display mode 60 Hz; energy mode automatic\)$" && fk_in "$R/limit60.txt" "^  Seconds below 58 fps \(%\) +100\.0$" && ! fk_in "$R/limit60.txt" "below the display limit"'
  sed 's/screenMaxFps=? refreshInterval=?/screenMaxFps=60 refreshInterval=16.7-16.7/' "$R/limit30.log" >"$R/limit-changed.log"
  "$SR" "$R/limit-changed.log" >"$R/limit-changed.txt" 2>&1 || true
  check "field: a limit that changed: both values, the seconds below 58 fps kept" eval 'fk_in "$R/limit-changed.txt" "^  Display limit +30 fps \(macOS; it changed while the game ran: 60, 30; energy mode low power\)$" && fk_in "$R/limit-changed.txt" "^  Seconds below 58 fps \(%\) +100\.0$"'
  # 30, not known (0: a window without a screen), 30 again: not one limit all through
  { sed -n '1,/ STATS t=10 /p' "$R/limit30.log"; fk_info "screenMaxFps=0 refreshInterval=0.0-0.0"; fk_st 11 20.0
    fk_info "screenMaxFps=30 refreshInterval=33.3-33.3"; sed -n '/ STATS t=12 /,$p' "$R/limit30.log"; } >"$R/limit-gap.log"
  "$SR" "$R/limit-gap.log" >"$R/limit-gap.txt" 2>&1 || true
  check "field: a limit not known in between: named, the seconds below 58 fps kept" eval 'fk_in "$R/limit-gap.txt" "^  Display limit +30 fps \(macOS; it changed while the game ran: 30, \?, 30; energy mode low power\)$" && fk_in "$R/limit-gap.txt" "^  Seconds below 58 fps \(%\) +100\.0$"'
  # a second before macOS gave the limit (AppKit answers later than the first STATS line), and a
  # cut log (Collect Logs keeps the wrapper's lines and the end): only the seconds after the limit
  { fk_head 0.1.9 9b64581 "2026-11-02 20:00:00" "" "" "low power"
    fk_info "screenMaxFps=? refreshInterval=?"; fk_st 1 20.0
    fk_info "screenMaxFps=30 refreshInterval=33.3-33.3"
    for t in $(seq 2 20); do fk_st "$t" "$([ "$t" -le 3 ] && echo 20.0 || echo 30.0)" 33.3/34.0/35.0; done
  } >"$R/limit-late.log"
  "$SR" "$R/limit-late.log" >"$R/limit-late.txt" 2>&1 || true
  check "field: a second before the limit is known: left out of its count, named with the limit" eval 'fk_in "$R/limit-late.txt" "^  Seconds below the display limit \(%\) +10\.5 \(below 28 fps\)$" && fk_in "$R/limit-late.txt" "^  Display limit +30 fps \(macOS; energy mode low power; 1 shown STATS seconds before the first recorded limit not counted below it\)$"'
  # (with an SM3 hazard line among them, whose parser has counters of its own)
  { cat "$R/limit-late.log"; echo "warn:  D3D9 SM3 hazard: ps_0123 PS crs-partial-mask:r2.yz packed-io:v1 swizzle:x"; } >"$R/limit-sm3.log"
  "$SR" "$R/limit-sm3.log" >"$R/limit-sm3.txt" 2>&1 || true
  check "field: an SM3 hazard line doesn't change the count below the limit" eval 'fk_in "$R/limit-sm3.txt" "^  Seconds below the display limit \(%\) +10\.5 \(below 28 fps\)$" && fk_in "$R/limit-sm3.txt" "^  SM3 shaders"'
  { fk_head 0.1.9 9b64581 "2026-11-02 20:00:00" "" "" "low power"; echo "[SWTOR on Mac: only the last 5 MB of wine.log]"
    for t in 1 2 3 4 5; do fk_st "$t" 20.0; done
    fk_info "screenMaxFps=30 refreshInterval=33.3-33.3"
    for t in $(seq 6 20); do fk_st "$t" 30.0 33.3/34.0/35.0; done
  } >"$R/limit-cut.log"
  "$SR" "$R/limit-cut.log" >"$R/limit-cut.txt" 2>&1 || true
  check "field: a cut log: only the seconds after the limit it kept" eval 'fk_in "$R/limit-cut.txt" "^  Seconds below the display limit \(%\) +0\.0 \(below 28 fps\)$" && fk_in "$R/limit-cut.txt" "^  Display limit +30 fps \(macOS; energy mode low power; 5 shown STATS seconds before the first recorded limit not counted below it\)$"'
  # Wine's mode not known any more at the last SCREEN-INFO: not named
  { cat "$R/limit60.log"; fk_info "screenMaxFps=60 refreshInterval=16.7-16.7"; fk_st 21 30.0; } >"$R/limit-nomode.log"
  "$SR" "$R/limit-nomode.log" >"$R/limit-nomode.txt" 2>&1 || true
  check "field: Wine's mode unknown at the end: not named" fk_in "$R/limit-nomode.txt" '^  Display limit +60 fps \(macOS; energy mode automatic\)$'
  tail -n +6 "$R/limit30.log" >"$R/limit-headless.log"
  "$SR" "$R/limit-headless.log" >"$R/limit-headless.txt" 2>&1 || true
  check "field: a log without its start: the limit named, the seconds below 58 fps kept" eval 'fk_in "$R/limit-headless.txt" "^  Display limit +30 fps \(macOS\)$" && fk_in "$R/limit-headless.txt" "^  Seconds below 58 fps \(%\) +100\.0$"'
  check "field: no SCREEN-INFO: no display limit rows" eval '! fk_in "$R/a.txt" "Display limit|below the display limit"'
  "$SR" --compare "$R/a.log" "$R/limit30.log" >"$R/limit-compare.txt" 2>&1 || true
  check "field: compared with an unlimited session: the limit in its arm's block, each its own row of seconds" eval 'fk_in "$R/limit-compare.txt" "^    Display limit +30 fps \(macOS; energy mode low power\)$" && [ "$(grep -c "Display limit" "$R/limit-compare.txt")" = 1 ] && fk_in "$R/limit-compare.txt" "^  Seconds below 58 fps \(%\) +[0-9.]+ +n/a$" && fk_in "$R/limit-compare.txt" "^  Seconds below the display limit \(%\) +n/a +15\.0 \(below 28 fps\)$"'

  # 6. The wrapper's lines, its functions on stand-ins: no path, no home folder
  local fns="$R/wrapper-fns.sh" pm="$R/pmset" sc="$R/sysctl" pfx="$R/prefix" eng="$R/engine" line
  sed -n '/^session_settings() {/,/^}/p; /^session_conditions() {/,/^}/p; /^file_hashes() {/,/^}/p; /^d9mt_files() {/p; /^session_diag() {/,/^}/p' "$wrapper" >"$fns"
  cat >"$pm" <<'PM'
#!/bin/bash
case "$*" in
  "-g ps") echo "Now drawing from 'Battery Power'" ;;
  "-g therm") echo "Note: No thermal warning level has been recorded"; echo "CPU_Speed_Limit 	= 80" ;;
  "-g") printf 'Currently in use:\n powermode            1\n' ;;
esac
PM
  # (a sysctl stand-in that has every source, and one on a Mac without the pressure level and
  # free percentage: macOS's sysctl names an unknown one on stderr, goes on with the next and
  # exits 1; it prints swap with the locale's decimal separator)
  cat >"$sc" <<'SC'
#!/bin/bash
rc=0 d=.
[ "${LC_ALL:-}" = C ] || d=,
for o in "$@"; do
  case "$o:${FK_SYSCTL_MISSING:-}" in
    kern.memorystatus_vm_pressure_level:) echo "$o: 2" ;;
    kern.memorystatus_level:) echo "$o: 23" ;;
    vm.swapusage:*) echo "$o: total = 3072${d}00M  used = 1536${d}25M  free = 1535${d}75M  (encrypted)" ;;
    *) echo "sysctl: unknown oid '$o'" >&2; rc=1 ;;
  esac
done
exit $rc
SC
  chmod 755 "$pm" "$sc"
  mkdir -p "$pfx/drive_c/windows/system32" "$eng/lib/wine/x86_64-unix"
  printf 'd9mt' >"$pfx/drive_c/windows/system32/d3d9.dll"
  line=$(env -i PATH=/usr/bin:/bin HOME="$HOME" D9MT_PROFILE=1 MTL_HUD_ENABLED=1 SWTOR_GAMEMODE_APP="$HOME/x/SWTOR.app" \
    D9MT_AIR_CACHE="$HOME/Library/Caches/x" D9MT_DEBUG_FILE='C:\d9mt\flags.txt' DXVK_CONFIG='d3d9.presentInterval=0;d3d9.x=1' \
    LANG=de_DE.UTF-8 SWTOR_PMSET="$pm" SWTOR_SYSCTL="$sc" SWTOR_PREFIX="$pfx" SWTOR_ENGINE="$eng" /bin/bash -c '. "$1"; session_settings; session_conditions; d9mt_files' - "$fns" 2>&1)
  printf '%s\n' "$line" >"$R/wrapper-lines.txt"
  check "wrapper: the settings line, paths left out" eval 'fk_in "$R/wrapper-lines.txt" "^debug-logging=on hud=on game-mode=on native-fullscreen=off D9MT_AIR_CACHE=\(a path\) D9MT_DEBUG_FILE=\(a path\) D9MT_PROFILE=1 DXVK_CONFIG=d3d9\.presentInterval=0;d3d9\.x=1 MTL_HUD_ENABLED=1$" && ! grep -qF "$HOME" "$R/wrapper-lines.txt"'
  check "wrapper: the conditions line (swap read in the C locale under a German one)" fk_in "$R/wrapper-lines.txt" '^power Battery Power, energy mode low power, thermal warnings CPU_Speed_Limit = 80, memory pressure warning \(23 % free\), swap 1536 MB used of 3072 MB$'
  line=$(env -i PATH=/usr/bin:/bin HOME="$HOME" FK_SYSCTL_MISSING=1 SWTOR_PMSET="$pm" SWTOR_SYSCTL="$sc" /bin/bash -c '. "$1"; session_conditions' - "$fns" 2>&1)
  check "wrapper: a Mac without the pressure level: unknown, swap still read ($line)" eval '[ "$line" = "power Battery Power, energy mode low power, thermal warnings CPU_Speed_Limit = 80, memory pressure unknown, swap 1536 MB used of 3072 MB" ]'
  line=$(env -i PATH=/usr/bin:/bin HOME="$HOME" SWTOR_PMSET="$pm" SWTOR_SYSCTL="$R/no-sysctl" /bin/bash -c '. "$1"; session_conditions' - "$fns" 2>&1)
  check "wrapper: no sysctl: memory unknown, the rest of the line kept ($line)" eval '[ "$line" = "power Battery Power, energy mode low power, thermal warnings CPU_Speed_Limit = 80, memory pressure unknown, swap unknown" ]'
  # this Mac's own sysctl, without sudo, as the wrapper calls it: every source read (on the
  # Checks runner's macOS), an unknown name among them doesn't stop the ones after it, and the
  # exit status is then 1
  # (its status from the pipeline: pipefail gives sysctl's, tr's is 0)
  local real rc=0
  real=$(LC_ALL=C /usr/sbin/sysctl kern.memorystatus_vm_pressure_level som.no.such.oid kern.memorystatus_level vm.swapusage 2>/dev/null | tr '\n' ';') || rc=$?
  check "wrapper: this Mac's sysctl gives the pressure level, free % and swap past an unknown name, status 1 ($real status $rc)" eval '[ "$rc" = 1 ] && printf "%s\n" "$real" | piped -E "^kern\.memorystatus_vm_pressure_level: [124];kern\.memorystatus_level: [0-9]+;vm\.swapusage: total = [0-9.]+[KMG] +used = [0-9.]+[KMG] "'
  line=$(env -i PATH=/usr/bin:/bin HOME="$HOME" LANG=de_DE.UTF-8 SWTOR_PMSET="$pm" /bin/bash -c '. "$1"; session_conditions' - "$fns" 2>&1)
  check "wrapper: the conditions line from this Mac's sysctl ($line)" eval 'printf "%s\n" "$line" | piped -E ", memory pressure (normal|warning|critical) \([0-9]+ % free\), swap [0-9]+ MB used of [0-9]+ MB$"'
  check "wrapper: the d9mt files' hashes, a missing one named" fk_in "$R/wrapper-lines.txt" "^d3d9\.dll $(printf d9mt | /usr/bin/shasum -a 256 | cut -c1-12), winemetal\.so missing$"
  check "wrapper: the lines go into wine.log after the language" eval 'grep -A4 "SWTOR on Mac game language:" "$wrapper" | piped "SWTOR on Mac settings: \$(session_settings)" && grep -A5 "SWTOR on Mac game language:" "$wrapper" | piped "SWTOR on Mac \${files%_files} files: \$diag_files"'
  check "wrapper: the bounded probes run before wine.log takes stderr" eval 'grep -B3 "rotate_wine_log\$" "$wrapper" | piped "session_diag \"\$files\" 2>/dev/null"'
  # a pmset that hangs, ignores TERM and has a child: the probes end at the deadline, as
  # unknown, the d9mt files still hashed, nothing of the stand-in left
  cat >"$R/slow-pmset" <<'PM'
#!/bin/bash
[ "$1" != --warm ] || exit 0
trap '' TERM
echo $$ >>"$(dirname "$0")/slow.pids"
/bin/sleep 30 &
echo $! >>"$(dirname "$0")/slow.pids"
wait
PM
  # (run once first: macOS's first look at a new executable can take longer than the deadline,
  # and the check would then not see the hang at all)
  chmod 755 "$R/slow-pmset"; "$R/slow-pmset" --warm; rm -f "$R/slow.pids"
  local t0 t1 left=""
  t0=$(date +%s)
  line=$(env -i PATH=/usr/bin:/bin HOME="$HOME" SWTOR_PMSET="$R/slow-pmset" SWTOR_SYSCTL="$sc" SWTOR_DIAG_TIMEOUT=1 SWTOR_PREFIX="$pfx" SWTOR_ENGINE="$eng" \
    /bin/bash -c '. "$1"; session_diag d9mt_files 2>/dev/null; echo "$diag_conditions|$diag_files"' - "$fns" 2>&1)
  t1=$(date +%s)
  sleep 0.3
  for p in $(cat "$R/slow.pids" 2>/dev/null); do kill -0 "$p" 2>/dev/null && left="$left $p"; done
  [ -z "$left" ] || kill -KILL $left 2>/dev/null
  printf '%s\n' "$line" >"$R/slow-diag.txt"
  # (the deadline is 1 s of 50 ms polls plus the 0.2 s TERM grace; a loaded Mac, such as a CI
  # runner, stretches the polls: 4 s seen there. The hang is 30 s, so 10 s still tells a bounded
  # probe from one that was waited for, with room for the load; the deadline itself is checked
  # below, by the waits it asks for)
  check "wrapper: a hanging pmset: unknown within the deadline ($((t1 - t0)) s, limit 10 s; the hang is 30 s), the files still hashed" eval 'fk_in "$R/slow-diag.txt" "^unknown\|d3d9\.dll [0-9a-f]{12}, winemetal\.so missing$" && [ $((t1 - t0)) -le 10 ]'
  check "wrapper: nothing of the hanging probe left${left:+ (left:$left)}" eval '[ -s "$R/slow.pids" ] && [ -z "$left" ]'
  # the deadline it sets itself, independent of the Mac's load: the same run with a sleep that
  # logs each wait it's asked for (then waits it); with SWTOR_DIAG_TIMEOUT=1 the waits add up to
  # the 1 s deadline plus the 0.2 s TERM grace, however long they really took
  mkdir -p "$R/sleep-log-bin"
  cat >"$R/sleep-log-bin/sleep" <<'SL'
#!/bin/bash
echo "$1" >>"$FK_SLEEP_LOG"
exec /bin/sleep "$@"
SL
  chmod 755 "$R/sleep-log-bin/sleep"; rm -f "$R/slow.pids" "$R/sleeps.txt"
  local asked
  env -i PATH="$R/sleep-log-bin:/usr/bin:/bin" FK_SLEEP_LOG="$R/sleeps.txt" HOME="$HOME" SWTOR_PMSET="$R/slow-pmset" SWTOR_SYSCTL="$sc" SWTOR_DIAG_TIMEOUT=1 SWTOR_PREFIX="$pfx" SWTOR_ENGINE="$eng" \
    /bin/bash -c '. "$1"; session_diag d9mt_files 2>/dev/null' - "$fns" >/dev/null 2>&1
  sleep 0.3
  for p in $(cat "$R/slow.pids" 2>/dev/null); do kill -0 "$p" 2>/dev/null && kill -KILL "$p" 2>/dev/null; done
  asked=$(awk '{ s += $1 } END { printf "%.2f", s }' "$R/sleeps.txt" 2>/dev/null)
  local in_budget
  # shellcheck disable=SC2034 # (used in the check's eval string)
  in_budget=$(awk -v s="${asked:-0}" 'BEGIN { print (s >= 1.1 && s <= 1.3) ? "yes" : "no" }')
  check "wrapper: a hanging pmset: the waits asked for add up to the deadline (${asked:-none} s for 1 s + 0.2 s)" eval '[ -s "$R/sleeps.txt" ] && [ "$in_budget" = yes ]'
  line=$(env -i PATH=/usr/bin:/bin HOME="$HOME" SWTOR_PMSET="$pm" SWTOR_SYSCTL="$sc" SWTOR_PREFIX="$pfx" SWTOR_ENGINE="$eng" \
    /bin/bash -c '. "$1"; session_diag d9mt_files 2>/dev/null; echo "$diag_conditions|$diag_files"' - "$fns" 2>&1)
  check "wrapper: the probes within the deadline give their lines" eval '[ "$line" = "power Battery Power, energy mode low power, thermal warnings CPU_Speed_Limit = 80, memory pressure warning (23 % free), swap 1536 MB used of 3072 MB|d3d9.dll $(printf d9mt | /usr/bin/shasum -a 256 | cut -c1-12), winemetal.so missing" ]'
  # a sysctl that hangs (the slow stand-in in its place): the same deadline
  rm -f "$R/slow.pids"; t0=$(date +%s)
  line=$(env -i PATH=/usr/bin:/bin HOME="$HOME" SWTOR_PMSET="$pm" SWTOR_SYSCTL="$R/slow-pmset" SWTOR_DIAG_TIMEOUT=1 SWTOR_PREFIX="$pfx" SWTOR_ENGINE="$eng" \
    /bin/bash -c '. "$1"; session_diag d9mt_files 2>/dev/null; echo "$diag_conditions|$diag_files"' - "$fns" 2>&1)
  t1=$(date +%s); sleep 0.3; left=""
  for p in $(cat "$R/slow.pids" 2>/dev/null); do kill -0 "$p" 2>/dev/null && left="$left $p"; done
  [ -z "$left" ] || kill -KILL $left 2>/dev/null
  check "wrapper: a hanging sysctl: unknown within the deadline ($((t1 - t0)) s, limit 10 s), nothing of it left${left:+ (left:$left)}" eval 'printf "%s\n" "$line" | piped -E "^unknown\|d3d9\.dll [0-9a-f]{12}, winemetal\.so missing$" && [ $((t1 - t0)) -le 10 ] && [ -s "$R/slow.pids" ] && [ -z "$left" ]'

  # 7. Collect Logs: three arms and an older start in one zip; the old start cut, its first
  # lines kept; an account name in a log line replaced; no home folder
  local H="$SWTOR_ON_MAC_ROOT/home" L som acct=Fkaccountsentinel z zd
  L="$H/Library/Logs/SWTOR on Mac"; som="$H/Library/Application Support/SWTOR on Mac"
  mkdir -p "$L" "$som/prefix/drive_c/users/u/AppData/Local/SWTOR/swtor/settings" "$R/zip"
  : >"$som/prefix/drive_c/users/u/AppData/Local/SWTOR/swtor/settings/${acct}_Account.ini"
  cp "$R/a.log" "$L/wine.log.2"; cp "$R/b.log" "$L/wine.log.1"; cp "$R/a2.log" "$L/wine.log"
  echo "warn:  something about $acct" >>"$L/wine.log.1"
  # the game's settings in the app's prefix (user crossover): client_settings.ini (CRLF, as the
  # game writes it) with its [Renderer] section, a value of another form, an account name, and a
  # [Game] section with paths; a per-account and a per-character file beside it
  local gs="$som/prefix/drive_c/users/crossover/AppData/Local/SWTOR/swtor/settings" gsi
  gsi="$gs/client_settings.ini"
  mkdir -p "$gs/GUIProfiles"
  printf '%s\r\n' '[Renderer]' 'GraphicsQuality = 3' 'ShaderSet = 2' 'doShadows = true' 'EnableBloom = false' \
    'EnableSSAO = true' 'AntiAliasingLevel = 4' 'Width = 1728' 'Height = 1117' 'FullScreen = true' \
    'InfoGraphicsVendor = Apple '"$acct" 'FkOdd = C:\users\crossover\FkOddSentinel' '' \
    '[Game]' 'MoviesFolder = C:\users\crossover\Videos\FkMoviesSentinel' 'SwtorRegKey = FkRegKeySentinel' >"$gsi"
  : >"$gs/${acct}_Account.ini"; : >"$gs/he4000_Fkcharsentinel_PlayerGUIState.ini"; : >"$gs/GUIProfiles/FkGuiSentinel.xml"
  # the DirectX 12 client's own client_settings_DX12.ini beside it, by the same rules: its
  # resolution in DX12_RenderWidth/Height, a path value, an account name and a [Game] section
  local gsd="$gs/client_settings_DX12.ini"
  printf '%s\r\n' '[Renderer]' 'DX12_RenderWidth = 2560' 'DX12_RenderHeight = 1440' 'GraphicsQuality = 2' \
    'Width = 1920' 'Height = 1080' 'InfoGraphicsVendor = Apple '"$acct" 'FkOdd = C:\users\crossover\FkDx12OddSentinel' '' \
    '[Game]' 'SwtorRegKey = FkDx12RegKeySentinel' >"$gsd"
  { fk_head 0.1.7-dev.2 1111111 "2026-11-01 19:00:00"
    LC_ALL=C awk 'BEGIN { for (t = 1; t <= 9000; t++) printf "warn:  STATS t=%d fps=60.0 ms=16.7/17.0/17.5 slow33=0 slow50=0 | rp=1.0 skip=0.0 cb=1.0 draws=1500 | ld=0.0 clr=0.0 ldDc=0.0 st=0.0 stDc=0.0 rsv=0.0 restore=0.0 savedMiB=0.0 attMs=0.1 clrFold=0.0 clrPass=0.0 | sh=0 pso=0 wait=0/0.0ms | allocMiB=100 att=on%400s\n", t, "" }'
  } >"$L/wine.log.3"
  z=$(SWTOR_SCREEN_LIMIT="30 33.3 33.3" SWTOR_SYSCTL="$sc" SWTOR_ON_MAC_GPU_TIMEOUT=5 SWTOR_ON_MAC_BTM_TIMEOUT=5 "$app/Contents/Resources/collect-logs.sh" "$R/zip" 2>"$R/collect.err" || true)
  zd="$R/unzipped"; rm -rf "$zd"; mkdir -p "$zd"
  [ -f "$z" ] && (cd "$zd" && unzip -q "$z")
  zd=$(ls -d "$zd"/SWTOR-on-Mac-logs-* 2>/dev/null | head -1 || true)
  check "collect: one zip" test -n "$zd"
  zd=${zd:-$R/none}
  check "collect: the kept starts side by side, the oldest first" eval 'fk_in "$zd/sessions-compared.txt" "^ +A: wine\.log\.3 +B: wine\.log\.2 +C: wine\.log\.1 +D: wine\.log$" && fk_in "$zd/sessions-compared.txt" "^    Game start +2026-11-01 19:00:00$"'
  check "collect: each arm's interval from the mark" fk_in "$zd/sessions-compared.txt" '^    Interval +STATS t 16-75, 60 s from 5 s after the mark at 20:01:01\.500; 60 lines$'
  check "collect: the last three as A/B/A" fk_in "$zd/sessions-compared.txt" '^The last three as A/B/A \(B, C, D: wine\.log\.2, wine\.log\.1, wine\.log\):$'
  check "collect: a cut log keeps the wrapper's first lines" eval 'head -1 "$zd/logs/wine.log.3" | piped -x "SWTOR on Mac 0.1.7-dev.2: engine cx26 cx-26.3.0-8, d9mt 1111111, started 2026-11-01 19:00:00" && sed -n 6p "$zd/logs/wine.log.3" | piped "^\[SWTOR on Mac: only the last 5 MB of wine.log.3\]$"'
  check "collect: the account name replaced in the logs and the comparison" eval '! grep -rqF "$acct" "$zd" && grep -q "something about ACCOUNT" "$zd/logs/wine.log.1"'
  check "collect: no home folder, nothing left out" eval '! grep -rqF "$HOME/" "$zd" && ! grep -rqF "$H/" "$zd" && [ ! -e "$zd/left-out.txt" ]'
  check "collect: the thermal warnings now" fk_in "$zd/system-info.txt" '^Thermal and performance warnings now \(pmset -g therm\): '
  check "collect: memory now, after the Mac" eval 'grep -A1 "^Mac: " "$zd/system-info.txt" | piped -x "Memory now (sysctl): pressure warning (23 % free), swap 1536 MB used of 3072 MB"'
  check "collect: the display limit the app passed, after the displays" eval 'grep -B1 "^Display limit now" "$zd/system-info.txt" | sed -n 1p | piped -E "^(Display: |Free space: )" && fk_in "$zd/system-info.txt" "^Display limit now \(macOS, the main screen\): 30 fps, refresh interval 33\.3-33\.3 ms$"'
  check "collect: the game's graphics settings: [Renderer] alone, redacted, the line of another form counted" eval '[ "$(cat "$zd/game-graphics-settings.txt")" = "$(printf "%s\n" "[Renderer]" "GraphicsQuality = 3" "ShaderSet = 2" "doShadows = true" "EnableBloom = false" "EnableSSAO = true" "AntiAliasingLevel = 4" "Width = 1728" "Height = 1117" "FullScreen = true" "InfoGraphicsVendor = Apple ACCOUNT" "(1 lines of another form left out)")" ]'
  check "collect: nothing else of the settings folder: no [Game], no other file or its name" eval '! LC_ALL=C grep -r -q -e FkOddSentinel -e FkMoviesSentinel -e FkRegKeySentinel -e MoviesFolder -e SwtorRegKey -e "\[Game\]" -e Fkcharsentinel -e FkGuiSentinel -e PlayerGUIState "$zd" && [ "$(cd "$zd" && find . -name "*.ini" -o -name "*.xml" -o -name GUIProfiles)" = "" ]'
  check "collect: system info names the main graphics settings, a missing one as missing" fk_in "$zd/system-info.txt" '^Game graphics settings \(client_settings\.ini \[Renderer\], all of it in game-graphics-settings\.txt\): GraphicsQuality=3, ShaderSet=2, doShadows=true, EnableBloom=false, EnableSSAO=true, AntiAliasingLevel=4, Width=1728, Height=1117, FullScreen=true, D3DFullScreen=missing$'
  check "collect: the DirectX 12 client's graphics settings: [Renderer] alone, redacted, the line of another form counted" eval '[ "$(cat "$zd/game-graphics-settings-dx12.txt")" = "$(printf "%s\n" "[Renderer]" "DX12_RenderWidth = 2560" "DX12_RenderHeight = 1440" "GraphicsQuality = 2" "Width = 1920" "Height = 1080" "InfoGraphicsVendor = Apple ACCOUNT" "(1 lines of another form left out)")" ]'
  check "collect: nothing else of client_settings_DX12.ini" eval '! LC_ALL=C grep -r -q -e FkDx12OddSentinel -e FkDx12RegKeySentinel "$zd"'
  check "collect: system info names the DirectX 12 client's main graphics settings, its resolution first" fk_in "$zd/system-info.txt" '^Game graphics settings, DirectX 12 \(client_settings_DX12\.ini \[Renderer\], all of it in game-graphics-settings-dx12\.txt\): DX12_RenderWidth=2560, DX12_RenderHeight=1440, GraphicsQuality=2, ShaderSet=missing, doShadows=missing, EnableBloom=missing, EnableSSAO=missing, AntiAliasingLevel=missing, Width=1920, Height=1080, FullScreen=missing, D3DFullScreen=missing$'
  rm -f "$L/wine.log.3" "$L/wine.log.2" "$L/wine.log.1"; mkdir -p "$R/zip1"
  printf '%s\r\n' '[Game]' 'SwtorRegKey = FkRegKeySentinel' >"$gsi"
  printf '%s\r\n' '[Game]' 'SwtorRegKey = FkDx12RegKeySentinel' >"$gsd"
  # (the last start now one whose display limit changed: its whole line through the redaction)
  cp "$R/limit-changed.log" "$L/wine.log"
  z=$(FK_SYSCTL_MISSING=1 SWTOR_SYSCTL="$sc" SWTOR_ON_MAC_GPU_TIMEOUT=5 SWTOR_ON_MAC_BTM_TIMEOUT=5 "$app/Contents/Resources/collect-logs.sh" "$R/zip1" 2>>"$R/collect.err" || true)
  check "collect: one start, no comparison" eval '[ -f "$z" ] && ! unzip -l "$z" | piped sessions-compared.txt'
  check "collect: not run by the app: the display limit not known" eval 'unzip -p "$z" "*/system-info.txt" | piped -x "Display limit now: not known (Collect Logs ran without the app, which reads it)"'
  check "collect: a Mac without the pressure level: unknown, swap still read" eval 'unzip -p "$z" "*/system-info.txt" | piped -x "Memory now (sysctl): pressure unknown, swap 1536 MB used of 3072 MB"'
  check "collect: a display limit that changed, whole after the redaction" eval 'unzip -p "$z" "*/session-report.txt" | piped -E "^  Display limit +30 fps \(macOS; it changed while the game ran: 60, 30; energy mode low power\)$"'
  check "collect: no [Renderer] section: one line, no settings file" eval '[ -f "$z" ] && ! unzip -l "$z" | piped game-graphics-settings && unzip -p "$z" "*/system-info.txt" | piped -x "Game graphics settings: none (no \[Renderer\] section in client_settings.ini)"'
  check "collect: no [Renderer] section in client_settings_DX12.ini: one line" eval '[ -f "$z" ] && unzip -p "$z" "*/system-info.txt" | piped -x "Game graphics settings, DirectX 12: none (no \[Renderer\] section in client_settings_DX12.ini)"'
  rm -f "$gsd"
  rm -f "$gsi"; mkdir -p "$R/zip2"
  z=$(SWTOR_SCREEN_LIMIT="30 33.3 33.3
junk" SWTOR_ON_MAC_GPU_TIMEOUT=5 SWTOR_ON_MAC_BTM_TIMEOUT=5 "$app/Contents/Resources/collect-logs.sh" "$R/zip2" 2>>"$R/collect.err" || true)
  check "collect: no client_settings.ini: one line, the zip still made" eval '[ -f "$z" ] && ! unzip -l "$z" | piped game-graphics-settings && unzip -p "$z" "*/system-info.txt" | piped -x "Game graphics settings: none (no client_settings.ini in the app.s prefix)"'
  check "collect: no client_settings_DX12.ini: one line" eval '[ -f "$z" ] && unzip -p "$z" "*/system-info.txt" | piped -x "Game graphics settings, DirectX 12: none (no client_settings_DX12.ini in the app.s prefix)"'
  check "collect: a display limit with more than its one line: not used" eval 'unzip -p "$z" "*/system-info.txt" | piped -x "Display limit now: not known (not in the form the app passes)"'
  check "collect: this Mac's sysctl: memory now read" eval 'unzip -p "$z" "*/system-info.txt" | piped -E "^Memory now \(sysctl\): pressure (normal|warning|critical) \([0-9]+ % free\), swap [0-9]+ MB used of [0-9]+ MB$"'
}
