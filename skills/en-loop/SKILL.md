---
name: en-loop
description: "Run a bounded autonomous loop until an evidence-based stop condition: one committed, test-gated slice per iteration, cross-agent review at checkpoints. Wraps the gnhf CLI. Trigger phrases: 'loop on this', 'keep working overnight', 'run until', 'autonomous loop', 'good night have fun', 'gnhf'."
disable-model-invocation: true
---


# `/en-loop`

> **Running a bundled script.** Anchor every call to this skill's own directory:
> `SKILL_DIR="<absolute path of the directory containing this SKILL.md>"; bash "$SKILL_DIR/scripts/<name>"`.
> The trailing `;` is load-bearing. en-loop carries one script, `scripts/ensemble-detect-host`.

Run a **bounded, objective-driven autonomous loop**: keep an agent working, one small committed test-gated slice per iteration, toward an objective, until an evidence-based stop condition is met. This is the ralph / autoresearch / "good night, have fun" pattern for overnight, walk-away work.

> **Manual-invoke only.** `disable-model-invocation: true` — en-loop launches a long-running unattended process, so the user always starts it explicitly. It is never auto-triggered.

> **Core rule: the host orchestrates; gnhf executes. Completion is not acceptance.** A gnhf "stop condition met" only means the worker stopped; en-loop independently verifies (Morning Review) before calling anything mergeable. Do not manually implement inside the loop's scope while a gnhf worker owns it, unless the user explicitly changes the delegation.

## What this is (and the engine it wraps)

en-loop is a thin Ensemble layer over **gnhf** (`npm i -g gnhf`), a mature, agent-agnostic loop engine: interrupt handling, commit-on-success / rollback-on-failure, exponential-backoff retries, worktrees, process supervision, a live terminal title, and a permanent exit summary. **en-loop wraps that engine rather than reimplementing it** (the EN04 lesson: do not rebuild robust unattended-loop infra; wrap the existing engine and add value on top).

Ensemble's value-add is exactly two things, not the loop plumbing:

1. **The worker prompt** — Ensemble's per-iteration test-gate contract (implement one slice, run test + lint, commit only on green, no fake success).
2. **The review layer** — a branch-level cross-agent `/en-review --peer` at checkpoints (every `--review-every N` iterations and at loop end), whose findings become the next iterations' acceptance criteria.

## When to use which (positioning)

- **vs `/en-flow`** — en-flow is a *fixed one-shot pipeline* (plan → build → learn → ship) for a **defined plan**. en-loop is *open-ended*: an objective whose scope is not fully enumerated, chipped at one committed slice per iteration until a natural-language stop condition ("keep reducing complexity until the suite is green and lint is 0").
- **vs the built-in `/loop`** — `/loop` re-invokes a prompt on a fixed interval in-session. en-loop is objective-driven with commit / rollback / retry and a real supervised (gnhf) process that survives the session.
- **vs `/en-build`** — en-build executes *known plan units* with per-unit and branch-level review. en-loop discovers its slices in the loop, but borrows en-build's per-slice test-gate and the branch-level review model (D52). If the work is already a peer-reviewed plan, use `/en-build`, not en-loop.

## Preflight (before launching a loop)

1. **Detect host.** Run `eval "$(bash "$SKILL_DIR/scripts/ensemble-detect-host")"` and read `HOST` (the peer variables it also emits are not used here). Resolve the worker agent host-neutrally: `claude` on a Claude Code host, `codex` on a Codex host (unless the user overrides with `--agent`). Never hardcode a single agent. **Note guardrail applicability in the launch report:** `en-guardrail` (a Claude Code `PreToolUse` hook) covers the worker only when the worker runtime honors that hook — that is a `claude` worker. A `codex` (or other) worker is **not** covered by the Claude hook; for those runs the safety floor is the worker-prompt rules + gnhf rollback + `--worktree` (see Safety).
1a. **No recursion-guard step, deliberately.** en-loop cannot be reached from inside a peer subprocess: `disable-model-invocation: true` means only a human starts it. The detection script reads `ENSEMBLE_PEER_REVIEW` itself, and the checkpoint `/en-review --peer` sets that variable for the peer it dispatches; this skill neither sets nor branches on it.
2. **Verify gnhf is installed.** Run `gnhf --help`. If gnhf is not on PATH, **print the install command and stop**:
   > `/en-loop` needs the gnhf CLI. Install it with `npm i -g gnhf`, then re-run. (`/en-setup` also offers this install.)

   **Do NOT reimplement the loop natively and do NOT fall back to a fragile in-session markdown loop.** The whole point of en-loop is the supervised gnhf engine; a hand-rolled fallback would lack the interrupt / rollback / retry guarantees. Absent gnhf, en-loop stops with the install hint, nothing else.
3. **Clean git.** Check `git status --short` and `git branch --show-current`. Preserve any user changes; if the tree is dirty, ask the user to commit / stash / proceed before launching (an overnight loop must not bury uncommitted work).
4. **Resolve the project test and lint commands** (from `AGENTS.md` / `CLAUDE.md` / project config) so the worker prompt carries the exact `<test>` and `<lint>` invocations.
5. **Resolve the objective and the stop condition** (see Stop-condition discipline). Refuse to launch without an evidence-based `--stop-when`.

## Modes

Choose exactly one mode for the run.

### Hands-Off

Use when the objective is bounded, verification is clear, and the user wants one configured run to proceed without steering (the walk-away / overnight case).

- Compose a precise worker prompt (the per-iteration test-gate contract below) with constraints, non-goals, verification commands, and the stop condition.
- Launch gnhf in **bounded chunks** of `--review-every N` iterations (see Checkpoint review); between chunks, run the checkpoint review and relaunch on the same branch until `--stop-when` holds or an overall cap is hit.
- Intervene early only for hard failure, runaway scope, destructive behavior, or an impossible prerequisite.
- On final exit, run Morning Review before reporting anything as done.

### Companion

Use when the objective is uncertain, exploratory, design-heavy, or likely to need course correction.

- Keep a note of the original intent, branch, session id, and last known result.
- Between iterations, steer with `/en-review`: read the diff, and if the worker starts optimizing the wrong thing or drifts scope, tighten the **next** bounded prompt rather than taking over implementation by hand.
- Treat review findings as the next acceptance criteria.
- Prefer relaunching gnhf with a new bounded prompt over manual takeover.

### Morning Review (on return / after a Hands-Off run)

Reconstruct state from git / logs / running processes, **never from memory**:

```bash
git status --short
git branch --show-current
git log --oneline --decorate --max-count=20
pgrep -fl 'gnhf|claude|codex' || true
```

Then invoke `/en-review` over the branch diff and invoke `/en-qa`, as **independent** verification, comparing the result to the stop condition and the user's latest feedback. Decide: **Mergeable**, **Needs follow-up loop**, or **Do not merge**. If it needs follow-up, continue in Companion mode instead of presenting the run as complete. Hand off to `/en-ship` only when Mergeable and only with explicit authorization. Never auto-merge.

## Per-iteration worker-prompt contract (fed to gnhf)

This is Ensemble's core value-add over a bare gnhf run. Every iteration follows a **test-gate**: implement one slice, run test + lint, commit only on green. Compose the prompt from this block, substituting `<objective>`, `<test>`, `<lint>`, and `<evidence-based condition>`:

```text
You are operating autonomously. Nobody is watching this iteration and nobody can
answer a question, so do not end it on a plan, a question, or a promise; do the
work, or leave the blocker note below. Before ending, check your last paragraph:
if it describes work not yet done, do that work now.

Iteration: implement one small slice toward <objective>. Before coding, inspect the
repo, relevant docs, and recent commits. Preserve user changes; make no unrelated
refactors. A pre-existing bug or behaviour the objective does not mention is a note
in the commit body, not a fix in this slice, unless the slice cannot work without it.

Implement the slice, then run <test> and <lint>. Commit ONLY on green, with a
conventional message and a `phase:` / evidence trailer describing what was verified.

If blocked: NO fake success. Leave a note with the blocker and the evidence, and stop.

Stop only when: <evidence-based condition>.
```

## Checkpoint review (the branch-level review layer)

Ordinary iterations are test-gated but not peer-reviewed (a full Outside Voice pass every iteration is too slow and expensive for a long overnight loop — the D39 `performance > speed ≥ cost` trade-off: keep overnight throughput high while still producing a peer-reviewed, evidenced branch).

**How the cadence is driven (this is en-loop's mechanic, not a gnhf feature).** gnhf runs to its own stop condition and has **no mid-run callback** to invoke a reviewer, so en-loop drives the checkpoint cadence itself by running gnhf in **bounded chunks**. Do NOT assume gnhf calls `/en-review` mid-run — it does not. Each chunk:

1. **Launch gnhf capped at `--review-every N` iterations** (via gnhf's own `--max-iterations`, so the process stops at the chunk boundary), with the worker prompt and `--stop-when`.
2. When the chunk stops (cap reached or `--stop-when` self-reported), **run `/en-review --peer --mode headless`** over the branch diff (`git diff <merge-base>..HEAD`). This dispatches the cross-agent Outside Voice peer as the sole reviewer (Claude host → Codex reviews; Codex host → Claude reviews).
3. **Record the outcome as a `review-verdict:` trailer** on a checkpoint commit.
4. If the real `--stop-when` condition is not yet met, **relaunch gnhf on the same branch** for the next chunk with the review findings folded into the worker prompt as the bounded corrections to make (the gnhf Companion-review / relaunch pattern). **Findings become the next chunk's acceptance criteria.**

Repeat until `--stop-when` holds or an overall cap (total `--max-iterations`, `--max-tokens`, `--max-runtime`) is hit. A review always runs at the final loop end regardless of where the last chunk boundary fell. Default `--review-every` is 5 iterations.

## Stop-condition discipline

en-loop **requires an evidence-based `--stop-when`** and refuses vague ones. A loop with a fuzzy stop condition either runs forever or stops on the wrong signal.

- **Rejected:** "looks good", "done", "when it's ready" — not Ensemble-observable, so en-loop will not launch with them.
- **Required:** a condition Ensemble can observe, for example: "the full test suite passes AND `/en-review` reports no unresolved P0/P1 findings AND lint is 0 AND no unrelated files changed."

If the user gives a vague stop condition, ask for an observable one before launching.

## Launch contract

Check the installed CLI before relying on flags — do not invent unsupported ones:

```bash
gnhf --help
```

Known shape (verify against `--help`; flag names may differ by gnhf version):

```bash
gnhf \
  --agent <claude|codex> \
  --max-iterations <n> \
  --stop-when "<evidence-based condition>" \
  "<the Ensemble worker prompt>"
```

Forward only the caps `gnhf --help` advertises; if gnhf has no `--model` flag, put model requirements in the worker prompt or the backend config, and do not invent a `--model` flag. Enforce `--max-runtime` yourself by wrapping the gnhf process in `timeout` / `gtimeout` when gnhf has no native runtime cap. If `--worktree` is requested, launch gnhf in an isolated worktree so the loop does not disturb the primary checkout.

## Flags

| Flag | Effect |
|---|---|
| `--objective "<X>"` | **en-loop-owned.** The one concrete outcome the loop drives toward. Required. |
| `--stop-when "<cond>"` | **en-loop-owned.** Evidence-based, Ensemble-observable stop condition. Required; vague conditions are rejected. |
| `--max-iterations <n>` | **en-loop-owned.** Overall cap across every chunk; never forwarded. gnhf's own `--max-iterations` carries the per-chunk cap instead, which is `--review-every`. |
| `--max-tokens <n>` | **gnhf pass-through.** Token budget cap for the run, forwarded only if gnhf advertises it. |
| `--max-runtime <dur>` | **en-loop-owned.** Wall-clock cap (e.g. `8h`), enforced by wrapping the gnhf process in `timeout` / `gtimeout` when gnhf has no native runtime cap. |
| `--worktree` | **gnhf pass-through.** Run the loop in an isolated git worktree. |
| `--push` | **gnhf pass-through.** Allow the loop to push the feature branch (still never auto-merges). |
| `--agent <claude\|codex>` | **gnhf pass-through.** Override the host-detected worker agent. |
| `--review-every <N>` | **en-loop-owned.** Run the checkpoint `/en-review --peer` every N iterations (default 5; a review always runs at loop end). Drives the per-chunk `--max-iterations` cap passed to gnhf. |
| `--mode <hands-off\|companion>` | **en-loop-owned.** Select the run mode (default `hands-off`). |

**Flag ownership.** `--objective`, `--stop-when`, `--review-every`, `--mode`, `--max-iterations` and `--max-runtime` are **en-loop's own**: en-loop interprets them and does not forward them to gnhf verbatim. Only `--agent`, `--max-tokens`, `--worktree` and `--push` are pass-throughs, forwarded **only if `gnhf --help` advertises them**, because gnhf's flag surface is version-dependent and forwarding a flag it does not list is an error.

**`--max-iterations` is the one to get right.** It is the budget for the *whole run*, and gnhf never receives it. What gnhf's own `--max-iterations` receives is `--review-every`, so each chunk stops at the checkpoint boundary and the review can run. Forwarding the user's overall cap instead collapses the run to a single chunk: `--max-iterations 40 --review-every 5` would run forty iterations with **no checkpoint review at all**, which is half of what en-loop adds over a bare gnhf run. en-loop decrements the overall budget itself as chunks complete, and stops launching new ones when it reaches zero.

`--max-runtime` is likewise enforced by en-loop, via `command -v timeout || command -v gtimeout` (macOS: `brew install coreutils`), stopping the current chunk gracefully at the cap rather than relying on a gnhf runtime flag that may not exist.

## Lifecycle and hand-offs

- **Objective source.** A free-form objective, a `docs/plans/tech-debt-tracker.md` item, or a plan (though a peer-reviewed plan is usually better served by `/en-build`).
- **At loop end.** Run Morning Review, then the learning checkpoint via `/en-learn capture` on the branch, then hand off: `/en-review` → `/en-qa` → `/en-ship`.
- **Never auto-merge.** The loop's output is a reviewed feature branch plus the gnhf exit summary. Shipping stays an explicit `/en-ship` decision by the user.

## Safety

- **Preserve user changes.** Never run destructive git commands to clean up a loop branch.
- **No destructive git** inside the loop (enforced by the worker prompt for every worker). **Guardrail coverage is conditional:** `en-guardrail` is a Claude Code `PreToolUse` hook, so it intercepts destructive Bash **only for a `claude` worker** that honors that hook. A `codex` (or other) gnhf worker is **not** covered by the Claude hook — for those runs the protection is the worker prompt's no-destructive-git / preserve-changes rules, gnhf's rollback-on-failure, `--worktree` isolation, and the bounded caps. Preflight reports which applies for the selected worker; prefer `--worktree` for a non-`claude` worker.
- **Per-iteration test-gate** — nothing commits red; a blocked iteration leaves an evidenced note and stops rather than faking success.
- **Bounded caps** — `--max-iterations` / `--max-tokens` / `--max-runtime` keep an unattended run from running away.
- **Never auto-merge, never irreversible while the user is away.** Produce a reviewed branch and an exit summary, not merged or deployed changes, unless the user explicitly authorized it.
- **Completion is not acceptance** — a gnhf stop is a claim, verified independently at Morning Review before anything is called mergeable.

## Reference files

- `$SKILL_DIR/scripts/ensemble-detect-host` — host detection for worker-agent selection; run it, read `HOST`
- gnhf CLI (`npm i -g gnhf`) — the loop engine this skill wraps; surfaced as an optional install by `/en-setup`
