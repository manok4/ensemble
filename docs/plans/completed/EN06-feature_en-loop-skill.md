---
type: plan
plan_type: feature
plan_id: EN06
title: en-loop — bounded autonomous-loop orchestrator wrapping gnhf
status: completed
location: active
created: 2026-07-05
shipped: 2026-07-05
deepened:
covers_requirements: []
requirements_pending: false
related_design:
peer_review_verdict: approve
peer_review_iterations: 1
peer_review_last_run: 2026-07-05
peer_review_plan_hash: a9dac7edad6b224a2219ffd748c7eeebe70ba61c0c674708ff7e648aaf39f159
peer_review_resolutions: []
depth: standard
data_scale: small
---

# EN06 - en-loop: bounded autonomous-loop orchestrator wrapping gnhf

## Context

`/en-loop` is a new Ensemble skill for **bounded, objective-driven autonomous loops** — the ralph / autoresearch pattern: keep an agent running (overnight) where each iteration makes one small, committed, test-gated change toward an objective, until an evidence-based stop condition. It fills a gap the suite doesn't cover today.

It is built on **gnhf** (`npm gnhf`, "good night, have fun") — a mature, agent-agnostic loop engine (interrupt handling, commit-on-success / rollback-on-failure, exponential-backoff retries, worktrees, process supervision, live terminal title, permanent exit summary). en-loop **wraps** that engine rather than reimplementing it — the EN04 lesson (don't rebuild robust infra; wrap the existing engine and add your value on top). Ensemble's value-add is entirely the **worker prompt** (Ensemble's per-iteration test-gate contract) and the **review layer** (branch-level cross-agent review at checkpoints), not the loop plumbing.

**Two architecture decisions (confirmed with the user before planning):**
1. **Engine: wrap the gnhf CLI** (not native, not hybrid).
2. **Review cadence: test-gate per iteration + branch-level review at checkpoints** — each iteration implements one slice, runs test+lint, and commits only on green; a full `/en-review --peer-only --mode headless` runs every `--review-every N` iterations and at loop end (branch-level model, D35), and its findings become the next iterations' acceptance criteria.

Priority principle (D39) applies: **performance > speed ≥ cost** — the checkpoint-review cadence is chosen precisely to keep overnight throughput high while still producing a peer-reviewed, evidenced branch.

## Positioning (distinct from existing skills)

- **vs `/en-flow`** — en-flow is a *fixed one-shot pipeline* (plan → build → learn → ship) for a **defined plan**. en-loop is *open-ended*: an objective whose scope isn't fully enumerated, chipped at one committed slice per iteration until a natural-language stop condition ("keep reducing complexity until the suite is green and lint is 0").
- **vs the built-in `/loop`** — `/loop` re-invokes a prompt on a fixed interval in-session; en-loop is objective-driven with commit/rollback/retry and a real supervised (gnhf) process.
- **vs `/en-build`** — en-build executes *known plan units*; en-loop discovers its slices in the loop but borrows en-build's per-slice test-gate + the branch-level review (D35).

The skill documents this "when to use which" up front.

## Out of scope (deliberately)

- **Reimplementing the loop natively** — rejected; wrap gnhf.
- **A hybrid native+gnhf engine** — rejected; single engine keeps the surface small.
- **Upstream changes to gnhf** — en-loop consumes gnhf as-is; no fork/PR to gnhf.
- **Auto-merge / auto-ship from the loop** — the loop produces a reviewed branch + exit summary; shipping stays an explicit `/en-ship`.
- **Fixing the pre-existing stale skill count** in foundation D22 / the ASCII tree ("eleven skills") — that drift predates EN06; note it as tech-debt, don't fold a suite-wide rename into this plan.

## Decisions, assumptions & risks

- **Decision — wrap gnhf, not native (EN04 lesson).** A robust unattended-loop engine (interrupt/rollback/retry/worktrees/process-supervision/exit-summary) is hard and gnhf already is it, agent-agnostic across Claude + Codex (matching Ensemble's host contract). Reimplementing as a markdown loop would be fragile for true overnight runs. *Cost:* an external `npm i -g gnhf` dependency, surfaced by en-setup like the existing gh/codex deps.
- **Decision — test-gate per iteration + checkpoint review, not per-iteration peer review.** A full Outside Voice pass every iteration is too slow/expensive for a long overnight loop. Per-iteration = implement → test+lint → commit-on-green (fast, still gated); full `/en-review --peer-only` every `--review-every N` and at loop end (branch-level, D35). Balances performance and evidence per D39.
- **Decision — evidence-based stop conditions required.** en-loop refuses vague `--stop-when` ("looks good") and requires an Ensemble-observable condition ("suite green AND `/en-review` clean AND lint 0"). A loop with a fuzzy stop condition runs forever or stops wrong.
- **Decision — host orchestrates, gnhf executes; completion ≠ acceptance.** Adopted from gnhf's core rule: a gnhf "stop condition met" only means the worker stopped; en-loop's Morning Review independently verifies before calling anything mergeable.
- **Assumption — gnhf's flag surface is stable-ish but must be checked at runtime.** The skill instructs `gnhf --help` before relying on flags and never inventing unsupported flags (gnhf may lack `--model`; put model needs in the worker prompt).
- **Risk — the external gnhf dependency isn't installed.** *Mitigation:* en-setup offers the install; en-loop preflight detects absence and prints a clear `npm i -g gnhf` message — it does **not** silently fall back to a fragile native loop.
- **Risk — an unattended loop does damage while the user sleeps.** *Mitigation:* preserve user changes, no destructive git, `en-guardrail` still intercepts destructive bash inside the worker, per-iteration test-gate, bounded caps, and never auto-merge — the loop's output is a reviewed branch + exit summary.

## Technical design

### Control flow of an en-loop run (Hands-Off)

```
/en-loop --objective "<X>" --stop-when "<evidence-based condition>" [caps] [--review-every N]
  preflight: gnhf installed? (else print install cmd, stop) · host-detect agent · clean git · resolve test/lint cmds
  → compose the Ensemble worker prompt (per-iteration test-gate contract, below)
  → launch gnhf (feature branch or --worktree) with the prompt + caps + --stop-when
  → gnhf loops: [implement one slice → test+lint → commit on green w/ trailer | rollback | leave note if blocked]
       every N iterations (and at loop end): /en-review --peer-only --mode headless over the branch diff
         → record review-verdict: trailer; findings become the next iterations' acceptance criteria
  → gnhf exits (stop-when self-reported | cap | Ctrl-C) → exit summary
  → /en-learn capture on the branch → hand off to /en-review → /en-qa → /en-ship  (never auto-merge)
```

### Per-iteration worker-prompt contract (fed to gnhf)

```
Iteration: one small slice toward <objective>. Inspect repo/docs/recent commits first.
Preserve user changes; no unrelated refactors. Implement the slice → run <test> + <lint>.
Commit ONLY on green, with a phase:/evidence trailer. If blocked: NO fake success —
leave a note with the blocker + evidence and stop. Stop only when: <evidence-based condition>.
```

### Modes

- **Hands-Off** — bounded objective, walk away; intervene only on hard failure / runaway / destructive.
- **Companion** — host steers between iterations via `/en-review`; tightens the next bounded prompt; findings → next acceptance criteria; prefer a new bounded prompt over manual takeover.
- **Morning Review** — reconstruct state from git/logs/processes (never memory) → independent `/en-review` + `/en-qa` → Mergeable / Needs-follow-up / Do-not-merge → optional `/en-ship`.

## Implementation units

### U1. The `/en-loop` skill

- **Goal:** Author `skills/en-loop/SKILL.md` — the wrap-gnhf loop skill with two modes, the per-iteration test-gate worker contract, checkpoint-review integration, evidence-based stop-condition discipline, the launch contract, flags, lifecycle hand-offs, and safety.
- **Requirements covered:** none (no foundation R-IDs; new skill).
- **Dependencies:** none.
- **Files:** `skills/en-loop/SKILL.md` (new), `tests/lint/en-loop-skill.test.sh` (new).
- **Approach:** Write the SKILL.md with frontmatter (name `en-loop`; description + trigger phrases like "loop on this", "keep working overnight", "run until", "autonomous loop", "good night have fun", "gnhf"). Sections: **Positioning / when-to-use** (vs en-flow, /loop, en-build); **Preflight** (host-detect for `$AGENT` selection — claude on Claude host, codex on Codex host; verify `gnhf` on PATH else print `npm i -g gnhf` and stop, never native-fallback; clean git; resolve project test/lint commands); **Modes** — Hands-Off and Companion (mirroring gnhf, Ensemble-flavored); **Worker-prompt contract** (the per-iteration test-gate block); **Checkpoint review** (every `--review-every N` + at loop end → `/en-review --peer-only --mode headless` over the branch diff → `review-verdict:` trailer → findings feed next iterations); **Stop-condition discipline** (require Ensemble-observable conditions; reject "looks good"); **Launch contract** (`gnhf --help` before relying on flags; never invent flags; model needs go in the worker prompt if gnhf lacks `--model`); **Flags** (`--objective`, `--stop-when`, `--max-iterations`, `--max-tokens`, `--max-runtime`, `--worktree`, `--push`, `--agent`, `--review-every N`, `--mode hands-off|companion`); **Lifecycle** (objective from a plan / `docs/plans/tech-debt-tracker.md` / free objective; loop-end `/en-learn capture` → `/en-review → /en-qa → /en-ship`, never auto-merge); **Safety** (preserve user changes; no destructive git; en-guardrail intercepts inside the worker; reviewed branch + exit summary, never auto-merge); **core rule** "host orchestrates, gnhf executes; completion ≠ acceptance."
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - Happy path: SKILL.md documents both modes (Hands-Off, Companion) + Morning Review, and the wrap-gnhf launch. (drift guard asserts the mode headings + a `gnhf` launch invocation)
  - Edge — gnhf absent: preflight prints `npm i -g gnhf` and stops; does NOT native-fallback. (drift guard asserts the install message + a "do not reimplement / no native fallback" clause)
  - Edge — checkpoint cadence: per-iteration test-gate + `/en-review --peer-only` every `--review-every N` and at loop end. (drift guard asserts the test-gate contract + the checkpoint review invocation + `--review-every`)
  - Error path — stop-condition discipline: an evidence-based `--stop-when` is required; "looks good" is rejected. (drift guard asserts the evidence-based requirement)
  - Integration — safety: preserve user changes, no destructive git, never auto-merge, host-neutral agent selection. (drift guard asserts the safety list + host-detect agent selection)
- **Verification:** `tests/lint/en-loop-skill.test.sh` passes (ends with `report`); `bash tests/run.sh` green; `bin/ensemble-lint --scope docs/` exit 0.

### U2. en-setup installs / surfaces the gnhf dependency

- **Goal:** Teach `/en-setup` to offer the `gnhf` install (optional, State 2) and report its status (State 3), mirroring the existing Claude-Code-Review-action optional-install pattern.
- **Requirements covered:** none.
- **Dependencies:** U1 (the skill that consumes the dependency must exist).
- **Files:** `skills/en-setup/SKILL.md`, `tests/lint/en-loop-setup-install.test.sh` (new).
- **Approach:** In State 2, add an optional-install offer for `gnhf` (a `y`/`n` prompt like the Claude-Code-Review-action check at step 13): *"`/en-loop` uses the `gnhf` CLI for autonomous loops. Install now? (`npm i -g gnhf`) (y/n)"* — optional, never blocking. In State 3, add a status line (🟢 if `gnhf` on PATH; 🟡 if absent, with the install hint). Note that `gnhf` is agent-agnostic and only needed for `/en-loop`. Add a preflight/verification entry to the final-verification list (advisory, not a hard failure — gnhf is optional).
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - Happy path: en-setup State 2 offers the `gnhf` install (`npm i -g gnhf`, optional y/n). (drift guard asserts the offer)
  - Edge — State 3 status: en-setup reports gnhf presence/absence with the install hint. (drift guard asserts the status line)
  - Edge — optional, non-blocking: the install is documented as optional (only needed for `/en-loop`), never a hard gate. (drift guard asserts the "optional" framing)
  - Test expectation: covered by the drift guard above — this is a skill-doc unit.
- **Verification:** `tests/lint/en-loop-setup-install.test.sh` passes (ends with `report`); `bash tests/run.sh` green; `bin/ensemble-lint --scope docs/` exit 0.

### U3. Foundation D40 + skill catalog entry

- **Goal:** Record decision D40 for en-loop and add en-loop to the skill catalog (§5.1 table + a §5.2.x details subsection).
- **Requirements covered:** none.
- **Dependencies:** U1.
- **Files:** `docs/foundation.md`, `tests/lint/en-loop-foundation.test.sh` (new).
- **Approach:** Add **D40** in the §4.1 decision block (after D39): the en-loop skill — wrap-gnhf engine choice + rationale (EN04 lesson), the test-gate-per-iteration + checkpoint-review cadence, the two modes, evidence-based stop conditions, and the "host orchestrates, gnhf executes; completion ≠ acceptance" rule; note the external gnhf dependency surfaced by en-setup. Add an **en-loop row to the §5.1 skill-summary table** (purpose / input / output / gating / tests columns) and a **§5.2.x `en-loop` details subsection** (purpose, high-level process, modes, dependency, safety), marking `skills/en-loop/SKILL.md` as canonical. Do NOT attempt to reconcile the pre-existing stale "eleven skills" count in D22 / the ASCII tree — note it as tech-debt in the plan's out-of-scope, leave it for a dedicated cleanup.
- **Risk:** low
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - Happy path: foundation has D40 naming en-loop + the wrap-gnhf + cadence + modes facets. (drift guard asserts D40 exists and names the key facets)
  - Edge — catalog: §5.1 table has an en-loop row and a §5.2.x details subsection. (drift guard asserts both)
  - Integration — the "completion ≠ acceptance" + evidence-based-stop rules appear in D40. (drift guard asserts the rule language)
  - Test expectation: covered by the drift guard above — this is a doc unit.
- **Verification:** `tests/lint/en-loop-foundation.test.sh` passes (ends with `report`); `bash tests/run.sh` green; `bin/ensemble-lint --scope docs/` exit 0; foundation shows D40.

## Verification (whole plan)

- `bash tests/run.sh` — full suite green (new: 3 drift-test files).
- `bin/ensemble-lint --scope docs/` — exit 0.
- Manual spot-check: `skills/en-loop/SKILL.md` exists with both modes + the test-gate-per-iteration worker contract + checkpoint review + evidence-based stop discipline + the wrap-gnhf (never native) stance; en-setup offers the gnhf install (optional) + State-3 status; foundation shows D40 + an en-loop catalog entry; nothing auto-merges from the loop.
- Branch-level cross-agent review at build completion (D35), verdict recorded via the `review-verdict:` trailer.
