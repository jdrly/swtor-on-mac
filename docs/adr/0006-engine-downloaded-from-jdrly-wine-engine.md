---
status: accepted
date: 2026-11-11
deciders: Jan Drlý
---

# The engine is downloaded at install time from jdrly/wine-engine, never bundled

## Context

ADR-0002 had Install download the engine from athei/wine-build's GitHub release, and named the
risk among its consequences: installs depend on that release staying available, and there is no
copy to fall back to. On 2026-11-11 that happened. athei renamed `athei/wine-build` to
`athei/mach9`, which ships an arm64 Wine now; the release `cx-26.3.0-8` and its archive are gone,
and both of the app's addresses return 404. Every new install, and every Update or Repair that
needs the engine again, stopped at the engine's download (#102). GW2 on Mac, which downloads the
same file, broke the same day.

## Decision

- The maintainer decided on 2026-11-11 to host the engine, because the original release is gone
  and there was no other way to keep installs working. The maintainer knew before deciding that
  the archive contains Apple's D3DMetal as athei bundled it, and chose a public repository,
  [jdrly/wine-engine](https://github.com/jdrly/wine-engine).
- Its release `cx-26.3.0-8` has the same file, byte for byte (234,978,748 bytes, sha256
  `1976c331…456d`), unchanged, with the licence files athei's archive carries, and next to it the
  Wine source it was built from (athei/wine `d23b397`, sha256 `7002111d…746e`; in athei/wine that
  commit is on no branch any more).
- Install downloads the engine from that release (`ENGINE_URL` in `src/som.sh`) and checks it
  against the pinned size, start and sha256, as before. When that URL doesn't bring the file, it
  fetches the same release asset once more through GitHub's API (`ENGINE_API_URL`, the asset's
  id): another address of the same file, now of this release.
- A file a player downloads by hand into `~/Library/Caches/SWTOR on Mac/downloads/` is used when
  its checksum is right. One that isn't the engine is named in the window and moved aside as
  `<name>.wrong` (docs/updates.md).
- The app still bundles none of the engine. It bundles only what SWTOR on Mac builds itself
  (d9mt, the Mac driver and `ntdll.so`, with their licences and the LGPL patches) and Sparkle.

## Consequences

- Installs work again, and no longer depend on a release that someone else can take down.
- The maintainer now distributes the engine and everything inside it, including Apple's
  D3DMetal and the libraries in `lib/external`, and answers for that (see *Open questions*).
- Install and the 0.1 upgrade still need an internet connection and about 235 MB of download.
- An engine update still needs a new app version (the pin lives in `src/som.sh`), and now also a
  new release in jdrly/wine-engine.
- SWGL on Mac and GW2 on Mac download from the same release, so all three apps depend on it.

## Alternatives considered

- **Keep ADR-0002 and wait for athei's release to come back**: the repository is a different
  project now, with an arm64 Wine, and new installs stay broken while waiting.
- **Bundle the engine in the app**: the app would grow by about 235 MB, every update would carry
  it, and the redistribution question below would be the same.

## Open questions

- ADR-0002 rejected a mirror "for licensing reasons" without writing them down. This ADR doesn't
  claim they are resolved.
- The archive contains Apple's D3DMetal (Game Porting Toolkit redistributables) under the licence
  that ships with it, `lib/external/D3DMetal-License.rtf`, which jdrly/wine-engine carries
  unchanged. Section 2A(iii) of that licence allows distributing the Apple Software "solely for
  non-commercial purposes and in accordance with this Agreement, including Section 2C". Section
  2C says "the Framework in its entirety or any part of the Redistributables may be distributed
  separately from the Apple Software", and that "all distribution of the Apple Software,
  including the Framework in its entirety and any individual Redistributables, are subject to the
  non-commercial restriction in Section 2(A)(iii)". The same section also says "You may not
  rent, lease, lend, host, sell, or sublicense (except as expressly set forth in Section 2A) the
  Apple Software". Whether a lawyer would read this as permitting jdrly/wine-engine is not
  checked.
- Nobody has checked the libraries in `lib/external` one by one.
