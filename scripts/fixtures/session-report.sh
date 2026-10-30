# shellcheck shell=bash
# Fixture group session-report (scripts/test-sandbox.sh section 6f): the packaged
# session-report.sh on a sample log with the lines of d9mt 6fa5df7. Needs neither the official
# app nor Wine. Sourced; check and its counters come from lib.sh.
#
#   fx_session_report <session-report.sh> <folder for the sample logs and the report>
# has <text>: the report has it (a name of its own: a check on a pipe uses piped)
has() { grep -qF -- "$1" "$R/report.txt"; }
fx_session_report() {
  REPORT_SH=$1 R=$2
  mkdir -p "$R"
  cat >"$R/wine.log" <<'LOG'
SWTOR on Mac 0.1.1-dev.1: engine cx26 cx-26.3.0-8, d9mt 6fa5df7, started 2026-10-18 20:00:00
SWTOR on Mac d9mt-ab: pfv vsync-off
SWTOR on Mac frame rate limit: 30 fps (only on battery: on battery)
warn:  D9MT: 20:00:01.100 frame cap 30 fps: timer, cadence 33.33 ms (vsync off)
info:  Found config env: d3d9.presentInterval=0
info:  D9MT: PixelFormatView on every texture (D9MT_TEX_PFV=1): no lossless compression
info:  D9MT: end-of-pass barrier before Fragment|Blit|Dispatch, vertex fences for vertex textures
info:  D9MT: a clear that ends a pass skips the pass's store of what it clears
warn:  D3D9 SM3 hazard: ps_1a2b PS crs-partial-mask:r2.yz
warn:  D3D9 SM3 hazard: vs_3c4d VS packed-io:o1.xy=texcoord0+o1.zw=texcoord1 crs-partial-mask:r1.y
info:  STATECACHE load path=/x/d9mt/state/swtor.exe.d9mtstate status=ok entries=40 session=2 prewarmable=39 readyAtLoad=0 corrupt=0 truncated=0 invalid=1 (first: layout stride) capped=0 max=1024 guard=tripped threads=2 ms=3.8
warn:  STATECACHE the last session ended while prewarm builds were running (crash, kill, or exit without releasing the device; 1 in a row): dropped 2 in-flight entries, kept the rest
info:  STATECACHE prewarm t=0.83s built=37 dup=1 failed=1 skipped=0 buildMs=991 pausedMs=201
warn:  STATS t=1 fps=60.0 ms=16.7/18.0/21.4 slow33=0 slow50=0 | rp=31.4 skip=2.1 cb=13.0 draws=1520 | ld=12.1 clr=9.0 ldDc=4.0 st=15.2 stDc=6.0 rsv=0.0 restore=0.0 savedMiB=231.4 attMs=1.3 clrFold=6.0 clrPass=1.0 | sh=0 pso=0 wait=0/0.0ms | allocMiB=5210 att=on | split=8.0 splitSubmit=6.0 splitXfer=0.0 splitClear=2.0 splitMiB=420.0
info:  XFER t=1 | stretch copy=2 resolve=0 blit=5 (scaled=5 linear=4 convert=1 msaa=0) skip=0 | fill rt=1 rect=1 bc=0 skip=0
warn:  STATS t=2 fps=60.0 ms=16.7/18.0/21.4 slow33=0 slow50=0 | rp=31.4 skip=2.1 cb=13.0 draws=1520 | ld=12.1 clr=9.0 ldDc=4.0 st=15.2 stDc=6.0 rsv=0.0 restore=0.0 savedMiB=231.4 attMs=1.3 clrFold=6.0 clrPass=1.0 | sh=0 pso=0 wait=0/0.0ms | allocMiB=5210 att=on | split=4.0 splitSubmit=2.0 splitXfer=0.0 splitClear=2.0 splitMiB=100.0
info:  XFER t=2 | stretch copy=1 resolve=0 blit=0 (scaled=0 linear=0 convert=0 msaa=0) skip=1 | fill rt=0 rect=0 bc=2 skip=0
info:  STATECACHE use t=60s hits=37 late=1 misses=2 recorded=3 unrecorded=0 ringDrops=0 hitBuildMs=991 | prewarm built=37 dup=1 failed=1 skipped=0 buildMs=991 pausedMs=201 boosts=1 ready=0 | entries=42 invalid=0 (final)
info:  STATECACHE write entries=42 bytes=16128 ms=1.7
LOG
  rpt=$("$REPORT_SH" "$R/wine.log" 2>&1 || true)
  printf '%s\n' "$rpt" >"$R/report.txt"
  check "report: the A/B switches" grep -qE '^  A/B switches \(d9mt-ab\.sh\) +pfv vsync-off$' "$R/report.txt"
  check "report: the GPU path" has "lossless compression off (D9MT_TEX_PFV=1), narrow pass barrier, clears skip stores"
  check "report: DXVK_CONFIG" has "d3d9.presentInterval=0"
  check "report: the Frame Rate Limit" grep -qE '^  Frame Rate Limit +30 fps \(only on battery: on battery\)$' "$R/report.txt"
  check "report: d9mt's frame cap" grep -qE "^    d9mt's frame cap +30 fps: timer, cadence 33\.33 ms \(vsync off\)$" "$R/report.txt"
  check "report: pass splits (frame-weighted)" has "6.0 (4.0 with a submit), 260 MiB loaded again"
  check "report: state cache loaded" has "ok, 40 entries, 39 to prewarm, 1 invalid dropped"
  check "report: prewarm" has "built 37, failed 1, skipped 0, done 0.8 s after the start (991 ms of builds, paused 201 ms)"
  check "report: what the game needed" has "hits 37, late 1, misses 2 (build time saved 991 ms), 3 new recorded, 1 prewarms sped up"
  check "report: the guard" has "the last session ended while prewarm builds were running"
  check "report: written" has "42 entries, 15 KB"
  check "report: StretchRect by path, summed" has "copy 3, resolve 0, blit 5 (scaled 5, linear 4, convert 1, msaa 0), left alone 1 (2 seconds with any)"
  check "report: ColorFill by path" has "render target 1, part 1, block-compressed 2, left alone 0"
  check "report: SM3 hazards" has "2 shaders (crs-partial-mask, packed-io)"
  echo 'info:  XFER-SUMMARY | stretch copy=9 resolve=1 blit=5 (scaled=5 linear=4 convert=1 msaa=0) skip=1 | fill rt=1 rect=1 bc=2 skip=3' >>"$R/wine.log"
  echo 'info:  STATECACHE off (D9MT_STATE_CACHE=0)' >"$R/off.log"
  check "report: XFER-SUMMARY when the device was released" eval '"$REPORT_SH" "$R/wine.log" | grep -F "copy 9, resolve 1, blit 5 (scaled 5, linear 4, convert 1, msaa 0), left alone 1 (session total)" >/dev/null'
  check "report: state cache off" eval '"$REPORT_SH" "$R/off.log" | grep -F "off (D9MT_STATE_CACHE=0)" >/dev/null'
  check "report: --compare with both" eval '"$REPORT_SH" --compare "$R/wine.log" "$R/off.log" | grep "Pipeline state cache.*ok, 40 entries.*off (D9MT_STATE_CACHE=0)" >/dev/null'
  check "report: no visibility lines, every second counts" eval '! has "window hidden" && ! has "with the hidden seconds" && grep -qE "^  FPS: average +60\.0$" "$R/report.txt"'
  fx_session_report_visibility
}

# The frame rate over the seconds the window showed the game: d9mt's "MtlPresenter: ...
# visibility" lines between the STATS lines, 1 s around each change left out too.
# fx_sr_st <t> <fps> [<ms avg/p99/max> <slow33> <slow50>]: a STATS line
fx_sr_st() {
  printf 'warn:  STATS t=%s fps=%s ms=%s slow33=%s slow50=%s | rp=1.0 skip=0.0 cb=1.0 draws=1500 | ld=0.0 clr=0.0 ldDc=0.0 st=0.0 stDc=0.0 rsv=0.0 restore=0.0 savedMiB=0.0 attMs=0.1 clrFold=0.0 clrPass=0.0 | sh=0 pso=0 wait=0/0.0ms | allocMiB=100 att=on\n' \
    "$1" "$2" "${3:-16.7/17.0/17.5}" "${4:-0}" "${5:-0}"
}
fx_sr_vis() { printf 'warn:  MtlPresenter: 20:00:00.000 visibility 0x%s -> 0x%s (visible=0 activeSpace=0 miniaturized=0)%s\n' "$1" "$2" "${3:-}"; }
fx_sr_hitch() { echo 'warn:  HITCH frame=1 dtMs=70.0 inD9mtMs=1.0 (1%) texMiB created=0.0 uploaded=0.0 csBehind=0 | texCreate=1/1.0ms/0.0MiB | cs: renderWait=0/0.0ms shaders=0/0.0ms psos=0/0.0ms'; }
fx_session_report_visibility() {
  local t
  # 1-4 shown; 5 the second before the change; 6 the change (Cmd-Tab: 0x3 -> 0x2 -> 0x0);
  # 7-8 hidden; 9 back (0x0 -> 0x1 -> 0x3); 10 the second after; 11-14 shown
  {
    for t in 1 2 3 4; do fx_sr_st "$t" 60.0; done
    fx_sr_st 5 59.0
    fx_sr_vis 3 2; fx_sr_vis 2 0
    fx_sr_st 6 40.0 25.0/120.0/120.0 3 3
    fx_sr_hitch
    fx_sr_st 7 30.0; fx_sr_st 8 30.0
    fx_sr_vis 0 1; fx_sr_vis 1 3
    fx_sr_st 9 31.0; fx_sr_st 10 45.0; fx_sr_st 11 60.0; fx_sr_st 12 60.0
    fx_sr_hitch
    fx_sr_st 13 50.0 20.0/70.0/70.0 1 1; fx_sr_st 14 60.0
  } >"$R/visibility.log"
  "$REPORT_SH" "$R/visibility.log" >"$R/visibility.txt" 2>&1 || true
  check "report: every second in the total" grep -qE '^  Seconds with STATS lines +14$' "$R/visibility.txt"
  check "report: the hidden seconds, their own line" grep -qE '^    window hidden or switching +6 s, not counted below \(39\.2 fps\)$' "$R/visibility.txt"
  check "report: the average over the shown seconds" grep -qE '^  FPS: average +58\.8$' "$R/visibility.txt"
  check "report: the average over all seconds" grep -qE '^    with the hidden seconds +50\.4$' "$R/visibility.txt"
  check "report: frames of the shown seconds" grep -qE '^  Frames +470$' "$R/visibility.txt"
  check "report: below 58 of the shown seconds" grep -qE '^  Seconds below 58 fps \(%\) +12\.5$' "$R/visibility.txt"
  check "report: the worst frame time of the shown seconds" grep -qE '^  Frame time: worst \(ms\) +70\.0$' "$R/visibility.txt"
  check "report: frames over 50 ms in the shown seconds" grep -qE '^  Frames over 50 ms +1$' "$R/visibility.txt"
  check "report: hitches in the shown seconds" grep -qE '^  Hitches \(frames over 50 ms\) +1$' "$R/visibility.txt"
  # 1-2 hidden from the start (the first line's "from" tells it); 3 the change; 4-7 at 50 fps
  # before a line whose "from" isn't the state (the limiter left lines out: unknown, hidden);
  # 13 before a second device whose first state (hidden) only the next line's "from" tells
  {
    fx_sr_st 1 30.0; fx_sr_st 2 30.0
    fx_sr_vis 0 3
    fx_sr_st 3 60.0
    for t in 4 5 6 7; do fx_sr_st "$t" 50.0; done
    fx_sr_vis 0 3 ' [2 earlier lines suppressed]'
    for t in 8 9 10 11 12 13; do fx_sr_st "$t" 60.0; done
    fx_sr_st 1 50.0; fx_sr_st 2 50.0; fx_sr_st 3 50.0
    fx_sr_vis 0 3
    for t in 4 5 6 7; do fx_sr_st "$t" 60.0; done
  } >"$R/visibility-gaps.log"
  "$REPORT_SH" "$R/visibility-gaps.log" >"$R/visibility-gaps.txt" 2>&1 || true
  check "report: hidden from the start, lines left out, a second device" \
    grep -qE '^    window hidden or switching +15 s, not counted below \(51\.3 fps\)$' "$R/visibility-gaps.txt"
  check "report: only the shown seconds after them" eval 'grep -qE "^  FPS: average +60\.0$" "$R/visibility-gaps.txt" && grep -qE "^  Frames +300$" "$R/visibility-gaps.txt"'
  check "report: --skip leaves out hidden seconds, too" eval '"$REPORT_SH" --skip 6 "$R/visibility.log" | grep -E "^    window hidden or switching +4 s, not counted below \(34\.0 fps\)$" >/dev/null'
  { fx_sr_st 1 30.0; fx_sr_vis 3 0; fx_sr_st 2 30.0; } >"$R/all-hidden.log"
  "$REPORT_SH" "$R/all-hidden.log" >"$R/all-hidden.txt" 2>&1 || true
  check "report: all seconds hidden, no frame rate" eval 'grep -qE "^    window hidden or switching +2 s, not counted below \(30\.0 fps\)$" "$R/all-hidden.txt" && ! grep -q "FPS: average" "$R/all-hidden.txt"'
}
