---
type: plan
plan_type: improvement
plan_id: EN04
title: Hands-off en-ship with CI-hosted self-heal
status: in_progress
location: active
created: 2026-07-03
shipped:
deepened:
covers_requirements: []
requirements_pending: false
related_design:
peer_review_verdict: approve
peer_review_iterations: 2
peer_review_last_run: 2026-07-03
peer_review_plan_hash: 91ef0ccb6b41c4a014e1b36135fac4d3d8c6be2452f9723521ab33884d694329
peer_review_resolutions:
  - finding_id: "1-1"
    iteration: 1
    severity: P2
    title: "U2 depends on U3 but is ordered before it"
    status: applied
    rationale: "Split U2 into watcher-agnostic hands-off preflight (U2, depends U1 only) and watcher integration (U5, depends U2+U3, sequenced after U3). Dependency inversion removed."
    location: "Implementation units / Approach ordering"
  - finding_id: "1-2"
    iteration: 1
    severity: P3
    title: "U2 risk understates contract and automation blast radius"
    status: applied
    rationale: "Same split reduces blast radius per unit. Kept risk medium and gated:false for both (no production-state change); did not raise to high since the changes are skill-doc + CI-config, not destructive or production-mutating."
    location: "U2 risk / approach"
depth: standard
data_scale: small
---

# EN04 - Hands-off en-ship with CI-hosted self-heal

## Context

A review of the `no-mistakes` git-push-gate tool surfaced one property en-ship lacks: **no babysitting** - you kick off shipping and walk away, and the process self-heals CI failures and lands a mergeable PR without you keeping a session open. no-mistakes achieves this with a persistent local daemon. Ensemble can't ship a daemon (it's a skill suite, not a compiled binary), but it already has a daemon available for free - GitHub Actions.

This plan makes `/en-ship` **hands-off by default** and moves the self-heal loop off the local session into a CI-hosted, event-driven workflow. The user runs `/en-ship`, closes the laptop, and returns to a green, mergeable PR (or a merged one under `--auto-merge`).

Two kinds of babysitting are removed:

1. **Decision-babysitting** - en-ship's mid-flow interactive checkpoints (learning, scope) become auto-resolve, with a hard-stop safety floor (secrets / push-to-default-branch / destructive) that never auto-resolves.
2. **Session-babysitting** - the local watch-and-fix loop (current en-ship step 13, session-bound) is replaced by a CI-hosted `en-ship-watch.yml` that self-heals failures in the runner and survives the session ending.

Alongside, the **learning checkpoint moves from en-ship to en-build completion**, per an explicit user requirement. This is not a naive move: [en-learn-checkpoint-spec.md](../../en-learn-checkpoint-spec.md) placed the checkpoint in en-ship *specifically because* the en-build/en-qa soft prompts drop under context pressure (the PR #18 fix). So EN04 promotes en-build's soft auto-invoke into a **structured, non-droppable checkpoint** (visible outcome line, the four canonical outcome values) - preserving the anti-drop property at a point where the user is present and context is freshest.

The priority is **performance (walk-away reliability) first, then speed, then cost**. The CI-hosted watcher is event-driven (fires only on a CI failure, not polling), so it is cheaper to run than no-mistakes' polling daemon and - on public repos - effectively free beyond model tokens.

## Out of scope for this plan (deliberately)

- **A local background daemon.** The "don't become no-mistakes" boundary - GitHub Actions is the daemon.
- **Changing the plan-completion checkpoint's contract.** It stays in en-ship as the lifecycle backstop; EN04 only makes it *auto-resolve* under hands-off (auto-`y` when the build is verifiably complete; informational pass on `incomplete_build`). Its outcome enum and placement are unchanged.
- **Merging without a human by default.** Default stops at PR-ready; `--auto-merge` is opt-in.
- **en-qa changes.** en-qa's broadened capture prompt (from the learn-checkpoint spec) is untouched here.
- **New provider support / multi-SCM.** GitHub-only, matching the existing en-sweep/claude-review workflows.

## Approach (high-level)

Five units, sequenced so every dependency is built before its dependents. The learning checkpoint gets a new, structured home in en-build (U1). en-ship's hands-off *preflight* change (U2) is deliberately **watcher-agnostic** - it depends only on U1, not on the CI engine. The self-heal engine is a new CI workflow + bin wrapper (U3), installed by en-setup (U4). Only then does en-ship's *post-PR* watcher integration (U5) land, depending on both the hands-off preflight (U2) and the engine (U3).

- **U1** relocates the learning checkpoint to en-build as a structured, non-droppable step. (depends: none)
- **U2** makes en-ship's preflight hands-off: removes the learning checkpoint, auto-resolves scope + the plan-completion checkpoint, adds `--interactive`, records decision D38. Watcher-agnostic. (depends: U1)
- **U3** builds the CI self-heal engine: `github-workflow-en-ship-watch.yml` (event-driven on `check_suite: completed` failure for labeled PRs) + `bin/en-ship-watch-ci` (drives en-resolve-pr headless, bounded to 3 attempts, branch-only writes, escalates by dropping the label). (depends: none)
- **U4** teaches en-setup to install the workflow + wrapper and surface the (shared) secrets. (depends: U3)
- **U5** wires en-ship's post-PR hands-off completion: `--auto-merge`, watcher detection + labeling, graceful degradation, and the watch-loop-step rewrite. (depends: U2, U3)

**Split rationale (peer review, iteration 1).** An earlier draft folded U2 and U5 into a single "hands-off en-ship" unit that both *depended on* U3 and was sequenced *before* it - a dependency-order inconsistency, and too large a blast radius for one unit. Splitting the watcher-agnostic preflight change (U2) from the watcher-integration change (U5) removes the dependency inversion and keeps each unit reviewable.

## Decisions, assumptions & risks

- **Decision - CI-hosted, not local-detached, watcher.** *Alternative considered:* a detached local background process. *Rejected:* without daemon infrastructure it is brittle (dies on reboot, no crash recovery, races the working tree). CI-hosted gets the durability property for free and survives the machine being off.
- **Decision - event-driven, not polling.** The workflow triggers on `check_suite: completed` (failure) for labeled PRs, so compute is spent only when there is a failure to fix - cheaper than no-mistakes' polling and the GitHub-native pattern.
- **Decision - reuse en-sweep's secrets, add none.** en-setup already surfaces `CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY` (+ `OPENAI_API_KEY`, `GITHUB_TOKEN`) for en-sweep. The watcher reuses them; no new secret is introduced.
- **Decision - promote, don't just move, the learning checkpoint.** *Alternative:* revert en-build's invoke to a soft prompt at build completion. *Rejected:* regresses the PR #18 silent-drop fix. The en-build checkpoint must be structured (visible outcome line, four canonical values) to preserve the anti-drop guarantee.
- **Decision - hands-off is the default; `--interactive` is the escape hatch.** This is a **breaking change** to en-ship's contract (documented in D38). Acceptable for a pre-1.0 skill suite; `--interactive` restores the prior stop-and-ask flow, including a lightweight learning prompt for the direct-to-ship (no-en-build) path.
- **Assumption - en-resolve-pr runs acceptably headless in a runner.** It has no explicit `report-only` mode (it writes), but it is already driven bounded-and-automated by en-ship's watch loop; the wrapper enforces the same 2–3 cycle cap and the recursion guard (`ENSEMBLE_PEER_REVIEW`).
- **Assumption - repos allow auto-merge + Actions with repo-write.** One-time setup, like `no-mistakes init`. en-ship degrades gracefully when the watcher is absent.
- **Risk - a write-capable runner is a security surface.** *Mitigation:* branch-only writes, never force-push the default branch, bounded attempts, and the guardrail that the wrapper refuses to touch protected refs. Called out in D38.
- **Risk - fix→CI→fix infinite loop.** *Mitigation:* hard cap of 3 fix attempts tracked via a PR-visible counter; on exhaustion the wrapper drops the watch label and comments to escalate.
- **Risk - "hands-off but nothing is watching."** *Mitigation:* en-ship detects whether `en-ship-watch.yml` is installed and never reports hands-off success when it is absent - it prints the install command and either falls back to the session-bound loop or stops cleanly at PR-ready.

## Technical design

> **Note (post-build).** The CI self-heal engine below records the *original* design. It evolved materially through the branch-level review: the trigger is `workflow_run` (not `check_suite`) with a trusted default-branch checkout + fork rejection before any PR fetch; a `EN_SHIP_WATCH_TOKEN` secret is required (a `GITHUB_TOKEN` push won't retrigger CI); the attempt counter lives in PR comments and `/en-resolve-pr` owns commit+push (the watcher never commits/pushes). The authoritative shipped design is **foundation D38** plus the `review-verdict:` commits.

### Control flow - default `/en-ship` (hands-off)

```
preflight (auto-resolve scope; HARD-STOP on secrets / push-to-default / destructive)
  → plan-completion checkpoint: auto-y if build verifiably complete, else informational
  → commit → push → open PR
  → watcher installed?
       yes → apply `en-ship-watch` label; report "watcher armed"; stop at PR-ready
             (if --auto-merge: also `gh pr merge --auto --squash`)
       no  → print `/en-setup` install command; fall back to session-bound watch OR
             stop cleanly at PR-ready (never silently claim hands-off)
```

### CI self-heal engine

`en-ship-watch.yml` (event-driven):
```
on:
  check_suite:
    types: [completed]
jobs:
  self-heal:
    if: github.event.check_suite.conclusion == 'failure'
    # gated further inside the wrapper: only PRs carrying the `en-ship-watch` label
    steps: [checkout, resolve CLI + auth env, run bin/en-ship-watch-ci]
```

`bin/en-ship-watch-ci` responsibilities (mirrors `en-sweep-ci`'s structure):
1. Resolve the PR from the failing check_suite head SHA; exit 0 (no-op) if it lacks the `en-ship-watch` label.
2. Read/increment a fix-attempt counter (PR-visible, e.g. a hidden marker in a bot comment or the label set); if `>= 3`, drop the label, comment an escalation, exit 0.
3. Fetch failed job logs; drive `/en-resolve-pr` (headless, recursion-guarded) to produce a fix.
4. If a fix was produced: commit on the PR branch, push (branch-only - refuse any write to the default branch or a force-push of a protected ref), which re-triggers CI.
5. If no fix was produced or the failure is a judgment call: drop the label + escalation comment.

### Data / state

No new persistent state. The fix-attempt bound and label are the only coordination signals, both living on the PR (GitHub is the store). No new secret - the workflow reuses en-sweep's auth env vars.

## Implementation units

### U1. Structured learning checkpoint at en-build completion

- **Goal:** Promote en-build's end-of-build soft `/en-learn` auto-invoke into a structured, non-droppable learning checkpoint so the capture decision survives context pressure at its freshest point.
- **Requirements covered:** none (no foundation R-IDs; skill-behavior change).
- **Dependencies:** none.
- **Files:** `skills/en-build/SKILL.md`, `docs/en-learn-checkpoint-spec.md`, `tests/lint/en-build-learning-checkpoint.test.sh` (new).
- **Approach:** Replace the step-10 soft prompt (`skills/en-build/SKILL.md` line ~256, "Build complete. Capture learnings? (yes / skip)") with a numbered, structured checkpoint that emits a visible `learning_checkpoint:` outcome line in the en-build report using the four canonical values from the spec - `captured (N learnings)` / `intentionally_skipped` / `up_to_date` / `ci_environment`. Reuse the spec's baseline machinery (read `docs/learnings/log.md` latest `capture | ... | <head-sha>` entry; `git log <sha>..HEAD` for scope; idempotent `up_to_date` on zero commits; `ci_environment` auto-skip under `CI=true`; `--no-learning-checkpoint` flag). Preserve the existing deferral: if the peer-evidence audit failed, defer the checkpoint until failing commits are addressed. Keep the checkpoint outside the autonomy-contract window (it fires at the en-learn hand-off, after step 10, not between units). Prepend a short "Relocated to en-build by EN04" note to `en-learn-checkpoint-spec.md` and update its resolved-decision #1 wording so the spec no longer contradicts the implementation.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - Happy path: en-build completion with new commits since last capture → the checkpoint fires and the report shows a `learning_checkpoint:` line with a canonical value. (drift guard: SKILL.md has a structured "Learning checkpoint" step at build completion emitting the outcome line)
  - Edge - idempotent: zero commits since last capture → `up_to_date`, no prompt. (drift guard asserts the idempotency branch is documented)
  - Edge - CI: `CI=true` → `ci_environment`, auto-skip. (drift guard asserts CI short-circuit)
  - Error path: peer-evidence audit failed → checkpoint deferred, not fired. (drift guard asserts the deferral clause survives)
  - Integration: the four canonical outcome values are spelled identically in SKILL.md and the test; bare `skipped` is not used as an outcome value. (drift guard mirrors the spec's assertion #4)
- **Verification:** `tests/lint/en-build-learning-checkpoint.test.sh` passes (ends with `report`); `bash tests/run.sh` green; `bin/ensemble-lint --scope docs/` exit 0; `en-learn-checkpoint-spec.md` no longer asserts an en-ship location.

### U2. Hands-off en-ship preflight: remove learning checkpoint, auto-resolve, `--interactive`, D38

- **Goal:** Make `/en-ship`'s preflight hands-off by default - remove the learning checkpoint, auto-resolve scope and the plan-completion checkpoint, add the `--interactive` escape hatch, and record decision D38. Watcher-agnostic (no dependency on the CI engine).
- **Requirements covered:** none.
- **Dependencies:** U1 (the checkpoint's new home in en-build must exist before it is removed here).
- **Files:** `skills/en-ship/SKILL.md`, `docs/foundation.md`, `docs/en-learn-checkpoint-spec.md` (cross-ref note only), `tests/lint/en-ship-hands-off.test.sh` (new).
- **Approach:**
  1. **Remove** the learning checkpoint (current step 4); renumber the remaining steps.
  2. **Hands-off preflight defaults:** auto-resolve scope-confirm; make the plan-completion checkpoint auto-resolve - auto-`y` (flip + `git mv` + set `shipped:`, atomic with the ship commit) when the build is verifiably complete via `bin/ensemble-verify-peer-evidence` (per-unit or `--branch-coverage`), and record an informational `incomplete_build` (non-gating) otherwise. **Safety floor unchanged:** secret-scan match, push to the default branch, and destructive-guardrail hits still hard-stop even in hands-off.
  3. **`--interactive` flag:** restore the removed checkpoints, including a lightweight learning prompt for the direct-to-ship path where no en-build ran. (Defining `--interactive` here keeps the flags table coherent; `--auto-merge` is added in U5 with the post-PR watcher wiring.)
  4. **D38** in `docs/foundation.md` §4.1 covering: hands-off default (breaking change), learning-checkpoint relocation to en-build, plan-completion auto-resolve under hands-off, and (forward-referencing U3/U5) the CI-hosted self-heal watcher with its guardrails.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - Happy path: default `/en-ship` runs preflight with no learning prompt and reaches commit. (drift guard: SKILL.md documents hands-off default; no learning checkpoint present in en-ship)
  - Edge - `--interactive`: restores the checkpoints incl. the direct-to-ship learning prompt. (drift guard asserts the escape hatch)
  - Edge - plan-completion auto-resolve: verifiably-complete build → auto-`y` flip; incomplete → informational, non-gating. (drift guard asserts both branches)
  - Error path - safety floor: secret-scan match / push-to-default / destructive still hard-stop under hands-off. (drift guard asserts the floor list survives and is not auto-resolved)
  - Integration - D38: foundation records the breaking-change decision with the canonical facets. (drift guard asserts D38 exists and names hands-off + relocation)
- **Verification:** `tests/lint/en-ship-hands-off.test.sh` passes (ends with `report`); `bash tests/run.sh` green; `bin/ensemble-lint --scope docs/` exit 0; foundation shows D38; grep confirms the learning checkpoint no longer appears in en-ship.

### U3. CI-hosted self-heal engine: workflow template + bin wrapper

- **Goal:** Provide the event-driven CI workflow and the bin wrapper that self-heals CI failures on a labeled PR, bounded and branch-safe.
- **Requirements covered:** none.
- **Dependencies:** none.
- **Files:** `references/templates/github-workflow-en-ship-watch.yml` (new), `bin/en-ship-watch-ci` (new), `tests/lint/en-ship-watch-ci.test.sh` (new).
- **Approach:** Model the template on `references/templates/github-workflow-en-sweep.yml` - same auth env-var block and CLI-resolution step, but triggered on `check_suite: { types: [completed] }` with an `if: conclusion == 'failure'` job guard, and delegating to `bin/en-ship-watch-ci`. Write `bin/en-ship-watch-ci` (bash, `set -euo pipefail`, mirroring `en-sweep-ci`'s shape): resolve the PR from the failing check_suite head SHA; no-op exit 0 unless the PR carries the `en-ship-watch` label; read/increment a fix-attempt counter and, at `>= 3`, drop the label + post an escalation comment and exit 0; fetch failed-job logs; drive `/en-resolve-pr` headless (recursion-guarded via `ENSEMBLE_PEER_REVIEW`); if a fix is produced, commit on the PR branch and push **branch-only** - a guard function refuses any push to the default branch or a force-push of a protected ref; if no fix or a judgment call, drop the label + escalate. Keep all logic in the wrapper (the workflow has no inline script), matching the en-sweep pattern.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - Happy path: labeled PR + failing check_suite → wrapper drives a fix and pushes to the PR branch. (test with mocked `gh`/`git`: fix path commits + pushes to the feature branch)
  - Edge - no label: unlabeled PR → wrapper no-ops exit 0. (test asserts early exit)
  - Edge - attempt cap: counter `>= 3` → drops label + escalates, no further fix. (test asserts the bound)
  - Error path - branch safety: wrapper refuses to push to the default branch / force-push a protected ref. (test asserts the guard rejects a default-branch target)
  - Integration: workflow YAML is valid and triggers on `check_suite: completed` with the failure guard. (drift guard greps the template for the trigger + job guard + wrapper invocation)
- **Verification:** `tests/lint/en-ship-watch-ci.test.sh` passes (ends with `report`); `bash -n bin/en-ship-watch-ci` clean; a YAML sanity check on the template; `bash tests/run.sh` green.

### U4. en-setup installs the watch workflow + wrapper

- **Goal:** Teach `/en-setup` to install `en-ship-watch.yml` and `bin/en-ship-watch-ci`, and surface the (shared) secrets, mirroring the en-sweep install.
- **Requirements covered:** none.
- **Dependencies:** U3 (the template + wrapper must exist to install).
- **Files:** `skills/en-setup/SKILL.md`, `tests/lint/en-setup-watch-install.test.sh` (new).
- **Approach:** Extend en-setup's workflow-install section (step 10, alongside the en-sweep install) to also copy `references/templates/github-workflow-en-ship-watch.yml` → `.github/workflows/en-ship-watch.yml` and add `bin/en-ship-watch-ci` to the project-local bin scripts installed in step 9. Note in the secrets step that the watcher **reuses en-sweep's existing secrets** (`CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY` + `GITHUB_TOKEN`) - no new secret. Make the install idempotent (refresh on re-run, like the en-sweep install). Note the repo must allow auto-merge for `--auto-merge` to function.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - Happy path: en-setup documents installing `en-ship-watch.yml` from the template + the `en-ship-watch-ci` bin script. (drift guard asserts both install lines)
  - Edge - idempotent: re-running refreshes rather than duplicating. (drift guard asserts the idempotency language)
  - Edge - shared secret: the secrets step states the watcher reuses en-sweep's secrets (no new secret). (drift guard asserts the no-new-secret note)
  - Integration: the referenced template path matches U3's file name exactly. (drift guard cross-checks the template filename)
- **Verification:** `tests/lint/en-setup-watch-install.test.sh` passes (ends with `report`); `bash tests/run.sh` green; `bin/ensemble-lint --scope docs/` exit 0.

### U5. en-ship post-PR hands-off: `--auto-merge`, watcher integration, graceful degradation

- **Goal:** Wire en-ship's post-PR completion for walk-away shipping - add `--auto-merge`, detect and arm the CI watcher, degrade gracefully when it is absent, and rewrite the watch-loop step to the CI-first model.
- **Requirements covered:** none.
- **Dependencies:** U2 (hands-off preflight must be in place), U3 (references the `en-ship-watch.yml` workflow + `en-ship-watch` label).
- **Files:** `skills/en-ship/SKILL.md`, `tests/lint/en-ship-watch-loop.test.sh` (update).
- **Approach:**
  1. **`--auto-merge` flag:** after the PR opens and the watcher is armed, run `gh pr merge --auto --squash`. Default remains stop-at-PR-ready.
  2. **Watcher integration:** after the PR opens, detect whether `.github/workflows/en-ship-watch.yml` exists; if so apply the `en-ship-watch` label and report "watcher armed, stopping at PR-ready" (or arm auto-merge under the flag).
  3. **Graceful degradation:** if the watcher is absent, print the `/en-setup` install command and either fall back to the existing session-bound watch loop or stop cleanly at PR-ready - never report hands-off success while nothing watches.
  4. **Rewrite the watch-loop step** to describe the CI-first model with the session-bound loop as the documented fallback.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - Happy path: watcher installed → en-ship applies the `en-ship-watch` label and reports "watcher armed", stopping at PR-ready. (drift guard asserts the label + arm-and-stop behavior)
  - Edge - `--auto-merge`: arms `gh pr merge --auto --squash` after the PR opens. (drift guard asserts the flag + behavior)
  - Edge - CI-first watch-loop rewrite: step 13 describes CI-hosted self-heal with session-bound fallback. (drift guard asserts the rewritten step references the CI workflow)
  - Error/degradation path: watcher absent → print install command + fallback/stop, never silent hands-off. (drift guard asserts the degradation branch and the "never claim hands-off without a watcher" invariant)
  - Integration: the label name and workflow filename referenced in en-ship match U3/U4 exactly. (drift guard cross-checks `en-ship-watch` + `en-ship-watch.yml`)
- **Verification:** updated `tests/lint/en-ship-watch-loop.test.sh` passes (ends with `report`); `bash tests/run.sh` green; grep confirms en-ship references the watcher label + workflow name consistently with U3/U4.

## Verification (whole plan)

- `bash tests/run.sh` - full suite green (new: 5 test files; updated: 1).
- `bin/ensemble-lint --scope docs/` - exit 0 (no cross-link / frontmatter / unit drift).
- `bash -n bin/en-ship-watch-ci` - syntax clean; YAML sanity on the new workflow template.
- Manual spot-check: the four canonical learning-checkpoint values are spelled identically across en-build SKILL, the spec, and tests; en-ship no longer contains a learning checkpoint; the hands-off safety floor (secrets / push-to-default / destructive) is preserved as hard-stops.
- Branch-level cross-agent review at build completion (D35), verdict recorded via the `review-verdict:` trailer.
