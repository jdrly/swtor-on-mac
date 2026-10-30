---
status: accepted
date: 2026-10-21
deciders: Jan Drlý
---

# The game runs on one Wine engine: CrossOver 26.3 with Wine 11, the engine SWGL on Mac uses

## Context

SWTOR on Mac 0.0.1 to 0.0.6 ran the game on Sikarugir's CrossOver 24.0.7 (Wine 9), with
Sikarugir's template libraries in a `frameworks/` folder (`src/som.sh`, `OLD_ENGINE_SHA256`).
SWGL on Mac already ran on athei's build of CodeWeavers' CrossOver 26.3 (Wine 11)
(README, *Credits and licenses*).

## Decision

- SWTOR on Mac uses exactly one engine, athei/wine-build `cx-26.3.0-8` (CrossOver 26.3, Wine
  11.0, x86_64 WoW64), pinned by URL, size and sha256 in `src/som.sh` and the README's *Pinned
  components*. There is no choice between engines (`release-notes/0.1.0-dev.1.md`).
- The first Reinstall on 0.1 upgrades a 0.0.x install: it downloads the new engine and updates
  the existing prefix with `wineboot -u`, keeping the game's and SWTOR on Mac's settings. What it
  replaces is kept until the upgrade has gone through and put back if it fails (docs/updates.md; `upgrade_from_old_engine` in `src/som.sh`).

## Consequences

- SWTOR on Mac and SWGL on Mac share one engine, so a Mac driver patch or an engine fix applies
  to both (the mouse-look patches are SWGL on Mac's, unchanged; docs/building.md).
- The engine has no `wine-preloader`: every Wine process runs from its loader, so leftover
  processes are found by their real executable, and the Game Mode link wraps the loader
  (`src/som.sh`; docs/how-it-works.md).
- The engine's compatdb would put DXGI on Apple's D3DMetal or on DXMT's own `winemetal.dll`;
  `WINE_COMPATDB` keeps DXGI on wined3d so nothing competes with d9mt's bridge (`src/som.sh`).
- The engine brought a bug CrossOver 24 didn't have: its msync port lets an exiting thread close
  an unrelated file descriptor. SWTOR on Mac ships its own `ntdll.so` with a fix
  (`patches/ntdll-msync-alert-fd.patch`; docs/building.md).
- Going back means installing 0.0.6 and running its Reinstall, which takes the updated prefix
  back (docs/updates.md).

## Alternatives considered

- **Keep CrossOver 24.0.7**: replaced; no rationale beyond sharing SWGL on Mac's engine is
  recorded.
- **An engine switch** (both engines, chosen per install): rejected by the maintainer; “there is
  no choice between engines: this version uses only the new one” (`release-notes/0.1.0-dev.1.md`).

## Open questions

- The engine for life after Rosetta (an arm64 Wine) is not decided.
