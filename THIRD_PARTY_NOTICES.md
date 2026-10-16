# Third-party notices

SWTOR on Mac's own code (the app in `src/native`, `som.sh`, `collect-logs.sh`, the Wine
wrapper, `hold-launcher`, `setsid-exec`, the build and release scripts) is under the
[zlib license](LICENSE), copyright (c) 2026 Jan Drlý. The patch to Wine's Mac driver,
[`patches/winemac-physical-keys.patch`](patches/winemac-physical-keys.patch), is a change to
Wine and under Wine's LGPL-2.1-or-later.

The app bundles a few components and downloads others at install time. Star Wars: The Old
Republic, its launcher, game files and Broadsword's Wine are never bundled or downloaded by
SWTOR on Mac: they come from the official install from [swtor.com](https://www.swtor.com).

## Bundled in the app (in the DMG)

| Component | Where in the app | License | License text in the app |
|---|---|---|---|
| **d9mt** `7975e2e`, <https://github.com/jdrly/d9mt> (Jan Drlý's fork of neo773's [d9mt-v2](https://github.com/neo773/d9mt-v2), with code from DXVK) | `Contents/Resources/d9mt/d3d9.dll` | zlib/libpng | `Resources/Licenses/d9mt/LICENSE` |
| **d9mt's winemetal bridge** (derived from [DXMT](https://github.com/3Shain/dxmt)'s `src/winemetal`; includes Wine's `unixlib.h`) | `Contents/Resources/d9mt/winemetal.so`, `winemetal.dll` | LGPL-2.1-or-later. Complete source: [`bridge/` at d9mt `7975e2e`](https://github.com/jdrly/d9mt/tree/7975e2ea6a90493b2c565c75e4fd92bf73f986c6/bridge) | `Resources/Licenses/d9mt/bridge/LICENSE`, `COPYING.LIB` |
| Inside d9mt's binaries: DXVK (zlib/libpng), dxbc-spirv (MIT), LLVM 15.0.7 (Apache-2.0 WITH LLVM-exception, with its regex and ConvertUTF notices), mingw-w64 runtime and winpthreads (ZPL-2.1 / MIT-style / BSD) | as above | see d9mt's notices | `Resources/Licenses/d9mt/THIRD_PARTY_NOTICES.md`, `Resources/Licenses/d9mt/LICENSES/` |
| **Sparkle** 2.10.0, <https://sparkle-project.org> (app updates; with bsdiff, sais, and other notices) | `Contents/Frameworks/Sparkle.framework` | MIT | `Resources/Licenses/sparkle/LICENSE` |
| **Wine's Mac driver** (`dlls/winemac.drv`, x86_64 unix side) from CodeWeavers' [CrossOver 24.0.7 sources](https://media.codeweavers.com/pub/crossover/source/crossover-sources-24.0.7.tar.gz) (sha256 `56749e92…2e4e`, <https://www.codeweavers.com/crossover/source>), changed by SWTOR on Mac's [`patches/winemac-physical-keys.patch`](patches/winemac-physical-keys.patch) (the PhysicalKeyboard option) and built by [`scripts/build-winemac.sh`](scripts/build-winemac.sh) | `Contents/Resources/wine/winemac.so` | LGPL-2.1-or-later. Complete source: those CrossOver sources plus the patch (also in the app) | `Resources/Licenses/winemac/COPYING.LIB`, `LICENSE`, `winemac-physical-keys.patch` |

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
| **Wine engine** `WS12WineCX24.0.7_7`: Wine 9.0 from CodeWeavers' CrossOver 24.0.7 sources, built by [Sikarugir](https://github.com/Sikarugir-App) | [Sikarugir-App/Engines v1.0](https://github.com/Sikarugir-App/Engines/releases/tag/v1.0) | LGPL-2.1-or-later ([Wine](https://www.winehq.org); CrossOver sources: <https://www.codeweavers.com/crossover/source>) |
| **Engine libraries** (FreeType, GnuTLS, SDL, GStreamer and others: `Template-1.0.21.app/Contents/Frameworks`, without its `renderer/` folder) | [Sikarugir-App/Template v1.0](https://github.com/Sikarugir-App/Template/releases/tag/v1.0) | each library's own license (LGPL, MIT, BSD and others), as published by Sikarugir |

The installer changes its copy of the engine in two places: d9mt's winemetal bridge replaces
the engine's `winemetal.so` and `winemetal.dll`, and while *Game keys by keyboard position* is
on in Settings, the bundled Mac driver replaces the engine's `winemac.so` (the engine's own is
kept as `winemac.so.stock` and comes back when the setting is off). It puts d9mt's `d3d9.dll` into its own Wine
prefix (Wine's own is kept as `d3d9.dll.wine`).

## Trademarks

Star Wars: The Old Republic and SWTOR are trademarks of their respective owners. SWTOR on Mac
is an unofficial community project, not made, endorsed or supported by Broadsword Games,
Electronic Arts, Lucasfilm or Disney.
