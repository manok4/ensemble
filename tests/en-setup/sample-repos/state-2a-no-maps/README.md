# Sample repo — State 2a (existing project, no maps)

Has `package.json` + `src/` (so source-code-present heuristic fires) but no `AGENTS.md`, no `CLAUDE.md`, no `docs/foundation.md`, no `docs/learnings/`.

## Expected detection

- State: **state-2**
- Sub-variant: **2a** (neither AGENTS.md nor CLAUDE.md present)

## Expected `/en-setup` behavior

1. Detect 2a.
2. Create `docs/{plans/active,plans/completed,learnings/{bugs,patterns,decisions,sources},references,generated,designs}/`.
3. Seed `docs/learnings/{index.md,log.md}` and `docs/generated/{plan-index.md,learning-index.md}`.
4. **Generate** `AGENTS.md` from template.
5. **Generate** `CLAUDE.md` from template (with the AGENTS.md cross-reference line).
6. Add `.ensemble/config.local.example.yaml`.
7. Add `.gitignore` entries (or create `.gitignore` if missing).
8. Install `.github/workflows/en-garden.yml`.
9. Recommend `/en-foundation --retrofit` or `/en-plan` next.
