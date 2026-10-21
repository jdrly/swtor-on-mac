---
status: accepted
date: 2026-10-21
deciders: Jan Drlý
---

# A release is built by CI and finished on the maintainer's Mac; development builds are pre-releases only

## Context

The app updates itself with Sparkle, whose feed is signed with an EdDSA key (`SUPublicEDKey`);
whoever holds the private key can ship code to every player (README, *Updates*). Releases also
need the Developer ID signature and Apple's notarization.

## Decision

- Sparkle's EdDSA key never leaves the maintainer's Mac, so a release comes in two halves
  (README, *Releasing*):
  1. A `v<version>` tag starts the Release workflow, which runs only after approval in the
     `release` environment: it builds, signs and notarizes the app and creates a draft release
     with the DMG.
  2. On the Mac, `scripts/release.sh --feed <version>` checks the DMG, builds and checks
     `appcast.xml` and the deltas, and uploads them to the draft, which is then published.
- Development builds (`X.Y.Z-dev.N`) are built and released from the Mac with
  `scripts/release.sh --dev`, as GitHub pre-releases with the DMG and no feed. Development builds
  never go into a feed or a regular release, and releases are never development builds
  (`scripts/release.sh`).
- The Release workflow refuses a version that doesn't match `build.sh`, a development version,
  and release notes without the title, the summary or the Discord invite (`.github/workflows/release.yml`).

## Consequences

- No release can be published without the maintainer's Mac; CI alone can't ship an update.
- A development build is never offered as an update; testers install it from the DMG, and the
  next release is offered over it (README, *Development builds*).
- Each development build's `CFBundleVersion` has to sort between the previous release and its
  own (README, *Development builds*).

## Alternatives considered

- **Signing the feed in CI**: rejected, because the EdDSA key would have to leave the Mac
  (README, *Releasing*).
- **Everything on the Mac** (`./build.sh && scripts/release.sh`): still possible without CI, but
  not the normal path (README, *Releasing*).
