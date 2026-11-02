# The window and settings

The main window, the Play SWTOR button and the Settings window in detail. The [README](../README.md) covers install and everyday use.

## The window

- **SWTOR on Mac menu:** *About SWTOR on Mac*, *Check for Updates…*, *Settings…* (⌘,) and
  *Collect Logs…* (see [Getting help](../README.md#getting-help)).
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
  is built but off: [warp-video-loop.md](warp-video-loop.md)).
- **When the game never showed up:** if macOS ended the game's Wine in the last 24 hours because
  the launcher is not allowed in the background, the window says so when it opens, with the
  setting to change and **Open Login Items**; **Dismiss** hides it until it happens
  again (see [Troubleshooting](../README.md#troubleshooting)).
- SWTOR on Mac does not need to be open to play: the official app starts the game on SWTOR on
  Mac's engine by itself.

## Settings

SWTOR on Mac > **Settings…** (⌘,), while SWTOR on Mac is installed. A sidebar of panes
(Graphics, Game, Keyboard, Mouse, Play Button, Updates, Troubleshooting; the window opens on
the one used last) and the selected pane's settings. Changes take effect the next time the game starts.

| Pane | Setting | Default | What it changes |
|---|---|---|---|
| Graphics | Retina Mode | on | Wine's Mac driver `RetinaMode` in the prefix's registry (only while the launcher and the game are closed) |
| Graphics | Vsync | on | `d3d9.presentInterval = 1` in `dxvk.conf` (off: unset) |
| Graphics | Frame Rate Limit | Off | `SWTOR_FPS_LIMIT` in `env` (0, 30, 40, 45, 60): the wrapper gives the game d9mt's `D9MT_FPS_CAP`. Even frame times, for less heat and a longer battery life: with vsync, a cap that divides the refresh rate keeps every frame on screen for the same number of refreshes (30 at 60 Hz: two; 40 at 120 Hz: three); 40 and 45 at 60 Hz keep the load even but show frames for one or two refreshes; at or above the refresh rate with vsync on it does nothing. `wine.log` names it (`frame rate limit:`, then d9mt's `frame cap` line) |
| Graphics | Only on battery | off | `SWTOR_FPS_LIMIT_BATTERY=1` in `env`: the limit only if the Mac draws from its battery when the game starts (the wrapper asks `pmset -g ps` once; nothing watches it while the game runs) |
| Graphics | Fewer GPU Batches (Experimental) | off | `SWTOR_FLUSH_CAP=1` in `env`: the wrapper gives the game d9mt's flush cap, `D9MT_FLUSH_CAP=1` (d9mt #113): weak flush hints no longer submit a command buffer mid-frame, so a frame goes to the GPU in fewer command buffers and render passes split by a submit load their attachments again less often. Recommended for lower-end MacBooks and MacBook Airs (Jan, 2026-10-31): Macs with less memory bandwidth (base M1–M3, Airs); it can cost frame rate where the GPU is the limit, since the GPU starts later. Other Wine starts don't get it. `wine.log` names it (`flush cap: on`; d9mt's own `flush cap` line is an info line, there only with Debug Logging). A development build's `d9mt-ab.sh flush-cap` / `flush-cap-off` win over it |
| Graphics | Video Memory Profile | Automatic | `D9MT_MEMORY_PROFILE` (auto, low, medium, high, ultra, unlimited). The video memory the game is told it has: Low 2 GB, Medium 3 GB, High and above 4 GB. Automatic picks by the Mac's memory: 8 GB Low, 16 GB Medium, 24 GB High, more Ultra |
| Game | Game Mode | on | `SWTOR_GAMEMODE_APP` in `env` |
| Game | Show Metal HUD | off | `MTL_HUD_ENABLED=1` in `env`, from the next game start. In the game Shift+F9 hides and shows it; Shift+F12, or a triple-click inside the HUD's area (also while it is hidden), opens macOS's own HUD settings panel (Apple's `libMTLHud`, which has no option to turn that off) |
| Game | Metal HUD Position | Top Center | `MTL_HUD_ALIGNMENT` (top left, top center, top right, center left, centered, center right, bottom left, bottom center, bottom right) while the HUD is on. Top Center keeps the HUD's area away from buttons that get clicked quickly, such as Randomize in character creation (top right, Apple's default) |
| Keyboard | Game keys by keyboard position | off | The game sees every key by its position on a US keyboard (see below): SWTOR on Mac's build of Wine's Mac driver in its engine and `PhysicalKeyboard=y` for `swtor.exe` in the prefix's registry; off, the engine's own driver (only while the launcher and the game are closed) |
| Mouse | Raw mouse-look | on | While the game hides the pointer to turn the camera, the mouse's own moves from GameController's `GCMouse`, sent by an input thread of the Mac driver as they come, the macOS pointer frozen (see below): SWTOR on Mac's build of Wine's Mac driver in its engine and `RawMouseWhenCursorHidden=y` for `swtor.exe`; off, `n` (and the engine's own driver if *Game keys by keyboard position* is off too). Only while the launcher and the game are closed |
| Mouse | Mouse-Look Speed | 1× | `RawMouseGameControllerScale` for `swtor.exe` (0.5× to 3×): a factor on the macOS pointer's speed, which raw mouse-look matches at 1× |
| Updates | Check for updates automatically | on | Sparkle's automatic checks and the daily check at the game's start |
| Troubleshooting | Debug Logging | off | `DXVK_LOG_LEVEL=info`, `D9MT_PROFILE=1` (with d9mt's `STATS` and `PACE` lines every second: frame times, and how evenly the game calls Present and how its thread's time per frame splits into d9mt's D3D9 calls and the game's own work), `D9MT_MEMSTATS=1`, `D9MT_DEBUG_FILE=C:\d9mt\flags.txt` (d9mt's live debug flags, see [Logs and debugging](logs-and-debugging.md#debug-logging-session-reports-and-live-d9mt-flags); else `DXVK_LOG_LEVEL=warn`), and `SWTOR_GAME_WINEDEBUG=-all,warn+rawmouse,warn+threadcpu`: the wrapper sets it as the game's `WINEDEBUG`, so the app's Mac driver logs `THREADCPU` (from `swtor.exe` only, `ThreadCpuStats=y` in the prefix) (the CPU time of the game's busiest threads and of the wineserver, once a second) and `RAWMOUSE` (raw mouse-look, once a second while it moves) |
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
setting or *Raw mouse-look* is on (see [Credits and licenses](../README.md#credits-and-licenses));
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
