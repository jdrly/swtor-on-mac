# SWTOR on Mac agent guidance

Work one prepared issue at a time, within its scope and acceptance criteria, and take the next
one only after this one meets the Definition of Done in [`CONTRIBUTING.md`](CONTRIBUTING.md).

The documentation is the source of truth and should answer scope and design questions:
[`CONTEXT.md`](CONTEXT.md), the decisions in [`docs/adr/index.md`](docs/adr/index.md) and the
[README](README.md) with its pages in [`docs/`](docs) (behaviour, what the app changes on disk,
how it works, building, testing, releasing). Look the answer up there before asking or choosing an approach of your own.

- Test the installer in a sandbox (`SWTOR_ON_MAC_ROOT`, `SWTOR_ON_MAC_DRY_RUN`,
  `scripts/test-sandbox.sh`), never against the real install, and never start the game or a Wine
  window on the maintainer's screen while they may be playing.
- The scripts run under macOS's `/bin/bash` 3.2: no bash 4 features.
- Work on a branch and open a pull request into `main`. Never push to `main` or `dev`, tag, or
  create releases, issues or labels without the maintainer's approval: this repository is public.
- Never put game files, Broadsword's launcher or Wine, account data or signing material into the
  repository, an issue or a pull request.

## Agent skills

### Issue tracker

GitHub issues in `jdrly/swtor-on-mac`. See [`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md).

### Triage labels

Vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`, plus
type and `area:` labels. See [`docs/agents/triage-labels.md`](docs/agents/triage-labels.md).

### Domain docs

Single context: root `CONTEXT.md` plus `docs/adr/`. See [`docs/agents/domain.md`](docs/agents/domain.md).
