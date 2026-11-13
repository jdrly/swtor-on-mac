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

## DirectX 12 (experimental, development builds)

Development builds have two more settings at the end of the Graphics pane, to try Broadsword's
DirectX 12 client (`swtor_RC2.exe`, which the patcher puts next to `swtor.exe`). A release build
neither shows nor applies them: `som.sh set dx12` refuses there, and a `dx12=on` left in
`settings.conf` by a development build does nothing.

| Setting | Default | What it changes |
|---|---|---|
| DirectX 12 (experimental) | off | `SWTOR_DX12=1` in `env`: when the launcher starts `…\retailclient\swtor.exe`, the wrapper starts `swtor_RC2.exe` from the same folder with the same arguments. If that file isn't there, it starts `swtor.exe` as always and says so in `wine.log` and `hold.log`. Only while the launcher and the game are closed (it changes the prefix's registry) |
| DirectX 12 Driver | Mullion | `SWTOR_DX12_DRIVER` in `env`: `mullion`, Mullion as my fork [jdrly/mullion](https://github.com/jdrly/mullion) builds it (Metal 4 where the GPU has it), `mullion-mtl3`, Mullion on Metal 3 (the wrapper sets `MULLION_D3D12_METAL4=0` for the game), `gptk`, Apple's D3DMetal from the engine (Metal 4 where macOS has it), or `gptk-mtl3`, D3DMetal on Metal 3 (`D3DM_MTL4=0`). Only while the launcher and the game are closed (a switch to or from Mullion changes the engine's files) |

With the setting on:

- `env`'s `WINE_COMPATDB` gets a second rule, `name=swtor-dx12;exe=swtor_RC2.exe;dxgi=dxmt` for
  Mullion, `dxgi=gptk` for D3DMetal: the DirectX 12 client gets that DXGI tree, every other
  process keeps wined3d. A rule that names an exe applies after the `exe=*` rules, whatever the
  line order;
- with a Mullion driver, the setting downloads my fork's build of Mullion (`MULLION_*` in
  `som.sh`: commit `124bfd5`, 9 MB, checked against its pinned sha256, its `VERSION` against the
  pinned commit) and installs it over the engine's
  `dxgi/dxmt` tree, the engine's own files kept as `<name>.stock` (see [What it
  changes](how-it-works.md#what-it-changes)). A download or tree that isn't the expected one is
  refused with the reason, and the setting stays as it was. Another driver, the setting off, or a
  release build's Reinstall puts the engine's own tree back. If Reinstall can't install Mullion,
  it says so and goes on: `env` then leaves DirectX 12 out, with a line saying why, and the game
  starts as `swtor.exe`. Mullion's logs (`swtor_RC2_<dll>.log`) and its flight record
  (`swtor_RC2.exe.flight`, written when the GPU removes the device) go into SWTOR on Mac's log
  folder (`MULLION_LOG_PATH`, `MULLION_DIAG_PATH`), so Collect Logs has them;
- the client gets Wine's builtin `d3d9` (`WINEDLLOVERRIDES=d3d9=b` from the wrapper, and
  `DllOverrides` under `AppDefaults\swtor_RC2.exe` in the prefix), so d9mt and its Metal bridge
  stay out of the Direct3D 12 process. `swtor.exe` keeps d9mt;
- `AppDefaults\swtor_RC2.exe` gets the values `swtor.exe` has (`GrabPointer`, *Game keys by
  keyboard position*, *Raw mouse-look* and its speed, `ThreadCpuStats`), and follows them when
  they change;
- `wine.log`'s header names it: `SWTOR on Mac DirectX 12: swtor_RC2.exe, driver mullion
  (dxgi=dxmt), Mullion (jdrly/mullion 124bfd5), v0.5-alpha.3-120-g124bfd5, codegen airconv 103`
  (the pin, then the `git describe` line and AIR codegen of the build's `VERSION`), or `driver gptk (dxgi=gptk), D3DMetal 4.0b2 (the
  engine's)`, with `MULLION_D3D12_METAL4=0` or `D3DM_MTL4=0` for a Metal 3 driver. The D3DMetal
  comes from the framework's `Info.plist`, or from the import (see below).

Off, `env` is the same as without the setting, and the `AppDefaults\swtor_RC2.exe` keys go.
Reinstall writes or removes them by the setting too, and Uninstall removes the prefix with them.

### D3DMetal from a Game Porting Toolkit (DirectX 12, development builds)

The engine carries Apple's D3DMetal from Game Porting Toolkit 4.0 beta 2. A development build
can use a newer one, 4.0 beta 3, for the DirectX 12 client. You download the toolkit from
Apple yourself. SWTOR on Mac never downloads, bundles or uploads Apple's files. With the
launcher and the game closed, run in Terminal:

```sh
"/Applications/SWTOR on Mac.app/Contents/Resources/som.sh" dx12-gptk ~/Downloads/Game_Porting_Toolkit_4.0_beta_3.dmg
```

It opens the image read only, and the evaluation environment image inside it. If Apple's licence
agreement shows up, it asks you in Terminal. Then it checks the layout before it changes
anything: `redist/lib` with `libd3dshared.dylib` and `D3DMetal.framework`, both signed by Apple,
and exactly beta 3's shims (`d3d10`, `d3d11`, `d3d12`, `d3d12core`, `dxgi`, `nvapi64`,
`nvngx-on-metalfx`). Any other image is refused and nothing changes. The shims replace the
engine's in `lib/wine/dxgi/gptk` (the engine's stay as `.stock`, and `nvngx-on-metalfx` becomes
`nvngx`). Apple's two libraries go to `lib/external/gptk-import`, and only the DirectX 12
client loads them. `lib/external`'s own pair stays as it is, because every Wine process, the
launcher and the DirectX 9 game included, loads that `libd3dshared.dylib`. The version it
imported goes into `lib/external/gptk-import/IMPORTED`, and `wine.log` names the D3DMetal each
DirectX 12 start ran.

Reinstall (and *Update to <version>* after an app update) puts the engine's own D3DMetal back,
so run the command again after either. Uninstall removes the engine with it.
