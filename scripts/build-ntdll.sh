#!/bin/bash
# Builds the Wine ntdll.so the app ships into prebuilt/ntdll/ from the sources of the app's Wine
# engine (athei's wine-build cx-26.3.0-8, CrossOver 26.3 / Wine 11.0: athei/wine at the commit
# its release notes name), with this patch:
#   ntdll-msync-alert-fd.patch  CodeWeavers' msync port keeps a thread's msync alert index in
#                               alert_fd, which pthread_exit_wrapper then close()s as if it were
#                               a file descriptor: every thread that did an alertable wait closes
#                               an unrelated fd when it exits (a file, another thread's wineserver
#                               pipe, a kqueue). With msync it leaves it alone (as athei's
#                               12927acab0 on another branch)
#   ntdll.so                    the unix side of ntdll (x86_64), ad-hoc signed
#   COPYING.LIB, LICENSE        Wine's license texts (LGPL-2.1-or-later), from the same sources
#   VERSION                     what it was built from
# The installer puts it into its engine copy in place of the engine's own (kept as .stock).
#
# Configured as athei's build-wine.sh at cx-26.3.0-8 configures the engine (x86_64 host,
# i386+x86_64 PE with llvm-mingw, --with-unwind, CFLAGS without -O or -g: the engine's Wine is
# built unoptimized, macOS 26.0 minimum), against the macOS 26.5 SDK the engine was built with
# (the Command Line Tools' MacOSX26.5.sdk; a newer SDK has pipe2, which the engine's ntdll.so
# does not use), except that gnutls, SDL and freetype are left out (x86_64 Homebrew libraries
# athei's CI has; ntdll uses none of them). It builds the unpatched ntdll.so too, and
# scripts/ntdll-compare.py checks that it is the engine's in exports, imports, libraries and
# the code of every function (the toolchain is right), and that the patch changes only
# pthread_exit_wrapper. The files are not byte for byte the engine's: athei linked with Xcode
# 26's ld, which lays out a section and the stubs differently from the ld here.
#
# The sources: .cache/ (sha256-checked), else $WINE_SRC_CACHE (default the copy in
# ~/Library/Application Support/swtor-mac-proper/source-cache: the commit is on no branch of
# athei/wine any more), else codeload.github.com.
#
#   scripts/build-ntdll.sh       work dir: $NTDLL_WORK (default /tmp/swtor-on-mac-ntdll)
#
# Needs Xcode, the Command Line Tools with the macOS 26.5 SDK, Rosetta and Homebrew bison. The
# result does not depend on the work dir (no debug info; reproducible link).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/prebuilt/ntdll"
PATCH=ntdll-msync-alert-fd
W="${NTDLL_WORK:-/tmp/swtor-on-mac-ntdll}"
case "$W" in *" "*) echo "NTDLL_WORK must not contain spaces (Wine's makefiles break on them)" >&2; exit 1 ;; esac
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
[ -d "$SDK" ] || { echo "Needs the macOS 26.5 SDK at $SDK (the engine's; Command Line Tools)" >&2; exit 1; }

# the same pins as scripts/build-winemac.sh
WINE_COMMIT="$(sed -n 's/^WINE_COMMIT=//p' scripts/build-winemac.sh)"
WINE_SRC_SHA256="$(sed -n 's/^WINE_SRC_SHA256=//p' scripts/build-winemac.sh)"
WINE_SRC_URL=https://codeload.github.com/athei/wine/tar.gz/$WINE_COMMIT
WINE_SRC_CACHE="${WINE_SRC_CACHE:-$HOME/Library/Application Support/swtor-mac-proper/source-cache/athei-wine-${WINE_COMMIT:0:12}.tar.gz}"
MINGW_URL="$(sed -n 's/^MINGW_URL=//p' scripts/build-winemac.sh)"
MINGW_SHA256="$(sed -n 's/^MINGW_SHA256=//p' scripts/build-winemac.sh)"
ENGINE_NAME="$(sed -n 's/^ENGINE_NAME=//p' src/som.sh)"
ENGINE_URL="$(sed -n 's/^ENGINE_URL=//p' src/som.sh)"
ENGINE_SHA256="$(sed -n 's/^ENGINE_SHA256=//p' src/som.sh)"
ENGINE_NTDLL_SHA256="$(sed -n 's/^ENGINE_NTDLL_SHA256=//p' src/som.sh)"

fetch() { # url sha256 [local copy] -> prints path of the verified download
  local url=$1 sha=$2 dir="$ROOT/.cache/$2" file
  file="$dir/$(basename "$url")"
  if [ ! -f "$file" ]; then
    mkdir -p "$dir"
    if [ -n "${3:-}" ] && [ -f "$3" ] && [ "$(shasum -a 256 "$3" | cut -d' ' -f1)" = "$sha" ]; then
      echo "Using $3" >&2
      cp -c "$3" "$file.part"
    else
      echo "Downloading $url" >&2
      curl -fL --progress-bar -o "$file.part" "$url"
    fi
    mv "$file.part" "$file"
  fi
  echo "$sha  $file" | shasum -a 256 -c --quiet >&2
  echo "$file"
}

src_tgz=$(fetch "$WINE_SRC_URL" "$WINE_SRC_SHA256" "$WINE_SRC_CACHE")
mingw_txz=$(fetch "$MINGW_URL" "$MINGW_SHA256")
engine_txz=$(fetch "$ENGINE_URL" "$ENGINE_SHA256")

mkdir -p "$W"
if ! grep -qx "Wine version 11.0" "$W/src-pristine/VERSION" 2>/dev/null; then
  echo "[ntdll] unpacking the Wine sources"
  rm -rf "$W/src-pristine" "$W/x" && mkdir "$W/x"
  tar -xzf "$src_tgz" -C "$W/x"
  mv "$W/x/wine-$WINE_COMMIT" "$W/src-pristine" && rm -rf "$W/x"
fi
grep -qx "Wine version 11.0" "$W/src-pristine/VERSION"
if [ ! -x "$W/mingw/bin/x86_64-w64-mingw32-clang" ]; then
  echo "[ntdll] unpacking llvm-mingw"
  rm -rf "$W/mingw" && mkdir "$W/mingw"
  tar -xJf "$mingw_txz" -C "$W/mingw" --strip-components 1
fi
E="$W/engine/lib/wine/x86_64-unix/ntdll.so"
if [ ! -f "$E" ]; then
  echo "[ntdll] unpacking ntdll.so from the engine"
  rm -rf "$W/engine" && mkdir -p "$W/engine"
  tar -xJf "$engine_txz" -C "$W/engine" --strip-components 1 wine/lib/wine/x86_64-unix/ntdll.so
fi
[ "$(shasum -a 256 "$E" | cut -d' ' -f1)" = "$ENGINE_NTDLL_SHA256" ] ||
  { echo "The engine's ntdll.so is not the one src/som.sh expects (ENGINE_NTDLL_SHA256)" >&2; exit 1; }

for v in stock patched; do
  rm -rf "$W/src-$v" && cp -c -R "$W/src-pristine" "$W/src-$v"
done
patch -d "$W/src-patched" -p1 --quiet --posix <"patches/$PATCH.patch"

export MACOSX_DEPLOYMENT_TARGET=26.0 SDKROOT="$SDK"
export ZERO_AR_DATE=1 SOURCE_DATE_EPOCH=0
rm -rf "$W/cross-bin" && mkdir "$W/cross-bin"
for t in "$W/mingw/bin/"x86_64-w64-mingw32-* "$W/mingw/bin/"i686-w64-mingw32-*; do
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$t" >"$W/cross-bin/${t##*/}"
  chmod 755 "$W/cross-bin/${t##*/}"
done
PATH="$W/cross-bin:$(brew --prefix bison)/bin:$PATH:$W/mingw/bin"   # flex: /usr/bin's
export PATH
NCPU="$(sysctl -n hw.ncpu)"
# athei's list, with gnutls, sdl (and freetype, which it leaves to configure) off
opts="--enable-archs=i386,x86_64 --with-coreaudio --with-mingw --with-opencl --with-unwind
  --without-gnutls --without-sdl --without-freetype
  --without-alsa --without-capi --without-cups --without-dbus --without-ffmpeg --without-fontconfig
  --without-gettext --without-gphoto --without-gssapi --without-gstreamer --without-hwloc
  --without-inotify --without-krb5 --without-netapi --without-oss --without-pcap --without-pcsclite
  --without-pulse --without-sane --without-udev --without-usb --without-v4l2 --without-vulkan
  --without-wayland --without-x"
for v in stock patched; do
  echo "[ntdll] building $v (log: $W/build-$v/make.log)"
  rm -rf "$W/build-$v" && mkdir "$W/build-$v"
  # ($opts: word splitting on purpose)
  # shellcheck disable=SC2086
  ( cd "$W/build-$v" &&
    arch -x86_64 "$W/src-$v/configure" $opts --host=x86_64-apple-darwin \
      CC="clang -arch x86_64" CROSSCC="clang -arch x86_64" CFLAGS="" \
      x86_64_CC="$W/mingw/bin/x86_64-w64-mingw32-clang" i386_CC="$W/mingw/bin/i686-w64-mingw32-clang" \
      >configure.log 2>&1 &&
    grep -qx '#define HAVE_LIBUNWIND 1' include/config.h && grep -qx '/\* #undef HAVE_PIPE2 \*/' include/config.h &&
    make -j"$NCPU" dlls/ntdll/ntdll.so >make.log 2>&1 ) ||
    { tail -30 "$W/build-$v/configure.log" "$W/build-$v/make.log" 2>/dev/null; exit 1; }
  install -m 755 "$W/build-$v/dlls/ntdll/ntdll.so" "$W/ntdll-$v.so"
done

# Toolchain check (stock rebuild vs the engine's file) and the patch's footprint (patched vs stock)
python3 -I scripts/ntdll-compare.py "$E" "$W/ntdll-stock.so" "$W/ntdll-patched.so"

rm -rf "$OUT" && mkdir -p "$OUT"
# with its symbols, as the engine's (crash reports name the functions); an ad-hoc signature
# (the release signs the app's copy with its Developer ID)
install -m 755 "$W/ntdll-patched.so" "$OUT/ntdll.so"
codesign --force --sign - "$OUT/ntdll.so" 2>/dev/null
cp "$W/src-pristine/COPYING.LIB" "$W/src-pristine/LICENSE" "$OUT/"
cat >"$OUT/VERSION" <<EOF
ntdll.so: Wine's ntdll (x86_64 unix side) for the $ENGINE_NAME engine
sources: athei/wine $WINE_COMMIT (codeload tar.gz sha256 $WINE_SRC_SHA256)
configured as the engine (athei/wine-build build-wine.sh), macOS 26.5 SDK, unsigned sha256 $(shasum -a 256 "$W/ntdll-patched.so" | cut -d' ' -f1)
patch:
  patches/$PATCH.patch sha256 $(shasum -a 256 "patches/$PATCH.patch" | cut -d' ' -f1)
EOF
echo "[ntdll] prebuilt/ntdll: $(cd "$OUT" && find . -type f | sed 's|^\./||' | sort | tr '\n' ' ')"
echo "[ntdll] ntdll.so sha256 $(shasum -a 256 "$OUT/ntdll.so" | cut -d' ' -f1) (unsigned $(shasum -a 256 "$W/ntdll-patched.so" | cut -d' ' -f1)), LC_UUID $(dwarfdump -u "$OUT/ntdll.so" | awk '{ print $2 }')"
