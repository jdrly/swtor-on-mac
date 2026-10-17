#!/bin/bash
# Builds the Wine Mac driver the app ships into prebuilt/winemac/ from the sources of the
# app's Wine engine (athei's wine-build cx-26.3.0-8, CrossOver 26.3 / Wine 11.0: athei/wine at
# the commit its release notes name), with these patches, in this order:
#   winemac-physical-keys.patch       the PhysicalKeyboard option (off by default)
#   winemac-swgl-relative-mouse.patch SWGL on Mac's patches/winemac-swg.patch, unchanged: raw
#                                     mouse moves while the game hides the cursor, the macOS
#                                     cursor frozen (RawMouseWhenCursorHidden)
#   winemac-swgl-input-thread.patch   SWGL on Mac's patches/winemac-input.patch, unchanged: those
#                                     moves from GameController's GCMouse, sent by an input
#                                     thread of the driver
#   winemac-swtor-mouse.patch         SWTOR on Mac's changes to them (see its header): options
#                                     off unless set, speed matched to the macOS pointer, the
#                                     RAWMOUSE and THREADCPU debug lines
#   winemac.so                     the unix side (x86_64)
#   x86_64-windows/winemac.drv     the PE sides (the input thread is started from dllmain.c);
#   i386-windows/winemac.drv       they go with this winemac.so only
#   COPYING.LIB, LICENSE           Wine's license texts (LGPL-2.1-or-later), from the same sources
#   VERSION                        what it was built from
# The installer puts the three into its engine copy while "Game keys by keyboard position" or
# "Raw mouse-look" is on. It also builds the unpatched driver, to check the toolchain against
# the engine's own files and what the patches change (scripts/winemac-compare.py).
#
# Configured like athei's build-wine.sh (x86_64 host, i386+x86_64 PE, macOS 26.0 minimum).
# Linking uses the engine's own ntdll.so and win32u.so (the right link inputs, and make need
# not build them): they come from the engine download pinned in src/som.sh. Downloads are
# cached in .cache/ and sha256-checked.
#
#   scripts/build-winemac.sh       work dir: $WINEMAC_WORK (default /tmp/swtor-on-mac-winemac)
#
# Needs Xcode (or the Command Line Tools), Rosetta and Homebrew bison. The PE cross compiler
# is the llvm-mingw release athei's build uses, pinned below, named to configure explicitly
# (it would take a mingw-w64 gcc found on PATH first, e.g. Homebrew's; athei's PE files are
# llvm-mingw's).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/prebuilt/winemac"
PATCHES="winemac-physical-keys winemac-swgl-relative-mouse winemac-swgl-input-thread winemac-swtor-mouse"
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
ENGINE_WINEMAC_PE64_SHA256="$(sed -n 's/^ENGINE_WINEMAC_PE64_SHA256=//p' src/som.sh)"
ENGINE_WINEMAC_PE32_SHA256="$(sed -n 's/^ENGINE_WINEMAC_PE32_SHA256=//p' src/som.sh)"

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
# (a work dir of an older build, e.g. 0.0.x's Wine 9 sources, is unpacked again)
if ! grep -qx "Wine version 11.0" "$W/src-pristine/VERSION" 2>/dev/null; then
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
if [ ! -f "$U/winemac.so" ] || [ ! -f "$W/engine/lib/wine/i386-windows/winemac.drv" ]; then
  echo "[winemac] unpacking ntdll.so, win32u.so and the Mac driver from the engine"
  rm -rf "$W/engine" && mkdir -p "$W/engine"
  tar -xJf "$engine_txz" -C "$W/engine" --strip-components 1 \
    wine/lib/wine/x86_64-unix/ntdll.so wine/lib/wine/x86_64-unix/win32u.so \
    wine/lib/wine/x86_64-unix/winemac.so \
    wine/lib/wine/x86_64-windows/winemac.drv wine/lib/wine/i386-windows/winemac.drv
fi
check_engine_file() { # <file> <sha256> <name in src/som.sh>
  [ "$(shasum -a 256 "$1" | cut -d' ' -f1)" = "$2" ] ||
    { echo "The engine's ${1#"$W/engine/"} is not the one src/som.sh expects ($3)" >&2; exit 1; }
}
check_engine_file "$U/winemac.so" "$ENGINE_WINEMAC_SHA256" ENGINE_WINEMAC_SHA256
check_engine_file "$W/engine/lib/wine/x86_64-windows/winemac.drv" "$ENGINE_WINEMAC_PE64_SHA256" ENGINE_WINEMAC_PE64_SHA256
check_engine_file "$W/engine/lib/wine/i386-windows/winemac.drv" "$ENGINE_WINEMAC_PE32_SHA256" ENGINE_WINEMAC_PE32_SHA256

# Source trees as APFS clones of the pristine one
for v in stock patched; do
  rm -rf "$W/src-$v" && cp -c -R "$W/src-pristine" "$W/src-$v"
done
for p in $PATCHES; do
  patch -d "$W/src-patched" -p1 --quiet --posix <"patches/$p.patch"
done
# Cursor hiding must stay athei's blank-cursor image: [NSCursor hide] or CGDisplayHideCursor
# turn the cursor plane off and on, which drops full-screen Metal out of direct presentation
# (the right-click hitch of SWTOR on Mac 0.0.x). None of the patches may bring them in.
# (code lines only: athei's comment names [NSCursor hide])
if grep -nE '^[[:space:]]*[^/*[:space:]].*(\[NSCursor (hide|unhide)\]|CGDisplay(Hide|Show)Cursor)' \
     "$W/src-patched/dlls/winemac.drv/"*.m "$W/src-patched/dlls/winemac.drv/"*.c; then
  echo "The patched Mac driver hides the cursor by turning the cursor plane off" >&2; exit 1
fi

# The engine's winemac.so says minos 26.0 (athei's build-wine.sh pins it).
export MACOSX_DEPLOYMENT_TARGET=26.0
# reproducible: no object file times in a debug map, so the same LC_UUID every build; the PE
# sides' link time stamp (lld) is 0
export ZERO_AR_DATE=1 SOURCE_DATE_EPOCH=0
# The cross tools by their target names (winegcc links through <target>-gcc found on PATH)
# come first, as shims into llvm-mingw (its wrappers find their clang next to themselves);
# llvm-mingw's own bin goes last (its clang must not replace the host's).
rm -rf "$W/cross-bin" && mkdir "$W/cross-bin"
for t in "$W/mingw/bin/"x86_64-w64-mingw32-* "$W/mingw/bin/"i686-w64-mingw32-*; do
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$t" >"$W/cross-bin/${t##*/}"
  chmod 755 "$W/cross-bin/${t##*/}"
done
PATH="$W/cross-bin:$(brew --prefix bison)/bin:$PATH:$W/mingw/bin"   # flex: /usr/bin's
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
      --with-mingw --with-coreaudio $without CC="clang -arch x86_64" CFLAGS="" \
      x86_64_CC="$W/mingw/bin/x86_64-w64-mingw32-clang" i386_CC="$W/mingw/bin/i686-w64-mingw32-clang" \
      x86_64_CFLAGS="-g -O2 -ffile-prefix-map=$W=/winemac" i386_CFLAGS="-g -O2 -ffile-prefix-map=$W=/winemac" \
      >configure.log 2>&1 &&
    # Link-only copies of the engine's ntdll.so and win32u.so (their ids are already the
    # @rpath names the engine's winemac.so refers to); make must not rebuild them (-o).
    mkdir -p dlls/ntdll dlls/win32u &&
    cp "$U/ntdll.so" dlls/ntdll/ntdll.so && cp "$U/win32u.so" dlls/win32u/win32u.so &&
    make -j"$NCPU" -o dlls/ntdll/ntdll.so -o dlls/win32u/win32u.so dlls/winemac.drv/winemac.so \
      dlls/winemac.drv/x86_64-windows/winemac.drv dlls/winemac.drv/i386-windows/winemac.drv >make.log 2>&1 ) ||
    { tail -30 "$W/build-$v/configure.log" "$W/build-$v/make.log" 2>/dev/null; exit 1; }
  mkdir -p "$W/out/$v/x86_64-windows" "$W/out/$v/i386-windows"
  install -m 755 "$W/build-$v/dlls/winemac.drv/winemac.so" "$W/out/$v/winemac.so"
  for a in x86_64 i386; do
    install -m 644 "$W/build-$v/dlls/winemac.drv/$a-windows/winemac.drv" "$W/out/$v/$a-windows/winemac.drv"
  done
done

# The PE sides: the stock rebuild must have the engine's files' imports and sections (the
# code differs by a few bytes, the debug info by its source paths; no exports either way), and
# the patched one the same imports plus the kernel32 calls that start the input thread
pe_facts() { # <file>: imports, then the section names without debug info and build id
  "$W/mingw/bin/llvm-readobj" --coff-imports "$1" | grep -E '^ *(Name|Symbol):' | sort
  "$W/mingw/bin/llvm-objdump" -h "$1" | awk '$1 ~ /^[0-9]+$/ && $2 !~ /^\.(debug_|buildid)/ { print "section", $2 }'
}
pe_text() { "$W/mingw/bin/llvm-objdump" -h "$1" | awk '$2 == ".text" { print $3 }'; }
for a in x86_64 i386; do
  e="$W/engine/lib/wine/$a-windows/winemac.drv" s="$W/out/stock/$a-windows/winemac.drv" p="$W/out/patched/$a-windows/winemac.drv"
  if ! diff <(pe_facts "$e") <(pe_facts "$s") >/dev/null; then
    diff <(pe_facts "$e") <(pe_facts "$s") >&2 || true
    echo "The stock $a-windows/winemac.drv rebuild differs from the engine's in imports or sections: check the toolchain" >&2; exit 1
  fi
  added=$(comm -13 <(pe_facts "$s" | grep -v '^section') <(pe_facts "$p" | grep -v '^section') |
    sed 's/^ *Symbol: \([A-Za-z]*\).*/\1/' | tr '\n' ' ')
  [ -z "$(comm -23 <(pe_facts "$s" | grep -v '^section') <(pe_facts "$p" | grep -v '^section'))" ] &&
    [ "$added" = "CloseHandle CreateThread SetThreadDescription " ] ||
    { echo "The patched $a-windows/winemac.drv imports something else than the stock one and the input thread's calls ($added)" >&2; exit 1; }
  echo "[winemac] $a-windows/winemac.drv: stock rebuild has the engine's imports and sections" \
    "(.text engine 0x$(pe_text "$e"), stock 0x$(pe_text "$s"), patched 0x$(pe_text "$p"))"
done

# Toolchain check (stock rebuild vs the engine's file) and the patch's footprint (patched vs
# stock, function by function), before stripping
python3 -I scripts/winemac-compare.py "$U/winemac.so" "$W/out/stock/winemac.so" "$W/out/patched/winemac.so"

rm -rf "$OUT" && mkdir -p "$OUT/x86_64-windows" "$OUT/i386-windows"
install -m 755 "$W/out/patched/winemac.so" "$OUT/winemac.so"
# PE sides without their debug info (compiled as configure's default, -g -O2, with the work
# dir mapped to /winemac, and linked with time stamp 0: the files do not depend on where or
# when they were built)
for a in x86_64 i386; do
  "$W/mingw/bin/llvm-strip" --strip-debug -o "$OUT/$a-windows/winemac.drv" "$W/out/patched/$a-windows/winemac.drv"
  chmod 644 "$OUT/$a-windows/winemac.drv"
done
# No debug map; then an ad-hoc signature (the release signs the app's copy with its Developer ID)
strip -S -x "$OUT/winemac.so"
codesign --force --sign - "$OUT/winemac.so" 2>/dev/null
cp "$W/src-pristine/COPYING.LIB" "$W/src-pristine/LICENSE" "$OUT/"
cat >"$OUT/VERSION" <<EOF
winemac.so: Wine's Mac driver (x86_64 unix side) for the $ENGINE_NAME engine
sources: athei/wine $WINE_COMMIT (codeload tar.gz sha256 $WINE_SRC_SHA256)
x86_64-windows/winemac.drv, i386-windows/winemac.drv: its PE sides, from the same build
patches, in this order:
$(for p in $PATCHES; do echo "  patches/$p.patch sha256 $(shasum -a 256 "patches/$p.patch" | cut -d' ' -f1)"; done)
EOF
echo "[winemac] prebuilt/winemac: $(cd "$OUT" && find . -type f | sed 's|^\./||' | sort | tr '\n' ' ')"
for f in winemac.so x86_64-windows/winemac.drv i386-windows/winemac.drv; do
  echo "[winemac] $f sha256 $(shasum -a 256 "$OUT/$f" | cut -d' ' -f1)"
done
