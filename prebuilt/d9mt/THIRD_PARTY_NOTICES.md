# Third-party notices

d9mt combines its own code with code from several other projects. This file
lists every component, where it lives, what it ends up in and its license.
The license texts are in [`LICENSES/`](LICENSES/) unless noted.

## License overview

| Part | License |
|---|---|
| d9mt's own code (neo773's d9mt-v2 and this fork's changes) and the DXVK-derived driver | zlib/libpng, see [`LICENSE`](LICENSE) |
| `bridge/` (the winemetal bridge, DXMT-derived) | LGPL-2.1-or-later, see [`bridge/LICENSE`](bridge/LICENSE) and [`bridge/COPYING.LIB`](bridge/COPYING.LIB) |
| Components fetched or linked at build time | their own licenses, below |

## Components

| Component | Where | Ends up in | License | Text |
|---|---|---|---|---|
| **DXVK** (Philip Rebohle, Joshua Ashton, Robin Kertels, Jeffrey Ellison and contributors), <https://github.com/doitsujin/dxvk> | `driver/d3d9/` (frontend, FF ubershaders in `driver/d3d9/shaders/`, `d3d9.def`), `driver/util/`, `driver/wsi/`, `driver/cs/`, `driver/dxvk/`; see [`driver/UPSTREAM`](driver/UPSTREAM) | `d3d9.dll` | zlib/libpng. **Altered**: Vulkan removed and retargeted to Metal; this is not the original DXVK | [`LICENSES/DXVK-LICENSE.txt`](LICENSES/DXVK-LICENSE.txt) (verbatim), [`LICENSE`](LICENSE) |
| ↳ SHA-1 by Steve Reid (via OpenBSD, as in DXVK) | `driver/util/sha1/` | `d3d9.dll` | Public domain | file header |
| **DXMT** `src/winemetal` and `src/airconv/airconv_public.h` (Feifan He for CodeWeavers), <https://github.com/3Shain/dxmt>, base `964f1308` | `bridge/` (changed files carry a notice; changes in [`bridge/UPSTREAM`](bridge/UPSTREAM)) | `winemetal.so`, `winemetal.dll` (i386, x86_64) | LGPL-2.1-or-later | [`bridge/LICENSE`](bridge/LICENSE), [`bridge/COPYING.LIB`](bridge/COPYING.LIB) |
| ↳ **Wine** `include/wine/unixlib.h` (via DXMT) | `bridge/wineunixlib.h` | bridge | LGPL-2.1-or-later | as above |
| **dxbc-spirv** (Philip Rebohle), <https://github.com/doitsujin/dxbc-spirv>, pinned `c5c1a5b9` | not committed; `scripts/fetch-deps.sh` puts it in `third_party/dxbc-spirv/` | `d3d9.dll` (sm3 parser + IR), `winemetal.so` and `d9mtair.so` (IR core) | MIT | [`LICENSES/dxbc-spirv-LICENSE.txt`](LICENSES/dxbc-spirv-LICENSE.txt) |
| **LLVM 15.0.7**, <https://llvm.org> | not committed; `scripts/build-llvm-unixside.sh` builds it into `toolchains/` | statically linked into `winemetal.so`, `d9mtair.so` and host test tools | Apache-2.0 WITH LLVM-exception | [`LICENSES/LLVM-LICENSE.txt`](LICENSES/LLVM-LICENSE.txt) |
| ↳ Henry Spencer regex (LLVM Support) | as above | `winemetal.so`, `d9mtair.so` | BSD-style (Henry Spencer, UC Regents BSD-3) | [`LICENSES/LLVM-regex-COPYRIGHT.txt`](LICENSES/LLVM-regex-COPYRIGHT.txt) |
| ↳ Unicode ConvertUTF (LLVM Support) | as above | `winemetal.so`, `d9mtair.so` | Unicode, Inc. notice | [`LICENSES/LLVM-ConvertUTF-Unicode.txt`](LICENSES/LLVM-ConvertUTF-Unicode.txt) |
| **mingw-w64 runtime** and **winpthreads** | toolchain (Homebrew `mingw-w64`) | statically linked into the PE files (`d3d9.dll` links `-static`) | mingw-w64: ZPL-2.1 / public domain; winpthreads: MIT-style + BSD (Lockless Inc.) | [`LICENSES/mingw-w64-COPYING.txt`](LICENSES/mingw-w64-COPYING.txt), [`LICENSES/mingw-w64-winpthreads-COPYING.txt`](LICENSES/mingw-w64-winpthreads-COPYING.txt) |
| **libstdc++ / libgcc** (GCC) | toolchain | statically linked into the PE files | GPL-3.0 WITH GCC-exception-3.1 (no notice requirement for the compiled program) | — |
| **SQLite** | macOS system library (`/usr/lib/libsqlite3.dylib`) | dynamically linked by `winemetal.so` | Public domain | — |
| **Apple Metal, MetalFX, QuartzCore** etc. | macOS SDK / system frameworks | dynamically linked by `winemetal.so` | Apple SDK terms | — |
| Embedded metallibs | `driver/d3d9/d3d9_ff_metallib.h` (from DXVK's FF GLSL via glslang + SPIRV-Cross + Apple `metal`), `driver/backend/mtl_blit_metallib.h` (from `driver/backend/shaders/mtl_blit.metal`) | `d3d9.dll` | compiler output of the sources above | — |
| **SPIRV-Cross**, <https://github.com/KhronosGroup/SPIRV-Cross> | not committed; build-time CLI for regenerating the FF metallib, and sources for the host dev tool `scripts/build-air-compiler.sh` (`third_party/SPIRV-Cross`) | not in shipped binaries | Apache-2.0 | upstream |
| **glslang** | build-time CLI (FF metallib regeneration) | not in shipped binaries | BSD-3-Clause and others | upstream |
| **Apple metal-cpp** | not committed; `examples/triangle/` only (`third_party/metal-cpp`) | not in shipped binaries | Apache-2.0 | upstream |
| `scripts/make-builtin.py` | from neo773's d9mt v1 (<https://github.com/neo773/d9mt>) | build step only | zlib (as d9mt's own code) | [`LICENSE`](LICENSE) |

Mesa's KosmicKrisp driver (MIT) was studied as a design reference
(`docs/dev-notes/kk-audit.md`); no Mesa source files are included in this
repository.

## Binary distributions

A binary release (`d3d9.dll`, `winemetal.so`, `winemetal.dll`) must ship:

- `LICENSE` (d9mt + DXVK, zlib)
- `bridge/LICENSE` and `bridge/COPYING.LIB`, plus where to get the exact
  corresponding source (link the release's git tag). The release must be
  buildable from that tag (LGPL-2.1 §6).
- everything in `LICENSES/` (LLVM, its regex and ConvertUTF notices,
  dxbc-spirv, mingw-w64 and winpthreads)
