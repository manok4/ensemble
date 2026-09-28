---
type: plan
plan_type: feature
plan_id: EN23
title: /en-fix, small bug fixes and improvements from request to PR without a plan
status: open
location: active
created: 2026-09-27
shipped:
deepened:
covers_requirements: []
requirements_pending: false
related_design: docs/designs/2026-09-27-en-fix-small-changes-design.md
peer_review_verdict: revise
peer_review_iterations: 2
peer_review_last_run: 2026-09-27
peer_review_plan_hash: 76bef54c89c67b7bbb3103a53de385d2d80d0f720cc4253502dab16253b9ca2d
peer_review_resolutions:
  - {finding_id: 1-1, iteration: 1, severity: P1, title: "Review edits bypass the risk check", status: applied, location: U1}
  - {finding_id: 1-2, iteration: 1, severity: P1, title: "Core intake and stop paths lack concrete scenarios", status: applied, location: U1}
  - {finding_id: 2-1, iteration: 2, severity: P1, title: "Bug label overrides the user's stated intent", status: applied, location: U1}
  - {finding_id: 2-2, iteration: 2, severity: P1, title: "Identifier-only requests lack a defined diagnosis handoff", status: applied, location: U1}
  - {finding_id: 2-3, iteration: 2, severity: P1, title: "Diagnosis-only behavior lacks concrete scenarios", status: applied, location: U2}
  - {finding_id: 2-4, iteration: 2, severity: P1, title: "No-file routing lacks a request-to-outcome scenario", status: applied, location: U3}
depth: standard
data_scale: small
---

# EN23: /en-fix, small bug fixes and improvements from request to PR without a plan

## Context

Small work has no complete route. `/en-plan`'s no-file path stops at a description of the change, `/en-debug` code mode fixes bugs but not improvements and runs no review, and `/en-build` needs a plan file. The design doc settles the shape: one manual-invoke skill takes one small bug or improvement to a reviewed PR, and `/en-debug` goes back to diagnosis only. This plan builds it.

## Requirements covered

None. Ensemble's foundation carries no R-IDs for skill-suite work; the decision lands as D124.

## Out of scope for this plan

- `/en-qa`'s inline fix loop. It fixes bugs on the branch it is testing and stays as is.
- Linear status writes or comments from `/en-fix`.
- Any change to `/en-review`'s or `/en-ship`'s SKILL.md. Only `/en-review`'s CONTRACT.md gains a caller row.
- A line-count size limit on `/en-fix` changes (design decision 2).

## Approach (high-level)

A new skill, `skills/en-fix/`, invokes existing skills in order and owns no review or ship logic of its own. For a bug it invokes `/en-debug` through a new contract that guarantees no blocking question and returns a verdict; it proceeds only on `convergent`. For an improvement it prints a three-line spec and confirms only when triage marked the request ambiguous. Both paths write a test first, run lint, typecheck and targeted tests, re-run the risk-surface check on the real diff, commit, run `/en-review --lite --mode headless`, verify a receipt for the current tree, then invoke `/en-ship`.

`/en-debug` then loses its fix path. When a person runs it directly, it ends with the diagnosis and suggests `/en-fix`. `/en-plan`'s no-file path suggests `/en-fix` too. Both *suggest* rather than invoke: `/en-fix` is `disable-model-invocation: true`, and `tests/lint/contract-shape.test.sh:52-61` forbids a skill invoking a manual-only one.

**Byte budgets** (leanness rule; the build records each delta in the commit body):

| File | Size now | Budget |
|---|---|---|
| `skills/en-fix/SKILL.md` | new | 14,000 bytes or fewer |
| `skills/en-debug/SKILL.md` | 17,412 | must shrink; net delta negative |
| `skills/en-plan/SKILL.md` | 24,291 (cap 24,576) | +40 bytes or fewer |

## Test seams

One seam, which already exists: skill and contract text checked by `tests/lint/*.test.sh` through `tests/lib/assert.sh`, ending in `report`. The harness cannot execute a skill, so there is no end-to-end run. Order-sensitive rules are checked by comparing line numbers, the pattern `tests/lint/en-debug-fix-loop.test.sh:85-91` already uses. Parity, payload, catalog and contract tests already cover the new directory once it exists.

## Technical design

```
/en-fix <request | file:line | IDENT | TD<N>>
  1 intake     ── Linear get_issue (+labels, comments) | tracker entry | words
  2 triage     ── bug|improvement: user's explicit word > Linear Bug label > stated call
               ── one concern, no risk surface (diff-signal-detection.md) ── else offer /en-plan, stop
  3 branch     ── on default: <IDENT>-<slug> | td<N>-<slug> | fix-<slug>; record pre-fix scope
  4a bug       ── invoke /en-debug with the user's words plus the resolved issue or tracker text (D70)
               ── verdict != convergent → show, stop
  4b improve   ── 3-line spec (change, test, files); confirm only if ambiguous
  5 change     ── failing test → minimal change → targeted tests, lint, typecheck; 3 failed fixes → stop
  6 recheck    ── risk surface on the real diff ── trips → offer /en-plan, stop uncommitted
  7 commit     ── one Conventional Commit; TD<N> moved to Resolved; Linear IDENT referenced
  8 review     ── invoke /en-review --lite --mode headless --base <merge-base>
               ── P0, or a block in round 2 → stop, report, offer /en-plan
               ── review applied edits → re-run the step 6 risk check on the branch diff
  9 receipt    ── ensemble-verification-receipt verify for this tree ── fail → stop
 10 ship       ── invoke /en-ship (pass --no-watch, --auto-merge only when given)
```

`/en-debug` contract return: `verdict` is exactly one of `convergent`, `divergent`, `design-problem`, `unresolved`, plus the causal chain with `file:line`, the proposed fix and the tests to add.

## Implementation units

Each unit has a stable U-ID. Never renumbered after assignment.

### U1. Add the `/en-fix` skill and the contracts it calls through

- **Goal:** `/en-fix` exists, is manual-invoke only, and runs the ten-step flow above through `/en-debug`, `/en-review` and `/en-ship`.
- **Requirements covered:** none
- **Dependencies:** none
- **Interfaces:**
  - *Produces:* `skills/en-debug/CONTRACT.md` with `## Accepted invocations` row `/en-debug <words>` for caller `en-fix`, a `## Non-interactive guarantee` stating no blocking question when a skill invokes it, and a `## Return` whose `verdict` field takes exactly `convergent` · `divergent` · `design-problem` · `unresolved`. U2 edits `/en-debug`'s SKILL.md to honour it.
- **Files:**
  - `skills/en-fix/SKILL.md` (new)
  - `skills/en-fix/scripts/ensemble-verification-receipt` (new, byte-identical copy)
  - `skills/en-fix/references/diff-signal-detection.md` (new, byte-identical copy)
  - `skills/en-fix/references/script-invocation.md` (new, byte-identical copy)
  - `skills/en-debug/CONTRACT.md` (new)
  - `skills/en-debug/SKILL.md` (caller-aware line only: when a skill invokes it, skip the fix-choice gate and return per CONTRACT.md)
  - `skills/en-review/CONTRACT.md` (new `## Accepted invocations` row for `en-fix`)
  - `README.md` (skill catalog row, total-count sentence)
  - `docs/foundation.md` (§5.1 row, new `#### 5.2.18 en-fix`, repository-layout comment drops "11 skills")
  - `docs/plans/tech-debt-tracker.md` (TD31 moved to Resolved)
  - `tests/lint/en-fix.test.sh` (new)
- **Approach:**
  - SKILL.md frontmatter: `name: en-fix`, `disable-model-invocation: true`, a description of 300 characters or fewer ending in trigger phrases.
  - Steps follow the Technical design block. The test-first loop, pre-fix scope record and three-failed-fixes rule are written fresh in `/en-fix`; U2 deletes the originals from `/en-debug`.
  - Invocations use the verb "invoke" so `contract-shape.test.sh` derives the callees, and pass the user's words rather than `$ARGUMENTS` (D70). For an identifier or `TD<N>` request, the `/en-debug` invocation also carries the text intake resolved: the issue title, description and comments, or the tracker entry. `/en-debug` never has to fetch from Linear.
  - Classification precedence: the user's explicit word ("this is an improvement") beats a Linear Bug label, which beats the stated judgment.
  - Linear branch names are built as `<IDENT>-<slug>`, as `skills/en-build/references/build-preflight.md:150` does. Nothing reads a branch name from the issue.
  - A recursion guard exits when `ENSEMBLE_PEER_REVIEW=true`.
  - The `/en-debug` SKILL.md edit is one line in its opening notes. It replaces the line-16 claim that no skill invokes it with a pointer to CONTRACT.md. Its direct-run fix path stays until U2.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:** Each request below names the SKILL.md instruction `en-fix.test.sh` asserts for it, scoped to the step that handles it.
  - *Happy path, bug:* `/en-fix "login 500s when email is null"` → the bug branch invokes `/en-debug`, and on `convergent` writes a failing test before the change.
  - *Happy path, improvement:* `/en-fix "make the CSV export include a header row"` → no `/en-debug` invoke; the three-line spec (change, test, files) is printed, and the confirmation question is conditioned on triage marking the request ambiguous.
  - *Happy path, Linear:* `/en-fix EMB-42` with a Bug label and no other words → bug path, branch `EMB-42-<slug>`, the `/en-debug` invocation carries the issue's title, description and comments, and the identifier is referenced in the commit.
  - *Edge case, conflict:* `/en-fix EMB-43 this is an improvement, add a retry` where EMB-43 has a Bug label → improvement path, no `/en-debug` invoke.
  - *Happy path, order:* `en-fix.test.sh` finds `disable-model-invocation: true` in the frontmatter, and finds invoke `/en-debug`, `/en-review --lite --mode headless`, `ensemble-verification-receipt` verify, and invoke `/en-ship`, in that line order.
  - *Stop path, diagnosis:* `/en-debug` returns `divergent`, `design-problem` or `unresolved` → show the diagnosis and stop, with no edit; `design-problem` also offers `/en-brainstorm`.
  - *Stop path, fixes:* a third failed fix attempt → stop and say the design is the problem, with no fourth attempt.
  - *Stop path, review:* a P0 in the envelope, or a block in round 2 → stop before step 9, report the findings, offer `/en-plan`.
  - *Stop path, risk after review:* review edits that touch a risk surface → the step 6 check re-runs on the branch diff and stops before ship.
  - *Stop path, receipt:* `verify` exits non-zero → stop and do not invoke `/en-ship`.
  - *Happy path:* `contract-shape.test.sh` derives `en-debug` as a callee and finds `skills/en-debug/CONTRACT.md` with all six required sections. `en-debug` stays model-invocable.
  - *Edge case:* the two-round review cap, the P0 stop, the post-change risk re-check and "`--auto-merge` only when given" are each asserted as text inside the matching step.
  - *Edge case:* `/en-debug` is invoked only on the bug path: the invoke line sits in the bug branch, not before the bug/improvement split.
  - *Error path:* moving the ship step above the receipt step turns the order check red. Deleting the manual-invoke flag turns the frontmatter check red. Both are run once as negative controls at build time and reverted.
  - *Integration:* `script-parity.test.sh`, `reference-parity.test.sh`, `skill-payload.test.sh`, `readme-catalog-drift.test.sh`, `foundation-catalog-drift.test.sh`, `skill-size.test.sh` and `skill-description-budget.test.sh` all pass with the new directory.
- **Verification:** `./tests/run.sh` passes; `bin/ensemble-lint` is clean; the negative controls went red and were reverted; the SKILL.md sizes are in the commit body.

### U2. Make `/en-debug` diagnosis-only

- **Goal:** `/en-debug` never writes code. A direct run ends with the diagnosis and suggests `/en-fix`; a skill caller gets the contract return.
- **Requirements covered:** none
- **Dependencies:** U1
- **Files:**
  - `skills/en-debug/SKILL.md`
  - `tests/lint/en-debug-fix-loop.test.sh` → `tests/lint/en-debug-diagnosis.test.sh` (renamed and rewritten)
  - `README.md` (catalog row 10 wording)
  - `docs/foundation.md` (D124, amending D62 and D89; §5.1 and §5.2 `en-debug` wording)
- **Approach:**
  - Delete the fix-choice gate's "Fix it now" option (lines 141-144) and step 4 (145-149). Keep the convergent/divergent classification (135-137): it now sets the contract verdict. Keep the findings-before-question ordering rule for the remaining choice, which is "Suggest `/en-fix`", "Diagnosis only" or "Rethink the design (`/en-brainstorm`)".
  - Rewrite step 5's handoff: suggest `/en-fix` when the verdict is `convergent`, with no mention of `/en-ship`. Update the description so "code mode fixes only on request" becomes diagnosis-only. Keep D89's required "telemetry mode" wording.
  - Use "suggest", never "invoke", before `/en-fix`, so `contract-shape.test.sh` does not derive it as a callee.
  - D124 records: `/en-fix` is the sole writer of small changes, `/en-debug` diagnoses only, and bug versus improvement is D62's convergent versus divergent split. A user's improvement request is the decision `/en-debug` will not make alone. This is where the learning the capture gate declined on 2026-09-27 lives.
  - Test rewrite: keep the assertions unrelated to fixing (both modes, telemetry read-only, the causal-chain gate, debug-investigation.md wiring, the five investigation techniques, the research-dispatch row, D89 description wording). Invert the fix assertions: no "Fix it now", no step that edits source, and the handoff names `/en-fix`.
- **Risk:** medium
- **Category:** removal
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:** Each run below names the SKILL.md instruction `en-debug-diagnosis.test.sh` asserts for it.
  - *Direct run, convergent:* `/en-debug "checkout total is off by one cent"` → the diagnosis block (causal chain, `file:line`, proposed fix, tests to add) is written before the choice, the choice offers "Suggest `/en-fix`", and no step edits a source file.
  - *Direct run, design problem:* evidence spans subsystems → verdict `design-problem`, and the choice offers `/en-brainstorm`.
  - *Skill caller:* invoked by `/en-fix` → no blocking-question tool is called, and the return carries `verdict` as one of the four contract values, plus the causal chain.
  - *Skill caller, unresolved:* hypotheses exhausted → `verdict: unresolved` with the invalidated hypotheses listed, and no edit.
  - *Happy path:* `en-debug-diagnosis.test.sh` finds the convergent/divergent vocabulary, the contract verdict names, and a handoff naming `/en-fix`.
  - *Edge case:* the findings block still precedes the blocking choice by line number, and the choice lists exactly the three options.
  - *Error path:* re-adding a "Fix it now" line or a test-first edit step turns the test red. This is run once as a negative control and reverted.
  - *Integration:* `contract-shape.test.sh` still derives exactly the callee set from U1 (`/en-fix` is not derived). `prompting-guide-lines.test.sh:45` still passes. `skill-size.test.sh` passes, and en-debug's SKILL.md is smaller than 17,412 bytes.
- **Verification:** `./tests/run.sh` passes; the byte delta for `skills/en-debug/SKILL.md` is negative and recorded in the commit body; no file under `tests/` still references `en-debug-fix-loop.test.sh`.

### U3. `/en-plan`'s no-file path suggests `/en-fix`

- **Goal:** a user who takes the no-file path is pointed to `/en-fix` instead of being told to make the edit by hand.
- **Requirements covered:** none
- **Dependencies:** U1
- **Files:**
  - `skills/en-plan/SKILL.md` (line 100)
  - `skills/en-plan/references/plan-prewrite.md` (lines 17-19, same text)
  - `tests/lint/en-plan-warranted-gate.test.sh` (check 5, lines 79-85)
- **Approach:** Rewrite line 100: on the no-file path, state the change and suggest `/en-fix`. There is still no file, no U-IDs and no peer review, and `/en-build` still does not apply. Make the same edit to the offer and consequence text in `plan-prewrite.md`. Replace words rather than add a sentence, so SKILL.md stays within +40 bytes. Use "suggest", never "invoke". Check 5 asserts "no file, no U-IDs" and `/en-fix`, in place of "consumes a plan file".
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Request to outcome:* `/en-plan "fix the typo in the --verbose help text"` qualifies (Lightweight, one unit, `risk: low`, no design doc) → the user takes the no-file path, and gets no plan file, no U-IDs and a suggestion to run `/en-fix`. Check 5 asserts that instruction inside the gate block.
  - *Happy path:* check 5 finds "no file, no U-IDs" and `/en-fix` inside the gate block.
  - *Edge case:* `skill-size.test.sh` passes, and `skills/en-plan/SKILL.md` grows 40 bytes or fewer.
  - *Error path:* reverting line 100 to the old text turns check 5 red. This is run once as a negative control.
- **Verification:** `./tests/run.sh -k en-plan` and `./tests/run.sh -k skill-size` pass; the byte delta is in the commit body.

## Decisions, assumptions & risks

- **Decision:** the receipt check proves no edit landed after review. `/en-fix` writes no receipt itself, so a receipt that is valid for the post-change tree can only come from `/en-review`'s post-review check or an equivalent run on the identical tree. The review verdict itself comes from `/en-review`'s returned envelope.
- **Decision:** `/en-review` runs `--mode headless`. Its contract says headless never asks. A P0 halts its automatic mutation, and `/en-fix` treats a P0 in the envelope as a stop.
- **Decision:** the fix-path text moves into `/en-fix` rather than being shared. `/en-debug` keeps no copy, so nothing can drift.
- **Alternative:** `/en-build --quick` and a broadened `/en-debug` were rejected in the design doc.
- **Assumption:** the Linear MCP `get_issue` returns the issue's labels. No skill reads labels today. If the labels are missing, triage falls back to its stated judgment, and the user's explicit word still wins.
- **Assumption:** `/en-debug` picks telemetry or code mode from the words `/en-fix` passes, the same way it does for a person. The build confirms this by reading step 1's mode decision.
- **Risk:** scope creep through the easiest path to code. **Mitigation:** the risk re-check runs on the branch diff after the change and again after any review edits, and the two-round review cap stops the run; both offer `/en-plan`.
- **Risk:** `/en-plan` has 285 bytes of headroom. **Mitigation:** U3 replaces words and does not add a sentence, within a +40 byte budget.

## Tracked debt

- **Resolves:** TD31

## Iteration log

> - 2026-09-27 (initial): plan v0 from `docs/designs/2026-09-27-en-fix-small-changes-design.md` and two planning rounds.
> - 2026-09-27 (iteration 1): peer (codex) verdict revise, two P1s applied. The risk check re-runs after review edits (1-1). U1 gained concrete request-to-outcome scenarios for both paths and every stop (1-2).
> - 2026-09-27 (iteration 2): peer (codex) verdict revise, four P1s applied; reloop cap reached. The user's explicit word now outranks a Bug label (2-1). The `/en-debug` invocation carries resolved issue or tracker text (2-2). U2 and U3 gained request-to-outcome scenarios (2-3, 2-4).
