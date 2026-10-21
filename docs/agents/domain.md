# Domain docs

How agents and engineering skills use this repository's domain documentation.

## Before exploring, read these

- **[`CONTEXT.md`](../../CONTEXT.md)** at the repository root: the glossary.
- **[`docs/adr/`](../adr/index.md)**: the ADRs that touch the area you are about to work in. The
  index is the status source of truth; a `proposed` ADR is not an implementation specification.

## Use the glossary's vocabulary

When your output names a domain concept (an issue title, a hypothesis, a test name, a log line,
a commit), use the term as `CONTEXT.md` defines it. Don't drift to the synonyms it lists under
_Avoid_.

If the concept you need isn't in the glossary, that is a signal: either you are inventing
language the project doesn't use (reconsider), or there is a real gap. Add the term in the same
pull request and say so in its description.

## Flag ADR conflicts

If your output contradicts an `accepted` ADR, say so explicitly instead of silently overriding it:

> _Contradicts ADR-0002 (…), but worth reopening because…_

## Mark what is open

Write down only what the code, the README, a test or a documented measurement shows. When
something is believed but not verified, say so (“open”, “not measured yet”) rather than stating
it as fact.
