---
type: plan
plan_type: feature
plan_id: EN17
title: Per-skill analytics, helpers record what each skill run cost and produced
status: completed
location: completed
created: 2026-09-10
shipped: 2026-09-11
deepened:
covers_requirements: []
requirements_pending: true
related_design: docs/designs/2026-09-10-per-skill-analytics-design.md
peer_review_verdict: reject
peer_review_overridden: true
peer_review_iterations: 2
peer_review_last_run: 2026-09-10
peer_review_plan_hash: 3eb7cfec5e4a5c9de2a3d84ec90e7d2f3022670b5b7ec8e9708e4ff67c634853
peer_review_resolutions:
  - finding_id: "1-1"
    iteration: 1
    severity: P1
    title: Instrumented skills lack complete run lifecycles
    status: applied
    rationale: U12 added; en-ship, en-review and en-foundation now open and close their own runs, guarded by a lint. The bypass fixture this rationale originally promised was not built: routing a prose failure table through a reporting step is not statically checkable, and U12 says so rather than claiming a gate that does not exist
    location: U12
  - finding_id: "1-2"
    iteration: 1
    severity: P1
    title: Dependencies do not protect duplicated carrier consistency
    status: applied
    rationale: U3 now depends on U2 and U4-U7 on U12, so every run-metrics edit precedes any new carrier; U8's forward reference to U10 removed and U8 now depends on U6
    location: U3, U4, U5, U6, U7, U8
  - finding_id: "1-3"
    iteration: 1
    severity: P1
    title: Config opt-out can still record into a stale active run
    status: applied
    rationale: opt-out moved to a _metrics_off() called by start, emit, event and finish; mid-run opt-out scenario added
    location: U1
  - finding_id: "1-4"
    iteration: 1
    severity: P1
    title: Rollup failures and rotation races can permanently lose data
    status: applied
    rationale: rollup published before the finish event and idempotent on run_id, so a failed write retries; the rotation lock is disagreed with, since the line survives in one generation or the other and both are read
    location: U3
  - finding_id: "1-5"
    iteration: 1
    severity: P1
    title: Outcome recording remains model-dependent
    status: disagreed
    rationale: the proposed shape is what U8 already does; no helper can observe corroboration, which is why the design made this the one exception. The review's testing point was taken, U8 now asserts through --peer-value
    location: U8
  - finding_id: "2-1"
    iteration: 2
    severity: P0
    title: Rollup rotation can still lose data
    status: applied
    rationale: two concurrent over-cap finishes each mv to .1 and the second destroys the first's generation; rotation is now serialized by a mkdir lock whose failure mode is a skipped rename, idempotence scans both generations, and the two contradictory read-only scenarios are replaced by one contract
    location: U3
  - finding_id: "2-2"
    iteration: 2
    severity: P1
    title: Opt-out can leave a stale active run
    status: applied
    rationale: finish now pops `active` even when metrics are off, and liveness is the absence of any finish event in the ledger rather than a last-line test; two scenarios added
    location: U1
  - finding_id: "2-3"
    iteration: 2
    severity: P1
    title: U8 consumes the U9 report before depending on it
    status: applied
    rationale: U9 added to U8's dependencies; the report-level assertion stays where it proves the most
    location: U8
  - finding_id: "2-4"
    iteration: 2
    severity: P1
    title: Failure-path closure is not actually verified
    status: applied
    rationale: the contract is stated once in the shared reference and each carrier is checked for a citation; the bypass fixture was not built, because deciding whether a prose failure-protocol row reaches a reporting step needs a reader rather than a grep, and U12 now says so
    location: U12
  - finding_id: "2-5"
    iteration: 2
    severity: P1
    title: Setup gives an unsafe blanket deletion instruction
    status: applied
    rationale: the advisory now classifies each oversized file and never says "safe to delete"; the rollup is named as the only surviving record with an export command, asserted by a grep for the phrase
    location: U11
depth: deep
data_scale: small
---

# EN17 — Per-skill analytics, helpers record what each skill run cost and produced

## Context

`ensemble-run-metrics` has existed since D106 and has never written a ledger in this repo, because recording was the model's job and the model forgot. The peer-in-the-fix-loop question has been parked for weeks on data that was never accumulating. This plan moves recording into the helpers that already know the answers: `ensemble-test-select` knows its tier, `ensemble-unit-verify` knows its exit code, `ensemble-peer-invoke` knows the decision and the elapsed seconds. No extra model turns, no extra tokens, and nothing that can block a run.

The design (`docs/designs/2026-09-10-per-skill-analytics-design.md`) settled the architecture. This plan carries it, with one mechanism correction recorded under Decisions.

## Requirements covered

None as R-IDs (`requirements_pending: true`). The plan implements the settled-decisions table of the related design.

## Out of scope for this plan

- The remaining helpers beyond the four named. The design deliberately keeps the first tranche small so the event vocabulary can be checked against real ledgers before it spreads.
- Migrating, truncating or pruning the operator's existing `~/.ensemble/analytics/guardrail.jsonl`. U11 surfaces its size; deleting operator data stays the operator's call.
- A generic query tool over the ledgers. Three named reports only.
- Measuring whether the work was any good. This data can say a skill is efficient; it only proxies for effective, and the design says so.

## Approach (high-level)

A skill run becomes a first-class unit with its own ledger. `ensemble-run-metrics start` mints `<skill>-<run-id>.jsonl` under `$(git rev-parse --git-dir)/ensemble/runs/` and registers it on a small `active` stack file beside it. Helpers call `ensemble-run-metrics emit --kind <k> --json '<obj>'` with no file argument; `emit` resolves the ledger from `$ENSEMBLE_RUN_LEDGER` when set, otherwise from the top live entry of `active`, otherwise does nothing at all. That last clause is what makes every helper's new call free: outside a run, and in every existing test, `emit` is a no-op that exits 0.

A per-kind key allowlist runs at write time. Keys not named for the kind are dropped before the line reaches disk and noted to stderr, so an unrecognised field is loud in a test run and invisible in a real one.

On `finish`, one summary line per run is appended to `$ENSEMBLE_ANALYTICS_DIR/<repo>.jsonl`, defaulting to `~/.ensemble/analytics/`, beside the guardrail store rather than in a new directory. That line is the only artifact that survives the clone, so it carries the run's counts, its outcome fields, and the small per-kind aggregates the three named reports need, rather than the minimum that answers today's question. The file rotates at a size cap so it cannot become the 8.6 MB that prompted this.

Test isolation is built in from the first unit, not retrofitted: `ENSEMBLE_ANALYTICS_DIR` and `ENSEMBLE_RUN_LEDGER` exist so a suite can redirect every write, and `tests/lint/analytics-isolation.test.sh` (merged in PR #108) already discovers analytics writers by grep, so the rollup writer is picked up the moment it exists.

## Test seams

Two, and only the second is new.

- **The helper's CLI surface, observed through the files it writes into a throwaway git repo.** Every existing helper test already works this way (`tests/lint/ensemble-unit-verify.test.sh` builds `$WORK/proj` with `git init -q` and drives the script from inside it). Every behavioural scenario in this plan is asserted there: run the script, read the JSONL, assert on the parsed line. It is the highest seam that can still observe an emit, and it survives any restructuring inside the scripts.
- **The source tree, read statically by `tests/lint/analytics-isolation.test.sh`.** This one exists because the invariant is "no writer can be un-redirectable" and "no suite drives a writer without redirecting it", which are properties of the code, not of a run. A behavioural test cannot prove the absence of a hardcoded path in a branch it did not take. U3 widens its existing suite loop past `tests/en-guardrail/`.

Deliberately not a seam: the operator's real `~/.ensemble/analytics/`. Nothing in the suite may touch it, which is the point of the guard.

## Technical design

Four components and four data-flow stages, so the sketch is load-bearing.

```
  skill run                       helper                        operator
  ─────────                       ──────                        ────────
  run-metrics start  ──writes──>  <skill>-<run-id>.jsonl
         │                        ^   ^   ^
         └──registers──> active   │   │   │
                          │       │   │   │
    ensemble-test-select ─┼───────┘   │   │   emit --kind select
    ensemble-unit-verify ─┼───────────┘   │   emit --kind verify
  ensemble-verif-receipt ─┼───────────────┤   emit --kind receipt
    ensemble-peer-invoke ─┘               │   emit --kind peer
    /en-review (model)  ──────────────────┘   emit --kind outcome
                                  │
  run-metrics finish ─────────────┴──appends──> ~/.ensemble/analytics/<repo>.jsonl
                                                         │
                                     bin/ensemble-metrics ┴─> --peer-value | --time | --selection
```

**Ledger addressing.** `emit` resolves in this order and never invents a third: `$ENSEMBLE_RUN_LEDGER` when non-empty; else the last live line of `$git_dir/ensemble/runs/active`; else no-op, exit 0. A line is live when its ledger file exists and does not yet contain a `finish` event. `active` holds `<run_id><TAB><ledger-path>` per line; `start` appends, `finish` removes its own line by path.

**Nesting.** When `start` finds a live top entry, it appends a `child` event to that parent's ledger naming the new run, and records `parent_run_id` in its own `start` line. Both directions are written by the helper that holds both paths, so no skill has to know it is nested.

**Privacy boundary.** The allowlist is the only place a key is judged. Every emitter passes a JSON object; `emit` intersects its keys with the kind's allowed set, drops the rest, and counts the drops. Nothing downstream re-filters, so there is one place to read to know what can reach disk.

**Rollup contract.** One line per `finish`, schema-versioned, carrying `counts` per kind, the `outcome` object verbatim, and a `detail` object holding the aggregates the three reports need (the `select` tier and ratio, the `peer` decisions and elapsed times). The ledgers are gone with the clone; this line is not.

## Implementation units

### U1. Ledger addressing: the `active` stack, `emit`, the child pointer, and the opt-out

- **Goal:** A helper anywhere in the repo can call `ensemble-run-metrics emit` with no file argument and have the event land in the current run's ledger, or nowhere at all.
- **Requirements covered:** none (`requirements_pending: true`); the design's "How a helper knows it is in a run" and "Nested runs" rows.
- **Dependencies:** none
- **Interfaces:**
  - *Produces:* `ensemble-run-metrics emit --kind <kind> --json '<object>'`. No file argument. Resolution order: `$ENSEMBLE_RUN_LEDGER` when non-empty, else the last live line of `$git_dir/ensemble/runs/active`, else no-op. Exit code is **always 0**, on every path including a missing ledger, absent jq, a malformed payload, and outside a git repo. Writes at most one line to stderr on a problem.
  - *Produces:* `$git_dir/ensemble/runs/active`, one `<run_id><TAB><ledger-path>` per line, newest last. A line is live when its ledger exists and contains **no `finish` event anywhere in the file**, tested with a grep over the whole ledger rather than by inspecting the last line. A late event arriving after `finish` would otherwise make a closed run look live again, which is the stale-variable case the design's devil's advocate names.
  - *Produces:* the `child` event shape, appended to the parent ledger: `{"kind":"child","at":<iso8601>,"run_id":<child run_id>,"skill":<child skill>,"ledger":<absolute path>}`.
  - *Produces:* `ENSEMBLE_METRICS=off` and `metrics.enabled: false` as the two opt-out spellings, honoured by **every** subcommand, not only by `start`.
  - *Produces:* `start`'s existing stdout contract unchanged: the ledger path on success, nothing when metrics are disabled.
- **Files:**
  - `skills/en-build/scripts/ensemble-run-metrics`
  - `skills/en-plan/scripts/ensemble-run-metrics`
  - `tests/lint/ensemble-run-metrics.test.sh` (new)
- **Approach:** Add an `emit` subcommand beside the existing `event`, which keeps its explicit file argument so nothing already calling it changes. Factor the current `_append` and the file-argument handling so `emit` resolves its target through a new `_resolve_ledger()` and then reuses the same append. `_resolve_ledger` reads `$ENSEMBLE_RUN_LEDGER` first; failing that it reads `active` bottom-up and returns the first line whose ledger exists and whose `tail -1` is not a `finish` event. `start` prunes dead lines from `active` (rewriting it through a temp file and `mv`, which is atomic), appends a `child` event to the surviving top entry when there is one, records `parent_run_id` in its own `start` line, then appends its own line. `finish` removes the line whose path matches its own file argument rather than simply dropping the last, so a parent finishing after its child is correct. **`active` is run bookkeeping, not analytics, so `finish` maintains it even when metrics are off**: a run begun while recording was enabled and finished after the operator opted out must still leave the stack, or its entry becomes a permanent phantom parent for every later run in the repo. Opt-out is a function, `_metrics_off()`, called by `start`, `emit`, `event` and `finish` rather than by `start` alone: `ENSEMBLE_METRICS=off` short-circuits, otherwise a six-line awk reads a nested `metrics:` / `enabled:` block from `<repo-root>/.ensemble/config.local.yaml`, mirroring `skills/en-sweep/scripts/ensemble-sweep-runner:109-118`. Checking it only at `start` would leave a run begun before the operator opted out still recording afterwards, which is the opposite of what an opt-out means. `ensemble-config-get` is not used: it reads flat top-level keys only (its parser skips any indented line) and `en-build` does not carry it, so pulling it in would add a script to a skill to read one boolean. When metrics are off, `start` prints nothing and creates nothing, `emit` and `event` return 0 having written nothing, and `finish` writes nothing but still pops `active`. The two copies stay byte-identical; `tests/parity/script-parity.test.sh` enforces it.
- **Risk:** medium
- **Category:** observability
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Patterns to follow:** the fail-soft contract already stated in the script's own header ("NEVER BLOCKS A RUN"); `tests/lint/ensemble-unit-verify.test.sh` for the throwaway-repo fixture shape.
- **Test scenarios:**
  - *Happy path:* `start --skill en-build` in a temp repo, then `emit --kind lint --json '{"scope":"docs"}'` from a **different** working directory inside the same repo, with no environment carried over → the event lands in the ledger `start` printed, and `active` holds exactly one line naming it.
  - *Happy path (nesting):* `start --skill en-build`, then `start --skill en-review` → the review ledger's `start` line carries `parent_run_id` equal to the build's run_id, and the build's ledger holds a `child` event whose `ledger` is the review ledger's absolute path. `emit` after both now targets the review ledger.
  - *Happy path (unwinding):* from the state above, `finish <review-ledger>` → `active` has one line left, and the next `emit` targets the build ledger again.
  - *Edge case:* `finish` called on the **parent** while the child is still live → the parent's line is removed by path, the child's line survives, and `emit` still targets the child.
  - *Edge case:* `ENSEMBLE_RUN_LEDGER` set to a path that is not the top of `active` → the event goes to the env-var path, and `active` is not consulted or modified.
  - *Edge case:* `active` holds a line whose ledger file was deleted, and another whose ledger ends in a `finish` event → both are pruned on the next `start`, and an `emit` between the deletion and that `start` is a silent no-op rather than an error.
  - *Edge case (late event):* a ledger holding a `finish` event followed by one more emitted line → still treated as dead, pruned on the next `start`, and not resolved by `emit`. Asserted explicitly, because a last-line test would call it live.
  - *Error / failure path:* `emit` with no run started at all → exit 0, ledger directory not created, nothing on stdout. Assert `[ -z "$(ls $git_dir/ensemble/runs 2>/dev/null)" ]`.
  - *Error / failure path:* `emit --json 'not json'` and `emit --json '[1,2]'` (valid JSON, wrong type) → both exit 0, one stderr line each, ledger byte-unchanged (compare `shasum` before and after).
  - *Error / failure path:* `emit` run from outside any git repository with `ENSEMBLE_RUN_LEDGER` unset → exit 0, no output, no directory created.
  - *Error / failure path:* ledger directory made read-only, then `emit` → exit 0, one stderr line, caller unaffected.
  - *Edge case (opt-out):* `.ensemble/config.local.yaml` containing a `metrics:` block with `enabled: false` → `start` prints nothing and creates no file; a subsequent `emit` is a no-op. Same with `ENSEMBLE_METRICS=off` and no config file. With `enabled: true`, or with a `metrics:` block that omits `enabled`, or with no config file at all, recording is on.
  - *Edge case (opt-out mid-run):* `start` a run, write a ledger event, **then** set `enabled: false`, then call `emit` and `finish` from fresh shells → the ledger is byte-unchanged (`shasum` before and after), no `finish` event is appended, and no rollup line is written. This is the case a `start`-only check would miss.
  - *Edge case (opt-out leaves no phantom parent):* continuing from the scenario above, re-enable metrics and `start` a second run → `active` holds exactly one line, and the new run's `start` records `parent_run_id: null`. Without `finish` popping the stack while opted out, the abandoned run would parent it.
  - *Edge case (concurrency):* twenty `emit` calls backgrounded against one ledger → twenty well-formed lines, each parsing as JSON under `jq -e`.
  - *Integration:* the existing `event <file> --kind ...` form still works unchanged, asserted against the same ledger in the same test.
- **Verification:** `tests/lint/ensemble-run-metrics.test.sh` green on every scenario above; `tests/parity/script-parity.test.sh` green (both copies identical); `bash tests/lint/skill-payload.test.sh` green. Negative control: delete the `_resolve_ledger` fallback to `active` and confirm the cross-directory happy path and the nesting scenarios go red.

### U2. Per-kind key allowlist, enforced at write time

- **Goal:** Only named keys reach disk, and a dropped key is loud in a test run and countable in the rollup.
- **Requirements covered:** none; the design's "Privacy enforcement" row.
- **Dependencies:** U1
- **Interfaces:**
  - *Produces:* the allowlist, one set per kind. `select`: `tier, reason, count, total`. `verify`: `unit, tier, ran, failed, rc, checks`. `receipt`: `op, result, reason, age_s, checks`. `peer`: `peer, decision, reason, peer_mode, effort, model_alias, model_actual, elapsed_s`. `outcome`: `result, verdict, findings_total, peer_only, corroborated, host_only, applied, deferred, disagreed, units_total, units_done, gates_failed`. `child`: `run_id, skill, ledger`. The nine pre-existing kinds (`dispatch`, `peer` as already used, `lint`, `findings`, `unit`, `phase`, `suite`, `review`, `note`) keep an explicitly-named set derived from what `references/run-metrics.md` documents today, so no currently-recorded field starts being dropped.
  - *Produces:* `emit`'s drop behaviour: unknown keys are removed from the payload, the surviving object is written, and one stderr line per call names the dropped keys. A `dropped` count is added to the written line when any key was dropped.
- **Files:**
  - `skills/en-build/scripts/ensemble-run-metrics`
  - `skills/en-plan/scripts/ensemble-run-metrics`
  - `tests/lint/ensemble-run-metrics.test.sh`
- **Approach:** A single `jq` filter does the intersection: the allowlist is a `kind -> [keys]` object built inline in the script, and the payload is reduced with `with_entries(select(.key as $k | $allowed | index($k)))`. Count the difference in key counts to decide whether to add `dropped` and what to print. The `outcome` kind uses one shared set rather than a per-skill schema, because one skill emits it in this tranche and a table with one row is a table to maintain rather than a guard. This is the design's own reasoning and is recorded as a decision below, with the revisit trigger named. An unknown **kind** stays a rejection rather than a drop: the existing `case` already refuses one and prints a line.
- **Risk:** medium
- **Category:** observability
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* `emit --kind select --json '{"tier":"graph","count":4,"total":260}'` → all three keys present in the line, no `dropped` field, nothing on stderr.
  - *Happy path:* `emit --kind peer --json '{...all eight allowed keys...}'` → all eight survive.
  - *Edge case:* a payload mixing allowed and unknown keys, `{"tier":"graph","cwd":"/Users/someone/secret-project"}` → the written line holds `tier` and not `cwd`, carries `"dropped":1`, and stderr names `cwd`.
  - *Edge case:* a payload of only unknown keys → the line is still written with its `kind` and `at`, `dropped` equals the key count, and the caller still gets exit 0.
  - *Edge case:* an empty object `{}` → written, no `dropped` field.
  - *Error / failure path:* `emit --kind nonsense --json '{}'` → rejected as today, exit 0, ledger unchanged.
  - *Integration:* every one of the nine pre-existing kinds emitted with the exact payload shape `references/run-metrics.md` documents → nothing is dropped, asserted kind by kind, so this unit cannot silently break what `/en-build` and `/en-plan` already record.
- **Verification:** the scenarios above green; `grep -c dropped` on a ledger from a clean run is 0. Negative control: add a key to the `select` payload in the test without adding it to the allowlist and confirm the "no `dropped` field" assertion goes red.

### U3. Durable rollup on `finish`, with size-cap rotation

- **Goal:** Every finished run leaves one summary line in `~/.ensemble/analytics/<repo>.jsonl`, the file cannot grow without bound, and no test run can touch the operator's copy.
- **Requirements covered:** none; the design's "Durable rollup" row.
- **Dependencies:** U2
- **Interfaces:**
  - *Produces:* the rollup line. `{"schema":1,"skill":…,"run_id":…,"plan_id":…|null,"repo":…,"parent_run_id":…|null,"started_at":…,"ended_at":…,"duration_s":<int>,"counts":{<kind>:<int>,…},"outcome":{…}|null,"detail":{"select":{"tier":…,"count":…,"total":…}|null,"peer":[{"peer":…,"decision":…,"elapsed_s":…},…]},"dropped":<int>}`.
  - *Produces:* `ENSEMBLE_ANALYTICS_DIR`, defaulting to `$HOME/.ensemble/analytics`, matching the spelling `skills/en-guardrail/bin/check-guardrail.sh` already uses.
  - *Produces:* rotation: before appending, if `<repo>.jsonl` is at or over 5 MB it is renamed to `<repo>.jsonl.1`, replacing any previous `.1`. Exactly one previous generation is kept; the ceiling is about 10 MB and never grows. The rename is serialized by a `mkdir` lock held **only across the rotation**, never across the append.
- **Files:**
  - `skills/en-build/scripts/ensemble-run-metrics`
  - `skills/en-plan/scripts/ensemble-run-metrics`
  - `tests/lint/ensemble-run-metrics.test.sh`
  - `tests/lint/analytics-isolation.test.sh`
- **Approach:** `finish` reads its own ledger once through `jq -s`, derives the counts, the first `start` line's fields, the `outcome` object when one was emitted, and the `detail` aggregates, then appends a single line. **The rollup is published before the `finish` event is appended, not after.** Order matters because the ledger dies with the clone: if `finish` closed the ledger first and the rollup write then failed, that run's only durable record would be gone with no way to notice or retry. Publishing first means a failed rollup leaves the ledger open, so the next `finish` call retries it, and the retry is safe because publication is idempotent on `run_id`: `finish` greps **every retained generation**, `<repo>.jsonl` and `<repo>.jsonl.1`, for its own `run_id` and appends nothing if it is already there. Scanning only the current file would re-append a run whose line had just been rotated out. `repo` is `basename $(git rev-parse --show-toplevel)`, the same derivation `check-guardrail.sh` uses, so the two files in the directory agree on what names a repo. Size is read with `wc -c` and compared numerically. **The rename is serialized**, because an unsynchronized one loses a whole generation: two `finish` calls both seeing the file over the cap would each `mv` it to `.1`, and the second rename overwrites the first's `.1` with a file holding one line, destroying 5 MB of history. `mkdir "$dir/.rotate.lock"` is the mutex, held across the size check and the `mv` and nothing else. **Losing the lock never drops an event**: a caller that cannot take it skips rotation entirely and appends to whatever `<repo>.jsonl` currently is, so the file briefly exceeds the cap and the next run rotates it. That is the difference from the lock PR #106 removed, which dropped the event outright after five seconds of contention; this one can only defer a rename. The append itself takes no lock at all. Every failure here is swallowed the way the rest of the script swallows failures: an unwritable analytics directory costs one stderr line and the ledger is still complete. Widen the isolation guard's second loop past `tests/en-guardrail/` so it also covers any suite that drives `ensemble-run-metrics finish`; its first loop already discovers the new writer by grep and will demand `ENSEMBLE_ANALYTICS_DIR` without being told to.
- **Risk:** medium
- **Category:** observability
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Patterns to follow:** `skills/en-guardrail/bin/check-guardrail.sh:48-58` for the override spelling and the swallow-everything write.
- **Test scenarios:**
  - *Happy path:* a run with one `select`, two `peer` and one `outcome` event, then `finish`, with `ENSEMBLE_ANALYTICS_DIR` pointed at a temp dir → exactly one line in `<repo>.jsonl`; `counts.peer` is 2; `detail.peer` has two entries in emit order; `detail.select.tier` matches what was emitted; `outcome` is present verbatim; `duration_s` is a non-negative integer.
  - *Happy path:* a nested pair finished child-then-parent → two lines, and the child's `parent_run_id` matches the parent's `run_id`.
  - *Edge case:* a run with no `outcome` event → `outcome` is `null`, not absent, so a reader can distinguish "no outcome" from "old schema".
  - *Edge case:* a run with no `select` event → `detail.select` is `null` and `detail.peer` is `[]`.
  - *Edge case (rotation):* seed `<repo>.jsonl` with 5 MB of filler, then `finish` → the seeded content is now in `<repo>.jsonl.1` and `<repo>.jsonl` holds exactly the one new line. Run `finish` again with a second 5 MB seed → `.1` holds the second generation and the first is gone, with no `.2` created.
  - *Edge case:* `finish` called twice on the same ledger → the second call appends no second rollup line, because the ledger already holds a `finish` event.
  - *Error / failure path (retry):* make the analytics directory read-only, call `finish` → no rollup line, no `finish` event in the ledger, the `active` entry still present, exit 0. Make it writable, call `finish` again → exactly one rollup line and one `finish` event, and `active` is now empty.
  - *Edge case (idempotence):* seed the rollup with a line already carrying this run's `run_id`, then `finish` → no duplicate line is appended, and the `finish` event is still written.
  - *Edge case (idempotence across generations):* seed `<repo>.jsonl.1` (not the current file) with a line carrying this run's `run_id`, then `finish` → still no duplicate, which a current-file-only scan would miss.
  - *Edge case (concurrent rotation):* ten `finish` calls backgrounded against a rollup seeded one byte over the 5 MB cap → reading `<repo>.jsonl` and `<repo>.jsonl.1` together yields all ten `run_id`s exactly once **and** the seeded history is still present in one of the two files. The second half is the assertion that fails without the rotation lock.
  - *Edge case (lock contention):* hold `.rotate.lock` from outside, then `finish` against an over-cap file → no rotation happens, the line is appended to the over-cap file, exit 0, and nothing is dropped.
  - *Error / failure path:* `ENSEMBLE_ANALYTICS_DIR` pointing at a read-only directory → `finish` exits 0 and writes one stderr line, and **the ledger is left open**: no `finish` event, no rollup line, and the `active` entry stays. This is the single contract for an unwritable store, and it is what makes the retry below possible. A run whose rollup never succeeds is a run that never closed, which is the honest record.
  - *Error / failure path:* a ledger whose `start` line is malformed → no rollup line can be derived, so `finish` exits 0, writes one stderr line, and **does** append the `finish` event and pop `active`, because retrying a ledger that will never parse would leave the entry stale forever. A malformed ledger is unrecoverable; an unwritable directory is not, and the two paths differ for exactly that reason.
  - *Integration:* run the **full** `./tests/run.sh` with the operator's real `~/.ensemble/analytics/` line-counted before and after → both counts identical, for `guardrail.jsonl` and for any `<repo>.jsonl`. This is the same check that proved PR #108.
- **Verification:** scenarios green; `tests/lint/analytics-isolation.test.sh` green with the run-metrics writer now in its discovered set. Negative controls, run and recorded: (a) hardcode `$HOME/.ensemble/analytics` in place of the override and confirm the guard's first assertion goes red; (b) remove `ENSEMBLE_ANALYTICS_DIR` from the new suite and confirm the widened second loop goes red; (c) remove the size comparison and confirm the rotation scenario goes red; (d) append the `finish` event before publishing the rollup and confirm the retry scenario goes red; (e) remove the `mkdir` lock around the rename and confirm the concurrent-rotation scenario's history assertion goes red; (f) scan only `<repo>.jsonl` for the `run_id` and confirm the across-generations idempotence scenario goes red.

### U12. Every instrumented skill opens and closes its own run

- **Goal:** A standalone `/en-ship`, `/en-review` or `/en-foundation` run has a ledger of its own, so its helpers' events are recorded and attributed to it rather than dropped or folded into somebody else's run.
- **Requirements covered:** none; the design's "every skill run is a first-class unit".
- **Dependencies:** U3
- **Interfaces:**
  - *Consumes:* `ensemble-run-metrics start --skill <name>` and `finish <ledger>` (U1, U3).
- **Files:**
  - `skills/en-ship/SKILL.md`
  - `skills/en-review/SKILL.md`
  - `skills/en-foundation/SKILL.md`
  - `skills/en-ship/scripts/ensemble-run-metrics` (new carrier if U4 has not yet added it)
  - `skills/en-review/scripts/ensemble-run-metrics` (new carrier if U6 has not yet added it)
  - `skills/en-foundation/scripts/ensemble-run-metrics` (new carrier if U7 has not yet added it)
  - `tests/lint/skill-run-lifecycle.test.sh` (new)
- **Approach:** `/en-build` and `/en-plan` already call `start` and `finish`; the three skills that gain emitters do not, and without the pair their helpers resolve no ledger and record nothing. This is the gap that would have made U4 through U7 look implemented and produce no data for any skill but `en-build`. Each of the three gets the same two lines `/en-build` carries: `start --skill <name>` before its first measured operation, and `finish` in its reporting step. **"Finish on every terminal path" is not statically verifiable, and the built lint does not claim to verify it.** A failure-protocol table is prose, and deciding whether one of its rows reaches a reporting step needs a reader, not a grep. The contract is stated once in the shared reference and each carrier is checked for a citation of it, which is what a model following the skill can actually reach. That stops the contract being dropped silently; it does not prove the model obeys, and the lint's own header says so. The nesting the design describes then works without anyone writing it: `/en-build` invoking `/en-review`, and `/en-ship` invoking `/en-resolve-pr`, each get a child ledger and a parent pointer from `start` alone. The guard is a lint over the skill bodies, because these are prose steps the model executes: for every skill carrying `ensemble-run-metrics`, assert a `start --skill <that skill>` call under the skill's own name, exactly one `finish` call site, and a citation of the reference that states the contract. The subject list is the carrier set, so a sixth carrier is covered by the commit that adds it.
- **Risk:** medium
- **Category:** observability
- **Reversibility:** trivial
- **Gated:** false
- **Ship scope:** in
- **Execution note:** pragmatic
- **Patterns to follow:** `skills/en-build/SKILL.md:38` for the exact `start` call shape; `tests/lib/assert.sh:132-140` (`assert_reached`).
- **Test scenarios:**
  - *Happy path:* the lint finds a `start --skill en-ship` and a `finish` in `skills/en-ship/SKILL.md`, both reachable from the flow. Same for `en-review` and `en-foundation`.
  - *Happy path:* the skill named in each `start --skill <name>` matches the directory the SKILL.md lives in, so a copied line cannot silently record `en-build` from inside `en-ship`.
  - *Edge case:* the lint is driven by which skills carry `ensemble-run-metrics`, not by a hardcoded list, so a sixth carrier added later is covered without editing the test.
  - *Edge case (standalone attribution):* scripted in a temp repo, `start --skill en-ship`, a `select` emit, `finish` → one rollup line whose `skill` is `en-ship` and whose `parent_run_id` is null.
  - *Edge case (nested attribution):* `start --skill en-build`, `start --skill en-review`, an emit, `finish` the review, another emit, `finish` the build → two rollup lines; the review's `parent_run_id` is the build's `run_id`; the review's emit is counted in the review's line and the build's emit in the build's, with no double counting.
  - *Error / failure path:* a skill body carrying `start` with no `finish` anywhere → the lint fails, naming the skill. Same for a `finish` with no `start`.
  - *Error / failure path (fixtures):* four synthetic skill bodies, one per property: no `finish`, no citation of the contract reference, a `start` naming another skill, and a well-formed one that passes. Each must be rejected or accepted as named.
  - *Error / failure path (abandoned run):* a ledger started and never finished, then a second `start` in the same repo → the second run records `parent_run_id: null` once the first is pruned, and `bin/ensemble-metrics --time` excludes the unfinished run rather than reporting it with a null duration.
  - *Integration:* after this unit, a scripted `/en-ship`-shaped sequence (start, test-select emit, receipt emit, finish) produces a rollup line whose `counts` hold both events, which is the end-to-end proof that U4 and U6 record for a skill other than `en-build`.
- **Verification:** the new lint green on every carrier; `tests/lint/skill-size.test.sh` green with `BASELINE` still empty; `tests/parity/script-parity.test.sh` green across all `ensemble-run-metrics` copies. Negative controls: delete the `finish` line from `skills/en-ship/SKILL.md` and confirm the lint goes red naming `en-ship`; change one `start --skill` to the wrong skill name and confirm the matching assertion goes red; strip the contract sentence from the shared reference and confirm the single contract assertion goes red.

### U4. `ensemble-test-select` records the tier it chose

- **Goal:** Every selection decision is on disk, so "did test selection actually narrow anything" stops being a guess.
- **Requirements covered:** none; the design's Phase 2 tranche.
- **Dependencies:** U12
- **Interfaces:**
  - *Consumes:* `ensemble-run-metrics emit --kind select --json '{"tier":…,"reason":…,"count":…,"total":…}'` (U1, U2).
- **Files:**
  - `skills/en-build/scripts/ensemble-test-select`
  - `skills/en-ship/scripts/ensemble-test-select`
  - `skills/en-ship/scripts/ensemble-run-metrics` (new carrier, byte-identical copy)
  - `tests/lint/ensemble-unit-verify.test.sh`
- **Approach:** One call inside `emit()`, the script's single terminal function, immediately before its `exit 0`, so all seven call sites are covered by one edit and a new tier added later records without a second change. Guard it with `[ -x "$_self_dir/ensemble-run-metrics" ]` so a carrier missing the sibling degrades to silence rather than an error; `_self_dir` is resolved the way the script already resolves its own directory. `en-ship` gains a byte-identical copy of `ensemble-run-metrics`, which is also what makes it reachable for `tests/lint/skill-payload.test.sh`: the lint follows a script's reference to a sibling script, proved by its own `sibling` fixture at `tests/lint/skill-payload.test.sh:91-92`.
- **Risk:** medium
- **Category:** observability
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* inside a started run, a change touching one source file with a sibling test → one `select` event whose `tier` matches the `TEST_SELECT_TIER` the script printed on stdout, and whose `count`/`total` match `TEST_SELECT_COUNT`/`TEST_SELECT_TOTAL`. The stdout contract is asserted byte-identical to the pre-change output, so nothing that `eval`s it can break.
  - *Happy path:* a change forcing `full-suite` → one `select` event with that tier and the reason string the script emitted.
  - *Edge case:* the `empty` and `none-declared` tiers → still one event each; a tier that selects nothing is exactly the case worth recording.
  - *Error / failure path:* no run started → the script behaves identically, stdout byte-for-byte the same, and no ledger directory is created.
  - *Error / failure path:* `ensemble-run-metrics` absent from the carrier directory → script still exits 0 with the same stdout, nothing on stderr.
  - *Integration:* `ensemble-unit-verify`, which sources this script's output through `eval`, still parses every field after the change; the existing `val()` assertions in `tests/lint/ensemble-unit-verify.test.sh` pass unmodified.
- **Verification:** scenarios green; `tests/parity/script-parity.test.sh` green across both `ensemble-test-select` copies and now three `ensemble-run-metrics` copies; `tests/lint/skill-payload.test.sh` green. Negative control: point the guard at a non-existent sibling and confirm the happy-path event assertion goes red while the stdout assertion stays green.

### U5. `ensemble-unit-verify` records what it verified and what failed

- **Goal:** Per-unit verification cost and outcome are on disk, which is the raw material for "how long does a unit actually take".
- **Requirements covered:** none; the design's Phase 2 tranche.
- **Dependencies:** U12
- **Interfaces:**
  - *Consumes:* `ensemble-run-metrics emit --kind verify --json '{"unit":…,"tier":…,"ran":…,"failed":…,"rc":…,"checks":…}'` (U1, U2).
- **Files:**
  - `skills/en-build/scripts/ensemble-unit-verify`
  - `tests/lint/ensemble-unit-verify.test.sh`
- **Approach:** One call in the terminal block that follows the three `run_check` calls, placed so it runs on all four exit codes (0 success, 1 a check failed, 3 empty tier, 4 nothing verifiable) rather than only on success. The script has no verify-wide clock, only per-check timings inside `run_check`; rather than add one, `checks` carries the per-check strings already built into `$LINES`, normalised to `{"label":…,"status":"pass"|"fail","seconds":<int>}`, which preserves the timing the script already measured and costs no new instrumentation. `rc` is the exit code the script is about to return, captured into a variable before the emit so the emit cannot change it. `en-build` already carries `ensemble-run-metrics`, so no new carrier here.
- **Risk:** medium
- **Category:** observability
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* a unit whose lint, typecheck and tests all pass → one `verify` event with `rc` 0, `failed` 0, `ran` 3, and three `checks` entries each carrying a non-negative `seconds`.
  - *Error / failure path:* a fixture whose test command exits 1 → exactly one `verify` event, `rc` 1, `failed` 1, and the failing check's entry has `"status":"fail"`. Assert the script still exits 1: the emit must not swallow the failure.
  - *Edge case:* `--no-lint --no-typecheck --no-tests` → the nothing-verifiable path, `rc` 4, one event, `ran` 0.
  - *Edge case:* the `empty` test tier → `rc` 3, one event, `tier` recorded as `empty`.
  - *Edge case:* a usage error (`--unit` omitted) → exit 2 and **no** event, because nothing was verified and a usage error is not a measurement.
  - *Error / failure path:* no run started → identical exit codes and identical stdout on all four terminal paths, no ledger created.
  - *Integration:* the `tier` recorded here equals the tier the `select` event from U4 recorded in the same run, asserted by reading both events from one ledger.
- **Verification:** scenarios green, with the exit-code assertions checked on every path. Negative control: move the emit call inside the `exit 0` branch only and confirm the three failure-path scenarios go red.

### U6. `ensemble-verification-receipt` records writes and verdicts

- **Goal:** Receipt hits and misses are countable, so the question the receipt exists to answer ("did we skip a suite we had already run") has evidence behind it.
- **Requirements covered:** none; the design's Phase 2 tranche.
- **Dependencies:** U12
- **Interfaces:**
  - *Consumes:* `ensemble-run-metrics emit --kind receipt --json '{"op":"write"|"verify","result":…,"reason":…,"age_s":…,"checks":…}'` (U1, U2).
- **Files:**
  - `skills/en-build/scripts/ensemble-verification-receipt`
  - `skills/en-review/scripts/ensemble-verification-receipt`
  - `skills/en-ship/scripts/ensemble-verification-receipt`
  - `skills/en-review/scripts/ensemble-run-metrics` (new carrier, byte-identical copy)
  - `skills/en-ship/scripts/ensemble-run-metrics` (present after U4; copy it here if U4 has not run)
  - `tests/verification-receipt/receipt.test.sh`
- **Approach:** Two call sites, one per subcommand, both in shell rather than inside the embedded Python, so the emit stays in one language and the Python block keeps its single `out()` exit. `write` emits after "receipt written" with `op: "write"`, `result: "ok"` and the recorded check names. `verify` emits after the Python block returns, reading the reason from the `--json` output the block already produces and the exit status from `$?` captured immediately; `result` is `hit` on exit 0 and `miss` otherwise, and `reason` carries the existing enum verbatim (`ok`, `fingerprint-mismatch`, `base-moved`, `dependency-changed`, `expired`, `check-not-recorded`, `wrong-repo`, `malformed`, `no-receipt`). `show` does not emit: it reads and prints, and measuring a read of a read is noise. The status capture is the delicate part, because `cmd_verify`'s exit code is the contract `/en-build` and `/en-ship` branch on; capture `rc=$?` on the line after the call and return `$rc` explicitly, so no emit can sit between the Python and the status read.
- **Risk:** medium
- **Category:** observability
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* `write --check unit=passed --check full_suite=passed` inside a run → one `receipt` event, `op` `write`, `checks` naming both.
  - *Happy path:* `verify --requires full_suite` against that receipt on an unchanged tree → one event, `op` `verify`, `result` `hit`, `reason` `ok`, `age_s` a non-negative integer, and the script still exits 0.
  - *Error / failure path:* `verify` after touching a dependency → `result` `miss`, `reason` `dependency-changed`, and the script still exits 1. Repeat for `base-moved` (move the base ref) and `expired` (`--ttl 0`), asserting the exit code each time.
  - *Edge case:* `verify` with no receipt present → one event with `reason` `no-receipt`, and the script still exits 2. The distinct exit code is what `/en-build` reads, so it is asserted separately from the 1 case.
  - *Edge case:* `show` → no event emitted at all.
  - *Error / failure path:* no run started → all of the above exit codes and stdout are byte-identical to the pre-change script, asserted by capturing both before and after.
  - *Integration:* a `write` then a `verify` in one run → two events in emit order in one ledger, and `counts.receipt` in the U3 rollup line is 2.
- **Verification:** scenarios green with every exit code asserted; `tests/parity/script-parity.test.sh` green across all three receipt copies. Negative control: drop the `rc=$?` capture so the emit's status leaks through, and confirm the `dependency-changed`, `no-receipt` and `expired` exit-code assertions go red.

### U7. `ensemble-peer-invoke` records the peer decision and its elapsed time

- **Goal:** Every peer pass leaves its decision, its reason, the model actually served and its wall-clock cost, which is half of what the parked peer-value question needs.
- **Requirements covered:** none; the design's Phase 2 tranche.
- **Dependencies:** U12
- **Interfaces:**
  - *Consumes:* `ensemble-run-metrics emit --kind peer --json '{"peer":…,"decision":…,"reason":…,"peer_mode":…,"effort":…,"model_alias":…,"model_actual":…,"elapsed_s":…}'` (U1, U2).
- **Files:**
  - `skills/en-plan/scripts/ensemble-peer-invoke`
  - `skills/en-review/scripts/ensemble-peer-invoke`
  - `skills/en-foundation/scripts/ensemble-peer-invoke`
  - `skills/en-foundation/scripts/ensemble-run-metrics` (new carrier, byte-identical copy)
  - `skills/en-review/scripts/ensemble-run-metrics` (present after U6; copy it here if U6 has not run)
  - `tests/lint/ensemble-peer-invoke.test.sh` or the existing peer-invoke suite
- **Approach:** One call inside `_epi_decision`, which the script's own comment already calls "the terminal event" and which every one of `ensemble_peer_invoke`'s return paths passes through. All seven values are already its arguments, including the elapsed seconds each call site computes inline, so the emit composes them and adds nothing. This is a sourced library, not an executed script, so the sibling path resolves from the directory the library itself was sourced from rather than from `$0`; capture it once at source time into a private variable alongside the other `_epi_` state, because `$0` inside a sourced file is the caller. The recursion guard matters here: when `ENSEMBLE_PEER_REVIEW=true` the peer subprocess is running its own skill, and nothing in this unit changes that, so a peer's own helper calls resolve against whatever ledger that subprocess has, which is none. That keeps a peer pass counted once, by the host.
- **Risk:** medium
- **Category:** observability
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* a stubbed peer CLI returning well-formed JSON → one `peer` event, `decision` `on`, `elapsed_s` a non-negative integer, `model_actual` matching what the stub reported.
  - *Error / failure path:* a stub that sleeps past the timeout → one event with `decision` `off` and `reason` `peer-failed:timeout`, and `ensemble_peer_invoke` returns the same non-zero status it returned before the change.
  - *Error / failure path:* a stub exiting on an auth error → one event, `reason` `peer-failed:auth`, unchanged return status.
  - *Edge case:* the degraded path (a dropped model fragment) → `decision` `degraded` and `reason` `dropped-model-fragment`.
  - *Edge case:* two peer passes in one run (the finalize loop) → two events in one ledger, both with their own `elapsed_s`, and `counts.peer` is 2 in the rollup.
  - *Edge case:* the detached form (`ensemble_peer_start` then `ensemble_peer_wait` then `ensemble_peer_result`) → still exactly one event, because it also funnels through `_epi_decision`, not two.
  - *Error / failure path:* no run started → every return status and every stdout byte identical to the pre-change library, asserted across the happy path and the timeout path.
  - *Integration:* invoked from a skill directory that carries `ensemble-peer-invoke` but not `ensemble-run-metrics` → no error, no event, unchanged behaviour.
- **Verification:** scenarios green; `tests/parity/script-parity.test.sh` green across all three peer-invoke copies; the existing peer-invoke and peer-run-marker suites green unmodified. Negative control: resolve the sibling path from `$0` instead of the captured source directory and confirm the happy-path event assertion goes red when the library is sourced from a different working directory.

### U8. `/en-review` emits the outcome event that makes peer value answerable

- **Goal:** The corroboration split, which no helper can observe, reaches the ledger from the one place that computes it.
- **Requirements covered:** none; the design's "one `/en-review` outcome event".
- **Dependencies:** U6, U9, U12
- **Interfaces:**
  - *Consumes:* `ensemble-run-metrics emit --kind outcome --json '{"result":…,"verdict":…,"findings_total":…,"peer_only":…,"corroborated":…,"host_only":…,"applied":…,"deferred":…,"disagreed":…}'` (U1, U2).
- **Files:**
  - `skills/en-review/SKILL.md`
  - `skills/en-review/references/run-metrics.md` (new carrier, byte-identical copy of the version current when this unit runs; U10 later rewrites all three copies together)
  - `tests/lint/en-review-outcome-event.test.sh` (new)
- **Approach:** One step added to `/en-review` immediately after reconciliation, where the corroboration buckets are already computed and named, calling `emit --kind outcome` with the counts it just produced. This is the deliberate exception to "the helper records, not the model": the buckets exist only in the reconciliation the model performs, and `ensemble-peer-invoke` provably cannot see them (it contains no reference to corroboration). Everything else `/en-review` records stays helper-emitted. `en-review` gains the `run-metrics.md` reference so the call point is documented where the skill can read it. The `start`/`finish` pair that gives a standalone review a ledger belongs to U12, which this unit depends on, so the outcome event has somewhere to land the first time it fires. The guard is a lint over the skill body, not a behavioural test, because the emitter here is prose the model executes: assert the call point exists, sits after the reconciliation step and not before it, and names only allowlisted keys. That last assertion is what stops the skill and the allowlist drifting apart, which is the failure mode a write-time drop makes silent.
- **Risk:** medium
- **Category:** observability
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** pragmatic
- **Patterns to follow:** `tests/lib/assert.sh:132-140` (`assert_reached`) for asserting a step is reachable from the skill's own flow rather than merely present in the file.
- **Test scenarios:**
  - *Happy path:* the lint finds the `outcome` emit call in `skills/en-review/SKILL.md` and confirms its step number is greater than the reconciliation step's.
  - *Happy path:* every key named in that call appears in the `outcome` allowlist in `ensemble-run-metrics`, compared by parsing both rather than by a fixed list, so adding a key to one without the other fails.
  - *Edge case:* the call site is reachable from the skill's flow per `assert_reached`, not merely present somewhere in the file.
  - *Error / failure path:* `en-review` carries `ensemble-run-metrics` and `references/run-metrics.md`, asserted so the payload lint's both-directions check cannot be satisfied by a dangling mention.
  - *Integration:* a scripted end-to-end run in a temp repo carrying the whole chain, `start --skill en-review`, a `peer` emit, an `outcome` emit composed from a known reconciliation (9 findings: 3 peer-only, 4 corroborated, 2 host-only) using the exact key names the SKILL.md call uses, then `finish` → the rollup line carries those three counts under `outcome`, `counts.outcome` is 1, and `bin/ensemble-metrics --peer-value` over that store reports the 3/4/2 split for the run. Asserting through the report is what proves the whole path, since a key that survives the allowlist but is named differently from what the report reads would otherwise pass every earlier assertion.
- **Verification:** the new lint green with all five assertions; `tests/lint/skill-size.test.sh` still green for `en-review` (the addition is small, and the BASELINE list is empty and must stay empty); `tests/parity/reference-parity.test.sh` green across the now-three `run-metrics.md` copies. Negative control: rename one key in the SKILL.md call and confirm the allowlist cross-check goes red; move the call above reconciliation and confirm the ordering assertion goes red.

### U9. `bin/ensemble-metrics` with three named reports

- **Goal:** The collected data answers the three questions it was collected for, without anyone writing jq.
- **Requirements covered:** none; the design's "Report surface" row.
- **Dependencies:** U3
- **Interfaces:**
  - *Consumes:* the rollup line schema (U3).
  - *Produces:* `bin/ensemble-metrics [--peer-value|--time|--selection] [--repo <name>] [--analytics-dir <path>] [--json]`. Exit 0 with a "no data yet" line when the store is empty or absent; exit 2 on an unknown flag.
- **Files:**
  - `bin/ensemble-metrics` (new)
  - `tests/lint/ensemble-metrics-report.test.sh` (new)
  - `AGENTS.md`
- **Approach:** A Python script beside `bin/ensemble-lint`, reading `<repo>.jsonl` and `<repo>.jsonl.1` together so a rotation does not truncate a report's history, and skipping unparseable lines rather than failing on them. `--repo` defaults to the current repo's basename. `--peer-value` reports the **distribution**, not a ratio: per run, the peer-only / corroborated / host-only counts, then a histogram of peer-only findings per run and the count of runs where the peer found nothing. The design's devil's advocate is explicit that a single averaged ratio misleads, because a peer that finds nothing on easy diffs and everything on hard ones averages to mediocre, so the single-number form is deliberately not offered. `--time` reports per skill: run count, median, p90 and max `duration_s`, and the per-kind event counts. `--selection` reports the `select` tier distribution and the `count`/`total` ratio per tier, so "did selection narrow anything" has an answer. Each report prints a one-line note when fewer than five runs back it, because a p90 over three runs is not a p90. Statistics use the standard library only; the repo takes on no dependency for this.
- **Risk:** medium
- **Category:** diagnostics
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* a fixture store of twelve runs across three skills → `--time` prints one row per skill with counts summing to 12, and the median for a skill with known durations equals the hand-computed value.
  - *Happy path:* a fixture with known corroboration splits → `--peer-value` prints one row per run plus a histogram whose buckets sum to the run count, and names the number of runs where `peer_only` was 0.
  - *Happy path:* a fixture spanning tiers → `--selection` prints each tier with its run count and its mean `count`/`total` ratio.
  - *Edge case:* a store where `<repo>.jsonl.1` exists → lines from both files are counted exactly once, asserted by a total that only matches if both were read and neither twice.
  - *Edge case:* runs with `outcome: null` → `--peer-value` excludes them from the distribution and says how many it excluded, rather than counting them as zeroes.
  - *Edge case:* fewer than five runs → the small-sample note is printed; at five or more it is not.
  - *Error / failure path:* an absent analytics directory, and an empty file → exit 0 with "no data yet", no traceback.
  - *Error / failure path:* a store with a truncated final line and a line of plain text → both skipped, the valid lines still reported, and the skipped count stated.
  - *Error / failure path:* an unknown flag → exit 2 and a usage line.
  - *Integration:* `--json` on each of the three reports emits parseable JSON, asserted with `jq -e`, so the reports are usable by something other than a human.
- **Verification:** scenarios green against fixture stores under a temp `--analytics-dir`, never the operator's; `tests/lint/analytics-isolation.test.sh` green (the reports read and never write, so nothing new is discovered as a writer). Negative control: read only `<repo>.jsonl` and confirm the rotation scenario goes red.

### U10. Config key, reference doc, and the decision record

- **Goal:** The event vocabulary, the opt-out and the reports are documented where the people and the skills that need them will look.
- **Requirements covered:** none.
- **Dependencies:** U8, U9, U12
- **Files:**
  - `.ensemble/config.local.example.yaml`
  - `skills/en-setup/references/templates/config-local-example.yaml`
  - `skills/en-plan/references/run-metrics.md`
  - `skills/en-build/references/run-metrics.md`
  - `skills/en-review/references/run-metrics.md`
  - `skills/en-ship/references/run-metrics.md`
  - `skills/en-foundation/references/run-metrics.md`
  - `docs/foundation.md`
  - `AGENTS.md`
- **Approach:** Add a `metrics:` block to both config examples with `enabled: true` and a comment naming what recording covers and where it lands, following the `sweep:` block's shape. Rewrite `run-metrics.md` around what is now true: the ledger, the `active` file and the resolution order; the full event table, kind by kind, with each kind's allowed keys, since that table is the contract U2 enforces and the only place a reader can learn what a field means; the rollup line's schema; the three reports; the two opt-out spellings; and the two overrides that exist for tests. Delete the model-emitted call-point tables for the kinds that are now helper-emitted, and keep the `/en-build` table for the kinds that genuinely remain the model's to record. Add the lifecycle contract U12 introduces: which skills open a run, where `finish` goes, and what a missing `finish` costs. Every skill that carries `ensemble-run-metrics` carries this reference, which after U12 is five: en-build, en-plan, en-review, en-ship and en-foundation. All five copies stay byte-identical, enforced by `tests/parity/reference-parity.test.sh`. Record the decision in `docs/foundation.md` as D117: helpers record, the ledger is addressed through a file on disk rather than an environment variable, and the reason.
- **Risk:** medium
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Ship scope:** in
- **Execution note:** pragmatic
- **Test expectation:** none — documentation and config defaults, covered by the parity and lint suites the other units already run, plus the opt-out behaviour asserted in U1.
- **Verification:** `tests/parity/reference-parity.test.sh` green across all three copies; `bin/ensemble-lint` clean; the `metrics:` block present and identical in both config examples; every kind named in the U2 allowlist appears in the reference table and no kind appears that the allowlist does not carry, checked by grep.

### U11. `/en-setup` reports an oversized analytics store

- **Goal:** An operator whose analytics store has grown large finds out on the path they already run, is told what each oversized file actually holds, and decides for themselves what to do about it.
- **Requirements covered:** none.
- **Dependencies:** none
- **Files:**
  - `skills/en-setup/scripts/check-health`
  - `skills/en-setup/references/setup-verification.md`
  - `tests/en-setup/analytics-store-advisory.test.sh` (new)
- **Approach:** The check lives in `scripts/check-health`, which step 15 already delegates its advisory checks to, so `SKILL.md` is untouched: it has 52 bytes of budget left, and D116's lesson is that a mechanical sequence in prose drifts while a script does not. One advisory line for each file under the analytics directory at or over 5 MB, naming the file, its size, its line count and **what that file holds**. The classification is the point, and it is why the line says nothing about deleting. `guardrail.jsonl` is a hook-fire log that nothing reads back and that PR #108 established was 97% test noise, so the advisory says it is a log of hook fires and that removing it loses only that history. `<repo>.jsonl` is the durable rollup and the **only** surviving record of runs whose per-clone ledgers are gone, so the advisory says exactly that, notes that nothing else holds the data, and points at `bin/ensemble-metrics --json` as the way to export before removing anything. An unrecognised file gets its size and a plain "unrecognised, left alone". Calling any of this "safe to delete" would be wrong for the rollup and presumptuous for the rest. Advisory only: it does not fail verification, does not prompt, and never deletes. The check honours `ENSEMBLE_ANALYTICS_DIR` like every other reader, which is what lets the test assert it against a fixture rather than against the operator's real 8.6 MB file.
- **Risk:** low
- **Category:** diagnostics
- **Reversibility:** trivial
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* a fixture analytics dir holding a 6 MB `guardrail.jsonl` → verification prints the advisory naming the file, its size, its line count and its classification as a hook-fire log, still reports success, and the output does **not** contain the words "safe to delete".
  - *Happy path:* a fixture holding a 6 MB `<repo>.jsonl` → the advisory classifies it as the durable rollup, says no other copy of the data exists, and names the export command. Asserted separately from the guardrail case, because the two files earn opposite advice.
  - *Edge case:* a fixture holding only small files → no advisory line at all.
  - *Edge case:* an oversized file matching neither name → one line with its size and "unrecognised, left alone", and no advice.
  - *Edge case:* two oversized files → both named, one line each, each with its own classification.
  - *Error / failure path:* no analytics directory → no advisory, no error.
  - *Integration:* the advisory never runs against `$HOME` during the suite, asserted by pointing `ENSEMBLE_ANALYTICS_DIR` at a temp dir and confirming the operator's real directory is not stat'd, and by the line-count-unchanged check U3 already performs over the full suite.
- **Verification:** scenarios green; verification's exit status unchanged in every case; `grep -c 'safe to delete' skills/en-setup/` is 0. Negative controls: raise the threshold above the fixture size and confirm the happy-path scenario goes red; give the rollup fixture the guardrail file's advice and confirm the classification assertion goes red.

## Decisions, assumptions & risks

- **Decision:** The ledger is addressed through `$git_dir/ensemble/runs/active`, a file on disk, with `ENSEMBLE_RUN_LEDGER` demoted to an override. The design specified the environment variable alone. That does not work in the host these skills actually run in: each Bash tool call is a fresh shell, so a variable exported by the call that ran `start` is gone by the call that runs `ensemble-unit-verify`. Keeping it would have put `ENSEMBLE_RUN_LEDGER=… bash …` on every helper invocation, which is exactly the bookkeeping-the-model-forgets that the design rejected Approach A for. The file survives across shells, is per-repo, is never committed, and disappears with the clone like the ledgers themselves. Every settled decision that depended on the variable (the child pointer, one ledger per skill run, no required arguments, no skill changes) holds unchanged, and the override still covers the case the variable was good at: a genuine subprocess tree, and test redirection.
- **Decision:** The rollup line is wide rather than minimal, carrying counts, the outcome verbatim and a `detail` object. The per-clone ledgers are the only place a missing field could be recovered from and they do not survive, so a field omitted today is unrecoverable for every run before someone adds it. The design's devil's advocate names this as the least reversible decision in the whole shape.
- **Decision:** The `outcome` event is validated against one shared allowlist rather than a per-skill schema. One skill emits it in this tranche, and the design calls that too small a sample to design a schema from. **Revisit trigger:** the second skill to emit an `outcome`. If its fields do not fit the shared set, that is the evidence for splitting it, and it will be concrete rather than hypothetical.
- **Decision:** `/en-review` is the one model-emitted call point, and it stays that way. The corroboration split is computed during reconciliation and `ensemble-peer-invoke` contains no reference to it, so no helper can observe it. Peer review pushed to move the recording into a deterministic helper "with the model supplying only the reconciliation result"; that is already the shape here, since the model supplies counts and the helper owns validation, naming and the write. Making it more deterministic would require a helper that can see corroboration, which is the thing that does not exist. What the review was right about is the proof: U8's integration scenario now asserts all the way through `bin/ensemble-metrics --peer-value`, so a key that survives the allowlist under the wrong name cannot pass.
- **Decision:** The rollup is published before the ledger's `finish` event, and publication is idempotent on `run_id`. The other order loses the run's only durable record whenever the analytics directory is briefly unwritable, with nothing left to retry from. Rotation **is** serialized by a `mkdir` lock, reversing the position taken in the first iteration. That position was wrong: two `finish` calls both seeing an over-cap file each `mv` it to `.1`, and the second overwrites the first's `.1`, so a whole 5 MB generation disappears rather than merely being reordered. The lock is unlike the one PR #106 removed in the way that matters. It is held only across the size check and the rename, never across an append, and failing to take it skips rotation and appends anyway, so its worst case is a file that stays over the cap until the next run. The old lock's worst case was a dropped event.
- **Decision:** The opt-out is checked by every subcommand, not only by `start`. A run begun before the operator set `enabled: false` would otherwise keep recording until it ended, which is not what an opt-out means.
- **Decision:** The opt-out is read by a six-line awk inside `ensemble-run-metrics` rather than through `ensemble-config-get`. The reader parses flat top-level keys only, skipping every indented line, so it cannot see a nested `metrics:` block at all; `skills/en-sweep/scripts/ensemble-sweep-runner` already hand-rolls its own parser for `sweep.enabled` for the same reason. `en-build` also does not carry `ensemble-config-get`, so using it would mean adding a script to a skill to read one boolean.
- **Alternative:** Each emitter inlining its own four-line append instead of calling `ensemble-run-metrics`. It would need no new carriers. Rejected because the allowlist is the design's privacy boundary and it would then exist in five copies, each able to drift; one script owning what can reach disk is the property worth the extra carriers.
- **Alternative:** One ledger per run tree, with nested skills appending to whatever they inherit. This is the design's rejected Approach B, and the reason still holds: the ask is per-skill effectiveness, so "an `/en-review` run" has to be a first-class unit rather than a span you reconstruct by filtering.
- **Assumption:** `tests/lint/analytics-isolation.test.sh` is on `main` (PR #108, merged 2026-09-10) and its writer discovery is a grep over `skills/*/bin/*` and `skills/*/scripts/*` for an append to a path containing "analytics". U3 relies on that grep finding the new rollup writer without being told about it. Falsified by the guard staying green after U3 lands with the override deliberately removed, which U3's negative control (a) checks directly.
- **Assumption:** Two levels of skill nesting is the practical maximum (`/en-build` into `/en-review`, `/en-ship` into `/en-resolve-pr`). Carried forward from the design, still unenforced. The `active` stack does not care about depth, so a third level would work; it has simply never been exercised.
- **Risk:** A run that dies without calling `finish` leaves a live line on `active`, and the next skill's events get attributed to it as a parent. **Mitigation:** `start` prunes entries whose ledger is missing or already finished; the residue is a run that is genuinely still open, which is the honest reading. The design's own devil's advocate makes the matching point about events arriving after `finish`, and `--time` excludes runs with no `ended_at` for the same reason.
- **Risk:** Two skill runs active in the same repo at once make "the last live line" the wrong answer for one of them. **Mitigation:** accepted and recorded rather than solved. The helpers run from one agent session per repo in practice, and the alternative is threading a run id through every call site, which is the required argument the design refused.
- **Risk:** A helper emitting a field nobody added to the allowlist gets it dropped silently, and the symptom is a number that is quietly always zero. **Mitigation:** stderr on every drop, a `dropped` count on the written line, and `dropped` carried up into the rollup line, so the loss is visible in the durable artifact and not only in a terminal nobody was watching.
- **Risk:** Twelve units all touching scripts that are byte-identical across two to three skills, where a single unsynced copy fails `tests/parity/script-parity.test.sh`. **Mitigation:** every unit lists all its carriers explicitly in `Files:`, and the parity suite runs in each unit's verification rather than only at the end.

## Tracked debt

None resolved. Nothing deferred.

## Iteration log

> - 2026-09-10 (initial): plan v0 from `docs/designs/2026-09-10-per-skill-analytics-design.md`, with the four open questions resolved by the user (rich rollup, shared outcome allowlist, size-cap rotation, leave the old store and surface it in setup).
> - 2026-09-10 (iteration 1, `revise`): five P1 findings. Four applied: U12 added so the three newly-instrumented skills open and close their own runs; the dependency chain serialized so every `ensemble-run-metrics` edit precedes any new carrier; the opt-out moved off `start` onto every subcommand; the rollup published before the ledger closes and made idempotent. One disagreed: `/en-review`'s outcome event stays model-emitted, because no helper can observe corroboration. Its testing point was taken.
> - 2026-09-11 (branch review, `reject` from the peer and `revise` from the personas): the plan's own drift reconciled against what shipped. U12's Approach specified a lint that routes a prose failure-protocol table through a reporting step; that is not statically checkable and was never built, so U12 now says so rather than claiming a gate that does not exist. U6's Files named a test directory the tests did not land in, U11's named a SKILL.md that was never touched and omitted the script the whole unit landed in, and U10 said three carriers and six in the same paragraph where the number is five. `peer_review_plan_hash` re-baselined, because Approach and Files both changed.
> - 2026-09-10 (iteration 2, `reject`): one P0 and four P1, all applied. The P0 was a defect introduced by iteration 1's own fix, two concurrent rotations each renaming the current file to `.1` and the second destroying the first's generation, plus two read-only scenarios that contradicted each other. Rotation is now locked, idempotence scans both generations, `finish` pops `active` even when opted out, liveness no longer depends on the last line, U8 declares the report dependency it uses, U12's failure-path promise became a lint-checkable property, and `/en-setup` classifies each oversized file rather than calling any of them safe to delete. Plan held at `status: draft` per the reject protocol; no third peer pass was run.
