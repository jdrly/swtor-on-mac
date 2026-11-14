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
  `otool -l winemetal.so` showing minos 26.0, since d9mt #110's macOS 26 path is in it. The
  script sets `MACOSX_DEPLOYMENT_TARGET=26.0` itself and refuses an LLVM built for a newer
  macOS; d9mt's `scripts/build-llvm-unixside.sh` builds one for 26.0. From `b532e9c` to
  `1d33ea4` the bridge also had to report the AIR cache lineage 0.1.5.1
  (`build/bridge/air-codegen-id.txt`, d9mt ADR-0006), or the script stopped: another toolchain
  that changes the shader compiler's code would make every player recompile their shaders.
  From `f5439a6` on, the script records the AIR codegen id itself, `AIR_CODEGEN`, and
  `scripts/air-codegen-guard.sh` stops the build unless that file is one line and the line is,
  whole, the recorded id's with no lineage, or a later id's with the lineage of `AIR_LINEAGE`'s
  release. `scripts/build-d9mt.sh --check-air-codegen <file>` runs only that guard.)
- `build.sh` assembles `dist/SWTOR on Mac.app` with Sparkle (pinned download; ad-hoc signed;
  `--install` copies it to /Applications). Needs Xcode 27 (macOS 27 SDK); the app runs on
  macOS 26 and later. The app's `Resources/VERSIONS` (in Collect Logs too) names its components
  and the source tree it was built from: `source <git tree id of HEAD> clean`, or `changed` when
  the working tree had changes, or `source unknown` outside a git checkout.
- `scripts/release.sh` signs a copy with the Developer ID (hardened runtime; the helpers get
  `allow-dyld-environment-variables`, the app and Sparkle no exceptions), builds the DMG,
  notarizes and staples it, and builds the Sparkle feed (`appcast.xml` with delta updates from
  the last 5 versions in `release/updates/`, checked by `scripts/check-appcast.swift`), then
  drafts the GitHub release (`--sign-only`, `--no-notarize`, `--no-release` for local runs
  and the release build; `--dev` for development builds). Before it builds a release, it checks
  the notes' title, summary and Discord invite (release-notes/README.md).
- `scripts/ui-snapshot.sh` builds the app's windows into a small test bundle and runs it on a
  temporary virtual display (swtor-mac-proper's `tools/vd/with-vd.sh`), never on the main one:
  screenshots of the main window in its states, of Settings, of the Logs collected alert and of
  the notice (`shots`), which keys close that alert (`alertkeys`), and what the warp costs (`measure`,
  `sweep`, `findcost`, `idlecheck`, `stillcheck`: CPU, instructions, the GPU time the GPU driver
  counts for the process, frames drawn).
- `.github/workflows/checks.yml` lints the scripts and builds the app on GitHub's `xcode-27`
  image (macOS 27 with Xcode 27, a public preview; there is no `macos-27` label). No workflow
  signs, notarizes or builds a release.

- `scripts/build-winemac.sh` builds Wine's Mac driver (`winemac.so`, x86_64, and its PE sides
  `x86_64-windows/` and `i386-windows/winemac.drv`) from the sources the engine is built from
  (athei/wine at the commit athei/wine-build's release names, pinned sha256; configured like
  athei's build; the engine download pinned in `src/som.sh` for linking) with
  `patches/winemac-physical-keys.patch`, SWGL on Mac's `winemac-swgl-relative-mouse.patch` and
  `winemac-swgl-input-thread.patch` (unchanged copies), `winemac-swtor-mouse.patch` and
  `winemac-native-fullscreen.patch`, in that order, into `prebuilt/winemac`, together with an
  unpatched build: `scripts/winemac-compare.py` checks that one against the engine's own
  `winemac.so` and that the patches change only the keyboard and mouse functions, the native
  fullscreen functions (named one by one) and the options; the PE sides are checked by their imports and
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

Agents build, sign, notarize, check and publish every release on my Mac. The Developer ID
certificate, the notary credentials and Sparkle's EdDSA key exist only there. No workflow builds
a release or signs with the Developer ID; the Checks workflow's build is ad-hoc signed and goes
nowhere. Nobody approves a step or clicks anything once I've played the release
candidate. [ADR 0007](adr/0007-releases-from-the-maintainers-mac.md) has the reasons. Every release has
been built on my Mac, by agents since 0.1.2: no tag's run of the old Release workflow ever
finished.

1. **The release candidate.** The app at a commit of `main`, through the checks its changes call
   for (the fixture groups, `scripts/test-sandbox.sh`, the d9mt pin's checks; CONTRIBUTING.md,
   *Definition of Done*). I play it.
2. **The version PR.** `APP_VERSION` in `build.sh`, `release-notes/<version>.md` and the
   README's current version and *Pinned components* line, squash-merged into `main`. Its Checks
   run includes the d9mt pin check (below).
3. **The build**, in a clean checkout of the squash commit: `./build.sh`, then
   `scripts/release.sh --no-release`. It signs, notarizes and staples the DMG, builds the feed
   with deltas from the last five releases' DMGs in `release/updates/`, checks the feed with
   `scripts/check-appcast.swift` and applies every delta. It then writes the **receipt**,
   `release/<version>/RECEIPT` (`scripts/release-receipt.sh`): the version, build and channel, the
   source tree the app was built from (the `source` line of its `VERSIONS`: git's tree id and
   whether the working tree was clean), the notes' sha256 and the sha256 of the DMG, each delta
   and `appcast.xml`. No keys, user names or paths. Each gate below that passes on these files
   is added with `scripts/release-receipt.sh gate release/<version> <name> pass`, which first
   checks that the files are still the receipt's.
4. **The checks of the DMG's own app**, without Wine: `codesign --verify --deep --strict`,
   `spctl` for the app and the DMG, `stapler validate`, the `Info.plist` keys and versions, the
   feed (`check-appcast.swift`, and it names the version), `som.sh status` in an empty sandbox
   and `scripts/test-btm.sh`.
5. **The binary-diff gate**, two comparisons of the DMG's app. Both have to pass.
   - Against the release candidate I played: every Mach-O file is byte-identical or differs only
     in its signature (compared after `codesign --remove-signature`), and d9mt's and Wine's
     Windows files (the DLLs and `.drv` files) are byte-identical. Any other file differs only in
     the version files (`Info.plist`, `app.properties`, `VERSIONS`), `Licenses/README.txt`,
     `Assets.car` (actool's output isn't reproducible) and what the version PR changed.
   - Against the last release's published app: a file differs only where the commits between the
     two releases changed it or what it is built from. The files from `prebuilt/` (d9mt, the Mac
     driver, `ntdll.so`) are the committed ones byte for byte, Mach-O files up to their
     signature, and each changed script is its source at the squash commit.

   A file added, removed or changed anywhere else stops the release. The first comparison shows
   that the build being published is the one I played; the second, that nothing changed since
   the last release that the commits don't explain.
6. **Publish**, after `scripts/release-receipt.sh verify release/<version> --commit <squash commit>
   --notes release-notes/<version>.md` passes and the squash commit is on `origin/main`. Verify
   reads only and runs nothing of the commit: the files against the receipt's hashes, the DMG's
   name, the channel and the feed's versions against the receipt, an app built from a clean tree,
   and at the commit to be tagged the same source tree (a squash merge's equal tree passes),
   build.sh's `APP_VERSION` and the notes, and the notes file to upload. It fails before anything
   is uploaded. Then:
   `gh release create v<version> --target <squash commit> --latest --title "SWTOR on Mac <version>" --notes-file release-notes/<version>.md`
   with exactly the DMG, the deltas and `appcast.xml`. The tag this creates starts no build. The
   Site workflow runs on the published release and rebuilds swonmac.com.
7. **Verify.** `scripts/release-receipt.sh verify release/<version> --release v<version>`
   downloads the release's assets and compares them with the receipt, the same files with the
   same hashes, naming each one. Then check that `https://github.com/jdrly/swtor-on-mac/releases/latest/download/appcast.xml` names
   the new version, that the release is the latest, and that the Site run passed.

Changing the notes after the build doesn't rebuild anything. The change is a notes-only commit,
the feed's `<description>` (the notes as Markdown, in CDATA) is replaced with the new notes, and
the feed is checked again with `scripts/check-appcast.swift`. Its signatures cover the DMG and
the deltas, not the description, so they stay valid. `scripts/release-receipt.sh write
release/<version> release-notes/<version>.md` then writes the receipt again with the new feed and
notes; with the DMG and the deltas unchanged it keeps the gate runs. The release is published from
the notes' commit, whose tree may differ from the receipt's only in `release-notes/<version>.md`.

Development builds' `--dev` writes a receipt too (the DMG only) and verifies it against `HEAD`
before it creates the pre-release; so does the one-go `scripts/release.sh` below before its draft.

Development builds (`APP_VERSION` `X.Y.Z-dev.N`, on the `dev` branch):
`./build.sh && scripts/release.sh --dev`. It signs, notarizes and staples the DMG, then
creates the GitHub pre-release `v<version>` with the DMG and `release-notes/<version>.md`, and
no feed. The other modes refuse dev versions.

`./build.sh && scripts/release.sh` also does everything in one go (sign, notarize, feed, a draft
release with the DMG, the deltas and the feed), without the gates above.

## d9mt pin

`scripts/check-d9mt-pin.sh` checks the pin against d9mt's own CI: `prebuilt/d9mt/VERSION` is the
`COMMIT` of `scripts/build-d9mt.sh`, that commit is on `jdrly/d9mt`'s `main`, and d9mt's `Checks`
workflow has a green run of exactly that commit (a push, a nightly run or a run by hand; a pull
request's run tests another tree and doesn't count). The Checks workflow runs it on every pull
request, the version PR's included. A pin older than d9mt's CI (before `45fcedb`)
passes with a note. Exit status 1 means the pin fails; 2 means GitHub didn't answer or d9mt's run
hasn't finished, which is no verdict: run it again.

`main` pins d9mt `f5439a6`, d9mt main after jdrly/d9mt#190: the driver of 0.1.8, the one
release that changes the AIR codegen on purpose. Since `1d33ea4` it adds:

- the AIR target per macOS, #167: AIR 2.8 and Metal 4.0 on macOS 26, AIR 2.9 and Metal 4.1 on
  macOS 27 and later, in the bitcode and in the container. `D9MT_AIR_LEGACY=1` writes 0.1.7's
  fields, as a support switch;
- dxbc-spirv at `76236b82` with four d9mt patches, #168;
- the pixel shader function chosen by each draw's `D3DSHADE_FLAT`, #169;
- Apple's position-invariance form for SM3 vertex shaders, #172;
- the fixed-function batch, #173: a flat fragment shader, DXVK's fog, clip plane and
  DOTPRODUCT3 fixes, the fixed-function vertex shader compiled with `-fpreserve-invariance`, and
  cube and volume textures in fixed-function stages;
- Metal's pipeline archives in a folder per AIR identity and AIR target, #174;
- `D9MT_DEPTH_BIAS_VS=1`, #175, off by default: the constant depth bias applied in the vertex
  shader on float depth formats;
- `D3DRS_FILLMODE` sent to Metal, so a wireframe draw is a wireframe, #165;
- d9mt's own CI and test scripts, #160 and #176 to #190. None of them changes the driver's or
  the bridge's code. #181 lists the codegen's files in byte order in the bridge's build, so the
  AIR codegen id no longer depends on the locale of the shell that starts the build.

#167, #168 and #172 change the AIR codegen, so the bridge reports a new id, `25fc2491…`, with no
lineage: every player's shaders recompile once after the update to 0.1.8. #175 changes no codegen
and is off by default. Metal's pipeline archives are rebuilt too, and #174 deletes the folders
earlier versions left behind on the first start; a folder that a running game still holds stays
until that game has ended. `scripts/build-d9mt.sh` records the id in `AIR_CODEGEN` and stops a
build that reports another one (above), because a second new id would make every player
recompile again. The id doesn't depend on my Mac: GitHub's hosted runner and a rented M1, each
with Xcode 27.0 and its own LLVM 15.0.7 from d9mt's recipe, build the same one.

`1d33ea4`, d9mt main after jdrly/d9mt#155, was the driver of 0.1.7. Since `73511be` (#125, a
StretchRect sub-rect resolved at its offset) it added the GPU-fault fixes #133, #135 to #137, #147, #148
and #151, the DXVK hang fixes #138 and #139, the anti-aliasing compression fix for M1–M4 #140, the
pipeline descriptor changes #156 and #157, and the diagnostics #134, #141, #154 and #155. The bridge
changed, but its AIR codegen id was still `38243f7b…` (lineage 0.1.5.1), so players kept 0.1.6's
shader cache. #156 and #157 changed how render pipelines are described to Metal, so Metal's own
pipeline archive missed once for those pipelines. `b532e9c`, main after jdrly/d9mt#122, keeps
the shaders players compiled with 0.1.5.1 on macOS 27 (#122: the AIR cache keyed on the shader
compiler's code, with 0.1.5.1's cache adopted; AIR codegen id `38243f7b…`, lineage 0.1.5.1). It
brings shaders
tagged with the AIR version macOS 26 accepts (#110), textures sampled before their first write
read as empty (#105), a GPU hang ends the game (#53), the per-draw vertex copy clamped from the
first vertex (#57), the GPU canary on every present and at most every 250 ms otherwise (#67), and
the default-off A/B switches `D9MT_PSO_ASYNC_FLUSH` (#114), `D9MT_FLUSH_CAP` (#113) and
`D9MT_COMPILE_MAXCONC` (#117). Before them came the frame cap `D9MT_FPS_CAP` (#47), the present
path's drawable kept until the GPU is done with it (#26), the PSO key changes (#32 to #34, #40;
the state cache's mapping version 4), the state cache journal (#35), and fixed-function and
argument-table fixes (#37, #38). Issue and pull request numbers are in
[jdrly/d9mt](https://github.com/jdrly/d9mt).
