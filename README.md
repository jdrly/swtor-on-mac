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

Install again (**Reinstall**) whenever you like, for example after the official launcher has
updated itself: it is safe to repeat and keeps your game settings. The window shows when a
launcher update has removed the hook (*Wine wrapper: Removed by a launcher update*).

## Uninstall

Quit the launcher and the game, open SWTOR on Mac and click **Uninstall…**. The official app
goes back to exactly how Broadsword ships it, and SWTOR on Mac's engine, prefix and settings are
deleted, including the game settings stored in its prefix (graphics options, UI layouts and key
bindings saved on this Mac; characters live on the server and are not affected). Logs stay in
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
  - `env` – the settings the wrapper applies, `dxvk.conf` – d9mt's options
  - `install-manifest.json` – what was changed, for Uninstall
  - `backup/` – only if you replaced another Wine wrapper: a copy of it
- `~/Library/Logs/SWTOR on Mac/` – `install.log`, and per game start `wine.log` (d9mt
  warnings), `hold.log`, `launch-env.txt`, `effective-env.txt`

To revert by hand: in Broadsword's `Wine` folder, move `bin-real/wine-preloader` and
`bin-real/wine64-preloader` back into `bin/` (replacing the scripts there), delete `bin-real`,
and delete `~/Library/Application Support/SWTOR on Mac`. Deleting only the latter also works:
the wrapper then runs Broadsword's own Wine.

## How it works

The official launcher starts every Wine process through `bin/wine64`, which loads
`bin/wine64-preloader`. The wrapper (`src/wine-wrapper.sh`) sits in its place, reads
`~/Library/Application Support/SWTOR on Mac/env` and runs the command on SWTOR on Mac's engine
and prefix instead (falling back to Broadsword's real preloader if those are missing). For the
game (`swtor.exe`) it also:

- starts the engine's wineserver in its own session (`setsid-exec`), and sends the game's output
  to `wine.log` instead of the launcher's pipe;
- runs `hold-launcher`: the launcher quits ~30 s after starting the game, and its exit takes the
  engine's wineserver with it, so the launcher is hidden and frozen (SIGSTOP) until the game
  exits, then resumed to finish quitting; afterwards orphaned Wine processes of the engine are
  cleaned up. It waits in kqueue: nothing polls;
- links CrossOver's re-exec name for the game (`winetemp-…/swtor.exe`) to
  `gamemode/SWTOR.app`, a bundle with `LSSupportsGameMode` around an identical clone of the
  engine's preloader, so macOS turns Game Mode on.

Settings (`env` and the prefix's registry): `WINEMSYNC=1`, `WINEDEBUG=-all`,
`WINEDLLOVERRIDES=d3d9=n,b` (also per app for `swtor.exe`), d9mt's `dxvk.conf` with
`d3d9.presentInterval = 1` (vsync; SWTOR asks for none in borderless mode) and
`d3d9.allowOutOfRangeVsDefs = True`, `DXVK_LOG_LEVEL=warn`, Wine's Mac driver `RetinaMode=y`,
and `GrabPointer=n` for `swtor.exe` (no hitch when mouse-look starts). The Metal HUD is off; add
`MTL_HUD_ENABLED=1` to `env` to see frame rates.

The installer is `src/som.sh` (`status`, `install`, `uninstall`); the window
(`src/native/App.swift`, SwiftUI) runs it and shows its progress. Install is idempotent and
all-or-nothing: it refuses while the launcher or game runs, checks every download against a
pinned sha256, prepares everything in SWTOR on Mac's folders first, touches Broadsword's folder
last, and rolls back if anything fails. If Broadsword's Wine folder holds a Wine wrapper that is
not SWTOR on Mac's (for example the developer's own setup), it says so and leaves it alone
unless you confirm; it then keeps a copy in `backup/`.

### Testing without touching the system

`som.sh` takes `SWTOR_ON_MAC_ROOT=/abs/dir` (every path, official install included, under that
directory) and `SWTOR_ON_MAC_DRY_RUN=1` (print the changes, make none). The app passes both on,
so `SWTOR_ON_MAC_ROOT=/tmp/x "SWTOR on Mac.app/Contents/MacOS/SWTORonMac"` shows the window for
a sandbox. `scripts/test-sandbox.sh` builds a sandbox from APFS clones of this Mac's official
install and runs install, reinstall, a simulated launcher update, a failed install, the
conflict cases and uninstall end to end, checking that uninstall restores Broadsword's folder
byte for byte and that no Wine process is left behind.

## Building

- `scripts/build-d9mt.sh` builds d9mt (x86_64) at a pinned commit of
  [jdrly/d9mt](https://github.com/jdrly/d9mt) in a scratch clone into `prebuilt/d9mt`
  (Homebrew bash, mingw-w64, cmake, ninja, Xcode; an LLVM 15 build for macOS 26 via
  `D9MT_LLVM`).
- `build.sh` assembles `dist/SWTOR on Mac.app` (ad-hoc signed; `--install` copies it to
  /Applications). Needs Xcode 27 (macOS 27 SDK); the app runs on macOS 26 and later.
- `scripts/release.sh` signs a copy with the Developer ID (hardened runtime, entitlements in
  `src/entitlements`), builds the DMG, and notarizes and staples it (`--sign-only`,
  `--no-notarize` for dry runs).
- `.github/workflows/checks.yml` lints the scripts and builds the app;
  `.github/workflows/release.yml` signs and notarizes on a `v*` tag.

`prebuilt/` holds the d9mt binaries, so `build.sh` works from a fresh clone.

## Pinned components

| Component | Source | sha256 |
|---|---|---|
| Wine engine `WS12WineCX24.0.7_7` (CrossOver 24.0.7, Wine 9.0, x86_64) | [Sikarugir-App/Engines v1.0](https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineCX24.0.7_7.tar.xz) | `203f9e9fd6c2cc77e6525d798a434ced326145db34a356355e05659d3445fd1c` |
| Engine libraries (`Template-1.0.21.app/Contents/Frameworks`, without `renderer/`) | [Sikarugir-App/Template v1.0](https://github.com/Sikarugir-App/Template/releases/download/v1.0/Template-1.0.21.tar.xz) | `bbe996e4e4375318485953d0c7818b7b4b0a4dc1f13303bcc584f99f7602f78d` |
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
- Built after the example of SWGL on Mac.

## License

The code in this repository is under the [zlib license](LICENSE). The files in `prebuilt/` and
everything the installer downloads keep their own licenses (see above).
