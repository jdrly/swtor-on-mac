# Triage labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the
label strings of this repository's issue tracker, and lists the type and area labels next to
them.

> **Proposed vocabulary.** The labels marked _new_ do not exist on GitHub yet; the maintainer
> creates them. Until then GitHub ignores them in the issue forms.

## Triage state (exactly one on an open issue)

| Label in mattpocock/skills | Label in our tracker | Meaning                                          | Exists |
| -------------------------- | -------------------- | ------------------------------------------------ | ------ |
| `needs-triage`             | `needs-triage`       | The maintainer needs to evaluate this issue      | _new_  |
| `needs-info`               | `needs-info`         | Waiting on the reporter for more information     | _new_  |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent          | _new_  |
| `ready-for-human`          | `ready-for-human`    | Needs a human: a decision, hardware or the game  | _new_  |
| `wontfix`                  | `wontfix`            | Will not be actioned                             | yes    |

When a skill mentions a role (for example "apply the AFK-ready triage label"), use the label
string from this table. An issue is `ready-for-agent` only when its verification can be done
without a person at the Mac; anything that needs the game played, a real GPU run or a
maintainer's decision is `ready-for-human`.

## Type (exactly one)

| Label           | Meaning                                                   | Exists |
| --------------- | --------------------------------------------------------- | ------ |
| `bug`           | Something doesn't work as the README describes            | yes    |
| `enhancement`   | New or better behaviour                                   | yes    |
| `documentation` | Only the docs change                                      | yes    |
| `performance`   | Frame rate, stutter, pacing (as in d9mt and SWGL on Mac)  | _new_  |

## Area (one or more)

| Label            | Meaning                                                                          | Exists |
| ---------------- | -------------------------------------------------------------------------------- | ------ |
| `area:installer` | Install, Reinstall, Uninstall, the launchd job (`src/som.sh`)                    | _new_  |
| `area:wrapper`   | The wrapper, the Wine session, Game Mode (`src/wine-wrapper.sh`, `src/helpers/`) | _new_  |
| `area:app`       | The window, Settings, Play SWTOR (`src/native/`)                                 | _new_  |
| `area:engine`    | The Wine engine and SWTOR on Mac's Wine builds (`patches/`, `prebuilt/winemac`, `prebuilt/ntdll`) | _new_  |
| `area:d9mt`      | Needs a change in jdrly/d9mt, or the d9mt pin (`prebuilt/d9mt`)                  | _new_  |
| `area:logs`      | Collect Logs, Debug Logging, the session report                                  | _new_  |
| `area:release`   | Build, signing, updates, CI, release notes                                       | _new_  |
