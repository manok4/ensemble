---
title: /en-ship plan-completion checkpoint + /en-learn skip-path unbundle
status: spec
owner: mano
related:
  - skills/en-ship/SKILL.md
  - skills/en-learn/SKILL.md
  - skills/en-build/SKILL.md (read-only)
  - docs/foundation.md (decision entry to be added)
created: 2026-05-14
---

# Spec: `/en-ship` plan-completion checkpoint + `/en-learn` skip-path unbundle

## Context

Field-observed bug: implementation plans are getting stuck at `status: in_progress` after the build and QA finish. The user expected the plan to transition to `status: completed` at some point in the lifecycle — but it doesn't.

### Lifecycle as designed

| Status | Who flips it | Where |
|---|---|---|
| `draft → open` | `/en-plan` finalize loop on `approve` | en-plan step 14 |
| `open → in_progress` | `/en-build` | en-build step 4b |
| `in_progress → completed` + move file from `active/` to `completed/` + set `shipped: <date>` | `/en-learn capture` step 11 | en-learn SKILL.md line 50 |

The flip from `in_progress → completed` is genuinely there in the spec. It's the **last step of `/en-learn capture`** and it bundles three things:

- Flip `status: in_progress → completed`
- Set `shipped: <today>`
- `git mv` the file from `docs/plans/active/` to `docs/plans/completed/`
- Replace plan-tense ("we will") with documentation-tense ("we did")
- Note any deviations from the plan

### Three stacking failure modes

The flip doesn't happen reliably because:

**1. `/en-learn` is soft-auto-invoked.** Both `/en-build` (line 220) and `/en-qa` (line 72) call `/en-learn` as a soft prompt at end-of-flow: *"Build complete. Capture learnings? (yes / skip)"*. If the user says `skip` (or the prompt gets dropped under context pressure, which is a known failure mode for end-of-long-sequence soft prompts), `/en-learn` never runs and step 11 never fires.

**2. The flip is bundled with "actually captured a learning."** Step 11 is the LAST step of `/en-learn capture`'s flow — it runs only when a learning was actually filed. If the user opens `/en-learn` and says "skip — no learnings worth capturing," step 11 doesn't fire either. Lifecycle bookkeeping is tied to wiki bookkeeping in a way that doesn't reflect their actual separability.

**3. `/en-ship` doesn't touch plan status at all.** A grep of `skills/en-ship/SKILL.md` finds zero mentions of `status`, `in_progress`, `completed`, or `plan_id`. So even when `/en-ship` runs cleanly and the PR opens, no flip happens — there's no backstop.

Net result: unless `/en-learn capture` runs through to step 11 successfully (which requires both invocation AND a non-skip capture decision), the plan is orphaned at `in_progress`. The observed behavior matches exactly.

### Why this matters

A plan at `status: in_progress` indefinitely:

- Pollutes `docs/plans/active/` — work that's actually done sits next to work that's not.
- Breaks `/en-sweep`'s scheduled health checks — sweep can't tell whether `EN07` is genuinely active or just orphaned.
- Confuses `/en-plan`'s auto-resume heuristic — a future invocation might see the in-progress plan and offer to resume it when the user just wants to start a new feature.
- Makes status-based reporting (e.g. "what's open right now?") unreliable.

## Outcome enum (canonical)

`/en-ship`'s preflight gets a new `plan_completion_checkpoint:` field in its report. Five terminal values + one non-terminal response option:

| Outcome | Terminal? | Action |
|---|---|---|
| `completed_and_moved` | yes | User picked `y` AND build is verifiably complete; status flipped, `shipped:` set, file `git mv`-d to `completed/`. |
| `skipped_by_user` | yes | User picked `skip`; status left at `in_progress`. Auditable record of explicit skip. |
| `up_to_date` | yes | Status was already `completed` before this run (the file's already in `completed/`); silent pass-through. |
| `not_applicable` | yes | Couldn't derive a plan_id from the current branch (e.g. shipping from main with no plan context); checkpoint silently skipped. |
| `incomplete_build` | yes | Refused to flip — some plan-units lack peer-evidence trailers (per `bin/ensemble-verify-peer-evidence`). Surfaced the missing units; left at `in_progress`. PR still opens — this is informational, not blocking. |
| `details` | **no** | Diagnostic: list per-unit completion state, plan-branch detection result, all values defined above. Re-prompts after surfacing. |

Every section of this spec, the foundation update, the SKILL.md changes, and the drift-guard tests MUST use these exact strings. Bare words `completed`, `done`, `skipped`, `flipped` MUST NOT appear as report values — they'd drift the contract.

## Resolved decisions

1. **Plan completion checkpoint lives in `/en-ship`'s preflight as a NEW step.** Not `/en-qa` (verification ≠ shipping; QA can pass and the user still abandons the work). Not implicit in `/en-build` (build can be done locally without the work shipping). `/en-ship` is the actual chokepoint where code leaves the local environment — by the time `/en-ship` opens a PR or pushes, the work is committed to going out.

2. **Two-tier fix: backstop in `/en-ship` + primary-path unbundle in `/en-learn`.** Defense in depth.
   - **Primary path:** `/en-learn capture` step 11 continues to do the move-and-flip when a learning IS captured. Unchanged.
   - **NEW skip-path in `/en-learn`:** when the user picks "skip — no learning to capture," `/en-learn` STILL flips status and moves the file. Documentation-tense updates only happen on actual capture; the lifecycle flip happens regardless.
   - **Backstop in `/en-ship`:** new preflight step that catches the case where `/en-learn` wasn't invoked at all (dropped prompt, user fled to ship directly, etc.).

3. **Plan-branch detection: derive `plan_id` from the current git branch name.** Per PR #19 (default-branch auto-branch), `/en-plan` creates `<plan_id>-<slug>` branches. The checkpoint reads the current branch name, extracts `<plan_id>` via regex match against the foundation's `plan_id_prefix:` (e.g. `EN`, `FR`), and looks up the corresponding plan file. If no plan_id derivable → outcome `not_applicable`; checkpoint silently skips.

4. **"Build verifiably complete" definition: all plan-units have peer-evidence trailers.** Per the peer-evidence contract from PR #14, every unit commit on the plan branch must have at least one of `peer-verdict:`, `peer-resolution:`, or `peer-skipped:` git-trailer. The checkpoint runs `bin/ensemble-verify-peer-evidence <commit>` for each commit-on-branch since branch creation, aggregates by U-ID. If every U-ID in the plan has ≥1 evidence trailer → build is complete; flip allowed. If any U-ID has zero → outcome `incomplete_build`; refuse to flip but PR still opens (informational, not blocking).

5. **`/en-ship` doesn't block on `incomplete_build`.** The checkpoint surfaces the gap and continues. The user might be shipping intentionally with a subset of units (e.g. mid-build manual PR). Plan-status correctness is important but not a ship-blocker.

6. **No new flags for v1.** Existing `/en-ship` flags stay unchanged. If the user wants to skip the checkpoint entirely (rare), they can simply pick `skip` at the prompt.

## Change 1 — `/en-ship` SKILL.md: new "Plan completion checkpoint" preflight step

**File:** `skills/en-ship/SKILL.md`.

**Placement:** new step inserted in the Process section, **after step 3 (Pre-flight: git status / merge conflict / etc.) but before step 4 (Lint + typecheck + tests on changed files)**. The checkpoint is informational and doesn't gate ship; placing it early in preflight gives the user time to address it before the longer-running checks.

Numbering shifts: existing step 4 → 5, step 5 → 6, etc. Drift-guard test asserts the new step's heading appears between "Pre-flight" and "Lint + typecheck + targeted tests."

**Content:**

> **4. Plan completion checkpoint.** Before running the longer preflight checks, surface the plan's completion state. The checkpoint is informational (does NOT gate ship); it catches plans orphaned at `status: in_progress` that should have been flipped to `completed` by `/en-learn capture` step 11 but weren't (dropped soft prompt, skipped capture, etc.).
>
> 1. **Plan-branch detection.** Read the current git branch name. Extract `<plan_id>` via regex against the foundation's `plan_id_prefix:` (e.g. `EN`, `FR`) — branch name pattern is `<plan_id>-<slug>` per PR #19. If no plan_id derivable from the branch → record `plan_completion_checkpoint: not_applicable`; skip silently to step 5.
>
> 2. **Plan file lookup.** Look for `docs/plans/active/<plan_id>-*.md`. If found, read frontmatter; otherwise check `docs/plans/completed/<plan_id>-*.md` (already done; outcome `up_to_date`). If neither exists → outcome `not_applicable`; skip silently to step 5.
>
> 3. **Status inspection.**
>    - If status is `completed` → record `plan_completion_checkpoint: up_to_date`; skip silently to step 5.
>    - If status is `in_progress` → continue to completeness check.
>    - If status is `open` or `draft` → record `plan_completion_checkpoint: not_applicable` (the plan isn't mid-build); surface a one-line notice; skip to step 5.
>
> 4. **Build completeness check.** For each unit U-ID in the plan, run `$ENSEMBLE_ROOT/bin/ensemble-verify-peer-evidence` on every commit since the plan branch's creation. Aggregate evidence trailers (`peer-verdict:`, `peer-resolution:`, `peer-skipped:`) by U-ID. If every U-ID has ≥1 trailer → build complete; continue to step 4.5. If any U-ID has zero → outcome `incomplete_build`; list the missing U-IDs; surface a one-line notice; skip to step 5 (PR still opens).
>
> 5. **Surface the checkpoint prompt** (structured):
>    ```
>    Plan completion checkpoint
>    ──────────────────────────
>    Plan `<plan_id>-<slug>` is still at `status: in_progress`.
>    All <N> units have peer-evidence trailers; the build is
>    verifiably complete.
>
>    Mark the plan as completed and move to docs/plans/completed/?
>      y       (recommended) — flip status, set shipped: <today>, git mv to completed/
>      skip                — leave at in_progress; you flip manually later
>      details              — show per-unit completion state
>    ```
>
> 6. **Handle response.**
>    - `y` (default): perform the lifecycle flip — set `status: completed`, set `shipped: <today>`, `git mv docs/plans/active/<plan-file>.md docs/plans/completed/<plan-file>.md`, stage. The flip becomes part of the same commit `/en-ship` will create at step 9 (next step). Record `plan_completion_checkpoint: completed_and_moved`.
>    - `skip`: record `plan_completion_checkpoint: skipped_by_user` with an audit-friendly note ("user explicit skip; plan stays at in_progress"). Continue to next step.
>    - `details`: show per-unit completion state (U-ID, evidence trailer count, U-ID's risk classification). Show plan-branch detection source. Re-prompt; loop until terminal option.
>
> 7. **Idempotency.** Re-running `/en-ship` on the same branch after the checkpoint flipped status to `completed`:
>    - Status inspection finds `completed` → outcome `up_to_date`; checkpoint silently passes.
>    - No re-prompts. No double-flip. The state machine moves forward only.

### Report output extension

Extend the `/en-ship` report output (existing Output section, line 80+) to include the new field:

```
plan_completion_checkpoint: completed_and_moved (EN07-auth-rotation → completed/; shipped: 2026-05-14)
```

For `skipped_by_user`, include the audit-friendly note:

```
plan_completion_checkpoint: skipped_by_user (plan stays at in_progress; user explicit skip)
```

For `incomplete_build`:

```
plan_completion_checkpoint: incomplete_build (units missing peer-evidence: U3, U7)
```

For `not_applicable` and `up_to_date`, omit the line entirely — these aren't audit-worthy events.

## Change 2 — `/en-learn` SKILL.md: unbundle skip-path from step 11

**File:** `skills/en-learn/SKILL.md`, step 11 (the move-and-flip step).

### Why

Currently step 11 fires only on actual learning capture (the user filed a learning, the wiki entry was written, then status flips and file moves). If the user opens `/en-learn` and immediately says "skip — no learnings worth filing," the lifecycle flip is collateral damage.

This change separates concerns: capturing a learning (wiki bookkeeping) and marking the plan complete (lifecycle bookkeeping). The lifecycle flip should happen on every `/en-learn capture` invocation that reaches the end — regardless of whether a learning was actually filed.

### Behavior change

Step 11 splits into two sub-steps:

- **11a. Lifecycle flip (always runs):** flip `status: in_progress → completed`, set `shipped: <today>`, `git mv` the file. This is the *minimum* of what step 11 does today.
- **11b. Documentation-tense updates (only runs when a learning was actually captured):** replace plan-tense with documentation-tense, note deviations from the plan. Skipped if the user said "skip — no learnings worth capturing" earlier in the flow.

In effect: 11a always fires; 11b is conditional on capture-actually-happened.

### Edge case: `/en-learn capture` invoked without a plan context

If `/en-learn` is invoked outside the context of a specific plan (e.g. `/en-learn capture` from main with no `--from-conversation` argument and no plan_id derivable), step 11 should silently no-op the lifecycle flip — there's nothing to flip. Same as today; just be explicit about it.

## Change 3 — `docs/foundation.md` decision entry

Add a decision entry (number TBD at implementation time):

> **D-N. Source of truth for `in_progress → completed` is `/en-learn capture` step 11, with `/en-ship` preflight as backstop.** The plan-status lifecycle moves through three flips: `/en-plan` finalize loop (`draft → open`), `/en-build` step 4b (`open → in_progress`), and `/en-learn capture` step 11 (`in_progress → completed`). The final flip is bundled with the file move from `docs/plans/active/` to `docs/plans/completed/` and the `shipped:` date set. Field-observed friction: `/en-learn` is soft-auto-invoked, and step 11 was bundled with actually-captured-a-learning, so a "skip capture" decision orphaned the plan at `in_progress`. Resolution: (a) `/en-learn` step 11 unbundles — lifecycle flip happens whenever `/en-learn capture` is invoked, regardless of whether a learning was actually filed; (b) `/en-ship` preflight gains a plan-completion checkpoint as backstop — catches plans whose `/en-learn` invocation got dropped entirely. The checkpoint is informational (doesn't gate ship); it surfaces stuck-at-in_progress plans and offers a structured y/skip/details flip. Build completeness is checked via `bin/ensemble-verify-peer-evidence` aggregated by U-ID before offering the flip — refuses to flip if any unit lacks peer-evidence trailers.

## Change 4 — Drift-guard test

**File:** `tests/peer-resolution-trailer/peer-resolution-trailer.test.sh` (extend existing) OR `tests/lint/plan-completion-checkpoint.test.sh` (new file; decide at implementation time).

**New assertions (~16):**

| # | Assertion |
|---|---|
| 1 | `skills/en-ship/SKILL.md` has a "Plan completion checkpoint" step. Test asserts the literal phrase "Plan completion checkpoint" appears as a step heading. |
| 2 | The checkpoint is in the **preflight phase**, between step 3 (Pre-flight: git status) and the lint/typecheck/tests step. Asserted by step-number ordering: checkpoint step number must be < lint step number AND > pre-flight step number. |
| 3 | The checkpoint documents all six response/outcome paths: `y → completed_and_moved`, `skip → skipped_by_user`, automatic `up_to_date`, automatic `not_applicable`, automatic `incomplete_build`, `details` (non-terminal). Test asserts each canonical string appears in the section. |
| 4 | The checkpoint uses `$ENSEMBLE_ROOT/bin/ensemble-verify-peer-evidence` (anchored path per PR #15 anchoring convention) for the build-completeness check. |
| 5 | The checkpoint is **informational, not blocking** — explicit phrasing that PR still opens on `incomplete_build`. |
| 6 | Idempotency rule is documented: re-running after a flip yields `up_to_date`, not a double-flip. |
| 7 | `/en-ship` report output template documents the `plan_completion_checkpoint:` line with all five terminal outcome values (line emitted only for `completed_and_moved`, `skipped_by_user`, `incomplete_build`; omitted for `up_to_date` and `not_applicable`). |
| 8 | Bare words `completed`, `done`, `skipped`, `flipped` MUST NOT appear as report values (must be the canonical multi-word strings). |
| 9 | `skills/en-learn/SKILL.md` step 11 documents the 11a/11b unbundle: 11a (lifecycle flip) always runs; 11b (documentation-tense updates) only runs when a learning was captured. |
| 10 | en-learn step 11 explicitly states the skip-capture path STILL flips status (per the unbundle). |
| 11 | en-learn step 11's edge case (invoked without plan context) is documented as a silent no-op. |
| 12 | `docs/foundation.md` has a decision entry covering the source-of-truth + backstop semantics. |
| 13 | The foundation entry explicitly mentions the "field-observed friction" rationale so future readers see why the design changed. |
| 14 | The checkpoint section references `bin/ensemble-verify-peer-evidence` (catches drift toward simpler but less accurate completion checks). |
| 15 | Plan-branch detection logic is documented (regex extraction of `<plan_id>` from branch name; foundation's `plan_id_prefix:` source). |
| 16 | `/en-learn` step 11's existing behavior (when capture HAS happened: documentation-tense + deviation notes) is preserved — drift guard checks the en-learn SKILL.md still has the documentation-tense / deviation-notes language. Catches accidental removal during the unbundle implementation. |

## Implementation outline

5 units, Standard depth.

- **U1** — `skills/en-ship/SKILL.md`: insert the "Plan completion checkpoint" as new step 4 (renumber existing 4–11 → 5–12). Document the seven sub-steps (plan-branch detection, plan file lookup, status inspection, build completeness check, prompt, response handler, idempotency). Update the Output section's report template with the new `plan_completion_checkpoint:` line.

  **Risk:** medium (changes the en-ship preflight surface; affects every `/en-ship` run). **Category:** feature. **Gated:** false (not a production-state change — the checkpoint is informational, doesn't gate ship).

  **Depends:** nothing.

- **U2** — `skills/en-learn/SKILL.md`: split step 11 into 11a (always-runs lifecycle flip) and 11b (conditional documentation-tense updates). Document the skip-capture-still-flips-status behavior. Document the edge case (no plan context → silent no-op).

  **Risk:** low. **Category:** feature. **Gated:** false.

  **Depends:** nothing.

- **U3** — `docs/foundation.md`: add the source-of-truth decision entry per Change 3. Resolve the actual D-N number at PR time.

  **Risk:** low. **Category:** other (doc update). **Gated:** false.

  **Depends:** nothing.

- **U4** — `tests/peer-resolution-trailer/peer-resolution-trailer.test.sh` (or new file): +16 drift-guard assertions per the table above. Decide test-file home based on whether trailer tests are the right home or a new file is cleaner.

  **Risk:** low. **Category:** feature. **Gated:** false.

  **Depends:** U1, U2, U3 (the assertions test their outputs).

- **U5** — Verification: run `tests/run.sh` + `bin/ensemble-lint` + manual spot-check. Confirm the report output renders correctly; confirm the en-learn skip-path actually flips status in mental walkthroughs; confirm en-ship checkpoint surfaces the right outcome lines for each path.

  **Risk:** low. **Category:** diagnostics. **Gated:** false.

  **Depends:** U1, U2, U3, U4.

## What's deliberately NOT in this PR

- **`/en-qa` post-flow status check.** QA isn't shipping; flipping at QA-done conflates correctness with completion. The PR keeps `/en-qa` untouched.
- **A `--no-completion-checkpoint` flag.** No knob added; if the user wants to skip, they pick `skip` at the prompt. Adding a flag implies the checkpoint is intrusive — but it's a single prompt with skip readily available.
- **Auto-flip without prompt.** Even when build is verifiably complete, the checkpoint asks. Reason: the user might be shipping a WIP PR (e.g. draft PR for early feedback) and not actually completing the plan. The prompt preserves user agency.
- **Retroactive status updates for already-shipped plans.** If a plan is already shipped and the file is in `completed/` — checkpoint is `up_to_date` and silent. No retroactive editing.
- **Cross-plan status tracking.** The checkpoint only operates on the plan derivable from the current branch. Other in-progress plans on other branches are out of scope.

## Open questions (resolved during analysis)

1. **Should `/en-ship` block on `incomplete_build`?** Resolved: **no.** Informational only. User might be shipping intentionally with skipped units; plan-status correctness is important but not a ship-blocker.
2. **What defines "build complete"?** Resolved: every plan-unit has ≥1 peer-evidence trailer (`peer-verdict:`, `peer-resolution:`, or `peer-skipped:`) on the current branch. Leverages existing `bin/ensemble-verify-peer-evidence` helper.
3. **What about `/en-ship` from main (no plan branch)?** Resolved: `not_applicable` outcome; checkpoint silently passes.
4. **Should `/en-learn` step 11 unbundling be in scope, or separate PR?** Resolved: **same PR.** They're complementary (defense in depth). The en-ship backstop covers the case where `/en-learn` is dropped entirely; the en-learn unbundle covers the case where `/en-learn` is invoked but capture is skipped. Both fixes together are tighter than either alone.

## Verification plan

- All existing tests still pass.
- +16 new drift-guard assertions cover the new contract.
- Manual sanity check: walk a mental `/en-build → /en-qa → /en-learn (skip capture) → /en-ship` flow. Under the new design, the en-learn skip-path still flips status (U2), so by the time en-ship runs, status is `completed` and checkpoint reports `up_to_date`. Plan correctly lands in `completed/`.
- Manual sanity check: walk a mental `/en-build → /en-ship (no en-qa or en-learn at all)` flow. Status is still `in_progress` at en-ship time. Checkpoint runs, build is verifiably complete (assumes en-build set all peer-evidence trailers), prompt fires, user picks `y`, status flips and file moves. Plan lands in `completed/` via the backstop.
- Manual sanity check: walk a mental `/en-ship from main` flow. Checkpoint detects no plan_id from branch; outcome `not_applicable`; silent.

## Review history

Initial spec (this document).
