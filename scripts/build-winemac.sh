#!/bin/bash
# Builds the Wine Mac driver the app ships into prebuilt/winemac/: winemac.so (x86_64, the
# unix side of winemac.drv) from CodeWeavers' published CrossOver 24.0.7 sources, the version
# of the app's Wine engine (Sikarugir's WS12WineCX24.0.7_7, "wine-9.0 (SikarugirCX 24.0.7)"),
# with patches/winemac-physical-keys.patch (the PhysicalKeyboard option, off by default).
# Only winemac.so is built: the patch touches unix-side code only.
#   winemac.so        the patched driver; the installer puts it into its engine copy
#                     (lib/wine/x86_64-unix/) while "Game keys by keyboard position" is on
#   COPYING.LIB, LICENSE  Wine's license texts (LGPL-2.1-or-later), from the same sources
#   VERSION           what it was built from
# It also builds the unpatched driver, to check the toolchain against the engine's own file
# and that the patch changes only what it should (scripts/winemac-compare.py).
#
# Linking needs the engine's ntdll.so and win32u.so (Wine 9's ntdll does not assemble with
# current clang, and the engine's are the right link inputs anyway): they come from the
# engine download pinned in src/som.sh. Downloads are cached in .cache/ and sha256-checked.
#
#   scripts/build-winemac.sh       work dir: $WINEMAC_WORK (default /tmp/swtor-on-mac-winemac)
#
# Needs Xcode (or the Command Line Tools), Rosetta, Homebrew bison and Homebrew mingw-w64 (only
# so configure accepts the i386,x86_64 PE setup the engine has; no PE code is compiled).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/prebuilt/winemac"
PATCH="$ROOT/patches/winemac-physical-keys.patch"
W="${WINEMAC_WORK:-/tmp/swtor-on-mac-winemac}"
case "$W" in *" "*) echo "WINEMAC_WORK must not contain spaces (Wine's makefiles break on them)" >&2; exit 1 ;; esac

CX_URL=https://media.codeweavers.com/pub/crossover/source/crossover-sources-24.0.7.tar.gz
CX_SHA256=56749e926df9f0437dbcea259cf0bff6657a43871af50182887fe15a84fc2e4e
ENGINE_NAME="$(sed -n 's/^ENGINE_NAME=//p' src/som.sh)"
ENGINE_URL="$(sed -n 's/^ENGINE_URL=//p' src/som.sh)"
ENGINE_SHA256="$(sed -n 's/^ENGINE_SHA256=//p' src/som.sh)"
ENGINE_WINEMAC_SHA256="$(sed -n 's/^ENGINE_WINEMAC_SHA256=//p' src/som.sh)"

fetch() { # url sha256 [curl args] -> prints path of the verified download
  local url=$1 sha=$2 dir="$ROOT/.cache/$2" file
  shift 2
  file="$dir/$(basename "$url")"
  if [ ! -f "$file" ]; then
    mkdir -p "$dir"
    echo "Downloading $url" >&2
    curl -fL --progress-bar "$@" -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  echo "$sha  $file" | shasum -a 256 -c --quiet >&2
  echo "$file"
}

# media.codeweavers.com answers 403 to curl's own user agent
cx_tgz=$(fetch "$CX_URL" "$CX_SHA256" -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)")
engine_txz=$(fetch "$ENGINE_URL" "$ENGINE_SHA256")

mkdir -p "$W"
if [ ! -f "$W/src-pristine/VERSION" ]; then
  echo "[winemac] unpacking the CrossOver sources"
  rm -rf "$W/src-pristine" "$W/x" && mkdir "$W/x"
  tar -xzf "$cx_tgz" -C "$W/x" sources/wine
  mv "$W/x/sources/wine" "$W/src-pristine" && rm -rf "$W/x"
fi
grep -qx "Wine version 9.0" "$W/src-pristine/VERSION"
U="$W/engine/lib/wine/x86_64-unix"
if [ ! -f "$U/winemac.so" ]; then
  echo "[winemac] unpacking ntdll.so, win32u.so and winemac.so from the engine"
  rm -rf "$W/engine" && mkdir -p "$W/engine"
  tar -xJf "$engine_txz" -C "$W/engine" --strip-components 1 \
    wswine.bundle/lib/wine/x86_64-unix/ntdll.so wswine.bundle/lib/wine/x86_64-unix/win32u.so \
    wswine.bundle/lib/wine/x86_64-unix/winemac.so
fi
[ "$(shasum -a 256 "$U/winemac.so" | cut -d' ' -f1)" = "$ENGINE_WINEMAC_SHA256" ] ||
  { echo "The engine's winemac.so is not the one src/som.sh expects (ENGINE_WINEMAC_SHA256)" >&2; exit 1; }

# Source trees as APFS clones of the pristine one. Both get programs/winedbg/distversion.h,
# which CrossOver's own build generates (winedbg's crash dialog, not built here); makedep only
# needs it to exist.
for v in stock patched; do
  rm -rf "$W/src-$v" && cp -c -R "$W/src-pristine" "$W/src-$v"
  printf '#define WINDEBUG_WHAT_HAPPENED_MESSAGE "%s"\n#define WINDEBUG_USER_SUGGESTION_MESSAGE "%s"\n' \
    "The program crashed." "" >"$W/src-$v/programs/winedbg/distversion.h"
done
patch -d "$W/src-patched" -p1 --quiet <"$PATCH"

# The engine's winemac.so says minos 10.15.
export MACOSX_DEPLOYMENT_TARGET=10.15
# reproducible: no object file times in the debug map, so the same LC_UUID every build
export ZERO_AR_DATE=1
PATH="$(brew --prefix bison)/bin:$PATH:$(brew --prefix mingw-w64)/bin"   # flex: /usr/bin's
export PATH
NCPU="$(sysctl -n hw.ncpu)"
without="--without-freetype --without-gnutls --without-sdl --without-unwind --without-opencl --without-alsa
  --without-capi --without-cups --without-dbus --without-ffmpeg --without-fontconfig --without-gettext
  --without-gphoto --without-gssapi --without-gstreamer --without-inotify --without-krb5
  --without-netapi --without-oss --without-pcap --without-pcsclite --without-pulse --without-sane
  --without-udev --without-usb --without-v4l2 --without-vulkan --without-wayland --without-x"

# The whole build as x86_64 (build = host): Wine's own tools (makedep, ...) are x86_64 and run
# under Rosetta, like the engine.
for v in stock patched; do
  echo "[winemac] building $v (log: $W/build-$v/make.log)"
  rm -rf "$W/build-$v" && mkdir "$W/build-$v"
  # ($without: word splitting on purpose)
  # shellcheck disable=SC2086
  ( cd "$W/build-$v" &&
    # LDFLAGS: the engine's winemac.so has a second rpath, @loader_path/../../ (= lib/).
    "$W/src-$v/configure" --build=x86_64-apple-darwin --host=x86_64-apple-darwin --enable-archs=i386,x86_64 \
      --with-coreaudio $without CC="clang -arch x86_64" LDFLAGS="-Wl,-rpath,@loader_path/../../" \
      >configure.log 2>&1 &&
    # The engine's driver loads MoltenVK for Vulkan surfaces ("libMoltenVK.dylib" in it);
    # configure only finds that with MoltenVK installed, so define it as the engine has it.
    printf '\n#define SONAME_LIBMOLTENVK "libMoltenVK.dylib"\n' >>include/config.h &&
    # Link-only copies of the engine's ntdll.so and win32u.so, with the @rpath ids the
    # engine's winemac.so refers to (theirs are bare names); make must not rebuild them (-o).
    mkdir -p dlls/ntdll dlls/win32u &&
    cp "$U/ntdll.so" dlls/ntdll/ntdll.so && cp "$U/win32u.so" dlls/win32u/win32u.so &&
    install_name_tool -id @rpath/ntdll.so dlls/ntdll/ntdll.so 2>/dev/null &&
    install_name_tool -id @rpath/win32u.so dlls/win32u/win32u.so 2>/dev/null &&
    make -j"$NCPU" -o dlls/ntdll/ntdll.so -o dlls/win32u/win32u.so dlls/winemac.drv/winemac.so >make.log 2>&1 ) ||
    { tail -30 "$W/build-$v/configure.log" "$W/build-$v/make.log" 2>/dev/null; exit 1; }
  mkdir -p "$W/out/$v"
  install -m 755 "$W/build-$v/dlls/winemac.drv/winemac.so" "$W/out/$v/winemac.so"
  # The engine's install name (its build reset ids to bare names)
  install_name_tool -id winemac.so "$W/out/$v/winemac.so" 2>/dev/null
done

# Toolchain check (stock rebuild vs the engine's file) and the patch's footprint (patched vs
# stock, function by function), before stripping
python3 -I scripts/winemac-compare.py "$U/winemac.so" "$W/out/stock/winemac.so" "$W/out/patched/winemac.so"

rm -rf "$OUT" && mkdir -p "$OUT"
install -m 755 "$W/out/patched/winemac.so" "$OUT/winemac.so"
# No local symbols or debug map, like the engine's; then an ad-hoc signature like every .so
# in the engine (the release re-signs the app, not this file)
strip -S -x "$OUT/winemac.so"
codesign --force --sign - "$OUT/winemac.so" 2>/dev/null
cp "$W/src-pristine/COPYING.LIB" "$W/src-pristine/LICENSE" "$OUT/"
cat >"$OUT/VERSION" <<EOF
winemac.so: Wine's Mac driver (x86_64 unix side) for the $ENGINE_NAME engine
sources: crossover-sources-24.0.7.tar.gz sha256 $CX_SHA256
patch: patches/winemac-physical-keys.patch sha256 $(shasum -a 256 "$PATCH" | cut -d' ' -f1)
EOF
echo "[winemac] prebuilt/winemac: $(ls "$OUT" | tr '\n' ' ')"
echo "[winemac] winemac.so sha256 $(shasum -a 256 "$OUT/winemac.so" | cut -d' ' -f1)"
