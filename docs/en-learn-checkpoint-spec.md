---
title: en-learn capture checkpoint at en-ship — spec
status: draft
owner: mano
created: 2026-05-12
related:
  - skills/en-ship/SKILL.md
  - skills/en-qa/SKILL.md
  - skills/en-build/SKILL.md
  - skills/en-learn/SKILL.md
  - docs/foundation.md
---

# en-learn capture checkpoint at en-ship

## Problem

The current auto-invoke design relies on two soft prompts at the end of `/en-build` and `/en-qa`. Both have the same failure mode as the en-setup verification step we fixed in PR #13: a soft prompt at the end of a long mechanical sequence gets silently dropped by the agent under context pressure.

Two related issues compound this:

1. **`/en-qa`'s prompt is anchored to "N bugs found and fixed."** Implicit reading: if N=0, no prompt fires. That misses real non-bug captures — flaky-test stabilizations, missing edge-case fixtures, library footguns discovered during exploratory QA, architectural assumptions surfaced by end-to-end flows.

2. **No backstop before `/en-ship`.** If both `/en-build`'s and `/en-qa`'s soft prompts drop, learnings vanish silently. The user finds out only later when reviewing the wiki and noticing gaps. By then the context is gone and a retroactive capture is a worse capture.

**User-stated requirement:** *"make sure we capture the learning (if there are any to be captured) before we execute en-ship."*

en-ship is the natural chokepoint — last step before code leaves the local environment, user is engaged with "what's going out the door," one place to enforce instead of two soft-prompt sites.

## Resolved decisions

1. **Add a learning checkpoint to `/en-ship`'s preflight.** Not a post-flight soft prompt — a numbered, structured preflight step with a visible outcome line in the en-ship report. The agent must surface either "captured N learnings" OR "intentionally skipped" OR "up to date" — no silent drop possible.
2. **Always prompt; make skip cheap.** Don't gate on diff-size or commit-count thresholds. Prompt on every `/en-ship` invocation; the user types `skip` if nothing's worth filing. Cost of acknowledging "nothing this time" is much lower than cost of a missed capture.
3. **Broaden `/en-qa`'s anchor.** Replace *"QA found and fixed N bugs. Capture as learnings?"* with *"QA wrapped. Anything worth filing as a learning from this pass? (yes / skip)"* so the prompt fires even when zero bugs were found.
4. **Keep `/en-build` and `/en-qa` soft prompts.** They're freshest-point capture opportunities and they work when the agent runs them. The new en-ship checkpoint is the **backstop**, not a replacement.
5. **Update foundation §D26.** Currently *"en-learn auto-runs after en-build and en-qa."* Becomes *"en-learn auto-runs after en-build and en-qa, AND fires as a structured checkpoint in en-ship's preflight."*

## Change 1 — `/en-ship` learning checkpoint

**File:** `skills/en-ship/SKILL.md`

Add a new preflight step (after lint/typecheck/secret-scan, before commit composition):

> **N. Learning checkpoint.** Before composing the commit and pushing, surface a structured prompt to capture learnings from work since the last capture. This is the **backstop** for the soft auto-invokes in `/en-build` and `/en-qa` — those should have caught most captures already, but this step ensures no learnings ship without an explicit decision.
>
> 1. **Determine the capture baseline.** Read `docs/learnings/log.md` and find the latest `[YYYY-MM-DD] capture | ...` entry. If the log doesn't exist or has no capture entries, baseline is "since branch creation."
> 2. **Compute scope.** `git log <baseline-sha>..HEAD` (or `git log --since=<baseline-date>` if no SHA). Count commits and diff size.
> 3. **Surface the checkpoint prompt** (structured, not soft):
>    ```
>    Learning checkpoint
>    ───────────────────
>    <N> commits since last /en-learn capture (<date>).
>    Diff: <X> files changed, <Y> lines.
>    Recent commits touch: <comma-separated areas inferred from changed files>
>    
>    Worth filing learnings before shipping? (yes / skip / details)
>    ```
> 4. **Handle response.**
>    - `yes` → invoke `/en-learn capture` interactively; on completion, resume en-ship preflight at the next step. Record `learning_checkpoint: captured (N learnings)` in en-ship's report.
>    - `skip` → record `learning_checkpoint: intentionally_skipped` in en-ship's report. The structured record makes the skip auditable later (vs. the current silent drop).
>    - `details` → print the commit list + per-area summary; re-prompt with the same options.
> 5. **Idempotency check.** If the baseline scan finds zero commits since last capture, the checkpoint records `learning_checkpoint: up_to_date` and proceeds silently (no prompt). en-ship runs twice on the same branch don't re-prompt.

The structured outcome line in the en-ship report is the load-bearing piece. Agents can drop a soft post-flight prompt; they cannot omit a numbered step whose output is rendered in the report.

**Flag:** `--no-learning-checkpoint` to skip entirely (for CI scripts or fast iterations where the user wants en-ship strictly mechanical).

## Change 2 — Broaden `/en-qa`'s capture prompt

**File:** `skills/en-qa/SKILL.md`

Current (lines 66–72):

> After QA wraps, soft-prompt:
> > "QA found and fixed N bugs. Capture as learnings? (yes / skip)"
> User accepts → invoke `/en-learn capture` for each fixed bug.

Replace with:

> After QA wraps, soft-prompt regardless of bug count:
> > "QA wrapped. Anything worth filing as a learning from this pass? (yes / skip)"
> >
> > Surface a quick context line if any of these apply:
> > - Bugs found and fixed: cite count + brief one-liner per bug.
> > - Tests stabilized (flake fixes, fixture additions): cite count.
> > - Non-obvious patterns surfaced during exploratory QA: brief one-liner.
> > - Library / API footguns discovered.
>
> The prompt fires even when no bugs were found — exploratory QA often surfaces non-bug learnings (missing edge-case fixtures, architectural assumptions worth filing, library footguns). The agent uses judgment on what to include in the context line; the user decides whether anything's worth capturing.
>
> User accepts → invoke `/en-learn capture` for each item the user identifies. User declines → no-op. The en-ship learning checkpoint (per the en-ship preflight) acts as the backstop if this prompt drops.

Anchor shifts from "bugs found" to "QA wrapped." Always asks; user filters.

## Change 3 — Foundation §D26

**File:** `docs/foundation.md`

Current:

> **D26. `en-learn` auto-runs after `en-build` and `en-qa`.** Soft auto-invoke with a one-line announcement; user can decline. Removes the friction of remembering to capture lessons.

Replace with:

> **D26. `en-learn` auto-runs after `en-build` and `en-qa`, AND fires as a structured checkpoint in `en-ship`'s preflight.** The en-build and en-qa auto-invokes are soft prompts at the freshest point (right after the work is done); they're the preferred capture point when they fire. The en-ship checkpoint is the **backstop** — a structured preflight step (not a soft prompt) that surfaces a "what changed since last capture?" prompt before code leaves the local environment. Records `learning_checkpoint: <captured|skipped|up_to_date>` in en-ship's report, so missed captures are auditable rather than silently dropped. Together: capture at point of insight when it fires; backstop at point of ship when it doesn't.

## Drift guards

**File:** `tests/peer-resolution-trailer/peer-resolution-trailer.test.sh` (or a new test file for en-ship if appropriate).

New assertions:

| # | Assertion |
|---|---|
| 1 | `skills/en-ship/SKILL.md` has a "Learning checkpoint" preflight step. |
| 2 | The checkpoint step references `docs/learnings/log.md` for baseline. |
| 3 | The checkpoint records a structured outcome line (`learning_checkpoint:` field in the en-ship report). |
| 4 | The checkpoint supports `up_to_date`, `captured`, and `intentionally_skipped` outcome states. |
| 5 | The checkpoint has the `--no-learning-checkpoint` flag documented. |
| 6 | `skills/en-qa/SKILL.md`'s post-QA prompt is NOT anchored to "N bugs" only — must include the broadened phrasing ("QA wrapped" or similar). |
| 7 | `skills/en-qa/SKILL.md` documents the four capture categories (bugs, tests stabilized, patterns, library footguns). |
| 8 | `docs/foundation.md` §D26 mentions en-ship as a backstop, not just en-build and en-qa. |
| 9 | `docs/foundation.md` §D26 mentions "structured checkpoint" language (so the design intent doesn't drift back to soft prompt). |

These mirror the drift-guard pattern from PR #15 (skill-helper anchoring) and PR #17 (gated-criteria tightening) — assertions that catch regressions of the design intent, not just regressions of the code.

## Implementation outline

5 units, Standard depth:

- **U1** — `skills/en-ship/SKILL.md`: add learning-checkpoint preflight step with the five sub-steps (baseline, scope, prompt, handle response, idempotency). Add `--no-learning-checkpoint` to the flags table. Update the en-ship report output template to include the `learning_checkpoint:` line.

  **Risk:** low. **Category:** feature. **Gated:** false.

- **U2** — `skills/en-qa/SKILL.md`: replace the "N bugs found" prompt with the broadened "QA wrapped" prompt; document the four capture categories. Update the output-format example to show the broader prompt shape.

  **Risk:** low. **Category:** feature. **Gated:** false.

- **U3** — `docs/foundation.md`: update §D26 to document en-ship as the backstop checkpoint with structured outcome.

  **Risk:** low. **Category:** other (doc update). **Gated:** false.

- **U4** — `tests/peer-resolution-trailer/peer-resolution-trailer.test.sh`: +9 drift-guard assertions per the table above. Test totals expected: 709 → 718.

  **Risk:** low. **Category:** feature. **Gated:** false.

- **U5** — Verification: run `tests/run.sh` + `bin/ensemble-lint` + manual spot-check of the en-ship preflight prose. Confirm the structured outcome line renders correctly in the example output.

  **Risk:** low. **Category:** diagnostics. **Gated:** false.

## What this doesn't change

- **`/en-build`'s post-flight auto-invoke**: stays as a soft prompt. Working as designed for the freshest-point case.
- **`/en-learn` itself**: no changes to the capture mechanism. en-ship invokes the existing `/en-learn capture` flow.
- **D21 capture-from-synthesis reflex** in `/en-plan`, `/en-review`, `/en-brainstorm`: unchanged. Those are insight-moment captures, not end-of-work captures.

## Open questions left for review

1. **Threshold for the "up_to_date" silent-pass.** The spec currently silently passes when zero commits exist since last capture. Should the threshold be "zero commits" or "zero commits AND zero significant diff in `docs/`"? If a commit only touched docs, is that worth a capture prompt? Lean: zero commits is the right threshold; doc-only work rarely produces captures.

2. **What counts as a "capture entry" in `docs/learnings/log.md` for baseline detection?** Just lines starting with `## [YYYY-MM-DD] capture |`? Or any entry that mentions a learning ID? Lean: only lines starting with `[YYYY-MM-DD] capture |` — the explicit capture entries. Refresh/ingest/update operations don't reset the baseline because they don't represent "new work captured."

3. **Should the checkpoint also fire on hot-fix PRs that skip /en-build?** A user running `/en-ship` directly on a hand-coded hot-fix branch (no `/en-build` invocation in this session) still benefits from the checkpoint — they may have learned something worth filing. Lean: yes, the checkpoint fires regardless of how the commits got there. Hot-fixes are exactly the kind of work most likely to teach a lesson.

4. **What about `--no-learning-checkpoint` becoming the de facto default in CI?** If automated en-ship runs always pass `--no-learning-checkpoint`, the checkpoint never fires in automation. Acceptable trade-off? Or should the checkpoint always run interactively and CI is expected to skip via a different path (e.g., a `CI=true` env var)? Lean: `--no-learning-checkpoint` flag is fine; CI scripts opt in to non-interactive en-ship by setting `CI=true` (already convention), and the checkpoint can auto-skip when `CI=true` AND `--no-learning-checkpoint` isn't set — but record `learning_checkpoint: ci_environment` in the report so it's still auditable.

## Net summary

5 units, ~9 new test assertions, 3 SKILL.md / docs edits. The en-ship preflight checkpoint is the load-bearing change — it ensures the capture decision happens, even if the upstream soft prompts dropped. en-qa's broadened prompt is the secondary improvement that captures non-bug learnings at the freshest point. Foundation §D26 update keeps the design intent documented.

Smallest possible patch that closes the regression: learning capture either fires at the right time or surfaces a clear "intentionally skipped" record at en-ship time — never silently drops.
