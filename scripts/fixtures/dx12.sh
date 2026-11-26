# shellcheck shell=bash
# DirectX 12 (experimental, development builds) on a planted install: the app's som.sh as a
# development and as a release build (a copy with its app.properties) writes settings.conf, env
# and the prefix's user.reg, and the app's wrapper, reading that env, starts a stand-in engine
# whose bin/wine records the command and the environment it got. No Wine, no game, no official
# app. Fixture group dx12 (scripts/test-fixtures.sh) and scripts/test-sandbox.sh's section 17.
# Sourced; check and its counters come from lib.sh.

# fx_dx12_res <dev|release>: the app's som.sh and the files it reads, with an app.properties of
# that channel, in $FX_DX12_D/<channel> (som.sh takes its Resources from its own folder)
fx_dx12_res() {
  local r="$FX_DX12_D/$1" res="$FX_DX12_APP/Contents/Resources"
  mkdir -p "$r/d9mt"
  cp "$res/som.sh" "$res/dxvk.conf" "$res/wine-wrapper.sh" "$r/"
  cp "$res/d9mt/VERSION" "$r/d9mt/"
  chmod 755 "$r/som.sh"
  printf 'version=0.0.0-fx.1\nchannel=%s\n' "$1" >"$r/app.properties"
}
# fx_dx12_som <dev|release> <som.sh arguments>: that build's som.sh on the planted install;
# FX_RC its exit status, $FX_DX12_D/out.txt what it printed
fx_dx12_som() {
  local c=$1; shift
  FX_RC=0
  SWTOR_ON_MAC_ROOT="$FX_DX12_D/root" "$FX_DX12_D/$c/som.sh" "$@" >"$FX_DX12_D/out.txt" 2>&1 || FX_RC=$?
}
# fx_dx12_reg <key under AppDefaults, as in user.reg> <value line>: the value is set there
fx_dx12_reg() {
  K="[Software\\\\Wine\\\\AppDefaults\\\\$1]" V="$2" awk 'BEGIN { k = ENVIRON["K"]; v = ENVIRON["V"] }
    index($0, "[") == 1 { inkey = (substr($0, 1, length(k)) == k && substr($0, length(k) + 1, 1) == " ") }
    inkey && $0 == v { found = 1 }
    END { exit !found }' "$FX_DX12_SOM/prefix/user.reg"
}
# fx_dx12_env <variable>: its value as the wrapper gets it from the planted env, or <unset>
fx_dx12_env() { ( set -a; . "$FX_DX12_SOM/env"; set +a; eval "printf '%s' \"\${$1-<unset>}\"" ); }
# fx_dx12_game <path to swtor.exe as the launcher gives it>: a game start through the wrapper
# (the launcher's command: Broadsword's bin/wine64, the game, its arguments with the account)
fx_dx12_game() {
  rm -f "$FX_DX12_W/args" "$FX_DX12_W/seen"
  "$FX_DX12_W/bin/wine64-preloader" "$FX_DX12_W/bin/wine64" "$1" -set username TESTACCOUNT -set password SECRETTOKEN \
    -set lang en-us @swtor_dual.icb >/dev/null 2>&1
}
# fx_dx12_seen <variable>: its value in the stand-in engine's last start, or <unset>
fx_dx12_seen() { sed -n "s/^$1=//p" "$FX_DX12_W/seen"; }

# fx_dx12 <app> <folder>
fx_dx12() {
  local d=$2 sha win unix logs
  FX_DX12_APP=$1 FX_DX12_D=$2
  FX_DX12_SOM="$d/root/home/Library/Application Support/SWTOR on Mac"
  FX_DX12_W="$d/launcher"
  logs="$d/root/home/Library/Logs/SWTOR on Mac"
  fx_dx12_res dev
  fx_dx12_res release
  # the planted install: its manifest, an engine som.sh takes for its own (.som-source) with a
  # stand-in bin/wine, and a prefix with swtor.exe's values in user.reg and the game in C:
  sha=$(sed -n 's/^ENGINE_SHA256=//p' "$d/dev/som.sh")
  mkdir -p "$FX_DX12_SOM/engine/bin" "$FX_DX12_SOM/prefix/dosdevices" "$FX_DX12_SOM/prefix/drive_c/swtor/retailclient" \
    "$d/unix/retailclient" "$FX_DX12_W/bin" "$FX_DX12_W/bin-real"
  echo '{"version": "0.0.0-fx.1", "settings_sets": "yes"}' >"$FX_DX12_SOM/install-manifest.json"
  echo "$sha" >"$FX_DX12_SOM/engine/.som-source"
  ln -s ../drive_c "$FX_DX12_SOM/prefix/dosdevices/c:"
  touch "$FX_DX12_SOM/prefix/drive_c/swtor/retailclient/swtor.exe" "$FX_DX12_SOM/prefix/drive_c/swtor/retailclient/swtor_RC2.exe" \
    "$d/unix/retailclient/swtor.exe" "$d/unix/retailclient/swtor_RC2.exe"
  cat >"$FX_DX12_SOM/prefix/user.reg" <<'REG'
WINE REGISTRY Version 2
;; All keys relative to \\User\\S-1-5-21-0-0-0-1000

#arch=win64

[Software\\Wine\\AppDefaults\\swtor.exe\\DllOverrides] 1763000000
#time=1dc54a1b2c3d4e5
"d3d9"="native,builtin"

[Software\\Wine\\AppDefaults\\swtor.exe\\Mac Driver] 1763000000
#time=1dc54a1b2c3d4e5
"NativeFullscreen"="n"
"PhysicalKeyboard"="n"
"RawMouseGameControllerScale"="1"
"RawMouseWhenCursorHidden"="y"
"ThreadCpuStats"="y"

[Software\\Wine\\AppDefaults\\swtor.exe\\X11 Driver] 1763000000
#time=1dc54a1b2c3d4e5
"GrabPointer"="n"

[Software\\Wine\\Mac Driver] 1763000000
#time=1dc54a1b2c3d4e5
"RetinaMode"="y"
REG
  cat >"$FX_DX12_SOM/engine/bin/wine" <<STUB
#!/bin/bash
printf '%s\n' "\$@" >"$FX_DX12_W/args"
printf 'WINEDLLOVERRIDES=%s\nD3DM_MTL4=%s\nMULLION_D3D12_METAL4=%s\nMULLION_LOG_PATH=%s\nMULLION_DIAG_PATH=%s\nCX_APPLEGPTK_LIBD3DSHARED_PATH=%s\n' "\${WINEDLLOVERRIDES-<unset>}" "\${D3DM_MTL4-<unset>}" \
  "\${MULLION_D3D12_METAL4-<unset>}" "\${MULLION_LOG_PATH-<unset>}" "\${MULLION_DIAG_PATH-<unset>}" "\${CX_APPLEGPTK_LIBD3DSHARED_PATH-<unset>}" >"$FX_DX12_W/seen"
printf 'MULLION_SESSION_HEADER=%s\nMULLION_STATS=%s\nMULLION_MEMSTATS=%s\nMULLION_CONFIG=%s\nMULLION_TRACE_DIR=%s\n' "\${MULLION_SESSION_HEADER-<unset>}" "\${MULLION_STATS-<unset>}" "\${MULLION_MEMSTATS-<unset>}" "\${MULLION_CONFIG-<unset>}" "\${MULLION_TRACE_DIR-<unset>}" >>"$FX_DX12_W/seen"
printf 'MULLION_SYNC_INTERVAL=%s\nMULLION_FPS_CAP=%s\nMULLION_PACE=%s\nMULLION_DISPLAY_SYNC=%s\nMULLION_LOG_LEVEL=%s\nMTL_HUD_ENABLED=%s\n' "\${MULLION_SYNC_INTERVAL-<unset>}" "\${MULLION_FPS_CAP-<unset>}" \
  "\${MULLION_PACE-<unset>}" "\${MULLION_DISPLAY_SYNC-<unset>}" "\${MULLION_LOG_LEVEL-<unset>}" "\${MTL_HUD_ENABLED-<unset>}" >>"$FX_DX12_W/seen"
STUB
  # (hold-launcher's stand-in: no Wine session to start; --run-game <log> <lang> <wine> <args>)
  printf '#!/bin/bash\ncase "$1" in --run-game) shift 3; exec "$@" ;; esac\nexit 0\n' >"$FX_DX12_W/bin-real/hold-launcher"
  chmod 755 "$FX_DX12_SOM/engine/bin/wine" "$FX_DX12_W/bin-real/hold-launcher"
  sed "s|@CONF@|$FX_DX12_SOM/env|" "$d/dev/wine-wrapper.sh" >"$FX_DX12_W/bin/wine64-preloader"
  chmod 755 "$FX_DX12_W/bin/wine64-preloader"
  win='C:\swtor\retailclient\swtor.exe' unix="$d/unix/retailclient/swtor.exe"

  # Off (the default): env and user.reg as without the setting, the game's command unchanged
  fx_dx12_som dev set hud off
  check "dx12: development build, DirectX 12 off by default, driver mullion ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && grep -qx dx12=off "$FX_DX12_SOM/settings.conf" && grep -qx dx12driver=mullion "$FX_DX12_SOM/settings.conf"'
  # (the checks below are D3DMetal's, from the engine; Mullion's are in dx12-mullion.sh)
  fx_dx12_som dev set dx12driver gptk
  # (the DirectX 9 set: d9mt's 60 fps cap and the Metal HUD, which a fallback to swtor.exe keeps)
  fx_dx12_som dev set fpslimit 60
  fx_dx12_som dev set hud on
  check "dx12: off: no swtor-dx12 rule, no SWTOR_DX12 lines in env" \
    eval '! grep -q -e swtor-dx12 -e SWTOR_DX12 "$FX_DX12_SOM/env"'
  cp "$FX_DX12_SOM/env" "$d/env.off"; cp "$FX_DX12_SOM/prefix/user.reg" "$d/user.reg.off"
  fx_dx12_game "$win"; cp "$FX_DX12_W/args" "$d/args.off"
  check "dx12: off: the game's command as the launcher gave it, d9mt's d3d9=n,b ($(fx_dx12_seen WINEDLLOVERRIDES))" \
    eval '[ "$(sed -n 1p "$d/args.off")" = "$win" ] && [ "$(sed -n 2p "$d/args.off")" = -set ] && [ "$(fx_dx12_seen WINEDLLOVERRIDES)" = d3d9=n,b ]'
  check "dx12: off: no DirectX 12 line in wine.log" eval '[ -s "$logs/wine.log" ] && ! grep -q "DirectX 12" "$logs/wine.log"'

  # On: the rule and the wrapper's switch in env, swtor_RC2.exe's values in user.reg
  fx_dx12_som dev set dx12 on
  check "dx12: set dx12 on ($FX_RC)" eval '[ "$FX_RC" = 0 ] && grep -qx dx12=on "$FX_DX12_SOM/settings.conf"'
  check "dx12: on: compatdb's swtor-dx12 rule gives swtor_RC2.exe D3DMetal's tree, after the exe=* rule" \
    eval '[ "$(fx_dx12_env WINE_COMPATDB)" = "$(printf "v=5\nname=swtor-on-mac;exe=*;dxgi=wined3d\nname=swtor-dx12;exe=swtor_RC2.exe;dxgi=gptk")" ]'
  check "dx12: on: SWTOR_DX12=1 and SWTOR_DX12_DRIVER=gptk for the wrapper" \
    eval '[ "$(fx_dx12_env SWTOR_DX12)/$(fx_dx12_env SWTOR_DX12_DRIVER)" = 1/gptk ]'
  # (swtor_RC2.exe gets the DirectX 12 set's: raw mouse-look and the other DX9-only settings
  # off; swtor.exe keeps the DirectX 9 set's; fixture group settings-sets checks the sets)
  check "dx12: on: swtor_RC2.exe gets the DirectX 12 set's Mac driver values (its DX9-only ones off) and GrabPointer" \
    eval 'fx_dx12_reg "swtor_RC2.exe\\\\Mac Driver" "\"NativeFullscreen\"=\"n\"" && fx_dx12_reg "swtor_RC2.exe\\\\Mac Driver" "\"PhysicalKeyboard\"=\"n\"" && fx_dx12_reg "swtor_RC2.exe\\\\Mac Driver" "\"RawMouseWhenCursorHidden\"=\"n\"" && fx_dx12_reg "swtor_RC2.exe\\\\Mac Driver" "\"RawMouseGameControllerScale\"=\"1\"" && fx_dx12_reg "swtor_RC2.exe\\\\Mac Driver" "\"ThreadCpuStats\"=\"y\"" && fx_dx12_reg "swtor_RC2.exe\\\\X11 Driver" "\"GrabPointer\"=\"n\"" && fx_dx12_reg "swtor.exe\\\\Mac Driver" "\"RawMouseWhenCursorHidden\"=\"y\""'
  check "dx12: on: swtor_RC2.exe gets Wine's builtin d3d9, swtor.exe keeps d9mt's native,builtin" \
    eval 'fx_dx12_reg "swtor_RC2.exe\\\\DllOverrides" "\"d3d9\"=\"builtin\"" && fx_dx12_reg "swtor.exe\\\\DllOverrides" "\"d3d9\"=\"native,builtin\""'

  # The wrapper with DirectX 12 on: swtor_RC2.exe, every other argument as it was
  fx_dx12_game "$win"
  check "dx12: on: the game's command with C:\\...\\swtor_RC2.exe, every other argument unchanged" \
    eval '[ "$(sed -n 1p "$FX_DX12_W/args")" = "C:\\swtor\\retailclient\\swtor_RC2.exe" ] && [ "$(sed 1d "$FX_DX12_W/args")" = "$(sed 1d "$d/args.off")" ]'
  check "dx12: on: Wine's builtin d3d9 for it (d3d9=b), no Metal 3 switch ($(fx_dx12_seen WINEDLLOVERRIDES), $(fx_dx12_seen D3DM_MTL4))" \
    eval '[ "$(fx_dx12_seen WINEDLLOVERRIDES)/$(fx_dx12_seen D3DM_MTL4)" = "d3d9=b/<unset>" ]'
  check "dx12: on: wine.log names the client, the driver, its tree and the engine's D3DMetal (no Info.plist planted: unknown)" \
    grep -qx "SWTOR on Mac DirectX 12: swtor_RC2.exe, driver gptk (dxgi=gptk), D3DMetal unknown (the engine's)" "$logs/wine.log"
  check "dx12: on: effective-env.txt has the game's d3d9=b" grep -qx WINEDLLOVERRIDES=d3d9=b "$logs/effective-env.txt"
  # (the DirectX 12 set's HUD: off, as the DirectX 9 set had it at the file's first write; the
  # DirectX 9 set's hud=on since is its own)
  check "dx12: on: wine.log names the DirectX 12 set, no d9mt frame rate limit (a DirectX 9 setting), the DirectX 12 set's HUD (off)" \
    eval 'grep -qx "SWTOR on Mac settings set: DirectX 12'"'"'s" "$logs/wine.log" && ! grep -q "SWTOR on Mac frame rate limit" "$logs/wine.log" && [ "$(fx_dx12_seen MTL_HUD_ENABLED)" = "<unset>" ]'
  fx_dx12_som dev set hud on
  fx_dx12_game "$win"
  check "dx12: on, the DirectX 12 set's HUD on: swtor_RC2.exe gets it, both sets keep their own lines ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && [ "$(fx_dx12_seen MTL_HUD_ENABLED)" = 1 ] && grep -qx hud=on "$FX_DX12_SOM/settings.conf" && grep -qx dx12.hud=on "$FX_DX12_SOM/settings.conf"'
  fx_dx12_som dev set hud off
  fx_dx12_game "$unix"
  check "dx12: on: a Unix path to swtor.exe works the same" \
    eval '[ "$(sed -n 1p "$FX_DX12_W/args")" = "$d/unix/retailclient/swtor_RC2.exe" ] && [ "$(fx_dx12_seen WINEDLLOVERRIDES)" = d3d9=b ]'
  rm -f "$FX_DX12_W/args"
  "$FX_DX12_W/bin/wine64-preloader" "$FX_DX12_W/bin/wine64" 'C:\windows\system32\reg.exe' query 'HKCU\Software' >/dev/null 2>&1
  check "dx12: on: another Wine start is left alone (its command, d3d9=n,b, no Metal 3 switch)" \
    eval '[ "$(sed -n 1p "$FX_DX12_W/args")" = "C:\\windows\\system32\\reg.exe" ] && [ "$(fx_dx12_seen WINEDLLOVERRIDES)/$(fx_dx12_seen D3DM_MTL4)" = "d3d9=n,b/<unset>" ]'

  # D3DMetal on Metal 3
  fx_dx12_som dev set dx12driver gptk-mtl3
  fx_dx12_game "$win"
  check "dx12: driver gptk-mtl3: D3DM_MTL4=0 for the game, the same tree, named in wine.log ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && [ "$(fx_dx12_seen D3DM_MTL4)" = 0 ] && grep -qx "SWTOR on Mac DirectX 12: swtor_RC2.exe, driver gptk-mtl3 (dxgi=gptk), D3DM_MTL4=0, D3DMetal unknown (the engine'"'"'s)" "$logs/wine.log"'
  fx_dx12_som dev set dx12driver vulkan
  check "dx12: an unknown driver is refused, the setting kept ($FX_RC)" eval '[ "$FX_RC" = 2 ] && grep -qx dx12driver=gptk-mtl3 "$FX_DX12_SOM/settings.conf"'
  fx_dx12_som dev set dx12driver gptk

  # D3DMetal imported by som.sh dx12-gptk (its record planted; the import itself is fixture group
  # dx12-gptk's): the game's ntdll gets the import's libd3dshared, nothing else does
  mkdir -p "$FX_DX12_SOM/engine/lib/external/gptk-import"
  printf 'version=4.0b3\nimage=Evaluation environment for Windows games 4.0 beta 3\nadded=d3d12core\n' >"$FX_DX12_SOM/engine/lib/external/gptk-import/IMPORTED"
  fx_dx12_som dev set dx12driver gptk
  fx_dx12_game "$win"
  check "dx12: imported D3DMetal: the game gets CX_APPLEGPTK_LIBD3DSHARED_PATH to the import's libd3dshared, wine.log names its version ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && [ "$(fx_dx12_seen CX_APPLEGPTK_LIBD3DSHARED_PATH)" = "$FX_DX12_SOM/engine/lib/external/gptk-import/libd3dshared.dylib" ] && grep -qx "SWTOR on Mac DirectX 12: swtor_RC2.exe, driver gptk (dxgi=gptk), D3DMetal 4.0b3 (imported: Evaluation environment for Windows games 4.0 beta 3)" "$logs/wine.log"'
  "$FX_DX12_W/bin/wine64-preloader" "$FX_DX12_W/bin/wine64" 'C:\windows\system32\reg.exe' query 'HKCU\Software' >/dev/null 2>&1
  check "dx12: imported D3DMetal: another Wine start keeps lib/external's libd3dshared (no CX_APPLEGPTK_LIBD3DSHARED_PATH)" \
    test "$(fx_dx12_seen CX_APPLEGPTK_LIBD3DSHARED_PATH)" = "<unset>"
  mv "$FX_DX12_SOM/prefix/drive_c/swtor/retailclient/swtor_RC2.exe" "$d/swtor_RC2.exe"
  fx_dx12_game "$win"
  check "dx12: imported D3DMetal, no swtor_RC2.exe: swtor.exe keeps lib/external's libd3dshared too" \
    eval 'cmp -s "$FX_DX12_W/args" "$d/args.off" && [ "$(fx_dx12_seen CX_APPLEGPTK_LIBD3DSHARED_PATH)" = "<unset>" ]'
  mv "$d/swtor_RC2.exe" "$FX_DX12_SOM/prefix/drive_c/swtor/retailclient/swtor_RC2.exe"
  rm -rf "$FX_DX12_SOM/engine/lib/external/gptk-import"
  fx_dx12_som dev set dx12driver gptk
  check "dx12: without an import: no SWTOR_DX12_LIBD3DSHARED in env ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && [ "$(fx_dx12_env SWTOR_DX12_LIBD3DSHARED)" = "<unset>" ]'
  # DirectX 12's game window fitted to its screen (fx_dx12_fit, below)
  fx_dx12_fit "$d"

  # No swtor_RC2.exe next to swtor.exe: swtor.exe as always, and said so
  rm "$FX_DX12_SOM/prefix/drive_c/swtor/retailclient/swtor_RC2.exe"
  fx_dx12_game "$win"
  check "dx12: no swtor_RC2.exe: swtor.exe's command byte for byte, d3d9=n,b" \
    eval 'cmp -s "$FX_DX12_W/args" "$d/args.off" && [ "$(fx_dx12_seen WINEDLLOVERRIDES)" = d3d9=n,b ]'
  check "dx12: no swtor_RC2.exe: swtor.exe with the DirectX 9 set (its 60 fps cap and HUD), wine.log says it fell back" \
    eval 'grep -qx "SWTOR on Mac settings set: DirectX 9'"'"'s (DirectX 12 is on, but swtor.exe runs: fell back)" "$logs/wine.log" && grep -qx "SWTOR on Mac frame rate limit: 60 fps" "$logs/wine.log" && [ "$(fx_dx12_seen MTL_HUD_ENABLED)" = 1 ]'
  check "dx12: no swtor_RC2.exe: said in wine.log and hold.log" \
    eval 'grep -qx "SWTOR on Mac DirectX 12: swtor_RC2.exe not found next to swtor.exe: starting swtor.exe" "$logs/wine.log" && grep -q "DirectX 12: swtor_RC2.exe not found next to swtor.exe: starting swtor.exe$" "$logs/hold.log"'
  touch "$FX_DX12_SOM/prefix/drive_c/swtor/retailclient/swtor_RC2.exe"
  check "dx12: no account, token or folder of the game in the logs" \
    eval '! grep -rq -e TESTACCOUNT -e SECRETTOKEN -e retailclient "$logs"'

  # Off again: env and user.reg as before it was on
  fx_dx12_som dev set dx12 off
  check "dx12: set dx12 off: env byte for byte as before it was on ($FX_RC)" eval '[ "$FX_RC" = 0 ] && cmp -s "$d/env.off" "$FX_DX12_SOM/env"'
  check "dx12: set dx12 off: user.reg byte for byte as before (swtor_RC2.exe's keys gone)" cmp -s "$d/user.reg.off" "$FX_DX12_SOM/prefix/user.reg"
  fx_dx12_game "$win"
  check "dx12: off again: swtor.exe's command byte for byte" cmp -s "$FX_DX12_W/args" "$d/args.off"

  # A release build: no DirectX 12, whatever settings.conf says
  fx_dx12_som release set dx12 on
  check "dx12: release build: set dx12 refused, settings.conf unchanged ($FX_RC)" \
    eval '[ "$FX_RC" = 1 ] && grep -q "^@error DirectX 12 is in development builds only" "$d/out.txt" && grep -qx dx12=off "$FX_DX12_SOM/settings.conf"'
  # (a change of swtor.exe's values moves them in user.reg: after the byte-for-byte checks)
  fx_dx12_som dev set mousespeed 1.5
  fx_dx12_som dev set dx12 on
  check "dx12: Mouse-Look Speed 1.5 in the DirectX 9 set: swtor.exe gets it, swtor_RC2.exe the DirectX 12 set's 1 ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && grep -qx mousespeed=1.5 "$FX_DX12_SOM/settings.conf" && fx_dx12_reg "swtor.exe\\\\Mac Driver" "\"RawMouseGameControllerScale\"=\"1.5\"" && fx_dx12_reg "swtor_RC2.exe\\\\Mac Driver" "\"RawMouseGameControllerScale\"=\"1\""'
  # a release build installed over it, dx12=on still in settings.conf
  fx_dx12_som release set mousespeed 1
  check "dx12: release build with a stale dx12=on: env without DirectX 12 ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && grep -qx dx12=on "$FX_DX12_SOM/settings.conf" && ! grep -q -e swtor-dx12 -e SWTOR_DX12 "$FX_DX12_SOM/env"'
  check "dx12: release build: swtor_RC2.exe's keys removed from user.reg, swtor.exe's kept" \
    eval '! grep -qi "swtor_RC2" "$FX_DX12_SOM/prefix/user.reg" && fx_dx12_reg "swtor.exe\\\\DllOverrides" "\"d3d9\"=\"native,builtin\""'
  fx_dx12_game "$win"
  check "dx12: release build: swtor.exe's command byte for byte" cmp -s "$FX_DX12_W/args" "$d/args.off"
  # Mullion's switches at the game's start, on this planted install (dx12-mullion.sh)
  fx_dx12_mullion_start "$d"
}

# fx_dx12_fit <folder>: DirectX 12's game window (Settings: "Fit the game window to the screen at
# each start", som.sh fit-window, which Play SWTOR runs before it opens the launcher) on fx_dx12's
# planted install, DirectX 12 on: the four window keys of client_settings_DX12.ini's [Renderer]
# from the screens Play passes (two: the main one first), a missing one added, every other byte
# kept (CRLF, an unterminated last line, the file's mode); the backup in the app's folder, none
# beside the file; the log line numbers only; nothing written for the setting off, a release
# build, no file or section, no screen, an unreadable file; a game start changes nothing. A
# control: a som.sh that ignores the section fails the "nothing else" check.
fx_dx12_fit() {
  local d=$1 win='C:\swtor\retailclient\swtor.exe' set ini
  local s1="0.00,0.00,1920.00,1080.00,0.00,62.00,1920.00,1018.00" s2="1920.00,0.00,1728.00,1117.00,1920.00,69.00,1728.00,1048.00"
  set="$FX_DX12_SOM/prefix/drive_c/users/crossover/AppData/Local/SWTOR/swtor/settings"
  ini="$set/client_settings_DX12.ini"
  check "dx12 fit: on by default" grep -qx dx12fit=on "$FX_DX12_SOM/settings.conf"
  fx_dx12_som release set dx12fit off
  check "dx12 fit: release build: set dx12fit refused ($FX_RC)" eval '[ "$FX_RC" = 1 ] && grep -qx dx12fit=on "$FX_DX12_SOM/settings.conf"'
  # no settings file yet (the client's first start writes it): none made
  fx_dx12_som dev fit-window "$s1" "$s2"
  check "dx12 fit: no client_settings_DX12.ini: none written ($FX_RC)" eval '[ "$FX_RC" = 0 ] && [ ! -e "$ini" ] && piped -qx "@done no file" "$d/out.txt"'
  # the game's file (CRLF), the window saved small on the second screen, a [Game] section with
  # keys of the same names, an unterminated last line, mode 600
  mkdir -p "$set"
  { printf '%s\r\n' '[Renderer]' 'AllowColorRemapping = false' 'DX12_RenderHeight = 2075' 'DX12_RenderWidth = 3840' 'Height = 1018' \
      'Width = 1920' 'WindowX = 4000' 'WindowY = 300' 'GammaRamp = 1' '[Game]' 'Width = 7' 'WindowX = 5'
    printf 'Last = 1'; } >"$ini"
  chmod 600 "$ini"; cp -p "$ini" "$d/ini.orig"
  sed 's/^Height = 1018/Height = 2096/; s/^Width = 1920/Width = 3456/; s/^WindowX = 4000/WindowX = 3840/; s/^WindowY = 300/WindowY = 138/' "$d/ini.orig" >"$d/ini.want2"
  # (a temporary file another attempt left beside it: never renamed over it)
  printf 'stale\n' >"$ini.new.1"
  fx_dx12_som dev fit-window "$s1" "$s2"
  check "dx12 fit: the window on the second screen gets that screen's area, every other byte kept (CRLF, the [Game] keys, the unterminated last line) ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && cmp -s "$ini" "$d/ini.want2" && piped -qx "@done fitted" "$d/out.txt"'
  check "dx12 fit: the file's mode kept (600), a stale temporary file of another attempt left as it was" \
    eval '[ "$(stat -c %a "$ini" 2>/dev/null || stat -f %Lp "$ini")" = 600 ] && [ "$(cat "$ini.new.1")" = stale ]'
  rm -f "$ini.new.1"
  check "dx12 fit: the game's file kept once in the app's folder (backup/, its mode 600), nothing new beside it in the prefix" \
    eval 'cmp -s "$FX_DX12_SOM/backup/client_settings_DX12.ini" "$d/ini.orig" && [ "$(stat -c %a "$FX_DX12_SOM/backup/client_settings_DX12.ini" 2>/dev/null || stat -f %Lp "$FX_DX12_SOM/backup/client_settings_DX12.ini")" = 600 ] && [ "$(ls -A "$set")" = client_settings_DX12.ini ]'
  check "dx12 fit: rehook.log has no path (the user's name is in them), the lock released" \
    eval '! grep -q "Application Support" "$FX_DX12_SOM/../../Logs/SWTOR on Mac/rehook.log" && [ ! -e "$FX_DX12_SOM/.lock" ]'
  check "dx12 fit: rehook.log names the screen and the numbers" \
    grep -q "fit-window: fitted to screen 2 of 2: 3840,138 3456x2096 (was 4000,300 1920x1018)$" "$FX_DX12_SOM/../../Logs/SWTOR on Mac/rehook.log"
  # a value that isn't a number (an e-mail address in a note after it): logged as ?, the window
  # then on the main screen (its centre unknown), no text of the file in the logs
  printf '%s\r\n' '[Renderer]' 'Height = 1018' 'Width = 1920 ; fx.person@example.com' 'WindowX = 4000' 'WindowY = 300' >"$ini"
  fx_dx12_som dev fit-window "$s1" "$s2"
  check "dx12 fit: a value that isn't a number: logged as ?, the main screen's area, no text of the file in the logs" \
    eval 'grep -q "fit-window: fitted to screen 1 of 2: 0,124 3840x2036 (was 4000,300 ?x1018)$" "$FX_DX12_SOM/../../Logs/SWTOR on Mac/rehook.log" && grep -q "^Width = 3840.$" "$ini" && ! grep -rq example.com "$FX_DX12_SOM/../../Logs/SWTOR on Mac"'
  # a game start (from Broadsword's launcher or not) changes nothing of it
  cp -p "$d/ini.orig" "$ini"
  fx_dx12_game "$win"
  check "dx12 fit: a game start leaves the file as the game saved it" cmp -s "$ini" "$d/ini.orig"
  # the saved centre on no screen (a display unplugged): the main screen's area; WindowY missing:
  # added at the end of [Renderer] with its line ending; the backup stays the first file
  printf '%s\r\n' '[Renderer]' 'Height = 1018' 'Width = 1920' 'WindowX = 9000' '[Game]' 'Width = 7' >"$ini"
  printf '%s\r\n' '[Renderer]' 'Height = 2036' 'Width = 3840' 'WindowX = 0' 'WindowY = 124' '[Game]' 'Width = 7' >"$d/ini.want1"
  fx_dx12_som dev fit-window "$s1" "$s2"
  check "dx12 fit: the saved centre unknown: the main screen's area, the missing WindowY added in [Renderer], the backup the first file still" \
    eval 'cmp -s "$ini" "$d/ini.want1" && cmp -s "$FX_DX12_SOM/backup/client_settings_DX12.ini" "$d/ini.orig"'
  fx_dx12_som dev fit-window "$s1" "$s2"
  check "dx12 fit: already fitted: unchanged, said so" eval 'cmp -s "$ini" "$d/ini.want1" && piped -qx "@done fitted already" "$d/out.txt"'
  # a missing key and an unterminated last line in [Renderer]: the keys before that line, which
  # keeps its bytes and ends the file as it did
  printf '%s\r\n' '[Renderer]' 'Height = 1018' 'Width = 1920' 'WindowX = 9000' >"$ini"; printf 'Gamma=1' >>"$ini"
  { printf '%s\r\n' '[Renderer]' 'Height = 2036' 'Width = 3840' 'WindowX = 0' 'WindowY = 124'; printf 'Gamma=1'; } >"$d/ini.want3"
  fx_dx12_som dev fit-window "$s1" "$s2"
  check "dx12 fit: a missing key and an unterminated last line: the key before it, the line and the end of the file as they were" cmp -s "$ini" "$d/ini.want3"
  # an install, uninstall or settings change running (the lock): nothing written, said so
  cp -p "$d/ini.orig" "$ini"; mkdir "$FX_DX12_SOM/.lock"
  fx_dx12_som dev fit-window "$s1" "$s2"
  rmdir "$FX_DX12_SOM/.lock"
  check "dx12 fit: the lock held by another command: nothing written, busy" eval 'cmp -s "$ini" "$d/ini.orig" && piped -qx "@notice busy" "$d/out.txt"'
  # a dry run: nothing written, no backup folder made
  rm -rf "$FX_DX12_SOM/backup"
  SWTOR_ON_MAC_DRY_RUN=1 fx_dx12_som dev fit-window "$s1" "$s2"
  check "dx12 fit: a dry run: nothing written, no backup folder" eval 'cmp -s "$ini" "$d/ini.orig" && [ ! -e "$FX_DX12_SOM/backup" ]'
  # the settings folder can't be written: the file as it was, nothing of the attempt left
  if [ "$(id -u)" != 0 ]; then
    chmod 555 "$set"
    fx_dx12_som dev fit-window "$s1" "$s2"
    chmod 755 "$set"
    check "dx12 fit: a folder that can't be written: the file unchanged, nothing left beside it" \
      eval 'cmp -s "$ini" "$d/ini.orig" && [ "$(ls -A "$set")" = client_settings_DX12.ini ] && piped -qx "@done not written" "$d/out.txt"'
  fi
  # no screen given, or none in the form: nothing written
  cp -p "$d/ini.orig" "$ini"
  fx_dx12_som dev fit-window
  check "dx12 fit: no screen: nothing written ($FX_RC)" eval '[ "$FX_RC" = 0 ] && cmp -s "$ini" "$d/ini.orig" && piped -qx "@done no screen" "$d/out.txt"'
  fx_dx12_som dev fit-window "1,2,3" "a,b,c,d,e,f,g,h"
  check "dx12 fit: screens not in the form: nothing written" eval 'cmp -s "$ini" "$d/ini.orig" && piped -qx "@done no screen" "$d/out.txt"'
  # the file can't be read: nothing written
  chmod 000 "$ini"
  fx_dx12_som dev fit-window "$s1" "$s2"
  chmod 600 "$ini"
  if [ "$(id -u)" != 0 ]; then
    check "dx12 fit: a file that can't be read: nothing written" eval 'cmp -s "$ini" "$d/ini.orig" && piped -qx "@done not read" "$d/out.txt"'
  fi
  # no [Renderer] section: nothing written
  printf '%s\r\n' '[Game]' 'Width = 7' >"$ini"; cp -p "$ini" "$d/ini.nosec"
  fx_dx12_som dev fit-window "$s1" "$s2"
  check "dx12 fit: no [Renderer] section: nothing written" eval 'cmp -s "$ini" "$d/ini.nosec" && piped -qx "@done no section" "$d/out.txt"'
  # the setting off, or DirectX 12 off: nothing written
  cp -p "$d/ini.orig" "$ini"
  fx_dx12_som dev set dx12fit off
  fx_dx12_som dev fit-window "$s1" "$s2"
  check "dx12 fit: the setting off: nothing written" eval 'cmp -s "$ini" "$d/ini.orig" && piped -qx "@done off" "$d/out.txt"'
  fx_dx12_som dev set dx12fit on
  fx_dx12_som dev set dx12 off
  fx_dx12_som dev fit-window "$s1" "$s2"
  check "dx12 fit: DirectX 12 off: nothing written" eval 'cmp -s "$ini" "$d/ini.orig" && piped -qx "@done off" "$d/out.txt"'
  fx_dx12_som dev set dx12 on
  # Retina mode off: Wine's pixels are points (the window saved on the second screen in points)
  fx_dx12_som dev set retina off
  printf '%s\r\n' '[Renderer]' 'Height = 509' 'Width = 960' 'WindowX = 2000' 'WindowY = 150' >"$ini"
  fx_dx12_som dev fit-window "$s1" "$s2"
  check "dx12 fit: Retina mode off: the second screen's area in points" eval 'grep -q "^WindowX = 1920.$" "$ini" && grep -q "^WindowY = 69.$" "$ini" && grep -q "^Width = 1728.$" "$ini" && grep -q "^Height = 1048.$" "$ini"'
  fx_dx12_som dev set retina on
  # the control: a som.sh that changes the four keys in every section
  cp "$FX_DX12_D/dev/som.sh" "$d/som.good"
  sed 's/if (in_r \&\& index(b, "=")) {$/if (index(b, "=")) {/' "$d/som.good" >"$FX_DX12_D/dev/som.sh"
  cp -p "$d/ini.orig" "$ini"
  fx_dx12_som dev fit-window "$s1" "$s2"
  if ! cmp -s "$FX_DX12_D/dev/som.sh" "$d/som.good" && ! cmp -s "$ini" "$d/ini.want2"; then
    ok "dx12 fit: control: a som.sh that ignores the section fails the check (the [Game] keys change)"
  else
    bad "dx12 fit: control: a som.sh that ignores the section passes the check"
  fi
  cp "$d/som.good" "$FX_DX12_D/dev/som.sh"
  rm -rf "$ini" "$FX_DX12_SOM/backup"
}
