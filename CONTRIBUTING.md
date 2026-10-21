# Contributing

Thanks for helping with SWTOR on Mac.

- **Bugs:** open a [bug report](https://github.com/jdrly/swtor-on-mac/issues/new/choose) with
  the Collect Logs zip (SWTOR on Mac > Collect Logs…), or contact Pharaphobia on
  [Discord](https://discord.gg/AnV3fZWz2b). Never send them to Broadsword or SWTOR customer
  support.
- **Security problems:** privately, as [SECURITY.md](SECURITY.md) describes, not as a public
  issue.
- **Pull requests** are welcome. For anything larger than a small fix, open an issue first so we
  can agree on the approach. The rest of this file is how work is specified, reviewed and
  merged.

By contributing you agree that your contribution is licensed under the [zlib license](LICENSE),
like the rest of the code; changes to the patches in `patches/` are changes to Wine and stay
under Wine's LGPL-2.1-or-later.

## Before you start

```bash
gh auth status   # GitHub authentication
```

Read [CONTEXT.md](CONTEXT.md). Without it you are likely to introduce synonyms that come back in
review.

## Sources of truth and reading order

1. **[CONTEXT.md](CONTEXT.md)**: the terms to use.
2. **[docs/adr/](docs/adr/index.md)**: accepted decisions. An ADR with status `accepted` is the
   target contract even when the code differs. Record the difference as a gap; **don't weaken an
   ADR to match the current code**.
3. **[README.md](README.md)**: what the app does today, its settings, what it changes on disk,
   how it works, how it is built, tested and released.
4. **[release-notes/README.md](release-notes/README.md)**: the release notes format.
5. **The code and its tests**: `src/som.sh` (the installer), `src/wine-wrapper.sh`,
   `src/native` (the window), `scripts/test-sandbox.sh`.

If two sources conflict, report the conflict instead of silently choosing one.

## Issues

- Every change that isn't trivial starts from an issue. Players report with the **bug report**
  or **idea** forms; planned work is written as a **task**, a precise specification.
- Titles use `Context: Actionable result`, for example
  `Engine download: Resume a download that broke off`. The issue, the pull request and the squash
  commit carry the same title.
- The area is a label, never a title prefix (see
  [docs/agents/triage-labels.md](docs/agents/triage-labels.md)).
- *Affected areas* lists only paths you have verified in the repository.
- *Verification (UAT)* is a scenario a non-technical player can click through on their Mac: each
  step is an action and, after the arrow, the expected result.

## Branches

- Never push directly to `main`. Every change goes through a pull request into `main`.
  Development builds are cut from `dev` (README, *Releasing*).
- Name the branch `<type>/<issue>-<short-description>`, in English `lower-case-kebab-case`, for
  example `fix/42-engine-download-resume`. Types: `feat`, `fix`, `perf`, `test`, `chore`,
  `docs`. A change without an issue (a typo) leaves out the number.
- One branch is one issue. If separate work turns up, open another issue.

## Commits

- Write commit messages in **English**, in the imperative (`add`, `fix`, `remove`; not `added`
  or `adding`).
- The subject follows the title form, `Context: what the commit does`, for example
  `som.sh fetch: resume the engine download where it stopped`. No emoji, no scope tags. A release
  commit starts with its version (`0.1.3: …`).
- Add a body when the why isn't obvious: the evidence, what was measured, what was not done.
  Several focused commits are fine; they are squashed on merge.

## Pull requests

- The PR title is **identical to the issue title**.
- Fill in the [template](.github/PULL_REQUEST_TEMPLATE.md), with `Closes #<issue>`.
- Keep the PR a **draft** until it meets the Definition of Done.
- Keep changes focused: don't mix a change with unrelated refactoring, which gets its own issue
  and PR. Update the README when behaviour changes.
- **Review and merge.** Every PR gets an **independent agent review** (preferably GPT-6.1-Sol)
  by an agent that didn't write the change; its verdict goes into the PR, as a comment or in the
  description. The PR is **squash-merged**, with the PR title as the commit subject, once that
  verdict has no open `Blocker` or `High` **and** the repository's checks (the Checks workflow)
  are green. The maintainer doesn't review code by hand.

## Code review

- Read the issue and its UAT before the diff.
- Classify every finding by severity. `Blocker` and `High` prevent the merge; `Medium` and
  `Low` may merge with a follow-up issue.

  | Severity | Meaning |
  |---|---|
  | `Blocker` | The pull request must not merge until it is resolved. |
  | `High` | Materially wrong behaviour, or a hard project-rule violation. |
  | `Medium` | Significant duplication, overengineering or maintainability risk. |
  | `Low` | Local cleanup that can go with related work. |

- In this project a finding is a `Blocker` by default when it can **leave Broadsword's install in
  a state Uninstall can't restore**, **put account data into a log or the Collect Logs zip**, or
  **break the update path** (the feed, its signature, *Update to X.Y.Z*). A player can't
  recover from those by installing the next version.
- A finding describes **one problem with one fix boundary**, not one affected file.
- Findings stay in the pull request as review threads; never commit a review ledger. Decisions
  that should outlive the review (accepted risks, deferred work) go into the PR description.

## Definition of Done

A change is done only when all of these hold:

- [ ] `shellcheck -S warning` and `bash -n` with macOS's `/bin/bash` 3.2 on the scripts,
      `actionlint` on the workflows, and `./build.sh` (Xcode 27) pass locally; the Checks
      workflow runs the same.
- [ ] A change to `src/som.sh`, `src/wine-wrapper.sh`, the helpers or Collect Logs passes
      `scripts/test-sandbox.sh` (it needs the official SWTOR Mac app installed, and touches only
      a sandbox). A change to updates (Sparkle, the feed, the wrapper's update check) is tested
      with `scripts/test-update.sh`.
- [ ] A bug fix has a regression check that fails without the fix: a `test-sandbox.sh` section
      where the sandbox can reach it, otherwise a manual check written in the PR.
- [ ] Install stays all-or-nothing, and Uninstall still puts Broadsword's folder back byte for
      byte apart from the game settings it copies back (`test-sandbox.sh` checks both).
- [ ] No log, `env` or Collect Logs file gains account names, e-mail addresses, the user name or
      the launcher's command line.
- [ ] A change on the game's path (the wrapper, `env`, the engine's parts, the d9mt pin) is
      nothing measurably slower: session reports of the same scene before and after
      (`session-report.sh --compare`).
- [ ] A new d9mt pin changes `scripts/build-d9mt.sh`, `prebuilt/d9mt` and the README's *Pinned
      components* together.
- [ ] The README describes the new behaviour. Terms follow `CONTEXT.md`; a new term is added in
      the same PR.
- [ ] A changed decision has an ADR in the same PR, or links an existing `accepted` ADR.
- [ ] The independent agent review (preferably GPT-6.1-Sol) has no open `Blocker` or `High`, and
      its verdict is in the PR.
- [ ] The issue's UAT scenario has been clicked through and ticked off in the issue.

## Never do these things

- Push directly to `main`.
- Include game files, Broadsword's launcher or Wine, or anything from your SWTOR account
  (account names, logs with the launcher's command line) in an issue or a PR.
- Test against the real install when the sandbox can do it: use `SWTOR_ON_MAC_ROOT` and
  `SWTOR_ON_MAC_DRY_RUN` (README, *Testing without touching the system*).
- Change anything in Broadsword's install beyond what the README's *What it changes* lists (the
  two preloaders and `bin-real/`; Uninstall's copy of the game settings back).
- Bundle or mirror the Wine engine (ADR-0002).
- Put a development build into the update feed or a regular release.
- Commit signing material: the Developer ID, notarization credentials or Sparkle's EdDSA key.
- Tell players to contact Broadsword or SWTOR customer support about SWTOR on Mac.
- Add a dependency without the maintainer's approval.
- Change `CONTEXT.md` or an ADR incidentally during unrelated work.
