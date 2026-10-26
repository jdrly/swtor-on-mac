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
}
