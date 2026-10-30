# Building and releasing

- `scripts/build-d9mt.sh` builds d9mt (x86_64) at a pinned commit of
  [jdrly/d9mt](https://github.com/jdrly/d9mt) in a scratch clone into `prebuilt/d9mt`
  (Homebrew bash, mingw-w64, cmake, ninja, Xcode; an LLVM 15 build for macOS 26 via
  `D9MT_LLVM`): d9mt's `scripts/fetch-deps.sh` (dxbc-spirv at its pin with d9mt's patches),
  then a build from scratch every time. It is reproducible: `SOURCE_DATE_EPOCH` is the commit's
  time, and the same `D9MT_WORK` path gives the same `d3d9.dll`. (0.1.1's `winemetal.dll` is
  0.1.0's: the bridge's source is the same, and `SOURCE_DATE_EPOCH=1792149856` builds it byte
  for byte. 0.1.2's `d3d9.dll` is d9mt main `2a1bc00` built with `SOURCE_DATE_EPOCH=1792457826`,
  the time of `c3f46ce`, which has the same tree: byte for byte the file 0.1.2-dev.2 and dev.3
  were tested with. 0.1.4 pins main `b0d4597` and 0.1.6 main `b532e9c`, each built with its own
  commit time; from `8b22a99` on, `winemetal.so` must come from an LLVM built for macOS 26.0,
  `otool -l winemetal.so` showing minos 26.0, since d9mt #110's macOS 26 path is in it. From
  `b532e9c` on, the bridge must also report the AIR cache lineage `AIR_LINEAGE` names
  (`build/bridge/air-codegen-id.txt`, d9mt ADR-0006), or the script stops: another toolchain
  that changes the shader compiler's code would make every player recompile their shaders.)
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
  screenshots of the main window in its states, of Settings, of the Logs collected alert and of
  the notice (`shots`), which keys close that alert (`alertkeys`), and what the warp costs (`measure`,
  `sweep`, `findcost`, `idlecheck`, `stillcheck`: CPU, instructions, the GPU time the GPU driver
  counts for the process, frames drawn).
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

## Releasing

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

## d9mt pin

`main` pins d9mt `b532e9c`, main after jdrly/d9mt#122. It keeps the shaders players compiled
with 0.1.5.1 on macOS 27 (#122: the AIR cache keyed on the shader compiler's code, with 0.1.5.1's
cache adopted; AIR codegen id `38243f7b…`, lineage 0.1.5.1). It brings shaders
tagged with the AIR version macOS 26 accepts (#110), textures sampled before their first write
read as empty (#105), a GPU hang ends the game (#53), the per-draw vertex copy clamped from the
first vertex (#57), the GPU canary on every present and at most every 250 ms otherwise (#67), and
the default-off A/B switches `D9MT_PSO_ASYNC_FLUSH` (#114), `D9MT_FLUSH_CAP` (#113) and
`D9MT_COMPILE_MAXCONC` (#117). Before them came the frame cap `D9MT_FPS_CAP` (#47), the present
path's drawable kept until the GPU is done with it (#26), the PSO key changes (#32 to #34, #40;
the state cache's mapping version 4), the state cache journal (#35), and fixed-function and
argument-table fixes (#37, #38). Issue and pull request numbers are in
[jdrly/d9mt](https://github.com/jdrly/d9mt).
