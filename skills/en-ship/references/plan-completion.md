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
