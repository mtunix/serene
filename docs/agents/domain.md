# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **The glossary**: the section "Words used in the code and these pages" in `docs/README.md`. It is Serene's
  glossary; there is no `GLOSSARY.md` at the root, and terms resolved later go into that section, not into a new
  file.
- **`docs/adr/`**: read ADRs that touch the area you're about to work in.
- **The area docs**: `CLAUDE.md` says which page under `docs/` to read for each file touched. Those pages are the
  authority on how Serene works and why.

If `docs/adr/` doesn't exist, **proceed silently**. Don't flag its absence; don't suggest creating it upfront. The
`/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates it lazily
when a decision actually gets resolved.

## File structure

Single-context repo:

```
/
├── CLAUDE.md
├── *.lua, Serene.toc
└── docs/
    ├── README.md          ← the glossary ("Words used in the code and these pages")
    ├── adr/               ← decisions, created when the first one is written
    │   └── 0001-....md
    └── <area>.md
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use
the term as defined in the glossary. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project
doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because…_
