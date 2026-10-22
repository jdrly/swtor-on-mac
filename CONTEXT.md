# SWTOR on Mac domain context

The glossary of SWTOR on Mac, the macOS app that runs the official Star Wars: The Old Republic
Mac app's game on its own Wine engine with d9mt. Use these terms in issues, pull requests, code,
log lines, the window's text and release notes.

This glossary defines **language, not implementation**. ADRs in [`docs/adr/`](docs/adr/index.md)
own the decisions, and the README describes the behaviour in detail. If a term you need is
missing, add it here in the same pull request and say so in the PR description. Every definition
names its source; what is not decided is marked _Open_.

## Broadsword's side

**Official app**
`Star Wars - The Old Republic.app` from swtor.com. It must be installed and started once before
SWTOR on Mac does anything; SWTOR on Mac never downloads the launcher or the game (README,
*Install*).
_Avoid_: “the SWTOR app” when SWTOR on Mac could be meant.

**Launcher**
Broadsword's login and patching window inside the official app. It starts the game and quits
about 30 seconds later (README, *Known issues*, *How it works*).

**Broadsword's Wine folder**
`~/Library/Application Support/com.broadsword.swtor/Star Wars - The Old
Republic/swtor-precompiled/Libraries/Wine`: the official app's Wine, which is also its Wine
prefix (README, *What it changes*; `src/som.sh`).

**`mac_wine`**
Broadsword's helper that makes the launcher's Wine calls. SWTOR on Mac never ends it (README,
*How it works*; `src/som.sh`).

**Preloader**
`bin/wine64-preloader` and `bin/wine-preloader` in Broadsword's Wine folder. Every Wine process
the launcher starts goes through it (README, *How it works*).

## The hook

**Wrapper**
`src/wine-wrapper.sh`, installed in the preloaders' place. It reads `env` and runs the command on
SWTOR on Mac's engine and prefix, or on Broadsword's real preloader when those are missing
(README, *How it works*; `src/wine-wrapper.sh`).

**`bin-real/`**
The folder next to `bin/` that holds Broadsword's preloaders (moved, not changed), plus
`hold-launcher` and `setsid-exec` (README, *What it changes*).

**Launcher hook**
The wrapper in the preloaders' place. A launcher update can remove it; the *hook check* puts
it back when the app opens, else the window shows *Repair the Launcher Hook* (README, *Launcher
updates*). `som.sh`
tells it apart from Broadsword's own preloaders and from another tool's wrapper (`src/som.sh`).
_Avoid_: “patch”, “mod” (it changes no game file).

**Hook check**
`som.sh rehook`, run by the app each time it opens and before *Play SWTOR* when the hook is
gone: puts the wrapper back if a launcher update replaced it, and leaves it alone while an
install runs, another wrapper is there or the launcher is still changing its Wine (README,
*Launcher updates*; [ADR 0005](docs/adr/0005-no-background-helper.md)). Nothing of SWTOR on Mac
runs while the app is closed.
_Avoid_: “watcher”, “daemon”, “background service”.

**launchd job**
`cz.jandrly.swtoronmac.watch`, which versions up to 0.1.3 set up (launchd started it when
Broadsword's `Wine/bin` changed). Install and Uninstall remove it since 0.1.4.

## SWTOR on Mac's side

**Engine**
`engine/`: the Wine engine the game runs on, CrossOver 26.3 with Wine 11 (athei's build
`cx-26.3.0-8`), downloaded at install time and pinned by size and sha256, with d9mt's winemetal
bridge and SWTOR on Mac's builds of `ntdll.so` (and of the Mac driver, when a setting needs it)
in place of the engine's own files, which are kept as `.stock` (README, *What it changes*,
*Pinned components*; `src/som.sh`; ADR-0001).
_Avoid_: “Wine version” for the engine as a whole, “bottle”.

**Prefix**
`prefix/`: the game's Wine prefix, an APFS clone of Broadsword's, updated for the engine, with
d9mt's `d3d9.dll` in `system32` (README, *What it changes*).

**Install, Reinstall, Update to X.Y.Z**
Install sets everything up, all or nothing (ADR-0003). Reinstall is Install again; it is safe to
repeat and keeps the game's and SWTOR on Mac's settings. *Update to X.Y.Z* is the window's
button after an app update; it brings the installed setup up to the app's version (README,
*Install*, *Updates*).

**Uninstall**
Copies the game settings back to Broadsword's prefix, puts Broadsword's preloaders back and
deletes the engine, prefix, settings and an older version's launchd job; logs and d9mt's caches stay (README,
*Uninstall*).

**Install manifest**
`install-manifest.json`: what Install changed, for Uninstall, including the sha256 of
Broadsword's original preloaders (README, *What it changes*; `src/som.sh`).

**`env`, `settings.conf`, `dxvk.conf`**
`settings.conf` holds the Settings window's settings; `env` (what the wrapper applies) and
`dxvk.conf` (d9mt's options) are made from it (README, *Settings*).

**Wine session**
The prefix's wineserver and Wine's system processes. The wrapper brings it up through
`hold-launcher --start-session`; the wineserver ends 10 seconds after the last Wine process
(README, *How it works*; `src/helpers/hold-launcher/hold_launcher.c`).

**`hold-launcher`**
The wrapper's session helper. Its name dates from 0.1.1, when it held the launcher open; it no
longer does (`src/helpers/hold-launcher/hold_launcher.c`).

**Leftover Wine processes**
Processes of the engine that belong to this prefix's session while no wineserver of it runs.
*End Leftover Wine Processes*, Install, Uninstall and the registry settings end them (README,
*How it works*, *Troubleshooting*).

**Game Mode link**
`gamemode/SWTOR.app`, a bundle with `LSSupportsGameMode` around a clone of the engine's loader,
and the link to it that the wrapper makes at each game start in `$TMPDIR/winetemp-…/`, so macOS
turns Game Mode on (README, *How it works*).

**d9mt**
The Direct3D 9 to Metal driver the game draws with, Jan Drlý's fork of neo773's d9mt-v2,
[jdrly/d9mt](https://github.com/jdrly/d9mt), bundled at a pinned commit (`scripts/build-d9mt.sh`,
`prebuilt/d9mt`; README, *Credits and licenses*).

**Pipeline state cache**
d9mt's record of the pipelines the game used, which it builds again in the background while the
game loads (`D9MT_STATE_CACHE`, `state/` in d9mt's per-user cache folder). Uninstall leaves d9mt's
caches (README, *Install*, *What it changes*).

## Settings and diagnostics

**Raw mouse-look**
While the game hides the pointer to turn the camera, the mouse's own moves come from
GameController's `GCMouse` through an input thread of SWTOR on Mac's Mac driver, and the macOS
pointer stays frozen. On by default (README, *Settings*).
_Avoid_: “raw input” (SWTOR has none).

**Game keys by keyboard position**
The game sees every key by its position on a US keyboard (`PhysicalKeyboard=y`), for layouts whose
keys type something else (README, *Settings*).

**Debug Logging**
The Troubleshooting setting that makes d9mt and the Mac driver log in detail (`STATS`, `PACE`,
`THREADCPU`, `RAWMOUSE` lines) for the next game start; it costs a little performance (README,
*Settings*, *Debug Logging*).

**Collect Logs**
*SWTOR on Mac > Collect Logs…*: a zip for bug reports, `SWTOR-on-Mac-logs-<date>.zip`, with
account names, e-mail addresses and the user name replaced and without the game's command line
(README, *Reporting problems*; `src/collect-logs.sh`).

**Session report**
`session-report.sh`: a summary of the last game session from `wine.log` (frame rate, hitches,
compile waits, memory, d9mt's pipeline state cache); `--compare` puts two sessions side by side
(README, *Debug Logging, session reports and live d9mt flags*).

**Sandbox**
A run of `som.sh` with `SWTOR_ON_MAC_ROOT=/abs/dir`: every path, the official install included,
lives under that directory. `SWTOR_ON_MAC_DRY_RUN=1` prints the changes without making them
(README, *Testing without touching the system*).

## Releases

**Release**
A signed, notarized version `X.Y.Z` on GitHub Releases, offered as an update through the feed
(README, *Releasing*).

**Development build**
A test build `X.Y.Z-dev.N`, published only as a GitHub pre-release, never in the feed, with a
badge, Debug Logging on by default and no automatic update checks (README, *Development builds*).
_Avoid_: “beta”, “nightly”.

**A/B switches**
`d9mt-ab.sh`: d9mt's test switches for the next game starts in a development build
(`state-off`, `vsync-off`, `cold=<name>`, …), kept in `d9mt-ab.env`, which only a development
build reads (README, *Development builds*).

**Feed**
`appcast.xml` of the latest GitHub release, signed with Sparkle's EdDSA key, which the app and
the wrapper's daily check read (README, *Updates*).
_Avoid_: “update server”.

**Release notes**
`release-notes/<version>.md`, used unchanged in the GitHub release, the update window and on
swonmac.com, in the format of [release-notes/README.md](release-notes/README.md).
