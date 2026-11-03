# shellcheck shell=bash
# Fixture group system-reports: Collect Logs' extracts of macOS's own reports (collect-logs.sh's
# system_reports, issue #90) on planted, made-up reports in the sandbox's system-diagnostics
# folder (in a sandbox collect-logs.sh reads that instead of /Library/Logs/DiagnosticReports, which
# is never read here). Needs neither the official app nor Wine. Sourced; check and its counters
# come from lib.sh; SWTOR_ON_MAC_ROOT is the sandbox root.
#
#   fx_system_reports <collect-logs.sh> <folder for the zips and their contents>
#
# The planted reports have the shapes of macOS 27's, with made-up values: other apps' names
# (SecretApp..., SecretDaemon...), a Mac's name (Fixture-Host-Mac) in the file names, a home
# folder (/Users/fxplayer) and this user's name in the contents. None of them may reach the zip.
sr_has() { grep -qF -- "$2" "$SR_OUT/$1"; }
sr_zip() {  # <run>: collect into $SR/<run>, unzip there; the zip's path in $SR/<run>/zip
  local d="$SR/$1" z
  rm -rf "$d"; mkdir -p "$d"
  z=$("$SR_SH" "$d" 2>"$d/stderr" || true)
  echo "$z" >"$d/zip"
  [ -f "$z" ] && (cd "$d" && unzip -q "$z") || true
  SR_OUT=$(find "$d" -mindepth 1 -maxdepth 1 -type d -name 'SWTOR-on-Mac-logs-*' | head -1)
}
sr_plant() {  # <name> <minutes ago>: stdin into the system reports folder
  cat >"$SYSD/$1"
  touch -t "$(date -v-"$2"M +%Y%m%d%H%M)" "$SYSD/$1"
}
fx_system_reports() {
  SR_SH=$1 SR=$2
  local root="$SWTOR_ON_MAC_ROOT" me logs
  me=$(id -un)
  SYSD="$root/system-diagnostics"
  logs="$root/home/Library/Logs/SWTOR on Mac"
  mkdir -p "$SR" "$SYSD" "$logs"
  # a game session's log, so the session report is written (and the window is 48 h)
  printf 'SWTOR on Mac 0.1.7-dev.1: engine cx26 cx-26.3.0-8, d9mt 73511be, started 2026-10-31 19:00:00\n' >"$logs/wine.log"

  sr_plant gpuEvent-swtor.exe-2026-10-31-195244.ips 30 <<'EOF'
{"bug_type":"284","timestamp":"2026-10-31 19:52:44.00 +0100","os_version":"macOS 27.2 (26B123)","roots_installed":0,"incident_id":"00000000-0000-4000-8000-000000000001"}
{
  "roots_installed" : 0,
  "bug_type" : "284",
  "process_name" : "swtor.exe",
  "registers" : {},
  "timestamp" : 123456789,
  "analysis" : {"guilty_dm":2,"bif0_fault":{"pm_protect":false,"is_read":true,"sideband":7,"level":0,"requestor":11,"address":4096},"restart_reason_desc":"BIF0 page fault","restart_reason":3,"signature":500}
}
EOF
  # another app's GPU event: not ours, never read
  sr_plant gpuEvent-SecretAppAlpha-2026-10-31-195000.ips 32 <<'EOF'
{"bug_type":"284","timestamp":"2026-10-31 19:50:00.00 +0100"}
{ "process_name" : "SecretAppAlpha", "analysis" : {"restart_reason_desc":"BIF0 page fault"} }
EOF
  sr_plant WindowServer-2026-10-31-195329.ips 29 <<EOF
{"name":"WindowServer","timestamp":"2026-10-31 19:53:29.00 +0100","os_version":"macOS 27.2 (26B123)","incident_id":"00000000-0000-4000-8000-000000000002","bug_type":"409","app_name":"WindowServer"}
{
  "variant" : "stackshot",
  "crashReporterKey" : "00000000-0000-4000-8000-0000000000aa",
  "captureTime" : "2026-10-31 19:53:29.5000 +0100",
  "pid" : 312,
  "bug_type" : "409",
  "procName" : "WindowServer",
  "termination" : {"flags":0,"indicator":"monitoring timed out for service","code":1,"namespace":"WATCHDOG","details":["(1 monitored services unresponsive): checkin with service: WindowServer (0 induced crashes) returned not alive with context:","waiting on SecretAppAlpha for 40 seconds since /Users/fxplayer/Library","40 seconds since last successful checkin"]},
  "uptime" : 15000,
  "thermalPressureLevel" : "ThermalPressureLevelNominal (0)",
  "displayState" : "OFF",
  "stackshot" : {"processByPid" : {
    "312" : {"pid" : 312, "procname" : "WindowServer", "processUptime" : 15000.2, "threadById" : {"1" : {"id" : 1, "name" : "ws_main_thread"}}},
    "900" : {"pid" : 900, "procname" : "SecretAppAlpha", "processUptime" : 120.0, "threadById" : {"2" : {"id" : 2, "name" : "alpha-worker-thread"}}},
    "901" : {"pid" : 901, "procname" : "timed", "processUptime" : 15000.0, "threadById" : {"3" : {"id" : 3}}}
  }}
}
EOF
  # a WindowServer report cut off while the Mac went down: its first lines' fields only
  sr_plant WindowServer-2026-10-31-234600.ips 25 <<'EOF2'
{"name":"WindowServer","timestamp":"2026-10-31 23:46:00.00 +0100","bug_type":"409","app_name":"WindowServer"}
{
  "captureTime" : "2026-10-31 23:46:00.1000 +0100",
  "termination" : {"flags":0,"indicator":"monitoring timed out for service","code":1,"namespace":"WATCHDOG","details":["waiting on SecretAppAlpha"]},
  "uptime" : 9000,
  "thermalPressureLevel" : "ThermalPressureLevelNominal (0)",
  "stackshot" : {"processByPid" : {
    "900" : {"pid" : 900, "procname" : "SecretAppAlpha", "threadById" : {"2" : {"id" : 2, "name" : "alpha-wor
EOF2
  # an older report (5 days): outside the window
  sr_plant WindowServer-2026-10-26-100000.ips $((5 * 24 * 60)) <<'EOF'
{"name":"WindowServer","timestamp":"2026-10-26 10:00:00.00 +0100","bug_type":"409"}
{ "termination" : {"namespace":"WATCHDOG"} }
EOF
  sr_plant WindowServer_2026-10-31-195334_Fixture-Host-Mac.userspace_watchdog_timeout.spin 28 <<EOF
Date/Time:        2026-10-31 19:53:19.400 +0100
End time:         2026-10-31 19:53:24.900 +0100
OS Version:       Mac OS X 27.2 (Build 26B123)
Architecture:     arm64e
Report Version:   73

Data Source:      Stackshots
Shared Cache:     00000000-0000-4000-8000-000000000003 slid base address 0x180000000 (System Primary)
Reason:           (1 monitored services unresponsive): checkin with service: WindowServer (0 induced crashes) returned not alive, SecretDaemonGamma blocked, /Users/fxplayer/Desktop

Command:          WindowServer
Path:             /System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/Resources/WindowServer
PID:              312

Event:            service process watchdog
Duration:         5.50s
Steps:            12

Hardware model:   Mac99,1
Time Awake Since Boot: 15100s

Process:          WindowServer [312]
UUID:             00000000-0000-4000-8000-000000000004
Path:             /System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/Resources/WindowServer
Footprint:        500.00 MB
Time Since Fork:  15000s
Num samples:      12 (1-12)
CPU Time:         0.104s
Num threads:      26

  Thread 0x1802    DispatchQueue "com.apple.main-thread"(1)    Thread name "ws_main_thread"    12 samples (1-12)    priority 79 (base 79)    cpu time 0.033s
  12  ??? (SecretAppBeta + 1000) [0x180001000] 1-12
    12  waiting for SecretAppBeta [555] 1-12

  Thread 0x19b5    Thread name "render $me queue"    12 samples (1-12)    priority 79 (base 79)    cpu time 0.013s
  12  ??? (SkyLight + 1) [0x1] 1-12

Process:          SecretAppBeta [555]
Path:             /Applications/SecretAppBeta.app/Contents/MacOS/SecretAppBeta
Num threads:      3

  Thread 0x2001    Thread name "beta-secret-thread"    12 samples (1-12)    priority 31 (base 31)

Process:          SecretDaemonGamma [901]
Num threads:      1

  Thread 0x2101    Thread name "gamma-thread"    12 samples (1-12)    priority 31 (base 31)

Process:          swtor.exe [4321]
Path:             /Users/fxplayer/Library/Application Support/SWTOR on Mac/engine/bin/wine
Footprint:        9.10 GB
Num threads:      140

  Thread 0x3001    Thread name "d9mt-compile"    12 samples (1-12)    priority 47 (base 47)    cpu time 0.500s
  12  ??? (SecretAppBeta + 1) [0x2] 1-12

Binary Images:
       0x1000 -     0x2000 SecretAppBeta <00000000-0000-4000-8000-000000000005> /Applications/SecretAppBeta.app
EOF
  # (macOS 27's form: the JSON, then a plain-text System Profile, a brace pair in it too)
  sr_plant panic-full-2026-11-01-000358.0002.panic 20 <<EOF
{"bug_type":"210","timestamp":"2026-11-01 00:03:58.00 +0100","os_version":"macOS 27.2 (26B123)","roots_installed":0,"incident_id":"00000000-0000-4000-8000-000000000006"}
{
  "crashReporterKey" : "00000000-0000-4000-8000-0000000000bb",
  "product" : "Mac99,1",
  "panicString" : "panic(cpu 6 caller 0xfffffe0000c0ffee): userspace watchdog timeout: no successful checkins from WindowServer (2 induced crashes) in 120 seconds\nservice: SecretDaemonGamma, total successful checkins in 10000 seconds: 1000, last successful checkin: 0 seconds ago\nservice: WindowServer (2 induced crashes), total successful checkins in 9900 seconds: 990, last successful checkin: 120 seconds ago\npath /Users/fxplayer/Library\n\nDebugger message: panic\nsecret-after-debugger: SecretAppAlpha\n",
  "date" : "2026-11-01 00:03:58.12 +0100",
  "processByPid" : {
    "0" : {"pid" : 0, "procname" : "kernel_task", "processUptime" : 12500.0, "threadById" : {"10" : {"id" : 10, "name" : "kernel-thread-x"}}},
    "312" : {"pid" : 312, "procname" : "WindowServer", "processUptime" : 9900.4, "threadById" : {"11" : {"id" : 11, "name" : "ws_main_thread"}, "12" : {"id" : 12, "name" : "com.apple.coreanimation.render-server"}, "13" : {"id" : 13}}},
    "313" : {"pid" : 313, "procname" : "loginwindow", "processUptime" : 12420.0, "threadById" : {"14" : {"id" : 14, "name" : "lw_main"}}},
    "4321" : {"pid" : 4321, "procname" : "swtor.exe", "processUptime" : 169.7, "threadById" : {"15" : {"id" : 15, "name" : "d9mt-compile"}, "16" : {"id" : 16, "name" : "render $me queue"}}},
    "900" : {"pid" : 900, "procname" : "SecretAppAlpha", "processUptime" : 120.0, "threadById" : {"17" : {"id" : 17, "name" : "alpha-worker-thread"}}},
    "901" : {"pid" : 901, "procname" : "SecretDaemonGamma", "processUptime" : 99.0, "threadById" : {"18" : {"id" : 18, "name" : "gamma-thread"}}}
  }
}

System Profile:
Network Service: SecretAppEpsilon Network, Wi-Fi, en0
Thunderbolt Device: SecretAppEpsilon Dock, Fixture-Host-Mac, 1, 45.1
Boot Volume File System Type: apfs
Model: Mac99,1, BootROM 1.0, 18 processors, 128 GB
{
}
EOF
  # a panic whose JSON is cut off: named, left out, the zip still written
  sr_plant panic-full-2026-11-01-010000.0003.panic 10 <<'EOF'
{"bug_type":"210","timestamp":"2026-11-01 01:00:00.00 +0100"}
{
  "panicString" : "panic(cpu 1 caller 0x1): SecretAppAlpha
EOF
  sr_plant swtor.exe_2026-10-31-213115_Fixture-Host-Mac.diag 60 <<'EOF'
Date/Time:        2026-10-31 20:30:00.000 +0100
End time:         2026-10-31 21:23:20.000 +0100
OS Version:       macOS 27.2 (Build 26B123)
Incident Identifier: 00000000-0000-4000-8000-000000000007

Command:          swtor.exe
Path:             /Users/fxplayer/Library/Application Support/SWTOR on Mac/engine/bin/wine
PID:              4321

Event:            disk writes
Action taken:     none
Writes:           2200.00 MB of file backed memory dirtied over 3200 seconds (700.00 KB per second average), exceeding limit of 25.00 KB per second over 86400 seconds
Writes limit:     2150.00 MB
Limit duration:   86400s
Writes caused:    2200.00 MB
Duration:         3200.00s
Steps:            100

Heaviest stack for the target process:
  104  ??? (SecretAppDelta + 2000) [0x200000000]
EOF

  echo "  (run 1: planted reports)"
  sr_zip planted
  check "system reports: the zip is written" eval '[ -s "$SR/planted/zip" ] && [ -f "$(cat "$SR/planted/zip")" ] && [ -n "$SR_OUT" ]'
  local d="system-reports"
  check "system reports: the extracts, the Mac's name gone from the names" eval '[ "$(LC_ALL=C ls "$SR_OUT/$d" | tr "\n" " ")" = "WindowServer-2026-10-31-195329.ips.txt WindowServer-2026-10-31-234600.ips.txt WindowServer_2026-10-31-195334.userspace_watchdog_timeout.spin.txt gpuEvent-swtor.exe-2026-10-31-195244.ips panic-full-2026-11-01-000358.0002.panic.txt swtor.exe_2026-10-31-213115.diag.txt " ]'
  check "system reports: the GPU event whole" eval 'sr_has "$d/gpuEvent-swtor.exe-2026-10-31-195244.ips" "\"restart_reason_desc\":\"BIF0 page fault\"" && sr_has "$d/gpuEvent-swtor.exe-2026-10-31-195244.ips" "\"is_read\":true"'
  # (ws, wc, sp, pn and dg are read in the checks' eval strings)
  # shellcheck disable=SC2034
  local ws="$d/WindowServer-2026-10-31-195329.ips.txt"
  check "system reports: WindowServer's termination and thermal pressure" eval 'sr_has "$ws" "Termination namespace: WATCHDOG" && sr_has "$ws" "Termination code: 1" && sr_has "$ws" "Termination indicator: monitoring timed out for service" && sr_has "$ws" "  40 seconds since last successful checkin" && sr_has "$ws" "Thermal pressure: ThermalPressureLevelNominal (0)" && sr_has "$ws" "Timestamp: 2026-10-31 19:53:29.00 +0100"'
  check "system reports: WindowServer's details: its own service kept, a line of no known form left out" eval 'sr_has "$ws" "  (1 monitored services unresponsive): checkin with service: WindowServer (0 induced crashes) returned not alive with context:" && sr_has "$ws" "(a line of an unknown form, left out)"'
  check "system reports: WindowServer's report without its stack shot or key" eval '! sr_has "$ws" ws_main_thread && ! sr_has "$ws" 0000000000aa'
  # shellcheck disable=SC2034
  local wc="$d/WindowServer-2026-10-31-234600.ips.txt"
  check "system reports: a cut-off WindowServer report: its first lines' fields" eval 'sr_has "$wc" "(its JSON is cut off" && sr_has "$wc" "Termination namespace: WATCHDOG" && sr_has "$wc" "Termination indicator: monitoring timed out for service" && sr_has "$wc" "Uptime: 9000 s" && grep -qF "WindowServer-2026-10-31-234600.ips.txt (" "$SR_OUT/system-info.txt"'
  # shellcheck disable=SC2034
  local sp="$d/WindowServer_2026-10-31-195334.userspace_watchdog_timeout.spin.txt"
  check "system reports: the spin's header" eval 'sr_has "$sp" "Event:            service process watchdog" && sr_has "$sp" "Duration:         5.50s" && sr_has "$sp" "Hardware model:   Mac99,1" && ! sr_has "$sp" "Shared Cache:"'
  check "system reports: the spin's WindowServer and game threads, known names kept" eval 'sr_has "$sp" "DispatchQueue \"com.apple.main-thread\"(1)    Thread name \"ws_main_thread\"    12 samples (1-12)    priority 79 (base 79)    cpu time 0.033s" && sr_has "$sp" "Process: swtor.exe" && sr_has "$sp" "Thread name \"d9mt-compile\"" && sr_has "$sp" "Num threads:      140"'
  check "system reports: the spin without stacks or another process's block" eval '! sr_has "$sp" "???" && ! sr_has "$sp" "beta-secret-thread" && ! sr_has "$sp" "Binary Images"'
  # shellcheck disable=SC2034
  local pn="$d/panic-full-2026-11-01-000358.0002.panic.txt"
  check "system reports: the panic string's head, up to the Debugger message" eval 'sr_has "$pn" "userspace watchdog timeout: no successful checkins from WindowServer (2 induced crashes) in 120 seconds" && sr_has "$pn" "  service: OTHER, total successful checkins" && sr_has "$pn" "  service: WindowServer (2 induced crashes), total successful checkins in 9900 seconds: 990, last successful checkin: 120 seconds ago" && sr_has "$pn" "Debugger message: panic" && ! sr_has "$pn" "secret-after-debugger"'
  check "system reports: the panic's WindowServer, loginwindow and game (uptime, threads)" eval 'sr_has "$pn" "WindowServer (pid 312): up 9900 s, 3 threads" && sr_has "$pn" "      com.apple.coreanimation.render-server" && sr_has "$pn" "      (1 without a name)" && sr_has "$pn" "loginwindow (pid 313): up 12420 s, 1 threads" && sr_has "$pn" "swtor.exe (pid 4321): up 170 s, 2 threads" && sr_has "$pn" "      d9mt-compile"'
  check "system reports: the panic without kernel_task's or other processes' threads" eval '! sr_has "$pn" kernel-thread-x && ! sr_has "$pn" gamma-thread && ! sr_has "$pn" 0000000000bb'
  check "system reports: the panic read up to its JSON's end, its System Profile left out" eval '! sr_has "$pn" "System Profile" && ! sr_has "$pn" "Network Service" && ! sr_has "$pn" "Boot Volume" && ! grep -qF "panic-full-2026-11-01-000358.0002.panic (" "$SR_OUT/system-info.txt" && grep -qF "  panic-full-2026-11-01-000358.0002.panic.txt (" "$SR_OUT/system-info.txt"'
  # shellcheck disable=SC2034
  local dg="$d/swtor.exe_2026-10-31-213115.diag.txt"
  check "system reports: the resource report's event, limit and duration lines" eval 'sr_has "$dg" "Event:            disk writes" && sr_has "$dg" "Writes limit:     2150.00 MB" && sr_has "$dg" "Limit duration:   86400s" && sr_has "$dg" "Duration:         3200.00s" && ! sr_has "$dg" "Path:" && ! sr_has "$dg" "Heaviest"'
  check "system reports: no other app's name, home folder or Mac's name anywhere in the zip" eval '! grep -r -l -E "SecretApp|SecretDaemon|alpha-worker|beta-secret|gamma-thread|fxplayer|Fixture-Host-Mac" "$SR_OUT" >/dev/null'
  check "system reports: this user's name is not in them (a thread name with it: OTHER)" eval '! grep -r -w -F -- "$me" "$SR_OUT/$d" >/dev/null && sr_has "$sp" "Thread 0x19b5    Thread name \"OTHER\""'
  check "system reports: the malformed panic is named, not in the zip" eval 'grep -qF "panic-full-2026-11-01-010000.0003.panic (" "$SR_OUT/system-info.txt" && grep -qF "its JSON could not be read (malformed), left out" "$SR_OUT/system-info.txt"'
  check "system reports: the counts line in system-info.txt" grep -qxF "System reports of the last 48 h: 1 GPU faults, 2 WindowServer watchdog restarts, 2 kernel panics; 1 malformed; 1 cut off" "$SR_OUT/system-info.txt"
  check "system reports: the session report repeats it" eval '[ "$(sed -n 2p "$SR_OUT/session-report.txt")" = "System reports of the last 48 h: 1 GPU faults, 2 WindowServer watchdog restarts, 2 kernel panics; 1 malformed; 1 cut off" ]'
  check "system reports: nothing left out by the leak check" test ! -e "$SR_OUT/left-out.txt"

  # Names in no process list (a service gone before the snapshot, a kext, a queue's or thread's
  # label, a report with no process list at all), names in other scripts, names that are words of
  # Apple's texts (Fork), several of them (Movie Maker), a number (2048) or begin like Wine's
  # (winePrivateSentinel), another user's and an older, dotted name of the Mac: every one must come
  # out as OTHER, or its line must go
  echo "  (run 1b: names in no process list, in other scripts, like Apple's words; a former Mac name)"
  mkdir -p "$SR/hold"; mv "$SYSD"/* "$SR/hold/"
  sr_plant WindowServer-2026-11-01-100000.ips 15 <<'EOF'
{"name":"WindowServer","timestamp":"2026-11-01 10:00:00.00 +0100","bug_type":"409"}
{
  "captureTime" : "2026-11-01 10:00:00.5000 +0100",
  "termination" : {"code":1,"namespace":"WATCHDOG","indicator":"waiting on 隐私应用","details":[null,"(1 monitored services unresponsive): checkin with service: 隐私应用 (0 induced crashes) returned not alive with context:","(1 monitored services unresponsive): checkin with service: Fork (0 induced crashes) returned not alive with context:","service: 李明 on 私人电脑.local","waiting on winePrivateSentinel","waiting on Movie Maker","waiting on UnlistedDetailsApp","service: Fork returned not alive","task 2048 failed","waiting on a service\nOS Version: macOS 27.2 (Build BuildLeakSentinel)","40 seconds since last successful checkin"]},
  "thermalPressureLevel" : "ThermalPressureLevelNominal (0)",
  "uptime" : 3000
}
EOF
  sr_plant panic-full-2026-11-01-100100.0004.panic 14 <<'EOF'
{"bug_type":"210","timestamp":"2026-11-01 10:01:00.00 +0100"}
{
  "panicString" : "panic(cpu 2 caller 0x1): task 秘密程序 failed in com.机密厂商.driver.秘密扩展\nservice: UnlistedServiceApp, total successful checkins in 100 seconds: 10, last successful checkin: 0 seconds ago\nservice: Fork, total successful checkins in 100 seconds: 10, last successful checkin: 0 seconds ago\nservice: Movie Maker, total successful checkins in 100 seconds: 10, last successful checkin: 0 seconds ago\nservice: 2048, total successful checkins in 100 seconds: 10, last successful checkin: 0 seconds ago\nservice: winePrivateSentinel, total successful checkins in 100 seconds: 10, last successful checkin: 0 seconds ago\nservice: 秘密程序, total successful checkins in 100 seconds: 10, last successful checkin: 0 seconds ago\npath /Users/李明/Library on 私人电脑\nDebugger message: panic\n",
  "processByPid" : {
    "312" : {"pid" : 312, "procname" : "WindowServer", "processUptime" : 3000.0, "threadById" : {"1" : {"id" : 1, "name" : "com.UnlistedQueueApp.render"}, "4" : {"id" : 4, "name" : "com.私人程序.render"}}},
    "4321" : {"pid" : 4321, "procname" : "swtor.exe", "processUptime" : 100.0, "threadById" : {"2" : {"id" : 2, "name" : "com.UnlistedOverlayApp.queue"}, "3" : {"id" : 3, "name" : "d9mt-compile"}}},
    "77" : {"pid" : 77, "procname" : "winePrivateSentinel", "processUptime" : 10.0, "threadById" : {"5" : {"id" : 5, "name" : "sentinel-thread"}}},
    "78" : {"pid" : 78, "procname" : "Fork", "processUptime" : 10.0, "threadById" : {"6" : {"id" : 6, "name" : "fork-thread"}}}
  }
}
EOF
  sr_plant WindowServer_2026-11-01-100200_Prior.Owner.Mac.userspace_watchdog_timeout.spin 13 <<'EOF'
Date/Time:        2026-11-01 10:01:55.000 +0100
OS Version:       macOS 27.2 (Build BuildLeakSentinel)
Computer name:    Prior-Owner-Mac
Reason:           (1 monitored services unresponsive): UnlistedReasonApp blocked  私人电脑.local blocked 李明

Event:            service process watchdog

Process:          WindowServer [312]
Num threads:      2

  Thread 0x10    DispatchQueue "com.UnlistedQueueApp.event"(5)    Thread name "隐私应用 worker"    12 samples (1-12)    priority 79 (base 79)    blocked by Fork

Process:          winePrivateSentinel [77]
Num threads:      1

  Thread 0x11    Thread name "sentinel-thread"    12 samples (1-12)
EOF
  sr_plant UnlistedDaemonApp_2026-11-01-100300_Prior.Owner.Mac.userspace_watchdog_timeout.spin 12 <<'EOF'
Date/Time:        2026-11-01 10:02:55.000 +0100
Command:          Fork
EOF
  sr_plant swtor.exe_2026-11-01-100400_Prior.Owner.Mac.cpu_resource.diag 11 <<'EOF'
Date/Time:        2026-11-01 09:00:00.000 +0100
Command:          swtor.exe
Event:            cpu usage (隐私应用)
Duration:         100.00s
EOF
  sr_plant wine64-preloader_2026-11-01-100500_Prior.Owner.Mac.diag 10 <<'EOF'
Event:            disk writes
EOF
  # (a former Mac name whose last part looks like a report type: not one of the known types)
  sr_plant wine64-preloader_2026-11-01-100800_Prior.pastowner_resource.diag 7 <<'EOF'
Event:            disk writes
EOF
  # (another process whose name begins like Wine's: not the game's, left out by name)
  sr_plant winePrivateSentinel_2026-11-01-100600_Prior.Owner.Mac.diag 9 <<'EOF'
Command:          winePrivateSentinel
EOF
  sr_plant gpuEvent-winePrivateSentinel-2026-11-01-100700.ips 8 <<'EOF'
{"bug_type":"284","timestamp":"2026-11-01 10:07:00.00 +0100"}
{ "process_name" : "winePrivateSentinel", "analysis" : {"restart_reason_desc":"BIF0 page fault"} }
EOF
  sr_zip unlisted
  # shellcheck disable=SC2034
  local u="$d/WindowServer-2026-11-01-100000.ips.txt" up="$d/panic-full-2026-11-01-100100.0004.panic.txt" us="$d/WindowServer_2026-11-01-100200.userspace_watchdog_timeout.spin.txt" uo="$d/OTHER_2026-11-01-100300.userspace_watchdog_timeout.spin.txt" ud="$d/swtor.exe_2026-11-01-100400.cpu_resource.diag.txt"
  check "system reports, unlisted: the Mac's dotted former name gone from the names (spin, diag, known kind suffix kept, an unknown one not)" eval '[ "$(LC_ALL=C ls "$SR_OUT/$d" | tr "\n" " ")" = "OTHER_2026-11-01-100300.userspace_watchdog_timeout.spin.txt WindowServer-2026-11-01-100000.ips.txt WindowServer_2026-11-01-100200.userspace_watchdog_timeout.spin.txt panic-full-2026-11-01-100100.0004.panic.txt swtor.exe_2026-11-01-100400.cpu_resource.diag.txt wine64-preloader_2026-11-01-100500.diag.txt wine64-preloader_2026-11-01-100800.diag.txt " ]'
  check "system reports, unlisted: another process like Wine's: its GPU event and resource report left out, named as OTHER" eval 'grep -qF "  left out: gpuEvent-OTHER-2026-11-01-100700.ips (not the game" "$SR_OUT/system-info.txt" && grep -qF "  left out: OTHER_2026-11-01-100600.diag (not the game" "$SR_OUT/system-info.txt"'
  check "system reports, unlisted: no process list: services as OTHER (Fork too), lines of no known form left out (a text's second line too), a null named, the rest kept" eval 'sr_has "$u" "  (not a text)" && [ "$(grep -c -F "checkin with service: OTHER (0 induced crashes)" "$SR_OUT/$u")" = 2 ] && [ "$(grep -c -F "(a line of an unknown form, left out)" "$SR_OUT/$u")" = 9 ] && ! sr_has "$u" "OS Version" && sr_has "$u" "  40 seconds since last successful checkin"'
  check "system reports, unlisted: the panic string: its unknown rest left out, every service as OTHER" eval 'sr_has "$up" "  panic(cpu 2 caller 0x1): (the rest, of an unknown form, left out)" && [ "$(grep -c -F "  service: OTHER, total successful checkins in 100 seconds: 10" "$SR_OUT/$up")" = 6 ] && sr_has "$up" "(a line of an unknown form, left out)"'
  check "system reports, unlisted: thread and queue names as OTHER, known ones kept, other processes not listed" eval '[ "$(grep -c -x "      OTHER" "$SR_OUT/$up")" = 3 ] && sr_has "$up" "      d9mt-compile" && ! sr_has "$up" "(pid 77)" && ! sr_has "$up" "(pid 78)" && sr_has "$us" "DispatchQueue \"OTHER\"(5)    Thread name \"OTHER\"    12 samples (1-12)    priority 79 (base 79)    OTHER"'
  check "system reports, unlisted: the spin: its reason left out, an unknown header line and a build of no known form too, another process like Wine's not kept" eval 'sr_has "$us" "Reason:" && [ "$(grep -c -F "(a line of an unknown form, left out)" "$SR_OUT/$us")" = 3 ] && ! sr_has "$us" "OS Version" && ! sr_has "$us" "Computer name" && ! sr_has "$us" "Process: OTHER" && sr_has "$uo" "Command:          OTHER"'
  check "system reports, unlisted: the resource report's event of no known form left out" eval 'sr_has "$ud" "(a line of an unknown form, left out)" && sr_has "$ud" "Duration:         100.00s"'
  check "system reports, unlisted: no planted name, number or former Mac or user name in the extracts or their list" eval '! grep -r -l -E "Unlisted|unlisted|Prior[.-]|Owner|pastowner|Fork|Movie|2048|winePrivate|sentinel|Sentinel" "$SR_OUT/$d" >/dev/null && ! grep -E "^  (left out: |not readable: )?[A-Za-z]" "$SR_OUT/system-info.txt" | piped -E "Unlisted|Prior|Owner|pastowner|winePrivate"'
  check "system reports, unlisted: no byte outside printable ASCII in the extracts" eval '! LC_ALL=C grep -r -l "[^ -~]" "$SR_OUT/$d" >/dev/null'
  check "system reports, unlisted: the counts line" grep -qxF "System reports of the last 48 h: 0 GPU faults, 1 WindowServer watchdog restarts, 1 kernel panics" "$SR_OUT/system-info.txt"
  rm -f "$SYSD"/*

  # macOS 27's panic with a System Profile after its JSON, in shapes Apple's own don't have (yet):
  # a nested object closed at the start of a line (the first such brace isn't the JSON's end), and
  # CRLF line ends; each read, nothing of the System Profile in the zip
  echo "  (run 1c: panics with a System Profile: a nested object's brace at the start of a line; CRLF)"
  sr_plant panic-full-2026-11-01-110000.0005.panic 6 <<'EOF'
{"bug_type":"210","timestamp":"2026-11-01 11:00:00.00 +0100"}
{
  "panicString" : "panic(cpu 6 caller 0xfffffe0000c0ffee): userspace watchdog timeout: no successful checkins from WindowServer (2 induced crashes) in 120 seconds\nDebugger message: panic\n",
  "processByPid" : {
    "312" : {"pid" : 312, "procname" : "WindowServer", "processUptime" : 500.0, "threadById" : {"1" : {"id" : 1, "name" : "ws_main_thread"}}}
}
}

System Profile:
Network Service: SecretAppZeta Network, Wi-Fi, en0
}
EOF
  printf '%s\r\n' '{"bug_type":"210","timestamp":"2026-11-01 11:01:00.00 +0100"}' '{' \
    '  "panicString" : "panic(cpu 6 caller 0xfffffe0000c0ffee): userspace watchdog timeout: no successful checkins from WindowServer (2 induced crashes) in 120 seconds\nDebugger message: panic\n",' \
    '  "processByPid" : {' \
    '    "4321" : {"pid" : 4321, "procname" : "swtor.exe", "processUptime" : 60.0, "threadById" : {"2" : {"id" : 2, "name" : "d9mt-compile"}}}' \
    '  }' '}' '' 'System Profile:' 'Network Service: SecretAppZeta Network, Wi-Fi, en0' | sr_plant panic-full-2026-11-01-110100.0006.panic 5
  sr_zip trailers
  # shellcheck disable=SC2034
  local tn="$d/panic-full-2026-11-01-110000.0005.panic.txt" tc="$d/panic-full-2026-11-01-110100.0006.panic.txt"
  check "system reports, trailers: the nested-brace panic read (WindowServer from its process list)" eval 'sr_has "$tn" "userspace watchdog timeout: no successful checkins from WindowServer" && sr_has "$tn" "WindowServer (pid 312): up 500 s, 1 threads"'
  check "system reports, trailers: the CRLF panic read (the game from its process list)" eval 'sr_has "$tc" "Debugger message: panic" && sr_has "$tc" "swtor.exe (pid 4321): up 60 s, 1 threads" && sr_has "$tc" "      d9mt-compile"'
  check "system reports, trailers: both counted, none malformed, nothing of the System Profile in the zip" eval 'grep -qxF "System reports of the last 48 h: 0 GPU faults, 0 WindowServer watchdog restarts, 2 kernel panics" "$SR_OUT/system-info.txt" && ! grep -r -l -E "SecretApp|System Profile|Network Service" "$SR_OUT" >/dev/null'
  rm -f "$SYSD"/*

  echo "  (run 2: an empty folder, the game started 3 days ago)"
  touch -t "$(date -v-72H +%Y%m%d%H%M)" "$logs/wine.log"
  sr_zip empty
  check "system reports, empty: the zip is written, no folder" eval '[ -f "$(cat "$SR/empty/zip")" ] && [ ! -e "$SR_OUT/system-reports" ]'
  check "system reports, empty: since the game's last start, none" grep -qE "^System reports since the game's last start \(7[23] h\): 0 GPU faults, 0 WindowServer watchdog restarts, 0 kernel panics \(no reports\)$" "$SR_OUT/system-info.txt"

  echo "  (run 3: no access to the folder; no game start, so 48 h)"
  rm -f "$logs/wine.log"
  chmod 000 "$SYSD"
  sr_zip noaccess
  chmod 755 "$SYSD"
  check "system reports, no access: the zip is written, the reason stated" eval '[ -f "$(cat "$SR/noaccess/zip")" ] && grep -qE "^System reports of the last 48 h: not read \(no access to [^)]*/system-diagnostics\)$" "$SR_OUT/system-info.txt" && [ ! -e "$SR_OUT/system-reports" ]'

  echo "  (run 4: no folder at all)"
  rmdir "$SYSD"
  sr_zip nofolder
  check "system reports, no folder: the zip is written, the reason stated" eval '[ -f "$(cat "$SR/nofolder/zip")" ] && grep -qE "^System reports of the last 48 h: not read \(no [^)]*/system-diagnostics\)$" "$SR_OUT/system-info.txt"'
  mkdir -p "$SYSD"
}
