---
status: accepted
date: 2026-11-14
deciders: Jan Drlý
---

# Releases are built, checked and published from the maintainer's Mac; CI builds no release

## Context

[ADR-0004](0004-releases-in-two-halves.md) had a `v<version>` tag start the Release workflow,
which built, signed and notarized the app in CI after an approval in the `release` environment;
my Mac only added the Sparkle feed. That route never finished a tag's run: every one, from
v0.0.1 to v0.1.8, was cancelled or failed. Every release was built on my Mac and published from
there, by agents since 0.1.2, and the tag's Release run was cancelled. The runs for 0.1.5 and
0.1.5.1 failed at *Import the signing certificate*: the `release` environment holds no secrets,
and it never had the approval rule ADR-0004 describes either (#31).

The reason is the rule that the build that was tested is the build that ships. A rebuild in CI
gives another binary: d9mt's DLL image base follows its build path, and every notarization
stamps its own build. I decided on 2026-10-25 to write the route down and retire the CI build
(#41), and on 2026-11-14 that the release runs fully automated: "the release pipeline should be
fully automated, no need for manual intervention from me", run by "agents on my Mac, as before".

## Decision

- A release is built, signed, notarized, checked and published by agents on my Mac. The
  Developer ID certificate, the notary credentials and Sparkle's EdDSA key exist only there. CI
  holds no signing material and builds no release.
- A release candidate is the app at a commit of `main`. It goes through the checks its changes
  call for (the fixture groups, the sandbox suite, the d9mt pin's checks; CONTRIBUTING.md,
  *Definition of Done*), and I play it.
- The version PR (`APP_VERSION`, `release-notes/<version>.md`, the README) is squash-merged into
  `main`. The release is built at that squash commit with `./build.sh` and
  `scripts/release.sh --no-release`: the signed, notarized and stapled DMG, the deltas and the
  signed feed, which `scripts/check-appcast.swift` checks and every delta of which is applied.
- Exactly that DMG's app is checked without Wine: its signature, Gatekeeper's assessment and the
  stapled ticket, its `Info.plist`, the feed, `som.sh status` in an empty sandbox and
  `scripts/test-btm.sh`.
- The binary-diff gate ties the release to what was tested, in two comparisons of the DMG's
  app. Against the release candidate I played, every Mach-O file is byte-identical or differs
  only in its signature, d9mt's and Wine's Windows files are byte-identical, and any other file
  differs only in its version or where the version PR changed it. Against the last release as
  published, a file differs only where the commits between the two releases changed it or what
  it is built from, and the files from `prebuilt/` are the committed ones byte for byte. A
  difference anywhere else stops the release.
- Exactly those files are published: `gh release create v<version> --target <squash commit>
  --latest` with the DMG, the deltas, `appcast.xml` and the notes. Then the assets are
  downloaded again and compared with the hashes recorded for them, and
  `releases/latest/download/appcast.xml` has to name the new version.
- Nobody approves a step and nobody clicks anything after the release candidate has passed and
  I have played it.
- A tag starts no workflow that builds or signs. The Site workflow still runs on a published
  release and rebuilds swonmac.com.
- Development builds stay as they are: built on my Mac with `scripts/release.sh --dev`, GitHub
  pre-releases with the DMG only, never in the feed.
- The `release` environment is unused, and I remove it from the repository's settings. If a CI
  path ever needs secrets again, its environment admits only `v*` tag runs, and that is a
  condition of that path.

## Consequences

- No release can be published without my Mac. If that Mac is lost, so is the signing setup, and
  a release waits until the certificate, the notary credentials and the EdDSA key are set up
  again (the EdDSA key has to be the same one, or installed apps reject the feed).
- Nobody outside my Mac can rebuild a release and get the same DMG: the notarization and the
  signatures are in it. The source tree and `prebuilt/` are public; the binary-diff gate's
  evidence isn't.
- The binary-diff gate and the publish and verify steps are scripts outside this repository, so
  nothing here enforces them yet; #47 adds a record of the tested files and a check of it.
- A change to the release notes after the build changes `appcast.xml`, which embeds them, but not
  the DMG or the deltas: the feed's `<description>` is swapped, the feed checked again with
  `scripts/check-appcast.swift`, and its new hash recorded in place of the old one. The DMG's
  and the deltas' hashes stay as built.
- The release notes' format (title, summary, Discord invite) is checked by
  `scripts/release.sh` when it builds a release, no longer by a workflow.

## Alternatives considered

- **The CI route of ADR-0004**: a CI build is not the build that was tested, it needs the
  Developer ID certificate and the notary key as GitHub secrets, and the feed still has to be
  finished on my Mac. It never shipped a release.
- **Signing the feed in CI**: the EdDSA key would have to leave my Mac.
- **Requiring my approval in the `release` environment**: it would put me back into every
  release, which I don't want, and it would guard a build that no release uses.
