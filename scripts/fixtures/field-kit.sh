# shellcheck shell=bash
# Fixture group field-kit (scripts/test-fixtures.sh only): what a before/after field test reads.
# session-report.sh on made-up logs: frame times over 200 ms, the session's p99 and true 1% low
# reported as missing, the measurement (instrumented or ordinary play), the interval after the
# mark (--mark), gaps and suppressed lines, a log without its start, 3 to 5 sessions side by
# side and the A/B/A over the last three; the wrapper's settings, conditions and d9mt files lines
# on stand-ins; Collect Logs on planted logs: one zip with every kept game start side by side,
# each start's first lines kept when its log is cut, and no account name, home folder or path in
# what this adds. Needs neither the official app nor Wine. Sourced; check, piped and the counters
# come from lib.sh.
#
#   fx_field_kit <app> <wine-wrapper.sh> <folder>

# fk_st <t> <fps> [<ms avg/p99/max> <slow33> <slow50>]: a STATS line; fk_vis <from> <to> [at]: a
# visibility change; fk_hitch <ms>: a HITCH line; fk_head <version> <d9mt> <started> [settings]:
# the wrapper's lines at the start
fk_st() {
  printf 'warn:  STATS t=%s fps=%s ms=%s slow33=%s slow50=%s | rp=1.0 skip=0.0 cb=1.0 draws=1500 | ld=0.0 clr=0.0 ldDc=0.0 st=0.0 stDc=0.0 rsv=0.0 restore=0.0 savedMiB=0.0 attMs=0.1 clrFold=0.0 clrPass=0.0 | sh=0 pso=0 wait=0/0.0ms | allocMiB=100 att=on\n' \
    "$1" "$2" "${3:-16.7/17.0/17.5}" "${4:-0}" "${5:-0}"
}
fk_vis() { printf 'warn:  MtlPresenter: %s visibility 0x%s -> 0x%s (visible=0 activeSpace=0 miniaturized=0)%s\n' "${3:-20:00:00.000}" "$1" "$2" "${4:-}"; }
fk_hitch() { printf 'warn:  HITCH frame=1 dtMs=%s inD9mtMs=1.0 (1%%) texMiB created=0.0 uploaded=0.0 csBehind=0 | texCreate=1/1.0ms/0.0MiB | cs: renderWait=0/0.0ms shaders=0/0.0ms psos=0/0.0ms\n' "$1"; }
fk_pace() { printf 'warn:  PACE t=%s n=60 present=15.2/16.7/18.4 sd=0.61 | d9mt=4.1/5.0/7.9 wait=1.2 game=9.0/11.7/13.0 | cpu=%s d9mtBusy=230 gameCpu=582\n' "$1" "$2"; }
fk_head() {
  echo "SWTOR on Mac $1: engine cx26 cx-26.3.0-8, d9mt $2, started $3"
  echo "SWTOR on Mac game language: lang=en-us torsets=main,en-us, LANG=en_US.UTF-8"
  echo "SWTOR on Mac settings: ${4:-debug-logging=on hud=on game-mode=on D9MT_PROFILE=1 MTL_HUD_ENABLED=1}"
  echo "SWTOR on Mac conditions: power AC Power, energy mode automatic, thermal warnings none"
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
  check "field: the start's build, settings, conditions and files" eval 'fk_in "$R/a.txt" "^  Game start +2026-11-01 20:00:00$" && fk_in "$R/a.txt" "^  Settings at the start +debug-logging=on hud=on game-mode=on D9MT_PROFILE=1" && fk_in "$R/a.txt" "^  Power, thermal at the start +power AC Power, energy mode automatic, thermal warnings none$" && fk_in "$R/a.txt" "^  d9mt files \(SHA-256\) +d3d9\.dll 0123456789ab, winemetal\.so ba9876543210$"'
  check "field: no mark asked, the whole session, nothing lost" eval 'fk_in "$R/a.txt" "^  Interval +the whole session$" && fk_in "$R/a.txt" "^  Data +nothing left out or lost$"'

  # 2. --mark: 60 s from 5 s after the return (in second 11, the one STATS t=11 closes): seconds
  # 16-75, the loading and the
  # hitch before the mark left out
  "$SR" --mark 60 "$R/a.log" >"$R/a-mark.txt" 2>&1 || true
  check "field: the interval after the mark" fk_in "$R/a-mark.txt" '^  Interval +STATS seconds 16-75 \(60 lines\), from 5 s after the mark at 20:01:01\.500$'
  check "field: only the interval's seconds and frames" eval 'fk_in "$R/a-mark.txt" "^  Seconds with STATS lines +60$" && fk_in "$R/a-mark.txt" "^  Frames +3600$" && fk_in "$R/a-mark.txt" "^  Frame time: worst \(ms\) +17\.5$"'
  check "field: no hitch from before the mark" fk_in "$R/a-mark.txt" '^  Hitches \(frames over 50 ms\) +0$'
  check "field: PACE seconds of the interval only" fk_in "$R/a-mark.txt" '^  PACE seconds +60$'
  "$SR" --mark 100 "$R/a.log" >"$R/a-short.txt" 2>&1 || true
  check "field: a short interval says so" eval 'fk_in "$R/a-short.txt" "^  Interval +STATS seconds 16-85 \(70 lines of the 100 asked: the session ended\)" && fk_in "$R/a-short.txt" "^  Data +the interval is short$"'
  { fk_head 0.1.7-dev.3 73511be "2026-11-01 20:00:00"; for t in 1 2 3 4 5; do fk_st "$t" 60.0; done; } >"$R/nomark.log"
  "$SR" --mark 60 "$R/nomark.log" >"$R/nomark.txt" 2>&1 || true
  check "field: no mark: the whole session, and Data says so" eval 'fk_in "$R/nomark.txt" "^  Interval +the whole session: no mark" && fk_in "$R/nomark.txt" "^  Data +no mark$"'

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
  check "field: A/B/A drift and B against the A mean" eval 'fk_in "$R/aba.txt" "^The last three as A/B/A \(A, B, C: a\.log, b\.log, a2\.log\):$" && fk_in "$R/aba.txt" "^  FPS: average +A 60\.0, A again 59\.0 \(drift -1\.00\); B 62\.0: \+2\.50 against the A mean \(\+4\.2%\)$" && fk_in "$R/aba.txt" "^  Game thread CPU \(ms/s, median\) +A 800, A again 800 \(drift \+0\.00\); B 700: -100\.00 against the A mean"'
  check "field: no significance claimed" fk_in "$R/aba.txt" 'one sitting: no significance test'
  "$SR" --mark 60 --compare "$R/a.log" "$R/b.log" "$R/b.log" >"$R/notaba.txt" 2>&1 || true
  check "field: first and last differ: not an A/B/A, no numbers" eval 'fk_in "$R/notaba.txt" "the first and the last differ in build: not an A/B/A" && ! fk_in "$R/notaba.txt" "drift"'
  "$SR" --mark 60 --compare "$R/a.log" "$R/ordinary.log" "$R/a2.log" >"$R/mixed.txt" 2>&1 || true
  check "field: an ordinary arm among instrumented ones" eval 'fk_in "$R/mixed.txt" "the arms differ in Measurement" && ! fk_in "$R/mixed.txt" "drift"'
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

  # 6. The wrapper's lines, its functions on stand-ins: no path, no home folder
  local fns="$R/wrapper-fns.sh" pm="$R/pmset" pfx="$R/prefix" eng="$R/engine" line
  sed -n '/^session_settings() {/,/^}/p; /^session_conditions() {/,/^}/p; /^d9mt_files() {/,/^}/p' "$wrapper" >"$fns"
  cat >"$pm" <<'PM'
#!/bin/bash
case "$*" in
  "-g ps") echo "Now drawing from 'Battery Power'" ;;
  "-g therm") echo "Note: No thermal warning level has been recorded"; echo "CPU_Speed_Limit 	= 80" ;;
  "-g") printf 'Currently in use:\n powermode            1\n' ;;
esac
PM
  chmod 755 "$pm"
  mkdir -p "$pfx/drive_c/windows/system32" "$eng/lib/wine/x86_64-unix"
  printf 'd9mt' >"$pfx/drive_c/windows/system32/d3d9.dll"
  line=$(env -i PATH=/usr/bin:/bin HOME="$HOME" D9MT_PROFILE=1 MTL_HUD_ENABLED=1 SWTOR_GAMEMODE_APP="$HOME/x/SWTOR.app" \
    D9MT_AIR_CACHE="$HOME/Library/Caches/x" D9MT_DEBUG_FILE='C:\d9mt\flags.txt' DXVK_CONFIG='d3d9.presentInterval=0;d3d9.x=1' \
    SWTOR_PMSET="$pm" SWTOR_PREFIX="$pfx" SWTOR_ENGINE="$eng" /bin/bash -c '. "$1"; session_settings; session_conditions; d9mt_files' - "$fns" 2>&1)
  printf '%s\n' "$line" >"$R/wrapper-lines.txt"
  check "wrapper: the settings line, paths left out" eval 'fk_in "$R/wrapper-lines.txt" "^debug-logging=on hud=on game-mode=on D9MT_AIR_CACHE=\(a path\) D9MT_DEBUG_FILE=\(a path\) D9MT_PROFILE=1 DXVK_CONFIG=d3d9\.presentInterval=0;d3d9\.x=1 MTL_HUD_ENABLED=1$" && ! grep -qF "$HOME" "$R/wrapper-lines.txt"'
  check "wrapper: the conditions line" fk_in "$R/wrapper-lines.txt" '^power Battery Power, energy mode low power, thermal warnings CPU_Speed_Limit = 80$'
  check "wrapper: the d9mt files' hashes, a missing one named" fk_in "$R/wrapper-lines.txt" "^d3d9\.dll $(printf d9mt | /usr/bin/shasum -a 256 | cut -c1-12), winemetal\.so missing$"
  check "wrapper: the lines go into wine.log after the language" eval 'grep -A3 "SWTOR on Mac game language:" "$wrapper" | grep -q "SWTOR on Mac settings: \$(session_settings)" && grep -q "SWTOR on Mac d9mt files: \$(d9mt_files)" "$wrapper"'

  # 7. Collect Logs: three arms and an older start in one zip; the old start cut, its first
  # lines kept; an account name in a log line replaced; no home folder
  local H="$SWTOR_ON_MAC_ROOT/home" L som acct=Fkaccountsentinel z zd
  L="$H/Library/Logs/SWTOR on Mac"; som="$H/Library/Application Support/SWTOR on Mac"
  mkdir -p "$L" "$som/prefix/drive_c/users/u/AppData/Local/SWTOR/swtor/settings" "$R/zip"
  : >"$som/prefix/drive_c/users/u/AppData/Local/SWTOR/swtor/settings/${acct}_Account.ini"
  cp "$R/a.log" "$L/wine.log.2"; cp "$R/b.log" "$L/wine.log.1"; cp "$R/a2.log" "$L/wine.log"
  echo "warn:  something about $acct" >>"$L/wine.log.1"
  { fk_head 0.1.7-dev.2 1111111 "2026-11-01 19:00:00"
    LC_ALL=C awk 'BEGIN { for (t = 1; t <= 9000; t++) printf "warn:  STATS t=%d fps=60.0 ms=16.7/17.0/17.5 slow33=0 slow50=0 | rp=1.0 skip=0.0 cb=1.0 draws=1500 | ld=0.0 clr=0.0 ldDc=0.0 st=0.0 stDc=0.0 rsv=0.0 restore=0.0 savedMiB=0.0 attMs=0.1 clrFold=0.0 clrPass=0.0 | sh=0 pso=0 wait=0/0.0ms | allocMiB=100 att=on%400s\n", t, "" }'
  } >"$L/wine.log.3"
  z=$(SWTOR_ON_MAC_GPU_TIMEOUT=5 SWTOR_ON_MAC_BTM_TIMEOUT=5 "$app/Contents/Resources/collect-logs.sh" "$R/zip" 2>"$R/collect.err" || true)
  zd="$R/unzipped"; rm -rf "$zd"; mkdir -p "$zd"
  [ -f "$z" ] && (cd "$zd" && unzip -q "$z")
  zd=$(ls -d "$zd"/SWTOR-on-Mac-logs-* 2>/dev/null | head -1 || true)
  check "collect: one zip" test -n "$zd"
  zd=${zd:-$R/none}
  check "collect: the kept starts side by side, the oldest first" eval 'fk_in "$zd/sessions-compared.txt" "^ +A: wine\.log\.3 +B: wine\.log\.2 +C: wine\.log\.1 +D: wine\.log$" && fk_in "$zd/sessions-compared.txt" "^    Game start +2026-11-01 19:00:00$"'
  check "collect: each arm's interval from the mark" fk_in "$zd/sessions-compared.txt" '^    Interval +STATS seconds 16-75 \(60 lines\), from 5 s after the mark at 20:01:01\.500$'
  check "collect: the last three as A/B/A" fk_in "$zd/sessions-compared.txt" '^The last three as A/B/A \(B, C, D: wine\.log\.2, wine\.log\.1, wine\.log\):$'
  check "collect: a cut log keeps the wrapper's first lines" eval 'head -1 "$zd/logs/wine.log.3" | grep -qx "SWTOR on Mac 0.1.7-dev.2: engine cx26 cx-26.3.0-8, d9mt 1111111, started 2026-11-01 19:00:00" && sed -n 6p "$zd/logs/wine.log.3" | grep -q "^\[SWTOR on Mac: only the last 5 MB of wine.log.3\]$"'
  check "collect: the account name replaced in the logs and the comparison" eval '! grep -rqF "$acct" "$zd" && grep -q "something about ACCOUNT" "$zd/logs/wine.log.1"'
  check "collect: no home folder, nothing left out" eval '! grep -rqF "$HOME/" "$zd" && ! grep -rqF "$H/" "$zd" && [ ! -e "$zd/left-out.txt" ]'
  check "collect: the thermal warnings now" fk_in "$zd/system-info.txt" '^Thermal and performance warnings now \(pmset -g therm\): '
  rm -f "$L/wine.log.3" "$L/wine.log.2" "$L/wine.log.1"; mkdir -p "$R/zip1"
  z=$(SWTOR_ON_MAC_GPU_TIMEOUT=5 SWTOR_ON_MAC_BTM_TIMEOUT=5 "$app/Contents/Resources/collect-logs.sh" "$R/zip1" 2>>"$R/collect.err" || true)
  check "collect: one start, no comparison" eval '[ -f "$z" ] && ! unzip -l "$z" | grep -q sessions-compared.txt'
}
