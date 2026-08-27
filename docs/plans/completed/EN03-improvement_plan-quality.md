---
type: plan
plan_type: improvement
plan_id: EN03
title: Plan-quality upgrades to en-plan
status: completed
location: active
created: 2026-07-03
shipped: 2026-08-26
deepened:
covers_requirements: []
requirements_pending: false
related_design:
peer_review_verdict: approve
peer_review_iterations: 1
peer_review_last_run: 2026-07-03
peer_review_plan_hash: 230daa92e267b634c5f46e444ecb2094cf04d2cc11a64bbdf32384bd2e898902
peer_review_resolutions: []
depth: standard
data_scale: small
---

# EN03 - Plan-quality upgrades to en-plan

## Context

A head-to-head against compound-engineering's `ce-plan` found en-plan already leads on validation (cross-agent Outside Voice peer review — ce only self-deepens) and lifecycle (risk/gated classification, plan-hash, `draft→open→in_progress→completed`). ce's edge is entirely in **plan-content richness** — how thoroughly a single plan is specified before it ships. This plan adopts the three highest-leverage, lowest-overhead of those, deliberately keeping it lean.

The priority is **performance (plan→build quality) first, then speed, then cost**. All three upgrades honor that: two shift effort left (small plan cost, larger build/QA savings) and one self-gates to complex plans only.

**Branch/merge note.** This plan is cut from `main` and edits `skills/en-plan/SKILL.md` and `references/templates/plan-template.md`, which the in-flight skill-suite branch also edits — but in **different regions** (that branch added a brainstorm nudge near en-plan's request-sourcing step, and touched the plan-template Gated criteria). A merge should be trivial/auto-mergeable. This work is otherwise independent of the in-flight review-model branches.

## Out of scope for this plan (deliberately, to stay lean)

Adopted from ce only the three below. Explicitly **not** adopting: status-free plan model (our lifecycle is load-bearing across en-build/en-ship), unified single-artifact / in-plan Product Contract (foundation owns requirements — kept separate), input-classification / knowledge-work routing, approach-altitude, HTML rendering, CONCEPTS.md gap-fill, unit-index table, scoping-synthesis affirmability step.

## Approach (high-level)

Three targeted upgrades, each gated to avoid per-plan overhead:

1. **Test-scenario specificity gate** — feature units must carry real categorized test scenarios; a pre-write check + a mechanical lint rule enforce it. (Shift-left: the biggest build-quality lever.)
2. **Conditional "Decisions, assumptions & risks" section** — one optional plan section that appears only when there's real substance, giving research findings and inferred bets a reviewable home. (Omitted on trivial plans — no boilerplate tax.)
3. **Technical-design load-bearing audit** — architecture-complexity triggers require a plan-level Technical design section, verified at pre-write. (Self-gating: simple plans pay nothing.)

## Implementation units

Each unit has a stable U-ID. Never renumbered after assignment.

### U1. Test-scenario specificity gate

- **Goal:** Make every feature-bearing unit carry actual categorized test scenarios, enforced by a pre-write check and a mechanical lint rule, so plans hand en-build concrete test targets.
- **Requirements covered:** —
- **Dependencies:** none
- **Files:**
  - `references/templates/plan-template.md`
  - `skills/en-plan/SKILL.md`
  - `bin/ensemble-lint`
  - `references/doc-lints.md`
  - `docs/foundation.md` (decision record D37)
  - `tests/lint/en-plan-test-scenarios.test.sh` (new)
- **Approach:** In `plan-template.md`, specify that a **feature-bearing** unit's `Test scenarios:` must enumerate scenarios across the applicable categories — **happy path, edge cases, error/failure paths, integration** — each with concrete inputs/actions/expected outcomes. **Non-feature-bearing** units (config, scaffolding, styling, pure docs) use `Test expectation: none — <reason>` instead of scenarios. In `skills/en-plan/SKILL.md`, add a **pre-write check** (in the step-17 confidence-check / pre-write review area, before the step-14 peer pass finalizes) that flags any feature unit whose test scenarios are blank, a single vague line, or "none" without a reason → mark **incomplete**, fix before finalizing. Add a mechanical lint rule **`unit.test-scenarios`** to `bin/ensemble-lint` (**P2 advisory**): a `category: feature` unit whose `Test scenarios:` is empty or a single non-specific line AND that lacks the `Test expectation: none` escape is flagged; remediation names the four categories. Document the rule in `references/doc-lints.md`. Record foundation **D37** capturing all three EN03 upgrades. Keep it mechanical and lenient (advisory, not a P1 blocker) — the goal is a nudge toward real scenarios, not a gate that fails valid plans.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Patterns to follow:** ce-plan test-scenario specificity + AE-link convention; existing `bin/ensemble-lint` `unit.gated-flag` / `unit.risk-class` rules (same shape); `references/doc-lints.md` rule catalog
- **Test scenarios:**
  - *Happy path:* plan-template documents the four test-scenario categories + the `Test expectation: none — <reason>` escape for non-feature units.
  - *Happy path:* en-plan's pre-write check flags a feature unit with blank/single-line test scenarios as incomplete.
  - *Edge case:* a non-feature (`category: other`/config) unit with `Test expectation: none — <reason>` passes the lint rule (not flagged).
  - *Edge case:* a feature unit with a single vague line ("tests pass") is flagged; a feature unit with categorized scenarios is not.
  - *Error path:* the lint rule is P2 advisory (does not fail CI as P1); confirm severity.
  - *Integration:* `references/doc-lints.md` lists `unit.test-scenarios`; foundation D37 present.
- **Verification:** drift guard passes; `bash tests/run.sh` green; `bash bin/ensemble-lint --scope docs/` still exits 0 on the repo's own plans.

### U2. Conditional "Decisions, assumptions & risks" section

- **Goal:** Give non-obvious decisions, rejected alternatives, inferred assumptions, and real risks a single reviewable home — without taxing trivial plans.
- **Requirements covered:** —
- **Dependencies:** none
- **Files:**
  - `references/templates/plan-template.md`
  - `skills/en-plan/SKILL.md`
  - `tests/lint/en-plan-decisions-section.test.sh` (new)
- **Approach:** Add ONE **optional** plan-level section to `plan-template.md` — `## Decisions, assumptions & risks` — a lean bulleted list (not four heavyweight sub-sections). It appears **only when there is real substance**: a non-obvious technical decision, a road not taken (alternative + why rejected), an inferred assumption the plan bets on, or a genuine risk. The template explicitly marks it **optional — omit entirely on trivial plans**. In `skills/en-plan/SKILL.md`, instruct that when research (repo/learnings/web) surfaces a decision/alternative/assumption/risk, it **lands here** rather than scattered in unit `Approach:` fields; when there's nothing substantive, the section is omitted. No mandatory-section enforcement (that would be the per-plan overhead we're avoiding).
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Patterns to follow:** ce-plan KTDs / Alternatives / Assumptions / Risks (consolidated into one lean section for ensemble)
- **Test scenarios:**
  - *Happy path:* plan-template documents the optional `## Decisions, assumptions & risks` section with the four content types.
  - *Edge case:* the section is explicitly marked optional / "omit on trivial plans" (no lint rule forces it).
  - *Integration:* en-plan instructs research findings + inferred bets to land in this section rather than unit Approach fields.
- **Verification:** drift guard passes; `bash tests/run.sh` green.

### U3. Technical-design load-bearing audit

- **Goal:** Ensure complex plans carry a coherent cross-cutting architecture sketch, while simple plans pay nothing.
- **Requirements covered:** —
- **Dependencies:** none
- **Files:**
  - `skills/en-plan/SKILL.md`
  - `references/templates/plan-template.md`
  - `tests/lint/en-plan-technical-design.test.sh` (new)
- **Approach:** In `skills/en-plan/SKILL.md`, define **architecture-complexity triggers**: ≥3 new/changed components, a ≥3-step protocol/handshake, a state machine, ≥3 data-flow stages, or DSL/public-API design. When **any** trigger fires (typically Deep/high-risk plans), require a plan-level `## Technical design` section — a **directional** high-level sketch/structured description of the cross-cutting architecture (component boundaries, data flow, key interfaces), not a spec. Add a **pre-write review check** that **verifies the section is present when a trigger fired** (missing section + fired trigger = incomplete; fix before finalizing). Add the optional `## Technical design` section to `plan-template.md` (marked "present only when a complexity trigger fires"). **Self-gating:** simple plans never fire a trigger → the section is absent and nothing is flagged.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Patterns to follow:** ce-plan High-Level Technical Design load-bearing audit (trigger-count ≥ sketch-count)
- **Test scenarios:**
  - *Happy path:* en-plan documents the architecture-complexity triggers and the `## Technical design` requirement when they fire.
  - *Happy path:* the pre-write review verifies the section's presence when a trigger fired.
  - *Edge case:* a simple plan (no trigger) does not require the section — explicitly a no-op.
  - *Integration:* plan-template includes the optional `## Technical design` section marked trigger-gated.
- **Verification:** drift guard passes; `bash tests/run.sh` green.

## Phasing

Three units; `depth: standard` and unit count < 8 → **phasing off** (simple per-unit loop in dependency order). Zero gated/destructive units, so no safety gates fire. Risk mix: U1 medium, U2 low, U3 medium — no dependency edges, so the phase invariant is trivially satisfied.

Build order: U1 (headline — template categories + lint rule + pre-write check + foundation D37) → U2 (optional decisions section) → U3 (technical-design audit). All three touch `plan-template.md` and/or `en-plan/SKILL.md` in distinct regions; building in order keeps the same-file edits clean.

## Lifecycle

`draft → open → in_progress → completed`. `plan_id: EN03` is forced (the two in-flight plans aren't on `main` yet, so auto-increment would collide low). Independent of the in-flight stack; mergeable in parallel (trivial overlap with the skill-suite branch in en-plan/plan-template, different regions).
