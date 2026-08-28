---
title: en-learn capture checkpoint (at en-build completion since EN04) - spec
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

# en-learn capture checkpoint at en-build completion (relocated from en-ship by EN04)

> **AUTHORITATIVE LOCATION: `/en-build` completion — and it is the SOLE capture point.** EN04 relocated this checkpoint from `/en-ship`'s preflight to the end of `/en-build`, and the EN04 follow-up **consolidated it to en-build only**: `/en-qa` and `/en-ship` no longer prompt for learnings. It fires at the very end of en-build's post-build phase — **after the branch-level simplify + Outside Voice review + evidence audit** — so capture reflects the fully reviewed build. The mechanics below (a structured, non-droppable checkpoint with the four canonical outcome values) are unchanged and still load-bearing.
>
> **Two things in this document are now HISTORICAL / superseded:** (1) every "en-ship preflight" / "en-ship report" reference — read it as "en-build completion" / "en-build report" (the checkpoint no longer exists in en-ship); (2) **Decisions #3/#4 and "Change 2" below (broaden + keep `/en-qa`'s prompt) — the en-qa prompt was REMOVED, not broadened.** Drift guards assert the en-build-only location. Canonical records: foundation D26 + D38, `skills/en-build/SKILL.md`.

## Problem

The current auto-invoke design relies on two soft prompts at the end of `/en-build` and `/en-qa`. Both have the same failure mode as the en-setup verification step we fixed in PR #13: a soft prompt at the end of a long mechanical sequence gets silently dropped by the agent under context pressure.

Two related issues compound this:

1. **`/en-qa`'s prompt is anchored to "N bugs found and fixed."** Implicit reading: if N=0, no prompt fires. That misses real non-bug captures — flaky-test stabilizations, missing edge-case fixtures, library footguns discovered during exploratory QA, architectural assumptions surfaced by end-to-end flows.

2. **No backstop before `/en-ship`.** If both `/en-build`'s and `/en-qa`'s soft prompts drop, learnings vanish silently. The user finds out only later when reviewing the wiki and noticing gaps. By then the context is gone and a retroactive capture is a worse capture.

**User-stated requirement:** *"make sure we capture the learning (if there are any to be captured) before we execute en-ship."*

en-ship is the natural chokepoint — last step before code leaves the local environment, user is engaged with "what's going out the door," one place to enforce instead of two soft-prompt sites.

## Review history

This spec went through one round of review on PR #18. Three findings, all addressed in-place:

| Finding | Severity | Resolution |
|---|---|---|
| Checkpoint ran after lint/typecheck/secret-scan — newly written `/en-learn` files would ship unchecked | P2 | Moved checkpoint to **first** preflight step (before lint/typecheck/secret-scan). Files written by `/en-learn capture` now go through all preflight checks. |
| Baseline detection via `git log --since=<date>` was imprecise — same-day captures couldn't distinguish commits before vs. after | P2 | Added `\| <head-sha>` field to `docs/learnings/log.md` capture entries (Change 1b). Baseline scan uses `git log <sha>..HEAD` for precise semantics. Legacy entries fall back gracefully with a one-line imprecise-baseline notice. |
| Outcome-enum drift: foundation §D26 used `<captured\|skipped\|up_to_date>` while the rest of the spec used `intentionally_skipped` | P3 | Locked the canonical enum at the top of the spec; updated foundation §D26 to match; added drift-guard assertion #4 (test asserts exact spelling of all four values; asserts bare `skipped` is NOT used as an outcome value). |

## Outcome enum (canonical)

The **en-build report's** `learning_checkpoint:` field accepts exactly these four values. Every other section of this spec, the foundation update, the SKILL.md changes, and the drift-guard tests MUST use these exact strings:

| Value | Meaning |
|---|---|
| `captured (N learnings)` | User answered `yes`; `/en-learn capture` wrote N entries. |
| `intentionally_skipped` | User answered `skip`; explicit decision recorded for audit. |
| `up_to_date` | Idempotency path — zero commits since last capture; no prompt fired. |
| `ci_environment` | Non-interactive CI run; checkpoint auto-skipped under `CI=true`. |

If any section of this spec uses different wording (e.g. `skipped` instead of `intentionally_skipped`), it's a bug. The drift-guard test (see Drift guards section) asserts the exact spelling across the spec, SKILL.md, foundation §D26, and the test suite.

## Resolved decisions

1. **Add a structured learning checkpoint at `/en-build` completion** (relocated from `/en-ship`'s preflight by EN04). Not a post-flight soft prompt - a numbered, structured step with a visible `learning_checkpoint:` outcome line in the build summary. The agent must surface one of the four canonical outcome values - no silent drop possible. (Originally specified in `/en-ship`'s preflight; EN04 moved it to en-build completion so capture happens at the point of insight and en-ship stays hands-off. The non-droppable-structured-step requirement is unchanged.)
2. **Always prompt; make skip cheap.** Don't gate on diff-size or commit-count thresholds. Prompt on every `/en-ship` invocation; the user types `skip` if nothing's worth filing. Cost of acknowledging "nothing this time" is much lower than cost of a missed capture.
3. **Broaden `/en-qa`'s anchor.** Replace *"QA found and fixed N bugs. Capture as learnings?"* with *"QA wrapped. Anything worth filing as a learning from this pass? (yes / skip)"* so the prompt fires even when zero bugs were found.
4. **Keep `/en-build` and `/en-qa` soft prompts.** They're freshest-point capture opportunities and they work when the agent runs them. The new en-ship checkpoint is the **backstop**, not a replacement.
5. **Update foundation §D26** (as shipped, EN04): *"en-learn auto-runs after en-qa, AND fires as a structured checkpoint at `/en-build` completion."* (The original EN04 draft said "en-ship's preflight"; the relocation to en-build is the shipped state.)

## Change 1 - learning checkpoint

> **HISTORICAL (superseded by EN04).** This section describes the ORIGINAL placement in `/en-ship`'s preflight. **EN04 relocated the checkpoint to `/en-build` completion** - it no longer exists in `/en-ship`, and drift guards now assert the en-build location. Read the mechanics below (baseline, scope, outcome enum, prompt) as-is, but the host file is `skills/en-build/SKILL.md` at the end-of-build `/en-learn` hand-off, NOT en-ship preflight. Do not reintroduce the en-ship step. The "before lint/typecheck/secret-scan" ordering rationale below is an en-ship-preflight concern and no longer applies at en-build.

**File (as implemented since EN04):** `skills/en-build/SKILL.md` (originally `skills/en-ship/SKILL.md`).

Original en-ship placement: a new preflight step **as the FIRST preflight step - before lint, typecheck, and secret-scan.**

**Ordering rationale.** When the user answers `yes`, `/en-learn capture` can write new files: `docs/learnings/log.md` (appended), new learning pages under `docs/learnings/{bugs,patterns,decisions,sources}/`, possibly `docs/architecture.md` or `docs/foundation.md` cross-reference updates, and the architecture-sync index updates. If the checkpoint runs AFTER lint/typecheck/secret-scan, those newly-written files get staged and committed without being scanned — they ship unchecked. Running the checkpoint FIRST guarantees every file in the final diff was inspected by every preflight check.

> **1. Learning checkpoint** (first preflight step). Before any other preflight check, surface a structured prompt to capture learnings from work since the last capture. This is the **backstop** for the soft auto-invokes in `/en-build` and `/en-qa` — those should have caught most captures already, but this step ensures no learnings ship without an explicit decision, AND any files written by `/en-learn capture` go through the rest of preflight (lint/typecheck/secret-scan) before being committed.
>
> 1. **Determine the capture baseline.** Read `docs/learnings/log.md` and find the latest `[YYYY-MM-DD] capture | <subject> | <head-sha>` entry. **The `<head-sha>` field is the load-bearing piece** — see "Change 1b: log format" below for the format addition required to make this work. If the log doesn't exist or has no capture entries, baseline is "since branch creation" (resolved via `git merge-base HEAD <default-branch>`).
> 2. **Compute scope.** `git log <baseline-sha>..HEAD` — precise commit range, no date-boundary fuzziness. Count commits and diff size.
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
> 5. **Idempotency check.** If `git log <baseline-sha>..HEAD` returns zero commits, the checkpoint records `learning_checkpoint: up_to_date` and proceeds silently (no prompt). en-ship runs twice on the same branch don't re-prompt.
>
> 6. **Legacy-log fallback.** If the latest capture entry in `docs/learnings/log.md` doesn't have a `<head-sha>` field (legacy plans pre-this-spec), the checkpoint cannot precisely determine the baseline because `## [YYYY-MM-DD] capture | <subject>` alone can't distinguish commits before vs. after a same-day capture. In that case:
>    - Surface a one-line notice: *"Last capture entry lacks `<head-sha>`. Baseline detection is imprecise until next capture refreshes the log format."*
>    - Use the conservative fallback: prompt unconditionally with `<unknown> commits since last capture (date: <date>)`. The user makes the call; no silent up_to_date.
>    - After the user runs a `yes` capture, the new log entry will include the SHA, restoring precise detection on subsequent en-ship runs.

## Change 1b — `docs/learnings/log.md` format addition

**Files:** `references/learn-log-format.md`, `skills/en-learn/SKILL.md`.

**Format change.** Each capture-mode entry in `docs/learnings/log.md` gains a `| <head-sha>` field, recording the git HEAD at the moment of capture:

```
## [2026-05-12] capture | Single-flight cache pattern for refresh tokens | 4b0424d1
```

**Why** — without a stored SHA, the en-ship checkpoint's baseline scan falls back to `git log --since=<date>`, which can't distinguish commits *before* vs. *after* a same-day capture. Two captures on the same day or a commit between same-day captures both break the up_to_date idempotency. Storing the HEAD SHA at capture time gives `git log <sha>..HEAD` precise semantics.

**Backward compatibility.** Existing log entries without a SHA continue to parse. The checkpoint logic (step 6 in Change 1) falls back to the conservative "imprecise baseline" path with a one-line notice and unconditional prompt. The first new capture re-establishes precise detection.

**`/en-learn capture` write path.** On every capture, `/en-learn` writes the new log entry with `| $(git rev-parse --short HEAD)` substituted in. Other capture modes (refresh, ingest, CONTEXT.md seeding) don't include SHA — only `capture` mode does, since only `capture` represents a baseline reset.

**Refresh mode does NOT update the baseline.** `## [YYYY-MM-DD] refresh | ...` entries don't carry SHA and don't reset the en-ship checkpoint baseline. Only explicit `capture | ` entries do. (Per open question #2 from the original spec — resolved here in favor of capture-only.)

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

> **D26 (as shipped since EN04). `en-learn` auto-runs after `en-qa`, AND fires as a structured checkpoint at `/en-build` completion.** The en-qa auto-invoke is a soft prompt at the freshest point. The **en-build completion checkpoint** is the structured, non-droppable capture point (not a soft prompt) that surfaces a "what changed since last capture?" prompt at build completion. Records `learning_checkpoint: <captured|intentionally_skipped|up_to_date>` in the en-build report (with `ci_environment` as a fourth value under `CI=true`), so missed captures are auditable rather than silently dropped. *(The original EN04 draft placed this in en-ship's preflight; the shipped D26 in `docs/foundation.md` is the authoritative wording.)*

## Drift guards

**File:** `tests/peer-resolution-trailer/peer-resolution-trailer.test.sh` (or a new test file for en-ship if appropriate).

New assertions:

| # | Assertion |
|---|---|
| 1 | `skills/en-ship/SKILL.md` has a "Learning checkpoint" preflight step. |
| 2 | The checkpoint step references `docs/learnings/log.md` for baseline. |
| 3 | The checkpoint records a structured outcome line (`learning_checkpoint:` field in the en-ship report). |
| 4 | The checkpoint supports **exactly four** outcome values, spelled exactly: `captured (N learnings)`, `intentionally_skipped`, `up_to_date`, `ci_environment`. Assert all four spellings appear in the SKILL.md and the test suite; assert the bare word `skipped` does NOT appear as an outcome value (must be `intentionally_skipped` to match the spec contract). |
| 5 | The checkpoint runs FIRST in en-ship's preflight, BEFORE lint/typecheck/secret-scan. Test asserts the step ordering by reading SKILL.md and confirming the learning-checkpoint step number is less than the lint/typecheck/secret-scan step numbers. |
| 6 | The checkpoint has the `--no-learning-checkpoint` flag documented. |
| 7 | `skills/en-qa/SKILL.md`'s post-QA prompt is NOT anchored to "N bugs" only — must include the broadened phrasing ("QA wrapped" or similar). |
| 8 | `skills/en-qa/SKILL.md` documents the four capture categories (bugs, tests stabilized, patterns, library footguns). |
| 9 | `docs/foundation.md` §D26 mentions en-ship as a backstop, not just en-build and en-qa. |
| 10 | `docs/foundation.md` §D26 mentions "structured checkpoint" language (so the design intent doesn't drift back to soft prompt). |
| 11 | `docs/foundation.md` §D26 uses the canonical outcome enum spelling — `intentionally_skipped` (not `skipped`), `up_to_date`, `captured`, `ci_environment`. Catches the P3 drift class from PR #18 review. |
| 12 | `references/learn-log-format.md` documents the `\| <head-sha>` field on capture entries. |
| 13 | `skills/en-learn/SKILL.md` writes the SHA on `capture` mode (via `git rev-parse --short HEAD` substitution). |
| 14 | Refresh/ingest/bootstrap entries do NOT include SHA (only `capture` mode does — it's the only baseline-resetting operation). |

These mirror the drift-guard pattern from PR #15 (skill-helper anchoring) and PR #17 (gated-criteria tightening) — assertions that catch regressions of the design intent, not just regressions of the code.

## Implementation outline

7 units, Standard depth. **Build order matters**: U1 (log format) must land before U2 (en-ship checkpoint) so the baseline-SHA read path has somewhere to read from.

- **U1** — `references/learn-log-format.md` + `skills/en-learn/SKILL.md`: extend the capture-entry format to include `| <head-sha>` (the actual format change in the reference doc + the write path in `/en-learn capture`). Backward-compat: legacy entries without SHA continue to parse; en-ship checkpoint falls back to "imprecise baseline" with a one-line notice. Refresh / ingest / bootstrap modes don't carry SHA.

  **Risk:** medium (format change with backward-compat surface). **Category:** schema-evolution. **Gated:** false.

- **U2** — `skills/en-ship/SKILL.md`: add learning-checkpoint as the **first preflight step, before lint/typecheck/secret-scan** (per the P2 ordering fix). Six sub-steps: baseline, scope, prompt, response handler, idempotency, legacy fallback. Add `--no-learning-checkpoint` to the flags table. Update the en-ship report output template to include the `learning_checkpoint:` line with the four canonical outcome values.

  **Risk:** low. **Category:** feature. **Gated:** false. **Depends:** U1.

- **U3** — `skills/en-qa/SKILL.md`: replace the "N bugs found" prompt with the broadened "QA wrapped" prompt; document the four capture categories. Update the output-format example to show the broader prompt shape.

  **Risk:** low. **Category:** feature. **Gated:** false.

- **U4** — `docs/foundation.md`: update §D26 to document en-ship as the backstop checkpoint with structured outcome, using the **canonical four-value enum spelling** (`captured | intentionally_skipped | up_to_date | ci_environment`). NOT `skipped` — that's the P3 drift class from PR #18 review.

  **Risk:** low. **Category:** other (doc update). **Gated:** false.

- **U5** — `tests/peer-resolution-trailer/peer-resolution-trailer.test.sh`: +14 drift-guard assertions per the table above (the table grew from 9 → 14 with the SHA-in-log additions and the enum-consistency assertions). Test totals expected: 709 → 723.

  **Risk:** low. **Category:** feature. **Gated:** false.

- **U6** — Add a small unit test for the baseline-SHA parsing logic. Synthetic `docs/learnings/log.md` fixtures: (a) entry with SHA → parsed correctly; (b) entry without SHA (legacy) → falls back to date with notice; (c) no entries → falls back to branch creation. Asserts the parsing logic the checkpoint depends on.

  **Risk:** low. **Category:** feature. **Gated:** false. **Depends:** U1.

- **U7** — Verification: run `tests/run.sh` + `bin/ensemble-lint` + manual spot-check of the en-ship preflight prose. Confirm the structured outcome line renders correctly in the example output, and that the four canonical enum values are spelled identically across all touched files.

  **Risk:** low. **Category:** diagnostics. **Gated:** false.

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
