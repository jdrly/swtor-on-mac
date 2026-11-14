# shellcheck shell=bash
# DirectX 12 on Mullion (development builds): som.sh's install_mullion on a planted install, in
# a sandbox root of its own, without the app's window, Wine or a game start. The engine's dxmt
# tree is the real one, unpacked from the pinned engine archive (downloaded once into the
# repository's .cache/<sha256>/, as scripts/test-sandbox.sh keeps it). Mullion's archives are
# stand-ins in the layout of my fork's builds (the files at the top, a VERSION), pinned in the
# test's copy of som.sh and served by scripts/fetch-test-server.py (SWTOR_ON_MAC_MULLION_URL); the
# real one is checked by scripts/check-mullion-pin.sh. Fixture group dx12-mullion (scripts/test-fixtures.sh), and scripts/test-sandbox.sh's
# section 17b. Sourced; check and its counters come from lib.sh.

# fx_dxm_cached <url> <sha256>: the path of the verified download in $REPO/.cache
fx_dxm_cached() {
  local f="$REPO/.cache/$2/${1##*/}"
  if [ ! -f "$f" ]; then mkdir -p "${f%/*}"; curl -fsSL -o "$f.part" "$1" && mv "$f.part" "$f"; fi
  [ "$(shasum -a 256 "$f" | cut -d' ' -f1)" = "$2" ] && echo "$f"
}
fx_dxm_val() { sed -n "/^$1=/{s/^$1=//p;q;}" "$2"; }
# fx_dxm [som.sh's arguments]: the development build's som.sh in the planted sandbox; FX_RC its
# exit status, $FX_DXM_D/out.txt what it printed. With FX_DXM_CP_FAIL=<file name>, a cp that
# copies part of that file and fails, as on a full disk, comes first on the PATH.
fx_dxm() {
  local path=$PATH
  [ -z "${FX_DXM_CP_FAIL:-}" ] || path="$FX_DXM_D/failcp:$PATH"
  FX_RC=0
  PATH="$path" FX_FAIL="${FX_DXM_CP_FAIL:-}" SWTOR_ON_MAC_ROOT="$FX_DXM_D/root" SWTOR_ON_MAC_MULLION_URL="${FX_DXM_URL:-}" \
    "$FX_DXM_D/dev/Resources/som.sh" "$@" >"$FX_DXM_D/out.txt" 2>&1 || FX_RC=$?
}
# fx_dxm_env <variable>: its value in the planted env, or <unset>
fx_dxm_env() { ( set -a; . "$FX_DXM_SOM/env"; set +a; eval "printf '%s' \"\${$1-<unset>}\"" ); }
# fx_dxm_stock: the tree is the engine's own, byte for byte as unpacked: the same names (but the
# .stock copies, and the <name>.new.<pid> a copy that the tests make fail leaves), the same files,
# the link to the main tree's winemetal.so; no Mullion file and no mark
fx_dxm_stock() {
  local f
  [ "$(cd "$FX_DXM_ORIG" && find . | sort)" = "$(cd "$FX_DXM_T" && find . ! -name '*.stock' ! -name '*.new.*' | sort)" ] || return 1
  (cd "$FX_DXM_ORIG" && find . -type f) | while read -r f; do cmp -s "$FX_DXM_ORIG/$f" "$FX_DXM_T/$f" || exit 1; done || return 1
  [ "$(readlink "$FX_DXM_T/x86_64-unix/winemetal.so")" = ../../../x86_64-unix/winemetal.so ]
}
# fx_dxm_mullion: the tree has the pinned build's files, its own winemetal.so in place of the
# link, the mark (its sha256), no file of the earlier pin
fx_dxm_mullion() {
  local f
  for f in $FX_DXM_FILES; do cmp -s "$FX_DXM_REL/$f" "$FX_DXM_T/$f" || return 1; done
  for f in nvapi64.dll nvngx.dll; do [ ! -e "$FX_DXM_T/x86_64-windows/$f" ] || return 1; done
  [ ! -L "$FX_DXM_T/x86_64-unix/winemetal.so" ] && [ "$(sed -n 1p "$FX_DXM_T/.mullion")" = "$FX_DXM_SHA" ]
}
# fx_dxm_archive <file> <commit> [<codegen>]: a stand-in for my fork's archive of that commit, in
# its layout (the files at the top, VERSION, LICENSE), each file naming the commit
fx_dxm_archive() {
  local s="$1.src" f
  mkdir -p "$s/x86_64-windows" "$s/x86_64-unix"
  for f in $FX_DXM_FILES; do echo "stand-in $f of $2" >"$s/$f"; done
  printf 'v0.5-alpha.3-1-g%s\ncommit: %s\ncodegen: %s\ntoolchain: a stand-in\n' "${2:0:7}" "$2" "${3:-airconv 103}" >"$s/VERSION"
  echo "a stand-in" >"$s/LICENSE"
  tar -cJf "$1" -C "$s" x86_64-windows x86_64-unix VERSION LICENSE
  rm -rf "$s"
}
# fx_dxm_pin <archive> <commit>: the test's som.sh pins that archive as a build of that commit
fx_dxm_pin() {
  FX_DXM_SHA=$(shasum -a 256 "$1" | cut -d' ' -f1)
  sed -i.bak -e "s/^MULLION_COMMIT=.*/MULLION_COMMIT=$2/" -e "s/^MULLION_SIZE=.*/MULLION_SIZE=$(wc -c <"$1" | tr -d ' ')/" \
    -e "s/^MULLION_SHA256=.*/MULLION_SHA256=$FX_DXM_SHA/" -e "s|^MULLION_URL=.*|MULLION_URL=https://github.example/${1##*/}|" \
    -e "s|^MULLION_TITLE=.*|MULLION_TITLE=\"Mullion (jdrly/mullion ${2:0:7})\"|" "$FX_DXM_D/dev/Resources/som.sh"
}
# fx_dxm_upstream: the tree as Mullion v0.5-alpha.3, the pin before my fork's, left it: the
# engine's files kept as .stock, its nine files (the NVIDIA shims too) over the tree's, its mark
fx_dxm_upstream() {
  local f
  for f in d3d10core.dll d3d11.dll dxgi.dll winemetal.dll; do
    cp "$FX_DXM_ORIG/x86_64-windows/$f" "$FX_DXM_T/x86_64-windows/$f.stock"
  done
  rm -f "$FX_DXM_T/x86_64-unix/winemetal.so"
  for f in $FX_DXM_FILES x86_64-windows/nvapi64.dll x86_64-windows/nvngx.dll; do echo "v0.5-alpha.3's $f" >"$FX_DXM_T/$f"; done
  echo b743f2ffcd88392e91f1b52e007137ce897c0ffc4e3376d17218da075b5c646c >"$FX_DXM_T/.mullion"
}

# fx_dxm_kept: the engine's own files Mullion replaces are kept next to them as .stock
fx_dxm_kept() {
  local f
  for f in d3d10core.dll d3d11.dll dxgi.dll winemetal.dll; do
    cmp -s "$FX_DXM_ORIG/x86_64-windows/$f" "$FX_DXM_T/x86_64-windows/$f.stock" || return 1
  done
}

# fx_dx12_mullion_start <folder>: Mullion's switches at the game's start, through the wrapper on
# the planted install of scripts/fixtures/dx12.sh's fx_dx12 (its helpers and stand-in engine;
# called at its end). Its engine has no dxmt tree: the mark stands for an installed Mullion.
fx_dx12_mullion_start() {
  local d=$1 t logs win='C:\swtor\retailclient\swtor.exe'
  t="$FX_DX12_SOM/engine/lib/wine/dxgi/dxmt"
  # shellcheck disable=SC2034 # (used in check's eval strings)
  logs="$d/root/home/Library/Logs/SWTOR on Mac"
  # (the driver first, with DirectX 12 off: Mullion not wanted yet, so its mark stays)
  fx_dx12_som dev set dx12 off
  fx_dx12_som dev set dx12driver mullion
  mkdir -p "$t/x86_64-windows" "$t/x86_64-unix"
  { sed -n 's/^MULLION_SHA256=//p' "$d/dev/som.sh"; echo "v0.5-alpha.3-1-g1111111, codegen airconv 103"; } >"$t/.mullion"
  fx_dx12_som dev set dx12 on
  fx_dx12_game "$win"
  check "dx12 mullion: the game as swtor_RC2.exe, Mullion's logs and flight record into the log folder, Metal 4 left to Mullion ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && [ "$(sed -n 1p "$FX_DX12_W/args")" = "C:\\swtor\\retailclient\\swtor_RC2.exe" ] && [ "$(fx_dx12_seen MULLION_LOG_PATH)/$(fx_dx12_seen MULLION_DIAG_PATH)/$(fx_dx12_seen MULLION_D3D12_METAL4)" = "$logs/$logs/<unset>" ]'
  check "dx12 mullion: Debug Logging on (a development build's default): the session header and STATS for the game, no Mullion options ($FX_RC)" \
    eval 'grep -qx debug=on "$FX_DX12_SOM/settings.conf" && [ "$(fx_dx12_seen MULLION_SESSION_HEADER)/$(fx_dx12_seen MULLION_STATS)/$(fx_dx12_seen MULLION_CONFIG)" = "1/1/<unset>" ] && ! grep -q MULLION_CONFIG "$FX_DX12_SOM/env"'
  check "dx12 mullion: wine.log names the driver, its tree, the switches set and the build (the pin, its VERSION from the mark)" \
    eval 'grep -qx "SWTOR on Mac DirectX 12: swtor_RC2.exe, driver mullion (dxgi=dxmt), MULLION_SESSION_HEADER=1, MULLION_STATS=1, $(sed -n "s/^MULLION_TITLE=//p" "$d/dev/som.sh" | tr -d \"), v0.5-alpha.3-1-g1111111, codegen airconv 103" "$logs/wine.log"'
  # the DirectX 12 Frame Rate Limit: Mullion's option in env's one MULLION_CONFIG line
  fx_dx12_som dev set dx12fps 45
  fx_dx12_game "$win"
  check "dx12 mullion: dx12fps 45: one MULLION_CONFIG line in env, the game gets it, wine.log names it ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && [ "$(grep -c "^MULLION_CONFIG=" "$FX_DX12_SOM/env")" = 1 ] && [ "$(fx_dx12_seen MULLION_CONFIG)" = "d3d12.preferredMaxFrameRate=45" ] && grep -q "^SWTOR on Mac DirectX 12: swtor_RC2.exe, driver mullion (dxgi=dxmt), MULLION_SESSION_HEADER=1, MULLION_STATS=1, MULLION_CONFIG=d3d12.preferredMaxFrameRate=45, Mullion " "$logs/wine.log"'
  rm -f "$FX_DX12_W/seen"
  "$FX_DX12_W/bin/wine64-preloader" "$FX_DX12_W/bin/wine64" 'C:\windows\system32\reg.exe' query 'HKCU\Software' >/dev/null 2>&1
  check "dx12 mullion: another Wine start gets none of the game's Mullion switches" \
    eval '[ "$(fx_dx12_seen MULLION_SESSION_HEADER)/$(fx_dx12_seen MULLION_STATS)/$(fx_dx12_seen MULLION_LOG_PATH)" = "<unset>/<unset>/<unset>" ]'
  fx_dx12_som release set dx12fps 60
  check "dx12 mullion: release build: set dx12fps refused, settings.conf unchanged ($FX_RC)" \
    eval '[ "$FX_RC" = 1 ] && grep -q "^@error DirectX 12 is in development builds only" "$FX_DX12_D/out.txt" && grep -qx dx12fps=45 "$FX_DX12_SOM/settings.conf"'
  fx_dx12_som dev set dx12fps off
  fx_dx12_game "$win"
  check "dx12 mullion: dx12fps off: no MULLION_CONFIG in env or for the game ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && ! grep -q MULLION_CONFIG "$FX_DX12_SOM/env" && [ "$(fx_dx12_seen MULLION_CONFIG)" = "<unset>" ]'
  # Debug Logging off: none of the fork's diagnostic switches
  fx_dx12_som dev set debug off
  fx_dx12_game "$win"
  check "dx12 mullion: Debug Logging off: no session header or STATS for the game, none named in wine.log ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && [ "$(fx_dx12_seen MULLION_SESSION_HEADER)/$(fx_dx12_seen MULLION_STATS)" = "<unset>/<unset>" ] && grep -q "^SWTOR on Mac DirectX 12: swtor_RC2.exe, driver mullion (dxgi=dxmt), Mullion " "$logs/wine.log"'
  fx_dx12_som dev set debug on
  fx_dx12_som dev set dx12driver mullion-mtl3
  fx_dx12_game "$win"
  check "dx12 mullion-mtl3: MULLION_D3D12_METAL4=0 for the game, named in wine.log, no D3DMetal switch ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && [ "$(fx_dx12_seen MULLION_D3D12_METAL4)/$(fx_dx12_seen D3DM_MTL4)" = "0/<unset>" ] && grep -q "^SWTOR on Mac DirectX 12: swtor_RC2.exe, driver mullion-mtl3 (dxgi=dxmt), MULLION_D3D12_METAL4=0, MULLION_SESSION_HEADER=1, MULLION_STATS=1, Mullion " "$logs/wine.log"'
  fx_dx12_som dev set dx12fps 30
  fx_dx12_som dev set dx12driver gptk
  fx_dx12_game "$win"
  check "dx12 mullion: back on D3DMetal: no Mullion switch or option (a frame rate limit set), the mark gone ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && [ "$(fx_dx12_seen MULLION_LOG_PATH)/$(fx_dx12_seen MULLION_D3D12_METAL4)/$(fx_dx12_seen MULLION_SESSION_HEADER)/$(fx_dx12_seen MULLION_STATS)/$(fx_dx12_seen MULLION_CONFIG)" = "<unset>/<unset>/<unset>/<unset>/<unset>" ] && ! grep -q MULLION_CONFIG "$FX_DX12_SOM/env" && [ ! -e "$t/.mullion" ]'
  fx_dx12_som dev set dx12fps off
  fx_dx12_som dev set dx12 off
}

# fx_dx12_mullion <app> <folder>
fx_dx12_mullion() {
  local app=$1 d=$2 r engine port server e f c1=1111111111111111111111111111111111111111 c2=2222222222222222222222222222222222222222 a
  FX_DXM_D=$d
  r="$app/Contents/Resources"
  FX_DXM_FILES=$(sed -n '/^MULLION_FILES="/,/"$/p' "$r/som.sh" | tr -d '"' | sed 's/^MULLION_FILES=//')
  engine=$(fx_dxm_cached "$(fx_dxm_val ENGINE_URL "$r/som.sh")" "$(fx_dxm_val ENGINE_SHA256 "$r/som.sh")") || true
  check "dx12-mullion: the pinned engine archive is at hand" test -n "$engine"
  [ -n "$engine" ] || return 0

  # a development build's Resources (the app's som.sh, channel=dev) and a planted install: the
  # manifest, the engine's mark, its real dxmt tree, a stand-in for d9mt's bridge in the main
  # tree, a prefix registry
  mkdir -p "$d/dev/Resources/d9mt" "$d/rel" "$d/orig" "$d/a"
  cp "$r/som.sh" "$r/dxvk.conf" "$d/dev/Resources/"
  cp "$r/d9mt/VERSION" "$d/dev/Resources/d9mt/"
  printf 'version=0.0.0-dev.1\nchannel=dev\n' >"$d/dev/Resources/app.properties"
  FX_DXM_SOM="$d/root/home/Library/Application Support/SWTOR on Mac"
  e="$FX_DXM_SOM/engine"
  FX_DXM_T="$e/lib/wine/dxgi/dxmt"
  mkdir -p "$e/lib/wine/x86_64-unix" "$FX_DXM_SOM/prefix"
  fx_dxm_val ENGINE_SHA256 "$r/som.sh" >"$e/.som-source"
  tar -xJf "$engine" -C "$d/orig" --strip-components 5 wine/lib/wine/dxgi/dxmt
  # (and its D3DMetal's Info.plist, which env names on a D3DMetal driver)
  tar -xJf "$engine" -C "$e" --strip-components 1 wine/lib/wine/dxgi/dxmt \
    wine/lib/external/D3DMetal.framework/Versions/A/Resources/Info.plist
  FX_DXM_ORIG="$d/orig"
  echo "d9mt's bridge (a stand-in)" >"$e/lib/wine/x86_64-unix/winemetal.so"
  cp "$e/lib/wine/x86_64-unix/winemetal.so" "$d/bridge"
  echo '{}' >"$FX_DXM_SOM/install-manifest.json"
  printf 'WINE REGISTRY Version 2\n' >"$FX_DXM_SOM/prefix/user.reg"
  # my fork's build of c1, pinned; its VERSION's codegen line with characters env can't hold
  # between quotes, which the install leaves out
  a="$d/a/mullion-swtor-$c1.tar.xz"
  fx_dxm_archive "$a" "$c1" 'airconv 103"$(x)`y`\'
  fx_dxm_pin "$a" "$c1"
  tar -xJf "$a" -C "$d/rel"
  mkdir -p "$d/failcp"
  printf '#!/bin/bash\ncase "$2" in */"$FX_FAIL".new.*) head -c 1000 "$1" >"$2"; exit 1 ;; esac\nexec %q "$@"\n' "$(command -v cp)" >"$d/failcp/cp"
  chmod 755 "$d/failcp/cp"
  FX_DXM_REL="$d/rel"
  check "dx12-mullion: the planted tree is the engine's own (its winemetal.so a link to the main tree's)" fx_dxm_stock

  port=$((19000 + $$ % 1000))
  python3 -I "$REPO/scripts/fetch-test-server.py" "$a" "$port" >"$d/server.log" 2>&1 &
  server=$!
  sleep 1
  FX_DXM_URL="http://127.0.0.1:$port/ok/${a##*/}"

  fx_dxm set dx12 on
  check "dx12-mullion: dx12 on (Mullion by default): downloaded and installed ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && grep -q "^Installing Mullion " "$d/out.txt" && fx_dxm_mullion'
  check "dx12-mullion: the engine's own files kept as .stock" fx_dxm_kept
  check "dx12-mullion: d9mt's bridge in the main tree untouched (the link was replaced, not written through)" \
    cmp -s "$d/bridge" "$e/lib/wine/x86_64-unix/winemetal.so"
  check "dx12-mullion: env: DirectX 12 with Mullion, rule dxgi=dxmt for swtor_RC2.exe, the build named by its VERSION ($(fx_dxm_env SWTOR_DX12_DRIVER_VERSION))" \
    eval '[ "$(fx_dxm_env SWTOR_DX12)/$(fx_dxm_env SWTOR_DX12_DRIVER)" = 1/mullion ] && fx_dxm_env WINE_COMPATDB | piped -x "name=swtor-dx12;exe=swtor_RC2.exe;dxgi=dxmt" && [ "$(fx_dxm_env SWTOR_DX12_DRIVER_VERSION)" = "Mullion (jdrly/mullion 1111111), v0.5-alpha.3-1-g1111111, codegen airconv 103xy" ]'

  fx_dxm set dx12driver mullion-mtl3
  check "dx12-mullion: mullion-mtl3: the tree as it was, nothing downloaded ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && ! grep -q -e Downloading -e "^Installing Mullion " "$d/out.txt" && fx_dxm_mullion && [ "$(fx_dxm_env SWTOR_DX12_DRIVER)" = mullion-mtl3 ]'

  fx_dxm set dx12driver gptk
  check "dx12-mullion: gptk: the engine's own tree back ($FX_RC)" eval '[ "$FX_RC" = 0 ] && fx_dxm_stock'
  check "dx12-mullion: gptk: d9mt's bridge still untouched" cmp -s "$d/bridge" "$e/lib/wine/x86_64-unix/winemetal.so"
  # (the engine's real D3DMetal.framework Info.plist, planted above: 4.0b2)
  check "dx12-mullion: gptk: rule dxgi=gptk, the engine's D3DMetal named, not Mullion's build" \
    eval 'fx_dxm_env WINE_COMPATDB | piped -x "name=swtor-dx12;exe=swtor_RC2.exe;dxgi=gptk" && [ "$(fx_dxm_env SWTOR_DX12_DRIVER_VERSION)" = "D3DMetal 4.0b2 (the engine'"'"'s)" ]'

  FX_DXM_URL="http://127.0.0.1:$port/html/${a##*/}"
  fx_dxm set dx12driver mullion
  check "dx12-mullion: back to mullion: the archive kept in the cache is used, not downloaded ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && grep -q "using the verified download in the cache" "$d/out.txt" && fx_dxm_mullion'

  # a restore that stops halfway (a copy fails): refused, and env no longer starts the game on
  # Mullion, whose tree is now mixed
  FX_DXM_CP_FAIL=d3d11.dll fx_dxm set dx12 off
  check "dx12-mullion: dx12 off, a copy fails halfway: refused, the mark gone, env starts no DirectX 12 on the mixed tree ($FX_RC)" \
    eval '[ "$FX_RC" != 0 ] && [ ! -e "$FX_DXM_T/.mullion" ] && [ "$(fx_dxm_env SWTOR_DX12)" = "<unset>" ] && ! grep -q swtor-dx12 "$FX_DXM_SOM/env" && grep -qx dx12=on "$FX_DXM_SOM/settings.conf"'
  fx_dxm set dx12 off
  check "dx12-mullion: dx12 off: the engine's own tree back, byte for byte, no DirectX 12 in env ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && fx_dxm_stock && [ "$(fx_dxm_env SWTOR_DX12)" = "<unset>" ] && ! grep -q swtor-dx12 "$FX_DXM_SOM/env"'

  # an install that stops halfway (a copy fails): refused, no mark, no part of a file in place
  FX_DXM_CP_FAIL=d3d11.dll fx_dxm set dx12 on
  check "dx12-mullion: dx12 on, a copy fails halfway: refused, no mark, the engine's d3d11.dll, no DirectX 12 in env ($FX_RC)" \
    eval '[ "$FX_RC" != 0 ] && [ ! -e "$FX_DXM_T/.mullion" ] && cmp -s "$FX_DXM_ORIG/x86_64-windows/d3d11.dll" "$FX_DXM_T/x86_64-windows/d3d11.dll" && [ "$(fx_dxm_env SWTOR_DX12)" = "<unset>" ] && grep -qx dx12=off "$FX_DXM_SOM/settings.conf"'
  fx_dxm set dx12 off
  check "dx12-mullion: dx12 off again: the half-installed tree is the engine's own ($FX_RC)" eval '[ "$FX_RC" = 0 ] && fx_dxm_stock'

  # an update from the build that pinned Mullion v0.5-alpha.3: the tree has that release, with
  # the NVIDIA shims my fork doesn't build. Off puts the engine's own back; on installs my fork's
  # build over it, the shims gone
  fx_dxm_upstream
  fx_dxm set dx12 off
  check "dx12-mullion: over v0.5-alpha.3, dx12 off: the engine's own tree back, its NVIDIA shims gone ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && fx_dxm_stock'
  fx_dxm_upstream
  sed -i.bak 's/^dx12=off$/dx12=on/; s/^dx12driver=.*/dx12driver=mullion/' "$FX_DXM_SOM/settings.conf"
  fx_dxm set dx12driver mullion-mtl3
  check "dx12-mullion: over v0.5-alpha.3, a Mullion driver: my fork's build installed, the NVIDIA shims gone, the engine's .stock kept ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && grep -q "^Installing Mullion " "$d/out.txt" && fx_dxm_mullion && fx_dxm_kept && [ "$(fx_dxm_env SWTOR_DX12)" = 1 ]'
  fx_dxm set dx12 off
  check "dx12-mullion: and off from there: the engine's own tree ($FX_RC)" eval '[ "$FX_RC" = 0 ] && fx_dxm_stock'

  # a build of another commit, at the pinned hash (in the cache, as one put there by hand):
  # refused by its VERSION, nothing changed
  fx_dxm_archive "$d/a/other.tar.xz" "$c2"
  cp "$d/a/other.tar.xz" "$d/root/home/Library/Caches/SWTOR on Mac/downloads/${a##*/}"
  fx_dxm_pin "$d/a/other.tar.xz" "$c1"
  fx_dxm set dx12 on
  check "dx12-mullion: an archive whose VERSION names another commit: refused with the reason, the setting stays off, the tree the engine's own ($FX_RC)" \
    eval '[ "$FX_RC" != 0 ] && grep -q "^@error Mullion (jdrly/mullion 1111111).s archive is a build of another commit ($c2)" "$d/out.txt" && grep -qx dx12=off "$FX_DXM_SOM/settings.conf" && fx_dxm_stock && [ "$(fx_dxm_env SWTOR_DX12)" = "<unset>" ]'
  fx_dxm_pin "$a" "$c1"

  # a download that isn't the build: refused, nothing changed, and the game starts as before
  rm -rf "$d/root/home/Library/Caches/SWTOR on Mac/downloads"
  FX_DXM_URL="http://127.0.0.1:$port/changed/${a##*/}"
  fx_dxm set dx12 on
  check "dx12-mullion: a changed download: refused with the reason, the setting stays off, the tree the engine's own ($FX_RC)" \
    eval '[ "$FX_RC" != 0 ] && grep -q "^@error The download of Mullion .* is not the expected file" "$d/out.txt" && grep -qx dx12=off "$FX_DXM_SOM/settings.conf" && fx_dxm_stock && [ "$(fx_dxm_env SWTOR_DX12)" = "<unset>" ]'

  # a tree that isn't the engine's own (no .stock yet, d3d11.dll another file): refused, untouched
  rm -f "$FX_DXM_T"/x86_64-windows/*.stock
  echo changed >>"$FX_DXM_T/x86_64-windows/d3d11.dll"
  cp "$FX_DXM_T/x86_64-windows/d3d11.dll" "$d/d3d11.changed"
  FX_DXM_URL="http://127.0.0.1:$port/ok/${a##*/}"
  fx_dxm set dx12 on
  check "dx12-mullion: another engine's tree: refused, nothing kept as .stock or installed ($FX_RC)" \
    eval '[ "$FX_RC" != 0 ] && grep -q "^@error The Wine engine.s DXMT tree (x86_64-windows/d3d11.dll) is not the expected build" "$d/out.txt" && cmp -s "$d/d3d11.changed" "$FX_DXM_T/x86_64-windows/d3d11.dll" && [ ! -e "$FX_DXM_T/x86_64-windows/d3d11.dll.stock" ] && [ ! -e "$FX_DXM_T/x86_64-windows/d3d12.dll" ] && grep -qx dx12=off "$FX_DXM_SOM/settings.conf"'
  cp "$FX_DXM_ORIG/x86_64-windows/d3d11.dll" "$FX_DXM_T/x86_64-windows/d3d11.dll"

  # DirectX 12 on with Mullion in settings.conf, but the tree without it (a failed download at
  # Reinstall): env leaves DirectX 12 out and says why
  sed -i.bak 's/^dx12=off$/dx12=on/; s/^dx12driver=.*/dx12driver=mullion/' "$FX_DXM_SOM/settings.conf"
  fx_dxm set hud on
  check "dx12-mullion: Mullion not in place: no DirectX 12 rule or start in env, a line says why ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && [ "$(fx_dxm_env SWTOR_DX12)" = "<unset>" ] && ! grep -q swtor-dx12 "$FX_DXM_SOM/env" && grep -q "^# DirectX 12 is on in Settings, but driver mullion is not ready" "$FX_DXM_SOM/env"'
  kill "$server" 2>/dev/null || true
  wait "$server" 2>/dev/null || true
}
