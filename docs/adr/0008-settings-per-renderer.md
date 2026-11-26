---
status: accepted
date: 2026-11-26
deciders: Jan Drlý
---

# One app keeps a set of settings per renderer, in one settings.conf

## Context

Jan ran two installs, the DirectX 9 release and the DirectX 12 development build, sharing one
settings folder. Every switch meant unchecking what doesn't work with the other renderer. Two
apps side by side were tried and dropped (they share Broadsword's launcher hook). DirectX 12 will
replace DirectX 9, so Jan chose one app, the development build, with the settings remembered per
renderer (Jan, 2026-11-26).

## Decision

- Development builds keep a DirectX 9 and a DirectX 12 set. *DirectX 12 (experimental)* picks the
  one the window shows and changes. Some settings are global, and the DirectX 9-only ones are off
  and greyed out in DirectX 12's set (docs/settings.md, *DirectX 12*).
- **Where they live.** `settings.conf` keeps the DirectX 9 set as `key=value`, as before, and
  DirectX 12's per-renderer settings (Show Metal HUD and its position) as `dx12.<key>=value`. A
  file of one set gets both at the hook check, DirectX 12's seeded from it; that check writes
  `settings.conf` only (the dispatcher's decision, 2026-11-26), and Update writes the other files
  and the wrapper for this version.
- **Retina mode is global.** Wine's Mac driver reads `RetinaMode` for the whole prefix and not
  per program (athei/wine d23b397, `dlls/winemac.drv/macdrv_main.c:360`), so one value serves
  both clients (the dispatcher's decision, 2026-11-26).
- **What runs.** The files made from the settings hold both sets: `swtor.exe`'s prefix values,
  Retina mode, `env`'s game settings and `dxvk.conf` are DirectX 9's;
  `swtor_RC2.exe`'s values and `env`'s DirectX 12 lines are DirectX 12's. The game runs with the
  set of the client that starts, so a fallback from DirectX 12 to `swtor.exe` runs with DirectX
  9's set, and `wine.log` says it fell back (the dispatcher's decision, 2026-11-26).
- A settings change that fails puts `settings.conf`, `dxvk.conf` and `user.reg` back and makes
  `env` again from them, for the drivers the engine has then.
- An earlier version's install keeps its own wrapper and files until Update (Play doesn't replace
  them), so `swtor_RC2.exe` runs with that version's values meanwhile, and DirectX 12's set and
  the switch can't change.

## Consequences

- A release build (0.1.9 and the release line) reads the DirectX 9 set as its own, unchanged. One
  that writes the file drops the `dx12.` lines, and DirectX 12's set then starts again from the
  DirectX 9 one: Jan uses the development build alone, so this is accepted.
- The engine's Mac driver follows the DirectX 9 set. With its options off for `swtor_RC2.exe`, the
  app's build does what the engine's own does.
- The second app can go: nothing of it is needed.

## Alternatives considered

- **Two apps side by side** (feat/apps-side-by-side, parked): seven review rounds on the shared
  launcher hook, stopped by Jan.
- **Two settings files:** every reader of `settings.conf` (the window, `som.sh`, a release build)
  would need to know which to open; one file with prefixed lines keeps the release reader as it is.
