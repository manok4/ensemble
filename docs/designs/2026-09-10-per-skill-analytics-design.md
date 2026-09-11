---
type: design
created: 2026-09-10
topic: Per-skill analytics — what each skill records about its own effectiveness and efficiency
status: accepted
related_plan: EN17
---

# Per-skill analytics — what each skill records about its own effectiveness and efficiency

## Problem

We want to know how each skill performs, and today we cannot tell. `ensemble-run-metrics` has existed since D106 and **has never written a single ledger in this repo**; the peer-in-the-fix-loop question has been parked for weeks on data that was never accumulating. The hard requirement is that measuring must not be intrusive: no extra model turns, no extra tokens in the flow, and it must never block a run.

## Constraints and context

- **Phase 1 has landed** (PR #106). `ensemble-run-metrics` is keyed on `--skill` rather than `--plan`, so all sixteen skills can record rather than two, and events are appended as JSONL lines rather than rewritten through jq. Verified: twenty concurrent appends, twenty recorded.
- **The design principle is settled: the helper that does the work records the work, not the model.** `ensemble-unit-verify` knows its exit code and duration; `ensemble-peer-invoke` knows the peer decision and elapsed time; `ensemble-test-select` knows its tier. A model composing a JSON payload by hand is the intrusion being removed, and it is why the two skills that *could* record still produced nothing.
- **No helper emits today.** Verified: no script under `skills/*/scripts/` other than the helper itself references `ENSEMBLE_RUN_LEDGER` or `run-metrics event`.
- **`ensemble-metrics report` does not exist**, and there is no `metrics` key in `.ensemble/config.local.example.yaml`. Both verified.
- **A per-operator analytics store already exists**, and it is prior art rather than a greenfield: `~/.ensemble/analytics/guardrail.jsonl`, 71,171 events since 2026-05-02, written by `skills/en-guardrail/bin/check-guardrail.sh:52`. Its envelope is `{event, skill, pattern, ts, repo}` — five keys, one enum field, no content. That is close to what this design needs, and the new rollup belongs beside it.
- **That store carries two defects worth not repeating.** 97% of its events (69,373 of 71,171) land in the same second as another event, because `tests/en-guardrail/check-guardrail.test.sh` fires the matcher with no `HOME` override and the suite has been appending to the operator's real file for four months. And roughly 4,000 records carry `(^|` as their `pattern` value — a raw regex fragment reaching disk because nothing validates at write time.
- `/en-review`'s corroboration buckets are computed during reconciliation, which is model work. Verified: `ensemble-peer-invoke` contains no reference to corroboration, so no helper can observe it.

## Assumptions & unverified claims

- Assumes `check-guardrail.test.sh` is the only suite polluting the operator store. Two test files call the matcher and only that one lacks a `HOME` override, but the whole suite was not audited for other writers of `~/.ensemble/`.
- Assumes two levels of skill nesting is the practical maximum (`/en-build` → `/en-review`, `/en-ship` → `/en-resolve-pr`). Not enforced anywhere; a deeper chain would work but has not been exercised.

## Approaches considered

The dialogue settled this decision by decision rather than by choosing between whole designs, so the alternatives below are recorded as the shapes that were rejected at each fork, not as three competing architectures. The recommendation is the composition of the choices made.

### A. Model-emitted events (the status quo, rejected)

**Sketch:** The skill calls `run-metrics event` with a hand-composed JSON payload at documented call points, which is what `references/run-metrics.md` specifies today.

**Pros:**
- Already documented and already wired into two skills.
- The skill controls exactly what is recorded, including things no helper can see.

**Cons:**
- Costs model turns and tokens on bookkeeping, which is the stated non-requirement.
- It is forgettable, and the evidence is that it was forgotten: zero ledgers exist despite two skills carrying the call points.
- A hand-composed payload can invent a value; a helper reporting its own exit code cannot.

### B. Helper-emitted events, one ledger per run tree (rejected)

**Sketch:** Helpers emit via an inherited `ENSEMBLE_RUN_LEDGER`, and a nested skill appends to whichever ledger it inherits, with every event carrying the skill that emitted it.

**Pros:**
- One file per top-level run; no linking, no join at report time.
- End-to-end cost of a build is a single file read.

**Cons:**
- "An `/en-review` run" stops being a first-class unit and becomes a span you reconstruct by filtering. Two reviews in one build are indistinguishable without inventing more structure.
- A file named `en-build-<id>.jsonl` would hold another skill's data.
- Per-skill comparison, which is the actual ask, becomes derived rather than primary.

### C. Helper-emitted events, one ledger per skill run, parent holds a pointer (recommended)

**Sketch:** `start` exports `ENSEMBLE_RUN_LEDGER` for its own subtree. When it sees an inherited value it first appends a `child` pointer to the parent's ledger, then overrides the variable. Helpers append events; the model emits only a terminal `outcome` event carrying what a script cannot observe. A per-kind key allowlist drops anything not named, at write time. On `finish`, one summary line is appended to `~/.ensemble/analytics/<repo>.jsonl`.

**Pros:**
- Every skill run is a first-class unit with its own `start`, `finish` and `run_id`, so a nested `/en-review` and a standalone one are the same shape and directly comparable.
- No helper gains a required argument, so standalone use and every existing test keep working untouched.
- The inheritance problem solves itself: each `start` overrides the variable for everything below it, and the pointer is written by the helper that already knows both paths. No skill changes.
- A child that dies without finishing leaves the parent holding a pointer to an unfinished ledger, which is a recorded fact rather than a dangling reference.

**Cons:**
- `ensemble-metrics report` must follow the link to answer end-to-end cost. That is report-time complexity in one place, traded against write-time loss that would be unrecoverable.
- Two files per nested run instead of one.

## Recommendation

**Approach C.** The unit of analysis has to match the question being asked: the ask is per-skill effectiveness, so a skill run must be primary and the parent relationship derived, not the reverse. Approach B inverts that and makes "an en-review run" something you reconstruct. Approach A is the status quo, and its verdict is already in: two skills have carried its call points for weeks and produced nothing, because bookkeeping the model must remember is bookkeeping the model forgets.

## Settled decisions

| Decision | Choice |
|---|---|
| How a helper knows it is in a run | `ENSEMBLE_RUN_LEDGER` env var, exported by `start` |
| Event vocabulary | Shared efficiency kinds, plus one per-skill `outcome` event |
| Privacy enforcement | Per-kind key allowlist in the helper, dropping unknown keys at write time |
| Nested runs | Child starts its own ledger; parent records a `child` pointer |
| Durable rollup | One summary line per run, appended to `~/.ensemble/analytics/<repo>.jsonl` |
| Report surface | Named reports (`--peer-value`, `--time`, `--selection`), not a generic query tool |
| Phase 2 scope | Four helper emitters plus one `/en-review` outcome event |

Opt-out is `metrics.enabled: false` in `.ensemble/config.local.yaml`, following the existing `sweep.enabled` convention. This was not put to the user; it is the conventional default.

## Test isolation is a first-class requirement

The existing store is 97% test noise because its writer resolves `~` at call time and its matcher test does not override `HOME`. Every new emitter must honour an explicit override so the suite writes to a temporary directory, and a guard must assert that no test run appends to the operator's real store. Repeating this defect would make the new data as untrustworthy as the old.

## Devil's advocate

- **An env var is ambient state, and ambient state surprises people.** A helper run manually inside a shell that still has `ENSEMBLE_RUN_LEDGER` set will append to a run that ended hours ago. The mitigation is that `finish` unsets nothing and cannot; the honest answer is that a stale variable produces a misattributed event, and the report should treat events arriving after `finish` as suspect rather than silently counting them.
- **A write-time allowlist means silent data loss.** A helper that emits a new field gets it dropped until someone edits the allowlist, and the symptom is a number that is quietly always zero. The emitter should note dropped keys to stderr, which makes it loud in a test run and invisible in a real one.
- **Named reports encode an interpretation.** `--peer-value` will report peer-only versus corroborated findings, and whoever reads it will treat that ratio as the answer to whether the peer earns its place. It is not: a peer that finds nothing new on easy diffs and everything on hard ones averages to looking mediocre. The report should show the distribution, not a single ratio.
- **The framing may be wrong.** We are measuring what skills *do*, not whether the work was any good. A build with zero gate failures and fast units might have shipped the wrong thing, and nothing here would notice. This data can say a skill is efficient; it can only proxy for effective.
- **Four months from now the rollup is the only file that matters**, and it holds one summary line per run. If the summary omitted a field we later want, the per-clone ledgers that had it are gone. The summary's shape is the least reversible decision here and deserves the most scrutiny at plan time.

## Why we're proceeding anyway

- The alternative is the status quo, which produces nothing at all, and the parked peer question has already cost weeks of waiting on data that was never being collected.
- Phase 2 is four helpers and one outcome event, deliberately small enough to confirm the vocabulary against real ledgers before it spreads to the remaining six.

## Open questions

- Whether the `outcome` event's per-skill fields should be validated against a per-skill schema or only against the shared allowlist. Stricter is safer and more work; the tranche of one skill is too small a sample to decide on.
- What retention looks like for the rollup. The guardrail file reached 8.6 MB in four months at one event per hook fire; one line per run is far smaller, but nothing currently rotates or prunes, and "nothing prunes" is how the 8.6 MB happened.
- Whether the existing `guardrail.jsonl` should be migrated, truncated, or left alone. It is mostly test noise, so its historical value is low, but deleting an operator's data is not this design's call.

## Next steps

- Run `/en-plan` to turn this into units: the helper emit path, the allowlist, the four emitters, the `/en-review` outcome event, the rollup, and the three named reports.
- The test-isolation defect in `check-guardrail.sh` is a separate, smaller fix and does not need this design; it can go ahead of the plan.
