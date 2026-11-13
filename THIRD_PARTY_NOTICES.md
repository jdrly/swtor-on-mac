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
| **d9mt** `f5439a6`, <https://github.com/jdrly/d9mt> (Jan Drlý's fork of neo773's [d9mt-v2](https://github.com/neo773/d9mt-v2), with code from DXVK) | `Contents/Resources/d9mt/d3d9.dll` | zlib/libpng | `Resources/Licenses/d9mt/LICENSE` |
| **d9mt's winemetal bridge** (derived from [DXMT](https://github.com/3Shain/dxmt)'s `src/winemetal`; includes Wine's `unixlib.h`) | `Contents/Resources/d9mt/winemetal.so`, `winemetal.dll` | LGPL-2.1-or-later. Complete source: [`bridge/` at d9mt `f5439a6`](https://github.com/jdrly/d9mt/tree/f5439a625c3c30697d53ac658f86801ca6083e7f/bridge) | `Resources/Licenses/d9mt/bridge/LICENSE`, `COPYING.LIB` |
| Inside d9mt's binaries: DXVK (zlib/libpng), dxbc-spirv (MIT), LLVM 15.0.7 (Apache-2.0 WITH LLVM-exception, with its regex and ConvertUTF notices), mingw-w64 runtime and winpthreads (ZPL-2.1 / MIT-style / BSD) | as above | see d9mt's notices | `Resources/Licenses/d9mt/THIRD_PARTY_NOTICES.md`, `Resources/Licenses/d9mt/LICENSES/` |
| **Sparkle** 2.10.0, <https://sparkle-project.org> (app updates; with bsdiff, sais, and other notices) | `Contents/Frameworks/Sparkle.framework` | MIT | `Resources/Licenses/sparkle/LICENSE` |
| **Wine's Mac driver** (`dlls/winemac.drv`: the x86_64 unix side and the x86_64 and i386 PE sides) from the Wine sources of the app's engine: CodeWeavers' CrossOver 26.3 sources (<https://www.codeweavers.com/crossover/source>) with athei's patches, [athei/wine `d23b397`](https://github.com/athei/wine/tree/d23b39774528237cafe49f9a073286f854b779c0) (codeload tar.gz sha256 `7002111d…746e`; the same archive in [jdrly/wine-engine](https://github.com/jdrly/wine-engine/releases/download/cx-26.3.0-8/wine-d23b39774528237cafe49f9a073286f854b779c0-source.tar.gz)), changed by [`patches/winemac-physical-keys.patch`](patches/winemac-physical-keys.patch) (the PhysicalKeyboard option), [`winemac-swgl-relative-mouse.patch`](patches/winemac-swgl-relative-mouse.patch) and [`winemac-swgl-input-thread.patch`](patches/winemac-swgl-input-thread.patch) (SWGL on Mac's mouse-look patches) and [`winemac-swtor-mouse.patch`](patches/winemac-swtor-mouse.patch) (raw mouse-look for SWTOR), in that order, and built by [`scripts/build-winemac.sh`](scripts/build-winemac.sh) | `Contents/Resources/wine/winemac.so`, `wine/x86_64-windows/winemac.drv`, `wine/i386-windows/winemac.drv` | LGPL-2.1-or-later. Complete source: those sources plus the patches (also in the app) | `Resources/Licenses/winemac/COPYING.LIB`, `LICENSE`, the four `winemac-*.patch` |
| **Unbounded** (variable, `wght` 200 to 900), copyright 2022 The Unbounded Project Authors, <https://github.com/googlefonts/unbounded>, from [google/fonts `ofl/unbounded`](https://github.com/google/fonts/tree/main/ofl/unbounded) (`Unbounded[wght].ttf`, sha256 `323b511b…2c3f`), unmodified | `Contents/Resources/Fonts/Unbounded-Variable.ttf` | SIL Open Font License 1.1 | `Resources/Licenses/fonts/Unbounded-OFL.txt` |
| **JetBrains Mono** (variable, `wght` 100 to 800), copyright 2020 The JetBrains Mono Project Authors, <https://github.com/JetBrains/JetBrainsMono>, from [google/fonts `ofl/jetbrainsmono`](https://github.com/google/fonts/tree/main/ofl/jetbrainsmono) (`JetBrainsMono[wght].ttf`, sha256 `48715a42…feda`), unmodified | `Contents/Resources/Fonts/JetBrainsMono-Variable.ttf` | SIL Open Font License 1.1 | `Resources/Licenses/fonts/JetBrainsMono-OFL.txt` |
| **Wine's ntdll** (`dlls/ntdll`: the x86_64 unix side, `ntdll.so`) from the same Wine sources of the app's engine ([athei/wine `d23b397`](https://github.com/athei/wine/tree/d23b39774528237cafe49f9a073286f854b779c0), also as an [archive in jdrly/wine-engine](https://github.com/jdrly/wine-engine/releases/download/cx-26.3.0-8/wine-d23b39774528237cafe49f9a073286f854b779c0-source.tar.gz)), changed by [`patches/ntdll-msync-alert-fd.patch`](patches/ntdll-msync-alert-fd.patch) (with msync, an exiting thread no longer closes an unrelated file descriptor) and built by [`scripts/build-ntdll.sh`](scripts/build-ntdll.sh) | `Contents/Resources/wine/ntdll.so` | LGPL-2.1-or-later. Complete source: those sources plus the patch (also in the app) | `Resources/Licenses/ntdll/COPYING.LIB`, `LICENSE`, `ntdll-msync-alert-fd.patch` |

The same d9mt files and license texts are in this repository under [`prebuilt/d9mt`](prebuilt/d9mt)
(built by `scripts/build-d9mt.sh`), the Mac driver's under [`prebuilt/winemac`](prebuilt/winemac)
(built by `scripts/build-winemac.sh`), ntdll's under [`prebuilt/ntdll`](prebuilt/ntdll) (built by
`scripts/build-ntdll.sh`), the fonts and their licenses under [`src/fonts`](src/fonts); Sparkle is downloaded by `build.sh` at a pinned version
and sha256.

## Downloaded at install time (not in the app)

`som.sh` downloads these onto your Mac when you click Install, each checked against a pinned
sha256 (see `src/som.sh` and the README's *Pinned components*):

| Component | Source | License |
|---|---|---|
| **Wine engine** `cx-26.3.0-8`: Wine 11.0 from CodeWeavers' CrossOver 26.3 sources with athei's patches ([athei/wine](https://github.com/athei/wine), commit `d23b397`), built and bundled by athei, the engine SWGL on Mac uses. athei's release of it is gone, so jdrly/wine-engine hosts the same file, byte for byte (ADR-0006) | [jdrly/wine-engine cx-26.3.0-8](https://github.com/jdrly/wine-engine/releases/tag/cx-26.3.0-8), with its source, [`wine-d23b397…-source.tar.gz`](https://github.com/jdrly/wine-engine/releases/download/cx-26.3.0-8/wine-d23b39774528237cafe49f9a073286f854b779c0-source.tar.gz) (athei/wine [`d23b397`](https://github.com/athei/wine/tree/d23b39774528237cafe49f9a073286f854b779c0)) | LGPL-2.1-or-later ([Wine](https://www.winehq.org); CrossOver sources: <https://www.codeweavers.com/crossover/source>) |
| **Mullion** (Direct3D 10, 11 and 12 to Metal) as my fork builds it, commit `124bfd5`: [Mullion](https://github.com/dttdrv/mullion) by dttdrv, built on [DXMT](https://github.com/3Shain/dxmt), with LLVM and llvm-mingw's MinGW-w64 runtime. Only development builds download it, when DirectX 12 is on with a Mullion driver | [jdrly/mullion `swtor-builds`](https://github.com/jdrly/mullion/releases/tag/swtor-builds), `mullion-swtor-124bfd5f3f166b77926abf553649b4a1ccb8b8bf.tar.xz`, built by the fork's SWTOR workflow; source: [jdrly/mullion `124bfd5`](https://github.com/jdrly/mullion/tree/124bfd5f3f166b77926abf553649b4a1ccb8b8bf) with its submodules (the archive's `SOURCE`) | LGPL-2.1-or-later (DXMT's code from its releases up to v0.80 also MIT; LLVM Apache-2.0 WITH LLVM-exception; the MinGW-w64 runtime ZPL-2.1 and the parts it marks public domain, BSD or LGPL): `LICENSE`, `LICENSE-LLVM.txt` and `licenses/` (with `licenses/mingw-w64/`) in the archive |
| Inside that engine, as athei bundled it: its libraries in `lib/external` (FreeType, GnuTLS, SDL and others), DXMT, mtld3d, x87sidecar and Apple's D3DMetal (Game Porting Toolkit redistributables) | the same release | each component's own license, as published there (`lib/external/D3DMetal-License.rtf`, `x87sidecar-LICENSE`, ...). SWTOR on Mac uses none of the Direct3D backends: the game's Direct3D 9 is d9mt's, and DXGI stays on Wine's wined3d. Only a development build's DirectX 12 setting gives `swtor_RC2.exe` D3DMetal, or Mullion in the DXMT tree's place |

The installer changes its copy of the engine in three places, four in a development build on
Mullion (and leaves out its SDK: headers,
Wine's tests, man pages): d9mt's winemetal bridge replaces the engine's `winemetal.so` and its
placeholder `winemetal.dll`, the bundled `ntdll.so` replaces the engine's (kept as
`ntdll.so.stock`), and while *Game keys by keyboard position* or *Raw mouse-look* is
on in Settings, the bundled Mac driver replaces the engine's `winemac.so` and its two
`winemac.drv` (the engine's own are kept as `<name>.stock` and come back when both settings are
off). In a development build with DirectX 12 on a Mullion driver, Mullion's x86_64 files replace
the engine's in its `lib/wine/dxgi/dxmt` tree (the engine's own are kept as `<name>.stock` and
come back when the setting is off). A development build's `som.sh dx12-gptk` copies D3DMetal
from a Game Porting Toolkit image the user downloaded from Apple into the engine's `gptk` tree
and `lib/external/gptk-import` (the engine's own come back at the next install). SWTOR on Mac
never downloads, bundles or distributes those files. It puts d9mt's `d3d9.dll` into its own Wine
prefix (Wine's own is kept as `d3d9.dll.wine`).

## Trademarks

SWTOR on Mac is an unofficial fan project and is not affiliated with or endorsed by Lucasfilm,
Disney, Electronic Arts or Broadsword Online Games. STAR WARS is a registered trademark of
Lucasfilm Ltd. Star Wars: The Old Republic and SWTOR are trademarks of their respective owners.
Mac is a trademark of Apple Inc.
