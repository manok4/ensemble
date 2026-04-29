# Sample repo — State 2d (both maps present)

Has `package.json` + `src/` + pre-existing `AGENTS.md` AND `CLAUDE.md` with custom team content.

## Expected detection

- State: **state-2**
- Sub-variant: **2d** (both maps present)

## Expected `/en-setup` behavior

1. Detect 2d.
2. Create `docs/` skeleton.
3. **Append-merge** `AGENTS.md`: keep existing content; append Ensemble pointer-map section only if not present.
4. **Append-merge** `CLAUDE.md`: keep existing content; **prepend** the AGENTS.md cross-reference line if missing; append Claude-specific Ensemble section only if not present.
5. **Never** overwrite existing user content. Always idempotent.
