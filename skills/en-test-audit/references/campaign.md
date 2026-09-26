# Campaign mode

`/en-test-audit --campaign <path>` prunes one subsystem's whole test surface in
one PR: a plugin, a service, or one core area. Batch mode's value bar, retention
bar, candidate evidence and scripts apply to every lane unchanged; this file adds
the order of work. Each step ends on its done criterion, and the next step does
not start early.

The campaign writes one ledger with `mode: campaign`. Its extra tables (Lanes,
Product defects) and the full-coverage and rebaselining rules are in
`references/ledger-format.md`, and `ensemble-test-ledger-verify --tree` enforces
all of them, so a campaign that skips a step below fails the verifier rather
than relying on this file being followed.

## 1. Baseline

Run the preflight with `--scope <path>`. Record the subsystem's test and
test-support line counts and every test file's pass or fail state at that
`baseline_sha`. Keep baseline failures in their own list: in the campaign this
workflow was adapted from, all three were real product bugs, not stale tests.

**Done when** every in-scope test file has a recorded baseline result.

## 2. Lanes

Split the surface into lanes along **production owner boundaries**, not file
name prefixes: accounts, inbound, outbound, persistence, transport, shared
harness, and so on. Include the subsystem's cases at shared core boundaries and
its end-to-end or live-proof harness tests. Write the `## Lanes` table.

**Done when** every test file under the scope that matches `test_glob` is in
exactly one lane.

## 3. A read-only ledger per lane

Give each lane to its own read-only sub-agent (the host's read-only explore
agent; no agent file is carried for this), in one parallel batch. Each reads
every assigned test in full, including parameter tables, and the production
owners with their entry points, callers, history and CI routing. It returns one
row per declaration with a mark and an evidence line; a parameterised test is one
declaration unless its rows need different marks.

- `R` retain, naming the contract and the bug it catches;
- `F` keep the contract, repair the assertion (a negative that passes when only
  one of several items is missing, for example);
- `C` consolidate, naming the owner that absorbs the assertion first;
- `D` delete, naming the proof that remains, or why no contract exists.

**Judge a test by its assertions, not its name.** Merge the lanes' rows into the
one ledger yourself; sub-agents never write it.

**Done when** every declaration in every lane has a row, which the verifier's
full-coverage rule checks.

## 4. Layer plan per lane

Treat the per-test ledger as input, not as the edit list. A second read-only
pass per lane looks for a redundant **layer**: several suites replaying the same
shared behaviour through one mocked collaborator, around a stronger suite that
exercises the real boundary. Name the **keeper** suite for each contract,
preferring the real transport boundary with a fake network over a mocked
collaborator. Correct any ledger rows this pass shows were wrong.

**Done when** each lane names its retired files, its keeper per contract, the
assertions to carry into keepers, and the test-only production seams unlocked.

## 5. Cutover, lane by lane

Run batch mode's steps 6 to 9 for one lane at a time: tests first, a caught
mutation for every C and F row, then the seams, then the owner tests. **Changes
to shared harnesses and support files go through one owner**, serialized, never
edited by two lanes at once. Register moved suites in CI routing and any test
inventory, and update shrink-only line-count baselines. Put durable
test-ownership rules in the subsystem's `AGENTS.md`, drawn only from mistakes
this campaign actually found.

**Done when** every lane plan is applied and each lane's keepers pass.

## 6. Preservation review

Batch mode's step 10, run once per boundary group rather than once for the whole
diff, so each review sees a diff it can read in full.

**Done when** every reported gap is restored, with its own caught mutation, or
rejected with source evidence in its row.

## 7. Product defects

A baseline failure that survives into a keeper is a bug report. Fix it at its
owner in its own commit, and prove it through the real user flow with a
**control run**: revert the fix, show the keeper red, restore it. Record each in
`## Product defects` with the fix commit and the control evidence. Unrelated
product discrepancies found along the way become follow-ups, not fixes.

**Done when** each repaired defect has a failing control and a passing candidate
on the same harness.

## 8. Reconcile

Campaigns outlive many commits on main. Merge main rather than rebasing a long
campaign, then **rebaseline**: move `baseline_sha` to main's merged SHA and
record the old one as `rebaselined_from`. Reread every in-scope test file main
changed between the two, and give each new or changed declaration its own row
whose Evidence starts `reconciled:`, judged fresh. Carry each kept assertion into
its keeper with a new caught mutation, and rerun the preservation review over the
affected rows. **Only then** resolve a conflict on a file the campaign deleted as
a deletion. The verifier enforces this on the merged head: full coverage catches
a new declaration with no row, and the rebaseline rule catches a changed file
with no `reconciled:` row. Rerun the whole subsystem suite on the merged head.

Expect review tooling to see a truncated file list on a diff this large; the
ledger is the index a reviewer reads first.

## Hand-off

Batch mode's hand-off, plus:

- baseline and final test and test-support line counts, production counted
  separately;
- lanes, retired layers, and the keeper per contract;
- preservation gaps found, and the mutation that proved each restoration;
- product defects, with control and candidate proof.
