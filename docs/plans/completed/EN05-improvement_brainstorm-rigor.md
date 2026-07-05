---
type: plan
plan_type: improvement
plan_id: EN05
title: Brainstorm rigor upgrades from ce-brainstorm + explicit priority principle
status: completed
location: completed
created: 2026-07-04
shipped: 2026-07-05
deepened:
covers_requirements: []
requirements_pending: false
related_design:
peer_review_verdict: approve
peer_review_iterations: 1
peer_review_last_run: 2026-07-04
peer_review_plan_hash: d09489eb76fd8019ab1dadd1cd8d345063fc12fc29af66481b4fe36f0f5d3c20
peer_review_resolutions: []
depth: standard
data_scale: small
---

# EN05 - Brainstorm rigor upgrades from ce-brainstorm + explicit priority principle

## Context

A head-to-head of `/en-brainstorm` (92 lines) against compound-engineering's `ce-brainstorm` (318 lines + 9 reference files) found en-brainstorm's core loop sound and its leanness a genuine asset - it feeds the compounding learnings wiki (capture-from-synthesis, D21), has a sharp devil's-advocate pass, and keeps a clean design-doc → `/en-foundation`/`/en-plan` handoff. ce-brainstorm is clearly ahead on exactly **one** thing: **pre-approach product rigor** - it doesn't just interview, it pressure-tests whether the idea is real and well-framed before generating approaches.

EN05 adopts the 3–4 highest-leverage, lowest-overhead of ce-brainstorm's ideas - mirroring how EN03 adopted `ce-plan`'s best ideas - while deliberately staying lean (NOT growing en-brainstorm toward 318 lines). Every upgrade is **self-gating**: it fires only when it adds value, so a simple, well-framed brainstorm pays no tax.

It also makes explicit a principle that already implicitly drives EN03/EN05: **performance > speed ≥ cost** (plan/brainstorm quality first, then speed, then cost) - stated in both `/en-brainstorm` and `/en-plan` and recorded as a foundation decision.

## Out of scope for this plan (deliberately NOT adopted from ce-brainstorm)

These would over-build the lean loop; each is noted so future readers see it was a considered choice, not an oversight:

- **Visual probes** - ce's display-only Node browser sketch server (`visual-probe-server.js`) for spatial topics. Heavy infrastructure for a CLI-oriented suite.
- **HTML output mode + precedence chain** - a webpage version of the doc with a multi-source format-resolution chain. Markdown is sufficient.
- **Universal / non-software brainstorming route** - en-brainstorm is deliberately scoped to engineering work.
- **Model tiers** (extraction / generation / ceiling) - over-engineering for brainstorm.
- **Async grounding-scout dossier** - en-brainstorm's inline existing-context scan (foundation + learnings + commits) is lighter and already leverages the compounding memory.
- **Unified single-artifact model** - already rejected in EN03: foundation owns requirements; keep the design doc and the plan separate.

## Approach (high-level)

Four units, all `risk: low`, sequenced so the shared `skills/en-brainstorm/SKILL.md` is edited in dependency order (avoids same-file churn conflicts):

- **U1** adds the **Product Pressure Test** (rigor-gap taxonomy) - the headline adoption.
- **U2** adds the **integration check** + the **verify-before-claiming** guardrail.
- **U3** upgrades the Q&A loop to **default to the host's blocking question tool** (`$QUESTION_TOOL`, host-neutral) with an open-vs-closed discipline.
- **U4** states the **performance > speed ≥ cost** principle in en-brainstorm and en-plan, and records foundation **D39**.

## Decisions, assumptions & risks

- **Decision - adopt only the rigor ideas, not the machinery.** ce-brainstorm's value for Ensemble is its product-rigor lenses; its infrastructure (visual server, HTML, model tiers, dossier, unified artifact) is either out of scope or already-rejected. EN05 lifts the ideas, cites provenance, and copies none of the heavy machinery.
- **Decision - self-gating everywhere.** Each upgrade fires only when a real gap/consequence/claim exists, and depth-scales (e.g. the durability gap is Deep-only). A well-framed Lightweight brainstorm sees none of it. This protects the "leave with clarity, not ceremony" property that makes en-brainstorm good.
- **Decision - keep the rigor gaps as internal analysis surfaced as open-ended probes**, not a user-facing checklist. A menu would signal which evidence "counts" and let the user pick rather than produce; an open probe forces real observation. (Directly from ce's Interaction Rule 5.)
- **Assumption - AskUserQuestion is available and idiomatic.** Confirmed: already used by en-resolve-pr, en-simplify, en-debug, and host-detect documents it. The open-vs-closed rule keeps genuinely-narrative questions open-ended.
- **Risk - scope creep toward ce's weight.** *Mitigation:* the explicit out-of-scope list above + the self-gating requirement; drift tests assert the rigor steps exist but the plan caps the additions.
- **Risk - the rigor probes annoy on simple work.** *Mitigation:* self-gating (zero probes on a well-framed opening) + depth-scaling; a Lightweight brainstorm is unaffected.

## Technical design

Where each upgrade lands in en-brainstorm's existing flow:

```
1-4  detect host / recursion guard / right-size depth / existing-context scan   (unchanged)
5    Q&A loop  ──────────────────────────────► U3: default to AskUserQuestion; open-vs-closed discipline
5a   Product pressure test (NEW)  ────────────► U1: fire one open-ended probe per rigor gap that exists
5b   Integration check (NEW)  ────────────────► U2: surface non-obvious X+Y+Z downstream consequences
6    Optional research                          (unchanged)
7-9  propose approaches / recommendation / devil's advocate   (unchanged)
10   show synthesis to user                     (unchanged)
10a  Verify-before-claiming (NEW, pre-write)  ─► U2: verify absence-claims vs repo or label as assumption
11   write design doc                           (design-doc-template gains an Assumptions/verified note)
12-13 capture reflex / handoff                  (unchanged)
```

The `performance > speed ≥ cost` principle (U4) sits near the top of both skills as a short stated priority, and foundation D39 records the rigor upgrades + the principle.

## Implementation units

### U1. Product Pressure Test (rigor-gap taxonomy)

- **Goal:** Add a self-gating product-rigor pass to en-brainstorm that pressure-tests the idea before approaches, firing one open-ended probe per rigor gap that actually exists.
- **Requirements covered:** none (no foundation R-IDs; skill-behavior change).
- **Dependencies:** none.
- **Files:** `skills/en-brainstorm/SKILL.md`, `references/socratic-questions.md`, `tests/lint/en-brainstorm-pressure-test.test.sh` (new).
- **Approach:** Add a new step (e.g. "5a. Product pressure test") between the Q&A loop and the propose-approaches step. It is **internal analysis** - scan the opening for the rigor gaps and raise only those that exist, as **open-ended probes folded into dialogue** (not a pre-flight checklist). The gaps: **evidence** (has anyone actually done anything about this - paid, built a workaround, quit a tool?), **specificity** (name a specific person/segment and what changes for them), **counterfactual** (what's the current workaround and what does it cost?), **attachment** (what's the smallest version that still delivers real value?), plus a **durability** gap for Deep/strategic scope (how does it fare under plausible near-term shifts?). Self-gating: a well-framed opening earns zero probes; depth-scales (durability is Deep-only). Add a "Product rigor gaps" section to `references/socratic-questions.md` documenting each gap + its probe phrasing, and cite ce-brainstorm for provenance. If a probe surfaces genuine uncertainty, record it as an explicit assumption in the design doc rather than skipping it.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - Happy path: en-brainstorm documents a Product pressure test step before approaches that fires one probe per existing gap. (drift guard: SKILL.md has the step; socratic-questions has the "Product rigor gaps" section)
  - Edge - self-gating: a well-framed opening earns zero probes (the step is documented as fire-only-on-gap). (drift guard asserts the self-gating/"only those that exist" language)
  - Edge - depth-scaling: the durability gap is Deep-only. (drift guard asserts durability is scoped to Deep)
  - Error path: a probe that surfaces uncertainty records an explicit assumption rather than being skipped. (drift guard asserts the assumption-capture clause)
  - Integration: all five gap names (evidence/specificity/counterfactual/attachment/durability) appear in both SKILL.md and socratic-questions. (drift guard cross-checks the taxonomy)
- **Verification:** `tests/lint/en-brainstorm-pressure-test.test.sh` passes (ends with `report`); `bash tests/run.sh` green; `bin/ensemble-lint --scope docs/` exit 0.

### U2. Integration check + verify-before-claiming

- **Goal:** Add two lean guardrails to en-brainstorm - an integration check before approaches, and a verify-before-claiming rule before the design doc is written.
- **Requirements covered:** none.
- **Dependencies:** U1 (sequences the shared en-brainstorm edits).
- **Files:** `skills/en-brainstorm/SKILL.md`, `references/templates/design-doc-template.md`, `tests/lint/en-brainstorm-integration-verify.test.sh` (new).
- **Approach:** (1) **Integration check** - a new step before approaches: mentally combine user-stated X + Y + the agent's default Z and surface the non-obvious downstream consequence one-question-at-a-time dialogue misses (example: "if mute lives on the rule AND we don't warn on delete, rule-delete silently loses pause state"). One open-ended probe per genuine combination effect; complements the existing devil's-advocate pass (which runs AFTER the recommendation) by catching cross-cutting effects BEFORE approaches. (2) **Verify-before-claiming** - a rule near the design-doc-write step: any claim that something is **absent** in the codebase (a missing table/endpoint/dependency/config option) must be verified against the repo first, or explicitly labeled an **unverified assumption**. Reflect this in `references/templates/design-doc-template.md` (an Assumptions / verified-claims note so absence-claims are labeled). Lightweight rule - NOT a fresh-context verifier sub-agent.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - Happy path: en-brainstorm documents an integration check before approaches (X+Y+Z → downstream consequence). (drift guard asserts the step + its "before approaches" placement)
  - Edge - one probe per combination: the check fires per genuine combination effect, not a blanket audit. (drift guard asserts the per-combination phrasing)
  - Error path - verify-before-claiming: an absence claim must be verified or labeled an assumption. (drift guard asserts the rule in SKILL.md AND the assumptions note in the design-doc-template)
  - Integration: the integration check is distinguished from the devil's-advocate pass (before-approaches vs after-recommendation). (drift guard asserts both are present and positioned)
- **Verification:** `tests/lint/en-brainstorm-integration-verify.test.sh` passes (ends with `report`); `bash tests/run.sh` green; `bin/ensemble-lint --scope docs/` exit 0.

### U3. AskUserQuestion-by-default + open-vs-closed discipline

- **Goal:** Upgrade en-brainstorm's Q&A loop from "multiple-choice when natural" to a clear contract: default to the platform's blocking question tool for narrowing questions, reserve open-ended for genuinely-open questions.
- **Requirements covered:** none.
- **Dependencies:** U2 (sequences the shared en-brainstorm edits).
- **Files:** `skills/en-brainstorm/SKILL.md`, `references/socratic-questions.md`, `tests/lint/en-brainstorm-elicitation.test.sh` (new).
- **Approach:** Update the Q&A loop (step 5): **default to the host's blocking question tool** (`$QUESTION_TOOL` per host-detect — `AskUserQuestion` on Claude Code, `request_user_input` on Codex; host-neutral, not hardcoded) with its free-text fallback for narrowing / single-select questions - one question per turn. **Open-vs-closed discipline:** use an open-ended question only when the answer is inherently narrative OR you genuinely cannot write 3–4 distinct, plausibly-correct options without padding ("if you'd be straining to fill the option slots, ask it open-ended"). Note the graceful fallback to numbered chat options when no blocking tool exists in the harness. Fold the open-vs-closed guidance into `references/socratic-questions.md`'s "Question style guidelines" section. Consistent with existing AskUserQuestion use in en-resolve-pr / en-simplify / en-debug.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - Happy path: en-brainstorm's Q&A loop defaults to AskUserQuestion for narrowing questions. (drift guard asserts the SKILL.md + socratic-questions guidance)
  - Edge - open-vs-closed: open-ended reserved for genuinely-open questions (the "can't write 3–4 distinct options without padding" test). (drift guard asserts the discipline)
  - Error path - harness fallback: numbered chat options when no blocking tool exists. (drift guard asserts the fallback clause)
  - Integration: one-question-per-turn is preserved. (drift guard asserts the one-per-turn rule survives)
- **Verification:** `tests/lint/en-brainstorm-elicitation.test.sh` passes (ends with `report`); `bash tests/run.sh` green.

### U4. `performance > speed ≥ cost` principle (en-brainstorm + en-plan + D39)

- **Goal:** State the `performance > speed ≥ cost` priority principle explicitly in both `/en-brainstorm` and `/en-plan`, and record it (plus the EN05 rigor upgrades) as foundation D39.
- **Requirements covered:** none.
- **Dependencies:** U3 (sequences the shared en-brainstorm edits).
- **Files:** `skills/en-brainstorm/SKILL.md`, `skills/en-plan/SKILL.md`, `docs/foundation.md`, `tests/lint/en-brainstorm-priority-principle.test.sh` (new).
- **Approach:** Add a short stated principle near the top of both skills: *"Priority: performance (brainstorm→plan quality) > speed ≥ cost."* - the ordering that already drives EN03/EN05, made explicit and durable. Add foundation decision **D39** recording (a) the ce-brainstorm rigor adoptions (Product Pressure Test, integration check, verify-before-claiming, AskUserQuestion default) as self-gating lean upgrades, and (b) the `performance > speed ≥ cost` principle for the design/plan skills. Keep D39 in the main §4.1 decision block (after D38).
- **Risk:** low
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - Happy path: both en-brainstorm and en-plan state the `performance > speed ≥ cost` principle. (drift guard asserts the principle text in both skills)
  - Edge - ordering is exact: `performance > speed ≥ cost` (not a different ordering). (drift guard asserts the exact relation)
  - Integration - D39: foundation records the rigor upgrades + the principle. (drift guard asserts D39 exists and names both the rigor adoptions and the principle)
  - Test expectation: none beyond the drift guard - this is a doc/principle unit.
- **Verification:** `tests/lint/en-brainstorm-priority-principle.test.sh` passes (ends with `report`); `bash tests/run.sh` green; `bin/ensemble-lint --scope docs/` exit 0; foundation shows D39.

## Verification (whole plan)

- `bash tests/run.sh` - full suite green (new: 4 drift-test files).
- `bin/ensemble-lint --scope docs/` - exit 0 (no cross-link / frontmatter / unit drift).
- Manual spot-check: en-brainstorm gains the pressure test + integration check + verify-before-claiming + AskUserQuestion default, all self-gating; both en-brainstorm and en-plan state `performance > speed ≥ cost`; foundation shows D39; none of the deliberately-out-of-scope ce machinery (visual probes, HTML, universal route, model tiers, dossier, unified artifact) was added.
- Branch-level cross-agent review at build completion (D35), verdict recorded via the `review-verdict:` trailer.
