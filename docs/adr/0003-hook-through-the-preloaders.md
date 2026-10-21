---
status: accepted
date: 2026-10-21
deciders: Jan Drlý
---

# The game reaches SWTOR on Mac through a wrapper in the preloaders' place; Install is all or nothing and Uninstall puts Broadsword's folder back

## Context

SWTOR on Mac works on top of the official app and must not change the game's files or the
launcher (README, notice and *What it changes*). The launcher starts every
Wine process through `bin/wine64`, which loads `bin/wine64-preloader` (README, *How it works*).
Players must be able to go back to exactly what Broadsword ships.

## Decision

- The wrapper (`src/wine-wrapper.sh`) is installed as `bin/wine64-preloader` and
  `bin/wine-preloader`; Broadsword's preloaders move, unchanged, to `bin-real/`, next to
  SWTOR on Mac's helpers `hold-launcher` and `setsid-exec`. Those are the changes Install makes in
  Broadsword's install; `bin/wine64` stays the real program (README, *What it changes*;
  `src/wine-wrapper.sh`). The prefix is only read (it is cloned once).
- Without SWTOR on Mac's `env` or engine, the wrapper runs Broadsword's real preloader, so a
  half-removed setup still starts the game the official way.
- Install is idempotent and all or nothing: it refuses while the launcher or the game runs,
  prepares everything in SWTOR on Mac's folders first, touches Broadsword's folder last, and rolls
  back what it created if anything fails (README, *How it works*; `cmd_install` and
  `on_install_exit` in `src/som.sh`).
- Another tool's wrapper is left alone unless the player confirms; SWTOR on Mac then keeps a copy
  in `backup/` (README, *Troubleshooting*).
- Uninstall puts Broadsword's preloaders back, checked against the sha256 recorded in the install
  manifest, and removes `bin-real/`. It also copies the game settings from SWTOR on Mac's prefix
  back into Broadsword's, with a backup of the previous ones (`restore_game_settings` in
  `src/som.sh`; README, *Uninstall*). `scripts/test-sandbox.sh` checks that everything in
  Broadsword's folder apart from those game settings comes back byte for byte.

## Consequences

- A launcher update that replaces its Wine also removes the hook; the launchd job puts it back,
  or the window offers *Repair the Launcher Hook* (README, *Launcher updates*).
- Every Wine process the launcher starts goes through the wrapper, not only the game's; the
  wrapper has to handle `mac_wine`'s calls and the Wine session correctly (README, *How it
  works*).
- The wrapper and `som.sh` run under macOS's `/bin/bash` 3.2, which the Checks workflow tests.
- Uninstall, the manual removal steps and the tests have to stay in step with the install
  (README, *Removing it by hand*).

## Alternatives considered

None are recorded in this repository. _Open:_ the maintainer adds the alternatives that were
weighed (for example changing `bin/wine64` itself, or starting the game outside the launcher),
or this section states that none were.
