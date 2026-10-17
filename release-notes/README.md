# Release notes

`<version>.md` here are the notes of each release. `scripts/release.sh` puts them, unchanged,
into the GitHub release and the update window (Sparkle), and [swonmac.com](https://swonmac.com)
shows them from the GitHub release. SWGL on Mac's notes use the same format, so both apps look
the same on the site.

```markdown
## SWTOR on Mac 0.0.7

One sentence that says what this release is about.

### First change, as a short headline
What changed and what it means for the player, in a short paragraph. Technical references
go in inline code, e.g. d9mt `68c7190`.

### Second change
- Bullets are fine when a change has several parts.
- Keep each bullet to one or two sentences.

### After updating
Open SWTOR on Mac and click *Update to 0.0.7* in the window (with the game closed).

### Support
SWTOR on Mac is an unofficial project, not made, endorsed or supported by Broadsword Games, EA,
Lucasfilm or Disney, and you use it at your own risk. Please send questions and bug reports to
Pharaphobia on Discord or as a [GitHub issue](https://github.com/jdrly/swtor-on-mac/issues),
never to Broadsword or SWTOR customer support.
```

| Part | Required | On swonmac.com |
|---|---|---|
| `## SWTOR on Mac <version>` | yes, the first line | Left out; the site shows its own title, version and date |
| Summary | yes, the first paragraph after the title, one sentence | The release's one-liner, also when it's folded away |
| `### <change>` | at least one | One block per change |
| `### After updating` | only when the player has to do something | A note before Support |
| `### Support` | yes, last, with the wording above | As is |

- No other `##` headings and nothing below `###`: the site and the update window style `###`
  as a change and nothing deeper.
- Inline code (`` `68c7190` ``) shows as a chip on the site. Code blocks only in development
  builds; the update window doesn't format them.
- Development builds (`<version>-dev.N`) use the same structure, with `(development build)`
  after the version in the title. The site leaves them out.
- The Release workflow stops when the title or the summary is missing.
