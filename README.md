# SWTOR on Mac

A small macOS app that makes the official [Star Wars: The Old Republic](https://www.swtor.com)
Mac app run faster on Apple Silicon. It installs a performance setup on top of your existing
official install: the game's Direct3D 9 goes straight to Metal with
[d9mt](https://github.com/jdrly/d9mt), on a newer Wine (CrossOver 24.0.7), with macOS Game
Mode. You start the game with **Play SWTOR** in its window, or from the official app as usual.

> **SWTOR on Mac is an unofficial community project.** It is not made, endorsed or supported
> by Broadsword Games, Electronic Arts, Lucasfilm or Disney. Broadsword doesn't support
> third-party tools or compatibility layers, so you use it at your own risk.
>
> **It's not a game mod.** It doesn't change the game's files, memory or network traffic and
> doesn't affect gameplay. It only replaces the compatibility layer the official Mac app
> already runs on (Wine, plus d9mt for Direct3D 9 on Metal), the same kind of software as
> CrossOver or Proton, and Uninstall puts that back the way Broadsword ships it.
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
  profile, Game Mode, the Metal HUD, game keys by keyboard position (for non-US layouts),
  debug logging, automatic update checks.
- **Updates**: the app updates itself with [Sparkle](https://sparkle-project.org) (SWTOR on
  Mac > Check for Updates…), and the game's start looks for a new version once a day.
- **Survives launcher updates**: when the official launcher updates its Wine and drops SWTOR on
  Mac's hook, a small launchd job hooks it back in by itself.
- **Collect Logs…** makes a zip for bug reports, without account names or passwords.
- **Fully reversible**: Uninstall puts the official app back exactly as Broadsword ships it and
  copies your game settings back to it.

<img src="docs/screenshots/installing-steps.png" width="360" alt="Installing: the timeline of the steps"> <img src="docs/screenshots/settings.png" width="360" alt="The Settings window"> <img src="docs/screenshots/installed-dark.png" width="360" alt="Installed, in dark mode">

More in [docs/screenshots](docs/screenshots) (the notice, a failed install, uninstall, a narrow
window).

## Install

**Requirements:**

- A Mac with Apple Silicon and macOS 26 or later (developed on macOS 27).
- The **official SWTOR Mac app, installed first** from [swtor.com](https://www.swtor.com) and
  started once, so it has set up the game. SWTOR on Mac never downloads the launcher or the
  game; without the official install it refuses to do anything.
- Rosetta (macOS offers it when you first start the official app).
- About 2 GB of free space and an internet connection for the install (it downloads the Wine
  engine and its libraries, ~270 MB, from their official source).

1. Download `SWTOR-on-Mac-<version>.dmg` from
   [Releases](https://github.com/jdrly/swtor-on-mac/releases), open it and drag
   **SWTOR on Mac** into Applications.
2. Quit the SWTOR launcher and the game.
3. Open **SWTOR on Mac**, click **Review the Notice…**, read it, tick *I understand, and I use
   SWTOR on Mac at my own risk* and click **Continue**, then **Install SWTOR on Mac**. It takes
   a minute or two; the window shows each step.
4. Click **Play SWTOR** (or start SWTOR from the official app as usual). The launcher looks and
   works the same; the game runs on SWTOR on Mac's engine.

The app is signed and notarized by Apple. It checks for updates once a day and offers new
versions with a click (see [Updates](#updates)).

**The first minutes of play may stutter**, and so may each new area or effect the first time
you see it (for example a city full of players): d9mt compiles the game's shaders and pipelines
for Metal the first time it meets them and caches them, so it gets smooth after that. After an
update of SWTOR on Mac the cache is rebuilt once.

Install again (**Reinstall**) whenever you like: it is safe to repeat and keeps your game
settings and SWTOR on Mac's settings.

## Using it

- **SWTOR on Mac menu:** *About SWTOR on Mac*, *Check for Updates…*, *Settings…* (⌘,) and
  *Collect Logs…* (see [Reporting problems](#reporting-problems)).
- **Play SWTOR**, the big button once SWTOR on Mac is installed (and at the end of an install),
  opens the official SWTOR app; log in and press Play in its launcher as usual. If the launcher
  or the game already runs, the button says **Show SWTOR Launcher** (or *Show SWTOR*) and
  brings it to the front. It is off, with the reason under it, while the official app is
  missing, the launcher hook is not active (*Repair the Launcher Hook* comes first then) or an
  install runs. Turn on *Quit SWTOR on Mac after launching* in Settings to have the app quit
  once the official app is open.
- **The window** shows the state of this Mac (the official app, Rosetta, SWTOR on Mac, the
  launcher hook, d9mt and the engine) and offers Reinstall, Settings and Uninstall. It looks
  again whenever it becomes active and when the launcher or the game starts or quits.
- SWTOR on Mac does not need to be open to play: the official app starts the game on SWTOR on
  Mac's engine by itself.

### Settings

SWTOR on Mac > **Settings…** (⌘,), while SWTOR on Mac is installed. A sidebar of panes
(Graphics, Game, Keyboard, Play Button, Updates, Troubleshooting; the window opens on the one
used last) and the selected pane's settings. Changes take effect the next time the game starts.

| Setting | Default | What it changes |
|---|---|---|
| Retina Mode | on | Wine's Mac driver `RetinaMode` in the prefix's registry (only while the launcher and the game are closed) |
| Vsync | on | `d3d9.presentInterval = 1` in `dxvk.conf` (off: unset) |
| Video Memory Profile | Automatic | `D9MT_MEMORY_PROFILE` (auto, low, medium, high, ultra, unlimited). The video memory the game is told it has: Low 2 GB, Medium 3 GB, High and above 4 GB. Automatic picks by the Mac's memory: 8 GB Low, 16 GB Medium, 24 GB High, more Ultra |
| Game Mode | on | `SWTOR_GAMEMODE_APP` in `env` |
| Show Metal HUD | off | `MTL_HUD_ENABLED=1` in `env`. It can't be toggled with a key in the game; turn it on here before starting the game |
| Game keys by keyboard position | off | The game sees every key by its position on a US keyboard (see below): SWTOR on Mac's build of Wine's Mac driver in its engine and `PhysicalKeyboard=y` for `swtor.exe` in the prefix's registry; off, the engine's own driver (only while the launcher and the game are closed) |
| Check for updates automatically | on | Sparkle's automatic checks and the daily check at the game's start |
| Debug Logging | off | `DXVK_LOG_LEVEL=info`, `D9MT_PROFILE=1`, `D9MT_MEMSTATS=1`, `D9MT_DEBUG_FILE=C:\d9mt\flags.txt` (d9mt's live debug flags, below; else `DXVK_LOG_LEVEL=warn`) |
| Quit SWTOR on Mac after launching | off | The app quits once **Play SWTOR** has opened the official app (the app's own preference) |

They are kept in `~/Library/Application Support/SWTOR on Mac/settings.conf`; `env` and
`dxvk.conf` are made from it (`som.sh settings`, `som.sh set <key> <value>`). *Quit SWTOR on
Mac after launching* is kept in the app's preferences instead.

**Game keys by keyboard position** is for keyboard layouts whose keys type something else than
a US keyboard's. Wine names a key by what it types in your current layout, so with Czech the
game's key binds and action bars show the number row as *+ ě š č ř ž ý á í é* (French: *& é "
' (*…). With the setting on, the game sees every key by its position on a US keyboard: the
number row is 1–0, the key right of P is `[`, and so on, in key binds and action bars. Typing
in chat still uses your layout (ě š č, dead keys like ´ + e = é, Shift and Option). The
catch: everything follows US positions, so on QWERTZ layouts (Czech, German) the key labelled
Z is *Y* in the game and the other way round. Settings says when your current layout's number
row doesn't type 1–0. It works with the patched Mac driver, which is used only while the
setting is on (see [Credits and licenses](#credits-and-licenses)); changing it needs no
Reinstall.

## Updates

- The app checks [its feed](https://github.com/jdrly/swtor-on-mac/releases/latest/download/appcast.xml)
  with Sparkle, signed with an EdDSA key (`SUPublicEDKey`), and asks before installing; SWTOR on
  Mac > **Check for Updates…** checks right away.
- At most once a day, when the game starts, the Wine wrapper looks at the same feed in a
  detached process (2 s timeout; the game never waits for it, offline it does nothing). If
  there is a newer version it posts a notification, *SWTOR on Mac update available — open the
  app to update*, and the app then offers the update when it is opened.
- After an app update, click **Update to &lt;version&gt;** in the window: it brings the
  installed setup (wrapper, d9mt) up to the app's version.

### Development builds

Versions like `0.0.6-dev.1` are test builds of the next version. They are published only as
GitHub **pre-releases** (DMG only, no `appcast.xml`), so the feed above never offers them, and
they differ from releases in three ways:

- A **Development build** badge next to the title, and in About.
- **Debug Logging is on by default.** The first install or Reinstall of each dev version turns
  it on, so every test session logs the `STATS`/`HITCH`/`DIAG MEM` lines the session report
  reads. Turned off in Settings, it stays off until the next dev version.
- **No automatic update checks**, neither Sparkle's nor the wrapper's at game start; the
  setting is shown off. **Check for Updates…** still works. A dev build's `CFBundleVersion`
  (what Sparkle compares) sorts between the previous release and its own:
  `0.0.6-dev.N` is `0.0.5.(1000+N)`. So the feed's 0.0.5 is never offered as an update, and the
  public 0.0.6 is offered once it is out. `CFBundleShortVersionString` stays `0.0.6-dev.N`.

**Session report.** `"/Applications/SWTOR on Mac.app/Contents/Resources/session-report.sh"`
(`scripts/session-report.sh`) sums up the last game session from
`~/Library/Logs/SWTOR on Mac/wine.log`:
- duration, median and 1%-low fps, the seconds below 58 fps;
- frames over 33 ms and 50 ms;
- hitches, split into d9mt's and the game's, and d9mt's top causes;
- compile waits and the memory peak;
- render passes and the attachment traffic d9mt saved, and (0.0.6-dev.3 and later) the
  render thread's CPU time in that optimization and the clears per frame, to tell its cost
  apart from compile waits (a cold shader cache);
- the attachment re-clears by cause, from the `RESTORE` lines (d9mt 0.0.6-dev.2 and later):
  image format and size, the aspects re-cleared, why and the D3D9 call, per frame.

`wine.log` starts afresh at every game start, so `--keep` saves a copy to `sessions/`.
`--compare A.log B.log` puts two sessions side by side. `--skip <s>` leaves out the first
seconds (loading). Collect Logs adds the report as `session-report.txt`. Logs from 0.0.5 have
no `STATS` lines: hitches, compile waits and memory still compare.

**Live d9mt flags.** With Debug Logging on, d9mt reads
`~/Library/Application Support/SWTOR on Mac/prefix/drive_c/d9mt/flags.txt` (`C:\d9mt\flags.txt`)
once a second while the game runs: one flag per line, `#` comments; the file is written with
every flag commented out, and edits are kept. `no_attach_opt` switches d9mt's attachment
load/store optimization off and back on live (A/B), `att_trace` logs up to 400 render-pass
decisions and re-clears to `wine.log` (remove and re-add the line for 400 more), `dump` dumps
the next frame's draws into that folder. For example:

```bash
F="$HOME/Library/Application Support/SWTOR on Mac/prefix/drive_c/d9mt/flags.txt"
echo att_trace >>"$F"                          # trace on
sed -i '' '/^att_trace$/d' "$F"                # trace off
echo no_attach_opt >>"$F"                      # optimization off (A/B)
sed -i '' '/^no_attach_opt$/d' "$F"            # back on
```

### Launcher updates (the launchd job)

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
Mac/watch.log`. If that did not work, the window shows *Launcher hook: Removed by a launcher
update* and a **Repair the Launcher Hook** button.

## Reporting problems

1. Choose **SWTOR on Mac > Collect Logs…**. It saves `SWTOR-on-Mac-logs-<date>.zip` to your
   Desktop (or, without access to the Desktop, to `~/Library/Logs/SWTOR on Mac`) and shows it
   in Finder.
2. Send that zip with a short description of what happened and when to **Pharaphobia on
   Discord** or attach it to a [GitHub issue](https://github.com/jdrly/swtor-on-mac/issues/new/choose).
   Please don't send it to Broadsword or SWTOR customer support: they don't support SWTOR on
   Mac.

The zip holds SWTOR on Mac's logs, `env`, `settings.conf`, `dxvk.conf`,
`install-manifest.json`, the versions, system information (macOS, chip, memory, displays) and
crash reports of the last 7 days for the game and Wine. Your home folder, user name, account
names and e-mail addresses are replaced, serial numbers and device identifiers are left out,
and the game's command line (the launcher passes the account on it) is never included. Turn on
**Settings > Debug Logging** only when asked: it makes the logs much more detailed for the next
game start, at some cost in performance, so turn it off again afterwards.

## Known issues (0.0.x test versions)

- **Stutter the first time** you see an area or effect, while d9mt compiles and caches its
  shaders (see [Install](#install)). It gets smooth after that.
- **Retina Mode** can only be changed while the launcher and the game are closed (it is in the
  Wine prefix's registry).
- **The Metal HUD** can't be toggled with a key in the game; turn it on in Settings before
  starting the game.
- **Non-US keyboard layouts**: without *Game keys by keyboard position* the game names keys by
  what your layout types (Czech: *+ ě š* … on the number row). With it, keys are named by
  their US positions, so on QWERTZ layouts Z and Y swap names in the game. It can only be
  changed while the launcher and the game are closed.
- **Official launcher updates** replace SWTOR on Mac's hook. The launchd job puts it back by
  itself, but if the update looks unfinished it only notifies, and you click **Reinstall**.
- **Blurry or missing textures in busy places** on 8 or 16 GB Macs: the game gets 2 or 3 GB of
  video memory there (official app: about 4 GB). Raise **Video Memory Profile** in Settings if
  macOS has memory to spare; lower it if macOS runs short of memory.
- Like the official Mac app, everything runs under **Rosetta** (the launcher and Wine are
  x86_64). Apple Silicon only.
- Only the official Mac app from swtor.com is supported (not the Windows or Steam version in
  CrossOver or other Wine setups).

## Troubleshooting

- **Official SWTOR app: Not found.** Install it from [swtor.com](https://www.swtor.com) into
  Applications and start it once, so it sets up the game.
- **Rosetta: Not installed.** Start the official SWTOR app once; macOS offers to install
  Rosetta.
- **A button says the launcher, the game or Wine is running.** Quit the SWTOR launcher and the
  game. SWTOR on Mac's own Wine ends by itself a few seconds after they quit.
- **Leftover Wine processes of SWTOR on Mac's engine.** Click **End Leftover Wine Processes**
  (Install, Uninstall, the Retina setting and Game keys by keyboard position also end them
  first).
- **Another Wine wrapper is installed** in Broadsword's Wine folder (another tool, or a manual
  setup). SWTOR on Mac leaves it alone unless you confirm; it then keeps a copy in
  `~/Library/Application Support/SWTOR on Mac/backup/`.
- **The game does not start, crashes, or looks wrong.** Collect Logs and report it (see
  [Reporting problems](#reporting-problems)). To compare with the official setup, Uninstall:
  the official app then runs exactly as Broadsword ships it.
- **An install failed.** The window says why, and the install was rolled back; the full log is
  `~/Library/Logs/SWTOR on Mac/install.log`. Click **Try Again**, or report it with Collect
  Logs.

## Uninstall

Quit the launcher and the game, open SWTOR on Mac and click **Uninstall…**. Your game settings
(graphics options, UI layouts, key bindings: `AppData/Local/SWTOR/swtor/settings` of SWTOR on
Mac's prefix, without `ContextError.ini`) are copied back to Broadsword's prefix first, with a
copy of its previous ones next to them (`settings-backup-<time>`). Then the official app goes
back to exactly how Broadsword ships it, and SWTOR on Mac's engine, prefix, settings, downloads
and launchd job are deleted (characters live on the server and are not affected). Logs stay in
`~/Library/Logs/SWTOR on Mac`. Then move the app to the Bin.

### What it changes

In Broadsword's install (`~/Library/Application Support/com.broadsword.swtor/Star Wars - The
Old Republic/swtor-precompiled/Libraries/Wine`), and nowhere else in it:

| | Before | After |
|---|---|---|
| `bin/wine64-preloader`, `bin/wine-preloader` | Broadsword's Wine preloaders | SWTOR on Mac's wrapper script |
| `bin-real/` | – | Broadsword's preloaders (moved, not changed), `hold-launcher`, `setsid-exec` |

The game files, the launcher app and Broadsword's Wine prefix are only read (the prefix is
cloned once). Everything else lives in SWTOR on Mac's own folders:

- `~/Library/Application Support/SWTOR on Mac/`
  - `engine/` – the Wine engine, with d9mt's winemetal bridge (and, while *Game keys by
    keyboard position* is on, SWTOR on Mac's build of its Mac driver `winemac.so`; the
    engine's own is kept as `winemac.so.stock`)
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
- `~/Library/LaunchAgents/cz.jandrly.swtoronmac.watch.plist` – the launchd job (see
  [Launcher updates](#launcher-updates-the-launchd-job))
- `~/Library/Caches/SWTOR on Mac/downloads` – the engine downloads, only during an install
- `winetemp-…/swtor.exe` in your per-user temporary folder (`$TMPDIR`) – the Game Mode link,
  made at each game start
- `~/Library/Logs/SWTOR on Mac/` – `install.log`, `watch.log`, and per game start `wine.log`
  (d9mt warnings), `hold.log`, `launch-env.txt`, `effective-env.txt`

### Removing it by hand

If the app is gone or Uninstall can't run, quit the launcher and the game and run this in
Terminal. It puts Broadsword's preloaders back from `bin-real`, then removes the launchd job
and SWTOR on Mac's folders:

```sh
W="$HOME/Library/Application Support/com.broadsword.swtor/Star Wars - The Old Republic/swtor-precompiled/Libraries/Wine"
for p in wine-preloader wine64-preloader; do
  # only where bin/ still holds the wrapper script (a launcher update may have put a newer preloader there)
  if [ "$(head -c 2 "$W/bin/$p")" = '#!' ]; then mv -f "$W/bin-real/$p" "$W/bin/$p"; fi
done
rm -rf "$W/bin-real"
launchctl bootout "gui/$(id -u)/cz.jandrly.swtoronmac.watch"
rm -f ~/Library/LaunchAgents/cz.jandrly.swtoronmac.watch.plist
rm -rf ~/Library/Application\ Support/SWTOR\ on\ Mac ~/Library/Caches/SWTOR\ on\ Mac
```

Afterwards `bin/wine-preloader` and `bin/wine64-preloader` must be Mach-O programs again
(`file "$W/bin/wine64-preloader"`); if not, reinstall the official app from swtor.com. Unlike
Uninstall, this does not copy your
game settings back: to keep them, first copy the `settings` folder from
`~/Library/Application Support/SWTOR on Mac/prefix/drive_c/users/crossover/AppData/Local/SWTOR/swtor/`
to `drive_c/users/<your user name>/AppData/Local/SWTOR/swtor/` in Broadsword's `Wine` folder
(`$W`, which is also its prefix). Deleting only `~/Library/Application Support/SWTOR on Mac`
also works: the wrapper then runs Broadsword's own Wine. Logs stay in
`~/Library/Logs/SWTOR on Mac`.

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
`end-leftovers`); the window (`src/native`, SwiftUI) runs it and shows its progress as a
timeline. Install is idempotent and all-or-nothing: it refuses while the launcher or game runs,
checks every download against a pinned sha256, prepares everything in SWTOR on Mac's folders
first, touches Broadsword's folder last, and rolls back if anything fails. If Broadsword's Wine
folder holds a Wine wrapper that is not SWTOR on Mac's (for example the developer's own setup),
it says so and leaves it alone unless you confirm; it then keeps a copy in `backup/`.

### Testing without touching the system

`som.sh` takes `SWTOR_ON_MAC_ROOT=/abs/dir` (every path, official install included, under that
directory) and `SWTOR_ON_MAC_DRY_RUN=1` (print the changes, make none). The app passes both on,
so `SWTOR_ON_MAC_ROOT=/tmp/x "SWTOR on Mac.app/Contents/MacOS/SWTORonMac"` shows the window for
a sandbox. In a sandbox the launchd job is written but not loaded, notifications go to
`notifications.log`, and Play SWTOR opens only the sandbox's official app
(`SWTORonMac --play-target` prints what the button would do, without opening anything). `scripts/test-sandbox.sh` builds a sandbox from APFS clones of this Mac's
official install and runs install, the settings, reinstall, the wrapper's update check (with a
stub engine and a local feed), a simulated launcher update and the launchd job's repair (run as
launchd would), leftover Wine processes (dummy programs under the sandbox engine: what
`status` reports, that only they end, from `end-leftovers`, install, uninstall, the wrapper and
`hold-launcher` after a fake launcher and game, and never while a wineserver runs), a failed
install, Collect Logs, what Play SWTOR would open, *Game keys by keyboard position* (the Mac
driver and the registry value, and what the game sees: a probe program run as `swtor.exe`
with Czech, German and US layouts, picked through the driver's `WINEMAC_TEST_KEYBOARD_LAYOUT`
test hook without changing the Mac's input source), the conflict cases and uninstall end to end, checking that uninstall
restores Broadsword's folder byte for byte, copies the game settings back and that no Wine
process is left behind. `scripts/test-update.sh` tests app updates with two Developer ID builds
and a local feed, as in SWGL on Mac.

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
  `.github/workflows/release.yml` signs and notarizes on a `v*` tag. Both build on GitHub's
  `xcode-27` image (macOS 27 with Xcode 27, a public preview; there is no `macos-27` label).

- `scripts/build-winemac.sh` builds Wine's Mac driver (`winemac.so`, x86_64) from CodeWeavers'
  CrossOver 24.0.7 sources (pinned sha256; the engine download pinned in `src/som.sh` for
  linking) with `patches/winemac-physical-keys.patch` into `prebuilt/winemac`, together with an
  unpatched build: `scripts/winemac-compare.py` checks that one against the engine's own file
  and that the patch changes only the keyboard functions and the option (Xcode, Rosetta,
  Homebrew bison and mingw-w64). The build is reproducible.

`prebuilt/` holds the d9mt binaries and the Mac driver, so `build.sh` works from a fresh clone. Build outputs
(`dist/`, `release/`) are not committed; DMGs, deltas and `appcast.xml` are release assets.

### Releasing

Sparkle's EdDSA key never leaves Jan's Mac, so a release comes in two halves:

1. Bump `APP_VERSION` in `build.sh`, add `release-notes/<version>.md`, commit, then tag and
   push: `git tag v<version> && git push origin main v<version>`.
2. The Release workflow (after approval in the `release` environment) builds, signs and
   notarizes the app, and creates the draft release `v<version>` with the DMG.
3. On the Mac: `./build.sh` (it unpacks Sparkle's tools), then
   `scripts/release.sh --feed <version>`. It downloads the notarized DMG from the draft, checks
   it, builds and checks `appcast.xml` (and deltas from the older DMGs in `release/updates/`)
   and uploads them to the draft.
4. Publish the draft. The update is live once
   `https://github.com/jdrly/swtor-on-mac/releases/latest/download/appcast.xml` names the new
   version.

Development builds (`APP_VERSION` `X.Y.Z-dev.N`, on the `dev` branch) don't go through CI:
`./build.sh && scripts/release.sh --dev`. It signs, notarizes and staples the DMG, then
creates the GitHub pre-release `v<version>` with the DMG and
`release-notes/<version>.md`, and no feed. The tag starts the Release workflow, which stops
at its version check; cancel the run. The other modes and the workflow refuse dev versions.

For the first release that is `git tag v0.0.1 && git push origin main v0.0.1`, then
`scripts/release.sh --feed 0.0.1` (no deltas: there is no older version). Without CI,
`./build.sh && scripts/release.sh` does everything on the Mac (sign, notarize, feed, draft).

## Pinned components

| Component | Source | sha256 |
|---|---|---|
| Wine engine `WS12WineCX24.0.7_7` (CrossOver 24.0.7, Wine 9.0, x86_64) | [Sikarugir-App/Engines v1.0](https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineCX24.0.7_7.tar.xz) | `203f9e9fd6c2cc77e6525d798a434ced326145db34a356355e05659d3445fd1c` |
| Engine libraries (`Template-1.0.21.app/Contents/Frameworks`, without `renderer/`) | [Sikarugir-App/Template v1.0](https://github.com/Sikarugir-App/Template/releases/download/v1.0/Template-1.0.21.tar.xz) | `bbe996e4e4375318485953d0c7818b7b4b0a4dc1f13303bcc584f99f7602f78d` |
| Sparkle 2.10.0 (bundled) | [sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0) | `c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c` |
| d9mt `7975e2e` (bundled, `prebuilt/d9mt`) | [jdrly/d9mt](https://github.com/jdrly/d9mt/tree/7975e2ea6a90493b2c565c75e4fd92bf73f986c6) | see `prebuilt/d9mt` |
| CrossOver 24.0.7 sources (for the Mac driver, `prebuilt/winemac`) | [CodeWeavers](https://media.codeweavers.com/pub/crossover/source/crossover-sources-24.0.7.tar.gz) | `56749e926df9f0437dbcea259cf0bff6657a43871af50182887fe15a84fc2e4e` |

## Credits and licenses

- Star Wars: The Old Republic, its launcher and game files belong to their owners (Broadsword
  Games, Electronic Arts, Lucasfilm, Disney). SWTOR on Mac ships none of them.
- [d9mt](https://github.com/jdrly/d9mt) by Jan Drlý, a fork of neo773's
  [d9mt-v2](https://github.com/neo773/d9mt-v2), with DXVK and DXMT code: zlib, its winemetal
  bridge LGPL-2.1-or-later (source: `bridge/` of the pinned commit). Licenses and third-party
  notices ship in the app under `Resources/Licenses/d9mt`.
- [Wine](https://www.winehq.org) (LGPL-2.1-or-later) from CodeWeavers' CrossOver 24.0.7
  sources, built by [Sikarugir](https://github.com/Sikarugir-App), with the libraries of
  Sikarugir's wrapper template; the engine and its libraries are downloaded from Sikarugir's
  releases at install time, not redistributed.
- Wine's Mac driver (`winemac.so`, LGPL-2.1-or-later), built from CodeWeavers' CrossOver
  24.0.7 sources with SWTOR on Mac's patch for *Game keys by keyboard position*
  ([`patches/winemac-physical-keys.patch`](patches/winemac-physical-keys.patch), by Jan Drlý):
  bundled in the app, with Wine's license and the patch under `Resources/Licenses/winemac`.
- [Sparkle](https://sparkle-project.org) for app updates (MIT, with bsdiff and other notices;
  in the app under `Resources/Licenses/sparkle`).
- Built after the example of [SWGL on Mac](https://github.com/jdrly/swgl-on-mac).

What the app bundles and what it downloads at install time, with their licenses:
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) (also in the app under `Resources/Licenses`).

## License

The code in this repository is under the [zlib license](LICENSE), except
`patches/winemac-physical-keys.patch`, a change to Wine and so under Wine's
LGPL-2.1-or-later. The files in `prebuilt/` and everything the build or the installer downloads
keep their own licenses (see above; d9mt's are in `prebuilt/d9mt`, the Mac driver's in
`prebuilt/winemac`).
