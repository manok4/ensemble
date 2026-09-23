---
type: plan
plan_type: improvement
plan_id: EN07
title: en-build post-build simplify+review gate (auditable, not prose)
status: completed
location: active
created: 2026-07-07
shipped: 2026-07-07
deepened:
covers_requirements: []
requirements_pending: false
related_design:
peer_review_verdict: approve
peer_review_iterations: 1
peer_review_last_run: 2026-07-07
peer_review_plan_hash: 8b75b4fd36d1b889cb1ead86e2dea90014c40fe72a775c842544695823517283
peer_review_resolutions: []
depth: standard
data_scale: small
---

# EN07 - en-build post-build simplify+review gate (auditable, not prose)

## Context

`/en-build`'s post-build phase (step 10) requires a code-simplification pass (`/en-simplify`, step 10.2) and a branch-level Outside Voice review (`/en-review --peer-only`, step 10.3) in **prose**, but the only **mechanical** gate is the end-of-build evidence audit (step 10.5), which calls `bin/ensemble-verify-peer-evidence --branch-coverage` and inspects **review evidence only** (`review-verdict:` / per-unit peer trailers). It has **no concept of simplify**. The learning-checkpoint deferral guard (step 10, learning sub-step 1) likewise defers only on *peer-evidence* audit failure.

Consequence, field-observed on the EN06 build: the simplify pass can be skipped (or the branch review can silently run via single-agent fallback without recording why) and the build still finishes "clean" because the review trailer alone satisfies the audit. On EN06 the branch was docs-only, so simplify was *legitimately* not-applicable, but nothing recorded that decision, so a legitimate skip and an accidental miss are indistinguishable. **The defect is the silence, not the skip.**

This plan turns the prose requirement into an **auditable stop gate**: a durable `simplify-verdict:` git trailer (parallel to `review-verdict:`), a verifier that fails closed when simplify/review evidence is missing, two visible outcome lines, and a learning-checkpoint gate that blocks completion until the audit passes.

## Decisions, assumptions & risks

- **Decision (confirmed with user) - durable git trailers, not summary-line-only.** A visible `simplify_pass:` line alone is self-reported prose the agent can still drop under context pressure (the exact failure mode we are fixing). The machine-checkable source of truth is a `simplify-verdict:` trailer on the post-build commit; `bin/ensemble-verify-peer-evidence` fails the audit unless a valid `simplify-verdict:` AND a valid `review-verdict:` are both present. The two summary lines are the human-visible echo of the trailers, not the enforcement.
- **Decision - fail-closed behavior is flag-gated (`--require-simplify`), the new JSON fields are unconditional.** `--branch-coverage` is also called by `/en-ship`'s plan-completion checkpoint purely to read `covered_units`; making the new evidence mandatory unconditionally would break that caller and any legacy branch built before this change. So: `--branch-coverage --json` **always** additively emits `simplify_pass` + `branch_review_pass` (non-breaking), and only `--require-simplify` makes their absence/failure a non-zero exit. `/en-build` step 10.5 passes `--require-simplify`; `/en-ship` does not.
- **Decision - all four units are `risk: low`.** Every change is additive (a new trailer, a new validator function, a new opt-in flag, doc/skill prose) and reversible; nothing is destructive, gated, or touches production data. Keeping them all `low` also satisfies the phase invariant (U2/U3/U4 depend on U1; `risk(dep) <= risk(dependent)` holds only if U1 is not higher-risk than its dependents).
- **Assumption - the post-build commit carries both trailers.** en-build step 10.4 commits simplify+review together on one commit (empty `--allow-empty` when there were no changes), so `simplify-verdict:` and `review-verdict:` co-locate. The verifier derives `simplify_pass` from `simplify-verdict:` trailers found on the branch's `review-verdict:` commits.
- **Risk - a stricter verifier breaks existing green branches / callers.** *Mitigation:* the new emission and fail-closed behavior are opt-in (`--require-simplify`); the JSON additions are purely additive; the full drift suite + the verifier's own behavioral tests (`tests/peer-resolution-trailer/`) run before ship.
- **Risk - schema drift between the skill (emitter) and the verifier (validator).** *Mitigation:* one canonical schema documented in `references/build-orchestration.md`, asserted by drift tests on both sides (skill prose + verifier behavior), so emitter and validator cannot diverge silently.

## Technical design

### The `simplify-verdict:` trailer (new)

Emitted once on the post-build commit, alongside the existing `review-verdict:` trailer. Single-line JSON:

```
simplify-verdict: {"outcome":"completed","reason":"","findings_count":3,"units_covered":["U1","U2"]}
```

- `outcome` (required): `completed | not_applicable | failed`.
- `reason` (required non-empty when `outcome` is `not_applicable` or `failed`; empty allowed for `completed`): the recorded justification, e.g. `docs-only`, `trivial:<10-lines`, `--no-simplify`, `all-destructive-gated` (not_applicable) or a one-line failure note (failed).
- `findings_count` (required, non-negative integer): simplifier changes applied (0 for not_applicable).
- `units_covered` (required array of strings): ordinary U-IDs the simplify pass spanned (may be `[]` for not_applicable).

`validate_simplify_verdict()` mirrors the existing `validate_review_verdict()` in `bin/ensemble-verify-peer-evidence` (type-and-value validation; a malformed trailer is treated as missing, i.e. fail-closed).

### Derived audit fields (from existing + new trailers)

`bin/ensemble-verify-peer-evidence --branch-coverage <range> --json` gains two derived fields:

- `simplify_pass`: `completed | not_applicable | failed | missing` - from the `simplify-verdict:` trailer(s) on the branch's post-build commit(s); `missing` when no valid trailer is found.
- `branch_review_pass`: `completed | fallback_completed | failed | missing` - from the existing `review-verdict:` trailer's `reviewer`/`verdict`: `cross-agent` -> `completed`; `single-agent-fallback` / `en-review-host-fallback` -> `fallback_completed`; a fallback reviewer with a blank/absent reason -> `failed`; no valid review-verdict -> `missing`.

Under `--require-simplify`, the command exits non-zero (audit `failed`) when `simplify_pass` is `missing`/`failed` or `branch_review_pass` is `missing`/`failed`. Without the flag, behavior and exit codes are unchanged (backward-compatible) and the two fields are still emitted.

### Gate flow in `/en-build`

```
step 10.4  commit post-build changes with BOTH trailers:
             review-verdict: {...}   (existing)
             simplify-verdict: {...} (new; --no-simplify => outcome:not_applicable,reason:--no-simplify)
step 10.5  audit = ensemble-verify-peer-evidence --branch-coverage <mb>..HEAD --require-simplify --json
             surface covered_units + simplify_pass + branch_review_pass in the audit table
             audit verdict `failed` (simplify/review missing) => block the success path
step 10    learning checkpoint deferral guard: defer when the audit failed
             OR simplify_pass in {missing,failed} OR branch_review_pass in {missing,failed}
             => no learning checkpoint, no "/en-review -> /en-qa -> /en-ship" suggestion,
                next step becomes "/en-cross-review / re-run post-build simplify+review"
```

## Out of scope (deliberately)

- **Per-unit simplify evidence.** Simplify stays a branch-level pass (D35 / D29); this plan does not add a per-unit simplify trailer.
- **Changing what `/en-simplify` or `/en-review` do.** Only the *evidence and gate* around them change; the passes themselves are unchanged.
- **Auto-reverting on audit failure.** Consistent with the existing audit, the gate *surfaces and blocks the success path*; it does not auto-revert. The user decides.
- **Retrofitting historical branches.** The fail-closed behavior applies to new builds (opt-in `--require-simplify`); already-shipped branches are not re-audited.

## Implementation units

### U1. Verifier: `simplify-verdict` schema + derived pass fields + `--require-simplify`

- **Goal:** Teach `bin/ensemble-verify-peer-evidence` the `simplify-verdict:` trailer, emit `simplify_pass` + `branch_review_pass` in `--branch-coverage --json`, and fail closed under a new `--require-simplify` flag.
- **Requirements covered:** none (addresses user requirements Req 2 + Req 3, the mechanical half).
- **Dependencies:** none.
- **Files:** `bin/ensemble-verify-peer-evidence`, `tests/peer-resolution-trailer/verify-peer-evidence.test.sh` (extend).
- **Approach:** Add `validate_simplify_verdict()` mirroring `validate_review_verdict()` (validate `outcome` enum; require non-empty `reason` when outcome is not_applicable/failed; `findings_count` non-negative int; `units_covered` array of strings; malformed => treated as missing). In `--branch-coverage`: while scanning `review-verdict:` commits, also parse any `simplify-verdict:` trailer and the review-verdict `reviewer`; derive `simplify_pass` and `branch_review_pass` per the Technical design. Add `--require-simplify` to the arg parser; when set, exit non-zero if either derived field is `missing`/`failed`. Extend the `--json` object (both branch-coverage and, harmlessly, keep single-commit output unchanged). Update the usage/`--help` header block to document the new trailer, flag, and fields.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - Happy path: a branch whose post-build commit has valid `review-verdict:` (reviewer `cross-agent`) + `simplify-verdict:` (outcome `completed`) => `--branch-coverage --json` reports `simplify_pass:completed`, `branch_review_pass:completed`; `--require-simplify` exits 0.
  - Edge - not_applicable: `simplify-verdict:` outcome `not_applicable`, reason `docs-only` => `simplify_pass:not_applicable`; `--require-simplify` exits 0 (a recorded skip passes).
  - Edge - fallback review: `review-verdict:` reviewer `single-agent-fallback` => `branch_review_pass:fallback_completed`; exits 0. Same reviewer with blank reason => `branch_review_pass:failed`; `--require-simplify` exits non-zero.
  - Error path - missing simplify: post-build commit has `review-verdict:` but no `simplify-verdict:` => `simplify_pass:missing`; `--require-simplify` exits non-zero (this is the exact EN06 hole).
  - Error path - malformed: a `simplify-verdict:` with an invalid `outcome` or a not_applicable missing its reason => treated as `missing`/invalid; `--require-simplify` exits non-zero.
  - Integration - backward compat: without `--require-simplify`, exit codes for existing fixtures are unchanged; `covered_units` still emitted; `/en-ship`'s read-only `--branch-coverage` call is unaffected.
- **Verification:** `bash tests/peer-resolution-trailer/verify-peer-evidence.test.sh` passes (ends with `report`); `bash tests/run.sh` green; the new/changed fixtures exercise all outcome branches.

### U2. en-build: emit the trailer, consume the audit, gate the checkpoint

- **Goal:** en-build step 10.4 emits `simplify-verdict:`; step 10.5 passes `--require-simplify`, surfaces `simplify_pass` + `branch_review_pass`, and treats a `failed` audit as blocking; the learning-checkpoint deferral guard also defers on missing/failed simplify or review.
- **Requirements covered:** none (addresses user requirements Req 1, Req 3, Req 4).
- **Dependencies:** U1.
- **Files:** `skills/en-build/SKILL.md`, `tests/lint/en-build-simplify-gate.test.sh` (new).
- **Approach:** In step 10.4, document emitting the `simplify-verdict:` trailer next to `review-verdict:` on the post-build commit, with the outcome/reason rules (`--no-simplify` => `not_applicable (--no-simplify)`; docs-only/trivial => `not_applicable (<reason>)`; all-destructive-gated branch => `not_applicable (all-destructive-gated)`; a real simplifier failure => `failed`). In step 10.5, change the audit invocation to `--require-simplify`, add `simplify_pass:` and `branch_review_pass:` to the audit table, and state that a `failed` audit blocks the `/en-review -> /en-qa -> /en-ship` success path. Add the two visible outcome lines to the build summary. Extend the learning-checkpoint deferral guard (step 10 learning sub-step 1) to defer when `simplify_pass` in {missing,failed} or `branch_review_pass` in {missing,failed}. Update the `--no-simplify` / `--no-peer` flag rows to state each records a visible, recorded skip (never silence). New drift test asserts all of the above prose is present.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - Happy path: SKILL.md step 10.4 documents emitting `simplify-verdict:` with the outcome enum + reason rules. (drift guard asserts the trailer name + `completed|not_applicable|failed`)
  - Edge - explicit opt-out: `--no-simplify` records `not_applicable (--no-simplify)` (visible), never silence. (drift guard asserts the recorded-skip language)
  - Edge - audit consumption: step 10.5 invokes `--require-simplify` and surfaces `simplify_pass` + `branch_review_pass`. (drift guard asserts the flag + both field names)
  - Error path - gate: a `failed` audit blocks the success path and the learning checkpoint defers on missing/failed simplify or review. (drift guard asserts the deferral-guard extension)
  - Integration - fallback: step 10 documents that a fallback review maps to `branch_review_pass: fallback_completed` and must record why. (drift guard asserts the fallback mapping)
- **Verification:** `tests/lint/en-build-simplify-gate.test.sh` passes (ends with `report`); `bash tests/run.sh` green.

### U3. Document the trailer schema in the build references

- **Goal:** Document the `simplify-verdict:` trailer next to `review-verdict:` so the emitter (skill) and validator (verifier) share one canonical schema.
- **Requirements covered:** none (addresses user requirement Req 2, documentation half).
- **Dependencies:** U1.
- **Files:** `references/build-orchestration.md`, `references/build-handoff.md`.
- **Approach:** In `build-orchestration.md`'s post-build section (where the `review-verdict:` trailer is shown), add the `simplify-verdict:` trailer with its JSON schema, the outcome enum, the reason rules, and the fallback-reviewer -> `branch_review_pass` mapping. Add the shared-verify-gate note in `build-handoff.md` (its "Trailers contract" section) so both flavors reference the same schema. Keep it a schema reference, not a duplicate of the skill process.
- **Risk:** low
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - **Test expectation:** none - documentation-only; the schema is asserted by U1's verifier test (behavior) and U2's drift test (skill prose). A dedicated drift assertion that `build-orchestration.md` contains `simplify-verdict` is added to U2's test to guard the reference too.
- **Verification:** `bin/ensemble-lint --scope docs/` exit 0 (references live under the plugin, but run lint to catch link/path drift); `bash tests/run.sh` green; manual check that the schema matches U1 exactly.

### U4. Foundation D41 + cross-references

- **Goal:** Record decision D41 (the auditable post-build simplify+review gate) and refine the cross-references in D26 (learning checkpoint) and D35 (branch-level review model).
- **Requirements covered:** none (decision record).
- **Dependencies:** U2.
- **Files:** `docs/foundation.md`, `tests/lint/en-build-simplify-gate.test.sh` (extend).
- **Approach:** Add **D41** after D40: the post-build gate makes the simplify + branch-review requirements auditable via the `simplify-verdict:` / `review-verdict:` trailers and `--require-simplify`; two visible outcome lines (`simplify_pass`, `branch_review_pass`); the learning checkpoint and success path are blocked until the audit passes; fallback reviews must record why. Note it hardens D35's branch-level model and gates D26's learning checkpoint. Extend the EN07 drift test to assert D41 exists and names the trailer + the gate.
- **Risk:** low
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - Happy path: foundation has D41 naming the `simplify-verdict:` trailer + the auditable gate. (drift guard asserts D41 exists and names the facets)
  - Integration - the "blocks the learning checkpoint / success path until audit passes" rule appears in D41. (drift guard asserts the gate language)
  - **Test expectation:** covered by the drift guard above - this is a decision-record unit.
- **Verification:** `tests/lint/en-build-simplify-gate.test.sh` passes; `bin/ensemble-lint --scope docs/` exit 0; foundation shows D41.

## Verification (whole plan)

- `bash tests/run.sh` - full suite green (new: `tests/lint/en-build-simplify-gate.test.sh`; extended: the verifier behavioral test).
- `bin/ensemble-lint --scope docs/` - exit 0.
- Manual spot-check: `bin/ensemble-verify-peer-evidence --branch-coverage <range> --json` emits `simplify_pass` + `branch_review_pass`; `--require-simplify` fails a branch whose post-build commit lacks a valid `simplify-verdict:`; en-build step 10 documents the emission, the `--require-simplify` audit, the two outcome lines, and the extended deferral guard; foundation shows D41.
- Self-referential check: building EN07 with `/en-build` must itself finish with `simplify_pass:` + `branch_review_pass:` visible in the summary (dogfood the gate we are adding).
- Branch-level cross-agent review at build completion (D35), verdict recorded via the `review-verdict:` trailer.
