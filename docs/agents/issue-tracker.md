# Issue tracker: GitHub

Issues and specifications for this repository live as GitHub issues in `jdrly/swtor-on-mac`. There is no
other tracker. Use the `gh` CLI for every GitHub operation, and follow the issue templates in
[`.github/ISSUE_TEMPLATE/`](../../.github/ISSUE_TEMPLATE) and the title rule in
[`CONTRIBUTING.md`](../../CONTRIBUTING.md#issues).

## Conventions

- **Create an issue**: `gh issue create --repo jdrly/swtor-on-mac --title "Context: Actionable result"
  --body-file <file>`, with a body that follows the matching template (`task.yml` for work,
  `bug_report.yml` for a bug). Show the draft to the maintainer and create it only after an
  explicit approval: this repository is public.
- **Read an issue**: `gh issue view <number> --repo jdrly/swtor-on-mac --comments`, including its labels.
- **List issues**: `gh issue list --repo jdrly/swtor-on-mac --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'`
  with `--label` and `--state` filters as needed.
- **Comment on an issue**: `gh issue comment <number> --repo jdrly/swtor-on-mac --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --repo jdrly/swtor-on-mac --add-label "..."` /
  `--remove-label "..."`
- **Close**: `gh issue close <number> --repo jdrly/swtor-on-mac --comment "..."`. A merged pull request
  with `Closes #<number>` closes its issue by itself.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repository treats external pull
requests as feature requests; `/triage` reads this flag.)_

GitHub shares one number space between issues and pull requests, so a bare `#42` may be either:
resolve it with `gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue in `jdrly/swtor-on-mac` as above, after showing the draft and getting approval.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --repo jdrly/swtor-on-mac --comments`.
