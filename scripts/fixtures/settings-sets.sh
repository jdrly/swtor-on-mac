# shellcheck shell=bash
# Fixture group settings-sets (scripts/test-fixtures.sh only): the settings kept per renderer in a
# development build (som.sh, SETTINGS_GLOBAL and SETTINGS_DX9_ONLY), on a planted install, without
# Wine or the official app.
# - an earlier version's settings.conf (one set) seeds both: the DirectX 12 set starts as the
#   DirectX 9 one with its DX9-only settings off, and nothing of the DirectX 9 set changes
# - the switch: DirectX 12 on and off swaps the values shown; each set keeps its own values,
#   swtor_RC2.exe's and env's DirectX 12 lines the DirectX 12 set's; a global setting (Retina) has
#   one value; a DX9-only setting can't change while DirectX 12's set is in effect
# - a change that fails half way puts the files back, env made for the drivers there are; a
#   failed copy leaves no lock; an earlier version's install can't change DirectX 12's set
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

# (dx9only and bad are read in the checks' eval strings)
# shellcheck disable=SC2034
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
  echo '{"version": "0.0.0-fx.1", "settings_sets": "yes"}' >"$FX_SS_SOM/install-manifest.json"
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

  local keys dx9only
  keys=$(sed -n 's/^SETTING_KEYS="\(.*\)"$/\1/p' "$d/dev/som.sh")

  # 1. the earlier version's file: the DirectX 9 set as it was, and the DirectX 12 set seeded
  fx_ss_som settings
  dx9only=$(sed -n 's/^dx9_only=//p' "$d/out.txt")
  check "settings-sets: an earlier file, DirectX 12 off: the DirectX 9 set is its values, the set chosen dx9" \
    eval 'piped -qx retina=off "$d/out.txt" && piped -qx physkeys=on "$d/out.txt" && piped -qx memory=high "$d/out.txt" && piped -qx fpslimit=30 "$d/out.txt" && piped -qx settings_set=dx9 "$d/out.txt"'
  fx_ss_som set dx12 on
  check "settings-sets: set dx12 on ($FX_RC)" eval '[ "$FX_RC" = 0 ] && fx_ss_conf dx12=on'
  fx_ss_som settings
  check "settings-sets: DirectX 12 on: the DirectX 12 set seeded from the DirectX 9 one (retina off, HUD on at top left)" \
    eval 'piped -qx retina=off "$d/out.txt" && piped -qx hud=on "$d/out.txt" && piped -qx hudpos=topleft "$d/out.txt" && piped -qx settings_set=dx12 "$d/out.txt"'
  check "settings-sets: ...the DX9-only ones off (memory auto, mouse speed 1), the global ones as they are" \
    eval '( for k in $dx9only; do case $k in memory) piped -qx memory=auto "$d/out.txt" ;; mousespeed) piped -qx mousespeed=1 "$d/out.txt" ;; *) piped -qx "$k=off" "$d/out.txt" ;; esac || exit 1; done ) && [ -n "$dx9only" ] && piped -qx debug=on "$d/out.txt" && piped -qx updates=on "$d/out.txt"'
  check "settings-sets: the file keeps the DirectX 9 set's lines as they were, the DirectX 12 set as dx12.* lines" \
    eval 'diff <(grep -v -e "^#" -e "^dx12\\." -e "^dx12=" "$d/settings.old") <(grep -v -e "^#" -e "^dx12\\." -e "^dx12=" "$FX_SS_SOM/settings.conf") >/dev/null && fx_ss_conf dx12.hud=on && fx_ss_conf dx12.hudpos=topleft && [ "$(grep -c "^dx12\\." "$FX_SS_SOM/settings.conf")" = 2 ]'
  # (the files hold both sets: swtor.exe's values and env's game settings the DirectX 9 set's,
  # which a fallback to swtor.exe runs with; swtor_RC2.exe's the DirectX 12 set's)
  check "settings-sets: DirectX 12 on: swtor_RC2.exe gets the DirectX 12 set (its DX9-only ones off), swtor.exe keeps the DirectX 9 set" \
    eval 'fx_ss_reg "Software\\\\Wine\\\\AppDefaults\\\\swtor_RC2.exe\\\\Mac Driver" "\"PhysicalKeyboard\"=\"n\"" && fx_ss_reg "Software\\\\Wine\\\\AppDefaults\\\\swtor_RC2.exe\\\\Mac Driver" "\"RawMouseWhenCursorHidden\"=\"n\"" && fx_ss_reg "Software\\\\Wine\\\\AppDefaults\\\\swtor.exe\\\\Mac Driver" "\"PhysicalKeyboard\"=\"y\"" && fx_ss_reg "Software\\\\Wine\\\\AppDefaults\\\\swtor.exe\\\\Mac Driver" "\"RawMouseGameControllerScale\"=\"1.5\"" && fx_ss_reg "Software\\\\Wine\\\\Mac Driver" "\"RetinaMode\"=\"n\""'
  check "settings-sets: ...env: the set chosen dx12, the DirectX 12 set's HUD for swtor_RC2.exe, the DirectX 9 set's game settings kept" \
    eval 'grep -qx SWTOR_SETTINGS_SET=dx12 "$FX_SS_SOM/env" && grep -qx SWTOR_DX12_HUD=1 "$FX_SS_SOM/env" && grep -qx SWTOR_DX12_HUD_POS=topleft "$FX_SS_SOM/env" && grep -qx SWTOR_FPS_LIMIT=30 "$FX_SS_SOM/env" && grep -qx D9MT_MEMORY_PROFILE=high "$FX_SS_SOM/env"'

  # 2. the DirectX 12 set's own values, a global one shared, and a DX9-only setting refused
  # while DirectX 12's set is chosen
  fx_ss_som set hud off
  check "settings-sets: HUD off with DirectX 12: dx12.hud=off, the DirectX 9 set's on kept, env's DirectX 12 HUD off ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && fx_ss_conf dx12.hud=off && fx_ss_conf hud=on && grep -qx SWTOR_DX12_HUD=0 "$FX_SS_SOM/env" && grep -qx MTL_HUD_ENABLED=1 "$FX_SS_SOM/env"'
  fx_ss_som set retina on
  check "settings-sets: Retina on with DirectX 12: one value (Wine reads it for the whole prefix), every program's RetinaMode y, none of swtor_RC2.exe's own ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && fx_ss_conf retina=on && ! grep -q "^dx12\\.retina=" "$FX_SS_SOM/settings.conf" && fx_ss_reg "Software\\\\Wine\\\\Mac Driver" "\"RetinaMode\"=\"y\"" && ! grep -q "RetinaMode" <(sed -n "/swtor_RC2/,/^\$/p" "$FX_SS_SOM/prefix/user.reg")'
  cp "$FX_SS_SOM/settings.conf" "$d/settings.dx12"
  fx_ss_som set vsync on
  check "settings-sets: a DX9-only setting while DirectX 12's set is chosen: refused, said why, settings.conf unchanged ($FX_RC)" \
    eval '[ "$FX_RC" = 1 ] && piped -q "^@error This setting doesn.t work with DirectX 12" "$d/out.txt" && cmp -s "$d/settings.dx12" "$FX_SS_SOM/settings.conf"'
  fx_ss_som set debug off
  check "settings-sets: a global setting with DirectX 12 on: one value for both sets ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && fx_ss_conf debug=off && ! grep -q "^dx12\\.debug=" "$FX_SS_SOM/settings.conf"'

  # 3. back to DirectX 9: its own values shown, swtor_RC2.exe's gone
  fx_ss_som set dx12 off
  fx_ss_som settings
  check "settings-sets: DirectX 12 off: the DirectX 9 set shown again (HUD on, Retina on, keys by position, memory high, 30 fps)" \
    eval 'piped -qx hud=on "$d/out.txt" && piped -qx retina=on "$d/out.txt" && piped -qx physkeys=on "$d/out.txt" && piped -qx memory=high "$d/out.txt" && piped -qx fpslimit=30 "$d/out.txt" && piped -qx mousespeed=1.5 "$d/out.txt" && piped -qx settings_set=dx9 "$d/out.txt" && piped -qx debug=off "$d/out.txt"'
  check "settings-sets: ...swtor_RC2.exe's values gone, the DirectX 9 set's in place, env names dx9" \
    eval '! grep -qi swtor_RC2 "$FX_SS_SOM/prefix/user.reg" && fx_ss_reg "Software\\\\Wine\\\\AppDefaults\\\\swtor.exe\\\\Mac Driver" "\"PhysicalKeyboard\"=\"y\"" && fx_ss_reg "Software\\\\Wine\\\\Mac Driver" "\"RetinaMode\"=\"y\"" && grep -qx SWTOR_SETTINGS_SET=dx9 "$FX_SS_SOM/env" && ! grep -q "^SWTOR_DX12_HUD=" "$FX_SS_SOM/env"'
  fx_ss_som set dx12 on
  check "settings-sets: DirectX 12 on again: its own HUD off remembered" eval '[ "$(fx_ss_get hud)" = off ]'

  # 4. a switch that fails half way (the prefix can't be written): settings.conf, env and the
  # registry as they were, so the window and the next game start agree
  cp "$FX_SS_SOM/settings.conf" "$d/settings.before"; cp "$FX_SS_SOM/env" "$d/env.before"; cp "$FX_SS_SOM/prefix/user.reg" "$d/user.reg.before"
  chmod a-w "$FX_SS_SOM/prefix"
  fx_ss_som set dx12 off
  chmod u+w "$FX_SS_SOM/prefix"
  check "settings-sets: a switch that fails: an error, settings.conf, env and user.reg as they were, no copy left ($FX_RC)" \
    eval '[ "$FX_RC" != 0 ] && cmp -s "$d/settings.before" "$FX_SS_SOM/settings.conf" && cmp -s "$d/env.before" "$FX_SS_SOM/env" && cmp -s "$d/user.reg.before" "$FX_SS_SOM/prefix/user.reg" && [ ! -e "$FX_SS_SOM/set-before.new" ] && [ ! -e "$FX_SS_SOM/.lock" ]'
  fx_ss_som set dx12 off
  # (a copy that can't be made: refused, and no lock left for the next check to find)
  chmod 000 "$FX_SS_SOM/dxvk.conf"
  fx_ss_som set debug on
  chmod 644 "$FX_SS_SOM/dxvk.conf"
  check "settings-sets: a copy that fails: an error, no lock or copy left ($FX_RC)" \
    eval '[ "$FX_RC" != 0 ] && [ ! -e "$FX_SS_SOM/.lock" ] && [ ! -e "$FX_SS_SOM/set-before.new" ] && fx_ss_conf debug=off'
  fx_ss_som rehook
  check "settings-sets: ...the next hook check isn't told busy" eval '! piped -q "^@notice busy" "$d/out.txt"'

  # 5. a reader of 0.1.9 (key=value, its last line) gets the DirectX 9 set, every key
  bad=""
  for k in $keys; do
    [ "$(fx_ss_old "$k")" = "$(SWTOR_ON_MAC_ROOT="$d/root" "$d/dev/som.sh" settings | sed -n "s/^$k=//p")" ] || bad="$bad $k"
  done
  check "settings-sets: a reader of 0.1.9 gets the DirectX 9 set's value of every key from the new file${bad:+ (not:$bad)}" test -z "$bad"

  # 6. a switch off Mullion that fails after Mullion went: settings.conf (DirectX 12 on, on
  # Mullion) and user.reg as they were, and env doesn't start the game on the missing Mullion
  sed -i.bak 's/^dx12driver=gptk$/dx12driver=mullion/' "$FX_SS_SOM/settings.conf" && rm -f "$FX_SS_SOM/settings.conf.bak"
  mkdir -p "$FX_SS_SOM/engine/lib/wine/dxgi/dxmt"
  printf '%s\nfx\n' "$(sed -n 's/^MULLION_SHA256=//p' "$d/dev/som.sh" | tr -d '"')" >"$FX_SS_SOM/engine/lib/wine/dxgi/dxmt/.mullion"
  fx_ss_som set dx12 on
  check "settings-sets: (planted: DirectX 12 on Mullion, env starts it) ($FX_RC)" eval '[ "$FX_RC" = 0 ] && grep -qx SWTOR_DX12_DRIVER=mullion "$FX_SS_SOM/env"'
  cp "$FX_SS_SOM/settings.conf" "$d/settings.before"; cp "$FX_SS_SOM/prefix/user.reg" "$d/user.reg.before"
  chmod a-w "$FX_SS_SOM/prefix"
  fx_ss_som set dx12 off
  chmod u+w "$FX_SS_SOM/prefix"
  check "settings-sets: a switch off Mullion that fails: settings.conf and user.reg as they were, Mullion gone, env doesn't start it ($FX_RC)" \
    eval '[ "$FX_RC" != 0 ] && cmp -s "$d/settings.before" "$FX_SS_SOM/settings.conf" && cmp -s "$d/user.reg.before" "$FX_SS_SOM/prefix/user.reg" && [ ! -e "$FX_SS_SOM/engine/lib/wine/dxgi/dxmt/.mullion" ] && ! grep -q "^SWTOR_DX12" "$FX_SS_SOM/env" && grep -q "not ready: the game starts as swtor.exe" "$FX_SS_SOM/env"'

  # 7. an install of an earlier version with DirectX 12 on (one set; swtor_RC2.exe given
  # swtor.exe's values): the hook check makes the two sets in settings.conf and changes nothing
  # else; Update writes the rest, and DirectX 12's set can't change before it
  cp "$d/settings.old" "$FX_SS_SOM/settings.conf"
  sed -i.bak 's/^dx12=off$/dx12=on/' "$FX_SS_SOM/settings.conf" && rm -f "$FX_SS_SOM/settings.conf.bak"
  printf '\n[Software\\\\Wine\\\\AppDefaults\\\\swtor_RC2.exe\\\\Mac Driver] 1763000000\n#time=1dc54a1b2c3d4e5\n"PhysicalKeyboard"="y"\n' >>"$FX_SS_SOM/prefix/user.reg"
  printf '# env of an earlier version\nSWTOR_DX12=1\n' >"$FX_SS_SOM/env"
  cp "$FX_SS_SOM/env" "$d/env.before"
  echo '{"version": "0.0.0-fx.0"}' >"$FX_SS_SOM/install-manifest.json"
  cp "$FX_SS_SOM/prefix/user.reg" "$d/user.reg.before"
  # (a settings.conf it can't read: every command refuses at once with one line, status says so
  # first, and nothing changes; the next check, once it can be read, goes on)
  cp "$FX_SS_SOM/settings.conf" "$d/settings.before"
  cp "$FX_SS_SOM/install-manifest.json" "$d/manifest.before"
  chmod 000 "$FX_SS_SOM/settings.conf"
  bad=""
  for k in rehook "set hudpos topright" "set debug on" install settings; do
    # shellcheck disable=SC2086 # (the command's words)
    fx_ss_som $k
    [ "$FX_RC" = 1 ] && [ "$(cat "$d/out.txt")" = "@error Settings can't be read: $FX_SS_SOM/settings.conf. Fix its permissions, then try again." ] || bad="$bad $k($FX_RC)"
  done
  rm -f "$FX_SS_SOM/install-manifest.json"
  fx_ss_som install
  [ "$FX_RC" = 1 ] && piped -q "^@error Settings can.t be read" "$d/out.txt" || bad="$bad install-without-manifest($FX_RC)"
  cp "$d/manifest.before" "$FX_SS_SOM/install-manifest.json"
  fx_ss_som status
  chmod 644 "$FX_SS_SOM/settings.conf"
  check "settings-sets: an unreadable settings.conf: rehook, set, install (with and without a manifest) and settings refuse with one line${bad:+ (not:$bad)}" test -z "$bad"
  check "settings-sets: ...settings.conf, env, user.reg as they were, no lock left" \
    eval 'cmp -s "$d/settings.before" "$FX_SS_SOM/settings.conf" && cmp -s "$d/env.before" "$FX_SS_SOM/env" && cmp -s "$d/user.reg.before" "$FX_SS_SOM/prefix/user.reg" && [ ! -e "$FX_SS_SOM/.lock" ]'
  check "settings-sets: ...status says so on its first line" \
    eval '[ "$(head -1 "$d/out.txt")" = "settings_error=Settings can'"'"'t be read: $FX_SS_SOM/settings.conf. Fix its permissions, then try again." ]'
  fx_ss_som status
  check "settings-sets: an earlier install whose env starts DirectX 12: status says dx12=on, settings_sets=no (Play waits for Update), no settings_error" \
    eval 'piped -qx dx12=on "$d/out.txt" && piped -qx settings_sets=no "$d/out.txt" && piped -qx installed_version=0.0.0-fx.0 "$d/out.txt" && ! piped -q settings_error "$d/out.txt"'
  # (the file turned unreadable, or the lock taken, after som.sh read it and before the
  # migration's lock: nothing written, busy for a change that holds the lock)
  SWTOR_ON_MAC_TEST_MIGRATE='chmod 000 "$SETTINGS"' fx_ss_som rehook
  chmod 644 "$FX_SS_SOM/settings.conf"
  check "settings-sets: settings.conf unreadable by the migration's read under the lock: its bytes kept, no lock left ($FX_RC)" \
    eval 'cmp -s "$d/settings.before" "$FX_SS_SOM/settings.conf" && [ ! -e "$FX_SS_SOM/.lock" ]'
  SWTOR_ON_MAC_TEST_MIGRATE='mkdir "$SOM/.lock"' fx_ss_som rehook
  check "settings-sets: a change takes the lock before the migration: busy, its bytes kept ($FX_RC)" \
    eval 'piped -qx "@notice busy" "$d/out.txt" && cmp -s "$d/settings.before" "$FX_SS_SOM/settings.conf"'
  rmdir "$FX_SS_SOM/.lock"
  fx_ss_som rehook
  check "settings-sets: an earlier install with DirectX 12 on: the hook check writes both sets into settings.conf, the DirectX 9 set's lines as they were" \
    eval 'fx_ss_conf dx12.hud=on && fx_ss_conf dx12.hudpos=topleft && diff <(grep -v -e "^#" -e "^dx12\\." "$d/settings.old" | sed "s/^dx12=off$/dx12=on/") <(grep -v -e "^#" -e "^dx12\\." "$FX_SS_SOM/settings.conf") >/dev/null'
  check "settings-sets: ...and nothing else: env and user.reg as they were" \
    eval 'cmp -s "$d/env.before" "$FX_SS_SOM/env" && cmp -s "$d/user.reg.before" "$FX_SS_SOM/prefix/user.reg"'
  cp "$FX_SS_SOM/settings.conf" "$d/settings.before"
  fx_ss_som set hud off
  check "settings-sets: ...DirectX 12's set can't change until Update: said so, settings.conf unchanged ($FX_RC)" \
    eval '[ "$FX_RC" = 1 ] && piped -q "^@error SWTOR on Mac 0.0.0-fx.0 is installed. Click Update" "$d/out.txt" && cmp -s "$d/settings.before" "$FX_SS_SOM/settings.conf"'
  echo '{"version": "0.0.0-fx.1"}' >"$FX_SS_SOM/install-manifest.json"
  fx_ss_som set hud off
  check "settings-sets: ...an earlier build of this version: Reinstall first, said so ($FX_RC)" \
    eval '[ "$FX_RC" = 1 ] && piped -q "^@error The installed SWTOR on Mac is an earlier build of 0.0.0-fx.1. Click Reinstall first" "$d/out.txt" && cmp -s "$d/settings.before" "$FX_SS_SOM/settings.conf"'
  fx_ss_som set debug off
  check "settings-sets: ...a global setting can ($FX_RC)" eval '[ "$FX_RC" = 0 ] && fx_ss_conf debug=off'

  # 8. the set a session ran with, in the session report
  printf 'SWTOR on Mac 0.0.0-fx.1: engine cx26 cx-26.3.0-8, d9mt abc1234, started 2026-11-26 10:00:00\nSWTOR on Mac settings: debug-logging=off hud=off game-mode=off native-fullscreen=off\nSWTOR on Mac settings set: DirectX 9'"'"'s (DirectX 12 is on, but swtor.exe runs: fell back)\n' >"$d/wine.log"
  "$res/session-report.sh" "$d/wine.log" >"$d/report.txt" 2>&1 || true
  check "settings-sets: the session report shows the set a session ran with, a fallback said" grep -qE "^  Settings set +DirectX 9's \(DirectX 12 is on, but swtor.exe runs: fell back\)$" "$d/report.txt"
}
