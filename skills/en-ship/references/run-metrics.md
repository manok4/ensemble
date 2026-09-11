# Run metrics — what a run records about itself

**The helper that does the work records the work.** `ensemble-test-select` knows
its tier, `ensemble-unit-verify` knows its exit code, `ensemble-peer-invoke`
knows the decision and the elapsed seconds. A model composing a JSON payload by
hand is the intrusion this removes, and it is why two skills carried call points
for weeks and produced nothing.

**Keyed on the skill, not the plan.** `--skill <name>` is required and `--plan`
is optional context, so a skill with no plan records too; the file is
`<skill>-<run-id>.jsonl` under `$(git rev-parse --git-dir)/ensemble/runs/`,
beside the verification receipt. Never committed, no `.gitignore` entry, gone
with the clone. **One JSON object per line, appended**, so parallel dispatches
cannot lose each other's events and reading a run is a line scan.

Carried by `/en-plan`, `/en-build`, `/en-review`, `/en-ship` and
`/en-foundation` — every skill that opens a run.

## Addressing: a file, not an environment variable

`emit` takes **no path**. It resolves, in order:

1. `$ENSEMBLE_RUN_LEDGER` when set. An explicit override, for tests and for a
   genuine subprocess tree.
2. the last live line of `runs/active`, the per-repo stack `start` appends to.
3. nothing. It writes nothing and exits 0.

The environment variable alone cannot carry this, because every tool call in the
host is a fresh shell: a variable exported by the call that ran `start` is gone
by the call that runs `ensemble-unit-verify`. `active` survives across shells.

**A line is live while its ledger holds no `finish` event anywhere in it** — not
"while the last line is not finish". An event arriving after `finish`, which a
stale `ENSEMBLE_RUN_LEDGER` in some other shell produces, would otherwise
resurrect a closed run and misattribute everything after it.

**Nesting needs no skill changes.** When `start` finds a live entry it appends a
`child` pointer to that ledger and records `parent_run_id` in its own. Both
directions are written by the helper that holds both paths, so `/en-build`
invoking `/en-review` produces two first-class runs and a link between them.

## The lifecycle

| When | Call |
|---|---|
| Before the first measured operation | `METRICS=$(bash "$SKILL_DIR/scripts/ensemble-run-metrics" start --skill <name> [--plan <id>])` |
| Any terminal stop, success or failure | `bash "$SKILL_DIR/scripts/ensemble-run-metrics" finish "$METRICS"` |
| The report line | `bash "$SKILL_DIR/scripts/ensemble-run-metrics" summary "$METRICS"` |

**Every terminal path closes the run.** Success, a refusal, a gate that stopped
the skill: each one calls `finish`. A run left open keeps its entry on
`runs/active`, where it becomes a phantom parent for the next run in the repo
and never produces a rollup line, so closing it is part of stopping rather than
part of succeeding.

Every call is fire-and-forget: outside a git repo, without `jq`, or on a bad
payload the helper prints one stderr line and exits 0, and a run is never
blocked by its own bookkeeping.

## The event vocabulary

`emit --kind <kind> --json '<object>'`. **The kind names the schema**, and keys
the kind does not name are **dropped before the line reaches disk**, with the
dropped names on stderr and a `dropped` count on the written line. One table
decides what can be recorded, so nothing downstream re-filters and an emitter
cannot leak a path, a branch name or a payload nobody reviewed.

Helper-emitted, with no call point for a model to remember:

| Kind | Keys | Emitted by |
|---|---|---|
| `select` | `tier`, `reason`, `count`, `total` | `ensemble-test-select`, in `emit()` |
| `verify` | `unit`, `tier`, `ran`, `failed`, `rc`, `checks` | `ensemble-unit-verify`, on all four exit codes |
| `receipt` | `op`, `result`, `reason`, `age_s`, `checks` | `ensemble-verification-receipt`, on `write` and `verify` |
| `peer` | `peer`, `decision`, `reason`, `peer_mode`, `effort`, `model_alias`, `model_actual`, `elapsed_s` | `ensemble-peer-invoke`, in `_epi_decision` |
| `child` | `run_id`, `skill`, `ledger` | `ensemble-run-metrics start`, into the parent |

Model-emitted, one call point, and the only one:

| Kind | Keys | Emitted by |
|---|---|---|
| `outcome` | `result`, `verdict`, `findings_total`, `peer_only`, `corroborated`, `host_only`, `applied`, `deferred`, `disagreed`, `units_total`, `units_done`, `gates_failed` | `/en-review` step 13 |

`/en-review`'s corroboration buckets are computed during reconciliation and
`ensemble-peer-invoke` has no notion of them, so no helper can observe this one.
That is the whole reason for the exception; do not add a second.

The kinds `/en-build` and `/en-plan` still record through `event <file>` are
unchanged: `dispatch` (`agent`, `host`, `model`, `model_source`, `started`,
`ended`), `lint` (`scope`, `seconds`), `findings` (`iteration`, `P0`–`P3`),
`unit` (`unit`, `event`, `commit`, `verify_exit`, `selection_tier`), `phase`
(`checkpoint`, `event`, `units`, `outcome`), `suite` (`where`, `seconds`,
`outcome`), `review` (`event`, `reviewer`, `findings`, `personas`) and `note`.

## The durable rollup

`finish` appends **one summary line per run** to
`$ENSEMBLE_ANALYTICS_DIR/<repo>.jsonl`, defaulting to
`~/.ensemble/analytics/`, beside `guardrail.jsonl` rather than in a new
directory. It carries `schema`, `skill`, `run_id`, `plan_id`, `repo`,
`parent_run_id`, `started_at`, `ended_at`, `duration_s`, a `counts` object per
kind, the `outcome` object verbatim, a `detail` object holding the `select`
tier and the `peer` passes, and `dropped`.

It is wide on purpose. The ledgers die with the clone, so a field omitted today
is unrecoverable for every run before someone adds it.

**Published before the ledger closes**, and idempotent on `run_id` across every
retained generation. If `finish` closed the ledger first and the rollup then
failed, the run's only durable record would be gone with nothing left to retry
from; this way an unwritable store leaves the run open and the next `finish`
retries. A ledger that will never parse is the opposite case and closes rather
than retrying forever.

**Rotates at 5 MB**, keeping exactly one previous generation, so the ceiling is
about 10 MB and never grows. The rename is serialized by a `mkdir` lock: two
finishes both seeing the file over the cap would each rename it and the second
would destroy the first's generation. Losing the lock skips the rename and
appends anyway, so its worst case is a file briefly over the cap.

## Reading it

Three named reports, not a query tool. Each encodes how to read its own numbers.

```
bin/ensemble-metrics --peer-value     # per-run peer-only / corroborated / host-only, and the spread
bin/ensemble-metrics --time           # runs, median, p90 and max duration per skill
bin/ensemble-metrics --selection      # tier distribution and how much of the suite each selected
```

`--peer-value` reports a **distribution, not a ratio**, and deliberately does
not offer the ratio: a peer that finds nothing on easy diffs and everything on
hard ones averages to looking mediocre. Add `--json` for a parseable envelope,
`--repo <name>` to read another repo's rollup.

## Turning it off

`metrics.enabled: false` in `.ensemble/config.local.yaml`, or
`ENSEMBLE_METRICS=off` in the environment. **Checked by every subcommand**, not
by `start` alone, so a run begun before the operator opted out stops recording
rather than finishing its run first. `finish` still pops `active` while opted
out, because that stack is run bookkeeping rather than analytics.

`ENSEMBLE_ANALYTICS_DIR` and `ENSEMBLE_RUN_LEDGER` exist so a test suite can
redirect every write. **No test run may touch the operator's store**;
`tests/lint/analytics-isolation.test.sh` enforces both halves, and the reason it
exists is that `guardrail.jsonl` reached 71,171 events of which 97% were test
noise before anything checked.

## The report line

Skills end their run report with `metrics: <path> (<summary>)`, for example
`metrics: .git/ensemble/runs/en-build-20260911T013747Z-7161.jsonl (2 dispatches, 2 peer passes, 3 lint runs)`.
When metrics were disabled the line reads `metrics: disabled (<reason>)` with
the helper's stderr reason, so a missing file is never mistaken for a run that
recorded nothing.
