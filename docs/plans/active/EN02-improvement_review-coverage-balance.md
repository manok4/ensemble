---
type: plan
plan_type: improvement
plan_id: EN02
title: Tiered peer-default code review with adversarial mode
status: in_progress
location: active
created: 2026-06-28
shipped:
deepened:
covers_requirements: []
requirements_pending: false
related_design:
peer_review_verdict: approve
peer_review_iterations: 1
peer_review_last_run: 2026-06-28
peer_review_plan_hash: 98113b5eddffdc5bd3997587f348735167b63ce40d9703ab30fe6dd1860375b9
peer_review_resolutions: []
depth: standard
data_scale: small
---

# EN02 - Tiered peer-default code review with adversarial mode

## Context

EN01 made `/en-review` lifecycle-aware (`--lite`, `--peer-only`, shared `references/diff-signal-detection.md`, the cross-agent peer machinery, and en-build's branch-level review-verdict model). A head-to-head against compound-engineering's `ce-code-review` showed ce is the stronger *standalone* reviewer — richer confidence model (discrete anchors + a quote-the-line evidence gate), an independent per-finding validator, cross-model adversarial review, thematic grouping, and more conditional reviewers — while en-review is leaner and cheaper.

EN02 closes the quality gap **without** reintroducing ce's always-on cost, by scaling review effort to the diff's risk and size. Two principles drive it: (1) **the peer is the default reviewer** — the host orchestrates and applies, but review judgment comes from the cross-agent Outside Voice (implementer ≠ reviewer), and (2) **host personas only join for high-stakes diffs**, where their independent findings are reconciled against the peer's to decide what's actually worth fixing.

**Builds on EN01.** This plan edits files EN01 already modified (`skills/en-review/SKILL.md`, `references/persona-dispatch.md`, `references/diff-signal-detection.md`, `skills/en-build/SKILL.md`, `references/build-orchestration.md`). It must be built on top of EN01 (this branch is cut from the EN01 branch). Do not build EN02 against `main` until EN01 has merged, or the en-review edits will conflict.

## Out of scope for this plan (follow-ups)

- Model tiering of reviewers (session vs mid-tier model overrides) — deliberately not adopted (EN earlier opted out of model tiers).
- ce's long tail of stack-specific reviewers (swift-iOS, etc.) — add later only if the codebase needs them.
- Replacing en-cross-review or en-build's per-unit destructive/gated peer pass — unchanged.

## Approach (high-level)

A three-tier review model, auto-selected from `references/diff-signal-detection.md`:

- **Lite** — small + zero risk signals → one narrow cross-agent peer call (correctness + standards dimensions).
- **Standard** (default) — normal diffs → one comprehensive cross-agent peer call (all matched dimensions, including conditionals expressed as brief dimensions).
- **Adversarial** — risk signals (auth / payments / migrations / data-mutation / external-API / secrets) OR diff ≥ ~150 lines OR `--adversarial` → host personas (parallel) **and** the cross-agent peer run independently, then reconcile.

The peer is the reviewer of record in Lite and Standard; the host only orchestrates and applies. Host personas enter solely in Adversarial (or as the no-peer fallback). A discrete-anchor confidence model with a quote-the-line evidence gate, thematic grouping, three new conditional reviewers, and an opt-in per-finding validator round out the coverage — each gated so routine reviews stay cheap.

## Implementation units

Each unit has a stable U-ID. Never renumbered after assignment.

### U1. Discrete confidence anchors + quote-the-line evidence gate

- **Goal:** Replace en-review's fuzzy 1–10 confidence with 5 discrete anchors and require verbatim evidence for high-confidence findings, cutting false positives.
- **Requirements covered:** —
- **Dependencies:** none
- **Files:**
  - `references/persona-dispatch.md`
  - `references/finding-schema.md`
  - `skills/en-review/SKILL.md`
  - `tests/lint/en-review-confidence-anchors.test.sh` (new)
- **Approach:** Define 5 discrete anchors with behavioral criteria: `0` (false positive — suppress), `25` (unverified — suppress), `50` (verified but nitpick/narrow), `75` (affects users/callers in normal use), `100` (verifiable from code alone). **Quote-the-line gate:** any finding at anchor 75 or 100 MUST carry a non-empty `first_evidence` (the verbatim motivating `file:line`); missing it demotes to 50. **Corroboration:** when ≥2 independent reviewers flag the same fingerprint, promote one anchor (`50→75→100`); promotion never bypasses the quote gate; the host fast-pass (anchor ≤50, already in EN01) never counts toward promotion. Update the confidence gate: suppress below anchor 75 EXCEPT P0 at 50+ (critical-but-uncertain must survive). **Preserve en-review's edge:** suppressed-but-real findings (anchor 50) are still filed as TD entries in `docs/plans/tech-debt-tracker.md`, not silently dropped. Keep the P0–P3 severity scale orthogonal to the anchor.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Execution note:** pragmatic
- **Patterns to follow:** ce-code-review `references/findings-schema.json` + `subagent-template.md` (anchor rubric, quote-the-line gate)
- **Test scenarios:**
  - The 5 anchors and their behavioral criteria are documented.
  - Quote-the-line gate: 75/100 requires `first_evidence`, else demote to 50.
  - Corroboration promotes one anchor; fast-pass never counts.
  - Confidence gate suppresses <75 except P0 at 50+.
  - Sub-threshold real findings still file as TD (en-review edge preserved).
- **Verification:** drift guard passes; `bash tests/run.sh` green.

### U2. Tiered review model + peer-as-default reviewer

- **Goal:** Make every non-adversarial review a single cross-agent peer pass (Lite/Standard), with the host orchestrating but never reviewing its own judgment.
- **Requirements covered:** —
- **Dependencies:** U1
- **Files:**
  - `skills/en-review/SKILL.md`
  - `references/diff-signal-detection.md`
  - `references/persona-dispatch.md`
  - `docs/foundation.md` (new decision record)
  - `tests/lint/en-review-tiered-model.test.sh` (new)
- **Approach:** Add an `is_high_stakes` classification to `diff-signal-detection.md` (true when any risk signal is present OR `EXEC_LINES ≥ 150` OR undetermined → fail-closed true). Restructure en-review's flow: after scope detection, classify the diff → select tier. **Lite** (`is_small_and_safe`): dispatch the cross-agent peer with a focused brief (correctness + standards dimensions). **Standard** (default, not high-stakes): dispatch the peer with the full brief (all matched dimensions, conditionals included as brief dimensions). In both, the host does NOT run personas — it builds the brief, dispatches the peer via `bin/ensemble-build-peer-prompt --artifact-type code` → `$PEER_CMD` (`ENSEMBLE_PEER_REVIEW=true`), applies the quote-the-line gate + confidence gate (U1), applies eligible fixes (D30 peer-reports/host-applies), re-verifies, files sub-threshold as TD. The optional host fast-pass may run as a cheap complement but is never the reviewer of record. Record a new foundation decision (D36) capturing the tiered peer-default model. Document the tier auto-selection and that `--adversarial` forces the Adversarial tier (built in U3).
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Execution note:** pragmatic
- **Patterns to follow:** EN01 `references/diff-signal-detection.md` (fail-closed classifier); `references/outside-voice.md` (peer dispatch)
- **Test scenarios:**
  - `diff-signal-detection.md` defines `is_high_stakes` with the documented triggers, fail-closed.
  - Lite + Standard are peer-only; host personas not dispatched in either.
  - The host dispatches the peer via ensemble-build-peer-prompt + PEER_CMD.
  - Tier auto-selection documented; `--adversarial` forces Adversarial.
  - Foundation D36 records the tiered peer-default model.
- **Verification:** drift guard passes; `bash tests/run.sh` green.

### U3. Adversarial reconciliation (host + peer, both independent)

- **Goal:** On high-stakes diffs, run host personas and the cross-agent peer independently, then reconcile the two sets to decide what's worth fixing.
- **Requirements covered:** —
- **Dependencies:** U1, U2
- **Files:**
  - `skills/en-review/SKILL.md`
  - `references/persona-dispatch.md`
  - `references/adversarial-reconciliation.md` (new)
  - `tests/lint/en-review-adversarial.test.sh` (new)
- **Approach:** When the Adversarial tier is selected (high-stakes or `--adversarial`): dispatch the host persona roster (parallel) to produce finding set H AND the cross-agent peer to produce set P — **independently** (the peer never sees H first; true second opinion). Reconcile per a new `references/adversarial-reconciliation.md`: dedup by fingerprint (file + line±3 + normalized title); **agreement** (both flag same fingerprint) → promote one anchor and mark `worth_fixing` (cross-MODEL agreement between peer and an in-process adversarial read is the strongest signal); **single-source** findings → a short adversarial judgment ("real AND worth fixing?") that survives only with quote-the-line evidence, else demote to advisory or file as TD. The reconciled set flows into the existing synthesis (grouping in U5, output). Record the reconciliation in the result so the reviewer mix is visible.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Execution note:** pragmatic
- **Patterns to follow:** ce-code-review Stage 5 cross-reviewer agreement + `cross-model-review.md`
- **Test scenarios:**
  - Adversarial tier dispatches host personas AND the peer independently.
  - Agreement promotes one anchor and marks worth_fixing.
  - Single-source findings need quote-the-line evidence to survive; else demote/TD.
  - Reconciliation reference documents the fingerprint + agreement rules.
- **Verification:** drift guard passes; `bash tests/run.sh` green.

### U4. Three new conditional reviewers (api-contract, reliability, frontend-races)

- **Goal:** Broaden coverage with three conditional reviewers that fire only when the diff matches, so unrelated diffs pay nothing.
- **Requirements covered:** —
- **Dependencies:** U2
- **Files:**
  - `agents/api-contract-reviewer.md` (new)
  - `agents/reliability-reviewer.md` (new)
  - `agents/frontend-races-reviewer.md` (new)
  - `references/persona-dispatch.md`
  - `references/diff-signal-detection.md`
  - `tests/lint/en-review-new-reviewers.test.sh` (new)
- **Approach:** Add three persona files mirroring the existing reviewer-agent shape (identity, what to flag, calibration, suppress conditions, returns findings JSON): **api-contract** (routes/serializers/public type signatures/versioning/generated-client breaks), **reliability** (error handling/retries/timeouts/background jobs/queues/idempotency), **frontend-races** (async UI / DOM events / client state — generalized to React/Vue/Svelte async patterns, not just Stimulus/Turbo). Add their trigger patterns to `diff-signal-detection.md` and the conditional roster in `persona-dispatch.md`. **Dual expression:** in peer-only tiers they're dimensions in the peer brief (no extra agents); in Adversarial they're dispatched as host persona subagents. Each fires only when the diff matches its patterns.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Execution note:** pragmatic
- **Patterns to follow:** ce-code-review `references/personas/{api-contract,reliability,julik-frontend-races}-reviewer.md`; existing ensemble `agents/security-reviewer.md` shape
- **Test scenarios:**
  - Three new persona files exist with the standard reviewer shape.
  - Trigger patterns added to diff-signal-detection + persona-dispatch.
  - They fire only when the diff matches (conditional, zero cost otherwise).
  - Documented as both peer-brief dimensions and adversarial host personas.
- **Verification:** drift guard passes; `bash tests/run.sh` green.

### U5. Thematic triage grouping in output

- **Goal:** Group related findings by root cause / fix path so the reader sees "fix this first, it resolves these three" instead of a flat list.
- **Requirements covered:** —
- **Dependencies:** U1
- **Files:**
  - `skills/en-review/SKILL.md`
  - `references/persona-dispatch.md`
  - `tests/lint/en-review-grouping.test.sh` (new)
- **Approach:** After dedup/promotion/gating, build triage groups (Stage-5-style): a group has a short title, the included stable finding `#`s, one-line context, preferred resolution, and why. Grouping never merges findings into a synthetic finding and never changes a finding's severity/anchor/route; a finding appears in at most one group. Trigger on distinct concerns (shared root cause, subsystem, fix path, dependency order), not item count. `grouping:auto` default; `grouping:off` / `grouping:always` tokens. Prune groups whose findings were dropped (post-validation) or applied (post-apply). Add to both the markdown report and the JSON envelope.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Execution note:** pragmatic
- **Patterns to follow:** ce-code-review Stage 5 step 9b (triage grouping)
- **Test scenarios:**
  - Grouping documented: groups reference stable `#`s, never merge/alter findings.
  - grouping:auto/off/always tokens documented.
  - Group pruning post-validation / post-apply documented.
  - Both markdown + JSON envelope carry triage_groups.
- **Verification:** drift guard passes; `bash tests/run.sh` green.

### U6. Opt-in `--validate` per-finding validator

- **Goal:** Offer a false-positive sweep that independently re-checks findings, kept off the hot path so routine reviews stay fast.
- **Requirements covered:** —
- **Dependencies:** U1
- **Files:**
  - `skills/en-review/SKILL.md`
  - `references/validator-dispatch.md` (new)
  - `tests/lint/en-review-validator.test.sh` (new)
- **Approach:** Add a `--validate` flag and an auto-on-for-P0/P1 default (capped at ~10, prioritizing P0/P1). For each in-scope finding, dispatch a validator that answers three questions: is the issue real in the code as written? introduced by THIS diff? not handled elsewhere? Returns `{validated, reason}`. Drop `validated:false` findings — but only P2/P3; keep P0/P1 even on validator infra failure (transient failure must never silently remove critical/high). Document the cost trade-off (N extra subagent calls) and that it's off by default for routine reviews. Prune dropped findings from triage groups (U5).
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Execution note:** pragmatic
- **Patterns to follow:** ce-code-review Stage 5b + `validator-template.md`
- **Test scenarios:**
  - `--validate` flag + auto-on-for-P0/P1 (capped) documented.
  - Validator re-checks real / introduced-by-diff / not-handled-elsewhere.
  - Drops P2/P3 on validated:false; keeps P0/P1 on infra failure.
  - Off the hot path by default; cost trade-off documented.
- **Verification:** drift guard passes; `bash tests/run.sh` green.

### U7. en-build adversarial escalation on high-stakes branches

- **Goal:** Have en-build's post-build review escalate from peer-only to adversarial when the branch diff is high-stakes, while keeping peer-only the default.
- **Requirements covered:** —
- **Dependencies:** U3
- **Files:**
  - `skills/en-build/SKILL.md`
  - `references/build-orchestration.md`
  - `docs/foundation.md` (D35 amendment)
  - `tests/lint/en-build-review-model.test.sh` (extend)
- **Approach:** In en-build's post-build phase (step 10.3), classify the branch diff via `diff-signal-detection.md`. Default stays `/en-review --peer-only` (implementer ≠ reviewer). When `is_high_stakes` is true, escalate to `/en-review --adversarial`: the implementer's fresh-context host self-read + the independent cross-agent peer + reconciliation (U3). The `review-verdict:` trailer's `reviewer` reflects the mode (`cross-agent` peer-only vs `adversarial`). Amend foundation D35 to note the escalation. Keep the no-peer fallback unchanged.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Execution note:** pragmatic
- **Patterns to follow:** EN01 U3 post-build phase; EN01 D35
- **Test scenarios:**
  - Post-build review stays --peer-only by default.
  - Escalates to --adversarial when the branch diff is_high_stakes.
  - review-verdict reviewer reflects peer-only vs adversarial.
  - Foundation D35 amended for the escalation.
- **Verification:** drift guard passes; `bash tests/run.sh` green.

## Phasing

All seven units are `risk: medium` (P2) — a cohesive review-flow refactor; none is low-risk doc-only or destructive. With 7 units (< 8) and `depth: standard`, **phasing is off**: a simple per-unit loop in dependency order. Universal safety gates still apply per unit (none here — zero gated/destructive units).

Dependency-respecting build order: U1 → U2 (needs U1) → U3 (needs U1, U2) → U4 (needs U2) → U5 (needs U1) → U6 (needs U1) → U7 (needs U3). U1 and U2 are the structural core (confidence model, then the tier/peer-default flow); U3 layers adversarial reconciliation; U4–U6 are additive coverage features; U7 wires en-build to the new adversarial mode.

## Lifecycle

`draft → open → in_progress → completed`. `plan_id_prefix: EN` (foundation). Builds on EN01 — cut from the EN01 branch; build/merge after or alongside EN01 so the shared en-review edits stack rather than conflict.
