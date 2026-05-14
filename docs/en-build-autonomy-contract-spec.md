---
title: /en-build agent autonomy contract
status: spec
owner: mano
related:
  - skills/en-build/SKILL.md
  - skills/en-qa/SKILL.md (for the extension question)
created: 2026-05-12
---

# Spec: `/en-build` agent autonomy contract

## Context

Field-observed friction: during an `/en-build` run, after U3 committed successfully, the agent output:

> *"Working tree is clean. I stopped at a clean checkpoint before U4, which is the larger API surface."*

It then waited for the user to confirm continuation. **Nothing in the spec authorizes this pause.** The agent inserted its own checkpoint based on independent judgment ("U4 is bigger; let me let the user confirm before continuing"). That violates the autonomous-execution contract that's the whole reason `/en-build` exists — the user already authorized the work by approving the plan; per-unit pauses bypass that authorization.

### Why the spec is leaking

The current SKILL.md enumerates the legitimate pause cases — destructive gates, gated:true gates, P4 confirmation, `--pause` flag, failure protocols — but it does so as a **list of examples**, not as a **closed enumeration with explicit prohibition of others**. An LLM trained on "when in doubt, ask the user" reads the list and adds its own pause cases when judging the situation warrants.

This is the same failure mode we addressed in PR #17 for `gated: true` over-application: agents have built-in anti-autonomy biases (be safe, ask before big changes, checkpoint at "natural" boundaries). The spec needs to **actively counter** those biases, not just stay silent and hope the agent reads correctly.

### Audit of legitimate pause cases (current spec)

The seven cases that ARE in the spec:

| # | Pause case | Where |
|---|---|---|
| 1 | Working tree dirty at branch setup | step 5 |
| 2 | Plan-review concerns surfaced at start | step 7 |
| 3 | `risk: destructive` unit — typed `"run unit U<N>"` | step 9a |
| 4 | `gated: true` unit — y/skip/abort | step 9a |
| 5 | P4 phase-level confirmation — typed `"run phase 4"` | step 9 (phasing-on path) |
| 6 | `--pause` flag — between-phase prompt | step 9 (opt-in, default off) |
| 7 | Failure protocol fires — gate failure, peer reject, malformed evidence, hash mismatch, after-phase verification failure, plan-hash drift, worker malformed diff | failure-protocol table |

Anything else is the agent overriding the design intent.

## Outcome enum (canonical)

**Not applicable in the usual sense** — this spec doesn't add a new prompt or report value. It defines a contract on agent behavior **within the inter-unit main loop** (step 9 start → step 10 end). The relevant assertion is **binary** for any inter-unit transition inside that window:

| Condition | Required behavior |
|---|---|
| One of cases 3–7 (in-window legitimate pauses) applies | Pause per the existing handler for that case |
| None applies | **Advance immediately. No prompt. No "checkpoint." No "let me verify."** |

Cases 1–2 (preflight prompts at step 5 / step 7) are out of the contract's scope and continue to operate per their existing handlers — see "Scope of the contract" in the SKILL.md changes below.

The drift guard asserts the contract is documented as a hard prohibition, not just an implicit assumption.

## Resolved decisions

1. **Continue is the default; pausing requires a specific authorized reason.** When in doubt, the agent advances. The failure protocols are the safety net for "things go wrong"; agent-initiated pauses add no protection on top — they just add friction.

2. **Add the contract to `skills/en-build/SKILL.md` as a top-level section near the beginning, plus extend "What this skill never does."** Two places, one rule, redundancy on purpose — agents read in different orders and a single mention is fragile.

3. **Extend to `/en-qa` in the same PR.** en-qa has analogous autonomous-loop semantics (system checks → Playwright flows → fix bugs as found → next flow). The same agent biases apply. Cheaper to do both now than spec a separate PR later.

4. **No new flags.** This is a spec tightening, not a feature. Existing flags (`--pause`, `--strict-destructive`, etc.) stay as the user-facing knobs.

5. **Use the same drift-guard pattern as PR #17 (gated criteria) and PR #18 (en-learn-checkpoint enum).** Test asserts: (a) the contract is present, (b) all seven cases are enumerated, (c) the explicit anti-patterns are forbidden, (d) the "never insert agent-initiated checkpoints" line appears in the "What this skill never does" section.

## Change 1 — `/en-build` SKILL.md: Agent autonomy contract section

**File:** `skills/en-build/SKILL.md`.

**Placement:** new section right after the "Universal safety gates" section (around line 95), before the per-unit loop in step 9.

**Content:**

> ## Agent autonomy contract
>
> `/en-build` is autonomous by design. The user authorized the work at plan time (peer-reviewed plan, status: open, hash recorded). After a unit commits successfully (step 9k passes), advance to the next unit immediately. **Do not pause** for confirmation, judgment, "natural checkpoint," "the next unit is bigger," "let me verify before continuing," or any reason not in the seven enumerated cases below.
>
> ### Scope of the contract
>
> The contract governs **the inter-unit main loop** — specifically, the window from the START of step 9 (per-unit loop, after preflight has cleared) through the END of step 10 (after all units, before /en-learn hand-off). Within this window, pauses are restricted to the seven cases below.
>
> **Steps 1–8 are NOT governed by this contract.** Preflight, sub-state matrix decisions (untracked-but-approved → offer auto-commit; draft + revise with cleared findings → offer finalize-and-build; unresolved draft findings → refuse and ask for `/en-plan --resume`), host detection, branch setup, plan-review concerns, and batch sizing all have their own documented prompts and protocols. Those are *pre-execution* prompts about whether the build can sensibly start; they're orthogonal to the *during-execution* autonomy this contract enforces.
>
> Why scope this way: the field-observed bug ("Working tree is clean. I stopped at a clean checkpoint before U4") is specifically a post-step-9k, inter-unit pause inserted by agent judgment. Scoping the contract to that window catches exactly that bug class. Scoping wider would either invalidate legitimate preflight prompts or require an unmaintainable enumeration of every prompt-emitting code path.
>
> ### Legitimate pause cases within the contract window (exhaustive within scope, no others permitted)
>
> 1. **Working tree dirty at branch setup** (step 5) — stash / commit / abort prompt. *(Out of contract window; listed for completeness — see Scope above.)*
> 2. **Plan-review concerns surfaced at start** (step 7) — continue / pause / split prompt. *(Out of contract window; listed for completeness.)*
> 3. **`risk: destructive` unit at step 9a** — typed `"run unit U<N>"` literal-string gate.
> 4. **`gated: true` unit at step 9a** — y/skip/abort prompt.
> 5. **P4 phase-level confirmation** (step 9, phasing-on path) — typed `"run phase 4"` literal-string.
> 6. **`--pause` flag set** (step 9, opt-in) — between-phase y/pause/n prompt.
> 7. **Failure protocol fires** (failure-protocol table) — gate failure, peer reject, malformed evidence, hash mismatch, after-phase verification failure, plan-hash drift, worker malformed diff, etc. Each has its own documented handler.
>
> Cases 3–7 are inside the contract window (steps 9 and 10). Cases 1 and 2 are listed for completeness so the reader sees the full pause-emitting universe of /en-build; they're already in their own documented handlers and are not subject to this contract.
>
> ### Anti-patterns (explicitly forbidden)
>
> - **Agent-initiated "checkpoint before bigger unit" pauses.** The plan was authored and peer-reviewed; the agent does not re-evaluate unit complexity at execution time.
> - **"Working tree is clean, paused for confirmation" between non-gated units.** Working-tree-clean is the *expected* state between units, not a reason to pause.
> - **"Should I continue?" preambles outside the seven cases.** Continuing is the default; stopping requires a specific authorized reason.
> - **"Let me verify with the user before [implementing/committing/running tests/anything]"** when none of the seven cases apply. The user already authorized the plan; per-unit pauses bypass that authorization.
> - **"This next unit has [X characteristic that's not in the seven cases]; pausing here."** No characteristic outside the seven cases is grounds for an inserted pause.
>
> ### Right response to LLM uncertainty: advance, not ask
>
> If the agent feels uncertain about advancing, the correct action is to **continue per the contract**. The failure protocols are the safety net:
>
> - Tests fail → step 9d / 9j catches it.
> - Lint fails → step 9d catches it.
> - Peer review fails → step 9g / 9h / 9i handles it.
> - Implementation goes wrong → verification gate 1 or 2 catches it.
> - After-phase regression → after-phase verification catches it.
>
> Agent-self-paused checkpoints add no protection on top of these mechanisms — they just add friction that the autonomous-execution design exists to avoid.
>
> If the agent has a real concern that's outside the seven cases AND not caught by failure protocols, the right place to surface it is in the **per-unit progress report after committing** (step 9k's report). The report is informational — it doesn't pause the loop. Example:
>
> ```
> ✓ U3 — feat(api): wrap rotateRefreshToken in singleFlight  [P2 / risk: medium]
>   Implementer: codex (worker) | Simplifier: 2 changes | Peer: applied 1, deferred 1
>   Tests: 7 added, 7 passing | Commit: a3f1b9c
>   Note: U4 touches more files than U3 (12 vs 3). No pause; advancing.
> ```
>
> "Note:" lines are encouraged when the agent has observations worth surfacing. They don't gate the build.

## Change 2 — `/en-build` SKILL.md: "What this skill never does"

**File:** `skills/en-build/SKILL.md`, the existing "What this skill never does" bullet list at the bottom.

**Add one new bullet** to the existing list:

> - **Never inserts agent-initiated checkpoints.** Only the seven enumerated pause cases (see Agent autonomy contract) are legitimate. The agent never adds "let me checkpoint here" or "I'll pause before the next unit" pauses based on its own judgment. The plan was authored and reviewed; the agent executes.

## Change 3 — `/en-qa` SKILL.md: same contract, scoped to QA flows

**File:** `skills/en-qa/SKILL.md`.

en-qa has analogous semantics: it runs Phase 1 (system checks) → Phase 2 (browser end-to-end with Playwright) → fixes bugs as found → reports. Each Phase 2 flow is autonomous: navigate → assert → fix → next flow. Same agent-bias risk as en-build.

**Placement:** new section after the existing "Phase 2 — browser QA" description, before the "Auto-invoke `/en-learn`" section.

**Content:**

> ## Agent autonomy contract (mirrors `/en-build`)
>
> `/en-qa` is autonomous by design. After fixing a bug (or confirming a flow passed), advance to the next flow immediately. **Do not pause** for confirmation, "let me checkpoint before the bigger test surface," or any reason not in the enumerated cases below.
>
> ### Scope of the contract
>
> The contract governs **already-runnable QA flows** — the period after setup has cleared, during which Phase 1 system checks are executing or Phase 2 Playwright flows are running and the bug-fix loop is iterating. Within this window, pauses are restricted to the five cases below.
>
> **Pre-flow setup is NOT governed by this contract.** Specifically, the following en-qa prompts and skip decisions have their own documented handlers and are NOT inter-flow pauses:
>
> - **URL discovery prompt** (en-qa SKILL.md line 22) — when no app URL is found, ask the user. Pre-flow; the QA flow can't start without a URL.
> - **Phase 2 skip on doc-only branches / `--system-only` / browser-disabled config** (SKILL.md line 52) — Phase 2 is correctly skipped; the contract doesn't force it to run.
> - **Playwright bootstrap offer** when no test framework is detected — pre-flow setup question; out of contract scope.
>
> Why scope this way: the autonomy bug class is the same as en-build's — agent-initiated checkpoints during the QA loop ("the next flow has more assertions; let me checkpoint"). The contract closes that, without invalidating legitimate pre-flow decisions about whether QA can sensibly run at all.
>
> ### Legitimate pause cases within the contract window (exhaustive within scope, no others permitted)
>
> 1. **System check fails** at Phase 1 (e.g. test suite red, typecheck broken). The QA flow can't sensibly proceed; surface and stop.
> 2. **Playwright MCP unavailable mid-flow.** A flow that started but lost MCP connectivity; surface gap and skip remaining flows. *(Distinct from the pre-flow Playwright availability check at setup — that's out of scope per Scope above.)*
> 3. **Bug found that requires user judgment** to fix (e.g. ambiguous expected behavior; missing requirement). Surface the bug and ask the user.
> 4. **Bug fix breaks Phase 1 checks** (regression). Stop; surface state.
> 5. **User-initiated abort.**
>
> ### Anti-patterns (explicitly forbidden — same as `/en-build`)
>
> - "Phase 1 passed; should I proceed to Phase 2?" No — proceed automatically.
> - "Test fixture X is more complex; let me verify before running it." No — run it.
> - "All bugs fixed; should I run the full suite once more?" No — the autoflow already does this.
> - "Big surface area in the next flow; checkpoint here." No — advance.

## Change 4 — Drift-guard test

**File:** `tests/peer-resolution-trailer/peer-resolution-trailer.test.sh` (or a new `tests/lint/agent-autonomy-contract.test.sh` — decide at implementation time based on which test file is the better home).

**New assertions** (~18):

| # | Assertion |
|---|---|
| 1 | `skills/en-build/SKILL.md` has an "Agent autonomy contract" section (heading match). |
| 2 | The contract section enumerates all seven legitimate pause cases (each case's keyword appears at least once in the section). Cases 1–2 are marked as "out of contract window" or equivalent so readers don't mistake them for forbidden-when-they-fire. |
| 3 | The contract section has an explicit **"Scope of the contract"** subsection that names "the inter-unit main loop" (or close equivalent) as the contract's window of applicability. Test asserts the literal phrase "Scope of the contract" appears in the section. |
| 4 | The scope subsection explicitly names "Steps 1–8 are NOT governed by this contract" (or close equivalent), so existing preflight prompts (sub-state matrix, host detection, plan review) are recognized as out-of-scope and legitimate. |
| 5 | The contract section uses the phrase "exhaustive within scope, no others permitted" (or close equivalent — note the "within scope" qualifier; bare "exhaustive, no others permitted" without the scope qualifier is the language that caused the PR #20 review finding). |
| 6 | At least four explicit anti-patterns are documented in the contract section. |
| 7 | The "Right response to LLM uncertainty: advance, not ask" framing is present (catches drift back to "when uncertain, prompt"). |
| 8 | The "What this skill never does" section includes "Never inserts agent-initiated checkpoints" (or close equivalent). |
| 9 | The contract section references the failure-protocol table as the safety net for "things go wrong" cases (so the agent understands the alternative to self-pausing is the existing failure-protocol catch). |
| 10 | The contract section explicitly mentions that per-unit progress-report "Note:" lines are the right place for agent observations — they're informational, not gating. |
| 11 | `skills/en-qa/SKILL.md` has the same contract section, scoped to QA flows. |
| 12 | en-qa's contract has its own "Scope of the contract" subsection naming "already-runnable QA flows" (or close equivalent) and explicitly lists pre-flow setup (URL discovery, Phase 2 skip on doc-only / `--system-only`, Playwright bootstrap offer) as out of scope. |
| 13 | en-qa's contract enumerates the five QA-scoped legitimate pauses. |
| 14 | en-qa's contract includes explicit anti-patterns. |
| 15 | en-qa's contract uses "exhaustive within scope, no others permitted" (matching en-build's scoped wording). |
| 16 | The forbidden phrase "should I continue?" appears in the anti-patterns of at least one of the two skills (catches drift back to that exact wording). |
| 17 | The forbidden phrase "let me verify" appears in the anti-patterns of at least one of the two skills. |
| 18 | Existing preflight prompts in en-build SKILL.md (the sub-state matrix's "Offer auto-commit", "Offer finalize-and-build", "Refuse; user must apply findings first" handlers) are NOT removed or altered by the contract — drift guard checks they remain present in step 4 / the pre-flight sub-state matrix. Catches accidental over-application of the contract during implementation. |

## Change 5 — `docs/foundation.md` decision entry

Add a decision entry to `docs/foundation.md` (number TBD at implementation time):

> **D-N. Autonomous execution is the contract; agent-initiated pauses are forbidden.** `/en-build` and `/en-qa` are designed to execute plans autonomously after user authorization at plan time. Only documented pause cases (universal safety gates, opt-in flags, failure protocols) are legitimate. Agent-initiated checkpoints based on independent judgment — "this next unit is bigger," "let me verify before continuing," "should I proceed?" — are explicit anti-patterns. Rationale: the user already authorized the work at plan time (peer-reviewed plan, `status: open`, hash recorded); per-unit pauses bypass that authorization. The safety net for "things go wrong" is the failure-protocol table (gate failures, peer rejects, hash mismatches, etc.), not agent self-judgment. When in doubt, advance; surface observations in per-unit progress reports, not as gating prompts.

## Implementation outline

4 units, Standard depth. Build order doesn't matter much — they're independent.

- **U1** — `skills/en-build/SKILL.md`: add "Agent autonomy contract" section (full text per Change 1). Add the new bullet to "What this skill never does" (Change 2). Approximately +60 lines.

  **Risk:** low (prose addition only; no behavior change in code paths). **Category:** other (doc/spec update). **Gated:** false.

- **U2** — `skills/en-qa/SKILL.md`: add the mirrored "Agent autonomy contract" section (per Change 3). Approximately +30 lines.

  **Risk:** low. **Category:** other. **Gated:** false.

- **U3** — `tests/lint/agent-autonomy-contract.test.sh` (new file) OR add to `tests/peer-resolution-trailer/peer-resolution-trailer.test.sh`: +14 drift-guard assertions per the table above.

  **Risk:** low. **Category:** feature. **Gated:** false.

- **U4** — `docs/foundation.md`: add decision entry per Change 5.

  **Risk:** low. **Category:** other (doc update). **Gated:** false.

## What's deliberately NOT in this PR

- **Runtime detection.** We can't realistically detect "the agent inserted its own pause" at runtime — that would require monitoring agent outputs for pause-shaped text, which is fragile. The fix is upstream (skill prose tightens the contract); detection isn't in scope.
- **Extending to other skills.** en-plan, en-foundation, en-brainstorm, en-cross-review, en-review, etc. have different shapes (single-pass synthesis, prompt-and-go) where agent autonomy is less critical. If those skills surface the same friction, address them in follow-up PRs.
- **A `--strict-autonomy` or `--no-pause-ever` flag.** Adding a knob implies the default isn't autonomous enough — but the spec says it IS autonomous by default. Adding a flag would weaken the contract by suggesting "default is somewhere on a spectrum." Better to tighten the default.
- **Re-applying the contract to past in-flight builds.** The contract applies to future builds. Past skipped builds stay as they are; the user just re-runs with the new contract in place.

## Open questions (for review before implementation)

1. **Should the contract section be at the top of SKILL.md (very visible) or buried after the universal safety gates section?** The PR draft places it right after universal safety gates so it's adjacent to the related concept (mandatory gates). Alternative: place it at the very top, as the first behavioral rule the agent reads.

   **My lean:** right after universal safety gates. The two sections together form "the rules of execution" — gates for what must pause, contract for everything else.

2. **Should the contract distinguish "phase-on" from "phase-off" path explicitly?** Currently it lists the seven cases together. Phasing-off path skips case #5 and #6 (P4 confirmation and `--pause`). Worth noting?

   **My lean:** mention it as a note. The seven cases are the universe; specific phasing-off context tightens the list to five (cases #1, #2, #3, #4, #7).

3. **Note-line surfacing format.** The "Note:" line for agent observations after a unit commits is recommended but not specified — should the format be standardized (e.g. `Note: <observation>` line in the per-unit progress report)? Or left to agent judgment?

   **My lean:** standardize as `Note: <observation>` — predictable parsing for future tooling (e.g. `/en-ship` could collect Note lines for the PR summary).

## Verification plan

- All existing tests still pass (this is spec-only; no behavior change in code paths).
- +14 new drift-guard assertions cover the new contract.
- Manual sanity check: read the contract section end-to-end; confirm it's unambiguous and doesn't leave room for "this case is similar to one of the seven, so it's OK."
- Manual sanity check: walk a mental U3 → U4 transition through the contract. Confirm the agent's correct action is "advance immediately, optionally add Note: line."

## Review history

Initial spec → PR #20 merged → post-merge code review surfaced two P2 findings, both addressed in-place via this follow-up PR:

| Finding | Severity | Resolution |
|---|---|---|
| The "seven cases exhaustive, no others permitted" framing omits existing en-build preflight prompts (untracked-approved → offer auto-commit; draft+revise with cleared findings → offer finalize-and-build; unresolved draft findings → refuse and ask for `/en-plan --resume`). If implemented literally, those legitimate prompts look like contract violations. | P2 | **Added "Scope of the contract" subsection** to en-build's contract. Names "the inter-unit main loop" (step 9 start → step 10 end) as the window. Steps 1–8 are explicitly OUT of scope; preflight handlers stay as-is. Cases 1–2 in the legitimate-pauses list are now labeled "out of contract window; listed for completeness." Drift-guard assertions 3, 4, 5 added to enforce the scoping in SKILL.md prose. |
| en-qa's "five exhaustive" list omits existing skip/prompt paths (URL discovery, Phase 2 skip on doc-only / `--system-only` / browser-disabled, Playwright bootstrap offer). | P2 | **Added matching "Scope of the contract" subsection** to en-qa's contract. Names "already-runnable QA flows" as the window. Pre-flow setup (URL discovery, doc-only / `--system-only` skip, Playwright bootstrap) is explicitly out of scope. Case 2 (Playwright unavailable) clarified as "mid-flow only" — pre-flow availability check is out of scope. Drift-guard assertion 12 added. |

Both fixes use the same shape: define a contract window, list cases inside the window as exhaustive, recognize legitimate handlers outside the window without trying to enumerate every prompt-emitting code path (unmaintainable). The "exhaustive, no others permitted" phrasing now reads as "exhaustive within scope, no others permitted" — the "within scope" qualifier is the load-bearing fix.

Drift-guard count: 14 → 18 (added scope assertions for both contracts + a guard against accidentally removing existing preflight handlers during implementation).

The implementation outline didn't grow — same 4 units, since both changes are within Change 1 (en-build) and Change 3 (en-qa) which were already in scope.
