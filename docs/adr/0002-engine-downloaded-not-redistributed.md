---
status: accepted
date: 2026-10-21
deciders: Jan Drlý
---

# The engine is downloaded from its official source at install time, never bundled or mirrored

## Context

The app needs a Wine engine on the player's Mac: athei/wine-build's build of CrossOver 26.3, about
235 MB (ADR-0001). In October 2026 a player updating from 0.0.6 got “The download of Wine engine
is damaged (checksum mismatch)” six times in a row, so the engine download had to become reliable
(0.1.3 hotfix, 2026-10-20; `release-notes/0.1.3.md`).

## Decision

- Install downloads the engine from its official source, athei/wine-build's GitHub release,
  checks it against the pinned size, start and sha256, and unpacks it into SWTOR on Mac's own
  folder (`src/som.sh`: “Components: downloaded at install time from their official sources
  (never bundled)”; README, *Credits and licenses*: “not redistributed”).
- **There is no engine mirror, for licensing reasons.** The maintainer decided this during the
  0.1.3 hotfix (2026-10-20); this ADR is where the decision is recorded.
- When the release URL doesn't bring the file, the installer fetches **the same release asset**
  once more through GitHub's API (`ENGINE_API_URL`, the asset's id): another address of the same
  file on GitHub's asset servers, not a mirror (`src/som.sh`; `release-notes/0.1.3.md`).
- A file a player downloads by hand into `~/Library/Caches/SWTOR on Mac/downloads/` is used when
  its checksum is right (README, *Updates*).
- The app bundles only what SWTOR on Mac builds itself: d9mt, the Mac driver and `ntdll.so`, with
  their licences and the LGPL patches (`THIRD_PARTY_NOTICES.md`).

## Consequences

- Install and the 0.1 upgrade need an internet connection and about 235 MB of download.
- Installs depend on athei/wine-build's release staying available; there is no copy to fall back
  to.
- A broken download is the most likely install failure; 0.1.3 resumes it, retries it, names its
  cause and logs every try (README, *Updates*).
- An engine update needs a new app version (the pin lives in `src/som.sh`).

## Alternatives considered

- **Mirror the engine on SWTOR on Mac's own releases**: rejected for licensing reasons (above).
- **Bundle the engine in the app**: not done; the components are downloaded from their official
  sources, never bundled (`src/som.sh`).

## Open questions

- Updating the engine without an app release (a component manifest) is an idea, not a decision.
