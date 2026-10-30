# How it works

What SWTOR on Mac changes on disk, how its wrapper runs the game, and how it handles launcher updates. The [README](../README.md#how-it-hooks-into-the-official-app) has the short version.

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
  - `engine/` – the Wine engine (self-contained: its libraries are inside it), with d9mt's
    winemetal bridge, SWTOR on Mac's build of its `ntdll.so` (`lib/wine/x86_64-unix`: the msync
    fix, see [Building](building.md); the engine's own kept as `ntdll.so.stock`) (and, while *Game keys by keyboard position* or *Raw mouse-look* is on,
    SWTOR on Mac's build of its Mac driver, `winemac.so` and the PE sides
    `x86_64-windows/winemac.drv`, `i386-windows/winemac.drv`; the engine's own files are kept
    as `<name>.stock`)
  - `frameworks/` – only in installs of 0.0.x: the old engine's libraries (removed by the
    Reinstall that upgrades it); `upgrade-backup/` – only while that Reinstall runs
  - `prefix/` – the game's Wine prefix: an APFS clone of Broadsword's, updated for the engine,
    with d9mt's `d3d9.dll` in `system32` (Wine's own kept as `d3d9.dll.wine`) and the settings
    in [Settings](settings.md); your existing game settings are taken over once
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
  (d9mt warnings; the 4 starts before it as `wine.log.1` to `wine.log.4`), `hold.log`
  (also a line per Wine start that is not the game: its time, the command's first word and who
  started it; and a line when the game ends: how long it ran, its exit code or signal, its
  language), `launch-env.txt`, `effective-env.txt`

## The wrapper and the Wine session

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

If it ended leftover Wine processes (`hold-launcher` exits 3), the last session ended without
its server: macOS ends what the launcher left running when it quits while it is not allowed in
the background (System Settings > Login Items > *App Background Activity*). The wrapper then runs the app's `som.sh btm-check 1h` (the path is `SWTOR_SOM_SH`
in `env`) in a detached process, so the Wine call doesn't wait for it: one look at the last hour
of macOS's unified log (`/usr/bin/log show`, loginwindow's *not allowed by BTM so terminating
its subordinates* line for the launcher, about a second, no root). If it finds one, it posts a
notification with the setting to change and logs it in `hold.log`; then it ends. The app runs
the same check over the last 24 hours when it opens, and Collect Logs over the last 7 days. The
check ends its query after a time limit in every case (20 s from the wrapper, 60 s from the app,
90 s in Collect Logs), so nothing of it keeps running.

Nothing holds the launcher: it quits ~30 s after starting the game, as with Broadsword's own
Wine, and macOS leaves the game (a foreground app) and the Wine session running. For the game
(`swtor.exe`) the wrapper also:

- runs it as the child of `hold-launcher --run-game`, which takes the wrapper's place: it passes
  `TERM`, `INT`, `HUP` and `QUIT` on to the game, and when the game ends it writes one line to
  `hold.log` (how long it ran, its exit code or signal, and its language: the `-set lang` and
  `-set torsets` values of its command line, nothing else of it), then ends the way the game
  did. It ends with the game: nothing of SWTOR on Mac stays after it ([ADR 0005](adr/0005-no-background-helper.md));
- records the game's language and the locale it gets (`LANG`, `LC_*`) in `effective-env.txt`
  and `wine.log`;
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
in the Settings window ([Settings](settings.md)).

The installer is `src/som.sh` (`status`, `install`, `uninstall`, `settings`, `set`, `rehook`,
`end-leftovers`, `btm-check`); the window (`src/native`, SwiftUI) runs it and shows its progress as a
timeline. Install is idempotent and all-or-nothing: it refuses while the launcher or game runs,
checks every download against a pinned sha256, prepares everything in SWTOR on Mac's folders
first, touches Broadsword's folder last, and rolls back if anything fails. If Broadsword's Wine
folder holds a Wine wrapper that is not SWTOR on Mac's (for example the developer's own setup),
it says so and leaves it alone unless you confirm; it then keeps a copy in `backup/`.

## Launcher updates (the hook check when the app opens)

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

## Removing it by hand

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
