#!/bin/bash
# SWTOR on Mac: the install, uninstall and status logic behind the app's window.
#
#   som.sh status      KEY=VALUE lines describing this Mac (what the window shows)
#   som.sh install     install or update; idempotent, safe to run again
#   som.sh uninstall   revert everything (the official install goes back to stock)
#   som.sh settings    KEY=VALUE lines: the settings (Settings window) and whether they can change
#   som.sh set K V     change one setting (retina, hud, gamemode, vsync, debug, physkeys,
#                      rawmouse: on/off; memory: auto/low/medium/high/ultra/unlimited;
#                      updates: on/off; mousespeed: one of MOUSE_SPEEDS)
#   som.sh watch       the launchd job (cz.jandrly.swtoronmac.watch): Broadsword's Wine/bin
#                      changed; hook the wrapper back in if a launcher update replaced it
#   som.sh end-leftovers  end leftover Wine processes of the engine (only if no launcher,
#                      game or Wine session runs); install, uninstall and the settings in the
#                      prefix's registry (retina, physkeys, rawmouse, mousespeed) do it too
#
# Environment:
#   SWTOR_ON_MAC_ROOT=/abs/dir  sandbox for tests: the official install, the app's own files,
#                               logs, caches and the per-user temp and cache dirs all live
#                               under it ($ROOT/Applications, $ROOT/home/Library/...,
#                               $ROOT/usertmp/, $ROOT/usercache/)
#   SWTOR_ON_MAC_DRY_RUN=1      print what would change and change nothing (no downloads,
#                               no Wine, no log file)
#   SWTOR_ON_MAC_FORCE=1        go ahead although Broadsword's Wine folder holds a Wine
#                               wrapper that is not SWTOR on Mac's (the app asks first)
#   SWTOR_ON_MAC_SETTLE=<s>     watch: how long Broadsword's Wine/bin must have been quiet
#                               before the wrapper is put back (default 20)
#
# In a sandbox (SWTOR_ON_MAC_ROOT) the launchd job is written but not loaded, and
# notifications go to <logs>/notifications.log instead of Notification Center.
#
# Lines for the app start with "@": "@phase <n>" (the app's timeline: install 1 download,
# 2 game files, 3 d9mt, 4 launcher hook; uninstall 1 restore, 2 game settings, 3 remove),
# "@step <text>", "@progress <label> <bytes> <total>", "@warn <text>", "@error <text>",
# "@done <text>". Everything else is plain log text.
# Runs under macOS's /bin/bash 3.2.
set -euo pipefail
RES="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(sed -n 's/^version=//p' "$RES/app.properties" 2>/dev/null || true)"
VERSION="${VERSION:-dev}"
# release, or dev: a development build (X.Y.Z-dev.N, GitHub pre-releases only). Dev builds turn
# Debug Logging on at their first install (dev_defaults) and never check for updates from the
# game's start.
CHANNEL="$(sed -n 's/^channel=//p' "$RES/app.properties" 2>/dev/null || true)"
CHANNEL="${CHANNEL:-release}"
D9MT_VERSION="$(cat "$RES/d9mt/VERSION" 2>/dev/null || echo unknown)"
# Sparkle's feed (the app's SUFeedURL, via app.properties): the wrapper's daily update check
FEED_URL="$(sed -n 's/^feed=//p' "$RES/app.properties" 2>/dev/null || true)"
FEED_URL="${FEED_URL:-https://github.com/jdrly/swtor-on-mac/releases/latest/download/appcast.xml}"

# --- Components: downloaded at install time from their official sources (never bundled).
# Bump name, URL, size and sha256 together.
# Wine engine: athei's build of CodeWeavers' CrossOver 26.3 (Wine 11.0, x86_64 WoW64;
# https://github.com/athei/wine-build), the engine SWGL on Mac uses. Self-contained (its
# libraries are in lib/external, found via @loader_path) and without a wine-preloader: every
# Wine process runs from its loader, lib/wine/x86_64-unix/wine.
ENGINE_ID=cx26
ENGINE_NAME=cx-26.3.0-8
ENGINE_TITLE="CrossOver 26.3 (Wine 11.0)"
ENGINE_URL=https://github.com/athei/wine-build/releases/download/cx-26.3.0-8/wine-cx-26.3.0-8-macos-x86_64.tar.xz
ENGINE_SIZE=234978748
ENGINE_SHA256=1976c3310a1f8be2f8e9a46fcb524f77b4316df3d281d94af2c8542bef60456d
# two of its files, checked after unpacking (the known-good engine)
ENGINE_LOADER_SHA256=2100dea802b2c560ba5d719c20ba1fcc1c8a09daf66580a4da6dd48e552d5a05
ENGINE_NTDLL_SHA256=f1ca0f092c9435299bb06f2e6e9c92b52b4b0ab5016a42c1a4ce01ccc18c9f4a
# its Mac driver (lib/wine/x86_64-unix/winemac.so and the PE sides lib/wine/x86_64-windows/
# and i386-windows/winemac.drv): the app's patched build (Resources/wine/,
# scripts/build-winemac.sh) replaces only these
ENGINE_WINEMAC_SHA256=e0ed7ac7405c21ae5644370aec778ff333c8ef6c27e45e6dd739ee83ad422001
ENGINE_WINEMAC_PE64_SHA256=eff4337246760e5752fe4bd19d729c860e8be0763f73f8787bb6543fcee9b43d
ENGINE_WINEMAC_PE32_SHA256=2de18f69739238fa5c6e1c4e9def2c153a7d96dd8502019d39778dc47a103054
# Its compatdb (the per-process Direct3D tree picker) defaults 64-bit processes to Apple's
# D3DMetal for DXGI, and the DXMT tree it falls back to brings its own winemetal.dll, which
# would not match d9mt's bridge. SWTOR is Direct3D 9 (d9mt from the prefix): DXGI stays on
# wined3d for every process.
ENGINE_COMPATDB='v=5
name=swtor-on-mac;exe=*;dxgi=wined3d'
# The engine of SWTOR on Mac 0.0.1-0.0.6 (Sikarugir's CrossOver 24.0.7, with Sikarugir's
# template libraries in $SOM/frameworks): an install over it upgrades the prefix and removes
# both once it has gone through (upgrade_from_old_engine).
OLD_ENGINE_SHA256=203f9e9fd6c2cc77e6525d798a434ced326145db34a356355e05659d3445fd1c

# --- Paths
ROOT="${SWTOR_ON_MAC_ROOT:-}"
DRY="${SWTOR_ON_MAC_DRY_RUN:-}"
FORCE="${SWTOR_ON_MAC_FORCE:-}"
if [ -n "$ROOT" ]; then
  case "$ROOT" in /*) ;; *) echo "@error SWTOR_ON_MAC_ROOT must be an absolute path"; exit 2 ;; esac
  # the real path (/tmp is /private/tmp): process paths are matched against it
  if [ -d "$ROOT" ]; then ROOT="$(cd "$ROOT" && pwd -P)"; fi
  H="$ROOT/home"
  APPS="$ROOT/Applications"
  USER_TMP="$ROOT/usertmp/"
  USER_CACHE="$ROOT/usercache/"
else
  H="$HOME"
  APPS=/Applications
  USER_TMP="$(getconf DARWIN_USER_TEMP_DIR)"
  # the per-user cache dir (/var/folders/.../C/), where d9mt keeps its caches in d9mt/:
  # air-cache.sqlite3 (compiled shaders), pso/ (pipeline archives) and state/ (the pipeline
  # state cache, D9MT_STATE_CACHE). They are d9mt's, shared with any other d9mt setup of this
  # user, and stay when SWTOR on Mac is uninstalled (macOS clears them when it needs space).
  USER_CACHE="$(getconf DARWIN_USER_CACHE_DIR)"
fi
BS_APP="$APPS/Star Wars - The Old Republic.app"
BS_DATA="$H/Library/Application Support/com.broadsword.swtor/Star Wars - The Old Republic"
BS_WINE="$BS_DATA/swtor-precompiled/Libraries/Wine"   # Broadsword's Wine, also its WINEPREFIX
SOM="$H/Library/Application Support/SWTOR on Mac"
LOGS="$H/Library/Logs/SWTOR on Mac"
CACHE="$H/Library/Caches/SWTOR on Mac"
MANIFEST="$SOM/install-manifest.json"
SETTINGS="$SOM/settings.conf"
PRELOADERS="wine-preloader wine64-preloader"
HELPERS="setsid-exec hold-launcher"
# The launchd job that puts the wrapper back after a launcher update (cmd_watch). It runs a
# copy of this script in $AGENT_DIR, so updating or moving the app does not break it.
AGENT_LABEL=cz.jandrly.swtoronmac.watch
AGENT_PLIST="$H/Library/LaunchAgents/$AGENT_LABEL.plist"
AGENT_DIR="$SOM/agent"
# What SWTOR on Mac keeps in $SOM (removed by uninstall; backup/ stays). frameworks: the old
# engine's libraries (0.0.x installs, until an install upgrades them); upgrade-backup: what an
# upgrade from 0.0.x keeps until it has gone through (begin_upgrade); d9mt-ab.env: development
# builds' d9mt A/B switches (Resources/d9mt-ab.sh, see write_env)
APP_FILES="engine prefix gamemode dxvk.conf env settings.conf agent last-update-check update-available dev-defaults frameworks upgrade-backup d9mt-ab.env"
LOGFILE=/dev/null

# The engine (one at a time) and the file every Wine process of it runs from: its loader
# (CrossOver's ntdll names its winetemp-<inode>-<size>-... links after that file).
# engine_loader <engine dir>: lib/wine/x86_64-unix/wine, or bin/wine-preloader in the CrossOver
# 24 engine of an install from 0.0.x that has not been upgraded yet
ENG="$SOM/engine"
engine_loader() {
  if [ -f "$1/bin/wine-preloader" ]; then echo "$1/bin/wine-preloader"; else echo "$1/lib/wine/x86_64-unix/wine"; fi
}
# Is the installed engine this version's? (no: SWTOR on Mac 0.0.x's, until Reinstall)
engine_current() { [ "$(cat "$ENG/.som-source" 2>/dev/null || true)" = "$ENGINE_SHA256" ]; }

# --- Output and logging
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOGFILE"; }
say() { echo "$*"; log "$*"; }
step() { echo "@step $*"; log "== $*"; }
phase() { echo "@phase $1"; }
warn() { echo "@warn $*"; log "WARNING: $*"; }
die() { echo "@error $*"; log "ERROR: $*"; exit 1; }

# run <command...>: a change to the system (only printed in a dry run)
run() {
  if [ -n "$DRY" ]; then
    printf '[dry-run]'; printf ' %q' "$@"; printf '\n'
  else
    { printf '+'; printf ' %q' "$@"; printf '\n'; } >>"$LOGFILE"
    "$@"
  fi
}

# put <file> <mode>: writes stdin to <file> atomically (a running bash may be reading it)
put() {
  if [ -n "$DRY" ]; then
    cat >/dev/null
    echo "[dry-run] write $1"
    return
  fi
  log "+ write $1"
  cat >"$1.new.$$"
  chmod "$2" "$1.new.$$"
  mv -f "$1.new.$$" "$1"
}

# copy_atomic <src> <dst> <mode>
copy_atomic() { run cp "$1" "$2.new.$$"; run chmod "$3" "$2.new.$$"; run mv -f "$2.new.$$" "$2"; }

# notify <text>: a macOS notification (one-shot osascript); in a sandbox, a line in
# notifications.log instead
notify() {
  log "notification: $*"
  if [ -n "$DRY" ]; then echo "[dry-run] notify: $*"; return; fi
  if [ -n "$ROOT" ]; then
    mkdir -p "$LOGS"
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOGS/notifications.log"
  else
    /usr/bin/osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "SWTOR on Mac"' \
      -e 'end run' "$*" >/dev/null 2>&1 || true
  fi
}

sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
is_macho() { [ -f "$1" ] && file -b "$1" 2>/dev/null | grep -q '^Mach-O'; }
json_get() { plutil -extract "$2" raw -o - "$1" 2>/dev/null || true; }   # <file> <keypath>

# --- Detection

# What sits at Broadsword's preloaders:
#   stock     the real preloaders, no bin-real
#   ours      SWTOR on Mac's wrapper
#   replaced  real preloaders back in bin, but bin-real still there (a launcher update
#             replaced the wrapper)
#   personal  the developer's own setup (swtor-mac-proper, reads ~/.config/swtor-mac/env)
#   foreign   some other wrapper
#   missing   no official Wine
wrapper_state_of() {
  local f="$BS_WINE/bin/$1"
  if [ ! -e "$f" ]; then echo missing
  elif is_macho "$f"; then
    if [ -e "$BS_WINE/bin-real/$1" ]; then echo replaced; else echo stock; fi
  elif grep -q 'SWTOR_ON_MAC_WRAPPER' "$f" 2>/dev/null; then echo ours
  elif grep -q '\.config/swtor-mac/env' "$f" 2>/dev/null; then echo personal
  else echo foreign
  fi
}
wrapper_state() {
  local a b
  a=$(wrapper_state_of wine64-preloader)
  b=$(wrapper_state_of wine-preloader)
  if [ "$a" = "$b" ]; then echo "$a"
  elif [ "$a" = missing ] || [ "$b" = missing ]; then echo missing
  else echo foreign
  fi
}

# The processes that matter for install/uninstall, one per line, "<kind> <pid> <program>":
#   launcher  the official launcher (anything in its app)
#   game      the game, swtor.exe (any engine)
#   wine      Broadsword's Wine
#   session   a wineserver of SWTOR on Mac's engine: a Wine session of it is running
#   engine    any other process of SWTOR on Mac's engine (its folder, or CrossOver's
#             winetemp-<loader inode>-... hard links of its loader)
# Programs are matched by their real executable (proc_pidpath, from hold-launcher --paths):
# Wine 11 rewrites argv[0], so ps shows C:\...\name.exe for its processes. The game is still
# found by that name (C:\...\swtor.exe, or a winetemp/... or Game Mode .../swtor.exe path).
proc_list() {
  local helper="$RES/helpers/hold-launcher"
  { if [ -x "$helper" ]; then "$helper" --paths 2>/dev/null | sed 's/^/P /'; fi
    ps -axww -o pid=,comm= 2>/dev/null | sed 's/^ */C /'; } |
  awk -v a="$BS_APP/" -v w="$BS_WINE/" -v e="$ENG/" -v s="$ENG/bin/wineserver" -v t="$(winetemp_tag)" '
    $1 == "P" { x = $0; sub(/^P [0-9]+ /, "", x); real[$2] = x; next }
    { pid = $2; prog = $0; sub(/^C [0-9]+ /, "", prog)
      exe = (pid in real) ? real[pid] : prog
      sub(/\/lib\/wine\/\.\.\/\.\.\/bin\//, "/bin/", exe) }   # a wineserver started by wine
    index(prog, a) || index(exe, a) || prog ~ /\/Star Wars - The Old Republic Launcher$/ { print "launcher", pid, prog; next }
    tolower(prog) ~ /[\/\\]swtor\.exe$/ || tolower(exe) ~ /\/swtor\.exe$/ { print "game", pid, prog; next }
    index(exe, w) { print "wine", pid, prog; next }
    exe == s { print "session", pid, prog; next }
    index(exe, e) == 1 || (t != "" && index(exe, t)) { print "engine", pid, prog }' || true
}

# busy_of <proc_list output>: what keeps install/uninstall from going ahead, the first of
# launcher, game, wine, session; else leftovers (only processes of SWTOR on Mac's engine,
# without its wineserver: what is left of a session whose server is gone), else none
busy_of() {
  local k
  for k in launcher game wine session; do
    if printf '%s\n' "$1" | grep -q "^$k "; then echo "$k"; return; fi
  done
  if printf '%s\n' "$1" | grep -q '^engine '; then echo leftovers; else echo none; fi
}

# proc_names <proc_list output> <kind>: the programs' names, "a, b"
proc_names() {
  printf '%s\n' "$1" | awk -v k="$2" '$1 == k { $1 = ""; $2 = ""; sub(/^ +/, ""); n = split($0, p, /[\/\\]/); print p[n] }' |
    sort -u | tr '\n' ',' | sed 's/,$//; s/,/, /g'
}

# busy_message <kind> <proc_list output>: why install/uninstall cannot go ahead
busy_message() {
  case "$1" in
    launcher) echo "Quit the SWTOR launcher first. Still running: $(proc_names "$2" launcher)" ;;
    game) echo "Quit the game first. Still running: $(proc_names "$2" game)" ;;
    wine) echo "Quit the SWTOR launcher and the game first: Broadsword's Wine is still running ($(proc_names "$2" wine))." ;;
    session) echo "SWTOR on Mac's Wine is still running (a Wine session: $(proc_names "$2" session)$(n=$(proc_names "$2" engine); [ -z "$n" ] || echo ", $n")). It ends by itself a few seconds after the launcher and the game have quit; try again then." ;;
  esac
}

# Is anything running that install/uninstall must wait for? (leftovers do not count: they
# are ended first, see end_leftovers)
running_now() { case "$(busy_of "$(proc_list)")" in launcher|game|wine|session) return 0 ;; esac; return 1; }

# Ends leftover Wine processes of SWTOR on Mac's engine: only when nothing else of SWTOR runs
# (no launcher, game, Broadsword's Wine, or wineserver of the engine), so they cannot belong
# to a Wine session. Only processes running from the engine's folder or from hard links of
# its loader; each is logged.
end_leftovers() {
  local l pids names
  l=$(proc_list)
  [ "$(busy_of "$l")" = leftovers ] || return 0
  pids=$(printf '%s\n' "$l" | awk '$1 == "engine" { print $2 }' | tr '\n' ' ')
  names=$(proc_names "$l" engine)
  if [ -n "$DRY" ]; then echo "[dry-run] end leftover Wine processes: $names (${pids% })"; return 0; fi
  # shellcheck disable=SC2086
  kill -9 $pids 2>/dev/null || true
  say "Ended leftover Wine processes of SWTOR on Mac's engine (no Wine session was running): $names (pids ${pids% })"
}

# CrossOver's ntdll runs Wine processes of an engine from hard links in
# winetemp-<loader inode>-<size>-... (CrossOver 26: only while WINEDLLPATH is set, as the
# wrapper does for the game with Game Mode on; CrossOver 24: always): the part of that name
# that is this engine's (nothing if there is no engine)
winetemp_tag() {
  local pre
  pre=$(engine_loader "$ENG")
  if [ -f "$pre" ]; then echo "/winetemp-$(stat -f '%i-%z' "$pre")-"; fi
}

rosetta_ok() { /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; }

status() {
  local s l b
  echo "version=$VERSION"
  echo "d9mt=$D9MT_VERSION"
  # this version's engine (what Install puts in place)
  echo "engine=$ENGINE_NAME"
  echo "engine_id=$ENGINE_ID"
  echo "engine_title=$ENGINE_TITLE"
  echo "root=${ROOT:-/}"
  echo "official_app=$([ -d "$BS_APP" ] && echo yes || echo no)"
  echo "official_app_path=$BS_APP"
  echo "official_wine=$([ -x "$BS_WINE/bin/wine64" ] && echo yes || echo no)"
  echo "official_wine_path=$BS_WINE"
  echo "rosetta=$(rosetta_ok && echo yes || echo no)"
  echo "arch=$(uname -m)"
  echo "macos=$(sw_vers -productVersion 2>/dev/null || echo unknown)"
  s=$(wrapper_state)
  echo "wrapper=$s"
  if [ -f "$MANIFEST" ]; then
    echo "installed=yes"
    echo "installed_version=$(json_get "$MANIFEST" version)"
    echo "installed_d9mt=$(json_get "$MANIFEST" d9mt)"
    # the engine in place (an install from 0.0.x: CrossOver 24.0.7 until Reinstall upgrades it)
    echo "installed_engine=$(json_get "$MANIFEST" engine)"
    echo "engine_current=$(engine_current && echo yes || echo no)"
    echo "watch_agent=$([ -f "$AGENT_PLIST" ] && [ -f "$AGENT_DIR/som.sh" ] && echo yes || echo no)"
    # a newer version the wrapper's daily check found (the app then offers it through Sparkle)
    echo "update_available=$(head -1 "$SOM/update-available" 2>/dev/null || true)"
  else
    echo "installed=no"
  fi
  # busy: launcher, game, wine, session (install/uninstall wait for those: running=yes),
  # leftovers (they end them first), none; busy_detail: the programs' names
  l=$(proc_list)
  b=$(busy_of "$l")
  echo "busy=$b"
  case "$b" in
    launcher|game|wine) echo "busy_detail=$(proc_names "$l" "$b")"; echo "running=yes" ;;
    session) echo "busy_detail=$(proc_names "$l" session)"; echo "running=yes" ;;
    leftovers) echo "busy_detail=$(proc_names "$l" engine)"; echo "running=no" ;;
    *) echo "busy_detail="; echo "running=no" ;;
  esac
  echo "app_dir=$SOM"
  echo "log_dir=$LOGS"
}

# --- Settings (the app's Settings window): $SETTINGS holds them as key=value; the env file,
# dxvk.conf, the prefix's Mac driver options (RetinaMode; for swtor.exe PhysicalKeyboard,
# RawMouseWhenCursorHidden, RawMouseGameControllerScale) and the engine's Mac driver are made
# from it. They survive a reinstall.
#   physkeys    "Game keys by keyboard position": swtor.exe gets PhysicalKeyboard=y
#   rawmouse    "Raw mouse-look": swtor.exe gets RawMouseWhenCursorHidden=y (while the game
#               hides the cursor: the mouse's own moves, from GCMouse, sent by the driver's
#               input thread, the macOS cursor frozen; patches/winemac-swgl-*.patch)
#   mousespeed  "Mouse-Look Speed": RawMouseGameControllerScale for swtor.exe, a factor on the
#               macOS pointer's speed (1: as with SWTOR on Mac 0.0.x)
# With physkeys or rawmouse on, the engine's Mac driver is the app's patched build
# (Resources/wine/), else the engine's own (install_winemac).
SETTING_KEYS="retina hud gamemode vsync debug memory updates physkeys rawmouse mousespeed"
MOUSE_SPEEDS="0.5 0.75 1 1.25 1.5 1.75 2 2.5 3"
setting_default() {
  case "$1" in
    retina|gamemode|vsync|updates|rawmouse) echo on ;;
    debug) if [ "$CHANNEL" = dev ]; then echo on; else echo off; fi ;;
    hud|physkeys) echo off ;;
    memory) echo auto ;;
    mousespeed) echo 1 ;;
  esac
}
setting_valid() { # <key> <value>
  case "$1:$2" in
    retina:on|retina:off|hud:on|hud:off|gamemode:on|gamemode:off|vsync:on|vsync:off) return 0 ;;
    debug:on|debug:off|updates:on|updates:off|physkeys:on|physkeys:off) return 0 ;;
    rawmouse:on|rawmouse:off) return 0 ;;
    memory:auto|memory:low|memory:medium|memory:high|memory:ultra|memory:unlimited) return 0 ;;
    mousespeed:*) case " $MOUSE_SPEEDS " in *" $2 "*) [ -n "$2" ] && return 0 ;; esac ;;
  esac
  return 1
}
setting() { # <key>: its value, or the default
  local v
  v=$(sed -n "s/^$1=//p" "$SETTINGS" 2>/dev/null | tail -1)
  if setting_valid "$1" "$v"; then echo "$v"; else setting_default "$1"; fi
}

write_settings() { # [<key> <value>]: settings.conf with every key, one of them changed
  local k v
  for k in $SETTING_KEYS; do
    v=$(setting "$k")
    if [ "$k" = "${1:-}" ]; then v=$2; fi
    echo "$k=$v"
  done | {
    echo "# SWTOR on Mac settings (change them in the app: SWTOR on Mac > Settings…)"
    cat
  } | put "$SETTINGS" 644
}

# A development build's first install (and Reinstall) turns Debug Logging on once per dev
# version, so every test session logs STATS/HITCH/DIAG MEM; Settings can still turn it off,
# and it stays off until the next dev version. Release builds keep the setting as it is.
dev_defaults() {
  local mark="$SOM/dev-defaults"
  if [ "$CHANNEL" = dev ] && [ "$(sed -n 's/^debug-on=//p' "$mark" 2>/dev/null)" != "$VERSION" ]; then
    say "Development build $VERSION: Debug Logging on (Settings can turn it off)"
    write_settings debug on
    [ -n "$DRY" ] || echo "debug-on=$VERSION" | put "$mark" 644
  else
    write_settings
  fi
}

settings() {
  local k
  echo "installed=$([ -f "$MANIFEST" ] && echo yes || echo no)"
  if running_now; then echo "running=yes"; else echo "running=no"; fi
  for k in $SETTING_KEYS; do echo "$k=$(setting "$k")"; done
}

# set_reg <key> <name> <value>: a REG_SZ value in HKCU, written straight into the prefix's
# user.reg (Wine reads it when its wineserver starts; none may run now, see cmd_set). <key> as
# in user.reg's section headers, with doubled backslashes: Software\\Wine\\Mac Driver
set_reg() {
  local reg="$SOM/prefix/user.reg"
  [ -f "$reg" ] || die "The Wine prefix is missing ($reg). Reinstall SWTOR on Mac."
  if [ -n "$DRY" ]; then echo "[dry-run] $2=$3 under $1 in $reg"; return; fi
  log "+ $2=$3 under $1 in $reg"
  # the section header in user.reg is [<key>] <time>
  K="[$1]" N="\"$2\"=" V="$3" T="$(date +%s)" awk '
    BEGIN { k = ENVIRON["K"]; n = ENVIRON["N"]; line = n "\"" ENVIRON["V"] "\"" }
    index($0, "[") == 1 {
      if (pending) { print line; pending = 0 }
      insec = (substr($0, 1, length(k)) == k && substr($0, length(k) + 1, 1) == " ")
      if (insec) { found = 1; pending = 1 }
      print; next
    }
    insec && index($0, n) == 1 { next }
    pending && index($0, "#time=") == 1 { print; next }
    pending { print line; pending = 0 }
    { print }
    END {
      if (pending) print line
      if (!found) { print ""; print k " " ENVIRON["T"]; print line }
    }' "$reg" >"$reg.new.$$"
  mv -f "$reg.new.$$" "$reg"
}

cmd_set() {
  local key="${1:-}" value="${2:-}"
  setting_valid "$key" "$value" || { echo "@error Unknown setting: $key=$value"; exit 2; }
  [ -f "$MANIFEST" ] || die "SWTOR on Mac is not installed."
  # an install from 0.0.x runs on its own engine until Reinstall upgrades it: settings written
  # for this version's engine would break it
  engine_current || die "SWTOR on Mac $(json_get "$MANIFEST" version) is installed. Click Reinstall to update it to $VERSION (with its new Wine engine) first, then change the settings."
  if [ -z "$DRY" ]; then mkdir -p "$LOGS"; LOGFILE="$LOGS/install.log"; fi
  log "---- set $key=$value"
  case "$key" in
    retina|physkeys|rawmouse|mousespeed)
      # Wine keeps the registry in its wineserver and writes it back on exit
      end_leftovers
      ! running_now || die "Quit the SWTOR launcher and the game to change $([ "$key" = retina ] && echo "Retina mode" || echo "this setting")." ;;
  esac
  lock
  trap 'rmdir "$SOM/.lock" 2>/dev/null || true' EXIT
  case "$key" in
    retina) set_reg 'Software\\Wine\\Mac Driver' RetinaMode "$([ "$value" = on ] && echo y || echo n)" ;;
    physkeys)
      install_winemac "$(winemac_wanted physkeys "$value")"
      set_reg 'Software\\Wine\\AppDefaults\\swtor.exe\\Mac Driver' PhysicalKeyboard "$([ "$value" = on ] && echo y || echo n)" ;;
    rawmouse)
      install_winemac "$(winemac_wanted rawmouse "$value")"
      set_reg 'Software\\Wine\\AppDefaults\\swtor.exe\\Mac Driver' RawMouseWhenCursorHidden "$([ "$value" = on ] && echo y || echo n)" ;;
    mousespeed) set_reg 'Software\\Wine\\AppDefaults\\swtor.exe\\Mac Driver' RawMouseGameControllerScale "$value" ;;
  esac
  write_settings "$key" "$value"
  write_env >/dev/null
  write_dxvk_conf
  echo "@done $key=$value. It takes effect the next time the game starts."
}

# --- Install steps

preflight() {
  [ "$(uname -m)" = arm64 ] || die "SWTOR on Mac needs a Mac with Apple Silicon."
  [ -d "$BS_APP" ] && [ -x "$BS_WINE/bin/wine64" ] ||
    die "The official SWTOR Mac app was not found. Install SWTOR from the official website (https://www.swtor.com) first, start it once so it sets up the game, then try again."
  rosetta_ok || die "Rosetta is not installed. Start the official SWTOR app once (macOS offers to install Rosetta), then try again."
  check_not_running
}

# Refuses while the launcher, the game or a Wine session runs; leftover Wine processes of the
# engine are ended first (logged)
check_not_running() {
  local l b
  end_leftovers
  l=$(proc_list)
  b=$(busy_of "$l")
  case "$b" in launcher|game|wine|session) die "$(busy_message "$b" "$l")" ;; esac
}

# check_wrapper <install|uninstall>: refuse over a wrapper that is not ours unless forced
check_wrapper() {
  WRAPPER_STATE=$(wrapper_state)
  case "$WRAPPER_STATE" in
    missing) die "Broadsword's Wine folder is incomplete ($BS_WINE/bin). Repair the official install first." ;;
    personal|foreign)
      if [ -z "$FORCE" ]; then
        [ "$WRAPPER_STATE" = personal ] &&
          die "Broadsword's Wine folder has a different Wine wrapper installed: the developer setup from swtor-mac-proper (it reads ~/.config/swtor-mac/env). SWTOR on Mac leaves it alone unless you confirm."
        die "Broadsword's Wine folder has a different Wine wrapper installed (not SWTOR on Mac's). SWTOR on Mac leaves it alone unless you confirm."
      fi
      warn "Replacing a $WRAPPER_STATE Wine wrapper (confirmed); a copy is kept in $SOM/backup"
      backup_foreign "$1" ;;
    replaced)
      [ -f "$MANIFEST" ] || [ -n "$FORCE" ] ||
        die "Broadsword's Wine folder has leftovers of a Wine wrapper that is not SWTOR on Mac's ($BS_WINE/bin-real). SWTOR on Mac leaves them alone unless you confirm." ;;
  esac
}

# A copy of a wrapper that is not ours (and its helpers), so it can be put back by hand
backup_foreign() {
  local dst f
  dst="$SOM/backup/wrapper-before-$1-$(date +%Y%m%d-%H%M%S)"
  run mkdir -p "$dst/bin" "$dst/bin-real"
  for f in $PRELOADERS; do
    if [ -f "$BS_WINE/bin/$f" ] && ! is_macho "$BS_WINE/bin/$f"; then run cp -p "$BS_WINE/bin/$f" "$dst/bin/"; fi
  done
  for f in $HELPERS; do
    if [ -f "$BS_WINE/bin-real/$f" ]; then run cp -p "$BS_WINE/bin-real/$f" "$dst/bin-real/"; fi
  done
  say "Copy of the previous wrapper: $dst"
}

# fetch <url> <sha256> <size> <label>: verified download into the cache; sets FETCHED
fetch() {
  local url=$1 sha=$2 size=$3 label=$4 dir="$CACHE/downloads" f pid
  f="$dir/$(basename "$url")"
  FETCHED=$f
  if [ -f "$f" ] && [ "$(sha256 "$f")" = "$sha" ]; then
    say "$label: using the verified download in the cache"
    return
  fi
  if [ -n "$DRY" ]; then
    echo "[dry-run] download $url ($size bytes, sha256 $sha) to $f"
    return
  fi
  mkdir -p "$dir"
  rm -f "$f.part"
  say "Downloading $label from $url"
  curl -fsSL --retry 3 --connect-timeout 20 -o "$f.part" "$url" 2>>"$LOGFILE" &
  pid=$!
  FETCH_PID=$pid
  while kill -0 "$pid" 2>/dev/null; do
    echo "@progress $label $(stat -f %z "$f.part" 2>/dev/null || echo 0) $size"
    sleep 1
  done
  wait "$pid" || { FETCH_PID=; rm -f "$f.part"; die "The download of $label failed. Check your internet connection and try again."; }
  FETCH_PID=
  echo "@progress $label $size $size"
  [ "$(sha256 "$f.part")" = "$sha" ] || { rm -f "$f.part"; die "The download of $label is damaged (checksum mismatch). Try again."; }
  mv -f "$f.part" "$f"
  log "verified $f (sha256 $sha)"
}

# winetemp_link <loader> <name>: a link in the winetemp folder CrossOver's ntdll starts Wine
# processes from, for that loader
winetemp_link() {
  local pre=$1 m
  m=$(stat -f '%Fm' "$pre")
  echo "${USER_TMP}winetemp-$(stat -f '%i-%z' "$pre")-${m%.*}-$((10#${m#*.}))/$2"
}
# The Game Mode links of the engine in place (symlinks only: ntdll's own entries are hard
# links): "wine" (the game as the first process of the wrapper's wine command) or "swtor.exe"
# (started through start.exe; CrossOver 24 always), see the wrapper
remove_gamemode_link() {
  local pre n l
  pre=$(engine_loader "$ENG")
  [ -f "$pre" ] || return 0
  for n in swtor.exe wine; do
    l=$(winetemp_link "$pre" "$n")
    if [ -L "$l" ]; then run rm -f "$l"; say "Removed the Game Mode link $l"; fi
  done
}

install_engine() {
  local dst="$ENG" w
  if engine_current && [ -x "$dst/bin/wine" ]; then
    say "Wine engine $ENGINE_TITLE ($ENGINE_NAME) is already in place"
  else
    fetch "$ENGINE_URL" "$ENGINE_SHA256" "$ENGINE_SIZE" "Wine engine"
    say "Unpacking the Wine engine ($ENGINE_TITLE)"
    run rm -rf "$dst.new"
    run mkdir -p "$dst.new"
    run tar -xJf "$FETCHED" -C "$dst.new" --strip-components 1 wine
    if [ -z "$DRY" ]; then
      [ "$(sha256 "$dst.new/lib/wine/x86_64-unix/wine")" = "$ENGINE_LOADER_SHA256" ] &&
        [ "$(sha256 "$dst.new/lib/wine/x86_64-unix/ntdll.so")" = "$ENGINE_NTDLL_SHA256" ] ||
        die "The unpacked Wine engine does not match the expected build."
      # its SDK (headers, Wine's conformance tests, man pages) is not needed to run it
      rm -rf "$dst.new/include" "$dst.new/lib/wine/tests" "$dst.new/share/man"
      echo "$ENGINE_SHA256" >"$dst.new/.som-source"
    fi
    remove_gamemode_link   # it names the old engine's loader
    if [ -n "${UPGRADE:-}" ] && [ -d "$dst" ]; then
      # 0.0.x's engine waits in upgrade-backup until the install has gone through
      run mv "$dst" "$SOM/upgrade-backup/engine"
    else
      run rm -rf "$dst"
    fi
    run mv "$dst.new" "$dst"
    CREATED="$CREATED engine"
  fi
  # d9mt's winemetal bridge replaces the engine's builtin winemetal (this copy only). Its
  # x86_64-windows winemetal.dll is only a placeholder (the real DXMT one lives in the
  # dxgi/dxmt tree, which DXGI never gets here: ENGINE_COMPATDB); the dxgi/dxmt tree's
  # winemetal.so is a link to the x86_64-unix one.
  w="$dst/lib/wine"
  say "Installing the d9mt bridge (winemetal) into the engine"
  copy_atomic "$RES/d9mt/winemetal.so" "$w/x86_64-unix/winemetal.so" 755
  copy_atomic "$RES/d9mt/winemetal.dll" "$w/x86_64-windows/winemetal.dll" 644
  install_winemac "$(winemac_wanted)"
}

# winemac_wanted [<key> <value>]: on if the engine needs the app's Mac driver (game keys by
# keyboard position or raw mouse-look on; <key> about to be set to <value>), else off
winemac_wanted() {
  local pk rm
  pk=$(setting physkeys) rm=$(setting rawmouse)
  case "${1:-}" in physkeys) pk=$2 ;; rawmouse) rm=$2 ;; esac
  if [ "$pk" = on ] || [ "$rm" = on ]; then echo on; else echo off; fi
}

# The engine's Mac driver, three files that go together (the PE sides start the raw mouse
# input thread of the unix side): <path in lib/wine> <the engine's sha256> <mode>
WINEMAC_FILES="x86_64-unix/winemac.so:$ENGINE_WINEMAC_SHA256:755
x86_64-windows/winemac.drv:$ENGINE_WINEMAC_PE64_SHA256:644
i386-windows/winemac.drv:$ENGINE_WINEMAC_PE32_SHA256:644"

# install_winemac <on|off>: the engine's Mac driver. On: the app's build of it
# (Resources/wine/: winemac.so, x86_64-windows/ and i386-windows/winemac.drv; scripts/
# build-winemac.sh with patches/ in the repository: the PhysicalKeyboard and raw mouse-look
# options, both off unless the prefix turns them on); off: the engine's own files, kept next
# to them as <name>.stock. Only over the engine build the patched one was made from
# (ENGINE_WINEMAC_*SHA256), so another engine never gets a mismatched driver. The PE sides go
# first when switching to the app's build and last when switching back (a PE side of the
# app's build only uses what the unix side says it has, see patches/winemac-swtor-mouse.patch).
install_winemac() {
  local w="$ENG/lib/wine" e f sha mode src order
  if [ -n "$DRY" ]; then echo "[dry-run] engine's Mac driver: $([ "$1" = on ] && echo "the app's" || echo "the engine's own")"; return; fi
  for e in $WINEMAC_FILES; do
    f=${e%%:*} sha=${e#*:} sha=${sha%%:*}
    if [ ! -f "$w/$f.stock" ]; then
      [ "$(sha256 "$w/$f")" = "$sha" ] ||
        die "The Wine engine's Mac driver ($f) is not the expected build. Uninstall SWTOR on Mac and install it again."
      run cp -p "$w/$f" "$w/$f.stock"
    fi
    [ "$(sha256 "$w/$f.stock")" = "$sha" ] ||
      die "The Wine engine's copy of its Mac driver ($f.stock) is damaged. Uninstall SWTOR on Mac and install it again."
  done
  if [ "$1" = on ]; then
    for e in $WINEMAC_FILES; do
      f=${e%%:*}
      [ -f "$RES/wine/${f#x86_64-unix/}" ] || die "This app has no Mac driver build ($RES/wine/${f#x86_64-unix/})."
    done
    say "Installing the app's Mac driver (game keys by keyboard position, raw mouse-look) into the engine"
    order="x86_64-windows/winemac.drv i386-windows/winemac.drv x86_64-unix/winemac.so"
  else
    say "Using the engine's own Mac driver"
    order="x86_64-unix/winemac.so x86_64-windows/winemac.drv i386-windows/winemac.drv"
  fi
  for f in $order; do
    mode=$(printf '%s\n' "$WINEMAC_FILES" | awk -F: -v f="$f" '$1 == f { print $3 }')
    if [ "$1" = on ]; then src="$RES/wine/${f#x86_64-unix/}"; else src="$w/$f.stock"; fi
    cmp -s "$src" "$w/$f" || copy_atomic "$src" "$w/$f" "$mode"
  done
  # the manifest says which (written by install; a settings change updates it)
  if [ -f "$MANIFEST" ]; then
    plutil -replace winemac -string "$([ "$1" = on ] && echo app || echo stock)" "$MANIFEST"
    plutil -replace winemac_sha256 -string "$(sha256 "$w/x86_64-unix/winemac.so")" "$MANIFEST"
  fi
}

# wine <args...> with SWTOR on Mac's engine and prefix (output goes to the log). The engine is
# self-contained (no library path); its compatdb rule as in the env file.
wine_do() {
  if [ -n "$DRY" ]; then echo "[dry-run] wine $*"; return; fi
  log "+ wine $*"
  env -u WINELOADER -u WINESERVER -u WINEDLLOVERRIDES -u WINEDLLPATH -u SWTOR_WRAPPED -u DYLD_FALLBACK_LIBRARY_PATH \
    WINEPREFIX="$SOM/prefix" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" WINE_COMPATDB="$ENGINE_COMPATDB" \
    "$ENG/bin/wine" "$@" </dev/null >>"$LOGFILE" 2>&1
}

# End this prefix's Wine session and make sure nothing of it stays running: a leftover
# wineserver started from here would break the next game start from the launcher.
stop_wine() {
  [ -n "$DRY" ] && { echo "[dry-run] wineserver -k"; return; }
  [ -x "$ENG/bin/wineserver" ] || return 0
  # (0.0.x's engine, until upgraded, needs its libraries for wineserver: libinotify)
  local fb=/usr/lib
  [ ! -d "$SOM/frameworks" ] || fb="$SOM/frameworks:/usr/lib"
  WINEPREFIX="$SOM/prefix" DYLD_FALLBACK_LIBRARY_PATH="$fb" "$ENG/bin/wineserver" -k >>"$LOGFILE" 2>&1 || true
  WINEPREFIX="$SOM/prefix" DYLD_FALLBACK_LIBRARY_PATH="$fb" "$ENG/bin/wineserver" -w >>"$LOGFILE" 2>&1 || true
  local left
  for _ in 1 2 3 4 5; do
    # (by real executable: Wine 11's processes show C:\... names in ps)
    left=$(proc_list | awk '$1 == "engine" || $1 == "session" { print $2 }')
    [ -z "$left" ] && return 0
    sleep 1
  done
  warn "Ending leftover Wine processes: $(echo "$left" | tr '\n' ' ')"
  echo "$left" | xargs kill -9 2>/dev/null || true
}

install_prefix() {
  local p="$SOM/prefix" sys u item
  if [ ! -d "$p" ]; then
    say "Creating SWTOR on Mac's Wine prefix (an APFS clone of Broadsword's, nothing is copied)"
    run rm -rf "$p.new"
    run mkdir -p "$p.new"
    for item in drive_c dosdevices system.reg user.reg userdef.reg .update-timestamp; do
      [ -e "$BS_WINE/$item" ] || [ -L "$BS_WINE/$item" ] || continue
      run cp -c -R -P -p "$BS_WINE/$item" "$p.new/"
    done
    run mv "$p.new" "$p"
    CREATED="$CREATED prefix"
    NEW_PREFIX=1
  else
    say "Updating the existing Wine prefix (your game settings in it are kept)"
  fi
  say "Updating the prefix for the new engine (wineboot, about a minute)"
  wine_do wineboot -u || { stop_wine; die "Wine could not set up the prefix (details in $LOGS/install.log)."; }
  say "Setting Wine options: Retina mode, mouse-look fix, game keys by position, raw mouse-look and its speed, d9mt for swtor.exe"
  wine_do reg add 'HKCU\Software\Wine\Mac Driver' /v RetinaMode /t REG_SZ /d "$([ "$(setting retina)" = on ] && echo y || echo n)" /f &&
    wine_do reg add 'HKCU\Software\Wine\AppDefaults\swtor.exe\X11 Driver' /v GrabPointer /t REG_SZ /d n /f &&
    wine_do reg add 'HKCU\Software\Wine\AppDefaults\swtor.exe\Mac Driver' /v PhysicalKeyboard /t REG_SZ /d "$([ "$(setting physkeys)" = on ] && echo y || echo n)" /f &&
    wine_do reg add 'HKCU\Software\Wine\AppDefaults\swtor.exe\Mac Driver' /v RawMouseWhenCursorHidden /t REG_SZ /d "$([ "$(setting rawmouse)" = on ] && echo y || echo n)" /f &&
    wine_do reg add 'HKCU\Software\Wine\AppDefaults\swtor.exe\Mac Driver' /v RawMouseGameControllerScale /t REG_SZ /d "$(setting mousespeed)" /f &&
    wine_do reg add 'HKCU\Software\Wine\AppDefaults\swtor.exe\Mac Driver' /v ThreadCpuStats /t REG_SZ /d y /f &&
    wine_do reg add 'HKCU\Software\Wine\AppDefaults\swtor.exe\DllOverrides' /v d3d9 /t REG_SZ /d native,builtin /f ||
    { stop_wine; die "Wine could not write the settings (details in $LOGS/install.log)."; }
  stop_wine

  # Game settings (graphics, UI layouts, key bindings) the official setup already has:
  # this engine runs as Wine user "crossover", so a new prefix starts with a clone of them.
  if [ -n "${NEW_PREFIX:-}" ] && [ ! -e "$p/drive_c/users/crossover/AppData/Local/SWTOR" ]; then
    for u in "$p"/drive_c/users/*; do
      case "${u##*/}" in Public|crossover) continue ;; esac
      if [ -d "$u/AppData/Local/SWTOR" ]; then
        say "Taking over the game settings of Wine user ${u##*/}"
        SETTINGS_USER=${u##*/}
        run mkdir -p "$p/drive_c/users/crossover/AppData/Local"
        run cp -c -R -p "$u/AppData/Local/SWTOR" "$p/drive_c/users/crossover/AppData/Local/"
        break
      fi
    done
  fi

  sys="$p/drive_c/windows/system32"
  phase 3
  say "Installing d9mt ($D9MT_VERSION) as the game's Direct3D 9"
  if [ -z "$DRY" ] && [ ! -e "$sys/d3d9.dll.wine" ]; then
    [ -f "$sys/d3d9.dll" ] || die "Wine's d3d9.dll is missing in the prefix."
    # (Wine's own: a builtin copy, or the engine's "Wine placeholder DLL", its compatdb picks
    # the d3d9 tree)
    if dd if="$sys/d3d9.dll" bs=1 skip=64 count=24 2>/dev/null | grep -q 'Wine builtin\|Wine placeholder'; then
      run mv "$sys/d3d9.dll" "$sys/d3d9.dll.wine"
    else
      warn "system32/d3d9.dll is not Wine's own; replacing it without keeping a copy"
    fi
  fi
  copy_atomic "$RES/d9mt/d3d9.dll" "$sys/d3d9.dll" 644
}

# The Game Mode bundle (as SWGL on Mac makes it for this engine): a clone of the engine's loader
# as the bundle's executable, and an ntdll.so link next to it (the loader looks for ntdll.so
# beside its resolved path; ntdll then finds the rest of the engine from its own real path).
# No LSUIElement (the loader has its own embedded Info.plist anyway).
install_gamemode() {
  local app="$SOM/gamemode/SWTOR.app" new pre
  pre=$(engine_loader "$ENG")
  say "Creating the Game Mode bundle"
  new="$SOM/gamemode/.SWTOR.app.new.$$"
  run rm -rf "$new"
  run mkdir -p "$new/Contents/MacOS"
  put "$new/Contents/Info.plist" 644 <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>swtor.exe</string>
	<key>CFBundleIdentifier</key><string>cz.jandrly.swtoronmac.game</string>
	<key>CFBundleName</key><string>Star Wars: The Old Republic</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>$VERSION</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.role-playing-games</string>
	<key>LSSupportsGameMode</key><true/>
	<key>GCSupportsGameMode</key><true/>
</dict>
</plist>
EOF
  # An APFS clone of the loader, not a re-signed copy: the same bytes keep the same code
  # identity and Rosetta cache. Must stay byte-identical to the engine's loader: the wrapper
  # checks. (relative link: Contents/MacOS -> $SOM/engine/lib/wine/x86_64-unix/ntdll.so)
  run cp -c "$pre" "$new/Contents/MacOS/swtor.exe"
  run ln -s "../../../../engine/lib/wine/x86_64-unix/ntdll.so" "$new/Contents/MacOS/ntdll.so"
  run rm -rf "$app"
  run mv "$new" "$app"
}

write_env() {
  local gm hud dbg upd notify_log="" ab=""
  say "Writing the settings file $SOM/env"
  gm="SWTOR_GAMEMODE_APP=\"$SOM/gamemode/SWTOR.app\""
  [ "$(setting gamemode)" = on ] || gm="#$gm   (Game Mode is off in Settings)"
  hud="MTL_HUD_ENABLED=1"
  [ "$(setting hud)" = on ] || hud="#$hud   (off in Settings)"
  if [ "$(setting debug)" = on ]; then
    dbg="# Debug logging is on in Settings: d9mt's info messages, per-frame timing (HITCH, PSOBUILD,
# STATS and RESTORE once a second) and memory statistics (DIAG MEM) in wine.log. Costs some
# performance.
DXVK_LOG_LEVEL=info
D9MT_PROFILE=1
D9MT_MEMSTATS=1
# d9mt's live debug flags, read once a second while the game runs: $D9MT_FLAGS_FILE
# (one flag per line, # comments; the file lists them)
D9MT_DEBUG_FILE='C:\\d9mt\\flags.txt'
# Wine debug output of the game (the wrapper uses it for swtor.exe only): RAWMOUSE (raw
# mouse-look, once a second while it moves) and THREADCPU (CPU time of the game's busiest
# threads and of the wineserver, once a second; ThreadCpuStats=y for swtor.exe in the prefix,
# so not from the session's other processes) from the app's Mac driver
SWTOR_GAME_WINEDEBUG=-all,warn+rawmouse,warn+threadcpu"
    write_d9mt_flags
  else
    dbg="# d9mt's own warnings and errors only (cheap); Debug logging in Settings adds more
DXVK_LOG_LEVEL=warn"
  fi
  upd=$([ "$(setting updates)" = on ] && echo 1 || echo 0)
  # development builds: no update check from the game's start (Updates.swift: no automatic
  # Sparkle checks either; Check for Updates… still works)
  [ "$CHANNEL" = release ] || upd=0
  # in a sandbox, the update check's notification goes to a file
  [ -z "$ROOT" ] || notify_log="SWTOR_NOTIFY_LOG=\"$LOGS/notifications.log\""
  # Development builds: d9mt's A/B switches for the next game starts (Resources/d9mt-ab.sh) live
  # in a file of their own, so rewriting this one (Settings, Reinstall) keeps them. Release
  # builds never read it.
  if [ "$CHANNEL" = dev ]; then
    ab="
# Development build: d9mt's A/B switches set by d9mt-ab.sh in the app's Resources (its status
# shows them), until it resets them
[ ! -f \"$SOM/d9mt-ab.env\" ] || . \"$SOM/d9mt-ab.env\""
  fi
  put "$SOM/env" 644 <<EOF
# SWTOR on Mac $VERSION: settings the Wine wrapper in Broadsword's Wine folder reads at every
# Wine start. Made from settings.conf by the installer and the app's Settings window, which
# overwrite this file: change the settings there.

# Faster Wine thread sync, no Wine debug output
WINEMSYNC=1
WINEDEBUG=-all

# SWTOR on Mac's Wine engine ($ENGINE_TITLE, self-contained) and prefix
SWTOR_ENGINE="$ENG"
SWTOR_ENGINE_ID=$ENGINE_ID
SWTOR_ENGINE_NAME=$ENGINE_NAME
SWTOR_PREFIX="$SOM/prefix"
SWTOR_D9MT=$D9MT_VERSION
# the engine's compatdb: DXGI on wined3d for every process (no D3DMetal, no DXMT winemetal)
WINE_COMPATDB='$ENGINE_COMPATDB'
# macOS Game Mode: the game runs from a bundle copy of the engine's loader
$gm
SWTOR_LOG_DIR="$LOGS"
SWTOR_LOG_FILTER=.

# d9mt: Direct3D 9 straight to Metal (d3d9.dll in the prefix, winemetal bridge in the engine)
WINEDLLOVERRIDES="d3d9=n,b"
DXVK_CONFIG_FILE="$SOM/dxvk.conf"
# how much video memory d9mt keeps in use: auto (by the Mac's memory), low, medium, high,
# ultra, unlimited
D9MT_MEMORY_PROFILE=$(setting memory)
# d9mt's pipeline state cache: the pipelines the game used, rebuilt in the background at the
# next start; in the per-user cache dir, next to d9mt's shader cache and pipeline archives
D9MT_STATE_CACHE="${USER_CACHE}d9mt/state"
$dbg

# Apple's Metal HUD (FPS, frame times)
$hud

# At most once a day, when the game starts: look for a newer SWTOR on Mac (a notification
# if there is one; the app updates itself)
SWTOR_ON_MAC_VERSION=$VERSION
SWTOR_APP_DIR="$SOM"
SWTOR_UPDATE_FEED="$FEED_URL"
SWTOR_UPDATE_CHECK=$upd
$notify_log$ab
EOF
}

# Debug Logging: d9mt's live debug flags file in the prefix (D9MT_DEBUG_FILE=C:\d9mt\flags.txt).
# Written once, with every flag commented out; edits are kept. d9mt also writes its frame
# dumps (flag dump) and d9mt-debug.log into that folder. Gone with the prefix at Uninstall.
D9MT_FLAGS_FILE="$SOM/prefix/drive_c/d9mt/flags.txt"
write_d9mt_flags() {
  [ -d "$SOM/prefix/drive_c" ] || return 0
  [ -f "$D9MT_FLAGS_FILE" ] && return 0
  run mkdir -p "${D9MT_FLAGS_FILE%/*}"
  put "$D9MT_FLAGS_FILE" 644 <<'EOF'
# d9mt live debug flags (SWTOR on Mac, Debug Logging on). d9mt reads this file once a second
# while the game runs; a flag is on while its line is here without the leading #. Output goes
# to ~/Library/Logs/SWTOR on Mac/wine.log.
#
# no_attach_opt   attachment load/store optimization off (the previous Load/Store actions), for A/B
# att_trace       log up to 400 render-pass load/store decisions and re-clears (D9MT-ATT lines);
#                 remove the line and add it again for the next 400
# dump            dump the next frame's draws to d9mt-dump-<n>.txt in this folder (re-save the
#                 file for another; ignored if already here when the game starts)
EOF
}

# d9mt's options: Resources/dxvk.conf, with vsync (d3d9.presentInterval = 1) unless it is
# off in Settings
write_dxvk_conf() {
  if [ "$(setting vsync)" = on ]; then
    put "$SOM/dxvk.conf" 644 <"$RES/dxvk.conf"
  else
    sed 's/^d3d9\.presentInterval = 1$/# d3d9.presentInterval = 1   (vsync is off in Settings)/' "$RES/dxvk.conf" |
      put "$SOM/dxvk.conf" 644
  fi
}

# Puts the wrapper in place of Broadsword's preloaders; the real ones go to bin-real.
install_wrapper() {
  local bin="$BS_WINE/bin" real="$BS_WINE/bin-real" b h conf_esc
  WRAPPER_PHASE=1
  BIN_REAL_EXISTED=$([ -d "$real" ] && echo true || echo false)
  run mkdir -p "$real"
  ORIG_SHAS=""
  for b in $PRELOADERS; do
    if is_macho "$bin/$b"; then
      # Broadsword's real preloader: first install, or the launcher updated its Wine since
      run mv -f "$bin/$b" "$real/$b"
      MOVED="$MOVED $b"
    fi
    if [ -z "$DRY" ]; then
      is_macho "$real/$b" || die "Broadsword's real $b is missing (neither in bin nor in bin-real). Repair the official install first."
      ORIG_SHAS="$ORIG_SHAS $b=$(sha256 "$real/$b")"
    fi
  done
  conf_esc=$(printf '%s' "$SOM/env" | sed 's/[&|\\]/\\&/g')
  for b in $PRELOADERS; do
    sed "s|@CONF@|$conf_esc|" "$RES/wine-wrapper.sh" | put "$bin/$b" 755
  done
  # helpers the wrapper runs (replaced atomically too: a running game may be using them)
  for h in $HELPERS; do
    copy_atomic "$RES/helpers/$h" "$real/$h" 755
  done
  WRAPPER_PHASE=
}

# Undo a half-done install_wrapper (the real preloaders go back where they were)
rollback_wrapper() {
  local b
  for b in $MOVED; do
    if [ -f "$BS_WINE/bin-real/$b" ]; then
      mv -f "$BS_WINE/bin-real/$b" "$BS_WINE/bin/$b" 2>/dev/null && log "rolled back $b"
    fi
  done
  if [ "${BIN_REAL_EXISTED:-true}" = false ]; then
    for b in $HELPERS; do rm -f "$BS_WINE/bin-real/$b"; done
    rm -f "$BS_WINE/bin-real"/.*.new.* 2>/dev/null || true
    rmdir "$BS_WINE/bin-real" 2>/dev/null || true
  fi
}

write_manifest() {
  local b sha pre="" first=1 user
  # the Wine user in Broadsword's prefix whose game settings were taken over (Uninstall
  # copies them back there); kept from an earlier install
  user=${SETTINGS_USER:-$(json_get "$MANIFEST" settings_user)}
  user=${user:-$(bs_settings_user)}
  for b in $PRELOADERS; do
    sha=$(echo "$ORIG_SHAS" | tr ' ' '\n' | sed -n "s/^$b=//p")
    [ $first = 1 ] || pre="$pre,"
    pre="$pre
    \"$b\": \"$sha\""
    first=0
  done
  put "$MANIFEST" 644 <<EOF
{
  "app": "SWTOR on Mac",
  "version": "$VERSION",
  "installed": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "d9mt": "$D9MT_VERSION",
  "engine_id": "$ENGINE_ID",
  "engine": "$ENGINE_NAME",
  "engine_sha256": "$ENGINE_SHA256",
  "winemac": "$([ "$(winemac_wanted)" = on ] && echo app || echo stock)",
  "winemac_sha256": "$([ -n "$DRY" ] || sha256 "$ENG/lib/wine/x86_64-unix/winemac.so")",
  "broadsword_wine": "$BS_WINE",
  "previous_wrapper": "$WRAPPER_STATE",
  "bin_real_created": $([ "$BIN_REAL_EXISTED" = false ] && echo true || echo false),
  "settings_user": "$user",
  "original_preloaders_sha256": {$pre
  },
  "helpers": ["setsid-exec", "hold-launcher"],
  "app_files": ["$(echo $APP_FILES | sed 's/ /", "/g')"],
  "launch_agent": "$AGENT_PLIST"
}
EOF
}

# --- Game settings (graphics options, UI layouts, key bindings): a new prefix starts with a
# clone of those in Broadsword's prefix (install_prefix); Uninstall copies them back.
GAME_SETTINGS_REL="AppData/Local/SWTOR/swtor/settings"

# The Wine user in Broadsword's prefix that has SWTOR's settings (Broadsword's Wine names it
# after the Mac user)
bs_settings_user() {
  local u
  for u in "$BS_WINE"/drive_c/users/*; do
    case "${u##*/}" in Public|crossover|\*) continue ;; esac
    if [ -d "$u/AppData/Local/SWTOR" ]; then echo "${u##*/}"; return; fi
  done
}

# Copies the game settings of SWTOR on Mac's prefix (Wine user crossover) back to
# Broadsword's prefix, so changes made while using SWTOR on Mac stay. Broadsword's previous
# folder is kept as settings-backup-<time> next to it (an APFS clone); files only it has stay.
# ContextError.ini (the game's last error) is not copied. Nothing happens if they are equal.
restore_game_settings() {
  local src="$SOM/prefix/drive_c/users/crossover/$GAME_SETTINGS_REL" user dst bak item changed=""
  if [ ! -d "$src" ]; then say "No game settings in SWTOR on Mac's prefix to copy back"; return 0; fi
  user=$(json_get "$MANIFEST" settings_user)
  user=${user:-$(bs_settings_user)}
  user=${user:-$(id -un)}
  case "$user" in */*|.|..|"") warn "Game settings not copied back (no Wine user in Broadsword's prefix)"; return 0 ;; esac
  [ -d "$BS_WINE/drive_c/users" ] ||
    { warn "Game settings not copied back: Broadsword's prefix has no drive_c/users"; return 0; }
  dst="$BS_WINE/drive_c/users/$user/$GAME_SETTINGS_REL"
  # anything to copy? (ContextError.ini aside)
  for item in "$src"/* "$src"/.[!.]*; do
    [ -e "$item" ] || continue
    [ "${item##*/}" = ContextError.ini ] && continue
    if ! diff -r -q "$item" "$dst/${item##*/}" >/dev/null 2>&1; then changed=1; break; fi
  done
  if [ -z "$changed" ]; then say "Game settings are the same in both prefixes"; return 0; fi
  say "Copying your game settings back to Broadsword's prefix (Wine user $user)"
  if [ -d "$dst" ]; then
    bak="$dst-backup-$(date +%Y%m%d-%H%M%S)"
    run cp -c -R -p "$dst" "$bak"
    say "Broadsword's previous game settings: ${bak#"$BS_WINE/"}"
  fi
  run mkdir -p "$dst"
  for item in "$src"/* "$src"/.[!.]*; do
    [ -e "$item" ] || continue
    [ "${item##*/}" = ContextError.ini ] && continue
    if [ -d "$item" ]; then
      run mkdir -p "$dst/${item##*/}"
      run cp -c -R -p "$item/." "$dst/${item##*/}/"
    else
      run cp -c -p "$item" "$dst/"
    fi
  done
}

# --- The launcher-update guard: a launchd job, started by launchd only when Broadsword's
# Wine/bin changes (WatchPaths; nothing runs in between), that puts the wrapper back if a
# launcher update replaced it (cmd_watch).
xml_escape() { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

install_agent() {
  local f env=""
  say "Setting up the launcher-update guard (a launchd job that only runs when Broadsword's Wine changes)"
  run rm -rf "$AGENT_DIR.new"
  run mkdir -p "$AGENT_DIR.new/helpers" "$AGENT_DIR.new/d9mt"
  # a copy of this script and what it needs, so app updates and moves do not break the job
  for f in som.sh wine-wrapper.sh dxvk.conf app.properties; do run cp -p "$RES/$f" "$AGENT_DIR.new/$f"; done
  for f in $HELPERS; do run cp -p "$RES/helpers/$f" "$AGENT_DIR.new/helpers/$f"; done
  run cp -p "$RES/d9mt/VERSION" "$AGENT_DIR.new/d9mt/VERSION"
  run rm -rf "$AGENT_DIR"
  run mv "$AGENT_DIR.new" "$AGENT_DIR"
  [ -z "$ROOT" ] || env="
	<key>EnvironmentVariables</key>
	<dict><key>SWTOR_ON_MAC_ROOT</key><string>$(xml_escape "$ROOT")</string></dict>"
  run mkdir -p "${AGENT_PLIST%/*}"
  put "$AGENT_PLIST" 644 <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- SWTOR on Mac: puts its Wine wrapper back after an official launcher update replaced it.
     launchd starts it only when Broadsword's Wine/bin changes; it does its check and exits.
     Removed by SWTOR on Mac's Uninstall. -->
<plist version="1.0">
<dict>
	<key>Label</key><string>$AGENT_LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>$(xml_escape "$AGENT_DIR/som.sh")</string>
		<string>watch</string>
	</array>
	<key>WatchPaths</key>
	<array>
		<string>$(xml_escape "$BS_WINE/bin")</string>
	</array>
	<key>RunAtLoad</key><false/>
	<key>ThrottleInterval</key><integer>30</integer>
	<key>ProcessType</key><string>Background</string>
	<key>LowPriorityIO</key><true/>
	<key>StandardOutPath</key><string>/dev/null</string>
	<key>StandardErrorPath</key><string>$(xml_escape "$LOGS/watch.log")</string>$env
</dict>
</plist>
EOF
  [ -n "$DRY" ] || plutil -lint -s "$AGENT_PLIST"
  if [ -n "$ROOT" ]; then
    say "Sandbox: the launchd job is written ($AGENT_PLIST) but not loaded"
    return 0
  fi
  run launchctl bootout "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null || true
  run launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST"
}

remove_agent() {
  if [ -z "$ROOT" ] && launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1; then
    run launchctl bootout "gui/$(id -u)/$AGENT_LABEL" || warn "Could not unload the launchd job $AGENT_LABEL"
  fi
  if [ -f "$AGENT_PLIST" ]; then run rm -f "$AGENT_PLIST"; say "Removed the launchd job $AGENT_PLIST"; fi
  if [ -d "$AGENT_DIR" ]; then run rm -rf "$AGENT_DIR"; fi
}

# Waits (bounded) until nothing in Broadsword's Wine/bin changed for $SETTLE seconds: a
# launcher update may still be writing. Fails if it keeps changing.
settle() {
  local newest age
  for _ in 1 2 3; do
    newest=$(find "$BS_WINE/bin" -maxdepth 1 -exec stat -f %m {} + 2>/dev/null | sort -n | tail -1)
    age=$(( $(date +%s) - ${newest:-0} ))
    [ "$age" -lt "$SETTLE" ] || return 0
    log "Wine/bin changed ${age}s ago; waiting"
    sleep $((SETTLE - age + 1))
  done
  return 1
}

on_watch_exit() {
  local st=$?
  if [ $st -ne 0 ] && [ -z "$DRY" ]; then
    [ -n "${WRAPPER_PHASE:-}" ] && rollback_wrapper
    log "watch failed (status $st)"
    notify "SWTOR's launcher updated its Wine and SWTOR on Mac could not hook itself back in. Open SWTOR on Mac and click Reinstall."
  fi
  if [ -n "${WATCH_LOCKED:-}" ]; then rmdir "$SOM/.lock" 2>/dev/null || true; fi
}

# The launchd job: Broadsword's Wine/bin changed. Idempotent: if the wrapper is still in
# place it only makes sure the helpers are; if a launcher update replaced the preloaders, it
# hooks the wrapper back in (as Install does) and says so. Leaves everything alone while an
# install or uninstall runs, if another wrapper is there, or if the folder looks half-updated
# (then it only notifies).
cmd_watch() {
  local b st states="" real="$BS_WINE/bin-real" h redo="" odd=""
  SETTLE="${SWTOR_ON_MAC_SETTLE:-20}"
  if [ -z "$DRY" ]; then mkdir -p "$LOGS"; LOGFILE="$LOGS/watch.log"; fi
  log "---- watch $VERSION: $BS_WINE/bin changed"
  [ -f "$MANIFEST" ] || { log "SWTOR on Mac is not installed; nothing to do"; return 0; }
  [ ! -d "$SOM/.lock" ] || { log "an install, uninstall or settings change is running; leaving it alone"; return 0; }
  settle || { log "Wine/bin keeps changing (a launcher update?); the next change starts this again"; return 0; }
  for b in $PRELOADERS; do
    st=$(wrapper_state_of "$b")
    states="$states $b=$st"
    case "$st" in
      ours) ;;
      stock|replaced) redo=1 ;;
      personal|foreign) log "state:$states; another Wine wrapper is installed: not ours to change"; return 0 ;;
      missing) odd=1 ;;
    esac
  done
  log "state:$states"
  if [ -n "$redo" ] && ! is_macho "$BS_WINE/bin/wine64"; then odd=1; fi
  if [ -n "$odd" ]; then
    notify "SWTOR's launcher is changing its Wine. If the game then starts without SWTOR on Mac, open SWTOR on Mac and click Reinstall."
    return 0
  fi
  if [ -z "$redo" ]; then
    # still hooked in; a launcher update may have removed the helpers next to the real preloaders
    for h in $HELPERS; do
      if [ ! -x "$real/$h" ]; then
        log "restoring the missing helper $h"
        run mkdir -p "$real"
        copy_atomic "$RES/helpers/$h" "$real/$h" 755
      fi
    done
    log "the wrapper is in place"
    return 0
  fi
  mkdir "$SOM/.lock" 2>/dev/null || { log "an install or uninstall just started; leaving it alone"; return 0; }
  WATCH_LOCKED=1 MOVED="" WRAPPER_PHASE="" WRAPPER_STATE=replaced
  trap on_watch_exit EXIT
  install_wrapper
  if [ -z "$DRY" ]; then
    for b in $PRELOADERS; do
      plutil -replace "original_preloaders_sha256.$b" -string "$(echo "$ORIG_SHAS" | tr ' ' '\n' | sed -n "s/^$b=//p")" "$MANIFEST"
    done
    plutil -replace rewrapped -string "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$MANIFEST"
  fi
  log "the wrapper is back in place"
  notify "SWTOR's launcher updated its Wine; SWTOR on Mac has hooked itself back in. Start the game as usual."
}

# The app's "End Leftover Wine Processes": ends them if that is all that runs
cmd_end_leftovers() {
  local l b
  if [ -z "$DRY" ]; then mkdir -p "$LOGS"; LOGFILE="$LOGS/install.log"; fi
  log "---- end-leftovers"
  l=$(proc_list)
  b=$(busy_of "$l")
  case "$b" in
    none) echo "@done No leftover Wine processes are running." ;;
    leftovers)
      end_leftovers
      echo "@done Ended the leftover Wine processes ($(proc_names "$l" engine))." ;;
    *) die "$(busy_message "$b" "$l")" ;;
  esac
}

# --- Upgrade from SWTOR on Mac 0.0.x (its engine: Sikarugir's CrossOver 24.0.7, with its
# libraries in $SOM/frameworks). An install over it puts this version's engine in place and
# updates the existing prefix for it (wineboot -u; the game settings, key bindings, the d9mt
# files and the Wine options in it stay), then rebuilds the Game Mode bundle, env and wrapper as
# every install does. What it replaces waits in $SOM/upgrade-backup until the install has gone
# through, and goes back if it fails: 0.0.x's engine (moved), its env, dxvk.conf, settings.conf,
# dev-defaults and Game Mode bundle (copies), and the prefix as it was, an APFS clone (no extra disk space)
# made only while the prefix is small: it holds Wine's own files, the game settings and d9mt's
# folder, not the game, which lives in Broadsword's folder (else the prefix stays as it is; 0.0.x
# can take a prefix back from Wine 11, tested). After success the old engine and its libraries
# go.
UPGRADE_PREFIX_MAX_KB=1048576
UPGRADE_FILES="env dxvk.conf settings.conf dev-defaults gamemode"
begin_upgrade() {
  local kb f
  UPGRADE=""
  [ -f "$MANIFEST" ] && [ -d "$ENG" ] && ! engine_current || return 0
  UPGRADE=1
  if [ "$(cat "$ENG/.som-source" 2>/dev/null)" = "$OLD_ENGINE_SHA256" ]; then OLD_LABEL="CrossOver 24.0.7"; else OLD_LABEL="an engine of another version"; fi
  say "Upgrading SWTOR on Mac $(json_get "$MANIFEST" version) ($OLD_LABEL) to $VERSION: the new Wine engine is $ENGINE_TITLE ($ENGINE_NAME); the prefix is updated for it"
  run rm -rf "$SOM/upgrade-backup"
  run mkdir -p "$SOM/upgrade-backup"
  for f in $UPGRADE_FILES; do
    if [ -e "$SOM/$f" ]; then run cp -c -R -P -p "$SOM/$f" "$SOM/upgrade-backup/$f"; fi
  done
  if [ -d "$SOM/prefix" ]; then
    kb=$(du -sk "$SOM/prefix" 2>/dev/null | cut -f1)
    if [ "${kb:-0}" -gt 0 ] && [ "$kb" -le "$UPGRADE_PREFIX_MAX_KB" ]; then
      say "Keeping the prefix as it is ($((kb / 1024)) MB, an APFS clone) until the upgrade has gone through"
      run cp -c -R -P -p "$SOM/prefix" "$SOM/upgrade-backup/prefix"
    else
      say "The prefix is large ($((${kb:-0} / 1024)) MB): no copy of it is kept"
    fi
  fi
}

# The upgrade went through: the old engine, its libraries and the copies go
finish_upgrade() {
  if [ -d "$SOM/upgrade-backup" ]; then
    run rm -rf "$SOM/upgrade-backup"
    [ -z "${UPGRADE:-}" ] || say "Removed the previous Wine engine (${OLD_LABEL:-CrossOver 24.0.7})"
  fi
  if [ -d "$SOM/frameworks" ]; then run rm -rf "$SOM/frameworks"; say "Removed the previous engine's libraries"; fi
}

# The upgrade failed: 0.0.x's install as it was (the new engine has gone already, CREATED)
rollback_upgrade() {
  local b="$SOM/upgrade-backup" f
  # (failed before the old engine moved: nothing of the install was changed yet)
  [ -d "$b/engine" ] || { rm -rf "$b"; return 0; }
  rm -rf "$SOM/engine" && mv "$b/engine" "$SOM/engine" && log "rolled back the engine"
  if [ -d "$b/prefix" ]; then rm -rf "$SOM/prefix" && mv "$b/prefix" "$SOM/prefix" && log "rolled back the prefix"; fi
  for f in $UPGRADE_FILES; do
    rm -rf "${SOM:?}/$f"
    if [ -e "$b/$f" ]; then mv "$b/$f" "$SOM/$f" && log "rolled back $f"; fi
  done
  rm -rf "$b"
}

on_install_exit() {
  local st=$?
  if [ $st -ne 0 ] && [ -z "$DRY" ]; then
    if [ -n "${FETCH_PID:-}" ]; then kill "$FETCH_PID" 2>/dev/null || true; fi
    stop_wine >/dev/null 2>&1 || true
    [ -n "${WRAPPER_PHASE:-}" ] && rollback_wrapper
    # all or nothing: what this run created goes again (a previous install stays)
    local c
    [ -n "${FIRST_INSTALL:-}" ] && CREATED="engine prefix gamemode dxvk.conf env settings.conf dev-defaults"
    for c in $CREATED; do
      if [ -e "$SOM/$c" ]; then rm -rf "${SOM:?}/$c"; log "removed $c (install failed)"; fi
    done
    [ -z "${UPGRADE:-}" ] || rollback_upgrade
    rm -rf "$SOM"/*.new "$SOM/gamemode"/.SWTOR.app.new.* 2>/dev/null || true
    log "install failed (status $st)"
  fi
  rmdir "$SOM/.lock" 2>/dev/null || true
}

lock() {
  [ -n "$DRY" ] && return
  mkdir -p "$SOM" "$LOGS"
  mkdir "$SOM/.lock" 2>/dev/null || die "Another SWTOR on Mac install or uninstall is running."
}

# A release's install over a development build's: what only development builds read goes,
# once the install has gone through (d9mt-ab.sh's switches, which a release's env never reads,
# and the caches of its cold= runs). Development builds keep both.
remove_dev_leftovers() {
  [ "$CHANNEL" = release ] || return 0
  if [ -e "$SOM/d9mt-ab.env" ]; then
    run rm -f "$SOM/d9mt-ab.env"
    say "Removed a development build's d9mt A/B switches (d9mt-ab.env)"
  fi
  if [ -e "$CACHE/d9mt-ab" ]; then
    run rm -rf "$CACHE/d9mt-ab"
    say "Removed a development build's d9mt test caches ($CACHE/d9mt-ab)"
  fi
}

cmd_install() {
  CREATED="" MOVED="" WRAPPER_PHASE="" NEW_PREFIX="" WRAPPER_STATE="" FIRST_INSTALL="" SETTINGS_USER="" UPGRADE=""
  [ -f "$MANIFEST" ] || FIRST_INSTALL=1
  if [ -z "$DRY" ]; then mkdir -p "$LOGS"; LOGFILE="$LOGS/install.log"; fi
  log "---- install $VERSION (d9mt $D9MT_VERSION, engine $ENGINE_ID $ENGINE_NAME) root=${ROOT:-/} dry=${DRY:-0} force=${FORCE:-0}"
  phase 1
  step "Checking your Mac"
  preflight
  check_wrapper install
  local avail
  avail=$(df -k "$H" | awk 'NR == 2 { print $4 }')
  [ "${avail:-0}" -gt 2000000 ] || die "Not enough free disk space (SWTOR on Mac needs about 2 GB)."
  lock
  trap on_install_exit EXIT
  trap 'exit 143' TERM INT HUP   # Cancel in the app: roll back through the EXIT trap
  [ -n "$DRY" ] || mkdir -p "$SOM"
  step "Wine engine"
  begin_upgrade
  install_engine
  phase 2
  step "Wine prefix and d9mt"
  install_prefix
  step "Settings"
  dev_defaults
  write_env
  write_dxvk_conf
  phase 4
  step "Game Mode"
  install_gamemode
  step "Hooking into the official launcher"
  install_wrapper
  write_manifest
  finish_upgrade
  # not part of the all-or-nothing install: without it, everything else still works
  install_agent || warn "The launcher-update guard (a launchd job) could not be set up; after a launcher update, open SWTOR on Mac and click Reinstall."
  [ -n "$DRY" ] || rm -rf "$CACHE/downloads"
  remove_dev_leftovers
  log "install complete"
  echo "@done SWTOR on Mac $VERSION is installed. Press Play SWTOR, or start SWTOR from the official app as usual."
}

cmd_uninstall() {
  MOVED="" WRAPPER_STATE=""
  if [ -z "$DRY" ]; then mkdir -p "$LOGS"; LOGFILE="$LOGS/install.log"; fi
  log "---- uninstall $VERSION root=${ROOT:-/} dry=${DRY:-0} force=${FORCE:-0}"
  phase 1
  step "Checking your Mac"
  local bin="$BS_WINE/bin" real="$BS_WINE/bin-real" b h want got left c
  check_not_running
  WRAPPER_STATE=$(wrapper_state)
  case "$WRAPPER_STATE" in
    personal|foreign)
      [ -n "$FORCE" ] || die "Broadsword's Wine folder has a Wine wrapper that is not SWTOR on Mac's ($WRAPPER_STATE). SWTOR on Mac leaves it alone unless you confirm."
      backup_foreign uninstall ;;
    replaced)
      [ -f "$MANIFEST" ] || [ -n "$FORCE" ] ||
        die "Broadsword's Wine folder has leftovers of a Wine wrapper that is not SWTOR on Mac's ($BS_WINE/bin-real). SWTOR on Mac leaves them alone unless you confirm." ;;
  esac
  lock
  # (the folder itself goes too once empty; a backup of another wrapper stays in it)
  trap 'rmdir "$SOM/.lock" "$SOM" 2>/dev/null || true' EXIT

  step "Restoring the official launcher's Wine"
  remove_agent
  if [ -d "$real" ]; then
    for b in $PRELOADERS; do
      [ -e "$real/$b" ] || continue
      if is_macho "$bin/$b"; then
        # a launcher update already put a (newer) real preloader back; the old copy goes
        run rm -f "$real/$b"
      else
        is_macho "$real/$b" || die "bin-real/$b is not a Wine preloader; leaving everything as it is."
        run mv -f "$real/$b" "$bin/$b"
      fi
    done
    for h in $HELPERS; do
      if [ -e "$real/$h" ]; then run rm -f "$real/$h"; fi
    done
    run rm -f "$real"/.*.new.* 2>/dev/null || true
    if [ -z "$DRY" ]; then
      left=$(ls -A "$real" 2>/dev/null || true)
      if [ -z "$left" ]; then rmdir "$real"; log "+ rmdir $real"
      else warn "Left alone in $real (not SWTOR on Mac's): $(echo "$left" | tr '\n' ' ')"; fi
    else
      echo "[dry-run] rmdir $real (if empty)"
    fi
  else
    say "Nothing to restore in Broadsword's Wine folder"
  fi

  phase 2
  step "Game settings"
  [ -n "$DRY" ] || stop_wine
  restore_game_settings

  phase 3
  step "Removing SWTOR on Mac's files"
  remove_gamemode_link
  for c in $APP_FILES engine.new frameworks.new prefix.new agent.new; do
    if [ -e "$SOM/$c" ]; then run rm -rf "${SOM:?}/$c"; fi
  done
  if [ -d "$CACHE" ]; then run rm -rf "$CACHE"; fi

  step "Checking"
  if [ -z "$DRY" ]; then
    for b in $PRELOADERS; do
      is_macho "$bin/$b" || die "$bin/$b is not Broadsword's preloader after uninstall."
      want=$([ -f "$MANIFEST" ] && json_get "$MANIFEST" "original_preloaders_sha256.$b" || true)
      got=$(sha256 "$bin/$b")
      if [ -n "$want" ] && [ "$want" != "$got" ]; then
        warn "$b differs from the one recorded at install (the official launcher may have updated it since)"
      else
        log "$b ok ($got)"
      fi
    done
    [ ! -d "$real" ] || warn "$real is still there (see above)"
  fi
  if [ -f "$MANIFEST" ]; then run rm -f "$MANIFEST"; fi
  log "uninstall complete"
  echo "@done SWTOR on Mac is removed. The official SWTOR app runs as it came from Broadsword. Logs stay in $LOGS."
}

case "${1:-}" in
  status) status ;;
  install) cmd_install ;;
  uninstall) cmd_uninstall ;;
  settings) settings ;;
  set) shift; cmd_set "$@" ;;
  watch) cmd_watch ;;
  end-leftovers) cmd_end_leftovers ;;
  *) sed -n '2,/^# Environment/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 2 ;;
esac
