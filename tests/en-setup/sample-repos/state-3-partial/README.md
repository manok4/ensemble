# Sample repo — State 3 (partial)

A nearly-fully-bootstrapped Ensemble project with one piece missing: `docs/learnings/log.md`. Modeled after foundation §20.4's "state-3-partial" fixture.

## Expected detection

- State: **state-3** (foundation + learnings/ both exist, so State 3 still applies)

## Expected `/en-setup` (diagnostic mode) behavior

1. Detect state-3.
2. Run `scripts/check-health`.
3. Report 🟡 on `docs/learnings/log.md present`.
4. Offer to repair (create the empty seed).
5. Other checks pass 🟢.
