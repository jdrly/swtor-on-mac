# Contributing

Thanks for helping with SWTOR on Mac.

- **Bugs:** open a [bug report](https://github.com/jdrly/swtor-on-mac/issues/new/choose) with
  the Collect Logs zip (SWTOR on Mac > Collect Logs…), or contact Pharaphobia on Discord.
- **Pull requests** are welcome. For anything larger than a small fix, open an issue first so
  we can agree on the approach. Keep changes focused, and update the README when behaviour
  changes.
- **Before you send a PR:** `shellcheck -S warning` and `bash -n` (macOS's bash 3.2) on the
  scripts, `actionlint` on the workflows, and `./build.sh` (Xcode 27) must pass; the Checks
  workflow runs the same. If you change `src/som.sh`, `src/wine-wrapper.sh`, the helpers or
  Collect Logs, run `scripts/test-sandbox.sh` (it needs the official SWTOR Mac app installed,
  and touches only a sandbox).
- **Never** include game files, Broadsword's launcher or Wine, or anything from your SWTOR
  account (account names, logs with the launcher's command line) in an issue or a PR.
- By contributing you agree that your contribution is licensed under the
  [zlib license](LICENSE), like the rest of the code.
