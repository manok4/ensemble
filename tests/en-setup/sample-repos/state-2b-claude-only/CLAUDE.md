# my-project — Claude Code notes

A pre-existing CLAUDE.md with the team's custom content. `/en-setup` must
**not** overwrite this; it should generate `AGENTS.md` from the template and
append-merge a Claude-Code-specific Ensemble section to this file (only if
not already present), prepending the AGENTS.md cross-reference line.

## Build commands

- `npm run dev` for local dev.
- `npm run test` for the suite.

## Conventions

- camelCase function names.
- Tests live next to source (`<file>.test.ts`).
