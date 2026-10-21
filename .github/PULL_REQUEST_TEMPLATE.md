## What changes

<!-- Two to five sentences: what this PR does and why, not a list of files. -->

Closes #

- **ADR:** none <!-- or docs/adr/NNNN-… -->

## How to verify

<!-- Steps for the reviewer: the Mac, the starting install, what to click, which log line or test section shows it. -->

## Definition of Done

- [ ] `shellcheck -S warning` and `/bin/bash -n` (macOS's bash 3.2) on the scripts, `actionlint` on the workflows, and `./build.sh` (Xcode 27) pass locally.
- [ ] A change to `src/som.sh`, `src/wine-wrapper.sh`, the helpers or Collect Logs passes `scripts/test-sandbox.sh`; a change to updates is tested with `scripts/test-update.sh`.
- [ ] A bug fix has a regression check that fails without the fix (a `test-sandbox.sh` section where it can reach; otherwise the manual check is described above).
- [ ] Install stays all-or-nothing, and Uninstall still puts Broadsword's folder back byte for byte apart from the game settings it copies back.
- [ ] No log, `env` or Collect Logs file gains account names, e-mail addresses, the user name or the launcher's command line.
- [ ] A change on the game's path (wrapper, `env`, the engine's parts, the d9mt pin) is nothing measurably slower: session reports before and after (`session-report.sh --compare`).
- [ ] A new d9mt pin updates `scripts/build-d9mt.sh`, `prebuilt/d9mt` and the README's *Pinned components* together.
- [ ] The README describes the new behaviour; terms follow `CONTEXT.md`, and a new term is added in this PR.
- [ ] A changed decision has an ADR in this PR, or links an existing `accepted` ADR.
- [ ] The independent agent review (preferably GPT-6.1-Sol) has no open `Blocker` or `High`, and its verdict is in the PR.
- [ ] The issue's UAT scenario has been clicked through and ticked off in the issue.

## Review

<!-- An independent agent (preferably GPT-6.1-Sol) reviews this PR and puts its verdict here or in a comment. Squash-merge (subject = PR title) after a clean verdict (no open Blocker or High) and green checks. -->

- **Verdict:** pending

## Risks and what I didn't do

<!-- Known limits, deferred work, effects on existing installs and on the way back to an older version. An empty field is an answer too: write "none". -->
