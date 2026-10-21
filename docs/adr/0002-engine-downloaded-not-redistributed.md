---
status: accepted
date: 2026-10-21
deciders: Jan Drlý
---

# The engine is downloaded from its own release at install time, never bundled or mirrored

## Context

The app needs a Wine engine on the player's Mac. The engine release (about 235 MB) bundles, next
to Wine, libraries and components under their own licences: DXMT, mtld3d, x87sidecar and Apple's
D3DMetal from the Game Porting Toolkit redistributables (`THIRD_PARTY_NOTICES.md`, *Downloaded at
install time*).

## Decision

- Install downloads the engine from athei/wine-build's GitHub release, checks it against the
  pinned size, start and sha256, and unpacks it into SWTOR on Mac's own folder
  (`src/som.sh`, “Components: downloaded at install time from their official sources (never
  bundled)”; README, *Credits and licenses*: “not redistributed”).
- The app bundles only what SWTOR on Mac builds itself: d9mt, the Mac driver and `ntdll.so`,
  with their licences and the LGPL patches (`THIRD_PARTY_NOTICES.md`).
- When the release URL doesn't bring the file, the installer fetches **the same release asset**
  once more through GitHub's API (`ENGINE_API_URL`, the asset's id). That is another address of
  the same file on GitHub, not a mirror (0.1.3; `src/som.sh`).
- A file a player downloads by hand into `~/Library/Caches/SWTOR on Mac/downloads/` is used when
  its checksum is right (README, *Updates*).

## Consequences

- Install and the 0.1 upgrade need an internet connection and about 235 MB of download.
- Installs depend on athei/wine-build's release staying available.
- A broken download is the most likely install failure; 0.1.3 resumes it, retries it, names its
  cause and logs every try (README, *Updates*).
- An engine update needs a new app version (the pin lives in `src/som.sh`).

## Alternatives considered

- **Bundle the engine in the app**: not done. The reason is not recorded (see *Open questions*).
- **Mirror the engine on SWTOR on Mac's own releases**: not done; the 0.1.3 fix for failing
  downloads deliberately uses a second address of the same release instead.

## Open questions

- **The reason is not written down.** Licensing of the components the engine bundles (above) is
  the likely one; the maintainer confirms or corrects it before this ADR is merged.
- Updating the engine without an app release (a component manifest) is an idea, not a decision.
