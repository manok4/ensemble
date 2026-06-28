---
type: plan
plan_type: improvement
plan_id: FR01
title: Skill-suite optimization and supercharge
status: in_progress
location: active
created: 2026-06-28
shipped:
deepened:
covers_requirements: []
requirements_pending: false
related_design:
peer_review_verdict: approve
peer_review_iterations: 4
peer_review_last_run: 2026-06-28
peer_review_plan_hash: a68ea5a940df49fb685649f085f323877d04b034051cb7ad08a89333b25f3f07
peer_review_resolutions:
  - finding_id: "1-1"
    iteration: 1
    severity: P2
    title: U7 gating rule is broader than the production-state-changing gate contract
    status: applied
    rationale: Tightened U7 so gated:true is limited to production-state-changing actions and risk:destructive is a distinct category; non-production external side effects are explicitly not gated.
    location: U7. Gating shrink + preflight gate summary
  - finding_id: "2-1"
    iteration: 2
    severity: P2
    title: U2 is medium risk but listed in the P1 low-risk phase
    status: applied
    rationale: Rewrote the Phasing section to place units by risk (P1=low, P2=medium); U2 and U11 are now explicitly medium-risk P2 units, with independence separated from phase label.
    location: Phasing section; U2
depth: deep
data_scale: small
---

# FR01 - Skill-suite optimization and supercharge

## Context

Field use of the Ensemble skills across real projects (policy-async, this repo) surfaced efficiency and ergonomics problems. A deep read of the compound-engineering-plugin (`/Users/mano.kulasingam/CodeRepo/agent-skills/compound-engineering-plugin`) — `ce-simplify-code`, `ce-code-review`, `ce-debug`, `ce-resolve-pr-feedback`, `lfg` — surfaced adaptable patterns. This plan applies them.

The unifying theme is **scale the work to the change, fail closed when unsure** — stop doing maximum work regardless of change size, and stop pausing for work the safety net already covers.

Decided before planning (do not re-litigate during build):
- en-build moves from **per-unit** simplify+peer-review to the **branch-level (lfg) model**: per-unit is implement+test+lint+commit; simplify + review run once over the branch diff after all units build.
- Orchestration is **baked into en-build** (U3) AND exposed as a standalone `en-flow` pipeline skill (U13) for fully hands-off plan→ship runs.
- Model tiers are **not** in scope.

## Decisions addressed (foundation D-entries)

- **D26** (en-learn auto-runs + en-ship backstop) — unaffected, but the en-ship plan-completion checkpoint's evidence source changes (U2/U3).
- **D29** (per-unit code simplification before peer review) — **superseded** by the branch-level model (U3); foundation updated in U3.
- **D33** (autonomous execution contract) — reinforced by the gating shrink (U7).
- **D34** (source of truth for in_progress → completed) — the plan-completion checkpoint's build-completeness signal changes from per-unit peer trailers to a branch-level review verdict (U2/U3); foundation updated.

## Out of scope for this plan (follow-ups)

- Model tiers (semantic cost classes for dispatched agents).
- Re-syncing consuming projects' frozen `bin/` copies (policy-async, etc.) — U11 documents the procedure; executing it per-project is operational follow-up.
- Flipping policy-async FR35 U6 to `gated: false` — different repo; U7 only recalibrates the criteria/docs here.

## Approach (high-level)

Thirteen units across two risk phases (P1 low, P2 medium — no high/destructive, zero gated units). The structural core is the en-build review-model change (U1 → U2 → U3), sequenced so the repo's drift tests pass at every commit: U2 makes the evidence model **accept** a branch-level verdict (backward-compatible with legacy per-unit trailers) **before** U3 switches en-build to emit it. The remaining units are largely independent enhancements.

A shared `references/diff-signal-detection.md` (U4) defines small-diff thresholds + frontend/UI + risk-surface file patterns once; both en-review `--lite` (U5) and en-qa's browser detector (U6) consume it (DRY).

## Implementation units

Each unit has a stable U-ID. Never renumbered after assignment.

### U1. Create en-simplify skill

- **Goal:** Standalone behavior-preserving code-simplification skill, usable ad-hoc and callable by en-build's post-build phase.
- **Requirements covered:** —
- **Dependencies:** none
- **Files:**
  - `skills/en-simplify/SKILL.md` (new)
  - `references/code-simplifier-dispatch.md` (reuse; reference from the new skill)
  - `agents/code-simplifier.md` (reuse the existing agent)
  - `tests/lint/en-simplify.test.sh` (new — drift guard)
- **Approach:** Port `ce-simplify-code`'s structure: scope resolution (user-named scope > branch diff vs base > recent files; ask if empty), three parallel reviewer dimensions (reuse / quality / efficiency) dispatched via the existing `code-simplifier` agent, behavior-preservation guardrails (never simplify away safety checks; skip findings that change behavior), scoped verification (typecheck + lint + tests matched to blast radius), and an impact-by-dimension summary. Honor `$ENSEMBLE_ROOT` helper-resolution convention. Add recursion guard (`ENSEMBLE_PEER_REVIEW=true` → exit). Default scope = branch diff vs base.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Patterns to follow:** existing SKILL.md helper-resolution header; `references/code-simplifier-dispatch.md`
- **Test scenarios:**
  - SKILL.md has the helper-resolution header and recursion guard.
  - Declares the three reviewer dimensions (reuse/quality/efficiency).
  - States behavior-preservation guardrail (never remove safety checks).
  - Default scope = branch diff vs base; ask-when-empty path documented.
  - `tests/run.sh` passes including the new drift guard.
- **Verification:** new drift guard passes; `bash tests/run.sh` green; SKILL.md frontmatter valid per `bin/ensemble-lint`.

### U2. Evidence model accepts a branch-level review verdict (backward-compatible)

- **Goal:** Let the build-completeness signal be satisfied by a branch-level review-verdict record, in addition to the legacy per-unit peer-evidence trailers, so U3 can switch en-build without breaking the audit or en-ship's checkpoint at any commit.
- **Requirements covered:** D34
- **Dependencies:** none
- **Files:**
  - `bin/ensemble-verify-peer-evidence`
  - `skills/en-ship/SKILL.md` (step 8 plan-completion checkpoint — build-completeness check)
  - `references/build-handoff.md`
  - `tests/lint/en-ship-plan-completion-checkpoint.test.sh`
  - `tests/lint/ensemble-verify-peer-evidence` tests (wherever exercised in `tests/`)
- **Approach:** Define a branch-level review-verdict record (e.g. a `review-verdict:` trailer on the final review/fix commit, or a recorded `peer_review_verdict` marker the audit can read). Extend `ensemble-verify-peer-evidence` to treat a valid branch-level verdict as satisfying evidence for the units it covers, while **still accepting** legacy per-unit `peer-resolution:`/`peer-skipped:` trailers (backward-compatible — existing branches/plans keep passing). Update en-ship's plan-completion build-completeness check to accept either form. Keep destructive/`gated:true` units' stricter requirement intact. This unit changes only what the audit *accepts*; it does not change what en-build *emits* (that's U3).
- **Risk:** medium
- **Category:** schema-evolution
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** characterization-first
- **Patterns to follow:** existing peer-evidence trailer model; `references/build-handoff.md`
- **Test scenarios:**
  - Legacy per-unit-trailer commits still audit as valid (no regression).
  - A branch-level review-verdict record satisfies the audit for covered units.
  - en-ship plan-completion checkpoint accepts both forms.
  - Destructive/gated units still require their stronger evidence.
- **Verification:** updated + existing audit tests pass; `bash tests/run.sh` green.

### U3. en-build branch-level review model

- **Goal:** Replace per-unit simplify + per-unit peer review with a fast per-unit inner loop plus a single post-build branch-level simplify → review → apply phase.
- **Requirements covered:** D29, D34
- **Dependencies:** U1, U2
- **Files:**
  - `skills/en-build/SKILL.md` (steps 9, 10)
  - `references/build-orchestration.md`
  - `references/build-handoff.md`
  - `references/code-simplifier-dispatch.md`
  - `docs/foundation.md` (supersede D29; update D34 evidence-source wording)
  - `tests/lint/en-build-autonomy-contract.test.sh` (per-unit loop changed)
  - `tests/lint/en-build-review-model.test.sh` (new drift guard)
- **Approach:** Remove step 9e (per-unit code-simplifier) and steps 9g–9h.1 (per-unit peer review + per-unit finalize loop). Per-unit loop becomes: gate (9a, unchanged) → execution note → implement → verify gate (tests + lint) → commit. After all units build, add a post-build orchestration phase: invoke `/en-simplify` on the branch diff (skip on docs-only/trivial per lfg), then invoke `/en-review` headless on the branch diff, apply eligible fixes, emit the branch-level review-verdict record (U2), then the existing `/en-learn` hand-off. Update the end-of-build audit (step 10) to verify the branch-level verdict. Update both flavor references (orchestration/handoff). Supersede D29 in foundation; adjust the per-unit loop description in the autonomy-contract test.
- **Risk:** medium
- **Category:** schema-evolution
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** characterization-first
- **Patterns to follow:** `lfg` step ordering (simplify before review, no commit in simplify step); `references/build-orchestration.md`
- **Test scenarios:**
  - Per-unit loop no longer dispatches simplifier or peer review.
  - Post-build phase order is simplify → review → apply → learn.
  - Branch-level verdict is emitted and the end-of-build audit verifies it.
  - Autonomy-contract drift test reflects the new per-unit loop.
  - foundation D29 marked superseded; D34 evidence-source updated.
- **Verification:** new + updated drift guards pass; `bash tests/run.sh` green.

### U4. Shared diff-signal detection reference

- **Goal:** Define small-diff thresholds, frontend/UI file patterns, and risk-surface patterns once, with fail-closed rules, for reuse by en-review and en-qa.
- **Requirements covered:** —
- **Dependencies:** none
- **Files:**
  - `references/diff-signal-detection.md` (new)
  - `tests/lint/diff-signal-detection.test.sh` (new)
- **Approach:** Capture: executable-line thresholds (small-diff window), uncounted-file rule (any non-code file → not small), frontend/UI patterns (`.tsx`/`.jsx`/`.vue`/`.svelte`/`components/`/`ui/` etc.), risk-surface patterns (auth, payments, migrations, external APIs, secrets). Define the **fail-closed** contract explicitly: unknown line count or any uncounted file or any risk signal disqualifies the "small/safe" classification. Pure additive reference.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Patterns to follow:** ce-code-review small-diff lite-roster gate (fail-closed)
- **Test scenarios:**
  - Frontend, risk-surface, and uncounted-file patterns documented.
  - Fail-closed contract stated unambiguously.
- **Verification:** drift guard passes; `bash tests/run.sh` green.

### U5. en-review --lite flag

- **Goal:** A fast review path for small, low-risk changes.
- **Requirements covered:** —
- **Dependencies:** U4
- **Files:**
  - `skills/en-review/SKILL.md`
  - `references/persona-dispatch.md`
  - `tests/lint/en-review-lite.test.sh` (new)
- **Approach:** Add `--lite`: collapse to correctness + standards (+ a fast-pass lens) when `references/diff-signal-detection.md` classifies the diff as small AND safe. FAIL CLOSED — any uncounted file, unknown line count, or risk signal forces the full roster regardless of `--lite`. Fast-pass findings confidence-capped so they surface only with corroboration (per ce-code-review). Document that `--lite` is advisory: the gate, not the flag, has final say.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Patterns to follow:** ce-code-review lite roster + confidence anchor; `references/diff-signal-detection.md`
- **Test scenarios:**
  - `--lite` documented in the flags table.
  - Fail-closed override stated (risk signal / uncounted file → full roster).
  - Lite roster persona set documented.
- **Verification:** drift guard passes; `bash tests/run.sh` green.

### U6. en-qa browser detector

- **Goal:** Skip the Playwright phase automatically when the change can't affect the UI.
- **Requirements covered:** —
- **Dependencies:** U4
- **Files:**
  - `skills/en-qa/SKILL.md`
  - `references/qa-flows.md`
  - `tests/lint/en-qa-browser-detector.test.sh` (new)
- **Approach:** Before Phase 2, classify the diff via `references/diff-signal-detection.md`. Run Phase 2 (browser) only when the diff touches frontend/UI files OR a `--browser` flag forces it; otherwise Phase-1-only with a one-line note ("Browser QA auto-skipped — no frontend files changed; pass --browser to force."). Preserve existing `--system-only` and doc-only auto-skip. Add `--browser` to the flags table.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Patterns to follow:** existing `--system-only` + doc-only skip; `references/diff-signal-detection.md`
- **Test scenarios:**
  - Auto-skip when no frontend files; runs when frontend files present.
  - `--browser` forces Phase 2; `--system-only` still skips.
  - One-line skip note documented.
- **Verification:** drift guard passes; `bash tests/run.sh` green.

### U7. Gating shrink + preflight gate summary

- **Goal:** Reduce en-build's pause surface to only genuinely consequential units, and make remaining gates predictable.
- **Requirements covered:** D33
- **Dependencies:** U3
- **Files:**
  - `skills/en-build/SKILL.md` (steps 8b, 9a; new preflight summary)
  - `references/templates/plan-template.md` (reinforce the tight `gated:` bar)
  - `docs/foundation.md` (D33 reinforcement)
  - `tests/lint/en-build-autonomy-contract.test.sh`
- **Approach:** Keep **two distinct** mandatory-gate categories and nothing else: (1) `risk: destructive` — its own literal-string (`run unit U<N>`) category for irreversible data loss; (2) `gated: true` — limited **explicitly to production-state-changing actions**: customer-facing feature-flag flips, production data backfills / data mutation, real-side-effect third-party API calls against **production** endpoints, API contract breaks, and production config changes with behavior impact. **Non-production external side effects** (PR/branch automation, issue/comment writes, local workflow or CI-config changes, sandbox/staging API calls, reversible repo operations) are explicitly **NOT** gated — they're handled by the per-unit verification gates + the post-build review (U3), not user prompts. Keep the two categories distinct in the wording (don't fold destructive into gated, and don't let "external side effect" smuggle non-production work into the gate). Add a **preflight gate-count summary** at build start: "This plan has N gated/destructive units: U3, U7 — each will pause as reached." Recalibration of criteria only — reinforce the existing tight bar, do not widen it. Note the policy-async FR35 U6 over-gate as an illustrative example (no cross-repo change here).
- **Peer note (finding 1-1, P2):** wording tightened to production-state-changing only, per cross-agent review — prevents non-production side effects from preserving over-gating.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Patterns to follow:** existing universal safety gates (8b/9a); plan-template `gated:` criteria
- **Test scenarios:**
  - Preflight gate-count summary documented.
  - Mandatory-gate table still covers destructive + gated:true; nothing widened.
  - plan-template `gated:` tight-bar language intact/reinforced.
- **Verification:** updated drift guard passes; `bash tests/run.sh` green.

### U8. en-ship watch loop + en-resolve-pr pagination

- **Goal:** After opening the PR, en-ship watches for review/CI issues and runs en-resolve-pr to fix them, bounded; no auto-merge.
- **Requirements covered:** —
- **Dependencies:** U2
- **Files:**
  - `skills/en-ship/SKILL.md` (post-PR watch loop)
  - `skills/en-resolve-pr/SKILL.md`
  - `skills/en-resolve-pr/scripts/get-pr-comments`
  - `tests/lint/en-ship-watch-loop.test.sh` (new)
- **Approach:** After step 12 (PR open), enter a bounded watch loop (default ON): poll the PR for new review comments / CI status; on issues, invoke `/en-resolve-pr`; cap at 2 cycles then escalate remaining as needs-human (mirror ce-resolve-pr-feedback). **Do NOT auto-merge** — surface "PR ready for your review/merge." Add a flag to disable the watch (e.g. `--no-watch`). Audit `en-resolve-pr`'s `get-pr-comments` for GraphQL pagination (compound #798: fixed page sizes silently drop feedback past page 1); add cursor pagination if missing. Note interaction with U2's checkpoint section to avoid edit conflict.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Patterns to follow:** ce-resolve-pr-feedback bounded loop + pagination; en-ship existing flags
- **Test scenarios:**
  - Watch loop documented (default on), bounded to 2 cycles, escalates needs-human.
  - No auto-merge; `--no-watch` disables.
  - `get-pr-comments` paginates all connections (cursor loop).
- **Verification:** new drift guard + pagination test pass; `bash tests/run.sh` green.

### U9. en-debug fix-loop extension

- **Goal:** Add an investigate → root-cause → test-first-fix → handoff loop to en-debug, alongside the existing telemetry front-end.
- **Requirements covered:** —
- **Dependencies:** none
- **Files:**
  - `skills/en-debug/SKILL.md`
  - `references/debug-investigation.md` (new — ported anti-patterns + investigation techniques)
  - `tests/lint/en-debug-fix-loop.test.sh` (new)
- **Approach:** Keep the telemetry/log-driven read-only mode as-is. Add a second (code/no-telemetry) mode adapting ce-debug: triage (incl. issue-tracker fetch) → reproduce + trace causal chain → hypotheses with grounding observations + predictions + causal-chain gate + smart escalation → optional test-first fix with workspace/branch safety → structured handoff. Preserve "read-only by default": the fix path is opt-in via a user choice (Fix it now / Diagnosis only). Honor recursion guard.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Patterns to follow:** ce-debug phases + anti-pattern guardrails
- **Test scenarios:**
  - Telemetry mode unchanged; new code-mode documented.
  - Causal-chain gate + one-change-at-a-time + test-first-fix documented.
  - Fix path is opt-in (Diagnosis only vs Fix it now).
- **Verification:** drift guard passes; `bash tests/run.sh` green.

### U10. Evidence dossiers for research agents

- **Goal:** Cut context bloat in en-plan/en-review research by having scouts write bulk evidence to scratch and return only a gist + path.
- **Requirements covered:** —
- **Dependencies:** none
- **Files:**
  - `agents/repo-research.md`
  - `agents/learnings-research.md`
  - `agents/web-research.md`
  - `references/research-dispatch.md`
  - `tests/lint/research-dossier.test.sh` (new)
- **Approach:** Adopt compound's evidence-dossier pattern: each research agent writes verbatim quotes with source pointers to a scratch path (e.g. `/tmp/ensemble/<skill>/<run-id>/<agent>.md`, line-capped), returns a short gist + the dossier path. Downstream (en-plan/en-review) reads the dossier from disk on demand instead of carrying full findings inline. Document a degraded fallback: if the scratch write fails, return inline.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Patterns to follow:** compound evidence-dossier (scout writes bulk, orchestrator carries gist)
- **Test scenarios:**
  - Each research agent documents dossier write + gist-return contract.
  - research-dispatch.md documents the dossier path + read-on-demand.
  - Write-failure inline fallback documented.
- **Verification:** drift guard passes; `bash tests/run.sh` green.

### U11. en-sweep CI fix

- **Goal:** Make the scheduled en-sweep actually run the skill instead of going green-but-inert.
- **Requirements covered:** —
- **Dependencies:** none
- **Files:**
  - `bin/en-sweep-ci`
  - `references/templates/github-workflow-en-sweep.yml`
  - `skills/en-setup/SKILL.md` (re-sync note for consumers)
  - `skills/en-sweep/SKILL.md` (doc)
  - `tests/lint/en-sweep-ci.test.sh` (new or extend existing sweep tests)
- **Approach:** Root cause: `claude -p --skill en-sweep` doesn't resolve the skill because the freshly-cloned plugin (`.ensemble/ensemble-source`) is never registered with the CLI → "Unknown command: /en-sweep", `num_turns:0`, exit 0, job green. Fix `bin/en-sweep-ci` to register/install the cloned plugin (e.g. `claude plugin install` from the clone, or the correct plugin-dir/settings-sources wiring) before invoking the skill; add a **guard** that fails the step when the result is `num_turns:0` or contains "Unknown command". Change the workflow template to invoke the **cloned** script (`.ensemble/ensemble-source/bin/en-sweep-ci`) so future fixes propagate automatically. Document in en-setup that consumers carry frozen `bin/` copies needing re-sync.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Patterns to follow:** existing `bin/en-sweep-ci` CLI resolution; workflow template structure
- **Test scenarios:**
  - en-sweep-ci registers the cloned plugin before invoking the skill.
  - Guard fails on `num_turns:0` / "Unknown command".
  - Workflow template invokes the cloned script path.
  - en-setup documents the consumer re-sync procedure.
- **Verification:** sweep CI tests pass; `bash tests/run.sh` green; manual `workflow_dispatch` on a consumer would show the sweep job doing real work (operational, post-merge).

### U12. en-plan brainstorm soft-nudge

- **Goal:** Encourage (not force) a brainstorm before planning when no design doc exists.
- **Requirements covered:** —
- **Dependencies:** none
- **Files:**
  - `skills/en-plan/SKILL.md` (step 4 area)
  - `tests/lint/en-plan-brainstorm-nudge.test.sh` (new)
- **Approach:** In en-plan preflight, if no `docs/designs/*.md` matches the topic, surface a soft one-line offer: "No design doc found for this — want to `/en-brainstorm` first? (y / proceed)." Soft nudge only — proceeding is always allowed; never a hard gate (consistent with the gating-shrink philosophy in U7).
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Patterns to follow:** compound's loose brainstorm→plan handoff (no prerequisite enforcement)
- **Test scenarios:**
  - Soft-nudge documented; proceeding without brainstorm always allowed.
  - Not a hard gate (explicit).
- **Verification:** drift guard passes; `bash tests/run.sh` green.

### U13. en-flow pipeline skill

- **Goal:** A single manual-invoke command that runs the full hands-off pipeline plan → build → ship, with a model-decided en-learn step, so the user isn't chaining skills by hand.
- **Requirements covered:** —
- **Dependencies:** U1, U3, U8
- **Files:**
  - `skills/en-flow/SKILL.md` (new)
  - `references/en-flow-pipeline.md` (new — stage contracts / gates)
  - `tests/lint/en-flow.test.sh` (new)
- **Approach:** Adapt compound's `lfg` as a thin orchestrator (`disable-model-invocation: true` — manual invoke only; never auto-triggered). Numbered, in-order steps with hard GATES and artifact hand-off between stages. Stages:
  1. **Plan** — invoke `/en-plan` with the feature description (or accept an existing `--plan <path>`). GATE: a finalized plan file exists with `status: open` (or `--no-peer` path); record the plan path. Stop if non-software / not implementation-ready.
  2. **Build** — invoke `/en-build <plan-path>`. en-build already runs its post-build phase internally (en-simplify → en-review → apply → en-learn hand-off per U3). GATE: build completed; end-of-build audit passed (branch-level review verdict present per U2); else stop and surface.
  3. **Learn (model-decided)** — the pipeline ensures `/en-learn` is *considered*. The model decides whether a capture is warranted based on the build's outcome (durable insight, non-obvious pattern, deviation from plan, library footgun) vs a mechanical change with no generalizable lesson. Capture when warranted; skip silently otherwise. This is a judgment step, not an unconditional invocation — mirrors en-learn's existing soft-prompt contract and avoids cluttering the wiki. (If U3's en-build post-build phase already captured, this step is a no-op; the pipeline does not double-capture.)
  4. **Ship** — invoke `/en-ship` (which, per U8, opens the PR then enters the bounded watch loop → en-resolve-pr; **no auto-merge**). GATE: shipping precondition — if no git remote, make local commits only and skip push/PR/watch (mirror lfg). 
  5. Output a terminal completion marker with the PR URL (or local-only summary).
  Honor `$ENSEMBLE_ROOT` helper resolution and the recursion guard. Resolve each sub-skill name against the host's available-skills list (namespace-aware), per lfg. Document flags: `--plan <path>` (skip planning), `--no-ship` (stop after build), `--no-watch` (pass through to en-ship).
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Patterns to follow:** compound `lfg` (numbered in-order steps, GATES, artifact hand-off, `disable-model-invocation: true`, shipping-precondition for remote-less checkouts)
- **Test scenarios:**
  - SKILL.md has `disable-model-invocation: true` (manual invoke only).
  - Stage order is plan → build → learn(model-decided) → ship, with a GATE after each.
  - en-learn step is conditional (model-decided), not unconditional; no double-capture when en-build already captured.
  - en-ship stage does NOT auto-merge; passes `--no-watch` through.
  - Shipping-precondition (no remote → local-only) documented.
  - `--plan` / `--no-ship` / `--no-watch` flags documented.
- **Verification:** drift guard passes; `bash tests/run.sh` green.

## Phasing

8+ units and `depth: deep` → phasing on. No P3/P4, **zero gated units**.

- **P1 (low risk):** U1, U4, U5, U6, U9, U10, U12
- **P2 (medium risk):** U2, U3, U7, U8, U11, U13

Phase placement follows `risk:` strictly (P1=low, P2=medium) — independence from other units does **not** imply P1. U2 and U11 are independent (no deps) but are **medium-risk P2 units**, not P1 setup work.

Dependency-respecting build order (phase label in brackets): U1 [P1], U4 [P1], U2 [P2] → U3 [P2] (needs U1, U2) → U5 [P1], U6 [P1] (need U4), U7 [P2] (needs U3), U8 [P2] (needs U2) → U13 [P2] (needs U1, U3, U8) → U9 [P1], U10 [P1], U11 [P2], U12 [P1] (independent). U13 (en-flow) lands last because it orchestrates the other skills and depends on their final form. Within phasing, P1 units run before P2 units; the order above is the dependency topology, not the phase-execution order.

## Lifecycle

`draft → open → in_progress → completed`. This is the first plan in `docs/plans/` for this repo (the repo previously tracked work via `docs/*-spec.md`). `plan_id_prefix` is unset in foundation → default `FR`; set `plan_id_prefix: EN` in foundation later if preferred (does not rewrite this plan's ID).
