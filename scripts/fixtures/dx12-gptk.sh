# shellcheck shell=bash
# D3DMetal from a Game Porting Toolkit image (som.sh dx12-gptk, development builds) on a planted
# install: the engine's gptk tree and lib/external as the engine has them (made-up files), and
# made-up Game Porting Toolkit images in the layout of Apple's 4.0 beta 3 (an outer image with
# "Evaluation environment for Windows games 4.0 beta 3.dmg" in it, which holds redist/lib). The
# images are real disk images (hdiutil). The made-up files aren't Apple's: codesign is a
# stand-in that says yes, or no, and notes what it was asked, and the shims' sha256 list is the
# made-up ones' (SWTOR_ON_MAC_GPTK_SHIMS), except where a check says otherwise. No Wine, no app. Fixture group
# dx12-gptk (scripts/test-fixtures.sh), also scripts/test-sandbox.sh's section 17c. Sourced;
# check and its counters come from lib.sh.

# fx_gptk_res <dev|release>: a copy of the app's som.sh with that channel in app.properties
fx_gptk_res() {
  mkdir -p "$FX_G_D/res-$1"
  cp "$FX_G_APP/Contents/Resources/som.sh" "$FX_G_D/res-$1/som.sh"
  printf 'version=0.0.0%s\nchannel=%s\n' "$([ "$1" = dev ] && echo -dev.1)" "$1" >"$FX_G_D/res-$1/app.properties"
}
# fx_gptk <dev|release> [som.sh's arguments]: som.sh dx12-gptk in the planted sandbox, with the
# shims' sha256 list in $FX_G_SHIMS; FX_RC its exit status, $FX_G_D/out.txt what it printed
fx_gptk() {
  local ch=$1; shift
  FX_RC=0
  PATH="$FX_G_D/bin:$PATH" SWTOR_ON_MAC_ROOT="$FX_G_D/root" SWTOR_ON_MAC_GPTK_SHIMS="$FX_G_SHIMS" \
    "$FX_G_D/res-$ch/som.sh" dx12-gptk "$@" </dev/null >"$FX_G_D/out.txt" 2>&1 || FX_RC=$?
}
# fx_gptk_env <variable>: its value as the wrapper gets it from the planted env, or <unset>
fx_gptk_env() { ( set -a; . "$FX_G_D/root/home/Library/Application Support/SWTOR on Mac/env"; set +a; eval "printf '%s' \"\${$1-<unset>}\"" ); }
# fx_gptk_plist <file> <version>: a framework's Info.plist
fx_gptk_plist() {
  mkdir -p "$(dirname "$1")"
  cat >"$1" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key><string>com.apple.D3DMetal</string>
	<key>CFBundleShortVersionString</key><string>$2</string>
</dict>
</plist>
EOF
}
# fx_gptk_framework <external folder> <whose> <version>: a made-up D3DMetal.framework and
# libd3dshared.dylib
fx_gptk_framework() {
  local fw="$1/D3DMetal.framework"
  mkdir -p "$fw/Versions/A/Resources"
  echo "$2 D3DMetal" >"$fw/Versions/A/D3DMetal"
  ln -s A "$fw/Versions/Current"
  ln -s Versions/Current/D3DMetal "$fw/D3DMetal"
  ln -s Versions/Current/Resources "$fw/Resources"
  fx_gptk_plist "$fw/Versions/A/Resources/Info.plist" "$3"
  echo "$2 libd3dshared" >"$1/libd3dshared.dylib"
}
# fx_gptk_eval <folder> [shims]: a made-up evaluation environment in <folder> (its shims: beta
# 3's unless named)
fx_gptk_eval() {
  local s="$1/redist/lib" n
  mkdir -p "$s/external" "$s/wine/x86_64-windows" "$s/wine/x86_64-unix"
  fx_gptk_framework "$s/external" gptk 4.0b3
  for n in ${2:-d3d10 d3d11 d3d12 d3d12core dxgi nvapi64 nvngx-on-metalfx}; do
    printf 'MZ gptk %s\n' "$n" >"$s/wine/x86_64-windows/$n.dll"
    ln -s ../../external/libd3dshared.dylib "$s/wine/x86_64-unix/$n.so"
  done
  echo license >"$1/License.rtf"
}
fx_gptk_dmg() { # <source folder> <volume name> <image>
  hdiutil create -quiet -fs HFS+ -format UDZO -volname "$2" -srcfolder "$1" "$3"
}

# fx_gptk_state: what the engine's D3DMetal looks like now, one line a file (content or link)
fx_gptk_state() {
  local e="$FX_G_ENG/lib" f
  for f in "$e"/wine/dxgi/gptk/*/* "$e"/external/libd3dshared.dylib "$e"/external/D3DMetal.framework/Versions/A/* \
           "$e"/external/gptk-import "$e"/external/gptk-import.new "$e"/external/gptk-import/* "$e"/external/gptk-import/D3DMetal.framework/Versions/A/*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    if [ -L "$f" ]; then echo "${f#"$e"/} -> $(readlink "$f")"
    elif [ -f "$f" ]; then echo "${f#"$e"/}: $(head -1 "$f")"
    else echo "${f#"$e"/}/"; fi
  done
}

# fx_dx12_gptk <app> <folder>
fx_dx12_gptk() {
  local d=$2 n stock imgs
  FX_G_APP=$1 FX_G_D=$2
  local som="$d/root/home/Library/Application Support/SWTOR on Mac"
  FX_G_ENG="$som/engine"
  local t="$FX_G_ENG/lib/wine/dxgi/gptk"
  mkdir -p "$d/bin" "$t/x86_64-windows" "$t/x86_64-unix" "$FX_G_ENG/lib/external"
  fx_gptk_res dev
  fx_gptk_res release
  # the planted install: a manifest, this version's engine, its D3DMetal (4.0b2's shims and
  # CrossOver's d3d10_1 and d3d10core)
  echo '{}' >"$som/install-manifest.json"
  sed -n 's/^ENGINE_SHA256=//p' "$d/res-dev/som.sh" >"$FX_G_ENG/.som-source"
  for n in d3d10 d3d10_1 d3d10core d3d11 d3d12 dxgi nvapi64 nvngx; do printf 'MZ engine %s\n' "$n" >"$t/x86_64-windows/$n.dll"; done
  for n in d3d10 d3d11 d3d12 dxgi nvapi64 nvngx; do ln -s ../../../../external/libd3dshared.dylib "$t/x86_64-unix/$n.so"; done
  fx_gptk_framework "$FX_G_ENG/lib/external" engine 4.0b2
  # shellcheck disable=SC2034 # (the checks' eval strings read it)
  stock=$(fx_gptk_state)
  # codesign: yes unless $d/unsigned exists; every call noted in $d/codesign.txt
  printf '#!/bin/bash\necho "$*" >>%q\n[ ! -e %q ]\n' "$d/codesign.txt" "$d/unsigned" >"$d/bin/codesign"
  chmod 755 "$d/bin/codesign"

  # the images: the download as Apple names it (here with a browser's " (1)"), and wrong ones
  imgs="$d/images"
  mkdir -p "$imgs/eval" "$imgs/outer" "$imgs/extra" "$imgs/outer-extra" "$imgs/plain"
  fx_gptk_eval "$imgs/eval"
  fx_gptk_dmg "$imgs/eval" "Evaluation environment for Windows games 4.0 beta 3" \
    "$imgs/outer/Evaluation environment for Windows games 4.0 beta 3.dmg"
  echo readme >"$imgs/outer/Read Me.pdf"
  fx_gptk_dmg "$imgs/outer" "Game Porting Toolkit 4.0 beta 3" "$imgs/Game_Porting_Toolkit_4.0_beta_3 (1).dmg"
  FX_G_SHIMS=$(for n in d3d10 d3d11 d3d12 d3d12core dxgi nvapi64 nvngx-on-metalfx; do
    echo "$n:$(shasum -a 256 "$imgs/eval/redist/lib/wine/x86_64-windows/$n.dll" | cut -d' ' -f1)"; done)
  # a shim beta 3 doesn't have (3.0's atidxx64)
  fx_gptk_eval "$imgs/extra" "atidxx64 d3d10 d3d11 d3d12 d3d12core dxgi nvapi64 nvngx-on-metalfx"
  fx_gptk_dmg "$imgs/extra" "Evaluation environment for Windows games 9.9" \
    "$imgs/outer-extra/Evaluation environment for Windows games 9.9.dmg"
  fx_gptk_dmg "$imgs/outer-extra" "Game Porting Toolkit 9.9" "$imgs/extra.dmg"
  # no evaluation environment in it
  echo readme >"$imgs/plain/Read Me.pdf"
  fx_gptk_dmg "$imgs/plain" "Something else" "$imgs/plain.dmg"
  local good="$imgs/Game_Porting_Toolkit_4.0_beta_3 (1).dmg"

  fx_gptk release "$good"
  check "dx12-gptk: a release build refuses, and the engine's D3DMetal stays ($FX_RC)" \
    eval '[ "$FX_RC" != 0 ] && grep -q "development builds" "$d/out.txt" && [ "$(fx_gptk_state)" = "$stock" ]'
  fx_gptk dev "$imgs/plain.dmg"
  check "dx12-gptk: an image without the evaluation environment is refused, nothing changes ($FX_RC)" \
    eval '[ "$FX_RC" != 0 ] && grep -q "no single \"Evaluation environment for Windows games\" image" "$d/out.txt" && [ "$(fx_gptk_state)" = "$stock" ]'
  fx_gptk dev "$imgs/extra.dmg"
  check "dx12-gptk: a shim beta 3 doesn't have is refused and named, nothing changes ($FX_RC)" \
    eval '[ "$FX_RC" != 0 ] && grep -q "x86_64-windows has atidxx64 " "$d/out.txt" && [ "$(fx_gptk_state)" = "$stock" ]'
  local shims=$FX_G_SHIMS
  FX_G_SHIMS=$(printf '%s\n' "$shims" | sed 's/^dxgi:.*/dxgi:0000/')
  fx_gptk dev "$good"
  check "dx12-gptk: a shim of another build (its sha256) is refused and named, nothing changes ($FX_RC)" \
    eval '[ "$FX_RC" != 0 ] && grep -q "dxgi.dll is not beta 3'"'"'s build" "$d/out.txt" && [ "$(fx_gptk_state)" = "$stock" ]'
  FX_G_SHIMS=""
  fx_gptk dev "$good"
  check "dx12-gptk: by default the shims must be Apple's beta 3 (the made-up ones are refused), nothing changes ($FX_RC)" \
    eval '[ "$FX_RC" != 0 ] && grep -q "d3d10.dll is not beta 3'"'"'s build" "$d/out.txt" && [ "$(fx_gptk_state)" = "$stock" ]'
  FX_G_SHIMS=$shims
  touch "$d/unsigned"
  fx_gptk dev "$good"
  rm -f "$d/unsigned"
  check "dx12-gptk: D3DMetal not signed by Apple is refused, nothing changes ($FX_RC)" \
    eval '[ "$FX_RC" != 0 ] && grep -q "not signed by Apple" "$d/out.txt" && [ "$(fx_gptk_state)" = "$stock" ]'
  # macOS's own codesign: the made-up files aren't Apple's
  FX_RC=0
  SWTOR_ON_MAC_ROOT="$d/root" SWTOR_ON_MAC_GPTK_SHIMS="$FX_G_SHIMS" "$d/res-dev/som.sh" dx12-gptk "$good" </dev/null >"$d/out.txt" 2>&1 || FX_RC=$?
  check "dx12-gptk: macOS's codesign refuses the made-up files, nothing changes ($FX_RC)" \
    eval '[ "$FX_RC" != 0 ] && grep -q "not signed by Apple" "$d/out.txt" && [ "$(fx_gptk_state)" = "$stock" ]'
  fx_gptk dev "$imgs/plain/Read Me.pdf"
  check "dx12-gptk: a file that is no disk image is refused, nothing changes ($FX_RC)" \
    eval '[ "$FX_RC" != 0 ] && grep -q "Could not open Read Me.pdf" "$d/out.txt" && [ "$(fx_gptk_state)" = "$stock" ]'
  check "dx12-gptk: the refused images are detached again, no mount folder left" \
    eval '! hdiutil info | piped -e "/som-gptk\." && ! ls -d "${TMPDIR:-/tmp}"/som-gptk.* >/dev/null 2>&1'

  rm -f "$d/codesign.txt"
  # (DirectX 12 on, D3DMetal its driver: the import rewrites env for the wrapper)
  printf 'dx12=on\ndx12driver=gptk\n' >"$som/settings.conf"
  fx_gptk dev "$good"
  check "dx12-gptk: beta 3's image, by a path with spaces and parentheses: imported, version and image named ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && grep -qx "@done D3DMetal 4.0b3 (Evaluation environment for Windows games 4.0 beta 3) is in the engine for the DirectX 12 client. Reinstall puts the engine'"'"'s own back." "$d/out.txt"'
  check "dx12-gptk: Apple's shims in the gptk tree, nvngx-on-metalfx as nvngx, d3d12core added, CrossOver's d3d10_1 and d3d10core kept" \
    eval '[ "$(head -1 "$t/x86_64-windows/d3d12.dll")/$(head -1 "$t/x86_64-windows/nvngx.dll")/$(head -1 "$t/x86_64-windows/d3d12core.dll")/$(head -1 "$t/x86_64-windows/d3d10_1.dll")/$(head -1 "$t/x86_64-windows/d3d10core.dll")" = "MZ gptk d3d12/MZ gptk nvngx-on-metalfx/MZ gptk d3d12core/MZ engine d3d10_1/MZ engine d3d10core" ] && [ ! -e "$t/x86_64-windows/nvngx-on-metalfx.dll" ]'
  check "dx12-gptk: the tree's own shims kept as .stock (six), none for the added d3d12core" \
    eval '[ "$(ls "$t/x86_64-windows" | grep -c "\.stock$")" = 6 ] && [ "$(head -1 "$t/x86_64-windows/d3d12.dll.stock")" = "MZ engine d3d12" ] && [ ! -e "$t/x86_64-windows/d3d12core.dll.stock" ]'
  check "dx12-gptk: every unix link of the tree (seven) points at the imported libd3dshared" \
    eval '[ "$(for n in d3d10 d3d11 d3d12 d3d12core dxgi nvapi64 nvngx; do readlink "$t/x86_64-unix/$n.so"; done | sort -u)" = ../../../../external/gptk-import/libd3dshared.dylib ] && [ "$(ls "$t/x86_64-unix" | wc -l | tr -d " ")" = 7 ] && [ "$(head -1 "$t/x86_64-unix/d3d12core.so")" = "gptk libd3dshared" ]'
  check "dx12-gptk: lib/external's libd3dshared and D3DMetal.framework stay the engine's (every Wine process loads them)" \
    eval '[ "$(head -1 "$FX_G_ENG/lib/external/libd3dshared.dylib")/$(head -1 "$FX_G_ENG/lib/external/D3DMetal.framework/Versions/A/D3DMetal")" = "engine libd3dshared/engine D3DMetal" ]'
  check "dx12-gptk: the imported pair in gptk-import, the framework's links kept, and the record" \
    eval '[ "$(head -1 "$FX_G_ENG/lib/external/gptk-import/D3DMetal.framework/D3DMetal")" = "gptk D3DMetal" ] && [ -L "$FX_G_ENG/lib/external/gptk-import/D3DMetal.framework/Versions/Current" ] && [ "$(cat "$FX_G_ENG/lib/external/gptk-import/IMPORTED")" = "$(printf "version=4.0b3\nimage=Evaluation environment for Windows games 4.0 beta 3\nadded=d3d12core")" ]'
  check "dx12-gptk: env names the imported D3DMetal for wine.log, and its libd3dshared for the game's ntdll" \
    eval '[ "$(fx_gptk_env SWTOR_DX12_DRIVER_VERSION)" = "D3DMetal 4.0b3 (imported: Evaluation environment for Windows games 4.0 beta 3)" ] && [ "$(fx_gptk_env SWTOR_DX12_LIBD3DSHARED)" = "$FX_G_ENG/lib/external/gptk-import/libd3dshared.dylib" ]'
  check "dx12-gptk: codesign asked for Apple's anchor, the framework deep" \
    eval 'piped -x -e "--verify --strict -R =anchor apple .*/redist/lib/external/libd3dshared.dylib" "$d/codesign.txt" && piped -x -e "--verify --strict --deep -R =anchor apple .*/redist/lib/external/D3DMetal.framework" "$d/codesign.txt" && piped -x -e "--verify --strict --deep -R =anchor apple .*/gptk-import.new/D3DMetal.framework" "$d/codesign.txt"'
  check "dx12-gptk: both images detached, the mount folder gone" \
    eval '! hdiutil info | piped -e "/som-gptk\." && ! ls -d "${TMPDIR:-/tmp}"/som-gptk.* >/dev/null 2>&1'
  check "dx12-gptk: install.log names the image, not its folder" \
    eval 'piped -x -e ".* ---- dx12-gptk Game_Porting_Toolkit_4.0_beta_3 (1).dmg" "$som/../../Logs/SWTOR on Mac/install.log" && ! piped -F "$imgs" "$som/../../Logs/SWTOR on Mac/install.log"'
  local imported
  # shellcheck disable=SC2034 # (the checks' eval strings read it)
  imported=$(fx_gptk_state)
  fx_gptk dev "$good"
  check "dx12-gptk: imported again: the same state, the .stock copies still the engine's ($FX_RC)" \
    eval '[ "$FX_RC" = 0 ] && [ "$(fx_gptk_state)" = "$imported" ] && [ "$(head -1 "$t/x86_64-windows/d3d12.dll.stock")" = "MZ engine d3d12" ]'
  fx_gptk dev "$imgs/extra.dmg"
  check "dx12-gptk: a wrong image over an import is refused and leaves the import as it was ($FX_RC)" \
    eval '[ "$FX_RC" != 0 ] && [ "$(fx_gptk_state)" = "$imported" ]'

  # an import that fails halfway, over an import: the engine's own D3DMetal again, and env with it
  printf '#!/bin/bash\nexit 1\n' >"$d/bin/ditto"
  chmod 755 "$d/bin/ditto"
  fx_gptk dev "$good"
  rm -f "$d/bin/ditto"
  check "dx12-gptk: a copy that fails over an import: refused, the engine's own D3DMetal again ($FX_RC)" \
    eval '[ "$FX_RC" != 0 ] && [ "$(fx_gptk_state)" = "$stock" ]'
  check "dx12-gptk: ...and env names the engine's D3DMetal, no imported libd3dshared" \
    eval '[ "$(fx_gptk_env SWTOR_DX12_DRIVER_VERSION)/$(fx_gptk_env SWTOR_DX12_LIBD3DSHARED)" = "D3DMetal 4.0b2 (the engine'"'"'s)/<unset>" ]'
  fx_gptk dev "$good"
  check "dx12-gptk: imported again after that ($FX_RC)" eval '[ "$FX_RC" = 0 ] && [ "$(fx_gptk_state)" = "$imported" ]'

  # gptk_restore (Install calls it), taken from som.sh as the app has it
  # (with som.sh's run and say as plain calls)
  { printf '%s\n' 'run() { "$@"; }' 'say() { echo "$*"; }'; sed -n '/^gptk_link() /p; /^gptk_restore() {/,/^}/p' "$d/res-dev/som.sh"; } >"$d/restore.sh"
  # fx_gptk_restore: FX_RC its exit status
  fx_gptk_restore() {
    FX_RC=0
    # shellcheck disable=SC2034 # (gptk_restore reads them)
    ( DRY="" GPTK_TREE="$t" GPTK_IMPORT="$FX_G_ENG/lib/external/gptk-import"
      . "$d/restore.sh"; gptk_restore ) >"$d/out.txt" 2>&1 || FX_RC=$?
  }
  # a restore that can't make a link (a full disk): it says so, and keeps the import and its
  # record, so no link points at a removed file and it can run again
  mkdir -p "$d/no-ln"
  printf '#!/bin/bash\nexit 1\n' >"$d/no-ln/ln"
  chmod 755 "$d/no-ln/ln"
  PATH="$d/no-ln:$PATH" fx_gptk_restore
  check "dx12-gptk: gptk_restore that can't make a link: fails, keeps the import and its record, no link dangles ($FX_RC)" \
    eval '[ "$FX_RC" != 0 ] && [ -f "$FX_G_ENG/lib/external/gptk-import/IMPORTED" ] && [ -z "$(find "$t/x86_64-unix" -type l ! -exec test -e {} \; -print)" ]'
  fx_gptk_restore
  check "dx12-gptk: gptk_restore: the engine's own D3DMetal again, file for file" \
    eval '[ "$(fx_gptk_state)" = "$stock" ] && grep -qx "D3DMetal: the engine'"'"'s own again" "$d/out.txt"'
  fx_gptk_restore
  check "dx12-gptk: gptk_restore without an import changes nothing and says nothing" \
    eval '[ "$(fx_gptk_state)" = "$stock" ] && [ ! -s "$d/out.txt" ]'
  # an import that stopped after its record and two shims (one replaced, the added one), with a
  # backup, a copy and a link it was still writing
  mkdir -p "$FX_G_ENG/lib/external/gptk-import"
  printf 'version=4.0b3\nimage=x\nadded=d3d12core\n' >"$FX_G_ENG/lib/external/gptk-import/IMPORTED"
  cp -p "$t/x86_64-windows/dxgi.dll" "$t/x86_64-windows/dxgi.dll.stock"
  echo "MZ gptk dxgi" >"$t/x86_64-windows/dxgi.dll"
  echo "MZ gptk d3d12core" >"$t/x86_64-windows/d3d12core.dll"
  ln -sfn ../../../../external/gptk-import/libd3dshared.dylib "$t/x86_64-unix/dxgi.so"
  ln -s ../../../../external/gptk-import/libd3dshared.dylib "$t/x86_64-unix/d3d12core.so"
  echo "MZ eng" >"$t/x86_64-windows/d3d11.dll.stock.new.123"
  echo "MZ gp" >"$t/x86_64-windows/d3d11.dll.new.456"
  ln -s ../../../../external/gptk-import/libd3dshared.dylib "$t/x86_64-unix/d3d11.so.new.789"
  mkdir -p "$FX_G_ENG/lib/external/gptk-import.new"
  fx_gptk_restore
  check "dx12-gptk: gptk_restore after an import that stopped halfway: the engine's own again" \
    eval '[ "$(fx_gptk_state)" = "$stock" ] && [ ! -e "$FX_G_ENG/lib/external/gptk-import.new" ]'
}
