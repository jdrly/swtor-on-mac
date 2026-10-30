---
status: accepted
date: 2026-10-22
deciders: Jan Drlý
---

# Nothing of SWTOR on Mac runs while the app is closed; the app checks the launcher hook when it opens

## Context

The official launcher sometimes updates its own Wine and puts Broadsword's preloaders back in
place of SWTOR on Mac's wrapper ([ADR 0003](0003-hook-through-the-preloaders.md)). Up to 0.1.3,
Install set up a launchd job for that, `cz.jandrly.swtoronmac.watch`: launchd started it when
Broadsword's `Wine/bin` changed, and it put the wrapper back. For 0.1.4 the maintainer decided
against any background helper: "when my app is not running, the helper should not be running"
(issue #21).

## Decision

- Nothing of SWTOR on Mac runs while the app is closed: no LaunchAgent, no login item, no daemon.
- The app checks the hook each time it opens, and right before *Play SWTOR* if the hook is gone
  (`som.sh rehook`). If a launcher update replaced the wrapper, it puts it back as Install does.
  It leaves everything alone while an install, uninstall or settings change runs, when another
  tool's wrapper is there, and while the launcher is still changing its Wine (a preloader
  missing, or `Wine/bin` changed in the last 20 seconds). The window then shows the hook as
  removed and offers *Repair the Launcher Hook*.
- Install (an update over 0.1.3 or older) and Uninstall remove the old launchd job, its plist
  and its copy of `som.sh`, unloading it if it is loaded.

## Consequences

- Someone who starts SWTOR from the official app right after a launcher update has replaced its
  Wine plays without SWTOR on Mac (the official way, as the wrapper's absence means) until they
  open SWTOR on Mac once. The maintainer accepts that.
- There is no notification after a launcher update any more; the app shows the state when it
  opens.
- No copy of `som.sh` outside the app, so nothing can run an older script after an app update.

## Alternatives considered

- **Keep the launchd job** (started only by `WatchPaths`, so idle in between): rejected by the
  maintainer's rule that nothing runs while the app is closed.
- **A login item or a menu-bar helper that watches the folder:** a background process, against
  the same rule.
- **Check only on Play SWTOR:** the app opening is the moment players look at the hook's state,
  so it checks there too.

## Implementation status as of 2026-10-22

`cmd_rehook`, `agent_state`, `unload_agent` and `remove_agent_files` in `src/som.sh`;
`Installer.rehook` (at start) and `Installer.play` in `src/native/`; `scripts/test-sandbox.sh`
sections 6c, 7b, 7c (the check) and 11c, 15, 16 (the old job removed over 0.0.6, 0.1.3 and a
development build).
