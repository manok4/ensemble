---
type: plan
plan_type: improvement
plan_id: EN08
title: en-review lite-gate transparency + auditable mutation boundary
status: open
location: active
created: 2026-07-07
shipped:
deepened:
covers_requirements: []
requirements_pending: false
related_design:
peer_review_verdict: revise
peer_review_overridden: cap-hit-accepted-by-user
peer_review_iterations: 3
peer_review_last_run: 2026-07-09
peer_review_plan_hash: 2002cdaaddcc37c25bbff87ae38da79dd4178bb72087be564be742e79d08d51f
peer_review_resolutions:
  - finding_id: EN08-PR-01
    iteration: 1
    severity: P1
    title: The mutation gate does not explicitly preserve the P0 pause rule
    status: applied
    location: U2 Approach and Test scenarios
  - finding_id: EN08-PR-02
    iteration: 1
    severity: P2
    title: Multiple lite-gate override reasons lack a canonical encoding
    status: applied
    location: U1 Approach and JSON envelope definition
  - finding_id: EN08-PR-03
    iteration: 2
    severity: P1
    title: The mandatory lite_gate line is omitted for non-lite runs
    status: applied
    location: U1 Goal, Approach, Test scenarios
  - finding_id: EN08-PR-04
    iteration: 2
    severity: P2
    title: The mutation rule contradicts its permitted auto-fix behavior
    status: applied
    location: U2 Approach
  - finding_id: EN08-PR-05
    iteration: 3
    severity: P1
    title: The applied set is recorded too late to form a fail-closed mutation boundary
    status: applied
    location: U2 Approach and Test scenarios
  - finding_id: EN08-PR-06
    iteration: 3
    severity: P2
    title: The review_fixes line and applied_fixes envelope can disagree
    status: applied
    location: U2 Approach and Test scenarios
depth: standard
data_scale: small
---

# EN08 - en-review: lite-gate transparency + auditable mutation boundary

## Context

Two failures were field-observed on a `/en-review --lite` interactive run (Fable host):

1. **Silent lite-gate override.** `--lite` is fail-closed by design (`references/diff-signal-detection.md`): conditional personas fired (security + performance) so the full 7-agent roster ran. Correct behavior - but the skill **never surfaced why**; the user had to infer the override from the agent list. A silent decision instead of a recorded one.
2. **Mutation-boundary breach.** The reviewing agent implemented findings wholesale. The contract (severity.md action matrix + the SKILL's mode rules) allows interactive mode to auto-apply `safe_auto` (and `gated_auto` only with a one-line announcement the user can decline); `manual` findings require the user's explicit decision; headless is `safe_auto`-only; report-only applies nothing. That boundary is **prose with no hard gate**, so a weaker-adherence run walked straight through it.

This is the EN07 lesson (D41: the defect is the silence, not the skip) replayed on `/en-review`. The fix is the same shape: **mandatory visible outcome lines + a recorded applied-set + fail-closed boundary language, drift-tested** - not more prose.

## Decisions, assumptions & risks

- **Decision - outcome lines + envelope fields, no new bin/ verifier.** Unlike EN07, en-review runs in-session and does not commit, so there is no git-trailer surface to verify mechanically. The auditable artifacts here are (a) two mandatory outcome lines in the markdown summary (`lite_gate:`, `review_fixes:`), (b) matching JSON-envelope fields (`lite_gate`, `applied_fixes[]`), and (c) explicit fail-closed boundary language - all pinned by a drift test on the skill/reference text. Lean by design; a bash verifier would have nothing durable to inspect.
- **Decision - the mutation boundary follows severity.md's existing action matrix, not a flat "safe_auto only" rule.** severity.md already grants interactive `gated_auto` apply-with-announcement (user can decline/revert) and pauses even `safe_auto` on P0. EN08 does not change the matrix; it makes every application **recorded and attributable**: each applied finding ID is listed with its tier, and the post-review working-tree delta must not exceed the recorded applied set. Headless stays `safe_auto`-only; report-only stays zero-mutation.
- **Decision - the `lite_gate:` override reason enum mirrors `diff-signal-detection.md`.** One source of truth for why `is_small_and_safe` is false: `unknown-line-count`, `exec-lines-out-of-range`, `uncounted-files`, `risk-signal`, plus en-review's own `conditional-persona:<names>`. No new taxonomy invented in the SKILL.
- **Assumption - drift tests on skill text are the right enforcement tier here.** They cannot stop a live agent mid-run, but they pin the contract so every future session loads unambiguous, load-bearing instructions (and they caught exactly this class of rot in EN07). Runtime enforcement (a wrapper that diffs the tree against the applied set) is deliberately out of scope - see below.
- **Risk - outcome-line names drift from EN07's precedent.** *Mitigation:* same naming style as `simplify_pass:` / `branch_review_pass:` (snake_case key, enum value, parenthesized reason), asserted verbatim by the drift test.

## Out of scope (deliberately)

- **A runtime tree-diff enforcer** (mechanically reverting edits beyond the applied set mid-session) - no stable artifact surface for it; revisit if breaches recur after the contract hardening.
- **Changing severity.md's action matrix** - the tiers and their per-severity actions are unchanged; EN08 only makes applications auditable.
- **Changing the lite gate's fail-closed classification** - the gate stays exactly as defined in diff-signal-detection.md; EN08 only makes the outcome visible.
- **Touching en-build/en-simplify** - EN07 territory, already shipped.

## Implementation units

### U1. Lite-gate transparency (`lite_gate:` outcome line)

- **Goal:** `/en-review` emits exactly one mandatory `lite_gate:` outcome line on EVERY run - `applied` / `overridden (<reasons>)` / `not-requested` - and the override-reason enum mirrors diff-signal-detection.md.
- **Requirements covered:** none (addresses user requirement Req 1).
- **Dependencies:** none.
- **Files:** `skills/en-review/SKILL.md`, `references/diff-signal-detection.md`, `tests/lint/en-review-mutation-gate.test.sh` (new).
- **Approach:** In SKILL.md step 7a, add: EVERY run emits exactly ONE `lite_gate:` markdown outcome line - `lite_gate: applied` (roster collapsed), `lite_gate: overridden (<reasons>)` (`--lite` requested but the gate won), or `lite_gate: not-requested` (no `--lite` flag) - so a missing line is always distinguishable from a not-requested lite. Never a silent override. **Canonical multi-reason grammar (deterministic, parseable):** `<reasons>` is a comma+space-separated list of enum values in the FIXED canonical order `unknown-line-count, exec-lines-out-of-range, uncounted-files, risk-signal, conditional-persona:<names>`, deduplicated, always exactly one space after `overridden` before `(`; `<names>` in `conditional-persona:` is the alphabetically-sorted `+`-joined persona list (e.g. `conditional-persona:performance+security`). Example: `lite_gate: overridden (risk-signal, conditional-persona:performance+security)`. **JSON envelope carries the structured form:** `"lite_gate": {"outcome": "applied" | "overridden" | "not-requested", "reasons": []}` (reasons array in the same canonical order; empty for applied/not-requested) - the markdown line is derived from it. Add a `lite_gate:` line to the markdown-summary example. In diff-signal-detection.md, name the false-reasons as that canonical enum (they already exist as prose; give them stable identifiers). Drift test asserts: the outcome line is documented as mandatory; the enum values appear in both files; the canonical order + `+`-joined sorted persona-name encoding is stated; the structured envelope field documented; "never a silent override" language present.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - Happy path: SKILL.md documents `lite_gate: applied` for a collapsed roster AND requires exactly one `lite_gate:` line on every run, with `not-requested` for runs without `--lite`. (drift guard asserts all three values + the every-run rule)
  - Edge - override: `lite_gate: overridden (<reasons>)` with the enum mirrored from diff-signal-detection.md, including `conditional-persona:<names>`. (drift guard asserts enum values in both files)
  - Edge - multi-reason grammar: canonical order, comma+space separation, dedup, and alphabetical `+`-joined persona names are all stated. (drift guard asserts the grammar clauses)
  - Error path - silence forbidden: "never a silent override" (or equivalent) stated. (drift guard asserts it)
  - Integration - envelope: the JSON envelope documents the structured `lite_gate` object (`outcome` + `reasons[]`) including `not-requested` for runs without `--lite`, and the markdown line is derived from it. (drift guard asserts the field)
- **Verification:** `tests/lint/en-review-mutation-gate.test.sh` passes (ends with `report`); `bash tests/run.sh` green; `bin/ensemble-lint --scope docs/` exit 0.

### U2. Auditable mutation boundary (`review_fixes:` outcome line + `applied_fixes[]`)

- **Goal:** Every en-review run records exactly what it applied: a mandatory `review_fixes:` outcome line and an `applied_fixes[]` envelope field listing applied finding IDs with tiers; the post-review working-tree delta must not exceed the recorded set; per-mode boundaries stated fail-closed.
- **Requirements covered:** none (addresses user requirement Req 2).
- **Dependencies:** U1 (same drift-test file; U1 creates it).
- **Files:** `skills/en-review/SKILL.md`, `references/persona-dispatch.md`, `tests/lint/en-review-mutation-gate.test.sh` (extend).
- **Approach:** In SKILL.md's apply step and "Mutation rules per mode" section: (a) add the mandatory outcome line - `review_fixes: applied <N> (<finding-ids with tiers>)` / `review_fixes: none` / `review_fixes: none (report-only)`; (b) add `applied_fixes: []` to the JSON envelope (objects `{finding_id, tier, files[]}`); (c) define the **two-phase mutation protocol** so the record is a boundary, not a post-hoc assertion: **phase 1 (before ANY edit)** - capture the pre-review working-tree state (`git status --porcelain` + `git stash create` or equivalent snapshot ref) and freeze the mode-permitted finding set (the only findings whose fixes MAY be applied this run); **phase 2 (apply)** - edit only within the frozen set, stopping before touching any unapproved finding or file; `applied_fixes[]` is then derived from the ACTUAL before-vs-after tree delta (not from intent), and pre-existing dirty-tree changes are explicitly excluded from attribution; **consistency invariants** - `<N>` in the markdown line MUST equal the count of unique `applied_fixes[]` entries, the line is DERIVED from the array (finding IDs in ascending ID order, each as `<finding_id>/<tier>`, comma+space separated; `files[]` per entry sorted + deduplicated), and both `review_fixes: none` forms REQUIRE `applied_fixes: []`; interactive may auto-apply `safe_auto` (and `gated_auto` only with the severity.md one-line announcement the user can decline); `manual` findings are NEVER applied without the user's explicit pick; headless applies `safe_auto` ONLY; report-only applies NOTHING; **any P0 finding halts ALL automatic mutation - including `safe_auto` and `gated_auto` - until severity.md's P0 pause-and-ask handling occurs** (this pins the existing severity.md P0 row inside the gate rather than leaving it referenced-only); and the precise implementation boundary: **en-review MUST NOT implement findings outside the mode-permitted, announced, and recorded `applied_fixes[]` set - wholesale implementation of findings is a contract violation** (scoped wording: permitted auto-fixes per the severity.md action matrix are in-contract; anything beyond them is implementing, which belongs to `/en-build`/`/en-resolve-pr`, not review). Reference severity.md for the tier definitions (do not duplicate the matrix). Mirror the boundary sentence in persona-dispatch.md where mode selection is defined. Add the `review_fixes:` line to the markdown-summary example. Drift test asserts all of the above, including the P0-halts-all-auto-mutation rule.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - Happy path: SKILL.md documents `review_fixes:` with the applied-IDs form and the `applied_fixes[]` envelope field. (drift guard asserts both)
  - Edge - report-only: `review_fixes: none (report-only)` documented. (drift guard asserts it)
  - Edge - headless: headless is safe_auto-ONLY, stated explicitly. (drift guard asserts it)
  - Error path - boundary: "manual findings are never applied without the user's explicit pick" + "working-tree delta must not exceed the recorded applied set" + the scoped implementation boundary ("must not implement findings outside the mode-permitted, announced, and recorded applied_fixes set"; wholesale implementation is a contract violation). (drift guard asserts the scoped wording, not a blanket "never implements" that would contradict the severity.md matrix)
  - Error path - P0 halt: a P0 finding halts all automatic mutation (even safe_auto/gated_auto) until the severity.md P0 pause-and-ask occurs. (drift guard asserts the rule)
  - Error path - two-phase protocol: the pre-review baseline + frozen permitted set precede ANY edit; applied_fixes[] derives from the actual before-vs-after delta; pre-existing dirty changes are excluded. (drift guard asserts the ordering + baseline + exclusion clauses)
  - Edge - consistency invariants: N equals the unique applied_fixes[] count; the markdown line derives from the array (ascending ID order, <finding_id>/<tier>, comma+space; files[] sorted+deduped); both none forms require applied_fixes: []. (drift guard asserts the invariants)
  - Integration - severity.md referenced for tiers, not duplicated; persona-dispatch.md carries the boundary sentence. (drift guard asserts the reference + the mirror)
- **Verification:** `tests/lint/en-review-mutation-gate.test.sh` passes; `bash tests/run.sh` green; `bin/ensemble-lint --scope docs/` exit 0.

### U3. Foundation D42

- **Goal:** Record decision D42: the en-review transparency + mutation-boundary gate, cross-referencing D41's prose-to-auditable-gate pattern.
- **Requirements covered:** none (decision record).
- **Dependencies:** U2.
- **Files:** `docs/foundation.md`, `tests/lint/en-review-mutation-gate.test.sh` (extend).
- **Approach:** Add **D42** after D41: the two field failures (silent lite override, wholesale implementation), the two mandatory outcome lines (`lite_gate:`, `review_fixes:`) + envelope fields (`lite_gate`, `applied_fixes[]`), the per-mode fail-closed mutation boundary (interactive safe_auto + announced gated_auto; headless safe_auto-only; report-only zero; manual never without the user's pick; P0 halts all auto-mutation), the reason-enum mirror of diff-signal-detection.md, and the explicit statement that this applies D41's pattern (visible outcome line + fail-closed rule instead of prose) to `/en-review`. Extend the drift test to assert D42 exists and names the key facets.
- **Risk:** low
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - Happy path: foundation has D42 naming both outcome lines + the mutation boundary. (drift guard asserts)
  - Integration - D42 cross-references D41's pattern. (drift guard asserts the D41 reference)
  - **Test expectation:** covered by the drift guard above - this is a decision-record unit.
- **Verification:** `tests/lint/en-review-mutation-gate.test.sh` passes; `bin/ensemble-lint --scope docs/` exit 0; foundation shows D42.

## Verification (whole plan)

- `bash tests/run.sh` - full suite green (new: `tests/lint/en-review-mutation-gate.test.sh`).
- `bin/ensemble-lint --scope docs/` - exit 0.
- Manual spot-check: SKILL.md shows both mandatory outcome lines + envelope fields; diff-signal-detection.md names the reason enum; persona-dispatch.md mirrors the boundary; foundation shows D42; severity.md's matrix unchanged.
- Branch-level cross-agent review at build completion (D35/D41), with `review-verdict:` + `simplify-verdict:` trailers and the `--require-simplify` audit green (EN07's gate now applies to this build itself).
