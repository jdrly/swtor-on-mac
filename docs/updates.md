# Updates and development builds

How SWTOR on Mac updates itself and the installed setup, and how development builds differ from releases.

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

## Development builds

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
  comparison; Settings' Frame Rate Limit wins over `cap=` while it is on), `unwritten-off`
  (`D9MT_UNWRITTEN_NULL=0`: d9mt #105 off), the switches that are off by default for an A/B:
  `pso-async` (`D9MT_PSO_ASYNC_FLUSH=1`, d9mt #114), `flush-cap` and `flush-cap-off`
  (`D9MT_FLUSH_CAP=1` or `0`, #113; they win over Settings' Fewer GPU Batches) and
  `compile-maxconc` (`D9MT_COMPILE_MAXCONC=1`, #117), and `cold=<name>` (an empty shader cache and pipeline
  archives of their own in `~/Library/Caches/SWTOR on Mac/d9mt-ab/<name>`, d9mt's own caches
  untouched). Each call sets exactly the switches it names; `d9mt-ab.sh` alone shows them,
  `reset` clears them (`--clean` also deletes the cold caches). They are kept in
  `d9mt-ab.env` next to `env`, which only a development build's `env` reads, so Settings keep
  them; `wine.log` names them in its second line and the session report shows them. A
  release's Reinstall over a development build removes `d9mt-ab.env` and the cold caches.
