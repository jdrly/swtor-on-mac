#!/bin/bash
# Builds "dist/SWTOR on Mac.app": a small SwiftUI app that installs SWTOR on Mac on top of the
# official SWTOR Mac app (see README.md). The app bundles only its own pieces:
#   Contents/MacOS/SWTORonMac          the window, menus, Settings and updates (src/native), arm64
#   Contents/Frameworks/Sparkle.framework  app updates (Sparkle 2, pinned below)
#   Contents/Resources/som.sh          install/uninstall/status/settings logic (src/som.sh)
#   Contents/Resources/collect-logs.sh "Collect Logs…" (src/collect-logs.sh)
#   Contents/Resources/session-report.sh  a game session in short (scripts/session-report.sh;
#                                      in Collect Logs, and for Terminal)
#   Contents/Resources/wine-wrapper.sh the wrapper template installed into Broadsword's Wine
#   Contents/Resources/helpers/        hold-launcher, setsid-exec (universal)
#   Contents/Resources/d9mt/           prebuilt d9mt (scripts/build-d9mt.sh)
#   Contents/Resources/wine/winemac.so Wine's Mac driver with the PhysicalKeyboard option
#                                      (scripts/build-winemac.sh, patches/), for the engine
#   Contents/Resources/Licenses/       licenses of the app and the bundled components
# The Wine engine and its libraries are not bundled: som.sh downloads them at install time
# from Sikarugir's official releases (pinned URL + sha256 in src/som.sh). Only the engine's
# Mac driver comes in a patched build of its own (Resources/wine).
#
# Built with the macOS 27 SDK (Xcode 27; the design follows the SDK the app links against)
# for macOS 26.0 and later.
#
#   ./build.sh                 build into dist/, ad-hoc signed
#   ./build.sh --install       also copy the app to /Applications
#
# Signing for distribution (Developer ID, hardened runtime, notarization) is
# scripts/release.sh, which re-signs a copy of dist/ inside out.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"

# SWTOR_ON_MAC_VERSION overrides the version for test builds.
APP_VERSION=${SWTOR_ON_MAC_VERSION:-0.0.6-dev.4}

# Development builds: a version with a prerelease suffix, X.Y.Z-dev.N. They are published only
# as GitHub pre-releases, never in the appcast. CFBundleShortVersionString is the version as is;
# CFBundleVersion (what Sparkle compares) is numeric and sorts above the previous release and
# below X.Y.Z: 0.0.6-dev.N -> 0.0.5.(1000+N). Sparkle's standard comparator orders
# 0.0.5 < 0.0.5.1001 < 0.0.5.1002 < 0.0.6, so a dev build is never offered 0.0.5 again and
# is offered the public 0.0.6 once that is out. Releases: CFBundleVersion = the version.
bundle_version() {
  local v=$1 core n x y z
  case "$v" in
    *-dev.*) core=${v%%-*}; n=${v##*-dev.} ;;
    *-*) echo "Unsupported version $v (X.Y.Z or X.Y.Z-dev.N)" >&2; return 1 ;;
    *) echo "$v"; return ;;
  esac
  IFS=. read -r x y z <<<"$core"
  case "$x$y$z$n" in *[!0-9]*|'') echo "Unsupported version $v" >&2; return 1 ;; esac
  if [ "$z" -gt 0 ]; then echo "$x.$y.$((z - 1)).$((1000 + n))"
  elif [ "$y" -gt 0 ]; then echo "$x.$((y - 1)).9999.$((1000 + n))"
  else echo "$((x - 1)).9999.9999.$((1000 + n))"; fi
}
BUNDLE_VERSION=$(bundle_version "$APP_VERSION")
case "$APP_VERSION" in *-*) CHANNEL=dev ;; *) CHANNEL=release ;; esac
APP_AUTHOR="Jan Drlý"
GITHUB_URL=https://github.com/jdrly
REPO_URL=https://github.com/jdrly/swtor-on-mac
MACOS_MIN=26.0
CACHE="$ROOT/.cache"
APP="$ROOT/dist/SWTOR on Mac.app"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# Pinned dependencies. Bump the version and sha256 together.
SPARKLE_VERSION=2.10.0
SPARKLE_URL=https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz
SPARKLE_SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c

fetch() { # url sha256 -> prints path of the verified download
  local url=$1 sha=$2 dir="$CACHE/$2" file
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

sdk="$(xcrun --sdk macosx --show-sdk-version)"
case "$sdk" in 2[7-9]*|[3-9]*) ;; *) echo "Needs the macOS 27 SDK (Xcode 27); found $sdk" >&2; exit 1 ;; esac

D9=prebuilt/d9mt
for f in d3d9.dll winemetal.dll winemetal.so VERSION LICENSE THIRD_PARTY_NOTICES.md bridge/COPYING.LIB; do
  [ -f "$D9/$f" ] || { echo "Missing $D9/$f; run scripts/build-d9mt.sh" >&2; exit 1; }
done
WM=prebuilt/winemac
for f in winemac.so VERSION COPYING.LIB LICENSE; do
  [ -f "$WM/$f" ] || { echo "Missing $WM/$f; run scripts/build-winemac.sh" >&2; exit 1; }
done

# Sparkle (app updates, as in SWGL on Mac): the framework goes into the app, its tools
# (generate_appcast, BinaryDelta, generate_keys) are used from here by scripts/release.sh.
SPARKLE="$CACHE/sparkle-$SPARKLE_VERSION"
if [ ! -d "$SPARKLE/Sparkle.framework" ]; then
  sparkle_txz=$(fetch "$SPARKLE_URL" "$SPARKLE_SHA256")
  rm -rf "$SPARKLE.part" && mkdir -p "$SPARKLE.part"
  tar -xJf "$sparkle_txz" -C "$SPARKLE.part"
  rm -rf "$SPARKLE" && mv "$SPARKLE.part" "$SPARKLE"
fi

echo "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
R="$APP/Contents/Resources"
sed -e "s/@VERSION@/$APP_VERSION/g" -e "s/@BUILD@/$BUNDLE_VERSION/g" -e "s/@CHANNEL@/$CHANNEL/g" \
  src/Info.plist >"$APP/Contents/Info.plist"
# Development builds: no automatic update checks (Sparkle's, and the wrapper's via som.sh);
# SWTOR on Mac > Check for Updates… still works and offers only newer versions (see above).
[ "$CHANNEL" = release ] || plutil -replace SUEnableAutomaticChecks -bool NO "$APP/Contents/Info.plist"
plutil -lint -s "$APP/Contents/Info.plist"
printf 'APPL????' >"$APP/Contents/PkgInfo"

NB="$CACHE/native-build"
rm -rf "$NB" && mkdir -p "$NB"
swiftc -parse-as-library -O -target "arm64-apple-macos$MACOS_MIN" -F "$SPARKLE" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$APP/Contents/MacOS/SWTORonMac" src/native/*.swift
# Sparkle without its XPC services (they are only for sandboxed apps); its license ships with it.
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/XPCServices" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"

install -m 755 src/som.sh "$R/som.sh"
install -m 755 src/collect-logs.sh "$R/collect-logs.sh"
install -m 755 scripts/session-report.sh "$R/session-report.sh"
install -m 644 src/wine-wrapper.sh "$R/wine-wrapper.sh"
install -m 644 src/dxvk.conf "$R/dxvk.conf"

# Helpers the wrapper runs from Broadsword's Wine/bin-real. Universal: the launcher and its
# Wine run under Rosetta.
mkdir -p "$R/helpers"
clang -O2 -arch x86_64 -arch arm64 -mmacosx-version-min=$MACOS_MIN -fobjc-arc -framework AppKit \
  -o "$R/helpers/hold-launcher" src/helpers/hold-launcher/hold_launcher.c src/helpers/hold-launcher/hide_app.m
clang -O2 -arch x86_64 -arch arm64 -mmacosx-version-min=$MACOS_MIN \
  -o "$R/helpers/setsid-exec" src/helpers/setsid-exec/setsid_exec.c

# d9mt: d3d9.dll for the app's prefix, the winemetal bridge for the app's engine copy
mkdir -p "$R/d9mt"
install -m 644 "$D9/d3d9.dll" "$R/d9mt/d3d9.dll"
install -m 644 "$D9/winemetal.dll" "$R/d9mt/winemetal.dll"
install -m 755 "$D9/winemetal.so" "$R/d9mt/winemetal.so"
install -m 644 "$D9/VERSION" "$R/d9mt/VERSION"

# Wine's Mac driver with the PhysicalKeyboard option; the installer puts it into its engine
# copy while "Game keys by keyboard position" is on
mkdir -p "$R/wine"
install -m 755 "$WM/winemac.so" "$R/wine/winemac.so"

# Licenses: the app's own (zlib), the overview of what is bundled and what is downloaded
# (THIRD_PARTY_NOTICES.md), d9mt's (zlib; its bridge LGPL-2.1-or-later; third parties), Sparkle's
L="$R/Licenses"
mkdir -p "$L/d9mt/bridge"
cp LICENSE "$L/SWTOR-on-Mac-LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$L/THIRD_PARTY_NOTICES.md"
cp -R "$D9/LICENSE" "$D9/LICENSES" "$D9/THIRD_PARTY_NOTICES.md" "$L/d9mt/"
cp "$D9/bridge/LICENSE" "$D9/bridge/COPYING.LIB" "$L/d9mt/bridge/"
mkdir -p "$L/sparkle"
cp "$SPARKLE/LICENSE" "$L/sparkle/LICENSE"
mkdir -p "$L/winemac"
cp "$WM/COPYING.LIB" "$WM/LICENSE" "$WM/VERSION" patches/winemac-physical-keys.patch "$L/winemac/"
cat >"$L/README.txt" <<EOF
SWTOR on Mac $APP_VERSION - licenses

SWTOR on Mac's own code (the app, som.sh, the Wine wrapper, hold-launcher, setsid-exec):
zlib license, see SWTOR-on-Mac-LICENSE.txt. What the app bundles and what it downloads at
install time: THIRD_PARTY_NOTICES.md.

d9mt ($(cat "$D9/VERSION")), https://github.com/jdrly/d9mt (based on neo773/d9mt-v2):
d3d9.dll is zlib/libpng (d9mt/LICENSE); the winemetal bridge (winemetal.so, winemetal.dll)
is derived from DXMT and licensed LGPL-2.1-or-later (d9mt/bridge/). Its complete source is
https://github.com/jdrly/d9mt/tree/$(cat "$D9/VERSION")/bridge. Other components and their
licenses: d9mt/THIRD_PARTY_NOTICES.md and d9mt/LICENSES/.

Sparkle $SPARKLE_VERSION (app updates), https://sparkle-project.org: MIT-style license, see
sparkle/LICENSE.

wine/winemac.so: Wine's Mac driver (dlls/winemac.drv, x86_64 unix side) from CodeWeavers'
CrossOver 24.0.7 sources, with SWTOR on Mac's patch for the PhysicalKeyboard option ("Game keys
by keyboard position"): LGPL-2.1-or-later, see winemac/COPYING.LIB and winemac/LICENSE. The
patch is winemac/winemac-physical-keys.patch (also
$REPO_URL/blob/v$APP_VERSION/patches/winemac-physical-keys.patch); the
sources it applies to: https://media.codeweavers.com/pub/crossover/source/crossover-sources-24.0.7.tar.gz
(https://www.codeweavers.com/crossover/source); build script:
$REPO_URL/blob/v$APP_VERSION/scripts/build-winemac.sh.

Not included in this app: the Wine engine (CrossOver 24.0.7 sources by CodeWeavers, built by
Sikarugir, LGPL-2.1-or-later) and its libraries are downloaded at install time from
https://github.com/Sikarugir-App (Engines and Template releases).
EOF

# feed: Sparkle's feed, also read by the Wine wrapper's daily update check (via som.sh)
# channel: release, or dev (development build: Debug Logging on by default, no automatic
# update checks; som.sh and the app read it)
printf 'version=%s\nbuild=%s\nchannel=%s\nauthor=%s\ngithub=%s\nrepo=%s\nfeed=%s\n' "$APP_VERSION" "$BUNDLE_VERSION" \
  "$CHANNEL" "$APP_AUTHOR" "$GITHUB_URL" "$REPO_URL" "$(plutil -extract SUFeedURL raw src/Info.plist)" >"$R/app.properties"
printf 'app %s\nd9mt %s\nengine %s\nframeworks %s\nwinemac %s\nsparkle %s\nsdk %s\n' "$APP_VERSION" "$(cat "$D9/VERSION")" \
  "$(sed -n 's/^ENGINE_NAME=//p' src/som.sh)" "$(sed -n 's/^FW_NAME=//p' src/som.sh)" \
  "physical-keys patch $(shasum -a 256 patches/winemac-physical-keys.patch | cut -c1-12)" "$SPARKLE_VERSION" "$sdk" >"$R/VERSIONS"

iconset="$CACHE/AppIcon.iconset"
rm -rf "$iconset"
swift src/make-icon.swift "$iconset"
iconutil -c icns "$iconset" -o "$R/AppIcon.icns"

xattr -cr "$APP"
# Ad-hoc signatures (Developer ID: scripts/release.sh). The helpers keep their own signature
# when the installer copies them into Broadsword's Wine folder.
for h in "$R/helpers/"*; do codesign --force --sign - "$h"; done
# Sparkle without its XPC services no longer matches its own signature (release.sh signs it
# for real, in the same order).
fw="$APP/Contents/Frameworks/Sparkle.framework"
for f in "$fw/Versions/B/Autoupdate" "$fw/Versions/B/Updater.app" "$fw"; do codesign --force --sign - "$f"; done
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($(du -sh "$APP" | cut -f1))"

if [ "${1:-}" = --install ]; then
  rm -rf "/Applications/SWTOR on Mac.app"
  ditto "$APP" "/Applications/SWTOR on Mac.app"
  echo "Installed to /Applications/SWTOR on Mac.app"
fi
