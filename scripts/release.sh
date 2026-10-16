#!/bin/bash
# Signs, notarizes and packages dist/SWTOR on Mac.app (run ./build.sh first), and prepares the
# update feed for Sparkle (src/native/Updates.swift), as in SWGL on Mac:
#   release/<version>/SWTOR on Mac.app                   Developer ID, hardened runtime
#   release/<version>/SWTOR-on-Mac-<version>.dmg         signed, notarized, stapled
#   release/<version>/SWTOR-on-Mac-<version>-from-<old>.delta   delta updates from older versions
#   release/<version>/appcast.xml                       the feed, with only this version
#   release/updates/                                    DMGs of this and the 5 previous versions
# then creates a draft GitHub release v<version> with the DMG, the deltas and appcast.xml.
# Publishing the draft makes the update live: the app reads
# https://github.com/jdrly/swtor-on-mac/releases/latest/download/appcast.xml.
#
# One notarization: submitting the disk image notarizes the app inside it too (Gatekeeper
# looks its ticket up online when the app is first opened); the ticket is stapled to the DMG.
#
# Needs the Developer ID Application identity in the keychain, a notarytool keychain profile
# (default swgl-notary: Jan's App Store Connect API key, the same team as SWGL on Mac;
# xcrun notarytool store-credentials <name> --key … --key-id … --issuer …), Sparkle's EdDSA
# key in the login keychain (Sparkle's generate_keys, the same key as SWGL on Mac; build.sh
# unpacks the tools into .cache/sparkle-<version>/bin), gh logged in, and release notes in
# Markdown at release-notes/<version>.md (they go into the appcast and the GitHub release).
#
#   scripts/release.sh               sign, notarize, package, feed, draft release
#   scripts/release.sh --sign-only   sign and verify only (for testing the signed app locally)
#   scripts/release.sh --no-notarize sign, package and build the feed, without notarizing or a
#                                    GitHub release (local dry runs and update tests)
#   scripts/release.sh --no-release  sign, notarize, staple and build the feed, without a GitHub
#                                    release (before the repository exists, or to look first)
#
# Releases from GitHub Actions (.github/workflows/release.yml) come in two halves, so
# Sparkle's EdDSA key never leaves Jan's Mac:
#   scripts/release.sh --ci          (CI) sign, package, notarize, and create the draft release
#                                    with the DMG only
#   scripts/release.sh --ci-dry-run  (CI) the same without a release (the workflow keeps the DMG
#                                    as a short-lived artifact)
#   scripts/release.sh --feed <ver>  (Mac) download the notarized DMG from the draft release,
#                                    build and check the feed, and upload appcast.xml and the
#                                    deltas to the draft
#
# Overrides: IDENTITY, NOTARY_PROFILE, or NOTARY_KEY/NOTARY_KEY_ID/NOTARY_ISSUER (an App Store
# Connect API key file instead of the keychain profile, as in CI); RELEASE_DIR (default
# release), DOWNLOAD_URL_PREFIX (where the appcast points, default the version's GitHub
# release), ED_KEY_FILE (a private EdDSA key file instead of the keychain, for test keys),
# RELEASE_NOTES (the notes file).
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-}"
case "$MODE" in
  ""|--sign-only|--no-notarize|--no-release|--ci|--ci-dry-run) ;;
  --feed) [ -n "${2:-}" ] || { echo "usage: $0 --feed <version>" >&2; exit 2; } ;;
  *) echo "unknown option: $MODE" >&2; exit 2 ;;
esac
IDENTITY="${IDENTITY:-Developer ID Application: Jan Drly (3JT82CY6ZK)}"
PROFILE="${NOTARY_PROFILE:-swgl-notary}"
REPO=jdrly/swtor-on-mac
SRC="dist/SWTOR on Mac.app"
ENT="$PWD/src/entitlements"
if [ "$MODE" = --feed ]; then
  VERSION="$2"
else
  VERSION="$(plutil -extract CFBundleShortVersionString raw "$SRC/Contents/Info.plist")"
fi
RELEASE_DIR="${RELEASE_DIR:-release}"
OUT="$RELEASE_DIR/$VERSION"
UPDATES="$RELEASE_DIR/updates"
APP="$OUT/SWTOR on Mac.app"
DMG="$OUT/SWTOR-on-Mac-$VERSION.dmg"
NOTES="${RELEASE_NOTES:-release-notes/$VERSION.md}"
URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/$REPO/releases/download/v$VERSION/}"
FW_REL="Contents/Frameworks/Sparkle.framework"
SPARKLE_BIN="$PWD/.cache/sparkle-$(sed -n 's/^SPARKLE_VERSION=//p' build.sh)/bin"
if [ -n "${NOTARY_KEY:-}" ]; then
  notary_auth=(--key "$NOTARY_KEY" --key-id "${NOTARY_KEY_ID:?}" --issuer "${NOTARY_ISSUER:?}")
else
  notary_auth=(--keychain-profile "$PROFILE")
fi

case "$MODE" in
  ""|--no-notarize|--no-release|--feed)
    [ -x "$SPARKLE_BIN/generate_appcast" ] || { echo "Missing $SPARKLE_BIN; run ./build.sh" >&2; exit 1; } ;;
esac
if [ "$MODE" != --sign-only ] && [ "$MODE" != --ci-dry-run ]; then
  if [ ! -f "$NOTES" ]; then
    [ "$MODE" = --no-notarize ] || { echo "Missing release notes: $NOTES" >&2; exit 1; }
    echo "[release] note: no release notes ($NOTES)"
  fi
fi
case "$MODE" in
  ""|--ci)
    gh auth status >/dev/null 2>&1 || { echo "gh is not logged in" >&2; exit 1; }
    ! gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1 || { echo "Release v$VERSION already exists" >&2; exit 1; } ;;
  --feed)
    [ "$(gh release view "v$VERSION" --repo "$REPO" --json isDraft --jq .isDraft 2>/dev/null)" = true ] ||
      { echo "No draft release v$VERSION (the CI workflow creates it)" >&2; exit 1; } ;;
esac

sign() { codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@"; }

# Submits $1 and polls Apple until it is processed (retrying through network errors, up to
# 3 hours); prints Apple's log and fails unless it was accepted.
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

# Mounts disk image $1 read-only at directory $2.
attach() {
  # diskutil image (macOS 27) replaces the deprecated hdiutil attach.
  if diskutil image attach --readOnly --nobrowse --mountPoint "$2" "$1" >/dev/null 2>&1; then :
  else hdiutil attach -quiet -readonly -nobrowse -noverify -mountpoint "$2" "$1"; fi
}
detach() { hdiutil detach -quiet "$1" || hdiutil detach -quiet -force "$1"; }

# Copies, signs and packages the app into $DMG, and notarizes it unless --no-notarize.
package() {
  echo "[release] $VERSION: copying the app"
  rm -rf "$OUT"
  mkdir -p "$OUT"
  ditto "$SRC" "$APP"
  xattr -cr "$APP"

  # Inside out: the helpers (they run inside the launcher's Wine start and must pass DYLD_*
  # on to Wine: helpers.plist), d9mt's winemetal.so (a Wine unix library Wine loads itself;
  # every Mach-O of a notarized app is signed), Sparkle in its documented order (Autoupdate,
  # Updater.app, the framework, each with the hardened runtime and no --deep; build.sh removed
  # its XPC services), then the app (app.plist: no exceptions).
  echo "[release] signing nested code"
  local h fw stage
  for h in "$APP/Contents/Resources/helpers/"*; do sign --entitlements "$ENT/helpers.plist" "$h"; done
  sign "$APP/Contents/Resources/d9mt/winemetal.so"
  fw="$APP/$FW_REL"
  sign "$fw/Versions/B/Autoupdate"
  sign "$fw/Versions/B/Updater.app"
  sign "$fw"
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
    echo "[release] not notarized (--no-notarize)"
  else
    echo "[release] notarizing the disk image"
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
    spctl --assess --type execute --verbose=2 "$APP"
  fi
}

# --feed: the notarized DMG from the draft release, checked, and the app inside it.
fetch_draft() {
  echo "[release] $VERSION: downloading the DMG from the draft release"
  rm -rf "$OUT"
  mkdir -p "$OUT"
  gh release download "v$VERSION" --repo "$REPO" --pattern "${DMG##*/}" --dir "$OUT"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  local mnt
  mnt="$(mktemp -d)"
  attach "$DMG" "$mnt"
  ditto "$mnt/SWTOR on Mac.app" "$APP"
  detach "$mnt"
  rm -rf "$mnt"
  spctl --assess --type execute --verbose=2 "$APP"
  [ "$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")" = "$VERSION" ] ||
    { echo "The DMG's app is not version $VERSION" >&2; exit 1; }
}

if [ "$MODE" = --feed ]; then
  fetch_draft
else
  package
fi

case "$MODE" in
  --ci-dry-run)
    echo "[release] $DMG ($(du -h "$DMG" | cut -f1)); no GitHub release (--ci-dry-run)"
    exit 0 ;;
  --ci)
    echo "[release] creating the draft GitHub release v$VERSION (DMG only)"
    gh release create "v$VERSION" --repo "$REPO" --draft --title "SWTOR on Mac $VERSION" \
      --notes-file "$NOTES" "$DMG"
    echo "[release] draft v$VERSION created; on the Mac, run scripts/release.sh --feed $VERSION"
    exit 0 ;;
esac

# The update feed. release/updates keeps the DMGs of this and the 5 previous versions, the
# bases of the delta updates. generate_appcast runs on a copy of them, so the feed starts
# afresh every time and holds only this version (it would rewrite older entries' URLs to
# this release's).
echo "[release] building the update feed"
mkdir -p "$UPDATES"
rm -f "$UPDATES/${DMG##*/}"
cp -c "$DMG" "$UPDATES/"
kept=()
while IFS= read -r v; do kept+=("$v"); done < <(ls "$UPDATES" | sed -n 's/^SWTOR-on-Mac-\(.*\)\.dmg$/\1/p' | sort -V)
for ((i = 0; i < ${#kept[@]} - 6; i++)); do rm -f "$UPDATES/SWTOR-on-Mac-${kept[i]}.dmg"; done
feed="$OUT/feed"
rm -rf "$feed"
mkdir -p "$feed"
cp -c "$UPDATES"/SWTOR-on-Mac-*.dmg "$feed/"
[ -f "$NOTES" ] && cp "$NOTES" "$feed/SWTOR-on-Mac-$VERSION.md"
"$SPARKLE_BIN/generate_appcast" ${ED_KEY_FILE:+--ed-key-file "$ED_KEY_FILE"} \
  --maximum-versions 1 --maximum-deltas 5 --embed-release-notes \
  --download-url-prefix "$URL_PREFIX" "$feed"
# Deltas are named "SWTOR on Mac<new>-<old>.delta"; GitHub replaces spaces in asset names, so
# rename them and their URLs. (The appcast itself is not signed, so it may be edited.)
cp "$feed/appcast.xml" "$OUT/appcast.xml"
deltas=()
for d in "$feed"/*.delta; do
  [ -e "$d" ] || continue
  pair="${d##*/SWTOR on Mac}"; pair="${pair%.delta}"   # <new>-<old>
  new="${pair%%-*}"; old="${pair#*-}"
  name="SWTOR-on-Mac-$new-from-$old.delta"
  mv "$d" "$OUT/$name"
  sed -i '' "s|SWTOR%20on%20Mac$new-$old\.delta\"|$name\"|" "$OUT/appcast.xml"
  deltas+=("$OUT/$name")
done
rm -rf "$feed"
xmllint --noout "$OUT/appcast.xml"
! grep -q 'SWTOR%20on%20Mac' "$OUT/appcast.xml" || { echo "appcast.xml still names unrenamed deltas" >&2; exit 1; }
echo "  $OUT/appcast.xml, ${#deltas[@]} delta(s)"

# Check the feed as Sparkle will: lengths and EdDSA signatures against the app's public key.
echo "[release] checking the update feed"
swift scripts/check-appcast.swift "$OUT/appcast.xml" "$OUT" \
  "$(plutil -extract SUPublicEDKey raw "$APP/Contents/Info.plist")"
# Apply every delta to the app of its old version, which must give this version's app with
# a valid signature (BinaryDelta checks the result against the hash in the delta).
for d in ${deltas[@]+"${deltas[@]}"}; do
  old="${d##*-from-}"; old="${old%.delta}"
  mnt="$(mktemp -d)"; tmp="$(mktemp -d "$OUT/delta-check.XXXXXX")"
  attach "$UPDATES/SWTOR-on-Mac-$old.dmg" "$mnt"
  ok=1
  "$SPARKLE_BIN/BinaryDelta" apply "$mnt/SWTOR on Mac.app" "$tmp/SWTOR on Mac.app" "$d" >/dev/null &&
    codesign --verify --strict --deep "$tmp/SWTOR on Mac.app" &&
    [ "$(plutil -extract CFBundleShortVersionString raw "$tmp/SWTOR on Mac.app/Contents/Info.plist")" = "$VERSION" ] || ok=0
  detach "$mnt"
  rm -rf "$tmp" "$mnt"
  [ "$ok" = 1 ] || { echo "Delta ${d##*/} does not apply to $old" >&2; exit 1; }
  echo "  ${d##*/}: applies to $old, signature valid"
done

case "$MODE" in
  --no-notarize|--no-release)
    echo "[release] $DMG ($(du -h "$DMG" | cut -f1)); no GitHub release ($MODE)" ;;
  --feed)
    echo "[release] adding the feed to the draft release v$VERSION"
    gh release upload "v$VERSION" --repo "$REPO" --clobber "$OUT/appcast.xml" ${deltas[@]+"${deltas[@]}"}
    echo "[release] draft v$VERSION complete; publish it to make the update live" ;;
  *)
    echo "[release] creating the draft GitHub release v$VERSION"
    gh release create "v$VERSION" --repo "$REPO" --draft --title "SWTOR on Mac $VERSION" \
      --notes-file "$NOTES" "$DMG" ${deltas[@]+"${deltas[@]}"} "$OUT/appcast.xml"
    echo "[release] $DMG ($(du -h "$DMG" | cut -f1)); publish the draft to make the update live" ;;
esac
