# shellcheck shell=bash
# Fixture group session-report-dx12 (scripts/test-fixtures.sh only): session-report.sh on a
# DirectX 12 session. The Mullion log is a copy of my fork's tests/swtor/fixtures/session.log
# (mullion-session.log; its first line names the commit it came from) behind the wrapper's lines:
# the renderer from Mullion's header, frame rows from its STATS, a hitch the driver's by
# inDriverMs, the footprint and swap from DIAG MEM, the removed device, GPU error and stuck
# command buffer. Then made-up logs: the failed shader and late pipeline totals, Mullion's
# present thread with its dropped frames and blocked nextDrawable calls, its allocator resets in
# flight, present pacing and textures lines, the fork's other new lines left alone, a session without
# Mullion's header, D3DMetal, d9mt's GPU lines, a session on different renderers side by
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
  check "dx12 report: a Mullion build before the fork's window lines (its header's -118): no visibility, said under Data" sdx_in "$R/mullion.txt" "^  Data +the driver doesn't report window visibility: every second counts as shown; no mark$"
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

  # 3b. Mullion's presents (fork #37, #40): its present thread, the frames it dropped, and the
  # nextDrawable calls of 50 ms or more (each line, and those its limiter left out), behind the
  # sample session with a drawableMs in its 120 ms HITCH (the fork's sample since #37)
  { sed 's/ encodeMs=2\.1 behind=2 / encodeMs=2.1 drawableMs=1149.3 behind=2 /' "$R/mullion.log"
    echo 'info:  Mullion: present thread=1'
    echo 'mullion: nextDrawable blocked 1200 ms got=1 visibility=0x0 at=20:00:34.712'
    echo 'mullion: nextDrawable blocked 1193 ms got=1 visibility=0x1 at=20:00:41.020'
    echo 'mullion: nextDrawable blocked 51 ms got=0 visibility=unknown at=20:00:50.004 [4 earlier lines suppressed]'
    echo 'info:  Mullion: present dropped=11 since=1203 drawableMs=1200 at=20:00:34.713'
    echo 'info:  Mullion: present dropped=2 since=1000 drawableMs=31 at=20:00:35.714'; } >"$R/present.log"
  "$SR" "$R/present.log" >"$R/present.txt" 2>&1 || true
  check "dx12 report: Mullion's present thread, its dropped frames and the blocked nextDrawable calls" \
    eval 'sdx_in "$R/present.txt" "^  Present thread \(Mullion\) +on: the drawables off the commit thread \(MULLION_PRESENT_THREAD=1\)$" && sdx_in "$R/present.txt" "^  nextDrawable waits of 50 ms or more +7 \(the longest logged wait 1200 ms\)$" && sdx_in "$R/present.txt" "^  Frames the present thread dropped +13 frames \(the longest wait for a drawable 1200 ms\)$"'
  check "dx12 report: the present lines and a HITCH's drawableMs (planted: $(grep -c " drawableMs=1149\.3 behind=2 " "$R/present.log") line) change no frame or hitch row" \
    eval '[ "$(grep -c " HITCH .* drawableMs=1149\.3 behind=2 " "$R/present.log")" = 1 ] && [ "$(grep -vE "^SWTOR on Mac session report: |^  (Present thread|nextDrawable waits|Frames the present thread)" "$R/present.txt")" = "$(grep -v "^SWTOR on Mac session report: " "$R/mullion.txt")" ]'
  # the longest wait is the longest of the lines written: the limiter's lines carry no time
  { sdx_head "$SDX_MULLION"
    echo 'mullion: nextDrawable blocked 51 ms got=1 visibility=0x0 at=20:00:34.712'
    echo 'mullion: nextDrawable blocked 52 ms got=1 visibility=0x0 at=20:00:44.800 [1 earlier lines suppressed]'; } >"$R/present-supp.log"
  check "dx12 report: a wait among the limiter's lines has no time: 3 waits, the longest logged one 52 ms" \
    eval '"$SR" "$R/present-supp.log" | grep -E "^  nextDrawable waits of 50 ms or more +3 \(the longest logged wait 52 ms\)$" >/dev/null'
  sed 's/Mullion: present thread=1/Mullion: present thread=0/' "$R/present.log" >"$R/present-off.log"
  check "dx12 report: the present thread off (MULLION_PRESENT_THREAD=0)" \
    eval '"$SR" "$R/present-off.log" | grep -E "^  Present thread \(Mullion\) +off: the drawables on the commit thread \(MULLION_PRESENT_THREAD=0\)$" >/dev/null'
  check "dx12 report: no present rows without their lines" eval '! grep -E "Present thread|nextDrawable waits|present thread dropped" "$R/mullion.txt" >/dev/null'

  # 3c. Mullion's allocator resets with lists in flight (fork #50, in place of #17's wait):
  # STATS's RESETINFLIGHT section summed, the allocators from MULLION-RESET-IN-FLIGHT; and its
  # textures line, the last one
  { cat "$R/mullion.log"
    echo 'info:  Mullion: textures compression=metal msaa=metal msaaSwitch=1 apple10=no'
    echo 'warn:  MULLION-RESET-IN-FLIGHT at=20:00:12.004 type=direct lists=1 frame=410 allocator=1'
    echo 'warn:  RESETINFLIGHT resets=3 lists=4'
    echo 'warn:  MULLION-RESET-IN-FLIGHT at=20:00:20.112 type=compute lists=2 frame=901 allocator=2'
    echo 'warn:  RESETINFLIGHT resets=1 lists=2'
    echo 'info:  Mullion: textures compression=metal msaa=off msaaSwitch=auto apple10=no'; } >"$R/resetinflight.log"
  "$SR" "$R/resetinflight.log" >"$R/resetinflight.txt" 2>&1 || true
  check "dx12 report: Mullion's allocator resets in flight summed, and its textures line (the last device's)" \
    eval 'sdx_in "$R/resetinflight.txt" "^  Allocator resets in flight +4 resets, 6 lists handed to the queues \(2 allocators\)$" && sdx_in "$R/resetinflight.txt" "^  Textures \(Mullion\) +compression=metal msaa=off msaaSwitch=auto apple10=no$"'
  # MULLION-RESET-IN-FLIGHT lines but no RESETINFLIGHT section: Debug Logging off (no
  # MULLION_STATS), or a session that ended before the next STATS line; the report can't tell
  grep -v "RESETINFLIGHT resets=" "$R/resetinflight.log" >"$R/resetinflight-nostats.log"
  check "dx12 report: MULLION-RESET-IN-FLIGHT lines without a RESETINFLIGHT section: the allocators only, no guess why" \
    eval '"$SR" "$R/resetinflight-nostats.log" >"$R/resetinflight-nostats.txt" 2>&1; sdx_in "$R/resetinflight-nostats.txt" "^  Allocator resets in flight +2 allocators \(no RESETINFLIGHT counts logged\)$" && ! grep -q "Debug Logging off" "$R/resetinflight-nostats.txt"'
  # the fork's allocator wait is gone (fork #50): its old lines are no row any more
  { cat "$R/mullion.log"
    echo 'warn:  MULLION-RESET-WAIT at=20:00:12.004 type=direct lists=1 frame=410 allocator=1'
    echo 'warn:  RESETWAIT waits=3 ms=4.5 longestMs=2.5'; } >"$R/resetwait.log"
  check "dx12 report: an older build's MULLION-RESET-WAIT and RESETWAIT lines make no row" \
    eval '! "$SR" "$R/resetwait.log" | grep -E "Allocator resets|waited" >/dev/null'
  check "dx12 report: no allocator reset or textures row without their lines" eval '! grep -E "Allocator resets|Textures \(Mullion\)" "$R/mullion.txt" >/dev/null'

  # 3d. Mullion's present pacing (fork #51): the last line's interval, the game's, whether
  # MULLION_SYNC_INTERVAL forced it, the refresh rate and the cap, and how many lines there were
  { cat "$R/mullion.log"
    echo 'info:  Mullion: present pacing interval=0 game=0 forced=no refreshHz=120.0 capFps=0 afterMs=0.0 at=20:00:04.100'
    echo 'info:  Mullion: present pacing interval=1 game=0 forced=1 refreshHz=60.0 capFps=60 afterMs=16.7 at=20:00:30.000 changes=2'; } >"$R/pacing.log"
  check "dx12 report: Mullion's present pacing, the last line's" \
    eval '"$SR" "$R/pacing.log" | grep -E "^  Present pacing \(Mullion\) +interval 1 \(the game.s 0, MULLION_SYNC_INTERVAL=1\), 60\.0 Hz, cap 60 fps \(the last of 2 lines\)$" >/dev/null'
  { cat "$R/mullion.log"
    echo 'info:  Mullion: present pacing interval=0 game=0 forced=no refreshHz=unknown capFps=0 afterMs=0.0 at=20:00:04.100'; } >"$R/pacing-one.log"
  check "dx12 report: one pacing line, the game's interval, the rate unknown" \
    eval '"$SR" "$R/pacing-one.log" | grep -E "^  Present pacing \(Mullion\) +interval 0 \(the game.s 0, not forced\), unknown Hz, no cap$" >/dev/null'
  check "dx12 report: no present pacing row without its line" eval '! grep -E "Present pacing" "$R/mullion.txt" >/dev/null'
  # fork #55's fields: the timer cap (MULLION_FPS_CAP, over d3d12.preferredMaxFrameRate), the
  # path, the deadlines' period and display sync; the first two lines are the fork's own test's
  # (tests/host/present_wait.cpp at f52b91e)
  { cat "$R/mullion.log"
    echo 'info:  Mullion: present pacing interval=1 game=0 forced=1 refreshHz=60.0 capFps=60 afterMs=0.0 timerFps=40 pace=wait periodMs=25.0 displaySync=1 at=09:05:07.042'; } >"$R/pacing-wait.log"
  check "dx12 report: the wait path under a timer cap of 40: the timer's cap, the preferred one pacing nothing, the deadlines and display sync" \
    eval '"$SR" "$R/pacing-wait.log" | grep -E "^  Present pacing \(Mullion\) +interval 1 \(the game.s 0, MULLION_SYNC_INTERVAL=1\), 60\.0 Hz, timer cap 40 fps \(MULLION_FPS_CAP; d3d12\.preferredMaxFrameRate=60 paces nothing\), pace wait, deadlines 25\.0 ms apart, display sync on$" >/dev/null'
  { cat "$R/mullion.log"
    echo 'info:  Mullion: present pacing interval=1 game=1 forced=no refreshHz=60.0 capFps=0 afterMs=16.7 timerFps=0 pace=duration periodMs=0.0 displaySync=0 at=00:00:00.000'; } >"$R/pacing-duration.log"
  check "dx12 report: the duration path with nothing set: no cap, the timer off, no frame deadline" \
    eval '"$SR" "$R/pacing-duration.log" | grep -E "^  Present pacing \(Mullion\) +interval 1 \(the game.s 1, not forced\), 60\.0 Hz, no cap, timer off, pace duration, no frame deadline, display sync off$" >/dev/null'
  # the checklist's arm 1: d3d12.preferredMaxFrameRate=60 on the duration path, no timer
  { cat "$R/mullion.log"
    echo 'info:  Mullion: present pacing interval=1 game=1 forced=no refreshHz=60.0 capFps=60 afterMs=16.7 timerFps=0 pace=duration periodMs=0.0 displaySync=0 at=20:00:04.100'; } >"$R/pacing-preferred.log"
  check "dx12 report: the preferred cap of 60 on the duration path: that cap, the timer off, no frame deadline" \
    eval '"$SR" "$R/pacing-preferred.log" | grep -E "^  Present pacing \(Mullion\) +interval 1 \(the game.s 1, not forced\), 60\.0 Hz, cap 60 fps, timer off, pace duration, no frame deadline, display sync off$" >/dev/null'
  # fork #55's reviewer's case: timerFps=40 with capFps=0 was "no cap"
  { cat "$R/mullion.log"
    echo 'info:  Mullion: present pacing interval=1 game=1 forced=no refreshHz=60.0 capFps=0 afterMs=16.7 timerFps=40 pace=duration periodMs=25.0 displaySync=0 at=20:00:04.100'; } >"$R/pacing-timer.log"
  check "dx12 report: timerFps=40 with capFps=0 is the timer's cap of 40, not no cap" \
    eval '"$SR" "$R/pacing-timer.log" | grep -E "^  Present pacing \(Mullion\) +interval 1 \(the game.s 1, not forced\), 60\.0 Hz, timer cap 40 fps \(MULLION_FPS_CAP\), pace duration, deadlines 25\.0 ms apart, display sync off$" >/dev/null'

  # 3e. The fork's new lines the report doesn't count (fork #50's store file, #53, #54, #55, #56) and its
  # new rows' lines change no frame, hitch or failure row
  { cat "$R/mullion.log"
    echo 'warn:  MULLION-RESET-IN-FLIGHT at=20:00:12.004 type=direct lists=1 frame=410 allocator=1'
    echo 'warn:  RESETINFLIGHT resets=3 lists=4'
    echo 'info:  Mullion: present pacing interval=0 game=0 forced=no refreshHz=unknown capFps=0 afterMs=0.0 at=20:00:04.100 changes=3'
    echo 'mullion: metal4 parts=reused'
    echo 'mullion: flight record of a stuck command buffer not written: swtor_RC2.exe.flight has 8 dumps, and takes only a reason not dumped yet now'
    echo 'info:  Mullion: cacheOpen shaders=mullion/swtor_RC2.exe/shaders_400.v7.db codegen=0123456789ab entries=0 sizeMiB=0 droppedTables=1 droppedShards=0 droppedMiB=700'
    # fork #55's and #56's (batch 4's ARCHIVEDRAW section, which has no row yet)
    echo 'info:  Mullion: display sync=1'
    echo 'warn:  Mullion: MULLION_PACE is not duration or wait; presents keep Metal'"'"'s minimum duration'
    echo 'warn:  Mullion: MULLION_FPS_CAP is not 0 or 20 to 1000; no cap'
    echo 'warn:  Mullion: MULLION_DISPLAY_SYNC=1 ignored: the present thread is off'
    echo 'warn:  ARCHIVEDRAW made=12 missed=1 ms=48.3'; } >"$R/newlines.log"
  "$SR" "$R/newlines.log" >"$R/newlines.txt" 2>&1 || true
  check "dx12 report: the fork's new lines change no other row" \
    eval '[ "$(grep -vE "^SWTOR on Mac session report: |^  (Allocator resets in flight|Present pacing \(Mullion\)) " "$R/newlines.txt")" = "$(grep -v "^SWTOR on Mac session report: " "$R/mullion.txt")" ]'

  # 4. Mullion without its header (Debug Logging off): the wrapper's line names the build
  sdx_head "$SDX_MULLION" >"$R/plain.log"
  "$SR" "$R/plain.log" >"$R/plain.txt" 2>&1 || true
  { cat "$R/plain.log"; echo '0124:warn:threadcpu:trace_thread_cpu THREADCPU 1.00 s: process 701 ms (16 threads), wineserver 21 ms; busiest (ms): 0130 610, 0134 66'; } >"$R/threadcpu.log"
  check "dx12 report: Mullion with the Mac driver's THREADCPU only: not credited to MULLION_STATS" eval '"$SR" "$R/threadcpu.log" | grep -E "^  Measurement +instrumented: Debug Logging on \(the Mac driver.s THREADCPU\)" >/dev/null'
  check "dx12 report: Mullion without its header, the wrapper's build" eval 'sdx_in "$R/plain.txt" "^  Renderer +DirectX 12 on Mullion \(jdrly/mullion 0009110\), v0\.5-alpha\.3-118-g1a2b3c4, codegen airconv 103 \(driver mullion; no session header" && sdx_in "$R/plain.txt" "^  Measurement +ordinary play \(Debug Logging off\)" && sdx_in "$R/plain.txt" "^  \(no STATS lines: Debug Logging was off \(Mullion.s MULLION_STATS\)" && ! grep -q "Attachment optimization" "$R/plain.txt"'

  check "dx12 report: Mullion without its header, a build before the window lines by the wrapper's -118: no visibility, said under Data" \
    sdx_in "$R/plain.txt" "^  Data +the driver doesn't report window visibility: every second counts as shown; no mark$"

  # 4b. A build since the fork's window lines (fork #24, v0.5-alpha.3-174 and later): the
  # sample session behind its header, with the fork's Cmd-Tab between STATS t=30 and t=34 (the
  # lines of its session.log since #24): the Data line no longer says Mullion reports no
  # visibility, and --mark finds the return to the window
  printf '%s\n' 'mullion: window at=20:00:34.412 active=0 visibility=0x3 why=resign' \
    'MtlPresenter: 20:00:34.655 visibility 0x3 -> 0x1 visible=1 activeSpace=0 miniaturized=0 active=0 why=space' \
    'MtlPresenter: 20:00:34.702 visibility 0x1 -> 0x0 visible=0 activeSpace=0 miniaturized=0 active=0 why=occlusion' >"$R/away.txt"
  printf '%s\n' 'mullion: window at=20:00:37.301 active=1 visibility=0x0 why=activate' \
    'MtlPresenter: 20:00:37.517 visibility 0x0 -> 0x2 visible=0 activeSpace=1 miniaturized=0 active=1 why=space' \
    'MtlPresenter: 20:00:37.566 visibility 0x2 -> 0x3 visible=1 activeSpace=1 miniaturized=0 active=1 why=occlusion' >"$R/back.txt"
  sed -e 's/ Mullion: session v0\.5-alpha\.3-118-g1a2b3c4 / Mullion: session v0.5-alpha.3-178-g23f4799 /' \
    -e "/ STATS t=30 /r $R/away.txt" -e "/ STATS t=33 /r $R/back.txt" "$R/mullion.log" >"$R/window.log"
  "$SR" "$R/window.log" >"$R/window.txt" 2>&1 || true
  "$SR" --mark 10 "$R/window.log" >"$R/window-mark.txt" 2>&1 || true
  check "dx12 report: a build since the window lines with a Cmd-Tab: the hidden seconds left out, the mark at the return, no line that Mullion reports no visibility" \
    eval 'sdx_in "$R/window.txt" "^    window hidden or switching +6 s, not counted below" && sdx_in "$R/window-mark.txt" "^  Interval +STATS t 39-48, 10 s from 5 s after the mark at 20:00:37\.566; 10 lines$" && ! grep -q "report window visibility" "$R/window.txt" "$R/window-mark.txt"'
  sed 's/ Mullion: session v0\.5-alpha\.3-118-g1a2b3c4 / Mullion: session v0.5-alpha.3-174-g5d91494 /' "$R/mullion.log" >"$R/since24.log"
  sed 's/, v0\.5-alpha\.3-118-g1a2b3c4, /, v0.5-alpha.3-178-g23f4799, /' "$R/plain.log" >"$R/plain24.log"
  check "dx12 report: a build since the window lines without a window change, by the header's -174 or the wrapper's -178: no line that Mullion reports no visibility" \
    eval '"$SR" "$R/since24.log" >"$R/since24.txt" 2>&1; "$SR" "$R/plain24.log" >"$R/plain24.txt" 2>&1; sdx_in "$R/since24.txt" "^  Renderer +DirectX 12 on Mullion v0\.5-alpha\.3-174-g5d91494 " && ! grep -q "report window visibility" "$R/since24.txt" "$R/plain24.txt"'

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
