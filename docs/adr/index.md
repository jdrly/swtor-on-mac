# Architecture Decision Records

An ADR records a decision or a proposed direction. **Its existence does not prove that the
behaviour is implemented.** When the code and an ADR differ, the code and its checks describe
what runs; the ADR stays the target and the difference is recorded as a gap.

## Statuses

| Status | Meaning |
|---|---|
| `proposed` | Awaiting discussion; **not an implementation specification**. |
| `accepted` | The valid target contract. |
| `superseded by ADR-NNNN` | Historical context; follow its successor. |
| `deprecated` | Don't use this approach in new work. |

## When to write an ADR

Only when there were real alternatives with consequences that matter. Ask: “Will someone want
to know a year from now why this wasn't done differently?” Tool choices and style rules belong in
`CONTRIBUTING.md`, not in an ADR.

## Format

`NNNN-english-slug.md`, in English, started from [0000-template.md](0000-template.md). Never reuse
a number; keep superseded records and change their status. Write only what a source shows, and
put what isn't decided under *Open questions*.

## Records

This table is the status source of truth. Update both it and the ADR's frontmatter.

| # | Decision | Status |
|---|---|---|
| [0001](0001-one-engine-crossover-26-3.md) | The game runs on one Wine engine: CrossOver 26.3 with Wine 11, the engine SWGL on Mac uses | `accepted` |
| [0002](0002-engine-downloaded-not-redistributed.md) | The engine is downloaded from its official source at install time, never bundled or mirrored (no mirror for licensing reasons) | `accepted` |
| [0003](0003-hook-through-the-preloaders.md) | A wrapper in the preloaders' place; all-or-nothing Install, byte-for-byte Uninstall | `accepted` |
| [0004](0004-releases-in-two-halves.md) | Releases built by CI and finished on the maintainer's Mac; development builds are pre-releases only | `accepted` |
