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
2. the newest open run in `runs/active`, the per-repo run log.
3. nothing. It writes nothing and exits 0.

**`runs/active` is append-only, and that is the whole design.** `start` appends
`+<TAB>run_id<TAB>path` and `finish` appends `-<TAB>...`; resolution replays the
tail backwards and takes the newest `+` with no matching `-`. Nothing rewrites
it, so there is nothing to race, nothing to lock, and nothing to prune.

That shape was earned. It began as a mutable stack, and three consecutive peer
passes found defects in it: a rewrite clobbered a concurrent append and lost
five registrations of twelve, the lock added to fix that could be leaked by an
argument check and stalled a contended caller for six seconds, its ownership
test could not tell "I hold it" from "someone else does", and the prune deleted
exactly the runs waiting to be retried. Every one is a property of rewriting a
shared file.

The environment variable alone cannot carry this, because every tool call in the
host is a fresh shell: a variable exported by the call that ran `start` is gone
by the call that runs `ensemble-unit-verify`. `active` survives across shells.

**A run is open while its ledger holds no `finish` event anywhere in it** — not
"while the last line is not finish". An event arriving after `finish`, which a
stale `ENSEMBLE_RUN_LEDGER` in some other shell produces, would otherwise
resurrect a closed run and misattribute everything after it. A ledger also stops
counting as open twenty-four hours after its last write, because a run killed
before its finish step can never satisfy the first test and would otherwise
parent every later run in the repo forever.

`finish` resolves a slightly wider set than `emit`: a run that is **publishing**
is closed to new events but is exactly what a retry must find.

**Nesting needs no skill changes.** When `start` finds a live entry it appends a
`child` pointer to that ledger and records `parent_run_id` in its own. Both
directions are written by the helper that holds both paths, so `/en-build`
invoking `/en-review` produces two first-class runs and a link between them.

## The lifecycle

| When | Call |
|---|---|
| Before the first measured operation | `bash "$SKILL_DIR/scripts/ensemble-run-metrics" start --skill <name> [--plan <id>]` |
| Any terminal stop, success or failure | `bash "$SKILL_DIR/scripts/ensemble-run-metrics" finish` |
| The report line | `bash "$SKILL_DIR/scripts/ensemble-run-metrics" summary` |

**No path, and no variable to carry.** `finish` and `summary` resolve the run the
same way `emit` does. An earlier version took `"$METRICS"` from `start`, which
cannot work for the reason at the top of this file: the variable does not survive
to the call that closes the run. It resolved to the empty string, the helper
treated that as "metrics disabled", and the run was never published, never
closed, and parented every later run in the repo. Passing an explicit path still
works and is what the tests use.

**Every terminal path closes the run.** Success, a refusal, a gate that stopped
the skill: each one calls `finish`. A run left open keeps its entry on
`runs/active`, where it becomes a phantom parent for the next run in the repo
and never produces a rollup line, so closing it is part of stopping rather than
part of succeeding. A run nobody closes stops counting as live after
twenty-four hours, which bounds the damage without hiding it.

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
| `peer` | `peer`, `decision`, `reason`, `peer_mode`, `effort`, `model_alias`, `model_actual`, `elapsed_s`, `iteration` | `ensemble-peer-invoke`, in `_epi_decision`; `/en-plan` adds `iteration`, which no helper can see |
| `child` | `run_id`, `skill`, `ledger` | `ensemble-run-metrics start`, into the parent |

**Model-emitted, for what no helper can see.** Every one of these describes a
decision the model made, so there is nothing for a script to observe. They are
recorded with `emit`, like everything else; the call points are the table below.

| Kind | Keys | Call point |
|---|---|---|
| `outcome` | `verdict`, `findings_total`, `peer_only`, `corroborated`, `host_only`, `applied`, `deferred`, `disagreed` | `/en-review`, after reconciliation, in its output-report step |
| `dispatch` | `agent`, `host`, `model`, `model_source`, `started`, `ended` | `/en-plan` and `/en-build`, once each research or persona agent returns |
| `findings` | `iteration`, `P0`, `P1`, `P2`, `P3` | `/en-plan`, after parsing each peer pass's findings |
| `lint` | `scope`, `seconds` | `/en-plan` and `/en-build`, after each lint run |
| `unit` | `unit`, `event`, `commit`, `verify_exit`, `selection_tier` | `/en-build`, entering a unit and again after it commits |
| `phase` | `checkpoint`, `event`, `units`, `outcome` | `/en-build`, at each phase checkpoint |
| `suite` | `where`, `seconds`, `outcome` | `/en-build`, around any full-suite run |
| `review` | `event`, `reviewer`, `findings`, `personas` | `/en-build`, around its branch-level review |
| `note` | `message`, `detail` | anywhere; free-form, and nothing reads it back |

`/en-review`'s corroboration buckets are computed during reconciliation and
`ensemble-peer-invoke` has no notion of them, so no helper can observe that one.
The same is true of every row above it: a phase boundary and a persona roster
are model concepts. **What is not allowed is a second call point for something a
helper CAN see.** The four emitters exist because bookkeeping the model has to
remember is bookkeeping the model forgets, and that verdict is already in.

`tests/lint/metrics-vocabulary.test.sh` holds this table and `_ALLOW` to each
other. They are two of the three places the vocabulary lives, and the third is
each emitter's payload; without that lint, a key added to one and not the other
becomes a column that is quietly always absent. That is not hypothetical: the
rewrite that produced this file deleted every model call point while leaving a
sentence saying they were unchanged, and nothing went red.

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

`start`, `closing` and `finish` are lifecycle markers rather than events. They
are written by the helper directly, carry no payload, and are not counted in
`counts`; `closing` is what makes publishing safe, and is described with the
rollup below.

**Published before the ledger closes**, and idempotent on `run_id` across every
retained generation. If `finish` closed the ledger first and the rollup then
failed, the run's only durable record would be gone with nothing left to retry
from; this way an unwritable store leaves the run open and the next `finish`
retries, bounded at two attempts so one wedged store cannot hold every run in
the repo open. The check, the rotation and the append are **one transaction**
under a lock on the rollup file, because separately two finishes both saw no
existing line and both appended.

**One torn line costs one line.** The ledger is parsed per record, so a partial
write is skipped rather than failing the whole file, which is the entire reason
the format is JSONL. `jq -s` failed the complete ledger on any bad line and the
run was then discarded.

**Rotates at 5 MB**, keeping exactly one previous generation, so the ceiling is
about 10 MB and never grows. Two finishes both seeing the file over the cap
would each rename it and the second would destroy the first's generation, so the
rename happens inside the same transaction as the check and the append. A caller
that cannot take that lock within a second **defers**: the run stays open and a
later `finish` publishes it, which cannot duplicate and cannot drop.

## Reading it

Three named reports, not a query tool. Each encodes how to read its own numbers.

`ensemble-metrics`, at the Ensemble repo root beside `ensemble-lint`. No skill
runs it; it is what a person runs to read what the skills recorded.

```
ensemble-metrics --peer-value     # per-run peer-only / corroborated / host-only, and the spread
ensemble-metrics --time           # runs, median, p90 and max duration per skill
ensemble-metrics --selection      # tier distribution and how much of the suite each selected
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
