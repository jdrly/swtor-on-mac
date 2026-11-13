#!/bin/bash
# SWTOR on Mac Wine wrapper (SWTOR_ON_MAC_WRAPPER v1)
#
# Installed by SWTOR on Mac as Wine/bin/wine64-preloader and Wine/bin/wine-preloader in the
# official SWTOR Mac install; Broadsword's real preloaders live in Wine/bin-real. Every Wine
# process the official launcher starts goes through the preloader (bin/wine64 itself stays
# the real Mach-O: the preloader loads it by path). This script reads the settings in $CONF
# and hands the process over to SWTOR on Mac's own Wine engine (CrossOver 26.3, Wine 11, with
# the d9mt Direct3D 9 -> Metal driver) and prefix. Without $CONF, or if the engine is gone, it
# runs Broadsword's real preloader unchanged, so the official setup keeps working. (It still
# runs an install of 0.0.x, CrossOver 24.0.7 with SWTOR_FRAMEWORKS, the same way: a failed
# upgrade puts that back.)
# Runs once per process start; nothing stays behind (for the game, hold-launcher waits for it
# and ends with it).
#
# The line below is filled in by SWTOR on Mac's installer (src/som.sh).
CONF="@CONF@"
REAL="$(cd "$(dirname "$0")/../bin-real" && pwd)/$(basename "$0")"

# the preloader runs more than once per process; only act the first time
[ -n "$SWTOR_WRAPPED" ] && exec "$REAL" "$@"
export SWTOR_WRAPPED=1
[ -f "$CONF" ] && set -a && . "$CONF" && set +a
LOG_DIR="${SWTOR_LOG_DIR:-$HOME/Library/Logs/SWTOR on Mac}"
# a missing engine (SWTOR on Mac half removed): run Broadsword's Wine instead
[ -n "$SWTOR_ENGINE" ] && [ ! -x "$SWTOR_ENGINE/bin/wine" ] && SWTOR_ENGINE=

# The daily update check (run detached, see below): one look at the app's Sparkle feed with
# a 2 s timeout; if it names a newer version than the installed one, a notification (the app
# then offers the update) and $SWTOR_APP_DIR/update-available for the app.
update_check() {
  stamp="$SWTOR_APP_DIR/last-update-check"
  now=$(date +%s)
  last=$(stat -f %m "$stamp" 2>/dev/null || echo 0)
  [ $((now - last)) -ge 86400 ] || return 0
  touch "$stamp" || return 0
  feed=$(/usr/bin/curl -fsL --max-time 2 "$SWTOR_UPDATE_FEED") || return 0
  latest=$(printf '%s\n' "$feed" | sed -n 's|.*<sparkle:shortVersionString>\([^<]*\)</sparkle:shortVersionString>.*|\1|p' | head -1)
  [ -n "$latest" ] || latest=$(printf '%s\n' "$feed" | sed -n 's|.*<sparkle:version>\([^<]*\)</sparkle:version>.*|\1|p' | head -1)
  [ -n "$latest" ] || return 0
  # newer: compare the dotted numbers; a prerelease (0.0.6-dev.1) is older than its release
  awk -v a="$latest" -v b="$SWTOR_ON_MAC_VERSION" 'BEGIN {
    pa = index(a, "-") > 0; pb = index(b, "-") > 0; sub(/-.*/, "", a); sub(/-.*/, "", b)
    n = split(a, x, "."); m = split(b, y, "."); if (m > n) n = m
    for (i = 1; i <= n; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 }
    exit !(pb && !pa) }' || return 0
  echo "$latest" >"$SWTOR_APP_DIR/update-available"
  notify "SWTOR on Mac update available ($latest) — open the app to update."
}

notify() {
  if [ -n "$SWTOR_NOTIFY_LOG" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >>"$SWTOR_NOTIFY_LOG"
  else
    /usr/bin/osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "SWTOR on Mac"' \
      -e 'end run' "$1"
  fi
}

# After the session's start ended leftover Wine processes (run detached, see below): did macOS
# end the last session because the launcher is not allowed in the background? One look at the
# last hour of macOS's log by the app's som.sh (btm-check, about a second, ended after 20 s at
# the latest; not if the app has moved since env was written), and if it says so, a notification
# with the setting to change.
btm_notice() {
  [ -f "$SWTOR_SOM_SH" ] || return 0
  SWTOR_ON_MAC_BTM_TIMEOUT="${SWTOR_ON_MAC_BTM_TIMEOUT:-20}" /bin/bash "$SWTOR_SOM_SH" btm-check 1h >/dev/null 2>&1 || return 0
  echo "$(date '+%Y-%m-%d %H:%M:%S') [wrapper $$] macOS ended the last Wine session when the launcher quit (not allowed in the background)" >>"$LOG_DIR/hold.log"
  notify "macOS ended the game's Wine when the SWTOR launcher quit. In System Settings > Login Items, turn on the launcher under App Background Activity."
}

# Frame Rate Limit (Settings): the cap d9mt gets for the game, D9MT_FPS_CAP. With "Only on
# battery", only if the Mac draws from its battery now: one look at macOS's power sources
# (pmset reads IOKit's), when the game starts; nothing watches it while the game runs.
# Sets fps_note for wine.log. (SWTOR_PMSET: a stand-in for tests.)
fps_limit() {
  fps_note=""
  case "${SWTOR_FPS_LIMIT:-0}" in 0|off|"") return 0 ;; esac
  if [ "$SWTOR_FPS_LIMIT_BATTERY" = 1 ]; then
    case "$("${SWTOR_PMSET:-/usr/bin/pmset}" -g ps 2>/dev/null | sed -n 1p)" in
      *"'Battery Power'"*) fps_note="$SWTOR_FPS_LIMIT fps (only on battery: on battery)" ;;
      *"'AC Power'"*) fps_note="off (only on battery: on AC power)"; return 0 ;;
      *) fps_note="off (only on battery: battery power not confirmed)"; return 0 ;;
    esac
  else
    fps_note="$SWTOR_FPS_LIMIT fps"
  fi
  export D9MT_FPS_CAP="$SWTOR_FPS_LIMIT"
}

# Fewer GPU Batches (Settings, experimental): d9mt's flush cap for the game, D9MT_FLUSH_CAP=1
# (d9mt #113; d9mt's own line is an info line, in wine.log only with Debug Logging on). A
# development build's $CONF reads d9mt-ab.env after its settings, so a D9MT_FLUSH_CAP set there
# (d9mt-ab.sh flush-cap, flush-cap-off) wins over Settings: keep that order. Sets flush_note
# for wine.log.
flush_cap() {
  flush_note=""
  [ "$SWTOR_FLUSH_CAP" = 1 ] || return 0
  if [ -n "${D9MT_FLUSH_CAP+set}" ] && [ "$D9MT_FLUSH_CAP" != 1 ]; then
    flush_note="D9MT_FLUSH_CAP=$D9MT_FLUSH_CAP from d9mt-ab, over Settings' on"
    return 0
  fi
  flush_note="on"
  export D9MT_FLUSH_CAP=1
}

# The game's language, from its command line: the values of "-set lang" and "-set torsets"
# only, their letters, digits and , . _ - (the line also holds the account name and session
# token, which are never read). Sets game_lang ("lang=de-de torsets=..." or "not given").
game_lang() {
  local key="" prev="" a
  game_lang=""
  for a in "$@"; do
    if [ "$prev" = -set ]; then key=$a
    elif [ -n "$key" ]; then
      case "$key" in lang|torsets) game_lang="$game_lang $key=$(printf '%s' "$a" | tr -cd 'A-Za-z0-9,._-' | cut -c1-40)" ;; esac
      key=""
    fi
    prev=$a
  done
  game_lang=${game_lang# }
  game_lang=${game_lang:-not given}
}

# What a game start ran with, for its wine.log (session-report.sh shows it; a before/after test
# tells its sessions apart by it). Each looks once, when the game starts; nothing watches;
# the ones that ask the system or read files run under session_diag's deadline.
# session_settings: Debug Logging, the Metal HUD, Game Mode and d9mt's, DXVK's and Metal's
# environment (D9MT_*, DXVK_*, MTL_*; a path's value left out, the rest only its letters,
# digits and , . ; : _ + = -)
session_settings() {
  printf 'debug-logging=%s hud=%s game-mode=%s' "$([ -n "$D9MT_PROFILE" ] && echo on || echo off)" \
    "$([ "$MTL_HUD_ENABLED" = 1 ] && echo on || echo off)" "$([ -n "$SWTOR_GAMEMODE_APP" ] && echo on || echo off)"
  env | LC_ALL=C grep -E '^(D9MT|DXVK|MTL)_[A-Za-z0-9_]*=' | LC_ALL=C sort | LC_ALL=C awk '{
    n = $0; sub(/=.*/, "", n); v = substr($0, length(n) + 2)
    if (v ~ /[\/\\]/) v = "(a path)"; else { gsub(/[^A-Za-z0-9,.;:_+=-]/, "", v); v = substr(v, 1, 80) }
    printf " %s=%s", n, v }'
  echo
}
# session_conditions: the power source, the energy mode (Low Power Mode) and macOS's thermal
# and performance warnings (pmset -g therm; "none" when it has recorded none). (SWTOR_PMSET: a
# stand-in for tests.)
session_conditions() {
  local pm="${SWTOR_PMSET:-/usr/bin/pmset}" ps em th
  ps=$("$pm" -g ps 2>/dev/null | sed -n "1s/.*'\(.*\)'.*/\1/p")
  # (macOS 26: "powermode 0/1/2", automatic, low power, high power; older: "lowpowermode 0/1")
  em=$("$pm" -g 2>/dev/null | awk '$1 == "powermode" { print ($2 == 1 ? "low power" : $2 == 2 ? "high power" : "automatic"); exit }
    $1 == "lowpowermode" { print ($2 == 1 ? "low power" : "automatic"); exit }')
  th=$("$pm" -g therm 2>/dev/null | LC_ALL=C awk '
    /^Note: No .* has been recorded/ { notes++; next }
    /[A-Za-z]/ { gsub(/[^A-Za-z0-9 _=.-]/, ""); gsub(/  +/, " "); w = w (w == "" ? "" : ", ") $0 }
    END { if (w != "") print w; else if (notes) print "none" }')
  echo "power ${ps:-unknown}, energy mode ${em:-unknown}, thermal warnings ${th:-unknown}"
}
# d9mt_files: the first 12 hex digits of the SHA-256 of d9mt's d3d9.dll in the prefix and its
# bridge in the engine (what ran, whatever the version label says)
d9mt_files() {
  local f h out=""
  for f in "$SWTOR_PREFIX/drive_c/windows/system32/d3d9.dll" "$SWTOR_ENGINE/lib/wine/x86_64-unix/winemetal.so"; do
    h=$(/usr/bin/shasum -a 256 "$f" 2>/dev/null | cut -c1-12)
    out="$out${out:+, }${f##*/} ${h:-missing}"
  done
  echo "$out"
}

# session_diag: session_conditions and d9mt_files, each in a process group of its own, both
# bounded by one deadline of SWTOR_DIAG_TIMEOUT s (default 2; they take about 70 ms): what isn't
# done by then is "unknown", its group is ended (TERM, KILL 0.2 s later) and waited for, so a
# stalled pmset or file read never holds the game's start longer, and nothing of it stays.
# Sets diag_conditions and diag_files.
session_diag() {
  local d pc pf i=0 n
  diag_conditions=unknown diag_files=unknown
  d=$(mktemp -d "${TMPDIR:-/tmp}/som-diag.XXXXXX") || return 0
  n=$((${SWTOR_DIAG_TIMEOUT:-2} * 20))
  set -m
  session_conditions </dev/null >"$d/c" 2>/dev/null & pc=$!
  d9mt_files </dev/null >"$d/f" 2>/dev/null & pf=$!
  set +m
  while { kill -0 "$pc" || kill -0 "$pf"; } 2>/dev/null && [ "$i" -lt "$n" ]; do sleep 0.05; i=$((i + 1)); done
  kill -TERM -- "-$pc" "-$pf" 2>/dev/null && sleep 0.2
  kill -KILL -- "-$pc" "-$pf" 2>/dev/null
  wait "$pc" "$pf" 2>/dev/null
  # (each writes its one line at its end: a group ended before that leaves an empty file)
  [ ! -s "$d/c" ] || diag_conditions=$(cat "$d/c")
  [ ! -s "$d/f" ] || diag_files=$(cat "$d/f")
  rm -rf "$d"
}

# DirectX 12 (Settings, development builds; env has SWTOR_DX12=1): the game's command with
# Broadsword's DirectX 12 client, swtor_RC2.exe from the same folder, in place of swtor.exe, every
# other argument as it was. The launcher's path to swtor.exe is a Unix path, or a Windows one
# (C:\...: found through the prefix's dosdevices). Without swtor_RC2.exe there, swtor.exe as
# always, and one line in hold.log (only the program's name: the path holds the user's home).
# Sets game_args (the command to run), game_exe and dx12_note for wine.log.
dx12_swap() {
  local a f done=""
  game_args=() game_exe=swtor.exe dx12_note=""
  for a in "$@"; do
    if [ -z "$done" ]; then
      case "$a" in
        swtor.exe|*/swtor.exe|*\\swtor.exe)
          done=1
          f="${a%swtor.exe}swtor_RC2.exe"
          case "$f" in
            [A-Za-z]:*) f="$SWTOR_PREFIX/dosdevices/$(printf '%s' "${f%%:*}" | tr 'A-Z' 'a-z'):${f#?:}" ;;
          esac
          if [ -f "${f//\\//}" ]; then
            a="${a%swtor.exe}swtor_RC2.exe" game_exe=swtor_RC2.exe
          else
            dx12_note="swtor_RC2.exe not found next to swtor.exe: starting swtor.exe"
            printf '%s [wrapper %d] DirectX 12: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" $$ "$dx12_note" >>"$LOG_DIR/hold.log" 2>/dev/null
          fi ;;
      esac
    fi
    game_args[${#game_args[@]}]=$a
  done
  [ "$game_exe" = swtor_RC2.exe ] || return 0
  # Wine's builtin d3d9 for it, not d9mt: Wine asks WINEDLLOVERRIDES before the registry's
  # AppDefaults\swtor_RC2.exe, and env gives every process d3d9=n,b
  export WINEDLLOVERRIDES="d3d9=b"
  # the driver's switches, for this start only
  case "$SWTOR_DX12_DRIVER" in
    gptk-mtl3) export D3DM_MTL4=0 ;;
  esac
  # (the DXGI tree as compatdb's swtor-dx12 rule in env names it)
  dx12_note="swtor_RC2.exe, driver ${SWTOR_DX12_DRIVER:-?} (dxgi=$(printf '%s\n' "$WINE_COMPATDB" | sed -n 's/^name=swtor-dx12;exe=swtor_RC2\.exe;dxgi=//p'))${D3DM_MTL4:+, D3DM_MTL4=$D3DM_MTL4}${SWTOR_DX12_DRIVER_VERSION:+, $SWTOR_DX12_DRIVER_VERSION}"
}

# wine.log is written anew at every game start: keep the last 4 sessions' as wine.log.1 (the
# one before) to wine.log.4, so a failed start isn't lost to the next one.
rotate_wine_log() {
  local i
  [ -f "$LOG_DIR/wine.log" ] || return 0
  for i in 3 2 1; do
    [ ! -f "$LOG_DIR/wine.log.$i" ] || mv -f "$LOG_DIR/wine.log.$i" "$LOG_DIR/wine.log.$((i + 1))"
  done
  mv -f "$LOG_DIR/wine.log" "$LOG_DIR/wine.log.1"
}

case " $* " in
  *swtor.exe*)
    mkdir -p "$LOG_DIR"
    # Record the Wine-related settings the launcher passes (no args: they hold account data)
    { date; env | grep -E '^(WINE|DXVK|MVK_|MTL_|DYLD_|CX_)' | sort; } > "$LOG_DIR/launch-env.txt"
    ;;
esac

if [ -n "$SWTOR_ENGINE" ]; then
  # Run this process on SWTOR on Mac's engine with its own prefix. $1 is Broadsword's
  # bin/wine64 (the loader the preloader would map); the rest is the command.
  shift
  # (WINEDLLPATH: CrossOver 26 starts processes from winetemp links only while it is set; the
  # game gets it below, with Game Mode on)
  unset WINELOADER WINELOADERNOEXEC WINEPRELOADRESERVE WINEPRELOADERDUMMYVAR WINESERVERSOCKET WINEDLLPATH
  export WINEPREFIX="$SWTOR_PREFIX"
  export DYLD_FALLBACK_LIBRARY_PATH="${SWTOR_FRAMEWORKS:+$SWTOR_FRAMEWORKS:}/usr/lib"
  mkdir -p "$LOG_DIR"
  # One line in hold.log per Wine start that is not the game: the time, the command's first
  # word only (the rest can hold the account token) and who started it (the launcher, or
  # Broadsword's mac_wine), next to hold-launcher's lines about the session.
  case " $* " in
    *swtor.exe*) ;;
    *) printf '%s [wrapper %d] wine start: %s (parent %d %s)\n' "$(date '+%Y-%m-%d %H:%M:%S')" $$ \
         "${1##*[/\\]}" "$PPID" "$(ps -o comm= -p "$PPID" 2>/dev/null | sed 's|.*/||')" >>"$LOG_DIR/hold.log" 2>/dev/null ;;
  esac
  # The prefix's Wine session, brought up by hold-launcher (next to the real preloaders): it
  # ends this prefix's leftover Wine processes (a session whose server is gone), starts the
  # engine's wineserver -p10 (it ends by itself 10 s after the last Wine process) in its own
  # session with nothing of this process open, and if that server is new, a bootstrap Wine
  # call starts Wine's system processes, so they don't inherit this command's stdout/stderr
  # (mac_wine reads its Wine calls' output to EOF) or the launcher's files. A no-op if the
  # session runs. Each step is logged in hold.log.
  hl=0
  "$(dirname "$REAL")/hold-launcher" --start-session "$LOG_DIR/wineserver.log" </dev/null >/dev/null 2>>"$LOG_DIR/hold.log" || hl=$?
  case $hl in
    0) ;;
    # it ended leftover Wine processes first: was the last session ended by macOS when the
    # launcher quit? (in a detached process: this Wine call doesn't wait for it)
    3) ( btm_notice & ) </dev/null >/dev/null 2>&1 ;;
    # (no or an older hold-launcher: the server alone; setsid-exec closes the inherited fds)
    *) ( exec "$(dirname "$REAL")/setsid-exec" "$SWTOR_ENGINE/bin/wineserver" -p10 ) </dev/null >/dev/null 2>>"$LOG_DIR/wineserver.log" ;;
  esac
  case " $* " in
    *swtor.exe*)
      # DirectX 12: the command from here on is game_args (swtor_RC2.exe if it is there)
      game_exe=swtor.exe dx12_note=""
      if [ "$SWTOR_DX12" = 1 ]; then dx12_swap "$@"; set -- "${game_args[@]}"; fi
      # Debug Logging: Wine debug channels for the game only (RAWMOUSE, THREADCPU lines)
      [ -z "$SWTOR_GAME_WINEDEBUG" ] || export WINEDEBUG="$SWTOR_GAME_WINEDEBUG"
      fps_limit
      flush_cap
      game_lang "$@"
      # (and the locale the game gets: a German one once failed where English worked)
      { date; env | grep -E '^(WINE|DYLD_|SWTOR_|DXVK_|MTL_|D9MT_|D3DM_|MULLION_|LANG=|LC_)' | sort
        echo "game language (from the launcher): $game_lang"; } > "$LOG_DIR/effective-env.txt"
      # Is there a newer SWTOR on Mac? At most once a day, in a detached process (the game
      # does not wait for it; offline it just fails).
      if [ "$SWTOR_UPDATE_CHECK" = 1 ] && [ -n "$SWTOR_UPDATE_FEED" ] && [ -d "$SWTOR_APP_DIR" ]; then
        ( update_check & ) </dev/null >/dev/null 2>&1
      fi
      # The game's stdout/stderr go to a file instead of the launcher's pipe, which closes when
      # the launcher quits (~30 s after starting the game).
      # SWTOR_LOG_FILTER set: keep the game's Wine/d9mt output in wine.log.
      if [ -n "$SWTOR_LOG_FILTER" ]; then
        # (before stderr goes to wine.log: the job control's messages, if any, go nowhere)
        session_diag 2>/dev/null
        rotate_wine_log
        exec >/dev/null 2>"$LOG_DIR/wine.log"
        # what this session runs on (session-report.sh shows it)
        echo "SWTOR on Mac ${SWTOR_ON_MAC_VERSION:-?}: engine ${SWTOR_ENGINE_ID:-cx24} ${SWTOR_ENGINE_NAME:-${SWTOR_ENGINE##*/}}, d9mt ${SWTOR_D9MT:-?}, started $(date '+%Y-%m-%d %H:%M:%S')" >&2
        # a development build's d9mt A/B switches (d9mt-ab.sh), if any
        [ -z "$SWTOR_D9MT_AB" ] || echo "SWTOR on Mac d9mt-ab: $SWTOR_D9MT_AB" >&2
        # the Frame Rate Limit, if one is set (d9mt's own "frame cap" line follows)
        [ -z "$fps_note" ] || echo "SWTOR on Mac frame rate limit: $fps_note" >&2
        # Fewer GPU Batches, if on (with Debug Logging, d9mt's "flush cap" line follows)
        [ -z "$flush_note" ] || echo "SWTOR on Mac flush cap: $flush_note" >&2
        # DirectX 12, if on: the client and its driver, or why swtor.exe runs instead
        [ -z "$dx12_note" ] || echo "SWTOR on Mac DirectX 12: $dx12_note" >&2
        # the game's language and locale (after those: the A/B switches stay the second line)
        echo "SWTOR on Mac game language: $game_lang, LANG=${LANG:-}" >&2
        # the settings, power and thermal state at the start, and the d9mt files' hashes
        echo "SWTOR on Mac settings: $(session_settings)" >&2
        echo "SWTOR on Mac conditions: $diag_conditions" >&2
        echo "SWTOR on Mac d9mt files: $diag_files" >&2
      else
        exec >/dev/null 2>/dev/null
      fi
      # Nothing holds the launcher: it quits ~30 s after starting the game, as with Broadsword's
      # own Wine, and macOS leaves the game (a foreground app) and the Wine session running.
      # macOS Game Mode: point the name CrossOver's ntdll starts the game from (a hard link
      # of the engine's loader in winetemp-<ino>-<size>-<mtime_s>-<mtime_ns>/, reused if
      # present) at the identical copy inside SWTOR.app, so gamepolicyd sees a bundle
      # executable with LSSupportsGameMode. Skipped if that copy no longer matches.
      #   CrossOver 26 (no wine-preloader; as SWGL on Mac does it): the loader is
      #   lib/wine/x86_64-unix/wine, ntdll uses the links only while WINEDLLPATH is set (to a
      #   harmless value: Wine's own lib/wine), and the first process of a wine command gets
      #   the name "wine": that is the game, unless the command is start.exe /exec <game>,
      #   whose child gets the game's name (swtor.exe, or swtor_RC2.exe for DirectX 12). The
      #   other names must not point at the bundle.
      #   CrossOver 24 (0.0.x): the loader is bin/wine-preloader, the game always swtor.exe.
      gm_exe="$SWTOR_GAMEMODE_APP/Contents/MacOS/swtor.exe"
      if [ -f "$SWTOR_ENGINE/bin/wine-preloader" ]; then
        gm_pre="$SWTOR_ENGINE/bin/wine-preloader" gm_name=swtor.exe gm_other="" gm_dllpath=""
      else
        gm_pre="$SWTOR_ENGINE/lib/wine/x86_64-unix/wine" gm_dllpath="$SWTOR_ENGINE/lib/wine"
        case " $* " in
          *" start.exe "*|*[/\\]start.exe" "*|*" start "*) gm_name=$game_exe ;;
          *) gm_name=wine ;;
        esac
        gm_other=""
        for gm_n in wine swtor.exe swtor_RC2.exe; do [ "$gm_n" = "$gm_name" ] || gm_other="$gm_other $gm_n"; done
      fi
      if [ -n "$SWTOR_GAMEMODE_APP" ] && cmp -s "$gm_pre" "$gm_exe" 2>/dev/null; then
        gm_m=$(stat -f '%Fm' "$gm_pre")
        gm_dir="$(getconf DARWIN_USER_TEMP_DIR)winetemp-$(stat -f '%i-%z' "$gm_pre")-${gm_m%.*}-$((10#${gm_m#*.}))"
        if mkdir -p -m 700 "$gm_dir" && ln -sf "$gm_exe" "$gm_dir/$gm_name" 2>>"$LOG_DIR/gamemode.log"; then
          for gm_n in $gm_other; do if [ -L "$gm_dir/$gm_n" ]; then rm -f "$gm_dir/$gm_n"; fi; done
          if [ -n "$gm_dllpath" ]; then
            export WINEDLLPATH="$gm_dllpath"
            echo "WINEDLLPATH=$WINEDLLPATH   (Game Mode)" >>"$LOG_DIR/effective-env.txt"
          fi
          # (the command's first word only: the rest has the account)
          gm_first=${1##*[/\\]}
          { date; echo "game mode: $gm_dir/$gm_name -> $gm_exe (command: $gm_first ...)${gm_dllpath:+, WINEDLLPATH=$gm_dllpath}"; } >>"$LOG_DIR/gamemode.log"
        fi
      elif [ -n "$SWTOR_GAMEMODE_APP" ]; then
        { date; echo "game mode skipped: $gm_exe missing or differs from $gm_pre"; } >>"$LOG_DIR/gamemode.log"
      fi
      # The game runs as hold-launcher's child, which takes this process's place: when it
      # ends, one line in hold.log (how long it ran, its exit code or signal, its language),
      # then hold-launcher ends the same way. It passes TERM, INT, HUP and QUIT on to the game.
      # (an older hold-launcher without --run-game: the game in this process, no line)
      hl="$(dirname "$REAL")/hold-launcher"
      if grep -q -a -F -e '--run-game' "$hl" 2>/dev/null; then
        exec "$hl" --run-game "$LOG_DIR/hold.log" "$game_lang" "$SWTOR_ENGINE/bin/wine" "$@"
      fi
      exec "$SWTOR_ENGINE/bin/wine" "$@"
      ;;
  esac
  exec "$SWTOR_ENGINE/bin/wine" "$@"
fi

case " $* " in
  *swtor.exe*)
    { date; env | grep -E '^(WINE|DYLD_|SWTOR_)' | sort; } > "$LOG_DIR/effective-env.txt"
    if [ -n "$SWTOR_LOG_FILTER" ]; then
      rotate_wine_log
      exec "$REAL" "$@" 2> >(grep --line-buffered -E "$SWTOR_LOG_FILTER" > "$LOG_DIR/wine.log")
    fi
    ;;
esac
exec "$REAL" "$@"
