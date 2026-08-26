# `/en-build` — contract for calling skills

Owned by `en-build`. Callers depend on this page, not on `SKILL.md`.

## Accepted invocations

| Form | Caller |
|---|---|
| `/en-build <plan-path>` | `en-flow` |
| `--unit U<N>` · `--from U<N>` · `--from-phase P<N>` | selection |
| `--no-simplify` · `--no-peer` · `--no-peer-per-unit` | post-build control, each recorded |
| `--orchestrate` · `--handoff` | force a flavor |

The plan must be at `status: open` (or `in_progress` when resuming). A caller
passing a `draft` plan gets a refusal or a recovery prompt, not a build.

## Non-interactive guarantee

**Not guaranteed, and this is deliberate.** Destructive and `gated: true` units
always stop for explicit confirmation, and **no flag disables that**. A caller
must either accept that a build can block, or verify the plan has no such units
first. Everything else advances autonomously.

## Return

A build summary. Callers branch on:

| Field | Values |
|---|---|
| `simplify_pass` | `completed` · `not_applicable` · `failed` · `missing` |
| `branch_review_pass` | `completed` · `fallback_completed` · `failed` · `missing` |
| `learning_checkpoint` | `captured (N learnings)` · `intentionally_skipped` · `up_to_date` · `ci_environment` |
| audit verdict | `ok` · `failed` |

**Branch on these exact spellings**, never the bare word `skipped`. A `missing`
or `failed` on either gate makes the audit `failed` even when every unit is
covered, and blocks the ship hand-off.

## Authority envelope

Writes code, runs tests, and commits per unit on a feature branch. **Never opens
a PR** (that is `en-ship`), never modifies plan content beyond the lifecycle
status flip, never deletes outside a unit's scope, and never auto-commits or
auto-stashes on abort or Ctrl-C.

## Cost bounds

The branch-level model runs `en-simplify` and the Outside Voice review **once**
over the branch diff, not per unit. Only destructive and gated units get a
dedicated per-unit peer pass, capped by `--max-per-unit-iterations` (default 1).

## Recursion

Under `ENSEMBLE_PEER_REVIEW=true` all peer subprocess calls are skipped and each
unit commit records `peer-skipped: recursion-guard-active` so the evidence gate
still passes. It never invokes itself.
