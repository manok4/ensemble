---
type: plan
plan_type: bug
plan_id: EN10
title: fix Codex --max-turns flag drift in the cross-agent peer contract
status: in_progress
location: active
created: 2026-07-20
shipped:
deepened:
covers_requirements: []
requirements_pending: false
related_design:
peer_review_verdict: approve
peer_review_iterations: 2
peer_review_last_run: 2026-07-20
peer_review_plan_hash: b28808b8754b8071cb88f9cfc7f58f4f09cb42600ba1fc03405475ae664f4249
peer_review_resolutions:
  - finding_id: EN10-PR-001
    iteration: 1
    severity: P1
    title: Drift test does not enforce parameterization at every peer call site
    status: applied
    location: U4 approach + test scenarios (full peer-contract scope + build-handoff)
  - finding_id: EN10-PR-002
    iteration: 1
    severity: P2
    title: Smoke test lists causes instead of classifying them
    status: applied
    location: U3 approach + test scenarios (stub-driven stderr classification)
  - finding_id: EN10-PR-003
    iteration: 1
    severity: P2
    title: D44 depends on PR 36 landing, not modeled
    status: applied
    location: U4 resolves the next-free D-ID at build time + prerequisite
depth: standard
data_scale: small
---

# EN10 - fix Codex `--max-turns` flag drift in the cross-agent peer contract

## Context

The current Codex CLI (`codex-cli 0.144.0`) **removed `--max-turns`**. Ensemble's cross-agent peer contract still appends a hardcoded `--max-turns 1` to the shared peer invocation (`$PEER_CMD $PEER_FORMAT --max-turns 1`), which works for `claude -p` but **fails on Codex**:

```
$ codex exec --json --max-turns 1
error: unexpected argument '--max-turns' found
```

`codex exec` has no turn/iteration flag at all - it is inherently single-shot (runs the agent to completion and exits), so `codex exec --json <prompt>` alone is the correct invocation (used successfully throughout this session's cross-agent reviews). `claude -p --output-format json --max-turns 1` still succeeds. So the flag must be **kept for Claude and dropped for Codex**, not removed globally.

Field-observed on a fresh-machine `./setup`: the CLI smoke test warned `Codex CLI: ⚠ flag mismatch` (real, reproducible on any current-Codex machine) and `Claude CLI: ⚠ flag mismatch` (that one was just an un-authenticated CLI - a different cause the smoke test conflated). Beyond the smoke test, the drift breaks actual cross-agent peer review whenever the peer is Codex.

## Decisions, assumptions & risks

- **Decision - the turn cap is host-resolved, not hardcoded.** `bin/ensemble-detect-host` already emits `PEER_CMD` / `PEER_FORMAT` per agent; it gains a `PEER_TURNS` variable = `--max-turns 1` when the peer is `claude -p`, **empty** when the peer is `codex exec`. Every call site changes `$PEER_CMD $PEER_FORMAT --max-turns 1` -> `$PEER_CMD $PEER_FORMAT $PEER_TURNS` (empty collapses to nothing for Codex). Same host-neutral parameterization pattern as `PEER_FORMAT` and EN05's `$QUESTION_TOOL`. The count `1` is baked into `PEER_TURNS` because peer review is always a single response - there is no per-call variation on the peer path.
- **Decision - the fix must be in the SCRIPT, not only the markdown.** `bin/ensemble-detect-host` is what actually emits the variables consumers `eval`; `references/host-detect.md` documents it. Both change, and `PEER_TURNS` is shell-escaped and emitted in the same heredoc as the other vars.
- **Decision - the Codex worker cap is dropped, not parameterized.** `references/build-orchestration.md` tells Codex workers to "pass `--max-turns` aggressively (e.g. 30)". Codex `exec` has no such flag and runs to completion, so the guidance is simply removed (no worker-turns variable needed; the worker is Codex-specific in that flavor).
- **Decision - the smoke test uses correct flags AND separates auth from flag failure.** The Codex probe drops `--max-turns`; on failure the message distinguishes "CLI not authenticated (run `codex login` / `claude` login)" from genuine flag drift, so a fresh un-authed machine stops reporting a false "flag mismatch".
- **Assumption - `claude -p` keeps `--max-turns`.** Verified on this machine (exit 0). If a future Claude CLI drops it, the same `PEER_TURNS` mechanism localizes the fix to one place.
- **Note - D-ID.** This branch is off `origin/main` (which predates the in-flight guardrail work), whose foundation ends at D42. The in-flight guardrail PR (#36) claims **D43**; to avoid a collision this plan uses **D44** and assumes that PR merges first (a D43 gap on this branch fills when #36 lands).
- **Risk - a call site is missed and still hardcodes `--max-turns`.** *Mitigation:* the U4 drift test greps every peer-contract reference and `setup` for a hardcoded `codex exec ... --max-turns`, failing if any remain.

## Implementation units

### U1. Emit `PEER_TURNS` from host detection

- **Goal:** `bin/ensemble-detect-host` resolves and emits `PEER_TURNS` (`--max-turns 1` for a `claude -p` peer, empty for `codex exec`); `references/host-detect.md` documents it.
- **Requirements covered:** none (bug fix).
- **Dependencies:** none.
- **Files:** `bin/ensemble-detect-host`, `references/host-detect.md`, `tests/lint/en-codex-flag-drift.test.sh` (new).
- **Approach:** After the peer-mode resolution block (where `PEER_CMD` is set), derive `PEER_TURNS`: if `PEER_CMD` begins with `claude` then `--max-turns 1`, else empty (covers `codex exec` and any non-Claude peer). Add `PEER_TURNS=$(shellesc "$PEER_TURNS")` to the `EMITTED` heredoc. In `host-detect.md`, add `PEER_TURNS` to the emitted-variables table with the rationale (Codex `exec` is single-shot; Claude `-p` caps turns). Preserve bash 3.2 compatibility and the shell-escaping round-trip.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - Happy path (Claude peer): with a Claude host + Codex present (cross-agent), the peer is Codex -> `PEER_TURNS` empty; force `ENSEMBLE_HOST=codex` so the peer is Claude -> `PEER_TURNS` = `--max-turns 1`. (test evals the emitted output under both host env settings)
  - Edge (single-agent fallback): when the peer is the host's own CLI, `PEER_TURNS` matches that CLI (`--max-turns 1` for claude, empty for codex). (test asserts)
  - Integration: the emitted `PEER_TURNS` line is shell-escaped and round-trips through `eval` without error. (test evals the block)
- **Verification:** `bash tests/lint/en-codex-flag-drift.test.sh` passes (ends with `report`); `bash tests/run.sh` green; `eval "$(bin/ensemble-detect-host)"; echo "$PEER_TURNS"` shows the right value per host.

### U2. Parameterize the peer call sites

- **Goal:** Every cross-agent peer invocation uses `$PEER_TURNS` instead of a hardcoded `--max-turns 1`; `cli-wrappers.md` documents the Claude/Codex divergence.
- **Requirements covered:** none.
- **Dependencies:** U1.
- **Files:** `references/outside-voice.md`, `references/cli-wrappers.md`, `references/build-handoff.md`.
- **Approach:** In `outside-voice.md`, change the peer invocation(s) `$PEER_CMD $PEER_FORMAT --max-turns 1 "$prompt"` -> `$PEER_CMD $PEER_FORMAT $PEER_TURNS "$prompt"`, and update the prose that explains the single-turn cap to note it applies to Claude (`--max-turns 1`) and that Codex `exec` is single-shot (no flag). In `cli-wrappers.md`, correct the Codex section (remove `--max-turns` from the Codex examples and the shared `PEER_TURNS` note), keep it for Claude, and document that `PEER_TURNS` is host-resolved. In `build-handoff.md`, the peer is always Claude (Codex host -> Claude peer), so `--max-turns 1` is correct there; parameterize to `$PEER_TURNS` for uniformity (still resolves to `--max-turns 1`).
- **Risk:** low
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - **Test expectation:** covered by U4's drift test (asserts no reference hardcodes `codex exec ... --max-turns` and that the peer sites reference `PEER_TURNS`) - these are documentation/contract files exercised by the drift guard, not runtime code.
- **Verification:** U4 drift test passes; `bin/ensemble-lint --scope docs/` exit 0; manual grep shows no `$PEER_CMD $PEER_FORMAT --max-turns` literals remain.

### U3. Fix the Codex worker cap + the setup smoke test

- **Goal:** Remove the invalid Codex worker `--max-turns 30` guidance; make `setup`'s Codex smoke probe use valid flags and distinguish an auth failure from a flag mismatch.
- **Requirements covered:** none.
- **Dependencies:** none.
- **Files:** `references/build-orchestration.md`, `setup`.
- **Approach:** In `build-orchestration.md`, replace the "pass `--max-turns` aggressively (e.g. 30)" worker guidance with a note that `codex exec` is single-shot and needs no turn cap (it runs the unit to completion). In `setup`, change the Codex probe to `codex exec --json <<<"ping"` (no `--max-turns`) and **actually classify the failure (EN10-PR-002), not just list causes:** capture stderr, and branch on it - if stderr matches an argument/option-parse failure (e.g. `unexpected argument`, `error: unrecognized`, `USAGE`), report **flag drift** ("check references/cli-wrappers.md"); if it matches a recognized auth failure (e.g. `not logged in`, `unauthorized`, `login`, `authentication`), report **auth guidance** ("run `codex login` / sign in to `claude`"); otherwise emit a **neutral probe-failed** message with the captured diagnostic snippet. Keep the Claude probe's `--max-turns 1` (still valid) with the same classification.
- **Test note:** the classification branches are exercised with small CLI **stubs** (a fake `codex`/`claude` on PATH that emits a chosen stderr + exit code) so each of flag-drift / auth / unknown is asserted deterministically without a real CLI.
- **Risk:** low
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - Happy path: `setup`'s Codex probe line no longer contains `--max-turns`. (drift guard asserts)
  - Error path - classification (EN10-PR-002): with a stub `codex` emitting `unexpected argument` -> "flag drift"; a stub emitting `not logged in` -> auth guidance; a stub emitting an unrecognized error -> neutral probe-failed message. (stub-driven test asserts each branch)
  - Integration: `build-orchestration.md` no longer tells Codex workers to pass `--max-turns`. (drift guard asserts absence)
- **Verification:** U4 drift test passes; `bash -n setup` clean; `bash tests/run.sh` green.

### U4. Foundation D44 + drift test

- **Goal:** Record decision D44 and add a drift test that fails if any peer-contract reference or `setup` re-introduces a hardcoded Codex `--max-turns`.
- **Requirements covered:** none (decision record + guard).
- **Dependencies:** U1, U2, U3.
- **Files:** `docs/foundation.md`, `tests/lint/en-codex-flag-drift.test.sh` (extend).
- **Approach:** **Resolve the actual next-free D-ID at build time (EN10-PR-003):** re-scan `docs/foundation.md` for the highest `D<N>`, reserve D43 for the in-flight guardrail PR (#36), and allocate the next free ID (D44 if D43 is reserved/present, else the next contiguous). Use that resolved ID consistently in the decision record AND the drift assertion - do not hardcode D44 if the branch state differs after syncing with main. Add the decision after the last on this branch: the Codex `--max-turns` removal, the host-resolved `PEER_TURNS` fix (Claude keeps the cap, Codex `exec` is single-shot), the worker-cap removal, and the smoke-test auth-vs-flag classification. **Strengthen the drift test (EN10-PR-001)** to scan the **complete peer-contract scope** (`references/outside-voice.md`, `references/cli-wrappers.md`, `references/build-handoff.md`, and any file matching the peer-invocation pattern) for ANY hardcoded `$PEER_CMD`-invocation containing `--max-turns` (fail if found), positively assert `$PEER_TURNS` appears at every enumerated executable peer call site (outside-voice.md AND build-handoff.md), keep the separate prohibition on a `codex exec ... --max-turns` literal in any reference or `setup`, assert `bin/ensemble-detect-host` emits `PEER_TURNS`, and assert foundation shows the resolved D-ID.
- **Prerequisite (EN10-PR-003):** before editing `foundation.md`, refresh the D-ID allocation against the current branch/main state so the number doesn't collide with or gap the in-flight D43.
- **Risk:** low
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - Happy path: foundation's new decision (resolved ID) names the Codex flag drift + the `PEER_TURNS` fix. (drift guard asserts on the resolved D-ID)
  - Error path (the guard's whole point, EN10-PR-001): a hardcoded `$PEER_CMD ... --max-turns` invocation OR a `codex exec ... --max-turns` literal anywhere in the peer-contract references (`outside-voice.md`, `cli-wrappers.md`, `build-handoff.md`) or `setup` fails the test. (drift guard greps the full scope and asserts absence)
  - Integration: `$PEER_TURNS` is referenced at every executable peer call site (outside-voice.md AND build-handoff.md), and `bin/ensemble-detect-host` emits `PEER_TURNS`. (drift guard asserts presence)
  - **Test expectation:** covered by the drift guards above.
- **Verification:** `tests/lint/en-codex-flag-drift.test.sh` passes; `bin/ensemble-lint --scope docs/` exit 0; foundation shows D44.

## Verification (whole plan)

- `eval "$(ENSEMBLE_HOST=codex bin/ensemble-detect-host)"; echo "$PEER_TURNS"` -> `--max-turns 1` (Claude peer); the Claude-host cross-agent case -> empty (Codex peer).
- `bash tests/run.sh` - full suite green (new: `tests/lint/en-codex-flag-drift.test.sh`).
- `bin/ensemble-lint --scope docs/` - exit 0.
- Manual: no `$PEER_CMD $PEER_FORMAT --max-turns` or `codex exec ... --max-turns` literals remain; `setup`'s Codex probe runs without the flag error.
- Branch-level cross-agent review at build completion (D35/D41) - which itself now exercises the fixed Codex peer invocation.
