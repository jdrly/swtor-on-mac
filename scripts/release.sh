#!/bin/bash
# Signs, notarizes and packages dist/SWTOR on Mac.app (run ./build.sh first):
#   release/<version>/SWTOR on Mac.app               Developer ID, hardened runtime
#   release/<version>/SWTOR-on-Mac-<version>.dmg     signed, notarized, stapled
# then creates a draft GitHub release v<version> with the DMG.
#
# One notarization: submitting the disk image notarizes the app inside it too; the ticket is
# stapled to the DMG.
#
# Needs the Developer ID Application identity in the keychain, a notarytool keychain profile
# (xcrun notarytool store-credentials swtor-notary --key … --key-id … --issuer …), gh logged
# in, and release notes in Markdown at release-notes/<version>.md.
#
#   scripts/release.sh               sign, notarize, package, draft release
#   scripts/release.sh --sign-only   sign and verify only (for testing the signed app locally)
#   scripts/release.sh --no-notarize sign and package, without notarizing or a release
#   scripts/release.sh --ci          (GitHub Actions) sign, package, notarize, draft release
#   scripts/release.sh --ci-dry-run  (GitHub Actions) the same without a release
#
# Overrides: IDENTITY, NOTARY_PROFILE, or NOTARY_KEY/NOTARY_KEY_ID/NOTARY_ISSUER (an App Store
# Connect API key file instead of the keychain profile, as in CI); RELEASE_DIR (default
# release), RELEASE_NOTES (the notes file).
#
# Sparkle (0.0.2): this is where SWGL on Mac's release.sh also signs Sparkle.framework (its
# Autoupdate, Updater.app, then the framework) and builds appcast.xml with delta updates.
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-}"
case "$MODE" in
  ""|--sign-only|--no-notarize|--ci|--ci-dry-run) ;;
  *) echo "unknown option: $MODE" >&2; exit 2 ;;
esac
IDENTITY="${IDENTITY:-Developer ID Application: Jan Drly (3JT82CY6ZK)}"
PROFILE="${NOTARY_PROFILE:-swtor-notary}"
REPO=jdrly/swtor-on-mac
SRC="dist/SWTOR on Mac.app"
ENT="$PWD/src/entitlements"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$SRC/Contents/Info.plist")"
RELEASE_DIR="${RELEASE_DIR:-release}"
OUT="$RELEASE_DIR/$VERSION"
APP="$OUT/SWTOR on Mac.app"
DMG="$OUT/SWTOR-on-Mac-$VERSION.dmg"
NOTES="${RELEASE_NOTES:-release-notes/$VERSION.md}"
if [ -n "${NOTARY_KEY:-}" ]; then
  notary_auth=(--key "$NOTARY_KEY" --key-id "${NOTARY_KEY_ID:?}" --issuer "${NOTARY_ISSUER:?}")
else
  notary_auth=(--keychain-profile "$PROFILE")
fi

case "$MODE" in
  ""|--ci)
    [ -f "$NOTES" ] || { echo "Missing release notes: $NOTES" >&2; exit 1; }
    gh auth status >/dev/null 2>&1 || { echo "gh is not logged in" >&2; exit 1; }
    ! gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1 || { echo "Release v$VERSION already exists" >&2; exit 1; } ;;
esac

sign() { codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@"; }

# Submits $1 and polls Apple until it is processed (up to 3 hours); prints Apple's log and
# fails unless it was accepted.
notarize() {
  local id status="" deadline=$((SECONDS + 3 * 3600))
  id="$(xcrun notarytool submit "$1" "${notary_auth[@]}" --output-format json | plutil -extract id raw -)"
  echo "  submission $id"
  while [ "$SECONDS" -lt "$deadline" ]; do
    status="$(xcrun notarytool info "$id" "${notary_auth[@]}" --output-format json 2>/dev/null |
      plutil -extract status raw - 2>/dev/null || true)"
    case "$status" in Accepted|Invalid|Rejected) break ;; esac
    sleep 30
  done
  echo "  status: ${status:-unknown}"
  if [ "$status" != Accepted ]; then
    xcrun notarytool log "$id" "${notary_auth[@]}" >&2 || true
    exit 1
  fi
}

echo "[release] $VERSION: copying the app"
rm -rf "$OUT"
mkdir -p "$OUT"
ditto "$SRC" "$APP"
xattr -cr "$APP"

# Inside out: the helpers (they run inside the launcher's Wine start and must pass DYLD_*
# on to Wine), then the app. The d9mt files are Windows DLLs and a Wine unix library that
# Wine loads itself; winemetal.so is signed too, as every Mach-O in a notarized app must be.
echo "[release] signing"
for h in "$APP/Contents/Resources/helpers/"*; do sign --entitlements "$ENT/helpers.plist" "$h"; done
sign "$APP/Contents/Resources/d9mt/winemetal.so"
sign --entitlements "$ENT/app.plist" "$APP"
codesign --verify --strict --deep "$APP"
echo "[release] signature verified: $(codesign -dvv "$APP" 2>&1 | grep -E '^Authority=Developer ID Application' | cut -d= -f2)"
[ "$MODE" = --sign-only ] && exit 0

echo "[release] building the disk image"
stage="$OUT/dmg"
mkdir -p "$stage"
ditto "$APP" "$stage/SWTOR on Mac.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "SWTOR on Mac $VERSION" -srcfolder "$stage" -fs HFS+ -format ULMO "$DMG"
rm -rf "$stage"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
if [ "$MODE" = --no-notarize ]; then
  echo "[release] $DMG ($(du -h "$DMG" | cut -f1)); not notarized (--no-notarize)"
  exit 0
fi
echo "[release] notarizing the disk image"
notarize "$DMG"
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
spctl --assess --type execute --verbose=2 "$APP"

if [ "$MODE" = --ci-dry-run ]; then
  echo "[release] $DMG ($(du -h "$DMG" | cut -f1)); no GitHub release (--ci-dry-run)"
  exit 0
fi
echo "[release] creating the draft GitHub release v$VERSION"
gh release create "v$VERSION" --repo "$REPO" --draft --title "SWTOR on Mac $VERSION" \
  --notes-file "$NOTES" "$DMG"
echo "[release] $DMG ($(du -h "$DMG" | cut -f1)); publish the draft to release it"
