#!/bin/bash
# SWTOR on Mac: the install, uninstall and status logic behind the app's window.
#
#   som.sh status      KEY=VALUE lines describing this Mac (what the window shows)
#   som.sh install     install or update; idempotent, safe to run again
#   som.sh uninstall   revert everything (the official install goes back to stock)
#
# Environment:
#   SWTOR_ON_MAC_ROOT=/abs/dir  sandbox for tests: the official install, the app's own files,
#                               logs, caches and the per-user temp dir all live under it
#                               ($ROOT/Applications, $ROOT/home/Library/..., $ROOT/usertmp/)
#   SWTOR_ON_MAC_DRY_RUN=1      print what would change and change nothing (no downloads,
#                               no Wine, no log file)
#   SWTOR_ON_MAC_FORCE=1        go ahead although Broadsword's Wine folder holds a Wine
#                               wrapper that is not SWTOR on Mac's (the app asks first)
#
# Lines for the app start with "@": "@step <text>", "@progress <label> <bytes> <total>",
# "@warn <text>", "@error <text>", "@done <text>". Everything else is plain log text.
# Runs under macOS's /bin/bash 3.2.
set -euo pipefail
RES="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(sed -n 's/^version=//p' "$RES/app.properties" 2>/dev/null || true)"
VERSION="${VERSION:-dev}"
D9MT_VERSION="$(cat "$RES/d9mt/VERSION" 2>/dev/null || echo unknown)"

# --- Components: downloaded at install time from their official sources (never bundled).
# Bump name, URL, size and sha256 together.
# Wine engine: Sikarugir's build of CrossOver 24.0.7 (Wine 9, x86_64).
ENGINE_NAME=WS12WineCX24.0.7_7
ENGINE_URL=https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineCX24.0.7_7.tar.xz
ENGINE_SIZE=172348356
ENGINE_SHA256=203f9e9fd6c2cc77e6525d798a434ced326145db34a356355e05659d3445fd1c
# two of its files, checked after unpacking (the known-good engine)
ENGINE_PRELOADER_SHA256=e2d7662ccb7e81ebb2d3f9ed8d76a73e75bb24caec41aa8016c168bfb8e48ec4
ENGINE_NTDLL_SHA256=81f81cf1bb70069e94fa89d53fb7327cfb52fb9629c5b84134c851e681a20235
# The libraries that engine is built against (FreeType, GnuTLS, SDL, GStreamer, ...): the
# Contents/Frameworks folder of Sikarugir's wrapper template, used via
# DYLD_FALLBACK_LIBRARY_PATH. Its renderer/ folder (D3DMetal, DXVK, DXMT) is not needed.
FW_NAME=Template-1.0.21
FW_URL=https://github.com/Sikarugir-App/Template/releases/download/v1.0/Template-1.0.21.tar.xz
FW_SIZE=95883080
FW_SHA256=bbe996e4e4375318485953d0c7818b7b4b0a4dc1f13303bcc584f99f7602f78d

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
else
  H="$HOME"
  APPS=/Applications
  USER_TMP="$(getconf DARWIN_USER_TEMP_DIR)"
fi
BS_APP="$APPS/Star Wars - The Old Republic.app"
BS_DATA="$H/Library/Application Support/com.broadsword.swtor/Star Wars - The Old Republic"
BS_WINE="$BS_DATA/swtor-precompiled/Libraries/Wine"   # Broadsword's Wine, also its WINEPREFIX
SOM="$H/Library/Application Support/SWTOR on Mac"
LOGS="$H/Library/Logs/SWTOR on Mac"
CACHE="$H/Library/Caches/SWTOR on Mac"
MANIFEST="$SOM/install-manifest.json"
PRELOADERS="wine-preloader wine64-preloader"
HELPERS="setsid-exec hold-launcher"
LOGFILE=/dev/null

# --- Output and logging
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOGFILE"; }
say() { echo "$*"; log "$*"; }
step() { echo "@step $*"; log "== $*"; }
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

# Processes that must not run during install/uninstall: the official launcher, anything
# from Broadsword's Wine or SWTOR on Mac's engine, and the game itself (any engine).
running_list() {
  ps -axww -o pid=,comm= 2>/dev/null | awk -v a="$BS_APP/" -v w="$BS_WINE/" -v e="$SOM/engine/" -v t="$(winetemp_tag)" '
    index($0, a) || index($0, w) || index($0, e) || (t != "" && index($0, t)) ||
    /\/Star Wars - The Old Republic Launcher$/ || /\/swtor\.exe$/ { print }' || true
}

# CrossOver's ntdll runs every Wine process of an engine from hard links in
# winetemp-<preloader inode>-<size>-...: the part of that name that is this engine's
winetemp_tag() {
  local pre="$SOM/engine/bin/wine-preloader"
  if [ -f "$pre" ]; then echo "/winetemp-$(stat -f '%i-%z' "$pre")-"; fi
}

rosetta_ok() { /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; }

status() {
  local s
  echo "version=$VERSION"
  echo "d9mt=$D9MT_VERSION"
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
  else
    echo "installed=no"
  fi
  if [ -n "$(running_list)" ]; then echo "running=yes"; else echo "running=no"; fi
  echo "app_dir=$SOM"
  echo "log_dir=$LOGS"
}

# --- Install steps

preflight() {
  [ "$(uname -m)" = arm64 ] || die "SWTOR on Mac needs a Mac with Apple Silicon."
  [ -d "$BS_APP" ] && [ -x "$BS_WINE/bin/wine64" ] ||
    die "The official SWTOR Mac app was not found. Install SWTOR from the official website (https://www.swtor.com) first, start it once so it sets up the game, then try again."
  rosetta_ok || die "Rosetta is not installed. Start the official SWTOR app once (macOS offers to install Rosetta), then try again."
  local r
  r=$(running_list)
  [ -z "$r" ] || die "Quit the SWTOR launcher and the game first. Still running: $(echo "$r" | awk '{ $1 = ""; print }' | sed 's|.*/||' | sort -u | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
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

# The winetemp name CrossOver's ntdll re-execs swtor.exe from, for the engine's preloader
winetemp_link() {
  local pre=$1 m
  m=$(stat -f '%Fm' "$pre")
  echo "${USER_TMP}winetemp-$(stat -f '%i-%z' "$pre")-${m%.*}-$((10#${m#*.}))/swtor.exe"
}
remove_gamemode_link() {
  local pre="$SOM/engine/bin/wine-preloader" l
  [ -f "$pre" ] || return 0
  l=$(winetemp_link "$pre")
  if [ -L "$l" ]; then run rm -f "$l"; say "Removed the Game Mode link $l"; fi
}

install_engine() {
  local dst="$SOM/engine" w
  if [ "$(cat "$dst/.som-source" 2>/dev/null || true)" = "$ENGINE_SHA256" ] && [ -x "$dst/bin/wine" ]; then
    say "Wine engine $ENGINE_NAME is already in place"
  else
    fetch "$ENGINE_URL" "$ENGINE_SHA256" "$ENGINE_SIZE" "Wine engine"
    say "Unpacking the Wine engine"
    run rm -rf "$dst.new"
    run mkdir -p "$dst.new"
    run tar -xJf "$FETCHED" -C "$dst.new" --strip-components 1 wswine.bundle
    if [ -z "$DRY" ]; then
      [ "$(sha256 "$dst.new/bin/wine-preloader")" = "$ENGINE_PRELOADER_SHA256" ] &&
        [ "$(sha256 "$dst.new/lib/wine/x86_64-unix/ntdll.so")" = "$ENGINE_NTDLL_SHA256" ] ||
        die "The unpacked Wine engine does not match the expected build."
      echo "$ENGINE_SHA256" >"$dst.new/.som-source"
    fi
    remove_gamemode_link   # it names the old engine's preloader
    run rm -rf "$dst"
    run mv "$dst.new" "$dst"
    CREATED="$CREATED engine"
  fi
  # d9mt's winemetal bridge replaces the engine's builtin winemetal (this copy only)
  w="$dst/lib/wine"
  say "Installing the d9mt bridge (winemetal) into the engine"
  copy_atomic "$RES/d9mt/winemetal.so" "$w/x86_64-unix/winemetal.so" 755
  copy_atomic "$RES/d9mt/winemetal.dll" "$w/x86_64-windows/winemetal.dll" 644
}

install_frameworks() {
  local dst="$SOM/frameworks"
  if [ "$(cat "$dst/.som-source" 2>/dev/null || true)" = "$FW_SHA256" ]; then
    say "Engine libraries ($FW_NAME) are already in place"
    return
  fi
  fetch "$FW_URL" "$FW_SHA256" "$FW_SIZE" "Engine libraries"
  say "Unpacking the engine libraries"
  run rm -rf "$dst.new"
  run mkdir -p "$dst.new"
  run tar -xJf "$FETCHED" -C "$dst.new" --strip-components 3 \
    --exclude "$FW_NAME.app/Contents/Frameworks/renderer" "$FW_NAME.app/Contents/Frameworks"
  if [ -z "$DRY" ]; then
    [ -f "$dst.new/libfreetype.6.dylib" ] || die "The engine libraries are incomplete."
    echo "$FW_SHA256" >"$dst.new/.som-source"
  fi
  run rm -rf "$dst"
  run mv "$dst.new" "$dst"
  CREATED="$CREATED frameworks"
}

# wine <args...> with SWTOR on Mac's engine and prefix (output goes to the log)
wine_do() {
  if [ -n "$DRY" ]; then echo "[dry-run] wine $*"; return; fi
  log "+ wine $*"
  env -u WINELOADER -u WINESERVER -u WINEDLLOVERRIDES -u SWTOR_WRAPPED \
    WINEPREFIX="$SOM/prefix" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" \
    DYLD_FALLBACK_LIBRARY_PATH="$SOM/frameworks:/usr/lib" \
    "$SOM/engine/bin/wine" "$@" </dev/null >>"$LOGFILE" 2>&1
}

# End this prefix's Wine session and make sure nothing of it stays running: a leftover
# wineserver started from here would break the next game start from the launcher.
stop_wine() {
  [ -n "$DRY" ] && { echo "[dry-run] wineserver -k"; return; }
  [ -x "$SOM/engine/bin/wineserver" ] || return 0
  # (wineserver needs the engine libraries too: libinotify)
  local fb="$SOM/frameworks:/usr/lib"
  WINEPREFIX="$SOM/prefix" DYLD_FALLBACK_LIBRARY_PATH="$fb" "$SOM/engine/bin/wineserver" -k >>"$LOGFILE" 2>&1 || true
  WINEPREFIX="$SOM/prefix" DYLD_FALLBACK_LIBRARY_PATH="$fb" "$SOM/engine/bin/wineserver" -w >>"$LOGFILE" 2>&1 || true
  local left
  for _ in 1 2 3 4 5; do
    left=$(ps -axww -o pid=,comm= | awk -v e="$SOM/engine/" -v t="$(winetemp_tag)" \
      'index($0, e) || (t != "" && index($0, t)) { print $1 }')
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
  say "Setting Wine options: Retina mode, mouse-look fix, d9mt for swtor.exe"
  wine_do reg add 'HKCU\Software\Wine\Mac Driver' /v RetinaMode /t REG_SZ /d y /f &&
    wine_do reg add 'HKCU\Software\Wine\AppDefaults\swtor.exe\X11 Driver' /v GrabPointer /t REG_SZ /d n /f &&
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
        run mkdir -p "$p/drive_c/users/crossover/AppData/Local"
        run cp -c -R -p "$u/AppData/Local/SWTOR" "$p/drive_c/users/crossover/AppData/Local/"
        break
      fi
    done
  fi

  sys="$p/drive_c/windows/system32"
  say "Installing d9mt ($D9MT_VERSION) as the game's Direct3D 9"
  if [ -z "$DRY" ] && [ ! -e "$sys/d3d9.dll.wine" ]; then
    [ -f "$sys/d3d9.dll" ] || die "Wine's d3d9.dll is missing in the prefix."
    if dd if="$sys/d3d9.dll" bs=1 skip=64 count=16 2>/dev/null | grep -q 'Wine builtin'; then
      run mv "$sys/d3d9.dll" "$sys/d3d9.dll.wine"
    else
      warn "system32/d3d9.dll is not Wine's own; replacing it without keeping a copy"
    fi
  fi
  copy_atomic "$RES/d9mt/d3d9.dll" "$sys/d3d9.dll" 644
  copy_atomic "$RES/dxvk.conf" "$SOM/dxvk.conf" 644
}

install_gamemode() {
  local app="$SOM/gamemode/SWTOR.app" new pre="$SOM/engine/bin/wine-preloader"
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
	<key>LSUIElement</key><true/>
</dict>
</plist>
EOF
  # An APFS clone of the preloader, not a re-signed copy: the same bytes keep the same code
  # identity and Rosetta cache. (Its signature does not cover this Info.plist; exec does not
  # check that.) Must stay byte-identical to the engine's preloader: the wrapper checks.
  run cp -c "$pre" "$new/Contents/MacOS/swtor.exe"
  run rm -rf "$app"
  run mv "$new" "$app"
}

write_env() {
  say "Writing the settings file $SOM/env"
  put "$SOM/env" 644 <<EOF
# SWTOR on Mac $VERSION: settings the Wine wrapper in Broadsword's Wine folder reads at every
# Wine start. Written by the installer; reinstalling overwrites this file.

# Faster Wine thread sync, no Wine debug output
WINEMSYNC=1
WINEDEBUG=-all

# SWTOR on Mac's Wine engine (CrossOver 24.0.7), prefix and engine libraries
SWTOR_ENGINE="$SOM/engine"
SWTOR_PREFIX="$SOM/prefix"
SWTOR_FRAMEWORKS="$SOM/frameworks"
# macOS Game Mode: the game runs from a bundle copy of the engine's preloader
SWTOR_GAMEMODE_APP="$SOM/gamemode/SWTOR.app"
SWTOR_LOG_DIR="$LOGS"

# d9mt: Direct3D 9 straight to Metal (d3d9.dll in the prefix, winemetal bridge in the engine)
WINEDLLOVERRIDES="d3d9=n,b"
DXVK_CONFIG_FILE="$SOM/dxvk.conf"
# d9mt's own warnings and errors only (cheap), kept in $LOGS/wine.log
DXVK_LOG_LEVEL=warn
SWTOR_LOG_FILTER=.

# Apple's Metal HUD (FPS, frame times): remove the # to turn it on
#MTL_HUD_ENABLED=1
EOF
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
  local b sha pre="" first=1
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
  "engine": "$ENGINE_NAME",
  "engine_sha256": "$ENGINE_SHA256",
  "frameworks": "$FW_NAME",
  "frameworks_sha256": "$FW_SHA256",
  "broadsword_wine": "$BS_WINE",
  "previous_wrapper": "$WRAPPER_STATE",
  "bin_real_created": $([ "$BIN_REAL_EXISTED" = false ] && echo true || echo false),
  "original_preloaders_sha256": {$pre
  },
  "helpers": ["setsid-exec", "hold-launcher"],
  "app_files": ["engine", "frameworks", "prefix", "gamemode", "dxvk.conf", "env"]
}
EOF
}

on_install_exit() {
  local st=$?
  if [ $st -ne 0 ] && [ -z "$DRY" ]; then
    if [ -n "${FETCH_PID:-}" ]; then kill "$FETCH_PID" 2>/dev/null || true; fi
    stop_wine >/dev/null 2>&1 || true
    [ -n "${WRAPPER_PHASE:-}" ] && rollback_wrapper
    # all or nothing: what this run created goes again (a previous install stays)
    local c
    [ -n "${FIRST_INSTALL:-}" ] && CREATED="engine frameworks prefix gamemode dxvk.conf env"
    for c in $CREATED; do
      if [ -e "$SOM/$c" ]; then rm -rf "${SOM:?}/$c"; log "removed $c (install failed)"; fi
    done
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

cmd_install() {
  CREATED="" MOVED="" WRAPPER_PHASE="" NEW_PREFIX="" WRAPPER_STATE="" FIRST_INSTALL=""
  [ -f "$MANIFEST" ] || FIRST_INSTALL=1
  if [ -z "$DRY" ]; then mkdir -p "$LOGS"; LOGFILE="$LOGS/install.log"; fi
  log "---- install $VERSION (d9mt $D9MT_VERSION) root=${ROOT:-/} dry=${DRY:-0} force=${FORCE:-0}"
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
  install_engine
  step "Engine libraries"
  install_frameworks
  step "Wine prefix and d9mt"
  install_prefix
  step "Game Mode"
  install_gamemode
  step "Settings"
  write_env
  step "Hooking into the official launcher"
  install_wrapper
  write_manifest
  [ -n "$DRY" ] || rm -rf "$CACHE/downloads"
  log "install complete"
  echo "@done SWTOR on Mac $VERSION is installed. Start SWTOR from the official app as usual."
}

cmd_uninstall() {
  MOVED="" WRAPPER_STATE=""
  if [ -z "$DRY" ]; then mkdir -p "$LOGS"; LOGFILE="$LOGS/install.log"; fi
  log "---- uninstall $VERSION root=${ROOT:-/} dry=${DRY:-0} force=${FORCE:-0}"
  step "Checking your Mac"
  local r bin="$BS_WINE/bin" real="$BS_WINE/bin-real" b h want got left c
  r=$(running_list)
  [ -z "$r" ] || die "Quit the SWTOR launcher and the game first."
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

  step "Removing SWTOR on Mac's files"
  remove_gamemode_link
  [ -n "$DRY" ] || stop_wine
  for c in engine frameworks prefix gamemode dxvk.conf env engine.new frameworks.new prefix.new; do
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
  *) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
