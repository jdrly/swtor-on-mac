#!/bin/bash
# End-to-end test of app updates (Sparkle) with a local feed: two Developer ID builds,
# 0.0.1 and 0.0.2 (signed, not notarized; ad-hoc builds cannot update each other), a feed
# with a delta update on http://127.0.0.1:8000, and 0.0.1 installed outside /Applications.
#
#   scripts/test-update.sh prepare   build both versions and the feed (~10 min; leaves no
#                                    app in dist/, run ./build.sh afterwards)
#   scripts/test-update.sh install   copy 0.0.1 to $TEST_DIR/Apps, point the app's feed here
#   scripts/test-update.sh serve     serve the feed on http://127.0.0.1:8000 (Ctrl-C stops)
#   scripts/test-update.sh status    version and signature of the installed test app
#   scripts/test-update.sh cleanup   remove the feed override (the app reads the real feed again)
#
# The test signs with its own throwaway EdDSA key ($TEST_DIR/test-ed-key, put into the test
# builds' SUPublicEDKey), so the real key in the keychain is not needed.
# TEST_DIR defaults to work/update-test; FROM and TO override the versions.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
TEST_DIR="${TEST_DIR:-$ROOT/work/update-test}"
FROM="${FROM:-0.0.1}"
TO="${TO:-0.0.2}"
PORT=8000
DOMAIN=cz.jandrly.swtoronmac
APP_NAME="SWTOR on Mac.app"
INSTALLED="$TEST_DIR/Apps/$APP_NAME"

prepare() {
  mkdir -p "$TEST_DIR"
  local key="$TEST_DIR/test-ed-key" pub="$TEST_DIR/test-ed-key.pub" v
  if [ ! -s "$key" ]; then
    # A 32-byte Ed25519 seed, base64: the key file format of Sparkle's generate_keys -x.
    swift - >"$key.tmp" <<'EOF'
import CryptoKit
let key = Curve25519.Signing.PrivateKey()
print(key.rawRepresentation.base64EncodedString())
print(key.publicKey.rawRepresentation.base64EncodedString())
EOF
    sed -n 1p "$key.tmp" >"$key"; sed -n 2p "$key.tmp" >"$pub"; rm -f "$key.tmp"
    chmod 600 "$key"
  fi
  rm -rf "$TEST_DIR/release" "$TEST_DIR/www"
  for v in "$FROM" "$TO"; do
    echo "=== building $v"
    SWTOR_ON_MAC_VERSION="$v" ./build.sh
    plutil -replace SUPublicEDKey -string "$(cat "$pub")" "dist/$APP_NAME/Contents/Info.plist"
    mkdir -p "$TEST_DIR/notes"
    printf '## SWTOR on Mac %s (test build)\n\n- Local update test, served from 127.0.0.1.\n' "$v" >"$TEST_DIR/notes/$v.md"
    RELEASE_DIR="$TEST_DIR/release" DOWNLOAD_URL_PREFIX="http://127.0.0.1:$PORT/" ED_KEY_FILE="$key" \
      RELEASE_NOTES="$TEST_DIR/notes/$v.md" scripts/release.sh --no-notarize
  done
  rm -rf "dist/$APP_NAME"  # a test build must not end up in a real release
  mkdir -p "$TEST_DIR/www"
  cp -c "$TEST_DIR/release/$TO/appcast.xml" "$TEST_DIR/release/$TO/SWTOR-on-Mac-$TO.dmg" "$TEST_DIR/www/"
  cp -c "$TEST_DIR/release/$TO/"*.delta "$TEST_DIR/www/"
  echo "=== feed in $TEST_DIR/www:"
  ls -l "$TEST_DIR/www"
}

install_app() {
  [ -d "$TEST_DIR/release/$FROM/$APP_NAME" ] || { echo "Run prepare first" >&2; exit 1; }
  mkdir -p "$TEST_DIR/Apps"
  rm -rf "$INSTALLED"
  ditto "$TEST_DIR/release/$FROM/$APP_NAME" "$INSTALLED"
  defaults write "$DOMAIN" SWTORUpdateFeedURL "http://127.0.0.1:$PORT/appcast.xml"
  # Sparkle remembers skipped versions and the last check per app: start clean.
  for k in SUSkippedVersion SUSkippedMajorVersion SUSkippedMajorSubreleaseVersion SULastCheckTime; do
    defaults delete "$DOMAIN" "$k" 2>/dev/null || true
  done
  echo "Installed $FROM: $INSTALLED"
  echo "Feed override: $(defaults read "$DOMAIN" SWTORUpdateFeedURL)"
}

status() {
  plutil -extract CFBundleShortVersionString raw "$INSTALLED/Contents/Info.plist"
  codesign --verify --strict --deep "$INSTALLED" && echo "signature valid"
  codesign -dvv "$INSTALLED" 2>&1 | grep -E '^Authority=Developer ID Application' || true
}

case "${1:-}" in
  prepare) prepare ;;
  install) install_app ;;
  serve)
    echo "Serving $TEST_DIR/www on http://127.0.0.1:$PORT (Ctrl-C stops)"
    exec python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$TEST_DIR/www" ;;
  status) status ;;
  cleanup)
    defaults delete "$DOMAIN" SWTORUpdateFeedURL 2>/dev/null || true
    echo "Feed override removed. The test app is in $TEST_DIR/Apps; delete $TEST_DIR when done." ;;
  *) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
