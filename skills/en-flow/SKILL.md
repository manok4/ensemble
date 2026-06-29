---
name: en-flow
description: "Run the full hands-off Ensemble pipeline from plan through a ready-for-review PR: en-plan → en-build → en-learn (model-decided) → en-ship (with watch loop). Manual-invoke only (never auto-triggered). Flags: --plan <path> (skip planning), --no-ship (stop after build), --no-watch (pass through to en-ship). Trigger phrases: 'run the full pipeline', 'plan build and ship', 'take this end to end', 'en-flow'."
disable-model-invocation: true
argument-hint: "[feature description, or --plan <path>]"
---

> **Helper resolution.** All `references/X` and `bin/Y` paths in this skill resolve relative to `$ENSEMBLE_ROOT` — the install root (skill at `$ENSEMBLE_ROOT/skills/<name>/`, shared helpers at `$ENSEMBLE_ROOT/{references,bin}/`). Compute once at start: `$ENSEMBLE_ROOT` env var if set; otherwise `$(realpath "$(dirname <this-SKILL.md>)/../..")`. Fail loudly if `$ENSEMBLE_ROOT/references/host-detect.md` does not resolve — that indicates a partial install (run `/en-setup` to repair).


# `/en-flow`

The hands-off Ensemble pipeline. Carries one piece of work from plan → build → learn → ship without you chaining skills by hand. A thin orchestrator: each stage is an existing Ensemble skill; en-flow only sequences them, gates between them, and passes artifacts forward.

> **Manual-invoke only.** `disable-model-invocation: true` — en-flow is never auto-triggered; the user starts it explicitly. It is the only skill that invokes other lifecycle skills in sequence.

> **CRITICAL: execute stages IN ORDER. Do not skip the plan stage and jump to coding.** Each stage has a GATE that must pass before the next begins. Resolve each sub-skill name against the host's available-skills list (some platforms namespace them, e.g. `ensemble:en-build`); match a listed entry verbatim before invoking.

## Process

1. **Detect host.** Source `$ENSEMBLE_ROOT/references/host-detect.md`.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, exit (pipeline never runs inside a peer subprocess).
3. **Shipping precondition.** Run `git remote` once. **No remote** → record `local_only: true`: every stage still runs and commits locally, but the ship stage skips push / PR / watch (a missing remote is a terminal local-only state, not an error — never retry a push). A remote exists → full pipeline.

### Stage 1 — Plan

- If `--plan <path>` was passed, use that plan; otherwise invoke `/en-plan` with `$ARGUMENTS`.
- **GATE:** a plan file exists at `docs/plans/active/<PREFIX><NN>-*.md` with `status: open` (or the `--no-peer` finalize path). Read its frontmatter; stop the pipeline if the request was non-software / not implementation-ready, or if the plan is stuck in `draft` (surface and stop). **Record the plan path** — it threads through stages 2–4.

### Stage 2 — Build

- Invoke `/en-build <plan-path>`. Per the branch-level review model (D35), en-build internally runs its post-build phase (`/en-simplify` → cross-agent Outside Voice review on the peer → apply → review-verdict) before handing off — en-flow does **not** re-run simplify/review at the top level.
- **GATE:** build completed and the end-of-build evidence audit passed (`verdict: ok`). If the audit failed, **stop** and surface the failing units (suggest `/en-cross-review` per en-build's failure path); do not proceed to ship.

### Stage 3 — Learn (model-decided)

- Ensure `/en-learn` is **considered** exactly once. **The model decides whether a capture is warranted** based on the build outcome: capture when there's durable insight — a non-obvious pattern, a deviation from the plan, a library footgun, a recurring shape worth filing; skip silently for a mechanical change with no generalizable lesson. This mirrors en-learn's existing soft-prompt contract; it is a judgment step, not an unconditional invocation.
- **No double-capture.** en-build's post-build phase already hands off to `/en-learn`. If that capture already ran this pipeline, this stage is a **no-op** — do not file a second time. Treat stage 3 as a backstop: it only acts if the build's hand-off was skipped/declined AND the model judges a capture is now warranted.

### Stage 4 — Ship

- **If `local_only`** (no remote): make any remaining commits locally and **stop** — surface the local-only summary (branch, commits, "no remote; push manually when ready"). Skip the rest of this stage.
- **If `--no-ship`:** stop after build/learn; surface what's ready and the suggested `/en-ship` command. Skip shipping.
- Otherwise invoke `/en-ship`. Per its default, en-ship opens the PR then enters the **bounded watch loop** (poll CI + reviews → `/en-resolve-pr`, capped at 2 cycles, then escalate needs-human). Pass `--no-watch` through when en-flow was invoked with `--no-watch`.
- **No auto-merge.** en-flow never merges; en-ship is invoked without `--auto-merge`. The user merges when the PR is ready.

5. **Terminal report.** Emit a completion summary: plan path, units built, audit verdict, whether a learning was captured, PR URL (or local-only summary). End with an explicit done marker.

## Flags

| Flag | Effect |
|---|---|
| `--plan <path>` | Skip Stage 1 planning; build the named existing plan. |
| `--no-ship` | Run plan + build + learn, then stop (no push / PR). |
| `--no-watch` | Pass through to `/en-ship` — open the PR but skip the watch loop. |

## What this skill never does

- **Never auto-triggers.** `disable-model-invocation: true`; the user invokes it explicitly.
- **Never skips the plan stage.** Plan first, always — building without a finalized plan is the failure mode this pipeline exists to prevent.
- **Never auto-merges.** Shipping opens a ready-for-review PR; merging is the user's call.
- **Never double-captures learnings.** Stage 3 is a no-op when en-build already handed off to `/en-learn`.
- **Never re-runs simplify/review at the top level.** Those live inside en-build's post-build phase (D35).
- **Never pushes when there is no remote.** Local-only is a terminal success state, not an error to retry.

## Reference files

- `$ENSEMBLE_ROOT/references/en-flow-pipeline.md` — stage contracts and gates
- `$ENSEMBLE_ROOT/references/host-detect.md`

## Failure protocol

| Failure | Behavior |
|---|---|
| Plan stage produces no plan / plan stuck in `draft` | Stop; surface; suggest `/en-plan --resume`. |
| Build evidence audit fails | Stop before ship; surface failing units; suggest `/en-cross-review`. |
| Non-software or not-implementation-ready request | Stop after Stage 1 with a clear message. |
| No git remote | Local-only: commit locally through build; skip push/PR/watch; surface summary. |
| A sub-skill name doesn't resolve | Stop; surface the unresolved name; tell the user to check the plugin install. |
