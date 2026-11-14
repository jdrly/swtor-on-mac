#!/bin/bash
# Builds the d9mt pieces the app ships into prebuilt/d9mt/, from Jan's public fork
# https://github.com/jdrly/d9mt at a pinned commit, in a scratch clone (never in a working
# checkout). SWTOR is a 64-bit game, so only the x86_64 parts:
#   d3d9.dll        64-bit D3D9 -> Metal driver (PE, x86_64), stripped; goes into the
#                   app's prefix (drive_c/windows/system32)
#   winemetal.dll   bridge, PE side (x86_64, builtin-marked); replaces the engine's own
#                   lib/wine/x86_64-windows/winemetal.dll in the app's engine copy
#   winemetal.so    bridge, macOS side (x86_64, includes the AIR shader compiler);
#                   lib/wine/x86_64-unix/winemetal.so in the app's engine copy
#   LICENSE, LICENSES/, THIRD_PARTY_NOTICES.md, bridge/{LICENSE,COPYING.LIB}
#                   (a binary release must carry them)
#   VERSION         the commit
#
# Needs Homebrew bash, mingw-w64, cmake and ninja, and Xcode for the metal compiler.
# LLVM 15 (x86_64, static) is needed for the bridge; it is not built here:
#   D9MT_LLVM=<an llvm-x86_64 install prefix built for macOS $MACOS_MIN>
# d9mt's scripts/build-llvm-unixside.sh builds one (LLVM 15.0.7, for macOS 26.0 unless
# MACOSX_DEPLOYMENT_TARGET says otherwise). The deployment target of everything built here is
# MACOS_MIN below: this script exports it, and refuses an LLVM or a winemetal.so built for a
# newer macOS. No path on the build machine decides it.
#
#   D9MT_SRC=<git url or local clone>  (default: GitHub)
#   D9MT_WORK=<scratch dir>            (default: /tmp/swtor-on-mac-d9mt)
#
#   scripts/build-d9mt.sh --check-air-codegen <air-codegen-id.txt>
# runs only the AIR codegen guard (scripts/air-codegen-guard.sh) on that file, with the id and
# the release recorded below, and builds nothing. Fixture group air-codegen tests the guard
# through it.
#
# Every run builds from scratch (d9mt's build does not track header dependencies, jdrly/d9mt#15)
# after d9mt's scripts/fetch-deps.sh has put its dxbc-spirv checkout at the pin with
# patches/dxbc-spirv applied (build-driver.sh refuses an unpatched tree). The output is
# reproducible: SOURCE_DATE_EPOCH is the pinned commit's time, and the same D9MT_WORK path gives
# the same d3d9.dll (its PE image base follows the path: mingw's auto image base).
set -euo pipefail
START="$PWD"
cd "$(dirname "$0")/.."
ROOT="$PWD"
REPO="${D9MT_SRC:-https://github.com/jdrly/d9mt.git}"
COMMIT=9b645818ef07383b1235afe6b06f3deefeafb9e6
MACOS_MIN=26.0
# The AIR codegen id the bridge must report (d9mt ADR-0006), the identity of the code that
# compiles the game's shaders. 0.1.8 changed that code on purpose, so this id has no lineage:
# every player's shaders recompiled once after that update. 0.1.9 keeps the id, so players keep
# the caches 0.1.8 built. Another Xcode or LLVM that changes the
# codegen's code would give winemetal.so yet another id and every player one more full recompile,
# so the build stops unless the bridge reports exactly this id, or a later id that d9mt's lineage
# table carries back to AIR_LINEAGE's cache.
AIR_CODEGEN=25fc2491f11d0902328bd623fa12d2d73b7eeebb877e6dfd30d85b78c8e7a6c2
AIR_LINEAGE=0.1.8
V="${D9MT_WORK:-/tmp/swtor-on-mac-d9mt}"
OUT="$ROOT/prebuilt/d9mt"
if [ $# -gt 0 ]; then
  if [ $# != 2 ] || [ "$1" != --check-air-codegen ] || [ -z "$2" ]; then
    echo "usage: $0 [--check-air-codegen <air-codegen-id.txt>]" >&2
    exit 64
  fi
  case $2 in /*) f=$2 ;; *) f=$START/$2 ;; esac   # (the caller's folder, not the repo's)
  exec "$ROOT/scripts/air-codegen-guard.sh" "$f" "$AIR_CODEGEN" "$AIR_LINEAGE"
fi
export PATH="/opt/homebrew/bin:$PATH"   # the d9mt scripts need bash >= 4.3
export MACOSX_DEPLOYMENT_TARGET=$MACOS_MIN
: "${D9MT_LLVM:?set D9MT_LLVM to an llvm-x86_64 install prefix (see the header)}"

newer_than_min() {  # <version>: true if above MACOS_MIN (trailing ".0"s don't count)
  local v="$1" m="$MACOS_MIN"
  while [[ $v == *.0 ]]; do v="${v%.0}"; done
  while [[ $m == *.0 ]]; do m="${m%.0}"; done
  [ "$v" != "$m" ] && [ "$(printf '%s\n%s\n' "$v" "$m" | sort -V | tail -1)" = "$v" ]
}

[ -d "$V/.git" ] || git clone -q "$REPO" "$V"
if [ "$(git -C "$V" rev-parse HEAD)" != "$COMMIT" ]; then
  [ -z "$(git -C "$V" status --porcelain --untracked-files=no)" ] || { echo "$V has local changes" >&2; exit 1; }
  git -C "$V" fetch -q origin
  git -C "$V" checkout -q --detach "$COMMIT"
fi

cd "$V"
scripts/fetch-deps.sh
rm -rf build
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git show -s --format=%ct HEAD)}"
mkdir -p toolchains && ln -sfn "$D9MT_LLVM" toolchains/llvm-x86_64
llvm_min="$(otool -l toolchains/llvm-x86_64/lib/libLLVMSupport.a | awk '/minos/ { print $2 }' | sort -V | tail -1)"
if newer_than_min "$llvm_min"; then
  echo "LLVM in $D9MT_LLVM is built for macOS $llvm_min, newer than $MACOS_MIN" >&2
  exit 1
fi
echo "[d9mt] bridge"
SMOKE=0 scripts/build-bridge.sh >build-bridge.log 2>&1 || { tail -20 build-bridge.log; exit 1; }
"$ROOT/scripts/air-codegen-guard.sh" build/bridge/air-codegen-id.txt "$AIR_CODEGEN" "$AIR_LINEAGE" || exit 1
echo "[d9mt] driver (x86_64)"
ARCH=x64 scripts/build-driver.sh >build-driver-x64.log 2>&1 || { tail -20 build-driver-x64.log; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
install -m 644 build/driver-x64/d3d9.dll "$OUT/d3d9.dll"
x86_64-w64-mingw32-strip "$OUT/d3d9.dll"
install -m 644 build/bridge/winemetal64.dll "$OUT/winemetal.dll"
install -m 755 build/bridge/winemetal.so "$OUT/winemetal.so"
strip -x "$OUT/winemetal.so"
cp -R LICENSE LICENSES THIRD_PARTY_NOTICES.md "$OUT/"
# the bridge is LGPL-2.1-or-later: its license texts travel with winemetal.so/.dll
mkdir -p "$OUT/bridge" && cp bridge/LICENSE bridge/COPYING.LIB "$OUT/bridge/"
git rev-parse --short HEAD >"$OUT/VERSION"

so_min="$(vtool -show-build "$OUT/winemetal.so" | awk '/minos/ { print $2 }')"
newer_than_min "$so_min" && { echo "winemetal.so is built for macOS $so_min, newer than $MACOS_MIN" >&2; exit 1; }
# Every embedded metallib for a newer macOS needs a Compat one for MACOS_MIN next to it,
# or macOS 26 shows a black screen.
newer=0 compat=0
for t in $(strings -a "$OUT/d3d9.dll" | sed -n 's/.*air64[_a-z0-9]*-apple-macosx\([0-9.]*\).*/\1/p'); do
  if newer_than_min "$t"; then newer=$((newer + 1)); else compat=$((compat + 1)); fi
done
if [ "$compat" -eq 0 ] || [ "$compat" -lt "$newer" ]; then
  echo "d3d9.dll: $newer metallibs for macOS newer than $MACOS_MIN but $compat Compat ones" >&2
  exit 1
fi
echo "[d9mt] built for macOS $MACOS_MIN (winemetal.so minos $so_min); $(cat build/bridge/air-codegen-id.txt)"
echo "[d9mt] prebuilt/d9mt: $(ls "$OUT" | tr '\n' ' ')"
