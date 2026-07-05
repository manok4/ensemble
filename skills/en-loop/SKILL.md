---
name: en-loop
description: "Run a bounded, objective-driven autonomous loop (the ralph / good-night-have-fun pattern): keep an agent working, one committed test-gated slice per iteration, until an evidence-based stop condition. Wraps the gnhf CLI for the loop engine; adds Ensemble's per-iteration test-gate worker contract and branch-level cross-agent review at checkpoints. Manual-invoke only. Flags: --objective, --stop-when, --max-iterations, --max-tokens, --max-runtime, --worktree, --push, --agent, --review-every N, --mode hands-off|companion. Trigger phrases: 'loop on this', 'keep working overnight', 'run until', 'autonomous loop', 'good night have fun', 'gnhf'."
disable-model-invocation: true
argument-hint: "--objective \"<X>\" --stop-when \"<evidence-based condition>\" [--mode hands-off|companion] [caps]"
---

> **Helper resolution.** All `references/X` and `bin/Y` paths in this skill resolve relative to `$ENSEMBLE_ROOT` — the install root (skill at `$ENSEMBLE_ROOT/skills/<name>/`, shared helpers at `$ENSEMBLE_ROOT/{references,bin}/`). Compute once at start: `$ENSEMBLE_ROOT` env var if set; otherwise `$(realpath "$(dirname <this-SKILL.md>)/../..")`. Fail loudly if `$ENSEMBLE_ROOT/references/host-detect.md` does not resolve — that indicates a partial install (run `/en-setup` to repair).


# `/en-loop`

Run a **bounded, objective-driven autonomous loop**: keep an agent working, one small committed test-gated slice per iteration, toward an objective, until an evidence-based stop condition is met. This is the ralph / autoresearch / "good night, have fun" pattern for overnight, walk-away work.

> **Manual-invoke only.** `disable-model-invocation: true` — en-loop launches a long-running unattended process, so the user always starts it explicitly. It is never auto-triggered.

> **Core rule: the host orchestrates; gnhf executes. Completion is not acceptance.** A gnhf "stop condition met" only means the worker stopped; en-loop independently verifies (Morning Review) before calling anything mergeable. Do not manually implement inside the loop's scope while a gnhf worker owns it, unless the user explicitly changes the delegation.

## What this is (and the engine it wraps)

en-loop is a thin Ensemble layer over **gnhf** (`npm i -g gnhf`), a mature, agent-agnostic loop engine: interrupt handling, commit-on-success / rollback-on-failure, exponential-backoff retries, worktrees, process supervision, a live terminal title, and a permanent exit summary. **en-loop wraps that engine rather than reimplementing it** (the EN04 lesson: do not rebuild robust unattended-loop infra; wrap the existing engine and add value on top).

Ensemble's value-add is exactly two things, not the loop plumbing:

1. **The worker prompt** — Ensemble's per-iteration test-gate contract (implement one slice, run test + lint, commit only on green, no fake success).
2. **The review layer** — a branch-level cross-agent `/en-review --peer-only` at checkpoints (every `--review-every N` iterations and at loop end), whose findings become the next iterations' acceptance criteria.

## When to use which (positioning)

- **vs `/en-flow`** — en-flow is a *fixed one-shot pipeline* (plan → build → learn → ship) for a **defined plan**. en-loop is *open-ended*: an objective whose scope is not fully enumerated, chipped at one committed slice per iteration until a natural-language stop condition ("keep reducing complexity until the suite is green and lint is 0").
- **vs the built-in `/loop`** — `/loop` re-invokes a prompt on a fixed interval in-session. en-loop is objective-driven with commit / rollback / retry and a real supervised (gnhf) process that survives the session.
- **vs `/en-build`** — en-build executes *known plan units* with per-unit and branch-level review. en-loop discovers its slices in the loop, but borrows en-build's per-slice test-gate and the branch-level review model (D35). If the work is already a peer-reviewed plan, use `/en-build`, not en-loop.

## Preflight (before launching a loop)

1. **Detect host.** Source `$ENSEMBLE_ROOT/references/host-detect.md`. Resolve the worker agent host-neutrally: `claude` on a Claude Code host, `codex` on a Codex host (unless the user overrides with `--agent`). Never hardcode a single agent.
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
- Launch gnhf with the prompt, the caps, and `--stop-when`. Wait for exit.
- Intervene early only for hard failure, runaway scope, destructive behavior, or an impossible prerequisite.
- On exit, run Morning Review before reporting anything as done.

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

Then run **independent** verification: `/en-review` over the branch diff plus `/en-qa`, comparing the result to the stop condition and the user's latest feedback. Decide: **Mergeable**, **Needs follow-up loop**, or **Do not merge**. If it needs follow-up, continue in Companion mode instead of presenting the run as complete. Hand off to `/en-ship` only when Mergeable and only with explicit authorization. Never auto-merge.

## Per-iteration worker-prompt contract (fed to gnhf)

This is Ensemble's core value-add over a bare gnhf run. Every iteration follows a **test-gate**: implement one slice, run test + lint, commit only on green. Compose the prompt from this block, substituting `<objective>`, `<test>`, `<lint>`, and `<evidence-based condition>`:

```text
Iteration: implement one small slice toward <objective>. Before coding, inspect the
repo, relevant docs, and recent commits. Preserve user changes; make no unrelated
refactors.

Implement the slice, then run <test> and <lint>. Commit ONLY on green, with a
conventional message and a `phase:` / evidence trailer describing what was verified.

If blocked: NO fake success. Leave a note with the blocker and the evidence, and stop.

Stop only when: <evidence-based condition>.
```

## Checkpoint review (the branch-level review layer)

Ordinary iterations are test-gated but not peer-reviewed (a full Outside Voice pass every iteration is too slow and expensive for a long overnight loop — this is the D39 `performance > speed ≥ cost` trade-off: keep overnight throughput high while still producing a peer-reviewed, evidenced branch).

Instead, review runs at **checkpoints** (branch-level model, D35):

- **Every `--review-every N` iterations, and at loop end**, run `/en-review --peer-only --mode headless` over the branch diff (`git diff <merge-base>..HEAD`). This dispatches the cross-agent Outside Voice peer as the sole reviewer (Claude host → Codex reviews; Codex host → Claude reviews).
- Record the outcome as a `review-verdict:` trailer on a checkpoint commit.
- **Findings become the next iterations' acceptance criteria** — feed them into the next worker prompt as the bounded corrections to make.

Default `--review-every` is 5 iterations. A review always runs at loop end regardless of the interval.

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

If gnhf has no `--model` flag, put model requirements in the worker prompt or the backend config; do not invent a `--model` flag. If `--worktree` is requested, launch gnhf in an isolated worktree so the loop does not disturb the primary checkout.

## Flags

| Flag | Effect |
|---|---|
| `--objective "<X>"` | The one concrete outcome the loop drives toward. Required. |
| `--stop-when "<cond>"` | Evidence-based, Ensemble-observable stop condition. Required; vague conditions are rejected. |
| `--max-iterations <n>` | Cap on loop iterations. |
| `--max-tokens <n>` | Token budget cap for the run. |
| `--max-runtime <dur>` | Wall-clock cap (e.g. `8h`). |
| `--worktree` | Run the loop in an isolated git worktree. |
| `--push` | Allow the loop to push the feature branch (still never auto-merges). |
| `--agent <claude\|codex>` | Override the host-detected worker agent. |
| `--review-every <N>` | Run the checkpoint `/en-review --peer-only` every N iterations (default 5; a review always runs at loop end). |
| `--mode <hands-off\|companion>` | Select the run mode (default `hands-off`). |

## Lifecycle and hand-offs

- **Objective source.** A free-form objective, a `docs/plans/tech-debt-tracker.md` item, or a plan (though a peer-reviewed plan is usually better served by `/en-build`).
- **At loop end.** Run Morning Review, then the learning checkpoint via `/en-learn capture` on the branch, then hand off: `/en-review` → `/en-qa` → `/en-ship`.
- **Never auto-merge.** The loop's output is a reviewed feature branch plus the gnhf exit summary. Shipping stays an explicit `/en-ship` decision by the user.

## Safety

- **Preserve user changes.** Never run destructive git commands to clean up a loop branch.
- **No destructive git** inside the loop; `en-guardrail` still intercepts destructive Bash commands the worker attempts (the guardrail hook applies inside the worker too).
- **Per-iteration test-gate** — nothing commits red; a blocked iteration leaves an evidenced note and stops rather than faking success.
- **Bounded caps** — `--max-iterations` / `--max-tokens` / `--max-runtime` keep an unattended run from running away.
- **Never auto-merge, never irreversible while the user is away.** Produce a reviewed branch and an exit summary, not merged or deployed changes, unless the user explicitly authorized it.
- **Completion is not acceptance** — a gnhf stop is a claim, verified independently at Morning Review before anything is called mergeable.

## Reference files

- `$ENSEMBLE_ROOT/references/host-detect.md` — host detection (worker-agent selection)
- gnhf CLI (`npm i -g gnhf`) — the loop engine this skill wraps; surfaced as an optional install by `/en-setup`
