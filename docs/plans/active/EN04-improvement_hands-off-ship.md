---
type: plan
plan_type: improvement
plan_id: EN04
title: Hands-off en-ship with a local self-heal loop
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

# EN04 - Hands-off en-ship with a local self-heal loop

> **Shipped design (authoritative): local self-heal, not CI.** An earlier draft of this plan (units U3–U5, retained in history below) moved the self-heal fix loop *into* CI via an `en-ship-watch.yml` workflow + `bin/en-ship-watch-ci` wrapper. That direction was **reversed during build, per user decision** — those artifacts were removed. Fixing happens **locally**; CI is read-only. The sections below describe what actually shipped. Foundation **D38** is the canonical record. **Do not reintroduce a CI-side writer / `en-ship-watch.yml` / write-capable runner.**

## Context

A review of the `no-mistakes` git-push-gate tool surfaced one property en-ship lacks: **no babysitting** — you kick off shipping, and the process self-heals PR findings and lands a mergeable PR without you hand-applying each fix. no-mistakes does this by fixing **locally** (in a local daemon's worktree, with the local agent). EN04 adopts that principle: the self-heal fix loop runs **on the developer's machine**, not in CI.

`/en-ship` becomes **hands-off by default** and, after opening the PR, runs a **session-bound local watch-and-fix loop**: CI runs tests + a review model posts findings; en-ship watches for those, drives `/en-resolve-pr` to fix them locally, pushes, re-validates, and loops until the PR is green with no unresolved findings.

Alongside, the **learning checkpoint moves from en-ship to en-build completion**, per an explicit user requirement. This is not a naive move: [en-learn-checkpoint-spec.md](../../en-learn-checkpoint-spec.md) placed the checkpoint in en-ship *specifically because* the en-build/en-qa soft prompts drop under context pressure (the PR #18 fix). So EN04 promotes en-build's soft auto-invoke into a **structured, non-droppable checkpoint** (visible outcome line, four canonical values) — preserving the anti-drop property at a point where the user is present.

## Out of scope for this plan (deliberately)

- **CI-side fixing / a write-capable CI runner.** Fixing is local; CI reviews only. (This is the reversal — see the banner above.)
- **A local background daemon.** The loop is session-bound (runs while the `/en-ship` session is open); no detached daemon is shipped.
- **Changing the plan-completion checkpoint's contract.** It stays in en-ship as the lifecycle backstop; EN04 only makes it *auto-resolve* under hands-off. Its outcome enum and placement are unchanged.
- **en-qa changes.** en-qa's broadened capture prompt is untouched here.

## Approach (high-level, as shipped)

- **U1** relocates the learning checkpoint to **en-build completion** as a structured, non-droppable step. (depends: none)
- **U2** makes **en-ship's preflight hands-off**: removes the learning checkpoint, auto-resolves scope + the plan-completion checkpoint, adds `--interactive`, records D38. (depends: U1)
- **Local watch-and-fix loop** (en-ship step 13, the shipped self-heal): after the PR opens, poll CI + review findings (via the comprehensive `get-pr-comments` fetch), gate on trusted authors, drive `/en-resolve-pr` locally to fix (routing failing-check logs and review threads), loop until clean (bounded `watch.max_cycles`, default 3), then escalate. `--auto-merge` (opt-in, armed once clean) and `--no-watch`.

**History (superseded).** The plan originally built the self-heal loop in CI as U3 (`en-ship-watch.yml` + `bin/en-ship-watch-ci`), U4 (en-setup install), and U5 (en-ship arms the CI watcher). Six review passes surfaced escalating security problems (a `workflow_run` pwn-request vuln, a required write-token in CI, fork-checkout safety, plugin-in-CI). The user then corrected the direction: **fix locally, not in CI.** U3/U4 artifacts were deleted and U5 was replaced by the local loop. The U3–U5 unit descriptions are retained below strictly as a historical record — **not** as buildable work.

## Decisions, assumptions & risks (as shipped)

- **Decision — self-heal is LOCAL, not CI.** *Rejected alternative:* a CI-hosted fix workflow (built as U3–U5, then removed). *Why:* a CI job that *writes* fixes needs repo-write + API secrets in the runner, which opens the `workflow_run` pwn-request class and a fork-safety surface. Fixing locally keeps all write access + secrets on the developer's machine; CI stays read-only (tests + a review model). Simpler and safer.
- **Decision — session-bound, not a detached daemon.** *Why:* Ensemble is a skill suite, not a compiled binary; a robust local daemon (crash recovery, state, service lifecycle) is out of scope. The loop runs while the `/en-ship` session is open — automated (no hand-applying fixes) but not full close-the-laptop walk-away.
- **Decision — trusted-source gate on findings.** Only auto-fix findings from trusted authors (PR author, collaborator/CODEOWNERS, recognized review bot) on same-repo PRs. A PR comment is untrusted input; blindly fixing from it is a prompt-injection vector.
- **Decision — promote, don't just move, the learning checkpoint.** The en-build checkpoint is structured (visible outcome line, four canonical values) to preserve the PR #18 anti-drop guarantee.
- **Decision — hands-off is the default; `--interactive` is the escape hatch.** A **breaking change** to en-ship's contract (D38), acceptable pre-1.0.
- **Risk — session-bound loop dies with the session.** Accepted: automated fixing without hand-holding is the goal; full walk-away would need a daemon (out of scope).
- **Risk — loop spins on an unfixable finding.** *Mitigation:* bounded to `watch.max_cycles` (default 3), then escalate the remainder as `needs-human`.

## Technical design (as shipped)

```
/en-ship (hands-off default)
  preflight (auto-resolve scope; HARD-STOP on secrets / push-to-default / destructive)
    → plan-completion checkpoint: auto-y if build verifiably complete, else informational
    → commit → push → open PR
    → LOCAL watch-and-fix loop (step 13):
         poll CI (gh pr checks) + review findings (get-pr-comments: inline threads + review bodies + comments)
         → trusted-source gate (PR author / collaborator / review bot; same-repo; head-SHA match)
         → fix locally via /en-resolve-pr (failing-check logs AND review threads) → push → re-poll
         → loop until green + no unresolved findings (bounded watch.max_cycles=3) → else escalate needs-human
    → --auto-merge (opt-in): arm `gh pr merge --auto --squash` ONLY once the loop is clean
```

CI's role is **read-only**: run tests + let a review model (Anthropic Code Review action, CodeRabbit, `/en-sweep`'s review) post findings. No CI-side writer, no `en-ship-watch.yml`, no new secret.

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
  3. **`--interactive` flag:** restore the removed checkpoints, including a lightweight learning prompt for the direct-to-ship path where no en-build ran.
  4. **D38** in `docs/foundation.md` §4.1 covering: hands-off default (breaking change), learning-checkpoint relocation to en-build, plan-completion auto-resolve under hands-off, and the local watch-and-fix loop. *(As shipped, D38 records the local self-heal design; the `--auto-merge` flag and the local loop landed in en-ship's step 13/14 — see the shipped design above.)*
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

### U3. CI-hosted self-heal engine: workflow template + bin wrapper — ⚠️ SUPERSEDED / REMOVED

> **This unit was built, then removed** when the direction was reversed to local self-heal (see the banner at the top of this plan and D38). `en-ship-watch.yml`, `bin/en-ship-watch-ci`, and their tests do **not** exist in the shipped tree. Kept only as a historical record — do not build.

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

### U4. en-setup installs the watch workflow + wrapper — ⚠️ SUPERSEDED / REMOVED

> **Built then removed** with U3 (local-self-heal reversal). en-setup does **not** install any en-ship-watch workflow/wrapper in the shipped tree. Historical record only — do not build.

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

### U5. en-ship post-PR hands-off: `--auto-merge`, watcher integration, graceful degradation — ⚠️ SUPERSEDED

> **The CI-watcher parts of this unit were reversed.** As shipped, en-ship's step 13 is the **local** watch-and-fix loop (not a CI-watcher arm); `--auto-merge` survives (armed once the local loop is clean). Historical record of the CI-first design below — do not build the watcher-arm/degradation parts.

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

## Verification (whole plan, as shipped)

- `bash tests/run.sh` - full suite green.
- `bin/ensemble-lint --scope docs/` - exit 0 (no cross-link / frontmatter / unit drift).
- Manual spot-check: the four canonical learning-checkpoint values are spelled identically across en-build SKILL, the spec, and tests; en-ship no longer contains a learning checkpoint; the hands-off safety floor (secrets / push-to-default / destructive) is preserved as hard-stops; **no `en-ship-watch.yml` / `bin/en-ship-watch-ci` / CI-side writer exists** (the local-self-heal reversal).
- Branch-level cross-agent review at build completion (D35) + subsequent `/en-review` passes, verdicts recorded via `review-verdict:` trailers.
