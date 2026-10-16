# SWTOR on Mac

A small macOS app that makes the official [Star Wars: The Old Republic](https://www.swtor.com)
Mac app run faster on Apple Silicon. It installs a performance setup on top of your existing
official install: the game's Direct3D 9 goes straight to Metal with
[d9mt](https://github.com/jdrly/d9mt), on a newer Wine (CrossOver 24.0.7), with macOS Game
Mode. You keep starting the game from the official app, as usual.

> **SWTOR on Mac is an unofficial community project.** It is not made, endorsed or supported
> by Broadsword Games, Electronic Arts, Lucasfilm or Disney. Broadsword doesn't support
> third-party modifications, so you use it at your own risk. It doesn't modify the game's
> files: it only changes the graphics layer the official Mac app already uses (Wine, plus
> d9mt for Direct3D 9 on Metal), and Uninstall puts that back the way Broadsword ships it.
>
> **All support for SWTOR on Mac comes from its developer, Jan Drlý (Pharaphobia).** For
> help, contact Pharaphobia on Discord or open a
> [GitHub issue](https://github.com/jdrly/swtor-on-mac/issues). Please don't send logs or bug
> reports about SWTOR on Mac to Broadsword or SWTOR customer support.
>
> Star Wars: The Old Republic and SWTOR are trademarks of their respective owners.

<img src="docs/screenshots/installed.png" width="720" alt="The SWTOR on Mac window after an install">

## Features

- **d9mt**: the game's Direct3D 9 goes straight to Metal, on CrossOver 24.0.7 Wine, with
  macOS **Game Mode** and Retina rendering.
- **Settings** (SWTOR on Mac > Settings…, ⌘,): Retina mode, vsync, d9mt's video memory
  profile, Game Mode, the Metal HUD, debug logging, automatic update checks.
- **Updates**: the app updates itself with [Sparkle](https://sparkle-project.org) (SWTOR on
  Mac > Check for Updates…), and the game's start looks for a new version once a day.
- **Survives launcher updates**: when the official launcher updates its Wine and drops SWTOR on
  Mac's hook, a small launchd job hooks it back in by itself.
- **Collect Logs…** makes a zip for bug reports, without account names or passwords.
- **Fully reversible**: Uninstall puts the official app back exactly as Broadsword ships it and
  copies your game settings back to it.

<img src="docs/screenshots/installing-steps.png" width="360" alt="Installing: the timeline of the steps"> <img src="docs/screenshots/settings.png" width="200" alt="The Settings window"> <img src="docs/screenshots/installed-dark.png" width="360" alt="Installed, in dark mode">

More in [docs/screenshots](docs/screenshots) (the notice, a failed install, uninstall, a narrow
window).

## Requirements

- A Mac with Apple Silicon and macOS 26 or later (developed on macOS 27).
- The **official SWTOR Mac app, installed first** from [swtor.com](https://www.swtor.com) and
  started once, so it has set up the game. SWTOR on Mac never downloads the launcher or the
  game; without the official install it refuses to do anything.
- Rosetta (macOS offers it when you first start the official app).
- About 1 GB of free space and an internet connection for the install (it downloads the Wine
  engine, ~270 MB, from its official source).

## Install

1. Quit the SWTOR launcher and the game.
2. Open **SWTOR on Mac**, read the notice and tick **I understand**, then click **Install**.
   It takes a minute or two; the window shows each step.
3. Start SWTOR from the official app as usual. The launcher looks and works the same; the game
   runs on SWTOR on Mac's engine.

**The first minutes of play may stutter**, and so may each new area or effect the first time
you see it (for example a city full of players): d9mt compiles the game's shaders and pipelines
for Metal the first time it meets them and caches them, so it gets smooth after that. After an
update of SWTOR on Mac the cache is rebuilt once.

Install again (**Reinstall**) whenever you like: it is safe to repeat and keeps your game
settings and SWTOR on Mac's settings. After an official launcher update SWTOR on Mac hooks
itself back in (see below); the window shows it if that did not work (*Launcher hook: Removed by
a launcher update*, with a **Repair** button).

## Settings

SWTOR on Mac > **Settings…** (⌘,), while SWTOR on Mac is installed. Changes take effect the
next time the game starts.

| Setting | Default | What it changes |
|---|---|---|
| Retina Mode | on | Wine's Mac driver `RetinaMode` in the prefix's registry (only while the launcher and the game are closed) |
| Vsync | on | `d3d9.presentInterval = 1` in `dxvk.conf` (off: unset) |
| Video Memory Profile | Automatic | `D9MT_MEMORY_PROFILE` (auto, low, medium, high, ultra, unlimited) |
| Game Mode | on | `SWTOR_GAMEMODE_APP` in `env` |
| Show Metal HUD | off | `MTL_HUD_ENABLED=1` in `env`. It can't be toggled with a key in the game; turn it on here before starting the game |
| Check for updates automatically | on | Sparkle's automatic checks and the daily check at the game's start |
| Debug Logging | off | `DXVK_LOG_LEVEL=info`, `D9MT_PROFILE=1`, `D9MT_MEMSTATS=1` (else `DXVK_LOG_LEVEL=warn`) |

They are kept in `~/Library/Application Support/SWTOR on Mac/settings.conf`; `env` and
`dxvk.conf` are made from it (`som.sh settings`, `som.sh set <key> <value>`).

## Updates

- The app checks [its feed](https://github.com/jdrly/swtor-on-mac/releases/latest/download/appcast.xml)
  with Sparkle, signed with an EdDSA key (`SUPublicEDKey`), and asks before installing; SWTOR on
  Mac > **Check for Updates…** checks right away.
- At most once a day, when the game starts, the Wine wrapper looks at the same feed in a
  detached process (2 s timeout; the game never waits for it, offline it does nothing). If
  there is a newer version it posts a notification, *SWTOR on Mac update available — open the
  app to update*, and the app then offers the update when it is opened.
- After an app update, click **Update** in the window: it brings the installed setup (wrapper,
  d9mt) up to the app's version.

## Launcher updates (the launchd job)

The official launcher sometimes updates its own Wine and puts Broadsword's preloaders back in
place of SWTOR on Mac's wrapper. Install sets up a launchd job for that,
`~/Library/LaunchAgents/cz.jandrly.swtoronmac.watch.plist`: launchd starts it only when
Broadsword's `Wine/bin` folder changes (`WatchPaths`, not at login, at most every 30 s); it
checks the wrapper and exits. Nothing runs in between. If a launcher update replaced the
wrapper, it waits until the folder has been quiet for 20 s, puts the wrapper back exactly like
Install does, records the new preloaders in `install-manifest.json` and posts a notification.
It does nothing while an install or uninstall runs or when another Wine wrapper is installed,
and if the folder looks half updated it only notifies (*open SWTOR on Mac and click
Reinstall*). It runs a copy of `som.sh` in `~/Library/Application Support/SWTOR on Mac/agent`,
so updating or moving the app does not affect it; its log is `~/Library/Logs/SWTOR on
Mac/watch.log`.

Uninstall removes it. To remove it by hand:

```sh
launchctl bootout gui/$(id -u)/cz.jandrly.swtoronmac.watch
rm ~/Library/LaunchAgents/cz.jandrly.swtoronmac.watch.plist
```

## Collect Logs

SWTOR on Mac > **Collect Logs…** saves `SWTOR-on-Mac-logs-<date>.zip` to the Desktop and shows
it in Finder: SWTOR on Mac's logs, `env`, `settings.conf`, `dxvk.conf`,
`install-manifest.json`, the versions, system information (macOS, chip, memory, displays) and
crash reports of the last 7 days for the game and Wine. Your home folder, user name, account
names and e-mail addresses are replaced, and the game's command line (the launcher passes the
account on it) is never included.

## Uninstall

Quit the launcher and the game, open SWTOR on Mac and click **Uninstall…**. Your game settings
(graphics options, UI layouts, key bindings: `AppData/Local/SWTOR/swtor/settings` of SWTOR on
Mac's prefix, without `ContextError.ini`) are copied back to Broadsword's prefix first, with a
copy of its previous ones next to them (`settings-backup-<time>`). Then the official app goes
back to exactly how Broadsword ships it, and SWTOR on Mac's engine, prefix, settings and launchd
job are deleted (characters live on the server and are not affected). Logs stay in
`~/Library/Logs/SWTOR on Mac`. Then move the app to the Bin.

## What it changes

In Broadsword's install (`~/Library/Application Support/com.broadsword.swtor/Star Wars - The
Old Republic/swtor-precompiled/Libraries/Wine`), and nowhere else in it:

| | Before | After |
|---|---|---|
| `bin/wine64-preloader`, `bin/wine-preloader` | Broadsword's Wine preloaders | SWTOR on Mac's wrapper script |
| `bin-real/` | – | Broadsword's preloaders (moved, not changed), `hold-launcher`, `setsid-exec` |

The game files, the launcher app and Broadsword's Wine prefix are only read (the prefix is
cloned once). Everything else lives in SWTOR on Mac's own folders:

- `~/Library/Application Support/SWTOR on Mac/`
  - `engine/` – the Wine engine, with d9mt's winemetal bridge
  - `frameworks/` – the engine's libraries
  - `prefix/` – the game's Wine prefix: an APFS clone of Broadsword's, updated for the engine,
    with d9mt's `d3d9.dll` in `system32` (Wine's own kept as `d3d9.dll.wine`) and the settings
    below; your existing game settings are taken over once
  - `gamemode/SWTOR.app` – the bundle that gets the game macOS Game Mode
  - `settings.conf` – the Settings window's settings; `env` – what the wrapper applies,
    `dxvk.conf` – d9mt's options (both made from `settings.conf`)
  - `install-manifest.json` – what was changed, for Uninstall
  - `agent/` – the copy of `som.sh` the launchd job runs; `last-update-check`,
    `update-available` – the wrapper's daily update check
  - `backup/` – only if you replaced another Wine wrapper: a copy of it
- `~/Library/LaunchAgents/cz.jandrly.swtoronmac.watch.plist` – the launchd job (see above)
- `~/Library/Logs/SWTOR on Mac/` – `install.log`, `watch.log`, and per game start `wine.log`
  (d9mt warnings), `hold.log`, `launch-env.txt`, `effective-env.txt`

To revert by hand: in Broadsword's `Wine` folder, move `bin-real/wine-preloader` and
`bin-real/wine64-preloader` back into `bin/` (replacing the scripts there), delete `bin-real`,
delete `~/Library/Application Support/SWTOR on Mac`, and remove the launchd job (above).
Deleting only the folder also works: the wrapper then runs Broadsword's own Wine.

## How it works

The official launcher starts every Wine process through `bin/wine64`, which loads
`bin/wine64-preloader`. The wrapper (`src/wine-wrapper.sh`) sits in its place, reads
`~/Library/Application Support/SWTOR on Mac/env` and runs the command on SWTOR on Mac's engine
and prefix instead (falling back to Broadsword's real preloader if those are missing). It first
ends leftover Wine processes of the engine, if any (`hold-launcher --reap`, see below). For the
game (`swtor.exe`) it also:

- starts the engine's wineserver in its own session (`setsid-exec`), and sends the game's output
  to `wine.log` instead of the launcher's pipe;
- runs `hold-launcher`: the launcher quits ~30 s after starting the game, and its exit takes the
  engine's wineserver with it, so the launcher is hidden and frozen (SIGSTOP) until the game
  exits, then resumed to finish quitting. It waits in kqueue: nothing polls. Once the launcher
  has quit (within 2 minutes of the game), it ends the engine's Wine session
  (`wineserver -k`), waits up to 10 s for its wineserver to go, and then ends whatever is left
  of the engine, each logged in `hold.log`;
- links CrossOver's re-exec name for the game (`winetemp-…/swtor.exe`) to
  `gamemode/SWTOR.app`, a bundle with `LSSupportsGameMode` around an identical clone of the
  engine's preloader, so macOS turns Game Mode on.

Leftover Wine processes are processes of SWTOR on Mac's engine (its preloader, or CrossOver's
`winetemp-<inode>-…` hard links of it) while no wineserver of the engine runs: what is left of
a session whose server is gone, such as a `winedevice.exe` that would wait forever. They don't
block anything: the window says so and offers **End Leftover Wine Processes**, and Install,
Uninstall and the Retina setting end them first (logged in `install.log`). The launcher, the
game, Broadsword's Wine or a running Wine session of the engine (its wineserver) do block
those; the window says which, and the buttons say why when clicked. The window looks again
when it becomes active and when the launcher or the game quits.

Fixed settings (`env` and the prefix's registry): `WINEMSYNC=1`, `WINEDEBUG=-all`,
`WINEDLLOVERRIDES=d3d9=n,b` (also per app for `swtor.exe`), `d3d9.allowOutOfRangeVsDefs = True`
in d9mt's `dxvk.conf`, and `GrabPointer=n` for `swtor.exe` (no hitch when mouse-look starts).
Vsync is on by default because SWTOR asks for none in borderless mode, which tears. The rest is
in the Settings window (above).

The installer is `src/som.sh` (`status`, `install`, `uninstall`, `settings`, `set`, `watch`,
`end-leftovers`);
the window (`src/native`, SwiftUI) runs it and shows its progress as a timeline. Install is idempotent and
all-or-nothing: it refuses while the launcher or game runs, checks every download against a
pinned sha256, prepares everything in SWTOR on Mac's folders first, touches Broadsword's folder
last, and rolls back if anything fails. If Broadsword's Wine folder holds a Wine wrapper that is
not SWTOR on Mac's (for example the developer's own setup), it says so and leaves it alone
unless you confirm; it then keeps a copy in `backup/`.

### Testing without touching the system

`som.sh` takes `SWTOR_ON_MAC_ROOT=/abs/dir` (every path, official install included, under that
directory) and `SWTOR_ON_MAC_DRY_RUN=1` (print the changes, make none). The app passes both on,
so `SWTOR_ON_MAC_ROOT=/tmp/x "SWTOR on Mac.app/Contents/MacOS/SWTORonMac"` shows the window for
a sandbox. In a sandbox the launchd job is written but not loaded, and notifications go to
`notifications.log`. `scripts/test-sandbox.sh` builds a sandbox from APFS clones of this Mac's
official install and runs install, the settings, reinstall, the wrapper's update check (with a
stub engine and a local feed), a simulated launcher update and the launchd job's repair (run as
launchd would), leftover Wine processes (dummy programs under the sandbox engine: what
`status` reports, that only they end, from `end-leftovers`, install, uninstall, the wrapper and
`hold-launcher` after a fake launcher and game, and never while a wineserver runs), a failed install, Collect Logs, the conflict cases and uninstall end to end,
checking that uninstall restores Broadsword's folder byte for byte, copies the game settings
back and that no Wine process is left behind. `scripts/test-update.sh` tests app updates with
two Developer ID builds and a local feed, as in SWGL on Mac.

## Building

- `scripts/build-d9mt.sh` builds d9mt (x86_64) at a pinned commit of
  [jdrly/d9mt](https://github.com/jdrly/d9mt) in a scratch clone into `prebuilt/d9mt`
  (Homebrew bash, mingw-w64, cmake, ninja, Xcode; an LLVM 15 build for macOS 26 via
  `D9MT_LLVM`).
- `build.sh` assembles `dist/SWTOR on Mac.app` with Sparkle (pinned download; ad-hoc signed;
  `--install` copies it to /Applications). Needs Xcode 27 (macOS 27 SDK); the app runs on
  macOS 26 and later.
- `scripts/release.sh` signs a copy with the Developer ID (hardened runtime; the helpers get
  `allow-dyld-environment-variables`, the app and Sparkle no exceptions), builds the DMG,
  notarizes and staples it, and builds the Sparkle feed (`appcast.xml` with delta updates from
  the last 5 versions in `release/updates/`, checked by `scripts/check-appcast.swift`), then
  drafts the GitHub release (`--sign-only`, `--no-notarize`, `--no-release` for local runs;
  `--ci`, `--feed <version>` for the two halves of a CI release, as in SWGL on Mac).
- `.github/workflows/checks.yml` lints the scripts and builds the app;
  `.github/workflows/release.yml` signs and notarizes on a `v*` tag; Sparkle's EdDSA key never
  leaves Jan's Mac, so the feed is added with `scripts/release.sh --feed <version>` there.

`prebuilt/` holds the d9mt binaries, so `build.sh` works from a fresh clone.

## Pinned components

| Component | Source | sha256 |
|---|---|---|
| Wine engine `WS12WineCX24.0.7_7` (CrossOver 24.0.7, Wine 9.0, x86_64) | [Sikarugir-App/Engines v1.0](https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineCX24.0.7_7.tar.xz) | `203f9e9fd6c2cc77e6525d798a434ced326145db34a356355e05659d3445fd1c` |
| Engine libraries (`Template-1.0.21.app/Contents/Frameworks`, without `renderer/`) | [Sikarugir-App/Template v1.0](https://github.com/Sikarugir-App/Template/releases/download/v1.0/Template-1.0.21.tar.xz) | `bbe996e4e4375318485953d0c7818b7b4b0a4dc1f13303bcc584f99f7602f78d` |
| Sparkle 2.10.0 (bundled) | [sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0) | `c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c` |
| d9mt `159bec7` (bundled, `prebuilt/d9mt`) | [jdrly/d9mt](https://github.com/jdrly/d9mt/tree/159bec7c5f3433cb3273db2ed576464086ac762c) | see `prebuilt/d9mt` |

## Credits and licenses

- Star Wars: The Old Republic, its launcher and game files belong to their owners (Broadsword
  Games, Electronic Arts, Lucasfilm, Disney). SWTOR on Mac ships none of them.
- [d9mt](https://github.com/jdrly/d9mt) by Jan Drlý, based on neo773's
  [d9mt-v2](https://github.com/neo773/d9mt-v2), with DXVK and DXMT code: zlib, its winemetal
  bridge LGPL-2.1-or-later (source: `bridge/` of the pinned commit). Licenses and third-party
  notices ship in the app under `Resources/Licenses/d9mt`.
- [Wine](https://www.winehq.org) (LGPL-2.1-or-later) from CodeWeavers' CrossOver 24.0.7
  sources, built by [Sikarugir](https://github.com/Sikarugir-App); the engine and its
  libraries are downloaded from Sikarugir's releases at install time, not redistributed.
- [Sparkle](https://sparkle-project.org) for app updates (MIT-style license, in the app under
  `Resources/Licenses/sparkle`).
- Built after the example of SWGL on Mac.

## License

The code in this repository is under the [zlib license](LICENSE). The files in `prebuilt/` and
everything the installer downloads keep their own licenses (see above).
