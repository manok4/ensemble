---
name: en-flow
description: "Run the hands-off pipeline from plan to a ready-for-review PR: en-plan, en-build, en-learn, then en-ship with its watch loop. Manual-invoke only. Trigger phrases: 'run the full pipeline', 'plan build and ship', 'take this end to end', 'en-flow'."
disable-model-invocation: true
---


# `/en-flow`

The hands-off Ensemble pipeline. Carries one piece of work from plan → build → learn → ship without you chaining skills by hand. A thin orchestrator: each stage is an existing Ensemble skill; en-flow only sequences them, gates between them, and passes artifacts forward.

> **Manual-invoke only.** `disable-model-invocation: true` — en-flow is never auto-triggered; the user starts it explicitly. It is the only skill that invokes other lifecycle skills in sequence.

> **CRITICAL: execute stages IN ORDER. Do not skip the plan stage and jump to coding.** Each stage has a GATE that must pass before the next begins. Resolve each sub-skill name against the host's available-skills list (some platforms namespace them, e.g. `ensemble:en-build`); match a listed entry verbatim before invoking.

## Stage graph

```
[--plan? ]── en-plan ──▶ plan file (status: open)        GATE: plan exists & buildable
                 │
                 ▼
            en-build ──▶ branch w/ unit commits +        GATE: evidence audit verdict: ok
                         post-build review-verdict
                 │       (en-build internally runs
                 │        en-simplify → /en-review --cross)
                 ▼
        en-learn (model-decided) ─▶ optional learning    acts only on ci_environment / missing
                 │
                 ▼
     [local-only? / --no-ship? ]── en-ship ──▶ PR +      no auto-merge; watch loop → en-resolve-pr
                                    watch loop            (bounded 2 repair cycles, then escalate)
                 │
                 ▼
              terminal report
```

## Process

1. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, exit (pipeline never runs inside a peer subprocess).
2. **Shipping precondition.** Run `git remote` once. **No remote** → record `local_only: true`: every stage still runs and commits locally, but the ship stage skips push / PR / watch (a missing remote is a terminal local-only state, not an error — never retry a push). A remote exists → full pipeline.

### 3. Plan

- If `--plan <path>` was passed, use that plan; otherwise invoke `/en-plan` with the request the user gave `/en-flow`, passed through verbatim. Pass the words, not a host substitution such as `$ARGUMENTS`, which expands to empty on Codex and plans nothing silently (D70).
- **GATE:** a plan file exists at `docs/plans/active/<PREFIX><NN>-*.md` with `status: open` (or the `--no-peer` finalize path). Read its frontmatter; stop the pipeline if the request was non-software / not implementation-ready, or if the plan is stuck in `draft` (surface and stop). **Record the plan path** in `/tmp/ensemble/en-flow/<run-id>/state.json`; it threads through steps 4 to 6, and a stage is long enough for the context to be compacted between it and the next. Before each stage, print one line naming the stage that finished and its result, and the stage starting.

### 4. Build

- Invoke `/en-build <plan-path>`. en-build internally runs its post-build phase before handing off, and en-flow does **not** re-run simplify or review at the top level: cheap gate → `/en-simplify` on the branch diff → **`/en-review --cross`** → apply → `review-verdict:`.
- **The review is peer *and* host personas, not peer alone.** `--cross` means the cross-agent peer is mandatory and the persona roster is additive, so the build gate does produce standards, testing and maintainability findings (D46, D52; the flag is the one en-build invokes).
- **GATE:** build completed and the end-of-build evidence audit passed (`verdict: ok`). If the audit failed, **stop** and surface the failing units (suggest `/en-review --peer <sha>` on the failing commits per en-build's failure path); do not proceed to ship.

### 5. Learn (model-decided)

- Ensure `/en-learn` is **considered** exactly once. **The model decides whether a capture is warranted** based on the build outcome: capture when there's durable insight — a non-obvious pattern, a deviation from the plan, a library footgun, a recurring shape worth filing; skip silently for a mechanical change with no generalizable lesson. This mirrors en-learn's existing soft-prompt contract; it is a judgment step, not an unconditional invocation.
- **Read en-build's outcome before doing anything.** Its learning checkpoint records one of four canonical values in `learning_checkpoint:`; record the value in `state.json` as soon as the build stage returns, and read it from there. Each one settles this step on its own:

  | `learning_checkpoint:` | What step 5 does |
  |---|---|
  | `captured (N learnings)` | **Nothing.** The capture ran; filing again would duplicate it. |
  | `intentionally_skipped` | **Nothing.** A person was asked and answered `skip`, or policy set `build.learning_checkpoint: false`. Either way the decision is already made and is not this step's to revisit. |
  | `up_to_date` | **Nothing.** Zero commits since the last capture; there is nothing to file. |
  | `ci_environment` | **Consider a capture.** Nobody was there to ask, so no decision was made. |

  If the value is missing entirely, the hand-off never ran, and this step considers a capture as it would in `ci_environment`.
- **The backstop covers an unasked question, not an answered one.** en-build's four values distinguish *nobody was asked* from *someone said no*; a step that acted on both would capture over a user who answered `skip` (D70).

### 6. Ship

- **If `local_only`** (no remote): make any remaining commits locally and **stop** — surface the local-only summary (branch, commits, "no remote; push manually when ready"). Skip the rest of this stage.
- **If `--no-ship`:** stop after build/learn; surface what's ready and the suggested `/en-ship` command. Skip shipping.
- Otherwise invoke `/en-ship`. Per its default, en-ship opens the PR then enters the **bounded watch loop** (poll CI + reviews → `/en-resolve-pr`, capped at 2 cycles, then escalate needs-human). Pass `--no-watch` through when en-flow was invoked with `--no-watch`.
- **No auto-merge.** en-flow never merges; en-ship is invoked without `--auto-merge`. The user merges when the PR is ready.

7. **Terminal report.** From `state.json`, emit a completion summary: plan path, units built, audit verdict, whether a learning was captured, PR URL (or local-only summary). End with an explicit done marker: the last line is `en-flow: done` or `en-flow: stopped at <step> — <reason>`, so a reader can tell a finished run from one that stopped at a gate.

## Flags

| Flag | Effect |
|---|---|
| `--plan <path>` | Skip the plan stage (step 3); build the named existing plan. |
| `--no-ship` | Run plan + build + learn, then stop (no push / PR). |
| `--no-watch` | Pass through to `/en-ship` — open the PR but skip the watch loop. |

## What this skill never does

- **Never auto-triggers.** `disable-model-invocation: true`; the user invokes it explicitly.
- **Never skips the plan stage.** Plan first, always — building without a finalized plan is the failure mode this pipeline exists to prevent.
- **Never auto-merges.** Shipping opens a ready-for-review PR; merging is the user's call.
- **Never double-captures learnings, and never overrides a decline.** Step 5 reads en-build's `learning_checkpoint:` and acts only on `ci_environment` or a missing value.
- **Never re-runs simplify/review at the top level.** Those live inside en-build's post-build phase (D52).
- **Never pushes when there is no remote.** Local-only is a terminal success state, not an error to retry.

## Failure protocol

| Failure | Behavior |
|---|---|
| Plan stage produces no plan / plan stuck in `draft` | Stop; surface; suggest `/en-plan --resume`. |
| Build evidence audit fails | Stop before ship; surface failing units; suggest `/en-review --peer <sha>` on the failing commits. |
| Non-software or not-implementation-ready request | Stop after step 3 with a clear message. |
| No git remote | Local-only: commit locally through build; skip push/PR/watch; surface summary. |
| A sub-skill name doesn't resolve | Stop; surface the unresolved name; tell the user to check the plugin install. |
