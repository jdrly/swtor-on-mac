#!/bin/bash
# Builds scripts/ui-snapshot.swift with the app's sources into a small bundle (the app's fonts,
# a fake som.sh for Settings) and runs it on a temporary virtual display (tools/vd/with-vd.sh of
# swtor-mac-proper), so no window ever shows on the main display.
#
#   scripts/ui-snapshot.sh shots <out dir>
#   scripts/ui-snapshot.sh measure <animating|paused|game|closed> <seconds>
#   scripts/ui-snapshot.sh bench <frames>        (no window: runs without the virtual display)
#   scripts/ui-snapshot.sh sweep [seconds] [rounds]  the warp's rendering variants against each
#                                                other (CPU, GPU, frames), each round in a new order;
#                                                default 20 s, 2 rounds: about 10 minutes
#   scripts/ui-snapshot.sh findcost [seconds] [rounds]  where a frame's fixed cost comes from: an
#                                                empty canvas on the same clock, the window without
#                                                glass buttons (the fresh state), as is, 20 fps;
#                                                default 20 s, 2 rounds: about 5 minutes
#   scripts/ui-snapshot.sh idlecheck            idleStop at 5 s: a window in front without input
#                                                draws until 5 + 2 s after it opens, then nothing
#                                                (counted from 4 s on: about 70 frames in 20 s)
#   scripts/ui-snapshot.sh stillcheck           the window as 0.1.4 ships it (the warp still), in
#                                                front, no input: one draw at most, then nothing
#   scripts/ui-snapshot.sh alertkeys            which button Return and Esc press in Collect Logs…'s alert
#   scripts/ui-snapshot.sh build                 only builds .cache/ui-snapshot/UISnapshot.app, for
#                                                several runs in one with-vd.sh call
#
# VD: the with-vd.sh to use (default ~/Development/personal/swtor-mac-proper/tools/vd/with-vd.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
VD=${VD:-$HOME/Development/personal/swtor-mac-proper/tools/vd/with-vd.sh}
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SPARKLE=$(ls -d "$ROOT"/.cache/sparkle-*/ 2>/dev/null | head -1)
[ -d "$SPARKLE/Sparkle.framework" ] || { echo "Sparkle not in .cache: run ./build.sh once" >&2; exit 1; }

B="$ROOT/.cache/ui-snapshot/UISnapshot.app/Contents"
rm -rf "$ROOT/.cache/ui-snapshot"
mkdir -p "$B/MacOS" "$B/Resources/Fonts" "$B/Frameworks"
cat >"$B/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>cz.jandrly.swtoronmac.uisnapshot</string>
<key>CFBundleExecutable</key><string>ui-snapshot</string>
<key>CFBundleShortVersionString</key><string>0.1.3</string>
<key>ATSApplicationFontsPath</key><string>Fonts</string>
<key>LSUIElement</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIconName</key><string>AppIcon</string>
</dict></plist>
EOF
# the app's icon (as build.sh makes it), for the alerts
xcrun actool "$ROOT/src/AppIcon.icon" --compile "$B/Resources" --platform macosx \
  --minimum-deployment-target "$(plutil -extract LSMinimumSystemVersion raw src/Info.plist)" \
  --app-icon AppIcon --output-partial-info-plist "$ROOT/.cache/ui-snapshot/icon.plist" >/dev/null
install -m 644 src/fonts/*.ttf "$B/Resources/Fonts/"
printf 'version=0.1.3\nauthor=Jan Drlý\ngithub=https://github.com/jdrly\nrepo=https://github.com/jdrly/swtor-on-mac\n' >"$B/Resources/app.properties"
printf 'app 0.1.3\nd9mt 2a1bc00\nengine cx-26.3.0-8\n' >"$B/Resources/VERSIONS"
# Settings reads its values through som.sh; this one only prints them
cat >"$B/Resources/som.sh" <<'EOF'
case "$1" in
  settings) printf 'installed=yes\nrunning=no\nretina=on\nvsync=off\nmemory=auto\ngamemode=on\nhud=on\nhudpos=topcenter\nphyskeys=off\nrawmouse=on\nmousespeed=1\nupdates=on\ndebug=off\n' ;;
  *) echo "@error ui-snapshot: no $1" ;;
esac
EOF
ditto "$SPARKLE/Sparkle.framework" "$B/Frameworks/Sparkle.framework"
swiftc -parse-as-library -O -D SWTOR_SNAPSHOT -target arm64-apple-macos26.0 -F "$SPARKLE" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$B/MacOS/ui-snapshot" src/native/*.swift scripts/ui-snapshot.swift
codesign --force --sign - "$B/Frameworks/Sparkle.framework" "$B/MacOS/ui-snapshot" 2>/dev/null

case "${1:-}" in
  build) echo "$B/MacOS/ui-snapshot" ;;
  sweep)
    secs=${2:-20} rounds=${3:-2}
    # current; Core Graphics; half resolution; 24 fps; the top part only; and combinations
    variants=("" "metal=0" "res=0.5" "fps=24" "res=0.5 fps=24" "res=0.5 height=0.7" "res=0.5 fps=24 height=0.7"
              "res=0.5 height=0.45" "res=0.5 fps=24 height=0.45" "res=0.5 metal=0")
    list=$(for r in $(seq "$rounds"); do printf '%s\n' "${variants[@]}" | awk -v r="$r" 'BEGIN{srand(r)} {print rand() "\t" $0}' | sort | cut -f2-; echo "@paused"; done)
    exec "$VD" $(( (secs + 8) * rounds * 11 + 120 )) bash -c '
      while IFS= read -r v; do
        if [ "$v" = @paused ]; then "$0" measure paused "$1"; else WARP="$v" "$0" measure animating "$1"; fi
      done <<<"$2"' "$B/MacOS/ui-snapshot" "$secs" "$list" ;;
  findcost)
    secs=${2:-20} rounds=${3:-2}
    exec "$VD" $(( (secs + 8) * rounds * 5 + 120 )) bash -c '
      for r in $(seq "$2"); do
        "$0" measure empty "$1"
        MEASURE_STATE=fresh "$0" measure animating "$1"
        "$0" measure animating "$1"
        WARP="fps=20" "$0" measure animating "$1"
        "$0" measure paused "$1"
      done' "$B/MacOS/ui-snapshot" "$secs" "$rounds" ;;
  idlecheck) WARP="idle=5" exec "$VD" 120 "$B/MacOS/ui-snapshot" measure idle 20 ;;
  stillcheck) exec "$VD" 120 "$B/MacOS/ui-snapshot" measure still 20 ;;
  bench) exec "$B/MacOS/ui-snapshot" "$@" ;;
  *) exec "$VD" 600 "$B/MacOS/ui-snapshot" "$@" ;;
esac
