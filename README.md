# SWTOR on Mac

A small macOS app that makes the official [Star Wars: The Old Republic](https://www.swtor.com)
Mac app run faster on Apple Silicon. It installs a performance setup on top of your existing
official install: the game's Direct3D 9 goes straight to Metal with
[d9mt](https://github.com/jdrly/d9mt), on a newer Wine (CrossOver 26.3 with Wine 11, the
engine SWGL on Mac uses), with macOS Game Mode. You start the game with **Play SWTOR** in its window, or from the official app as usual.

> **SWTOR on Mac is an unofficial fan project.** It is not affiliated with or endorsed by
> Lucasfilm, Disney, Electronic Arts or Broadsword Online Games. Broadsword doesn't support
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
> STAR WARS is a registered trademark of Lucasfilm Ltd. Star Wars: The Old Republic and SWTOR
> are trademarks of their respective owners. Mac is a trademark of Apple Inc.

<img src="docs/screenshots/installed.png" width="720" alt="The SWTOR on Mac window after an install">

## Features

- **d9mt**: the game's Direct3D 9 goes straight to Metal, on CrossOver 26.3 (Wine 11), with
  macOS **Game Mode** and Retina rendering.
- **Settings** (SWTOR on Mac > Settings…, ⌘,): Retina mode, vsync, a frame rate limit (for
  heat and battery, optionally only on battery), d9mt's video memory profile, Game Mode, the Metal HUD, game keys by keyboard position (for non-US layouts),
  raw mouse-look and its speed, debug logging, automatic update checks.
- **Updates**: the app updates itself with [Sparkle](https://sparkle-project.org) (SWTOR on
  Mac > Check for Updates…), and the game's start looks for a new version once a day.
- **After launcher updates**: when the official launcher updates its Wine and drops SWTOR on
  Mac's hook, the app hooks itself back in the next time you open it (or press Play SWTOR). No
  background helper: nothing of SWTOR on Mac runs while the app is closed.
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
  engine, ~235 MB, from its official source).

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
for Metal the first time it meets them and caches them, so it gets smooth after that. d9mt also
remembers which pipelines the game used (its pipeline state cache, 0.1.1 and later) and
builds them again in the background while the game loads, so the next sessions, and the first
one after an update of SWTOR on Mac that changes d9mt's shader compiler, stutter less.

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
  again whenever it becomes active and when the launcher or the game starts or quits. It has
  the look of [swonmac.com](https://swonmac.com), in light and dark: the site's colours and
  typefaces, and behind the whole window a still image of the site's jump point and warp. The
  image is drawn once, so the window costs nothing while it stays open (the warp's animation
  is built but off: [docs/warp-video-loop.md](docs/warp-video-loop.md)).
- SWTOR on Mac does not need to be open to play: the official app starts the game on SWTOR on
  Mac's engine by itself.

### Settings

SWTOR on Mac > **Settings…** (⌘,), while SWTOR on Mac is installed. A sidebar of panes
(Graphics, Game, Keyboard, Mouse, Play Button, Updates, Troubleshooting; the window opens on
the one used last) and the selected pane's settings. Changes take effect the next time the game starts.

| Pane | Setting | Default | What it changes |
|---|---|---|---|
| Graphics | Retina Mode | on | Wine's Mac driver `RetinaMode` in the prefix's registry (only while the launcher and the game are closed) |
| Graphics | Vsync | on | `d3d9.presentInterval = 1` in `dxvk.conf` (off: unset) |
| Graphics | Frame Rate Limit | Off | `SWTOR_FPS_LIMIT` in `env` (0, 30, 40, 45, 60): the wrapper gives the game d9mt's `D9MT_FPS_CAP`. Even frame times, for less heat and a longer battery life: with vsync, a cap that divides the refresh rate keeps every frame on screen for the same number of refreshes (30 at 60 Hz: two; 40 at 120 Hz: three); 40 and 45 at 60 Hz keep the load even but show frames for one or two refreshes; at or above the refresh rate with vsync on it does nothing. `wine.log` names it (`frame rate limit:`, then d9mt's `frame cap` line) |
| Graphics | Only on battery | off | `SWTOR_FPS_LIMIT_BATTERY=1` in `env`: the limit only if the Mac draws from its battery when the game starts (the wrapper asks `pmset -g ps` once; nothing watches it while the game runs) |
| Graphics | Video Memory Profile | Automatic | `D9MT_MEMORY_PROFILE` (auto, low, medium, high, ultra, unlimited). The video memory the game is told it has: Low 2 GB, Medium 3 GB, High and above 4 GB. Automatic picks by the Mac's memory: 8 GB Low, 16 GB Medium, 24 GB High, more Ultra |
| Game | Game Mode | on | `SWTOR_GAMEMODE_APP` in `env` |
| Game | Show Metal HUD | off | `MTL_HUD_ENABLED=1` in `env`, from the next game start. In the game Shift+F9 hides and shows it; Shift+F12, or a triple-click inside the HUD's area (also while it is hidden), opens macOS's own HUD settings panel (Apple's `libMTLHud`, which has no option to turn that off) |
| Game | Metal HUD Position | Top Center | `MTL_HUD_ALIGNMENT` (top left, top center, top right, center left, centered, center right, bottom left, bottom center, bottom right) while the HUD is on. Top Center keeps the HUD's area away from buttons that get clicked quickly, such as Randomize in character creation (top right, Apple's default) |
| Keyboard | Game keys by keyboard position | off | The game sees every key by its position on a US keyboard (see below): SWTOR on Mac's build of Wine's Mac driver in its engine and `PhysicalKeyboard=y` for `swtor.exe` in the prefix's registry; off, the engine's own driver (only while the launcher and the game are closed) |
| Mouse | Raw mouse-look | on | While the game hides the pointer to turn the camera, the mouse's own moves from GameController's `GCMouse`, sent by an input thread of the Mac driver as they come, the macOS pointer frozen (see below): SWTOR on Mac's build of Wine's Mac driver in its engine and `RawMouseWhenCursorHidden=y` for `swtor.exe`; off, `n` (and the engine's own driver if *Game keys by keyboard position* is off too). Only while the launcher and the game are closed |
| Mouse | Mouse-Look Speed | 1× | `RawMouseGameControllerScale` for `swtor.exe` (0.5× to 3×): a factor on the macOS pointer's speed, which raw mouse-look matches at 1× |
| Updates | Check for updates automatically | on | Sparkle's automatic checks and the daily check at the game's start |
| Troubleshooting | Debug Logging | off | `DXVK_LOG_LEVEL=info`, `D9MT_PROFILE=1` (with d9mt's `STATS` and `PACE` lines every second: frame times, and how evenly the game calls Present and how its thread's time per frame splits into d9mt's D3D9 calls and the game's own work), `D9MT_MEMSTATS=1`, `D9MT_DEBUG_FILE=C:\d9mt\flags.txt` (d9mt's live debug flags, below; else `DXVK_LOG_LEVEL=warn`), and `SWTOR_GAME_WINEDEBUG=-all,warn+rawmouse,warn+threadcpu`: the wrapper sets it as the game's `WINEDEBUG`, so the app's Mac driver logs `THREADCPU` (from `swtor.exe` only, `ThreadCpuStats=y` in the prefix) (the CPU time of the game's busiest threads and of the wineserver, once a second) and `RAWMOUSE` (raw mouse-look, once a second while it moves) |
| Play Button | Quit SWTOR on Mac after launching | off | The app quits once **Play SWTOR** has opened the official app (the app's own preference) |

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
row doesn't type 1–0. It works with the patched Mac driver, which is used only while this
setting or *Raw mouse-look* is on (see [Credits and licenses](#credits-and-licenses));
changing it needs no Reinstall.

**Raw mouse-look** ports [SWGL on Mac](https://github.com/jdrly/swgl-on-mac)'s two mouse
patches to SWTOR. SWTOR has no raw input: while you hold a mouse button it hides the pointer,
reads the pointer's position from its window messages and puts it back to the window's centre
after every move (`SetCursorPos`). Wine's stock Mac driver moves the real pointer for each of
those and drops the moves queued around it, and the moves themselves reach the game once per
screen refresh, about a refresh late, and only when the game's thread next looks at its
messages. With the setting on:

- while the game hides the pointer, the macOS pointer stays where it is (no warps) and the
  game gets the mouse's moves as relative motion; its re-centring only moves Wine's own pointer,
  as on Windows;
- the moves come from GameController's `GCMouse` (around 1000 a second for a typical mouse)
  and an input thread of the driver sends them to the Wine server as they arrive;
- `GCMouse` reports the mouse's own counts, not the pointer's speed, so the driver measures the
  ratio of the two while you turn and sends the counts at that ratio: at *Mouse-Look Speed* 1×
  the camera turns as fast as with the pointer's moves (SWTOR on Mac 0.0.x),
  including your pointer speed in System Settings and Retina mode. Until the first measurement,
  a second or so into the first mouse-look, the pointer's own moves are sent (also through the
  input thread). A device `GCMouse` does not report (a trackpad) keeps the pointer's moves;
- SWG-specific parts stay off for SWTOR: `SetCursorPos` to a recent position is not ignored
  (SWTOR puts the pointer back where mouse-look began), and the prefix keeps Windows mouse
  acceleration settings untouched (SWTOR does not apply them itself);
- the pointer is hidden as before, with a blank cursor image, never by turning the cursor off
  (that would drop the game out of Direct presentation, the Metal HUD's *Direct*).

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
- **From 0.0.x to 0.1** the Wine engine changes from CrossOver 24.0.7 (Wine 9) to CrossOver
  26.3 (Wine 11): that first Reinstall downloads the new engine (~235 MB) and updates the
  existing prefix for it (`wineboot -u`, under a minute; your game settings, key bindings and
  SWTOR on Mac's settings stay). Until then the game keeps running on the old engine, and the
  Settings window asks for the Reinstall first. If anything in it fails, the old engine,
  prefix and settings are put back as they were; the old engine and its libraries are removed
  only once it has gone through. Going back is a Reinstall with the older app: 0.0.6 takes
  the updated prefix back (tested).
- **The engine download** (0.1.3 and later) is checked by its size, its start (an xz archive)
  and its sha256. A download that breaks off is resumed (up to four tries, and the next
  Update continues where it stopped); if the release URL doesn't bring the file, it is fetched
  once more through GitHub's API (the release asset's id, pinned next to the sha256: another
  address on GitHub's asset servers). A web page instead of the file (a captive portal, a
  proxy, a VPN or a content filter) or a changed file is named as such, with the size that
  arrived, and `install.log` records each try (curl's status, the HTTP code, the size, the
  checksum). If it keeps failing,
  download [the engine](https://github.com/athei/wine-build/releases/download/cx-26.3.0-8/wine-cx-26.3.0-8-macos-x86_64.tar.xz)
  in a browser, put the file into `~/Library/Caches/SWTOR on Mac/downloads/` and click Update
  again: a file there with the right checksum is used as it is.

### Development builds

Versions like `0.0.6-dev.1` are test builds of the next version. They are published only as
GitHub **pre-releases** (DMG only, no `appcast.xml`), so the feed above never offers them, and
they differ from releases in four ways:

- A **Development build** badge next to the title, and in About.
- **Debug Logging is on by default.** The first install or Reinstall of each dev version turns
  it on, so every test session logs the `STATS`/`HITCH`/`DIAG MEM` lines the session report
  reads. Turned off in Settings, it stays off until the next dev version.
- **No automatic update checks**, neither Sparkle's nor the wrapper's at game start; the
  setting is shown off. **Check for Updates…** still works. A dev build's `CFBundleVersion`
  (what Sparkle compares) sorts between the previous release and its own:
  `0.0.6-dev.N` is `0.0.5.(1000+N)`, `0.1.0-dev.N` is `0.0.9999.(1000+N)`, `0.1.1-dev.N` is
  `0.1.0.(1000+N)`, `0.1.2-dev.N` is `0.1.1.(1000+N)`. So the feed's previous release is never offered as an update, and the
  public X.Y.Z is offered once it is out. `CFBundleShortVersionString` stays `X.Y.Z-dev.N`.
- **d9mt A/B switches** (0.1.1-dev.1 and later):
  `"/Applications/SWTOR on Mac.app/Contents/Resources/d9mt-ab.sh"` (`scripts/d9mt-ab.sh`) sets
  d9mt's test switches for the next game starts, without editing `env`: `state-off` (no
  pipeline state cache), `pfv`, `barrier-all`, `clear-keep` (each undoes one of 0.1.1's GPU
  savings; `gpu-old` all three), `vsync-off`, `repro` (`DXVK_CONFIG`
  `d3d9.reproducibleCommandStream=True`), `cap=<fps>`, `cap-noalign` and `dxvkcap=<fps>` (d9mt's
  frame cap, its timer without vsync alignment, and DXVK's limiter as before 0.1.3, for
  comparison; Settings' Frame Rate Limit wins over `cap=` while it is on) and `cold=<name>` (an empty shader cache and pipeline
  archives of their own in `~/Library/Caches/SWTOR on Mac/d9mt-ab/<name>`, d9mt's own caches
  untouched). Each call sets exactly the switches it names; `d9mt-ab.sh` alone shows them,
  `reset` clears them (`--clean` also deletes the cold caches). They are kept in
  `d9mt-ab.env` next to `env`, which only a development build's `env` reads, so Settings keep
  them; `wine.log` names them in its second line and the session report shows them. A
  release's Reinstall over a development build removes `d9mt-ab.env` and the cold caches.

### Debug Logging, session reports and live d9mt flags

For a bug report about stutter or frame rate: turn on Settings > Troubleshooting > **Debug
Logging**, start the game, play the part that misbehaves, quit, then use **Collect Logs…** (it
includes the session report below). Turn Debug Logging off again afterwards: it costs a little
performance. A setting you choose is kept through updates and Reinstall.

**Session report.** `"/Applications/SWTOR on Mac.app/Contents/Resources/session-report.sh"`
(`scripts/session-report.sh`) sums up the last game session from
`~/Library/Logs/SWTOR on Mac/wine.log`:
- the app version, Wine engine and d9mt the session ran on (0.1.0-dev.1 and later: the
  wrapper's first line in `wine.log`; also in `effective-env.txt`, and Collect Logs'
  `system-info.txt` names the engine in place);
- duration, median and 1%-low fps, the seconds below 58 fps;
- frames over 33 ms and 50 ms;
- hitches, split into d9mt's and the game's, and d9mt's top causes;
- compile waits and the memory peak;
- render passes and the attachment traffic d9mt saved, and (0.0.6 and later) the
  render thread's CPU time in that optimization and the clears per frame, to tell its cost
  apart from compile waits (a cold shader cache);
- the attachment re-clears by cause, from the `RESTORE` lines (0.0.6 and later):
  image format and size, the aspects re-cleared, why and the D3D9 call, per frame;
- (0.1.1 and later) d9mt's GPU path (lossless texture compression, the end-of-pass barrier,
  clears that skip stores) and the A/B switches the session ran with; the pass splits per
  frame (`split=`, with a submit, `splitMiB=`) from the `STATS` lines; the pipeline state
  cache from the `STATECACHE` lines: what it loaded (and whether the last session ended
  during its prewarm, `guard`), what the prewarm built or failed, and how many pipelines the
  game then found prewarmed (`hits`), still building (`late`) or not in it (`misses`);
  StretchRect and ColorFill by path from the `XFER` lines.

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

### Launcher updates (the hook check when the app opens)

The official launcher sometimes updates its own Wine and puts Broadsword's preloaders back in
place of SWTOR on Mac's wrapper. SWTOR on Mac checks its hook each time the app opens, and
right before **Play SWTOR** if the hook is gone (`som.sh rehook`). If a launcher update replaced
the wrapper, it puts it back exactly like Install does and records the new preloaders in
`install-manifest.json`; its log is `~/Library/Logs/SWTOR on Mac/rehook.log`. It leaves
everything alone while an install, uninstall or settings change runs, when another Wine wrapper
is installed, and while the launcher is still changing its Wine (a preloader missing, or
`Wine/bin` changed in the last 20 seconds). The window then shows *Launcher hook: Removed by a
launcher update* and a **Repair the Launcher Hook** button.

Nothing of SWTOR on Mac runs while the app is closed: no launchd job, no login item. So if you
start SWTOR from the official app right after a launcher update has replaced its Wine, the game
runs without SWTOR on Mac until you open SWTOR on Mac once. Versions up to 0.1.3 set up a
launchd job for this, `~/Library/LaunchAgents/cz.jandrly.swtoronmac.watch.plist`, with a copy of
`som.sh` in `~/Library/Application Support/SWTOR on Mac/agent`. Installing 0.1.4 or later removes
both, and Uninstall does too.

## Reporting problems

1. Choose **SWTOR on Mac > Collect Logs…**. After 10–30 seconds (the menu item says
   *Collecting Logs…* meanwhile) it saves `SWTOR-on-Mac-logs-<date>.zip` to your Desktop (or,
   without access to the Desktop, to `~/Library/Logs/SWTOR on Mac`) and shows it in Finder.
2. Send that zip with a short description of what happened and when to **Pharaphobia on
   Discord** or attach it to a [GitHub issue](https://github.com/jdrly/swtor-on-mac/issues/new/choose).
   Please don't send it to Broadsword or SWTOR customer support: they don't support SWTOR on
   Mac.

The zip holds SWTOR on Mac's logs, `env`, `settings.conf`, `dxvk.conf`,
`install-manifest.json`, the versions, system information (macOS, chip, memory, displays, the size of macOS's Metal caches for the engine's processes, shared with other CrossOver-based apps, and the size of Metal's archive usage index, called full only when its MDB_MAP_FULL lines are in the log) and
macOS's crash, hang and spin reports of the last 7 days (from `~/Library/Logs/DiagnosticReports`)
for the game, Wine, the official launcher and SWTOR on Mac, so you don't have to look for them:
the newest 20, up to 10 MB together; `system-info.txt` lists which are in the zip and which were
left out. `gpu-errors.txt` has the GPU errors of the game and Wine from macOS's unified log
of the last 2 hours (`IOGPUMetalError` counted per process, the last fault lines, the GPU
driver's events by time and kind, Metal's other errors), since `wine.log` starts anew with every
game start; other apps' errors are only counted, never named. Your home folder, user name, account
names and e-mail addresses are replaced, serial numbers and device identifiers are left out,
and the game's command line (the launcher passes the account on it) is never included. Turn on
**Settings > Debug Logging** only when asked: it makes the logs much more detailed for the next
game start, at some cost in performance, so turn it off again afterwards.

## Known issues

- **The Wine engine changed in 0.1** (CrossOver 26.3 with Wine 11, before CrossOver 24.0.7
  with Wine 9). If the game doesn't start or behaves worse than on 0.0.6, please report it
  (Debug Logging on, then **Collect Logs…**), and go back to 0.0.6 if you need to: download it
  from [Releases](https://github.com/jdrly/swtor-on-mac/releases/tag/v0.0.6), copy it over the
  app and click Reinstall.
- **Raw mouse-look** is on by default. If mouse-look feels wrong (speed, jumps, the pointer
  not coming back where you clicked), turn it off in Settings > Mouse to compare, and report it
  with Debug Logging on. Its speed matches your pointer speed from about a second into the
  first mouse-look; *Mouse-Look Speed* scales it.
- **Stutter the first time** you see an area or effect, while d9mt compiles and caches its
  shaders (see [Install](#install)). It gets smooth after that.
- **The Cartel Market sometimes ignores a reopen**: if you open it again right after closing
  it, the game sometimes ignores that press. The game does this on Windows too; press again.
- **Retina Mode** can only be changed while the launcher and the game are closed (it is in the
  Wine prefix's registry).
- **The Metal HUD** is turned on in Settings before starting the game; in the game Shift+F9
  only hides and shows it. Shift+F12, or three quick clicks inside the HUD's area (also while
  it is hidden), open macOS's own HUD settings panel: Apple's HUD has no option to turn that
  off, so SWTOR on Mac puts the HUD at the top center by default (Settings > Game > *Metal HUD
  Position*), away from buttons that get clicked quickly. Turn the HUD off in Settings to be
  rid of it entirely.
- **Non-US keyboard layouts**: without *Game keys by keyboard position* the game names keys by
  what your layout types (Czech: *+ ě š* … on the number row). With it, keys are named by
  their US positions, so on QWERTZ layouts Z and Y swap names in the game. It can only be
  changed while the launcher and the game are closed.
- **The launcher in the Dock while you play.** About 30 seconds after you press Play the
  official launcher quits (and plays the system alert sound once as it does), and macOS keeps
  showing it in the Dock as *running in the background* until the processes it started have
  ended: the game, Broadsword's `mac_wine` helper and the game's Wine. That is how the
  official setup behaves too; the icon goes by itself shortly after you quit the game. Don't
  **Quit** it from the Dock while the game runs: macOS then ends those processes, and the game
  with its Wine.
- **Official launcher updates** replace SWTOR on Mac's hook. Open SWTOR on Mac (or press Play
  SWTOR in it) and it hooks itself back in. If the update looks unfinished, it waits for you: open
  it again a little later, or click **Repair the Launcher Hook**.
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
  (Install, Uninstall and the settings kept in the prefix's registry, Retina, game keys by
  keyboard position, raw mouse-look and its speed, also end them first).
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
and, from versions up to 0.1.3, the launchd job are deleted (characters live on the server and
are not affected). Logs stay in `~/Library/Logs/SWTOR on Mac`. Then move the app to the Bin.

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
  - `engine/` – the Wine engine (self-contained: its libraries are inside it), with d9mt's
    winemetal bridge, SWTOR on Mac's build of its `ntdll.so` (`lib/wine/x86_64-unix`: the msync
    fix, see [Building](#building); the engine's own kept as `ntdll.so.stock`) (and, while *Game keys by keyboard position* or *Raw mouse-look* is on,
    SWTOR on Mac's build of its Mac driver, `winemac.so` and the PE sides
    `x86_64-windows/winemac.drv`, `i386-windows/winemac.drv`; the engine's own files are kept
    as `<name>.stock`)
  - `frameworks/` – only in installs of 0.0.x: the old engine's libraries (removed by the
    Reinstall that upgrades it); `upgrade-backup/` – only while that Reinstall runs
  - `prefix/` – the game's Wine prefix: an APFS clone of Broadsword's, updated for the engine,
    with d9mt's `d3d9.dll` in `system32` (Wine's own kept as `d3d9.dll.wine`) and the settings
    below; your existing game settings are taken over once
  - `gamemode/SWTOR.app` – the bundle that gets the game macOS Game Mode (a clone of the
    engine's loader and a link to its `ntdll.so`)
  - `settings.conf` – the Settings window's settings; `env` – what the wrapper applies,
    `dxvk.conf` – d9mt's options (both made from `settings.conf`)
  - `install-manifest.json` – what was changed, for Uninstall
  - `last-update-check`, `update-available` – the wrapper's daily update check
  - `backup/` – only if you replaced another Wine wrapper: a copy of it
- `~/Library/Caches/SWTOR on Mac/downloads` – the engine downloads, only during an install
- `winetemp-…/wine` (or `winetemp-…/swtor.exe`) in your per-user temporary folder
  (`$TMPDIR`) – the Game Mode link, made at each game start
- `d9mt/` in your per-user cache folder (`$(getconf DARWIN_USER_CACHE_DIR)`) – d9mt's own
  caches, made by the game: compiled shaders (`air-cache.sqlite3`), pipeline archives (`pso/`)
  and the pipeline state cache (`state/`, `D9MT_STATE_CACHE`). They are shared by every d9mt
  setup of your user (SWGL on Mac's too), so Uninstall leaves them; macOS clears that folder
  when it needs the space, and deleting it only costs the stutter of a first start
- `~/Library/Caches/SWTOR on Mac/d9mt-ab/` – only in development builds, the caches of
  `d9mt-ab.sh cold=<name>` runs (a release's Reinstall removes them and `d9mt-ab.env`)
- `~/Library/Logs/SWTOR on Mac/` – `install.log`, `rehook.log` (the hook check when the app
  opens), and per game start `wine.log`
  (d9mt warnings), `hold.log` (also a line per Wine start that is not the game: its time,
  the command's first word and who started it), `launch-env.txt`, `effective-env.txt`

### Removing it by hand

If the app is gone or Uninstall can't run, quit the launcher and the game and run this in
Terminal. It puts Broadsword's preloaders back from `bin-real`, then removes the launchd job of a
version up to 0.1.3, if there is one, and SWTOR on Mac's folders:

```sh
W="$HOME/Library/Application Support/com.broadsword.swtor/Star Wars - The Old Republic/swtor-precompiled/Libraries/Wine"
for p in wine-preloader wine64-preloader; do
  # only where bin/ still holds the wrapper script (a launcher update may have put a newer preloader there)
  if [ "$(head -c 2 "$W/bin/$p")" = '#!' ]; then mv -f "$W/bin-real/$p" "$W/bin/$p"; fi
done
rm -rf "$W/bin-real"
launchctl bootout "gui/$(id -u)/cz.jandrly.swtoronmac.watch" 2>/dev/null   # (0.1.3 and older)
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
brings up the prefix's Wine session through `hold-launcher --start-session` (a no-op if it
runs), one start at a time:

- it ends the prefix's leftover Wine processes, if any: Wine processes of the engine that
  belong to this prefix's session (they map files from its server directory
  `/tmp/.wine-<uid>/server-<dev>-<inode>`, or work in its `drive_c`) while no wineserver of
  it runs; other prefixes' are never touched;
- it starts the engine's wineserver with `-p10`: it ends by itself 10 s after the last Wine
  process (`-p 10`, with a space, would keep it forever: Wine's option takes its value only
  attached), in its own session, with nothing of the caller open (the launcher's and
  `mac_wine`'s pipes and sockets);
- if that server is new, a bootstrap Wine call (`reg query`, output to `/dev/null`) brings up
  Wine's system processes (`services.exe`, `winedevice.exe`, ...). They inherit the stdout and
  stderr of the session's first Wine process: were that a call of Broadsword's `mac_wine`,
  which reads its calls' output to the end, `mac_wine` would wait for the whole session.

Nothing holds the launcher: it quits ~30 s after starting the game, as with Broadsword's own
Wine, and macOS leaves the game (a foreground app) and the Wine session running. For the game
(`swtor.exe`) the wrapper also:

- sends the game's output to `wine.log` instead of the launcher's pipe, which closes when the
  launcher quits;
- links the name CrossOver's ntdll starts the game from to `gamemode/SWTOR.app`, a bundle
  with `LSSupportsGameMode` around an identical clone of the engine's loader
  (`lib/wine/x86_64-unix/wine`; the engine has no `wine-preloader`) and a link to its
  `ntdll.so`, so macOS turns Game Mode on. As SWGL on Mac does it for this engine: ntdll uses
  those links only while `WINEDLLPATH` is set, which the wrapper does for the game only, and
  the name is `winetemp-…/wine` when the game is the first process of the command, or
  `winetemp-…/swtor.exe` when the command is `start.exe /exec …` (the wrapper picks by the
  command and logs it in `gamemode.log`);
- sets `WINE_COMPATDB` for the engine's compatdb (its per-process choice of Direct3D
  backends): DXGI stays on wined3d, so neither Apple's D3DMetal nor the DXMT tree with its own
  winemetal is used next to d9mt's bridge;
- with Debug Logging on, sets `WINEDEBUG` to `SWTOR_GAME_WINEDEBUG` (the Mac driver's
  `THREADCPU` and `RAWMOUSE` lines, game only).

Leftover Wine processes are processes of SWTOR on Mac's engine (its loader, or CrossOver's
`winetemp-<inode>-…` hard links of it, found by their real executable: Wine 11 shows
`C:\…\name.exe` in `ps`) while no wineserver of the engine runs: what is left of
a session whose server is gone, such as a `winedevice.exe` that would wait forever. They don't
block anything: the window says so and offers **End Leftover Wine Processes**, and Install,
Uninstall and the settings in the prefix's registry end them first (logged in `install.log`). The launcher, the
game, Broadsword's Wine or a running Wine session of the engine (its wineserver) do block
those; the window says which, and the buttons say why when clicked. The window looks again
when it becomes active and when the launcher or the game quits.

Fixed settings (`env` and the prefix's registry): `WINEMSYNC=1`, `WINEDEBUG=-all`,
`WINEDLLOVERRIDES=d3d9=n,b` (also per app for `swtor.exe`), `D9MT_STATE_CACHE` (d9mt's
pipeline state cache next to its other caches, see [What it changes](#what-it-changes)), `d3d9.allowOutOfRangeVsDefs = True`
in d9mt's `dxvk.conf`, and `GrabPointer=n` for `swtor.exe` (no hitch when mouse-look starts).
Vsync is on by default because SWTOR asks for none in borderless mode, which tears. The rest is
in the Settings window (above).

The installer is `src/som.sh` (`status`, `install`, `uninstall`, `settings`, `set`, `rehook`,
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
a sandbox. In a sandbox notifications go to `notifications.log`, and Play SWTOR opens only the sandbox's official app
(`SWTORonMac --play-target` prints what the button would do, without opening anything, and `--play-check` what a press does after the hook check). `scripts/test-sandbox.sh` builds a sandbox from an APFS clone of this Mac's
Broadsword Wine folder and a stand-in for the official app (its `Info.plist`, ad-hoc signed,
with the test's stand-ins for the launcher built in, so Gatekeeper never sees a changed copy
of Broadsword's signed app) and runs install, the settings, reinstall, the wrapper's update check (with a
stub engine and a local feed), a simulated launcher update and the app's hook check when it opens (`som.sh rehook`: it hooks
back in, leaves a running install and a launcher still writing alone; an update over 0.0.6,
0.1.3 and a development build removes their launchd job), leftover Wine processes (dummy programs under the sandbox engine and in
Broadsword's Wine folder: what `status` reports, that only they end, from `end-leftovers`,
install, uninstall and the wrapper, never while a wineserver of theirs runs, never another
prefix's, never Broadsword's `mac_wine`), the Wine session (a `mac_wine`-like call that starts
it returns at once although its system process lives on, `-p10`, nothing of the caller
inherited, one start for two calls at once), a failed
install, Collect Logs, what Play SWTOR would open, *Game keys by keyboard position* and *Raw
mouse-look* (the Mac driver's three files and the registry values, and what the game sees: a
probe program run as `swtor.exe` with Czech, German and US layouts, picked through the
driver's `WINEMAC_TEST_KEYBOARD_LAYOUT` test hook without changing the Mac's input source; the
app's PE side with the engine's own unix side, as an older installer leaves them), the
conflict cases and uninstall end to end, checking that uninstall
restores Broadsword's folder byte for byte, copies the game settings back and that no Wine
process is left behind. With an older app (`OLD_APP`, default `release/0.0.6`) it then tests the
way from 0.0.6 and back: a 0.0.6 install upgraded (a failed upgrade rolled back first: engine,
libraries, env and prefix as before, and Wine 9 still reads the prefix), everything kept and
the new engine in use; 0.0.6's Reinstall over it (Wine 9 runs programs in the prefix Wine 11
updated, game keys by position work); the upgrade again; and this version's Uninstall of a
0.0.6 install. With the previous release (`PREV_APP`, default `release/0.1.0`, the same
engine) it tests the way from it and back: this version's Reinstall over it changes only d9mt's
`d3d9.dll` in the prefix and adds the env lines (the engine's code stays the same, its
`winemetal.so` that of the previous release), and the previous release's Reinstall puts
prefix, engine and `env` back as it had them. A release build then goes on from a development
build (`DEV_APP`, default `release/0.1.1-dev.1`): its Reinstall removes the dev build's
`d9mt-ab.env` and test caches and keeps the prefix, engine and settings. It also checks
development builds' `d9mt-ab.sh`, the session report on a sample of d9mt's log lines, the
app's `ntdll.so` in the engine (the engine's own kept as `.stock`, also after an upgrade and
a downgrade), and a wrapper copied by hand from the template (`@CONF@` not filled in, or
another install's `env`), which the window and Play treat as unhooked and Reinstall and the
app's hook check repair. `scripts/test-update.sh` tests app updates with two Developer ID builds and a
local feed, as in SWGL on Mac.

## Building

- `scripts/build-d9mt.sh` builds d9mt (x86_64) at a pinned commit of
  [jdrly/d9mt](https://github.com/jdrly/d9mt) in a scratch clone into `prebuilt/d9mt`
  (Homebrew bash, mingw-w64, cmake, ninja, Xcode; an LLVM 15 build for macOS 26 via
  `D9MT_LLVM`): d9mt's `scripts/fetch-deps.sh` (dxbc-spirv at its pin with d9mt's patches),
  then a build from scratch every time. It is reproducible: `SOURCE_DATE_EPOCH` is the commit's
  time, and the same `D9MT_WORK` path gives the same `d3d9.dll`. (0.1.1's `winemetal.dll` is
  0.1.0's: the bridge's source is the same, and `SOURCE_DATE_EPOCH=1792149856` builds it byte
  for byte. 0.1.2's `d3d9.dll` is d9mt main `2a1bc00` built with `SOURCE_DATE_EPOCH=1792457826`,
  the time of `c3f46ce`, which has the same tree: byte for byte the file 0.1.2-dev.2 and dev.3
  were tested with. 0.1.4 pins main `b0d4597`, built with its own commit time.)
- `build.sh` assembles `dist/SWTOR on Mac.app` with Sparkle (pinned download; ad-hoc signed;
  `--install` copies it to /Applications). Needs Xcode 27 (macOS 27 SDK); the app runs on
  macOS 26 and later.
- `scripts/release.sh` signs a copy with the Developer ID (hardened runtime; the helpers get
  `allow-dyld-environment-variables`, the app and Sparkle no exceptions), builds the DMG,
  notarizes and staples it, and builds the Sparkle feed (`appcast.xml` with delta updates from
  the last 5 versions in `release/updates/`, checked by `scripts/check-appcast.swift`), then
  drafts the GitHub release (`--sign-only`, `--no-notarize`, `--no-release` for local runs;
  `--ci`, `--feed <version>` for the two halves of a CI release, as in SWGL on Mac).
- `scripts/ui-snapshot.sh` builds the app's windows into a small test bundle and runs it on a
  temporary virtual display (swtor-mac-proper's `tools/vd/with-vd.sh`), never on the main one:
  screenshots of the main window in its states and of Settings (`shots`), and what the warp
  costs (`measure`, `sweep`, `findcost`, `idlecheck`, `stillcheck`: CPU, instructions, the
  GPU time the GPU driver counts for the process, frames drawn).
- `.github/workflows/checks.yml` lints the scripts and builds the app;
  `.github/workflows/release.yml` signs and notarizes on a `v*` tag. Both build on GitHub's
  `xcode-27` image (macOS 27 with Xcode 27, a public preview; there is no `macos-27` label).

- `scripts/build-winemac.sh` builds Wine's Mac driver (`winemac.so`, x86_64, and its PE sides
  `x86_64-windows/` and `i386-windows/winemac.drv`) from the sources the engine is built from
  (athei/wine at the commit athei/wine-build's release names, pinned sha256; configured like
  athei's build; the engine download pinned in `src/som.sh` for linking) with
  `patches/winemac-physical-keys.patch`, SWGL on Mac's `winemac-swgl-relative-mouse.patch` and
  `winemac-swgl-input-thread.patch` (unchanged copies) and `winemac-swtor-mouse.patch`, in that
  order, into `prebuilt/winemac`, together with an unpatched build: `scripts/winemac-compare.py`
  checks that one against the engine's own `winemac.so` and that the patches change only the
  keyboard and mouse functions and the options; the PE sides are checked by their imports and
  sections. It also refuses if a patch hides the cursor by turning it off (`[NSCursor hide]`),
  which would cost Direct presentation (Xcode, Rosetta, Homebrew bison; llvm-mingw pinned as in
  athei's build). The build is reproducible (the PE sides without their debug info).

- `scripts/build-ntdll.sh` builds Wine's `ntdll.so` (the x86_64 unix side) from the same sources
  with `patches/ntdll-msync-alert-fd.patch` into `prebuilt/ntdll`. CodeWeavers' msync port
  keeps a thread's msync alert index in the field Wine 11 keeps its alert file descriptor in,
  and a thread's exit closes it: every thread that did an alertable wait closes an unrelated
  file descriptor when it exits (a file, another thread's wineserver pipe, a kqueue); with
  msync the patch leaves it alone, as athei/wine `12927acab0` does on another branch. It is
  configured as athei's `build-wine.sh` configures the engine (`--with-unwind`, unoptimized)
  against the engine's macOS 26.5 SDK (the Command Line Tools'), together with an unpatched
  build: `scripts/ntdll-compare.py` checks that one against the engine's own `ntdll.so`
  (exports, imports, libraries and the code of every function the same; the files differ in
  the linker's layout only) and that the patch changes only `pthread_exit_wrapper`. The
  sources come from `.cache/`, a local copy (`WINE_SRC_CACHE`; the commit is on no branch of
  athei/wine any more) or codeload. The build is reproducible.

`prebuilt/` holds the d9mt binaries, the Mac driver and `ntdll.so`, so `build.sh` works from a fresh clone. Build outputs
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
| Wine engine `cx-26.3.0-8` (CrossOver 26.3, Wine 11.0, x86_64 WoW64; the one SWGL on Mac uses) | [athei/wine-build cx-26.3.0-8](https://github.com/athei/wine-build/releases/download/cx-26.3.0-8/wine-cx-26.3.0-8-macos-x86_64.tar.xz) | `1976c3310a1f8be2f8e9a46fcb524f77b4316df3d281d94af2c8542bef60456d` |
| Sparkle 2.10.0 (bundled) | [sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0) | `c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c` |
| d9mt `b0d4597` (bundled, `prebuilt/d9mt`; main after jdrly/d9mt#47: the frame cap `D9MT_FPS_CAP` (#47), and before it the present path's drawable kept until the GPU is done with it (#26), the GPU canary (#27), the PSO key changes (#32–#34, #40; the state cache's mapping version 4), the state cache journal (#35), fixed-function and argument-table fixes (#37, #38)) | [jdrly/d9mt](https://github.com/jdrly/d9mt/tree/b0d4597b4ac98166e5e96b0a4175591110f12e8b) | see `prebuilt/d9mt` |
| The engine's Wine sources (for the Mac driver, `prebuilt/winemac`, and `ntdll.so`, `prebuilt/ntdll`): athei/wine `d23b397` | [athei/wine](https://github.com/athei/wine/tree/d23b39774528237cafe49f9a073286f854b779c0) (codeload tar.gz) | `7002111d61bbf28e88cc2504080747d27d074907a7e278f6c78cf6cefe09746e` |
| llvm-mingw 20261006 (only for configuring that build) | [mstorsjo/llvm-mingw](https://github.com/mstorsjo/llvm-mingw/releases/tag/20261006) | `a7a19b11048e89372637d26279cdb7c430ed3cf8c1e224310421312bf986ebf6` |

## Credits and licenses

- Star Wars: The Old Republic, its launcher and game files belong to their owners (Broadsword
  Games, Electronic Arts, Lucasfilm, Disney). SWTOR on Mac ships none of them.
- [d9mt](https://github.com/jdrly/d9mt) by Jan Drlý, a fork of neo773's
  [d9mt-v2](https://github.com/neo773/d9mt-v2), with DXVK and DXMT code: zlib, its winemetal
  bridge LGPL-2.1-or-later (source: `bridge/` of the pinned commit). Licenses and third-party
  notices ship in the app under `Resources/Licenses/d9mt`.
- [Wine](https://www.winehq.org) (LGPL-2.1-or-later) from CodeWeavers'
  [CrossOver 26.3 sources](https://www.codeweavers.com/crossover/source) with athei's patches
  ([athei/wine](https://github.com/athei/wine)), built and bundled by
  [athei/wine-build](https://github.com/athei/wine-build) (the components it bundles are listed
  in its releases); the engine is downloaded from that release at install time, not
  redistributed.
- Wine's Mac driver (`winemac.so` and its PE sides, LGPL-2.1-or-later), built from the
  engine's Wine sources (athei/wine, CrossOver 26.3) with SWTOR on Mac's patch for *Game keys
  by keyboard position*
  ([`patches/winemac-physical-keys.patch`](patches/winemac-physical-keys.patch), by Jan Drlý),
  SWGL on Mac's two mouse-look patches
  ([`winemac-swgl-relative-mouse.patch`](patches/winemac-swgl-relative-mouse.patch),
  [`winemac-swgl-input-thread.patch`](patches/winemac-swgl-input-thread.patch), by Jan Drlý)
  and SWTOR on Mac's changes to them for *Raw mouse-look*
  ([`patches/winemac-swtor-mouse.patch`](patches/winemac-swtor-mouse.patch)): bundled in the
  app, with Wine's license and the patches under `Resources/Licenses/winemac`.
- Wine's `ntdll.so` (LGPL-2.1-or-later), built from the same sources with SWTOR on Mac's msync
  fix ([`patches/ntdll-msync-alert-fd.patch`](patches/ntdll-msync-alert-fd.patch), by Jan
  Drlý; the same guard as athei's `12927acab0`): bundled in the app, with Wine's license and
  the patch under `Resources/Licenses/ntdll`.
- [Sparkle](https://sparkle-project.org) for app updates (MIT, with bsdiff and other notices;
  in the app under `Resources/Licenses/sparkle`).
- The typefaces of [swonmac.com](https://swonmac.com),
  [Unbounded](https://github.com/googlefonts/unbounded) and
  [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) (SIL Open Font License 1.1),
  unmodified in `src/fonts`; in the app under `Resources/Fonts`, their licenses under
  `Resources/Licenses/fonts`.
- Built after the example of [SWGL on Mac](https://github.com/jdrly/swgl-on-mac).

What the app bundles and what it downloads at install time, with their licenses:
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) (also in the app under `Resources/Licenses`).

## License

The code in this repository is under the [zlib license](LICENSE), except the patches in
`patches/` (`winemac-*.patch`, `ntdll-*.patch`), changes to Wine and so under Wine's LGPL-2.1-or-later. The files in `prebuilt/` and everything the build or the installer downloads
keep their own licenses (see above; d9mt's are in `prebuilt/d9mt`, the Mac driver's in
`prebuilt/winemac`, `ntdll.so`'s in `prebuilt/ntdll`).
