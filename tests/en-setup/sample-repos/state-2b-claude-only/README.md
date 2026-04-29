# Sample repo — State 2b (CLAUDE.md only, no AGENTS.md)

Has `package.json` + `src/` + a pre-existing `CLAUDE.md` (with custom user content). No `AGENTS.md`, no `docs/`.

## Expected detection

- State: **state-2**
- Sub-variant: **2b** (CLAUDE.md exists, AGENTS.md does not)

## Expected `/en-setup` behavior

1. Detect 2b.
2. Create `docs/` skeleton (per State-2 step 2).
3. Seed `docs/learnings/{index.md,log.md}` + `docs/generated/{plan-index,learning-index}.md`.
4. **Generate** `AGENTS.md` from template (no existing file).
5. **Append-merge** `CLAUDE.md`: keep the existing user content; **prepend** the AGENTS.md cross-reference line if missing; **append** an "Ensemble — Claude Code notes" section only if not already present. Never modify existing user content.
6. Standard config + workflow + gitignore steps.
