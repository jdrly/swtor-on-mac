#!/bin/bash
# Builds the Wine Mac driver the app ships into prebuilt/winemac/: winemac.so (x86_64, the
# unix side of winemac.drv) from the sources of the app's Wine engine (athei's wine-build
# cx-26.3.0-8, CrossOver 26.3 / Wine 11.0: athei/wine at the commit its release notes name),
# with patches/winemac-physical-keys.patch (the PhysicalKeyboard option, off by default).
# Only winemac.so is built: the patch touches unix-side code only.
#   winemac.so        the patched driver; the installer puts it into its engine copy
#                     (lib/wine/x86_64-unix/) while "Game keys by keyboard position" is on
#   COPYING.LIB, LICENSE  Wine's license texts (LGPL-2.1-or-later), from the same sources
#   VERSION           what it was built from
# It also builds the unpatched driver, to check the toolchain against the engine's own file
# and that the patch changes only what it should (scripts/winemac-compare.py).
#
# Configured like athei's build-wine.sh (x86_64 host, i386+x86_64 PE, macOS 26.0 minimum).
# Linking uses the engine's own ntdll.so and win32u.so (the right link inputs, and make need
# not build them): they come from the engine download pinned in src/som.sh. Downloads are
# cached in .cache/ and sha256-checked.
#
#   scripts/build-winemac.sh       work dir: $WINEMAC_WORK (default /tmp/swtor-on-mac-winemac)
#
# Needs Xcode (or the Command Line Tools), Rosetta and Homebrew bison. The PE cross compiler
# (only so configure accepts the i386,x86_64 setup the engine has; no PE code is compiled) is
# the llvm-mingw release athei's build uses, pinned below.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/prebuilt/winemac"
PATCH="$ROOT/patches/winemac-physical-keys.patch"
W="${WINEMAC_WORK:-/tmp/swtor-on-mac-winemac}"
case "$W" in *" "*) echo "WINEMAC_WORK must not contain spaces (Wine's makefiles break on them)" >&2; exit 1 ;; esac

# athei/wine@cx-26-patched as named by https://github.com/athei/wine-build/releases/tag/cx-26.3.0-8
WINE_COMMIT=d23b39774528237cafe49f9a073286f854b779c0
WINE_SRC_URL=https://codeload.github.com/athei/wine/tar.gz/$WINE_COMMIT
WINE_SRC_SHA256=7002111d61bbf28e88cc2504080747d27d074907a7e278f6c78cf6cefe09746e
MINGW_URL=https://github.com/mstorsjo/llvm-mingw/releases/download/20261006/llvm-mingw-20261006-ucrt-macos-universal.tar.xz
MINGW_SHA256=a7a19b11048e89372637d26279cdb7c430ed3cf8c1e224310421312bf986ebf6
ENGINE_NAME="$(sed -n 's/^ENGINE_NAME=//p' src/som.sh)"
ENGINE_URL="$(sed -n 's/^ENGINE_URL=//p' src/som.sh)"
ENGINE_SHA256="$(sed -n 's/^ENGINE_SHA256=//p' src/som.sh)"
ENGINE_WINEMAC_SHA256="$(sed -n 's/^ENGINE_WINEMAC_SHA256=//p' src/som.sh)"

fetch() { # url sha256 -> prints path of the verified download
  local url=$1 sha=$2 dir="$ROOT/.cache/$2" file
  file="$dir/$(basename "$url")"
  if [ ! -f "$file" ]; then
    mkdir -p "$dir"
    echo "Downloading $url" >&2
    curl -fL --progress-bar -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  echo "$sha  $file" | shasum -a 256 -c --quiet >&2
  echo "$file"
}

src_tgz=$(fetch "$WINE_SRC_URL" "$WINE_SRC_SHA256")
mingw_txz=$(fetch "$MINGW_URL" "$MINGW_SHA256")
engine_txz=$(fetch "$ENGINE_URL" "$ENGINE_SHA256")

mkdir -p "$W"
if [ ! -f "$W/src-pristine/VERSION" ]; then
  echo "[winemac] unpacking the Wine sources"
  rm -rf "$W/src-pristine" "$W/x" && mkdir "$W/x"
  tar -xzf "$src_tgz" -C "$W/x"
  mv "$W/x/wine-$WINE_COMMIT" "$W/src-pristine" && rm -rf "$W/x"
fi
grep -qx "Wine version 11.0" "$W/src-pristine/VERSION"
if [ ! -x "$W/mingw/bin/x86_64-w64-mingw32-clang" ]; then
  echo "[winemac] unpacking llvm-mingw"
  rm -rf "$W/mingw" && mkdir "$W/mingw"
  tar -xJf "$mingw_txz" -C "$W/mingw" --strip-components 1
fi
U="$W/engine/lib/wine/x86_64-unix"
if [ ! -f "$U/winemac.so" ]; then
  echo "[winemac] unpacking ntdll.so, win32u.so and winemac.so from the engine"
  rm -rf "$W/engine" && mkdir -p "$W/engine"
  tar -xJf "$engine_txz" -C "$W/engine" --strip-components 1 \
    wine/lib/wine/x86_64-unix/ntdll.so wine/lib/wine/x86_64-unix/win32u.so \
    wine/lib/wine/x86_64-unix/winemac.so
fi
[ "$(shasum -a 256 "$U/winemac.so" | cut -d' ' -f1)" = "$ENGINE_WINEMAC_SHA256" ] ||
  { echo "The engine's winemac.so is not the one src/som.sh expects (ENGINE_WINEMAC_SHA256)" >&2; exit 1; }

# Source trees as APFS clones of the pristine one
for v in stock patched; do
  rm -rf "$W/src-$v" && cp -c -R "$W/src-pristine" "$W/src-$v"
done
patch -d "$W/src-patched" -p1 --quiet <"$PATCH"

# The engine's winemac.so says minos 26.0 (athei's build-wine.sh pins it).
export MACOSX_DEPLOYMENT_TARGET=26.0
# reproducible: no object file times in a debug map, so the same LC_UUID every build
export ZERO_AR_DATE=1
PATH="$(brew --prefix bison)/bin:$PATH:$W/mingw/bin"   # flex: /usr/bin's
export PATH
NCPU="$(sysctl -n hw.ncpu)"
without="--without-freetype --without-gnutls --without-sdl --without-unwind --without-opencl --without-alsa
  --without-capi --without-cups --without-dbus --without-ffmpeg --without-fontconfig --without-gettext
  --without-gphoto --without-gssapi --without-gstreamer --without-hwloc --without-inotify --without-krb5
  --without-netapi --without-oss --without-pcap --without-pcsclite --without-pulse --without-sane
  --without-udev --without-usb --without-v4l2 --without-vulkan --without-wayland --without-x"

# The whole build as x86_64 (build = host): Wine's own tools (makedep, ...) are x86_64 and run
# under Rosetta, like the engine. CFLAGS as athei's build-wine.sh sets them (only an include
# path, so none of configure's default -g -O2): the engine's Wine is built unoptimized.
for v in stock patched; do
  echo "[winemac] building $v (log: $W/build-$v/make.log)"
  rm -rf "$W/build-$v" && mkdir "$W/build-$v"
  # ($without: word splitting on purpose)
  # shellcheck disable=SC2086
  ( cd "$W/build-$v" &&
    "$W/src-$v/configure" --build=x86_64-apple-darwin --host=x86_64-apple-darwin --enable-archs=i386,x86_64 \
      --with-mingw --with-coreaudio $without CC="clang -arch x86_64" CFLAGS="" >configure.log 2>&1 &&
    # Link-only copies of the engine's ntdll.so and win32u.so (their ids are already the
    # @rpath names the engine's winemac.so refers to); make must not rebuild them (-o).
    mkdir -p dlls/ntdll dlls/win32u &&
    cp "$U/ntdll.so" dlls/ntdll/ntdll.so && cp "$U/win32u.so" dlls/win32u/win32u.so &&
    make -j"$NCPU" -o dlls/ntdll/ntdll.so -o dlls/win32u/win32u.so dlls/winemac.drv/winemac.so >make.log 2>&1 ) ||
    { tail -30 "$W/build-$v/configure.log" "$W/build-$v/make.log" 2>/dev/null; exit 1; }
  mkdir -p "$W/out/$v"
  install -m 755 "$W/build-$v/dlls/winemac.drv/winemac.so" "$W/out/$v/winemac.so"
done

# Toolchain check (stock rebuild vs the engine's file) and the patch's footprint (patched vs
# stock, function by function), before stripping
python3 -I scripts/winemac-compare.py "$U/winemac.so" "$W/out/stock/winemac.so" "$W/out/patched/winemac.so"

rm -rf "$OUT" && mkdir -p "$OUT"
install -m 755 "$W/out/patched/winemac.so" "$OUT/winemac.so"
# No debug map; then an ad-hoc signature (the release signs the app's copy with its Developer ID)
strip -S -x "$OUT/winemac.so"
codesign --force --sign - "$OUT/winemac.so" 2>/dev/null
cp "$W/src-pristine/COPYING.LIB" "$W/src-pristine/LICENSE" "$OUT/"
cat >"$OUT/VERSION" <<EOF
winemac.so: Wine's Mac driver (x86_64 unix side) for the $ENGINE_NAME engine
sources: athei/wine $WINE_COMMIT (codeload tar.gz sha256 $WINE_SRC_SHA256)
patch: patches/winemac-physical-keys.patch sha256 $(shasum -a 256 "$PATCH" | cut -d' ' -f1)
EOF
echo "[winemac] prebuilt/winemac: $(ls "$OUT" | tr '\n' ' ')"
echo "[winemac] winemac.so sha256 $(shasum -a 256 "$OUT/winemac.so" | cut -d' ' -f1)"
