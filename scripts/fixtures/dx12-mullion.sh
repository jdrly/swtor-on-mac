# shellcheck shell=bash
# DirectX 12 on Mullion (development builds): som.sh's install_mullion on a planted install, in
# a sandbox root of its own, without the app's window, Wine or a game start. The engine's dxmt
# tree is the real one, unpacked from the pinned engine archive, and Mullion's archive is the
# pinned release, served by scripts/fetch-test-server.py (SWTOR_ON_MAC_MULLION_URL); both are
# downloaded once into the repository's .cache/<sha256>/, as scripts/test-sandbox.sh keeps the
# engine. Fixture group dx12-mullion (scripts/test-fixtures.sh), and scripts/test-sandbox.sh's
# section 17b. Sourced; check and its counters come from lib.sh.

# fx_dxm_cached <url> <sha256>: the path of the verified download in $REPO/.cache
fx_dxm_cached() {
  local f="$REPO/.cache/$2/${1##*/}"
  if [ ! -f "$f" ]; then mkdir -p "${f%/*}"; curl -fsSL -o "$f.part" "$1" && mv "$f.part" "$f"; fi
  [ "$(shasum -a 256 "$f" | cut -d' ' -f1)" = "$2" ] && echo "$f"
}
fx_dxm_val() { sed -n "/^$1=/{s/^$1=//p;q;}" "$2"; }
# fx_dxm [som.sh's arguments]: the development build's som.sh in the planted sandbox; FX_RC its
# exit status, $FX_DXM_D/out.txt what it printed
fx_dxm() {
  FX_RC=0
  SWTOR_ON_MAC_ROOT="$FX_DXM_D/root" SWTOR_ON_MAC_MULLION_URL="${FX_DXM_URL:-}" \
    "$FX_DXM_D/dev/Resources/som.sh" "$@" >"$FX_DXM_D/out.txt" 2>&1 || FX_RC=$?
}
# fx_dxm_env <variable>: its value in the planted env, or <unset>
fx_dxm_env() { ( set -a; . "$FX_DXM_SOM/env"; set +a; eval "printf '%s' \"\${$1-<unset>}\"" ); }
# fx_dxm_stock: the tree is the engine's own: its files as unpacked, Mullion's extra ones gone,
# the link to the main tree's winemetal.so back, no mark
fx_dxm_stock() {
  local f
  for f in d3d10.dll d3d10_1.dll d3d10core.dll d3d11.dll dxgi.dll winemetal.dll; do
    cmp -s "$FX_DXM_ORIG/x86_64-windows/$f" "$FX_DXM_T/x86_64-windows/$f" || return 1
  done
  for f in d3d12.dll d3d12core.dll nvapi64.dll nvngx.dll; do [ ! -e "$FX_DXM_T/x86_64-windows/$f" ] || return 1; done
  [ "$(readlink "$FX_DXM_T/x86_64-unix/winemetal.so")" = ../../../x86_64-unix/winemetal.so ] && [ ! -e "$FX_DXM_T/.mullion" ]
}
# fx_dxm_mullion: the tree has Mullion's files, the release's own winemetal.so in place of the
# link, the mark
fx_dxm_mullion() {
  local f
  for f in $FX_DXM_FILES; do cmp -s "$FX_DXM_REL/$f" "$FX_DXM_T/$f" || return 1; done
  [ ! -L "$FX_DXM_T/x86_64-unix/winemetal.so" ] && [ "$(cat "$FX_DXM_T/.mullion")" = "$FX_DXM_SHA" ]
}

# fx_dxm_kept: the engine's own files Mullion replaces are kept next to them as .stock
fx_dxm_kept() {
  local f
  for f in d3d10core.dll d3d11.dll dxgi.dll winemetal.dll; do
    cmp -s "$FX_DXM_ORIG/x86_64-windows/$f" "$FX_DXM_T/x86_64-windows/$f.stock" || return 1
  done
}

# fx_dx12_mullion <app> <folder>
fx_dx12_mullion() {
  local app=$1 d=$2 r engine mullion port server e f
  FX_DXM_D=$d
  r="$app/Contents/Resources"
  FX_DXM_SHA=$(fx_dxm_val MULLION_SHA256 "$r/som.sh")
  FX_DXM_FILES=$(sed -n '/^MULLION_FILES="/,/"$/p' "$r/som.sh" | tr -d '"' | sed 's/^MULLION_FILES=//')
  engine=$(fx_dxm_cached "$(fx_dxm_val ENGINE_URL "$r/som.sh")" "$(fx_dxm_val ENGINE_SHA256 "$r/som.sh")") || true
  mullion=$(fx_dxm_cached "$(fx_dxm_val MULLION_URL "$r/som.sh")" "$FX_DXM_SHA") || true
  check "dx12-mullion: the pinned engine and Mullion archives are at hand" test -n "$engine" -a -n "$mullion"
  [ -n "$engine" ] && [ -n "$mullion" ] || return 0

  # a development build's Resources (the app's som.sh, channel=dev) and a planted install: the
  # manifest, the engine's mark, its real dxmt tree, a stand-in for d9mt's bridge in the main
  # tree, a prefix registry
  mkdir -p "$d/dev/Resources/d9mt" "$d/rel" "$d/orig"
  cp "$r/som.sh" "$r/dxvk.conf" "$d/dev/Resources/"
  cp "$r/d9mt/VERSION" "$d/dev/Resources/d9mt/"
  printf 'version=0.0.0-dev.1\nchannel=dev\n' >"$d/dev/Resources/app.properties"
  FX_DXM_SOM="$d/root/home/Library/Application Support/SWTOR on Mac"
  e="$FX_DXM_SOM/engine"
  FX_DXM_T="$e/lib/wine/dxgi/dxmt"
  mkdir -p "$e/lib/wine/x86_64-unix" "$FX_DXM_SOM/prefix"
  fx_dxm_val ENGINE_SHA256 "$r/som.sh" >"$e/.som-source"
  tar -xJf "$engine" -C "$d/orig" --strip-components 5 wine/lib/wine/dxgi/dxmt
  tar -xJf "$engine" -C "$e/lib/wine" --strip-components 3 wine/lib/wine/dxgi/dxmt
  FX_DXM_ORIG="$d/orig"
  echo "d9mt's bridge (a stand-in)" >"$e/lib/wine/x86_64-unix/winemetal.so"
  cp "$e/lib/wine/x86_64-unix/winemetal.so" "$d/bridge"
  echo '{}' >"$FX_DXM_SOM/install-manifest.json"
  printf 'WINE REGISTRY Version 2\n' >"$FX_DXM_SOM/prefix/user.reg"
  tar -xzf "$mullion" -C "$d/rel" --strip-components 1
  FX_DXM_REL="$d/rel"
  check "dx12-mullion: the planted tree is the engine's own (its winemetal.so a link to the main tree's)" fx_dxm_stock

  port=$((19000 + $$ % 1000))
  python3 -I "$REPO/scripts/fetch-test-server.py" "$mullion" "$port" >"$d/server.log" 2>&1 &
  server=$!
  sleep 1
  FX_DXM_URL="http://127.0.0.1:$port/ok/${mullion##*/}"

  fx_dxm set dx12 on
  check "dx12-mullion: dx12 on (Mullion by default): downloaded and installed ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && grep -q "^Installing Mullion " "$d/out.txt" && fx_dxm_mullion'
  check "dx12-mullion: the engine's own files kept as .stock" fx_dxm_kept
  check "dx12-mullion: d9mt's bridge in the main tree untouched (the link was replaced, not written through)" \
    cmp -s "$d/bridge" "$e/lib/wine/x86_64-unix/winemetal.so"
  check "dx12-mullion: env: DirectX 12 with Mullion, rule dxgi=dxmt for swtor_RC2.exe, the release named" \
    eval '[ "$(fx_dxm_env SWTOR_DX12)/$(fx_dxm_env SWTOR_DX12_DRIVER)" = 1/mullion ] && fx_dxm_env WINE_COMPATDB | piped -x "name=swtor-dx12;exe=swtor_RC2.exe;dxgi=dxmt" && [ "$(fx_dxm_env SWTOR_DX12_DRIVER_VERSION)" = "$(fx_dxm_val MULLION_TITLE "$r/som.sh" | tr -d \")" ]'

  fx_dxm set dx12driver mullion-mtl3
  check "dx12-mullion: mullion-mtl3: the tree as it was, nothing downloaded ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && ! grep -q -e Downloading -e "^Installing Mullion " "$d/out.txt" && fx_dxm_mullion && [ "$(fx_dxm_env SWTOR_DX12_DRIVER)" = mullion-mtl3 ]'

  fx_dxm set dx12driver gptk
  check "dx12-mullion: gptk: the engine's own tree back ($FX_RC)" eval '[ "$FX_RC" = 0 ] && fx_dxm_stock'
  check "dx12-mullion: gptk: d9mt's bridge still untouched" cmp -s "$d/bridge" "$e/lib/wine/x86_64-unix/winemetal.so"
  check "dx12-mullion: gptk: rule dxgi=gptk, no Mullion release named" \
    eval 'fx_dxm_env WINE_COMPATDB | piped -x "name=swtor-dx12;exe=swtor_RC2.exe;dxgi=gptk" && [ "$(fx_dxm_env SWTOR_DX12_DRIVER_VERSION)" = "<unset>" ]'

  FX_DXM_URL="http://127.0.0.1:$port/html/${mullion##*/}"
  fx_dxm set dx12driver mullion
  check "dx12-mullion: back to mullion: the archive kept in the cache is used, not downloaded ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && grep -q "using the verified download in the cache" "$d/out.txt" && fx_dxm_mullion'

  fx_dxm set dx12 off
  check "dx12-mullion: dx12 off: the engine's own tree back, no DirectX 12 in env ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && fx_dxm_stock && [ "$(fx_dxm_env SWTOR_DX12)" = "<unset>" ] && ! grep -q swtor-dx12 "$FX_DXM_SOM/env"'

  # a download that isn't the release: refused, nothing changed, and the game starts as before
  rm -rf "$d/root/home/Library/Caches/SWTOR on Mac/downloads"
  FX_DXM_URL="http://127.0.0.1:$port/changed/${mullion##*/}"
  fx_dxm set dx12 on
  check "dx12-mullion: a changed download: refused with the reason, the setting stays off, the tree the engine's own ($FX_RC)" \
    eval '[ "$FX_RC" != 0 ] && grep -q "^@error The download of Mullion .* is not the expected file" "$d/out.txt" && grep -qx dx12=off "$FX_DXM_SOM/settings.conf" && fx_dxm_stock && [ "$(fx_dxm_env SWTOR_DX12)" = "<unset>" ]'

  # a tree that isn't the engine's own (no .stock yet, d3d11.dll another file): refused, untouched
  rm -f "$FX_DXM_T"/x86_64-windows/*.stock
  echo changed >>"$FX_DXM_T/x86_64-windows/d3d11.dll"
  cp "$FX_DXM_T/x86_64-windows/d3d11.dll" "$d/d3d11.changed"
  FX_DXM_URL="http://127.0.0.1:$port/ok/${mullion##*/}"
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
