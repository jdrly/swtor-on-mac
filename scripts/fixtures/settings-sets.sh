# shellcheck shell=bash
# Fixture group settings-sets (scripts/test-fixtures.sh only): the settings kept per renderer in a
# development build (som.sh, SETTINGS_GLOBAL and SETTINGS_DX9_ONLY), on a planted install, without
# Wine or the official app.
# - the map: every key of SETTING_KEYS is global, DX9 only or per renderer, and the Settings
#   window greys out exactly the DX9-only ones
# - an earlier version's settings.conf (one set) seeds both: the DirectX 12 set starts as the
#   DirectX 9 one with its DX9-only settings off, and nothing of the DirectX 9 set changes
# - the switch: DirectX 12 on and off swaps the values shown, the prefix's (Retina, swtor.exe's
#   Mac driver options), env's and dxvk.conf's; each set keeps its own values; a DX9-only setting
#   can't change while DirectX 12's set is in effect
# - a reader of 0.1.9 (its setting(): key=value, the last line) still gets the DirectX 9 set
# - the set in effect named in env and wine.log, and in the session report
# Sourced; check, piped and the counters come from lib.sh.
#
#   fx_settings_sets <app> <folder>

# fx_ss_som <som.sh arguments>: the development build's som.sh on the planted install; FX_RC its
# exit status, $FX_SS_D/out.txt what it printed
fx_ss_som() {
  FX_RC=0
  SWTOR_ON_MAC_ROOT="$FX_SS_D/root" "$FX_SS_D/dev/som.sh" "$@" >"$FX_SS_D/out.txt" 2>&1 || FX_RC=$?
}
# fx_ss_get <key>: the value som.sh settings shows
fx_ss_get() { fx_ss_som settings; sed -n "s/^$1=//p" "$FX_SS_D/out.txt"; }
# fx_ss_conf <line>: settings.conf has that line
fx_ss_conf() { grep -qxF -- "$1" "$FX_SS_SOM/settings.conf"; }
# fx_ss_reg <key, as in user.reg> <value line>: the value is set there
fx_ss_reg() {
  K="[$1]" V="$2" awk 'BEGIN { k = ENVIRON["K"]; v = ENVIRON["V"] }
    index($0, "[") == 1 { inkey = (substr($0, 1, length(k)) == k && substr($0, length(k) + 1, 1) == " ") }
    inkey && $0 == v { found = 1 }
    END { exit !found }' "$FX_SS_SOM/prefix/user.reg"
}
# fx_ss_old <key>: the value a reader of 0.1.9 gets (its setting(): the last key= line, no default)
fx_ss_old() { sed -n "s/^$1=//p" "$FX_SS_SOM/settings.conf" | tail -1; }

fx_settings_sets() {
  local d=$2 res="$1/Contents/Resources" k bad=""
  FX_SS_D=$d
  FX_SS_SOM="$d/root/home/Library/Application Support/SWTOR on Mac"
  mkdir -p "$d/dev/d9mt"
  cp "$res/som.sh" "$res/dxvk.conf" "$res/wine-wrapper.sh" "$d/dev/"
  cp "$res/d9mt/VERSION" "$d/dev/d9mt/"
  chmod 755 "$d/dev/som.sh"
  printf 'version=0.0.0-fx.1\nchannel=dev\n' >"$d/dev/app.properties"
  # (D3DMetal as the DirectX 12 driver: it comes with the engine, no Mullion to install)
  # the planted install (manifest, this version's engine, the prefix's user.reg as Install
  # writes it), and an earlier version's settings.conf: one set, Jan's DirectX 9 choices
  mkdir -p "$FX_SS_SOM/engine" "$FX_SS_SOM/prefix"
  echo '{}' >"$FX_SS_SOM/install-manifest.json"
  sed -n 's/^ENGINE_SHA256=//p' "$d/dev/som.sh" >"$FX_SS_SOM/engine/.som-source"
  cat >"$FX_SS_SOM/prefix/user.reg" <<'REG'
WINE REGISTRY Version 2

[Software\\Wine\\AppDefaults\\swtor.exe\\Mac Driver] 1763000000
#time=1dc54a1b2c3d4e5
"NativeFullscreen"="y"
"PhysicalKeyboard"="y"
"RawMouseGameControllerScale"="1.5"
"RawMouseWhenCursorHidden"="y"

[Software\\Wine\\Mac Driver] 1763000000
#time=1dc54a1b2c3d4e5
"RetinaMode"="n"
REG
  printf '# SWTOR on Mac settings\nretina=off\nhud=on\ngamemode=on\nvsync=off\ndebug=on\nmemory=high\nupdates=on\nphyskeys=on\nrawmouse=on\nmousespeed=1.5\nhudpos=topleft\nfpslimit=30\nfpsbattery=on\nflushcap=on\nnativefs=on\ndx12=off\ndx12driver=gptk\ndx12fps=off\n' \
    >"$FX_SS_SOM/settings.conf"
  cp "$FX_SS_SOM/settings.conf" "$d/settings.old"

  # 1. the map
  local keys global dx9only
  keys=$(sed -n 's/^SETTING_KEYS="\(.*\)"$/\1/p' "$d/dev/som.sh")
  global=$(sed -n 's/^SETTINGS_GLOBAL="\(.*\)"$/\1/p' "$d/dev/som.sh")
  dx9only=$(sed -n 's/^SETTINGS_DX9_ONLY="\(.*\)"$/\1/p' "$d/dev/som.sh")
  for k in $global $dx9only; do case " $keys " in *" $k "*) ;; *) bad="$bad $k" ;; esac; done
  check "settings-sets: the map's global and DX9-only keys are settings (SETTING_KEYS)${bad:+ (not:$bad)}" test -z "$bad"
  check "settings-sets: the map: global debug updates dx12 dx12driver dx12fps, DX9 only the d9mt and DirectX 9 ones, retina hud hudpos per renderer" \
    eval '[ "$global" = "debug updates dx12 dx12driver dx12fps" ] && [ "$dx9only" = "gamemode vsync memory physkeys rawmouse mousespeed fpslimit fpsbattery flushcap nativefs" ]'
  # (the Settings window greys out each DX9-only setting, and only those)
  bad=""
  for k in $dx9only; do grep -qF "dx9Only(settings.dx9Only(\"$k\"))" "$FX_SS_REPO/src/native/Settings.swift" || bad="$bad $k"; done
  check "settings-sets: Settings greys out every DX9-only setting while DirectX 12's set is in effect${bad:+ (missing:$bad)}" test -z "$bad"
  check "settings-sets: ...and no other (one dx9Only per DX9-only key)" \
    eval '[ "$(grep -c "\.dx9Only(settings\.dx9Only(" "$FX_SS_REPO/src/native/Settings.swift")" = "$(echo $dx9only | wc -w | tr -d " ")" ]'

  # 2. the earlier version's file: the DirectX 9 set as it was, and the DirectX 12 set seeded
  fx_ss_som settings
  check "settings-sets: an earlier file, DirectX 12 off: the DirectX 9 set is its values, set in effect dx9" \
    eval 'piped -qx retina=off "$d/out.txt" && piped -qx physkeys=on "$d/out.txt" && piped -qx memory=high "$d/out.txt" && piped -qx fpslimit=30 "$d/out.txt" && piped -qx settings_set=dx9 "$d/out.txt"'
  fx_ss_som set dx12 on
  check "settings-sets: set dx12 on ($FX_RC)" eval '[ "$FX_RC" = 0 ] && fx_ss_conf dx12=on'
  fx_ss_som settings
  check "settings-sets: DirectX 12 on: the DirectX 12 set seeded from the DirectX 9 one (retina off, HUD on at top left)" \
    eval 'piped -qx retina=off "$d/out.txt" && piped -qx hud=on "$d/out.txt" && piped -qx hudpos=topleft "$d/out.txt" && piped -qx settings_set=dx12 "$d/out.txt"'
  check "settings-sets: ...its DX9-only settings off (memory auto, mouse speed 1), the global ones as they are" \
    eval 'for k in gamemode vsync physkeys rawmouse fpslimit fpsbattery flushcap nativefs; do piped -qx "$k=off" "$d/out.txt" || exit 1; done; piped -qx memory=auto "$d/out.txt" && piped -qx mousespeed=1 "$d/out.txt" && piped -qx debug=on "$d/out.txt" && piped -qx updates=on "$d/out.txt"'
  check "settings-sets: ...and the DX9-only list for Settings" piped -qx "dx9_only=$dx9only" "$d/out.txt"
  check "settings-sets: the file keeps the DirectX 9 set's lines as they were, the DirectX 12 set as dx12.* lines" \
    eval 'diff <(grep -v -e "^#" -e "^dx12\\." -e "^dx12=" "$d/settings.old") <(grep -v -e "^#" -e "^dx12\\." -e "^dx12=" "$FX_SS_SOM/settings.conf") >/dev/null && fx_ss_conf dx12.retina=off && fx_ss_conf dx12.hud=on && fx_ss_conf dx12.hudpos=topleft && [ "$(grep -c "^dx12\\." "$FX_SS_SOM/settings.conf")" = 3 ]'
  check "settings-sets: DirectX 12 on: the prefix gets the DirectX 12 set's values (swtor.exe's DX9-only ones off)" \
    eval 'fx_ss_reg "Software\\\\Wine\\\\AppDefaults\\\\swtor.exe\\\\Mac Driver" "\"PhysicalKeyboard\"=\"n\"" && fx_ss_reg "Software\\\\Wine\\\\AppDefaults\\\\swtor.exe\\\\Mac Driver" "\"RawMouseWhenCursorHidden\"=\"n\"" && fx_ss_reg "Software\\\\Wine\\\\AppDefaults\\\\swtor.exe\\\\Mac Driver" "\"NativeFullscreen\"=\"n\"" && fx_ss_reg "Software\\\\Wine\\\\AppDefaults\\\\swtor.exe\\\\Mac Driver" "\"RawMouseGameControllerScale\"=\"1\"" && fx_ss_reg "Software\\\\Wine\\\\Mac Driver" "\"RetinaMode\"=\"n\""'
  check "settings-sets: ...env names the DirectX 12 set, no d9mt frame cap, the default memory profile" \
    eval 'grep -qx SWTOR_SETTINGS_SET=dx12 "$FX_SS_SOM/env" && grep -qx SWTOR_FPS_LIMIT=0 "$FX_SS_SOM/env" && grep -qx D9MT_MEMORY_PROFILE=auto "$FX_SS_SOM/env" && grep -qx MTL_HUD_ALIGNMENT=topleft "$FX_SS_SOM/env"'

  # 3. the DirectX 12 set's own values, and a DX9-only setting refused while it is in effect
  fx_ss_som set retina on
  check "settings-sets: Retina on with DirectX 12: dx12.retina=on, the DirectX 9 set's retina=off kept, RetinaMode y ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && fx_ss_conf dx12.retina=on && fx_ss_conf retina=off && fx_ss_reg "Software\\\\Wine\\\\Mac Driver" "\"RetinaMode\"=\"y\""'
  cp "$FX_SS_SOM/settings.conf" "$d/settings.dx12"
  fx_ss_som set vsync on
  check "settings-sets: a DX9-only setting with DirectX 12's set in effect: refused, said why, settings.conf unchanged ($FX_RC)" \
    eval '[ "$FX_RC" = 1 ] && piped -q "^@error This setting doesn.t work with DirectX 12" "$d/out.txt" && cmp -s "$d/settings.dx12" "$FX_SS_SOM/settings.conf"'
  fx_ss_som set debug off
  check "settings-sets: a global setting with DirectX 12 on: one value for both sets ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && fx_ss_conf debug=off && ! grep -q "^dx12\\.debug=" "$FX_SS_SOM/settings.conf"'

  # 4. back to DirectX 9: its own values, everywhere
  fx_ss_som set dx12 off
  fx_ss_som settings
  check "settings-sets: DirectX 12 off: the DirectX 9 set shown again (retina off, keys by position, memory high, 30 fps)" \
    eval 'piped -qx retina=off "$d/out.txt" && piped -qx physkeys=on "$d/out.txt" && piped -qx memory=high "$d/out.txt" && piped -qx fpslimit=30 "$d/out.txt" && piped -qx mousespeed=1.5 "$d/out.txt" && piped -qx settings_set=dx9 "$d/out.txt" && piped -qx debug=off "$d/out.txt"'
  check "settings-sets: ...the prefix gets the DirectX 9 set's values back" \
    eval 'fx_ss_reg "Software\\\\Wine\\\\AppDefaults\\\\swtor.exe\\\\Mac Driver" "\"PhysicalKeyboard\"=\"y\"" && fx_ss_reg "Software\\\\Wine\\\\AppDefaults\\\\swtor.exe\\\\Mac Driver" "\"RawMouseWhenCursorHidden\"=\"y\"" && fx_ss_reg "Software\\\\Wine\\\\AppDefaults\\\\swtor.exe\\\\Mac Driver" "\"NativeFullscreen\"=\"y\"" && fx_ss_reg "Software\\\\Wine\\\\AppDefaults\\\\swtor.exe\\\\Mac Driver" "\"RawMouseGameControllerScale\"=\"1.5\"" && fx_ss_reg "Software\\\\Wine\\\\Mac Driver" "\"RetinaMode\"=\"n\""'
  check "settings-sets: ...env and dxvk.conf the DirectX 9 set's (d9mt's 30 fps, memory high, vsync off)" \
    eval 'grep -qx SWTOR_SETTINGS_SET=dx9 "$FX_SS_SOM/env" && grep -qx SWTOR_FPS_LIMIT=30 "$FX_SS_SOM/env" && grep -qx D9MT_MEMORY_PROFILE=high "$FX_SS_SOM/env" && grep -q "^# d3d9.presentInterval = 1" "$FX_SS_SOM/dxvk.conf"'
  fx_ss_som set dx12 on
  check "settings-sets: DirectX 12 on again: its own Retina on remembered" eval '[ "$(fx_ss_get retina)" = on ]'
  fx_ss_som set dx12 off

  # 5. a reader of 0.1.9 (key=value, its last line) gets the DirectX 9 set, every key
  bad=""
  for k in $keys; do
    [ "$(fx_ss_old "$k")" = "$(SWTOR_ON_MAC_ROOT="$d/root" "$d/dev/som.sh" settings | sed -n "s/^$k=//p")" ] || bad="$bad $k"
  done
  check "settings-sets: a reader of 0.1.9 gets the DirectX 9 set's value of every key from the new file${bad:+ (not:$bad)}" test -z "$bad"
  check "settings-sets: ...and no line of the DirectX 12 set it would take for its own (none starts with a key of it)" \
    eval '! grep -E "^($(echo $keys | tr " " "|"))=" "$FX_SS_SOM/settings.conf" | grep -q "^dx12\\."'

  # 6. the set in effect in wine.log and the session report
  check "settings-sets: the wrapper names the set in wine.log" \
    eval 'grep -qF "dx12) echo \"SWTOR on Mac settings set: DirectX 12'"'"'s\" >&2 ;;" "$d/dev/wine-wrapper.sh"'
  printf 'SWTOR on Mac 0.0.0-fx.1: engine cx26 cx-26.3.0-8, d9mt abc1234, started 2026-11-26 10:00:00\nSWTOR on Mac settings: debug-logging=off hud=off game-mode=off native-fullscreen=off\nSWTOR on Mac settings set: DirectX 12'"'"'s\n' >"$d/wine.log"
  "$res/session-report.sh" "$d/wine.log" >"$d/report.txt" 2>&1 || true
  check "settings-sets: the session report shows the set in effect" grep -qE "^  Settings set +DirectX 12's$" "$d/report.txt"
}
