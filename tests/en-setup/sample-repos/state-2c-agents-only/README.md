# Sample repo — State 2c (AGENTS.md only, no CLAUDE.md)

Has `package.json` + `src/` + a pre-existing `AGENTS.md` with custom team content. No `CLAUDE.md`, no `docs/`.

## Expected detection

- State: **state-2**
- Sub-variant: **2c** (AGENTS.md exists, CLAUDE.md does not)

## Expected `/en-setup` behavior

1. Detect 2c.
2. Create `docs/` skeleton.
3. **Append-merge** `AGENTS.md`: keep existing team content; append "Ensemble pointer map" section only if not already present.
4. **Generate** `CLAUDE.md` from template (with the AGENTS.md cross-reference line as the first non-frontmatter line).
5. Standard config + workflow + gitignore steps.
