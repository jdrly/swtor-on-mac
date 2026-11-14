# shellcheck shell=bash
# Fixture group nativefs (scripts/test-fixtures.sh only): Native fullscreen, the Settings switch
# for the Mac driver's NativeFullscreen option, without the official app, Wine or the engine.
# - som.sh set nativefs, as a dry run on a planted install with every other driver setting off:
#   on asks for the app's Mac driver and NativeFullscreen=y for swtor.exe, off for the engine's
#   own and n; and the same check fails on a copy of som.sh whose winemac_wanted doesn't know
#   the setting (the control). scripts/test-sandbox.sh's section 4b does it for real.
# - the wrapper's native_fullscreen and session_settings on stand-in environments: the game's
#   WINEDEBUG gets warn+nativefs with the setting on, with and without Debug Logging, and keeps
#   what it had with it off; the wine.log line and the settings field, on and off.
# - session-report.sh's Native fullscreen block on made-up logs: a clean session, an enter
#   without entered, a stuck exit, a fight, the wrapper's on without the driver's NATIVEFS: on,
#   and the setting off. Each bad log is flagged; the clean one and the off one are not.
# - the driver's decision itself (scripts/test-nativefs-decide.sh: the plain C cut out of
#   patches/winemac-native-fullscreen.patch, built with clang, and two broken stubs that fail).
# Sourced; check, piped and the counters come from lib.sh.
#
#   fx_nativefs <app> <wine-wrapper.sh> <folder> <test-nativefs-decide.sh>

# fx_nf_set <som.sh> <value>: som.sh set nativefs <value> as a dry run in the planted install;
# FX_RC its exit status, $FX_NF_D/set.txt what it printed
fx_nf_set() {
  FX_RC=0
  SWTOR_ON_MAC_ROOT="$FX_NF_D/root" SWTOR_ON_MAC_DRY_RUN=1 /bin/bash "$1" set nativefs "$2" >"$FX_NF_D/set.txt" 2>&1 || FX_RC=$?
}
# fx_nf_driver <app's|engine's own> <y|n>: the dry run asked for that Mac driver and that
# NativeFullscreen value for swtor.exe, and went through
fx_nf_driver() {
  [ "$FX_RC" = 0 ] && grep -qxF "[dry-run] engine's Mac driver: $([ "$1" = app ] && echo "the app's" || echo "the engine's own")" "$FX_NF_D/set.txt" &&
    grep -qF "[dry-run] NativeFullscreen=$2 under Software\\\\Wine\\\\AppDefaults\\\\swtor.exe\\\\Mac Driver in " "$FX_NF_D/set.txt" &&
    grep -q '^@done nativefs=' "$FX_NF_D/set.txt"
}
# fx_nf_wrap <SWTOR_NATIVE_FULLSCREEN> <WINEDEBUG before>: the wrapper's functions in an empty
# environment; prints "<WINEDEBUG after>|<nf_note>|<settings line>"
fx_nf_wrap() {
  env -i PATH=/usr/bin:/bin HOME="$HOME" SWTOR_NATIVE_FULLSCREEN="$1" WINEDEBUG="$2" \
    /bin/bash -c '. "$1"; native_fullscreen; printf "%s|%s|%s\n" "$WINEDEBUG" "$nf_note" "$(session_settings)"' - "$FX_NF_D/wrapper-fns.sh" 2>&1
}
# fx_nf_report <name>: session-report.sh on $FX_NF_D/<name>.log, into <name>.txt
fx_nf_report() { "$FX_NF_SR" "$FX_NF_D/$1.log" >"$FX_NF_D/$1.txt" 2>&1 || true; }
# fx_nf_in <name> <regex>: a line of that report matches (grep -E)
fx_nf_in() { grep -qE -- "$2" "$FX_NF_D/$1.txt"; }
# fx_nf_decide <test-nativefs-decide.sh> <folder>: the decision test, its output in <folder>/decide.txt
fx_nf_decide() { TMPDIR="$2" "$1" >"$2/decide.txt" 2>&1; }

fx_nativefs() {
  local app=$1 wrapper=$2 d=$3 decide=$4 som out dbg
  FX_NF_D=$d FX_NF_SR="$app/Contents/Resources/session-report.sh"
  mkdir -p "$d"

  # 1. som.sh set nativefs: an install planted far enough for a dry run of set (the manifest,
  # this version's engine id, the prefix's user.reg), game keys by position and raw mouse-look off
  som="$d/root/home/Library/Application Support/SWTOR on Mac"
  mkdir -p "$som/engine" "$som/prefix"
  echo '{}' >"$som/install-manifest.json"
  sed -n 's/^ENGINE_SHA256=//p' "$app/Contents/Resources/som.sh" >"$som/engine/.som-source"
  : >"$som/prefix/user.reg"
  printf 'physkeys=off\nrawmouse=off\nnativefs=off\n' >"$som/settings.conf"
  fx_nf_set "$app/Contents/Resources/som.sh" on
  check "nativefs: set on, every other driver setting off: the app's Mac driver and NativeFullscreen=y ($FX_RC)" fx_nf_driver app y
  fx_nf_set "$app/Contents/Resources/som.sh" off
  check "nativefs: set off: the engine's own Mac driver and NativeFullscreen=n ($FX_RC)" fx_nf_driver stock n
  printf 'physkeys=off\nrawmouse=on\nnativefs=on\n' >"$som/settings.conf"
  fx_nf_set "$app/Contents/Resources/som.sh" off
  check "nativefs: set off with raw mouse-look on: the app's Mac driver stays, NativeFullscreen=n ($FX_RC)" fx_nf_driver app n
  printf 'physkeys=off\nrawmouse=off\nnativefs=on\n' >"$som/settings.conf"
  fx_nf_set "$app/Contents/Resources/som.sh" maybe
  check "nativefs: a value other than on/off refused ($FX_RC)" eval '[ "$FX_RC" = 2 ] && grep -qx "@error Unknown setting: nativefs=maybe" "$d/set.txt"'
  # the control: winemac_wanted without the setting, as before it; the same check must fail
  printf 'physkeys=off\nrawmouse=off\nnativefs=off\n' >"$som/settings.conf"
  mkdir -p "$d/control"
  cp "$app/Contents/Resources/dxvk.conf" "$d/control/"
  sed 's/ || \[ "\$nf" = on \]//' "$app/Contents/Resources/som.sh" >"$d/control/som.sh"
  check "nativefs: the control's som.sh differs only in winemac_wanted's test" \
    eval '[ "$(diff "$app/Contents/Resources/som.sh" "$d/control/som.sh" | grep -c "^[<>]")" = 2 ]'
  fx_nf_set "$d/control/som.sh" on
  check "nativefs: control: a winemac_wanted that doesn't know the setting fails the check (the engine's own driver)" \
    eval '[ "$FX_RC" = 0 ] && ! fx_nf_driver app y && grep -qxF "[dry-run] engine'"'"'s Mac driver: the engine'"'"'s own" "$d/set.txt"'

  # 2. The wrapper: the game's WINEDEBUG, the wine.log line and the settings field
  sed -n '/^native_fullscreen() {/,/^}/p; /^session_settings() {/,/^}/p' "$wrapper" >"$d/wrapper-fns.sh"
  dbg=-all,warn+rawmouse,warn+threadcpu
  out=$(fx_nf_wrap 1 -all)
  check "nativefs: wrapper, on: WINEDEBUG -all,warn+nativefs, on, native-fullscreen=on ($out)" \
    eval '[ "${out%%|*}" = -all,warn+nativefs ] && printf "%s\n" "$out" | piped -E "\|on\|debug-logging=off hud=off game-mode=off native-fullscreen=on$"'
  out=$(fx_nf_wrap 1 "$dbg")
  check "nativefs: wrapper, on with Debug Logging: its channels and warn+nativefs ($out)" \
    eval '[ "${out%%|*}" = "$dbg,warn+nativefs" ] && printf "%s\n" "$out" | piped -E "\|on\|.* native-fullscreen=on$"'
  out=$(fx_nf_wrap 0 -all)
  check "nativefs: wrapper, off: WINEDEBUG kept, off, native-fullscreen=off ($out)" \
    eval '[ "${out%%|*}" = -all ] && printf "%s\n" "$out" | piped -E "\|off\|.* native-fullscreen=off$"'
  out=$(fx_nf_wrap 0 "$dbg")
  check "nativefs: wrapper, off with Debug Logging: its channels only ($out)" eval '[ "${out%%|*}" = "$dbg" ]'
  out=$(fx_nf_wrap "" "")
  check "nativefs: wrapper, an env without the setting (0.1.8's): off, no channel ($out)" eval '[ "$out" = "|off|debug-logging=off hud=off game-mode=off native-fullscreen=off" ]'
  check "nativefs: wrapper: the game only, after Debug Logging's channels" \
    eval '[ "$(grep -c "^ *native_fullscreen$" "$wrapper")" = 1 ] && grep -B2 "^ *native_fullscreen$" "$wrapper" | piped -F "export WINEDEBUG=\"\$SWTOR_GAME_WINEDEBUG\""'
  check "nativefs: wrapper: wine.log names the setting, on or off" grep -qF 'echo "SWTOR on Mac native fullscreen: $nf_note" >&2' "$wrapper"

  # 3. The session report
  local head='SWTOR on Mac 0.1.9-dev.1: engine cx26 cx-26.3.0-8, d9mt f5439a6, started 2026-11-14 20:00:00'
  local on='0124:warn:nativefs:macdrv_init NATIVEFS: on (variant=A separateSpaces=1 screens=1)'
  local enter='0124:warn:nativefs:reconcile NATIVEFS: enter screen=1 frame=1512x982pt scale=2 safeTop=0 request=(0,0)-(1512,982)'
  local entered='0124:warn:nativefs:did_enter NATIVEFS: entered content=1512x982pt (3024x1964px) in 612 ms'
  { echo "$head"; echo 'SWTOR on Mac native fullscreen: on'; echo "$on"; echo "$enter"; echo "$entered"
    echo '0124:warn:nativefs:reconcile NATIVEFS: exit reason=windowed'
    echo '0124:warn:nativefs:did_exit NATIVEFS: exited frame=(100,100)-(1380,820) in 704 ms'
    echo "$enter"; echo '0124:warn:nativefs:did_enter NATIVEFS: entered content=1512x982pt (3024x1964px) in 590 ms'
    echo '0124:warn:nativefs:did_exit NATIVEFS: exit reason=user'
    echo '0124:warn:nativefs:did_exit NATIVEFS: exited frame=(100,100)-(1380,820) in 500 ms'; } >"$d/clean.log"
  fx_nf_report clean
  check "nativefs: report, clean: on, confirmed by the driver" fx_nf_in clean '^  Native fullscreen +on, the driver confirmed it \(NATIVEFS: on\)$'
  check "nativefs: report, clean: entries, exits by reason, no failures, the longest transition" \
    eval 'fx_nf_in clean "^    entries +2 entered, 2 started$" && fx_nf_in clean "^    exits \(by reason\) +2 \(windowed 1, user 1\)$" && fx_nf_in clean "^    failures +none$" && fx_nf_in clean "^    longest transition +704 ms \(leaving\)$"'
  check "nativefs: report, clean: no warning" eval '! fx_nf_in clean "^    warning "'

  { echo "$head"; echo 'SWTOR on Mac native fullscreen: on'; echo "$on"; echo "$enter"; } >"$d/noentered.log"
  fx_nf_report noentered
  check "nativefs: report: an enter without entered is flagged" fx_nf_in noentered '^    warning +1 enter without entered or enter failed$'
  { echo "$head"; echo 'SWTOR on Mac native fullscreen: on'; echo "$on"; echo "$enter"; echo "$entered"
    echo '0124:warn:nativefs:reconcile NATIVEFS: exit reason=hidden'
    echo '0124:warn:nativefs:did_fail_exit NATIVEFS: exit failed, retry'
    echo '0124:warn:nativefs:did_fail_exit NATIVEFS: stuck'; } >"$d/stuck.log"
  fx_nf_report stuck
  check "nativefs: report: stuck is flagged, its failures counted" \
    eval 'fx_nf_in stuck "^    warning +stuck in the Space$" && fx_nf_in stuck "^    failures +exit failed 1, stuck 1$"'
  { echo "$head"; echo 'SWTOR on Mac native fullscreen: on'; echo "$on"; echo "$enter"; echo "$entered"
    echo '0124:warn:nativefs:reconcile NATIVEFS: resize told wine=(0,0)-(1512,950) (request=(0,0)-(1512,982))'
    echo '0124:warn:nativefs:reconcile NATIVEFS: fight'
    echo '0124:warn:nativefs:reconcile NATIVEFS: exit reason=fight'
    echo '0124:warn:nativefs:did_exit NATIVEFS: exited frame=(0,0)-(1512,982) in 650 ms'; } >"$d/fight.log"
  fx_nf_report fight
  check "nativefs: report: a fight is flagged, counted once" \
    eval 'fx_nf_in fight "^    warning +a fight over the window size$" && fx_nf_in fight "^    failures +fight 1$" && fx_nf_in fight "^    exits \(by reason\) +1 \(fight 1\)$"'
  { echo "$head"; echo 'SWTOR on Mac native fullscreen: on'; } >"$d/unconfirmed.log"
  fx_nf_report unconfirmed
  check "nativefs: report: the wrapper's on without the driver's NATIVEFS: on is flagged" \
    eval 'fx_nf_in unconfirmed "^  Native fullscreen +on, not confirmed by the driver \(no NATIVEFS: on line\)$" && fx_nf_in unconfirmed "^    warning +the wrapper turned it on, the driver never said NATIVEFS: on"'
  { echo "$head"; echo 'SWTOR on Mac native fullscreen: off'; } >"$d/off.log"
  fx_nf_report off
  check "nativefs: report, off: one row, no counts, no warning" \
    eval 'fx_nf_in off "^  Native fullscreen +off$" && ! fx_nf_in off "^    (entries|warning) "'
  echo "$head" >"$d/before.log"
  fx_nf_report before
  check "nativefs: report: a log without the wrapper's line (0.1.8 and older) has no Native fullscreen row" eval '! fx_nf_in before "Native fullscreen"'

  # 4. the Mac driver's decision, built from the patch (its two broken stubs must fail)
  check "nativefs: the driver's decision passes its test, and the stubs that never enter or ignore the player's exit fail" \
    fx_nf_decide "$decide" "$d"
}
