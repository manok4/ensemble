# Post-build protocol (the `/en-build` post-build phase)

The mechanics of the post-build phase: what to write once the suite is green,
the two trailer schemas, the shape of the evidence audit's report, and the
learning checkpoint's own steps. `SKILL.md` keeps the flow and the gates that
stop a build; this file is read when the build reaches the post-build phase.

It is a reference rather than skill body because of what it costs to carry: a
build long enough to compact re-injects every invoked skill in full on every
compaction, and 9KB of protocol that matters once, at the end, was
being paid for from the first unit onwards. The rules did not change when they moved here.

## Once the suite passes

**On success, write a verification receipt.** `bash "$SKILL_DIR/scripts/ensemble-verification-receipt" write --check full_suite=passed --check lint=passed --check typecheck=passed --base origin/<default-branch> --by en-build`, plus a `--dep <path>` for each lockfile the project has, **plus one `--check <suite>=passed` per named test command in `AGENTS.md`'s Test line** (a project that declares `test`, `test:db` and `test:e2e` records `unit`, `db` and `e2e`). `full_suite` is the conjunction and is what `/en-ship` asks for; the per-suite names let a later layer ask for exactly the suite it needs and get `check-not-recorded` for the rest. This is the layer that just paid for the expensive run, so it is the layer that records it: `/en-ship` and a project's pre-push hook can then skip what this proved, instead of re-running it minutes later on the identical tree.

**Only on a passing suite, and never fatal.** A receipt is evidence something succeeded, not a log that it ran, so a failed suite leaves none behind. If the write itself fails, warn and carry on — the receipt is an optimisation, and a build that fails because it could not record an optimisation has turned a saving into a liability.

**Do not interrupt a running suite.** Bound it with the project's own timeout if it has one, and otherwise let it finish. A suite that looks stalled is reported, not killed and retried: in the FR78 build eight of twelve launches were interrupted before producing a result, which is where most of its 2h48m of suite time went. If a run genuinely exceeds what the project expects, say so with the elapsed time and let the user decide — a suite slow enough to look hung is a finding about the project, not a reason to guess again.

**Report the elapsed time in the summary.** A full suite over ~10 minutes is worth the user knowing about; sharding it is their call, and they cannot make it if the number is never surfaced.

## The two trailers

**Trailer schemas.** These two are the branch's whole evidence record, so they live here rather than in a reference:

- **`review-verdict:`** — one per post-build review commit. Required keys: `verdict` (`approve`/`revise`/`reject`), `reviewer` (`cross-agent` normally; `single-agent-fallback` / `en-review-host-fallback` when the cross-agent peer was unavailable — the value IS the recorded reason a fallback was used, and it records which fallback), `mode`, `units_covered` (JSON array of **every U-ID built this run**), `findings_count`. A unit counts as reviewed when its U-ID appears in some `review-verdict.units_covered` on the branch. A fallback `reviewer` maps to `branch_review_pass: fallback_completed` — valid, because the field records why the cross-agent peer was not used.
- **`simplify-verdict:`** (EN07) — emitted on the **same** commit, so the `/en-simplify` pass is auditable rather than prose. Required keys: `outcome` (`completed` / `not_applicable` / `failed`), `reason` (non-empty and REQUIRED when `not_applicable` or `failed`: `docs-only`, `trivial:<10-lines`, `--no-simplify`, or the gate regression that reverted it), `findings_count`, `units_covered`. **`--no-simplify` records `{"outcome":"not_applicable","reason":"--no-simplify",...}` explicitly — a visible, recorded opt-out, never silence.** A **missing** `simplify-verdict:` trailer is NOT a legitimate skip; the audit treats it as `missing` and fails. **`--review none`** likewise records the branch review as a loud, recorded skip (`branch_review_pass: missing`, and the audit fails) — never a silent pass.

```
review-verdict: {"verdict":"approve","reviewer":"cross-agent","mode":"headless","units_covered":["U1","U2","U3"],"findings_count":1}
simplify-verdict: {"outcome":"completed","reason":"","findings_count":2,"units_covered":["U1","U2","U3"]}
```

`ensemble-verify-peer-evidence --branch-coverage <range> --require-simplify` derives `simplify_pass` and `branch_review_pass` from these and fails when either is `missing`/`failed`. Trailers rather than sidecar files because `git interpret-trailers --parse` and `git log --grep` are stable and scriptable.

## What the evidence audit reports

```
Evidence audit — FR07-auth-rotation (5 units)
  ✓ U1 — branch-level review-verdict (approve, covered)
  ✓ U2 — branch-level review-verdict (approve, covered)
  ✓ U3 — branch-level review-verdict (revise→applied, covered)
  ✓ U4 — branch-level review-verdict (revise→applied, covered)  [gated:true]
  ✓ U5 — branch-level review-verdict (approve, covered)

simplify_pass: completed
branch_review_pass: completed
Audit verdict: ok (5/5 units covered by the branch-level review; simplify + review gated)
```

**Each gate line carries its reason when it is anything but `completed`** — `simplify_pass: not_applicable (build config: simplifier off)` reads as loudly as `(--no-simplify)`. A policy set once in `.ensemble/config.local.yaml` and forgotten must be as visible here as a flag typed this morning; that is the whole reason it is safe to move standing policy out of the flag surface.

**The two gate lines are mandatory in every build summary** (the human-visible echo of the durable `simplify-verdict:` / `review-verdict:` trailers). A `simplify_pass`/`branch_review_pass` of `missing` or `failed` makes the audit verdict `failed` even when every U-ID is covered - a skipped simplify or an unrecorded review is a build defect, not a clean finish.

A unit not in `covered_units`, or a `missing`/`failed` gate line, makes the audit verdict `failed`; the same table then marks the uncovered units `✗` and names the gate that failed (`simplify_pass: missing` reads "no simplify-verdict trailer on the branch"). The audit surfaces, but does NOT auto-revert — the user decides. If the audit fails **for any reason** (uncovered unit, or a `missing`/`failed` `simplify_pass` / `branch_review_pass`), the suggested next step changes from `/en-review → /en-qa → /en-ship` to `/en-review --peer <sha>` on the failing units, then re-audit - the success path is **blocked** until the audit passes.

## The learning checkpoint, step by step

The checkpoint fires at the very end of the post-build phase, after the audit,
and emits one `learning_checkpoint:` outcome line in the build summary.

1. **Deferral guard.** **Defer** the checkpoint whenever the peer-evidence audit failed (the end-of-build audit at step 10.6) - do not fire it on a build with missing evidence. This covers an uncovered unit **and (EN07) a `simplify_pass` or `branch_review_pass` of `missing`/`failed`** - a skipped `/en-simplify` or an unrun/unrecorded branch review blocks the learning checkpoint exactly as a missing review-verdict does. Surface a one-line note that the learning checkpoint is deferred (name which gate failed) and skip the rest. This emits **no** `learning_checkpoint:` outcome value - the checkpoint did not run, so none of the four canonical outcomes applies.
2. **CI short-circuit.** If `CI=true`, record `learning_checkpoint: ci_environment` in the build summary; skip the prompt (no interactive prompt in CI).
3. **Determine the capture baseline.** Read `docs/learnings/log.md`; find the latest `## [YYYY-MM-DD] capture | <subject> | <head-sha>` entry. If a `<head-sha>` is present, baseline = that SHA (`git log <sha>..HEAD`). Legacy entry without a SHA → one-line imprecise-baseline notice + `git log --since=<date>` fallback. No capture entries at all → baseline = `git merge-base HEAD <default-branch>` (since branch creation).
4. **Idempotency check.** If the scope is zero commits since the last capture, record `learning_checkpoint: up_to_date` and skip the prompt silently.
5. **Surface the checkpoint prompt** (structured, not a soft prompt):
   ```
   Learning checkpoint
   ───────────────────
   <N> commits since last /en-learn capture (<baseline date or "branch creation">).
   Diff: <X> files changed, <Y> lines.
   Recent commits touch: <comma-separated areas from changed files>

   Worth filing learnings from this build? (yes / skip / details)
   ```
6. **Handle response.** `yes` → invoke `/en-learn capture`; record `learning_checkpoint: captured (<N> learnings)`. `skip` → record `learning_checkpoint: intentionally_skipped` (auditable). `details` → print the commit list + per-area summary; re-prompt.
7. **Policy override.** `build.learning_checkpoint: false` skips the whole step (records `learning_checkpoint: intentionally_skipped (--no-learning-checkpoint flag)`).

The four canonical outcome values are `captured (N learnings)` /
`intentionally_skipped` / `up_to_date` / `ci_environment` (never the bare word
`skipped`). It fires at the `/en-learn` hand-off, after the evidence audit and **outside**
the inter-unit autonomy-contract window, so it is a legitimate terminal
checkpoint rather than an inserted inter-unit pause.
