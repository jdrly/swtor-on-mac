# Third-party notices

SWTOR on Mac's own code (the app in `src/native`, `som.sh`, `collect-logs.sh`, the Wine
wrapper, `hold-launcher`, `setsid-exec`, the build and release scripts) is under the
[zlib license](LICENSE), copyright (c) 2026 Jan Drlý. The patches to Wine's Mac driver in
[`patches/`](patches) (`winemac-physical-keys.patch`, `winemac-swtor-mouse.patch`, and SWGL on
Mac's `winemac-swgl-relative-mouse.patch` and `winemac-swgl-input-thread.patch`, also by Jan
Drlý) are changes to Wine and under Wine's LGPL-2.1-or-later.

The app bundles a few components and downloads others at install time. Star Wars: The Old
Republic, its launcher, game files and Broadsword's Wine are never bundled or downloaded by
SWTOR on Mac: they come from the official install from [swtor.com](https://www.swtor.com).

## Bundled in the app (in the DMG)

| Component | Where in the app | License | License text in the app |
|---|---|---|---|
| **d9mt** `4b7ab26`, <https://github.com/jdrly/d9mt> (Jan Drlý's fork of neo773's [d9mt-v2](https://github.com/neo773/d9mt-v2), with code from DXVK) | `Contents/Resources/d9mt/d3d9.dll` | zlib/libpng | `Resources/Licenses/d9mt/LICENSE` |
| **d9mt's winemetal bridge** (derived from [DXMT](https://github.com/3Shain/dxmt)'s `src/winemetal`; includes Wine's `unixlib.h`) | `Contents/Resources/d9mt/winemetal.so`, `winemetal.dll` | LGPL-2.1-or-later. Complete source: [`bridge/` at d9mt `4b7ab26`](https://github.com/jdrly/d9mt/tree/4b7ab2652ae90383eac965a68da53bf3e81418bb/bridge) | `Resources/Licenses/d9mt/bridge/LICENSE`, `COPYING.LIB` |
| Inside d9mt's binaries: DXVK (zlib/libpng), dxbc-spirv (MIT), LLVM 15.0.7 (Apache-2.0 WITH LLVM-exception, with its regex and ConvertUTF notices), mingw-w64 runtime and winpthreads (ZPL-2.1 / MIT-style / BSD) | as above | see d9mt's notices | `Resources/Licenses/d9mt/THIRD_PARTY_NOTICES.md`, `Resources/Licenses/d9mt/LICENSES/` |
| **Sparkle** 2.10.0, <https://sparkle-project.org> (app updates; with bsdiff, sais, and other notices) | `Contents/Frameworks/Sparkle.framework` | MIT | `Resources/Licenses/sparkle/LICENSE` |
| **Wine's Mac driver** (`dlls/winemac.drv`: the x86_64 unix side and the x86_64 and i386 PE sides) from the Wine sources of the app's engine: CodeWeavers' CrossOver 26.3 sources (<https://www.codeweavers.com/crossover/source>) with athei's patches, [athei/wine `d23b397`](https://github.com/athei/wine/tree/d23b39774528237cafe49f9a073286f854b779c0) (codeload tar.gz sha256 `7002111d…746e`), changed by [`patches/winemac-physical-keys.patch`](patches/winemac-physical-keys.patch) (the PhysicalKeyboard option), [`winemac-swgl-relative-mouse.patch`](patches/winemac-swgl-relative-mouse.patch) and [`winemac-swgl-input-thread.patch`](patches/winemac-swgl-input-thread.patch) (SWGL on Mac's mouse-look patches) and [`winemac-swtor-mouse.patch`](patches/winemac-swtor-mouse.patch) (raw mouse-look for SWTOR), in that order, and built by [`scripts/build-winemac.sh`](scripts/build-winemac.sh) | `Contents/Resources/wine/winemac.so`, `wine/x86_64-windows/winemac.drv`, `wine/i386-windows/winemac.drv` | LGPL-2.1-or-later. Complete source: those sources plus the patches (also in the app) | `Resources/Licenses/winemac/COPYING.LIB`, `LICENSE`, the four `winemac-*.patch` |

The same d9mt files and license texts are in this repository under [`prebuilt/d9mt`](prebuilt/d9mt)
(built by `scripts/build-d9mt.sh`), the Mac driver's under [`prebuilt/winemac`](prebuilt/winemac)
(built by `scripts/build-winemac.sh`); Sparkle is downloaded by `build.sh` at a pinned version
and sha256.

## Downloaded at install time (not in the app, not redistributed)

`som.sh` downloads these from their publishers' GitHub releases onto your Mac when you click
Install, each checked against a pinned sha256 (see `src/som.sh` and the README's *Pinned
components*):

| Component | Source | License |
|---|---|---|
| **Wine engine** `cx-26.3.0-8`: Wine 11.0 from CodeWeavers' CrossOver 26.3 sources with athei's patches ([athei/wine](https://github.com/athei/wine), commit `d23b397`), built and bundled by [athei/wine-build](https://github.com/athei/wine-build), the engine SWGL on Mac uses | [athei/wine-build cx-26.3.0-8](https://github.com/athei/wine-build/releases/tag/cx-26.3.0-8) | LGPL-2.1-or-later ([Wine](https://www.winehq.org); CrossOver sources: <https://www.codeweavers.com/crossover/source>) |
| Inside that engine, as athei/wine-build bundles it: its libraries in `lib/external` (FreeType, GnuTLS, SDL and others), DXMT, mtld3d, x87sidecar and Apple's D3DMetal (Game Porting Toolkit redistributables) | the same release | each component's own license, as published there (`lib/external/D3DMetal-License.rtf`, `x87sidecar-LICENSE`, ...). SWTOR on Mac uses none of the Direct3D backends: the game's Direct3D 9 is d9mt's, and DXGI stays on Wine's wined3d |

The installer changes its copy of the engine in two places (and leaves out its SDK: headers,
Wine's tests, man pages): d9mt's winemetal bridge replaces the engine's `winemetal.so` and its
placeholder `winemetal.dll`, and while *Game keys by keyboard position* or *Raw mouse-look* is
on in Settings, the bundled Mac driver replaces the engine's `winemac.so` and its two
`winemac.drv` (the engine's own are kept as `<name>.stock` and come back when both settings are
off). It puts d9mt's `d3d9.dll` into its own Wine
prefix (Wine's own is kept as `d3d9.dll.wine`).

## Trademarks

Star Wars: The Old Republic and SWTOR are trademarks of their respective owners. SWTOR on Mac
is an unofficial community project, not made, endorsed or supported by Broadsword Games,
Electronic Arts, Lucasfilm or Disney.
