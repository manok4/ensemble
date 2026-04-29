# Sample repo — State 3 (fully set up)

Has `docs/foundation.md` AND `docs/learnings/` plus all required artifacts: `AGENTS.md`, `CLAUDE.md`, `docs/architecture.md`, the plans/ and learnings/ directories, the index/log files, the generated/ stubs.

## Expected detection

- State: **state-3** (fully set up)

## Expected `/en-setup` behavior

1. Diagnostic mode (per `references/setup-state-detection.md` State 3).
2. Run `scripts/check-health` against the project.
3. Report status with 🟢/🟡/🔴 per check.
4. Offer repairs for any 🟡/🔴.
5. **Don't** create or modify artifacts (other than the optional repairs the user accepts).
