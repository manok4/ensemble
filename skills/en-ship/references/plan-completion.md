# The plan-completion checkpoint's outcomes

Read at the plan-completion checkpoint. `ensemble-plan-checkpoint` returns one
`outcome`; this file says what each one means and which ones flip the plan.

| `outcome` | Meaning | Then |
|---|---|---|
| `up_to_date` | the plan is already `completed` | record `plan_completion_checkpoint: up_to_date`. **Idempotency:** a re-run after the flip silently passes here; the state machine moves forward only. |
| `not_applicable` | no plan for this branch, or it is `draft` / `abandoned` | record `plan_completion_checkpoint: not_applicable`; for `draft`, one line: finalize via `/en-plan` before shipping. |
| `complete` | every in-scope U-ID is covered | record `plan_completion_checkpoint: complete`, then flip. |
| `partial_expected` | every missing U-ID declares `Ship scope: deferred` or `production_pending` | record `plan_completion_checkpoint: partial_expected`, note `partial_expected: U1-U7 shipped; U8 held (production_pending)`, then flip. |
| `complete_evidence_missing` | implementing commits exist, but no `review-verdict:` covers them | record `plan_completion_checkpoint: complete_evidence_missing` with `evidence_warning: no review-verdict covers U5, U6`; the plan stays active. The work is there; the audit trail is not. |
| `incomplete_unexpected` | a U-ID has neither coverage nor an implementing commit | record `plan_completion_checkpoint: incomplete_unexpected` and name the units; the plan stays active. Something is genuinely unbuilt. |

**The flip.** Hands-off (default): auto-select `y` on `complete` / `partial_expected`. `--interactive`: prompt with `y` (recommended) / `skip` / `details`, where `details` shows per-unit state (U-ID, commit, coverage) and re-prompts, loop until terminal. `y`: set `status: completed` and `shipped: <today>` in the frontmatter, `git mv` the file to `docs/plans/completed/`, stage it, and record `plan_completion_checkpoint: completed_and_moved`. The flip commits atomically with the ship commit at step 10; if push or PR creation later fails, the local record is still right (the work is done) and a re-run sees `completed` → `up_to_date`. `skip` records `plan_completion_checkpoint: skipped_by_user`. `--no-plan-completion-checkpoint` skips the step and records `plan_completion_checkpoint: skipped_by_user (--no-plan-completion-checkpoint flag)`.

## Linear mode

**The input is the build's recorded provenance, never the repo's current `plan_store`.**
`plan_store` is mutable: flipping it between build and ship would make a Linear build run local
completion logic, or a local build skip its move to `completed/`. `/en-build` records provenance
at intake and it is immutable thereafter, so ship acts on what the build did.

**Two frontmatter fields, read by name.** `/en-build` writes both into the plan's own
frontmatter; do not infer a key name, and do not confuse either with the repo's live
`plan_store` config value:

| field | what it means | what it decides here |
|---|---|---|
| `plan_source:` | `linear` or `local`, where the plan came from | the lifecycle, per the table below |
| `configured_store:` | what `plan_store` read at intake | the **only** value compared against the repo's current `plan_store` |

Splitting them is load-bearing. The intake matrix deliberately allows a path argument under
`plan_store: linear` for a repo mid-migration, which resolves `plan_source: local` with
`configured_store: linear`. Against one combined field that build is guaranteed to read as
drift and stop on every ship.

| `plan_source` | outcome |
|---|---|
| `local` | unchanged: flip the frontmatter and `git mv` the plan to `docs/plans/completed/` |
| `linear` | record `plan_completion_checkpoint: linear_mode`; **no `git mv`, no frontmatter flip** |
| absent | legacy plan, predating this feature: treat it as `local` and say so once |

In `linear` mode the PR merge moves the parent to Done through Linear's GitHub integration, so
there is nothing on disk to flip and nothing to move. The `linear_mode` outcome records that
the checkpoint ran and deliberately did nothing, which is not the same as `not_applicable`.

A plan with **no provenance field at all** is a legacy plan. Every plan written before this
feature is one, so refusing them would break every in-flight branch the day it ships. Read them
as `local`, which is what they actually were.

**Configuration drift, in both directions.** When the repo's current `plan_store` disagrees with
the recorded `configured_store:`, stop with a blocking error naming both values rather than
guessing which is right. Both directions matter, and provenance is written on **both paths** for
that reason:

- a **linear** build shipped under `plan_store: local`, and
- a **local** build shipped under `plan_store: linear`, which is the more expensive of the two,
  because it is the one that skips the `git mv` and leaves the plan out of `completed/`
  entirely. A provenance field written only on the Linear path catches the first and misses
  this one.

**A generated plan is not a failed archive.** A materialized plan lives under
`.ensemble/materialized-plans/` and an authoring plan under `docs/plans/active/`. They share a
shape, so the directory is what tells them apart; an authoring plan still sitting in `active/`
after a Linear publish means the archive did not complete, and it is never `git mv`d on that
basis.

