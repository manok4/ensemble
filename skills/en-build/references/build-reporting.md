# Build reporting (`/en-build`)

The two report formats: one line per unit as it commits, and the build summary
at the end. `SKILL.md` keeps the lines that are mandatory and the rule each one
carries; this file is the shape they take.

## Per-unit progress report

After each unit commits, surface a one-line summary, and append the same record to `/tmp/ensemble/en-build/<run-id>/ledger.json` (unit, outcome, commit, tests, notes). The final summary and the step 10.6 audit table are derived from that file: a build runs long enough for the context to be compacted, and `--from U<N>` recovers git state but not what was reported.

```
✓ U3 — feat(auth): wrap rotateRefreshToken in singleFlight  [P2 / risk: medium]
  Tests: 7 added, 7 passing | Commit: a3f1b9c (trailer: phase: P2)
```

Simplify and review results appear once, in the final summary: they run over the branch, not per unit.

## Final summary

After all units complete:

```
Build summary — FR07-auth-rotation (5 units)

✓ U1: Add singleFlight helper (feat: 12 files, 4 tests)
✓ U2: Wire Redis connection (feat: 3 files)
✓ U3: Wrap rotateRefreshToken (feat: 2 files, 3 tests)
✓ U4: Migration for refresh_token_rotated_at (feat: 1 file) [gated]
✓ U5: Update test coverage (test: 6 files, 12 tests)

Full suite: 247 passing, 0 failing.
Lint: clean.
Typecheck: clean.

Code-simplifier: branch diff; 7 file changes.
Review: --cross, cross-agent (codex). Found 11 — P0:1 P1:3 P2:5 P3:2. Addressed 6 (1 P0, 3 P1, 2 P2), deferred 4 to tech-debt-tracker (TD11-TD14), disagreed 1.
simplify_pass: completed
branch_review_pass: completed
learning_checkpoint: captured (2 learnings)
metrics: <path> (<summary>)
```

**The `Review:` line is mandatory and carries both halves.** *Found*, broken down by severity, and *addressed*, broken down the same way — a review that found eleven things and addressed six is a different outcome from one that found six and addressed six, and a line reporting only the second is unreadable as either. Deferred findings name their TD IDs so the paper trail is followable from the summary; disagreed ones are counted so a silent drop is visible as a number. Where the review was skipped or fell back, this line says which and why, in place of the counts.

The `metrics:` line is the run ledger `references/run-metrics.md` describes, with the helper's own summary in the parentheses (`6 units, 3 phases, 1 suite runs`). When metrics were disabled it reads `metrics: disabled (<reason>)`, so a missing file is never mistaken for a run that recorded nothing.

The `simplify_pass:` and `branch_review_pass:` lines are **mandatory** (EN07) - they echo the durable `simplify-verdict:` / `review-verdict:` trailers so a skipped simplify or an unrecorded review can never read as a clean finish. A `missing`/`failed` value on either blocks the learning checkpoint and the ship hand-off.
