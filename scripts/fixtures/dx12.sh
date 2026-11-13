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
  echo '{}' >"$FX_DX12_SOM/install-manifest.json"
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
  check "dx12: on: swtor_RC2.exe gets swtor.exe's Mac driver values and GrabPointer" \
    eval 'fx_dx12_reg "swtor_RC2.exe\\\\Mac Driver" "\"PhysicalKeyboard\"=\"n\"" && fx_dx12_reg "swtor_RC2.exe\\\\Mac Driver" "\"RawMouseWhenCursorHidden\"=\"y\"" && fx_dx12_reg "swtor_RC2.exe\\\\Mac Driver" "\"RawMouseGameControllerScale\"=\"1\"" && fx_dx12_reg "swtor_RC2.exe\\\\Mac Driver" "\"ThreadCpuStats\"=\"y\"" && fx_dx12_reg "swtor_RC2.exe\\\\X11 Driver" "\"GrabPointer\"=\"n\""'
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

  # No swtor_RC2.exe next to swtor.exe: swtor.exe as always, and said so
  rm "$FX_DX12_SOM/prefix/drive_c/swtor/retailclient/swtor_RC2.exe"
  fx_dx12_game "$win"
  check "dx12: no swtor_RC2.exe: swtor.exe's command byte for byte, d3d9=n,b" \
    eval 'cmp -s "$FX_DX12_W/args" "$d/args.off" && [ "$(fx_dx12_seen WINEDLLOVERRIDES)" = d3d9=n,b ]'
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
  fx_dx12_som dev set dx12 on
  fx_dx12_som dev set mousespeed 1.5
  check "dx12: on: Mouse-Look Speed 1.5 for swtor.exe and swtor_RC2.exe ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && fx_dx12_reg "swtor.exe\\\\Mac Driver" "\"RawMouseGameControllerScale\"=\"1.5\"" && fx_dx12_reg "swtor_RC2.exe\\\\Mac Driver" "\"RawMouseGameControllerScale\"=\"1.5\""'
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
