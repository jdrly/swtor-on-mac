# shellcheck shell=bash
# Fixture group session-report-dx12 (scripts/test-fixtures.sh only): session-report.sh on a
# DirectX 12 session. The Mullion log is a copy of my fork's tests/swtor/fixtures/session.log
# (mullion-session.log; its first line names the commit it came from) behind the wrapper's lines:
# the renderer from Mullion's header, frame rows from its STATS, a hitch the driver's by
# inDriverMs, the footprint and swap from DIAG MEM, the removed device, GPU error and stuck
# command buffer. Then made-up logs: the failed shader and late pipeline totals, a session
# without Mullion's header, D3DMetal, d9mt's GPU lines, a session on different renderers side by
# side, and an A/B/A of Mullion arms by the driver files line. Needs neither the official app nor
# Wine. Sourced; check and the counters come from lib.sh.
#
#   fx_session_report_dx12 <session-report.sh> <mullion-session.log> <folder>

# sdx_head <DirectX 12 line> [driver files]: the wrapper's lines at the start of a DirectX 12 session
sdx_head() {
  echo "SWTOR on Mac 0.1.8-dev.1: engine cx26 cx-26.3.0-8, d9mt f5439a6, started 2026-11-14 20:00:00"
  echo "SWTOR on Mac DirectX 12: $1"
  echo "SWTOR on Mac game language: lang=en-us torsets=main,en-us, LANG=en_US.UTF-8"
  echo "SWTOR on Mac settings: debug-logging=on hud=on game-mode=on MULLION_STATS=1"
  echo "SWTOR on Mac conditions: power AC Power, energy mode automatic, thermal warnings none"
  echo "SWTOR on Mac d9mt files: d3d9.dll 0123456789ab, winemetal.so ba9876543210"
  echo "SWTOR on Mac driver files: ${2:-d3d12.dll 00112233aabb, winemetal.so ccddeeff0011}"
}
SDX_MULLION="swtor_RC2.exe, driver mullion (dxgi=dxmt), MULLION_SESSION_HEADER=1, MULLION_STATS=1, MULLION_MEMSTATS=1, Mullion (jdrly/mullion 0009110), v0.5-alpha.3-118-g1a2b3c4, codegen airconv 103"
# sdx_st <t>: a Mullion STATS line; sdx_hitch <inDriverMs> <categories>: a 70 ms HITCH line
sdx_st() { printf 'warn:  STATS t=%s fps=60.0 ms=16.7/70.0/70.0 slow33=1 slow50=1 | cb=3.0 rp=12.0 cp=2.0 draws=850 | sh=0 pso=0 wait=0/0.0ms cache=0/0 | allocMiB=2000 | at=20:00:0%s.000\n' "$1" "$1"; }
sdx_hitch() { printf 'warn:  HITCH frame=60 dtMs=70.0 inDriverMs=%s | %s | queue: gpuMs=9.8 encodeMs=2.3 behind=2 | at=20:00:01.500\n' "$1" "$2"; }
# sdx_in <file> <regex>: a line of the report matches (grep -E)
sdx_in() { grep -qE -- "$2" "$1"; }

fx_session_report_dx12() {
  local SR=$1 fixture=$2 R=$3
  mkdir -p "$R"

  # 1. The fork's sample session: the identity, the frame rows, the hitches, memory and failures
  { sdx_head "$SDX_MULLION"; sed 1d "$fixture"; } >"$R/mullion.log"
  "$SR" "$R/mullion.log" >"$R/mullion.txt" 2>&1 || true
  check "dx12 report: the fixture is the fork's, its commit named" eval 'head -1 "$fixture" | grep -qE "^# jdrly/mullion tests/swtor/fixtures/session\.log at [0-9a-f]{7,}" && sed -n 2p "$fixture" | grep -q " Mullion: session "'
  check "dx12 report: the renderer from Mullion's header" sdx_in "$R/mullion.txt" '^  Renderer +DirectX 12 on Mullion v0\.5-alpha\.3-118-g1a2b3c4 \(jdrly/mullion\), Apple10, Metal 4 on, feature level 12_1, macOS 26\.1 \(25B78\)$'
  check "dx12 report: instrumented by Mullion's STATS" sdx_in "$R/mullion.txt" "^  Measurement +instrumented: Debug Logging on \(Mullion's MULLION_STATS\)"
  check "dx12 report: the frame rows from Mullion's STATS" eval 'sdx_in "$R/mullion.txt" "^  Seconds with STATS lines +60$" && sdx_in "$R/mullion.txt" "^  Frames +3425$" && sdx_in "$R/mullion.txt" "^  FPS: average +57\.1$" && sdx_in "$R/mullion.txt" "^  Compiles +404 shaders, 162 pipelines$" && sdx_in "$R/mullion.txt" "^  Memory peak \(Metal, MiB\) +2400$"'
  check "dx12 report: the 70 ms pipeline wait Mullion's, the 120 ms frame the game's" eval 'sdx_in "$R/mullion.txt" "^    Mullion.s +1 \(37% of hitch time\)$" && sdx_in "$R/mullion.txt" "^    the game.s +1 \(63% of hitch time\)$" && sdx_in "$R/mullion.txt" "^    top Mullion causes +pipelineWait 39 ms$"'
  check "dx12 report: the process footprint and the swap from DIAG MEM" eval 'sdx_in "$R/mullion.txt" "^  Process footprint peak \(MiB\) +4010$" && sdx_in "$R/mullion.txt" "^  Swap used, peak \(MiB\) +0$"'
  check "dx12 report: the removed device, the GPU error and the stuck command buffer" eval 'sdx_in "$R/mullion.txt" "^  Device removed +DXGI_ERROR_DEVICE_HUNG\(0x887a0006\), cause gpu-error, frame 3601$" && sdx_in "$R/mullion.txt" "^  GPU errors \(command buffers\) +1 \(the first: PageFault\(3\)\)$" && sdx_in "$R/mullion.txt" "^  Stuck command buffers \(GPU hung\) +1 \(the first: status scheduled\(3\) after 10000 ms; Mullion went on waiting\)$"'
  check "dx12 report: no visibility from Mullion, said under Data" sdx_in "$R/mullion.txt" "^  Data +the driver doesn't report window visibility: every second counts as shown; no mark$"
  check "dx12 report: the driver files" sdx_in "$R/mullion.txt" '^  Driver files \(SHA-256\) +d3d12\.dll 00112233aabb, winemetal\.so ccddeeff0011$'
  check "dx12 report: no d9mt rows for a Mullion session" eval '! grep -E "d9mt.s|Attachment|re-clears|skipped \(no-op\)|GPU work lost" "$R/mullion.txt" >/dev/null'

  # 2. A 70 ms hitch: Mullion's with a 40 ms pipeline wait, the game's with none
  { sdx_head "$SDX_MULLION"; sdx_st 1; sdx_hitch "40.0 (57%)" "pipelineWait=1/40.0ms present=1/1.4ms"; sdx_st 2; } >"$R/hitch-driver.log"
  { sdx_head "$SDX_MULLION"; sdx_st 1; sdx_hitch "0.4 (1%)" none; sdx_st 2; } >"$R/hitch-game.log"
  "$SR" "$R/hitch-driver.log" >"$R/hitch-driver.txt" 2>&1 || true
  "$SR" "$R/hitch-game.log" >"$R/hitch-game.txt" 2>&1 || true
  check "dx12 report: a 70 ms hitch with pipelineWait=1/40.0ms is Mullion's" eval 'sdx_in "$R/hitch-driver.txt" "^    Mullion.s +1 \(100% of hitch time\)$" && sdx_in "$R/hitch-driver.txt" "^    the game.s +0 \(0% of hitch time\)$"'
  check "dx12 report: a 70 ms hitch with none is the game's" eval 'sdx_in "$R/hitch-game.txt" "^    Mullion.s +0 \(0% of hitch time\)$" && sdx_in "$R/hitch-game.txt" "^    the game.s +1 \(100% of hitch time\)$" && sdx_in "$R/hitch-game.txt" "^    top Mullion causes +-$"'

  # 3. Failed shaders at the end, late pipelines at each queue's release (summed)
  { cat "$R/mullion.log"
    echo 'info:  MULLION-PIPELINE-TOTALS late=12 ms=412.3 longestMs=88.1'
    echo 'info:  MULLION-PIPELINE-TOTALS late=3 ms=40.0 longestMs=20.5'
    echo 'warn:  MULLION-SHADER-TOTALS failed=3 byStep=convert:2,metal:1 skippedDraws=41 dumped=3'; } >"$R/totals.log"
  "$SR" "$R/totals.log" >"$R/totals.txt" 2>&1 || true
  check "dx12 report: failed shaders and late pipelines" eval 'sdx_in "$R/totals.txt" "^  Failed shaders +3 failed \(convert:2,metal:1\), 41 draws skipped, 3 dumped$" && sdx_in "$R/totals.txt" "^  Late pipelines +15 made after the first Present, 452 ms in all, the longest 88\.1 ms$"'
  check "dx12 report: no failed shader or late pipeline rows without their lines" eval '! grep -E "Failed shaders|Late pipelines" "$R/mullion.txt" >/dev/null'

  # 4. Mullion without its header (Debug Logging off): the wrapper's line names the build
  sdx_head "$SDX_MULLION" >"$R/plain.log"
  "$SR" "$R/plain.log" >"$R/plain.txt" 2>&1 || true
  { cat "$R/plain.log"; echo '0124:warn:threadcpu:trace_thread_cpu THREADCPU 1.00 s: process 701 ms (16 threads), wineserver 21 ms; busiest (ms): 0130 610, 0134 66'; } >"$R/threadcpu.log"
  check "dx12 report: Mullion with the Mac driver's THREADCPU only: not credited to MULLION_STATS" eval '"$SR" "$R/threadcpu.log" | grep -E "^  Measurement +instrumented: Debug Logging on \(the Mac driver.s THREADCPU\)" >/dev/null'
  check "dx12 report: Mullion without its header, the wrapper's build" eval 'sdx_in "$R/plain.txt" "^  Renderer +DirectX 12 on Mullion \(jdrly/mullion 0009110\), v0\.5-alpha\.3-118-g1a2b3c4, codegen airconv 103 \(driver mullion; no session header" && sdx_in "$R/plain.txt" "^  Measurement +ordinary play \(Debug Logging off\)" && sdx_in "$R/plain.txt" "^  \(no STATS lines: Debug Logging was off \(Mullion.s MULLION_STATS\)" && ! grep -q "Attachment optimization" "$R/plain.txt"'

  # 5. D3DMetal: named, and no numbers to read
  sdx_head "swtor_RC2.exe, driver gptk (dxgi=gptk), D3DMetal 4.0b3 (imported: Evaluation environment for Windows games 4.0 beta 3)" >"$R/gptk.log"
  "$SR" "$R/gptk.log" >"$R/gptk.txt" 2>&1 || true
  { cat "$R/gptk.log"; sed -n '$p' "$R/threadcpu.log"; } >"$R/gptk-threadcpu.log"
  check "dx12 report: D3DMetal with the Mac driver's THREADCPU: not credited to d9mt" eval '"$SR" "$R/gptk-threadcpu.log" | grep -E "^  Measurement +instrumented: Debug Logging on \(the Mac driver.s THREADCPU\)" >/dev/null'
  check "dx12 report: D3DMetal named, and that it logs no numbers" eval 'sdx_in "$R/gptk.txt" "^  Renderer +DirectX 12 on D3DMetal 4\.0b3 \(imported: Evaluation environment for Windows games 4\.0 beta 3\) \(driver gptk\): the driver logs no numbers$" && sdx_in "$R/gptk.txt" "^  Measurement +ordinary play: D3DMetal logs no frame times" && sdx_in "$R/gptk.txt" "^  \(no STATS lines: D3DMetal logs no frame numbers"'

  # 6. DirectX 9 on d9mt: its build, its GPU lines (d9mt writes the error and hang lines with no
  # Wine prefix), and a DirectX 12 start that fell back to swtor.exe
  { echo "SWTOR on Mac 0.1.7: engine cx26 cx-26.3.0-8, d9mt 73511be, started 2026-11-14 21:00:00"
    sdx_st 1 | sed 's/ | cb=3\.0 rp=12\.0 cp=2\.0 draws=850 | / | rp=1.0 skip=0.0 cb=1.0 draws=1500 | ld=0.0 restore=0.0 savedMiB=0.0 | /'
    echo 'warn:  HITCH frame=60 dtMs=70.0 inD9mtMs=40.0 (57%) texMiB created=0.0 uploaded=0.0 csBehind=0 | texCreate=1/40.0ms/0.0MiB | cs: renderWait=0/0.0ms shaders=0/0.0ms psos=0/0.0ms'
    echo 'D9MT-GPU-ERROR 21:00:05.120 PageFault (3): Caused GPU Address Fault Error gpu=1.000-2.000 now=3.000 commits=41'
    echo 'D9MT-GPU-ERROR 21:00:05.130 Timeout (2): timed out gpu=1.000-2.000 now=3.000 commits=42 [2 earlier lines suppressed]'
    echo 'err:   D9MT-GPU-LOST: command buffer 812 (frame 60, present) did not run to its end: the GPU discarded it; 1 this session'
    echo 'err:   D9MT-GPU-LOST: 24 more command buffers did not run to their end in the last 10 s; 25 this session'
    echo 'D9MT-GPU-HUNG: serial 900 not signalled after 10 s on the GPU (completed 899, submitted 900): the GPU stopped and its queue won'"'"'t recover; ending the game (exit code 55769; D9MT_GPU_HUNG=continue keeps it running)'
  } >"$R/d9mt.log"
  "$SR" "$R/d9mt.log" >"$R/d9mt.txt" 2>&1 || true
  check "dx12 report: a DirectX 9 session names d9mt" sdx_in "$R/d9mt.txt" '^  Renderer +DirectX 9 on d9mt 73511be$'
  check "dx12 report: d9mt's GPU error, lost and hang lines" eval 'sdx_in "$R/d9mt.txt" "^  GPU errors \(command buffers\) +4 \(the first: PageFault \(3\)\)$" && sdx_in "$R/d9mt.txt" "^  GPU work lost \(d9mt.s canary\) +25 command buffers$" && sdx_in "$R/d9mt.txt" "^  Stuck command buffers \(GPU hung\) +1 \(the first: d9mt ended the game\)$" && sdx_in "$R/d9mt.txt" "^    d9mt.s +1 \(100% of hitch time\)$"'
  { sed -n 1p "$R/d9mt.log"; echo "SWTOR on Mac DirectX 12: swtor_RC2.exe not found next to swtor.exe: starting swtor.exe"; sed 1d "$R/d9mt.log"; } >"$R/fallback.log"
  check "dx12 report: swtor_RC2.exe not found, swtor.exe started: DirectX 9" eval '"$SR" "$R/fallback.log" | grep -E "^  Renderer +DirectX 9 on d9mt 73511be$" >/dev/null'

  # 7. Different renderers side by side: said first, the driver's rows unnamed, never an A/B/A
  "$SR" --compare "$R/d9mt.log" "$R/mullion.log" >"$R/mixed.txt" 2>&1 || true
  check "dx12 report: d9mt and Mullion compared: different renderers, said first" eval 'sed -n 2p "$R/mixed.txt" | grep -q "^  These sessions ran on different renderers" && sdx_in "$R/mixed.txt" "^  FPS: average +60\.0 +57\.1$" && sdx_in "$R/mixed.txt" "^    the driver.s +1 \(100% of hitch time\) +1 \(37% of hitch time\)$"'
  "$SR" --compare "$R/d9mt.log" "$R/mullion.log" "$R/d9mt.log" >"$R/mixed-aba.txt" 2>&1 || true
  check "dx12 report: an A/B/A across renderers: no A/B/A numbers" eval 'sdx_in "$R/mixed-aba.txt" "^  the arms ran on different renderers \(their Renderer above\): no A/B/A numbers$" && ! grep -qE "drift|an A/A" "$R/mixed-aba.txt"'
  check "dx12 report: the same renderer: no different renderers line" eval '! "$SR" --compare "$R/mullion.log" "$R/hitch-driver.log" | grep -q "different renderers"'

  # 8. An A/B/A of Mullion arms by the driver files line: an unknown one isn't verified
  sed 's/^SWTOR on Mac driver files: .*/SWTOR on Mac driver files: unknown/' "$R/mullion.log" >"$R/unknown.log"
  "$SR" --compare "$R/mullion.log" "$R/unknown.log" "$R/totals.log" | sed -n '/^The last three as A\/B\/A/,$p' >"$R/mullion-aba.txt" 2>&1 || true
  check "dx12 report: Mullion arms checked by their driver files" eval 'sdx_in "$R/mullion-aba.txt" "^  B \(unknown\.log\): .*the driver files not verified \(unknown\)" && ! grep -E "^  [AC] \(.*driver files" "$R/mullion-aba.txt" >/dev/null && sdx_in "$R/mullion-aba.txt" "each arm needs its build, both driver files. hashes" && ! grep -q "d9mt files" "$R/mullion-aba.txt"'
}
