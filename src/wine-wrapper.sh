#!/bin/bash
# SWTOR on Mac Wine wrapper (SWTOR_ON_MAC_WRAPPER v1)
#
# Installed by SWTOR on Mac as Wine/bin/wine64-preloader and Wine/bin/wine-preloader in the
# official SWTOR Mac install; Broadsword's real preloaders live in Wine/bin-real. Every Wine
# process the official launcher starts goes through the preloader (bin/wine64 itself stays
# the real Mach-O: the preloader loads it by path). This script reads the settings in $CONF
# and hands the process over to SWTOR on Mac's own Wine engine (CrossOver 24 with the d9mt
# Direct3D 9 -> Metal driver) and prefix. Without $CONF, or if the engine is gone, it runs
# Broadsword's real preloader unchanged, so the official setup keeps working.
# Runs once per process start; nothing stays behind.
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
  msg="SWTOR on Mac update available ($latest) — open the app to update."
  if [ -n "$SWTOR_NOTIFY_LOG" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" >>"$SWTOR_NOTIFY_LOG"
  else
    /usr/bin/osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "SWTOR on Mac"' \
      -e 'end run' "$msg"
  fi
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
  unset WINELOADER WINELOADERNOEXEC WINEPRELOADRESERVE WINEPRELOADERDUMMYVAR WINESERVERSOCKET
  export WINEPREFIX="$SWTOR_PREFIX"
  export DYLD_FALLBACK_LIBRARY_PATH="${SWTOR_FRAMEWORKS:+$SWTOR_FRAMEWORKS:}/usr/lib"
  mkdir -p "$LOG_DIR"
  # Start this engine's wineserver ourselves, in its own session, so it is not in the
  # launcher's process group; a no-op if one is already running. Not enough on its own:
  # when the launcher exits, this wineserver still dies (see hold-launcher below).
  # setsid-exec sits next to the real preloaders (not perl: macOS strips DYLD_* when it
  # starts SIP-protected binaries, and Wine needs them).
  setsid_exec() { exec "$(dirname "$REAL")/setsid-exec" "$@"; }
  # First, if no wineserver of the engine runs: end leftover Wine processes of the engine
  # (a session whose server is gone, e.g. the launcher's last Wine call after a game, when
  # the launcher stayed open longer than hold-launcher waits). Each is logged in hold.log.
  "$(dirname "$REAL")/hold-launcher" --reap </dev/null >/dev/null 2>>"$LOG_DIR/hold.log" || true
  ( setsid_exec "$SWTOR_ENGINE/bin/wineserver" -p 10 ) </dev/null >/dev/null 2>>"$LOG_DIR/wineserver.log"
  case " $* " in
    *swtor.exe*)
      { date; env | grep -E '^(WINE|DYLD_|SWTOR_|DXVK_|MTL_|D9MT_)' | sort; } > "$LOG_DIR/effective-env.txt"
      # Is there a newer SWTOR on Mac? At most once a day, in a detached process (the game
      # does not wait for it; offline it just fails).
      if [ "$SWTOR_UPDATE_CHECK" = 1 ] && [ -n "$SWTOR_UPDATE_FEED" ] && [ -d "$SWTOR_APP_DIR" ]; then
        ( update_check & ) </dev/null >/dev/null 2>&1
      fi
      # The game's stdout/stderr go to a file instead of the launcher's pipe: the held
      # (stopped) launcher does not drain that pipe, so a full pipe would block the game,
      # and once the launcher has quit, writes to it raise SIGPIPE and kill the game.
      # SWTOR_LOG_FILTER set: keep the game's Wine/d9mt output in wine.log.
      if [ -n "$SWTOR_LOG_FILTER" ]; then
        exec >/dev/null 2>"$LOG_DIR/wine.log"
      else
        exec >/dev/null 2>/dev/null
      fi
      # The launcher quits ~30 s after starting the game, and its exit takes this engine's
      # wineserver with it, so the game would hang. hold-launcher hides the launcher and
      # freezes it (SIGSTOP) until the game exits, then lets it finish quitting (SIGCONT).
      # It waits in kqueue for the exit of $$, which stays the game (the exec below keeps
      # this pid). Returns once the launcher is stopped; does nothing if it cannot find it.
      # After the launcher has quit, it ends the engine's session and its leftovers.
      "$(dirname "$REAL")/hold-launcher" $$ </dev/null >/dev/null 2>>"$LOG_DIR/hold.log"
      # macOS Game Mode: point the name CrossOver's ntdll re-execs the game from (a hard link
      # of bin/wine-preloader in winetemp-<ino>-<size>-<mtime_s>-<mtime_ns>/, reused if
      # present) at the identical copy inside SWTOR.app, so gamepolicyd sees a bundle
      # executable with LSSupportsGameMode. Skipped if that copy no longer matches.
      gm_exe="$SWTOR_GAMEMODE_APP/Contents/MacOS/swtor.exe"
      gm_pre="$SWTOR_ENGINE/bin/wine-preloader"
      if [ -n "$SWTOR_GAMEMODE_APP" ] && cmp -s "$gm_pre" "$gm_exe" 2>/dev/null; then
        gm_m=$(stat -f '%Fm' "$gm_pre")
        gm_dir="$(getconf DARWIN_USER_TEMP_DIR)winetemp-$(stat -f '%i-%z' "$gm_pre")-${gm_m%.*}-$((10#${gm_m#*.}))"
        mkdir -p -m 700 "$gm_dir" && ln -sf "$gm_exe" "$gm_dir/swtor.exe" 2>>"$LOG_DIR/gamemode.log"
      elif [ -n "$SWTOR_GAMEMODE_APP" ]; then
        { date; echo "game mode skipped: $gm_exe missing or differs from $gm_pre"; } >>"$LOG_DIR/gamemode.log"
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
      exec "$REAL" "$@" 2> >(grep --line-buffered -E "$SWTOR_LOG_FILTER" > "$LOG_DIR/wine.log")
    fi
    ;;
esac
exec "$REAL" "$@"
