# The test-audit ledger

One markdown file per audit, committed with the batch it justifies:
`docs/test-audits/<YYYY-MM-DD>-<slug>.md` in the project being audited. It is the
PR's evidence of why each test went, and the input `ensemble-test-ledger-verify`
checks before anything is committed. Write it before the first edit, and keep it
true as the batch changes.

## Frontmatter

```yaml
---
type: test-audit
mode: batch                  # batch | campaign
scope: src/billing           # the path the audit covered; "." for the whole repo
test_glob: "*.test.ts"       # required: which files under scope are test files (see Removals)
baseline_sha: 3f2c1e9        # the commit every declaration is checked against
created: 2026-09-26
preservation_review: cross-agent   # cross-agent | single-agent-fallback | skipped-by-flag
# rebaselined_from: 1a2b3c4  # campaign only, after merging main (see Rebaselining)
---
```

`baseline_sha` is the preflight's `baseline_sha=`. `preservation_review` records
what actually reviewed the batch. `skipped-by-flag` is written only by a
`--no-peer` resume, never by default.

## The ledger table

Exactly one table under a `## Ledger` heading, with exactly these columns:

```markdown
## Ledger

| Test | Mark | Keeper or contract | Evidence | Mutation |
|---|---|---|---|---|
| src/billing/total.test.ts::sums line items | R | invoice total, public API | only test of rounding to cents | - |
| src/billing/total.test.ts::handles empty | F | empty invoice totals zero | asserted `toBeTruthy`, now `toBe(0)` | 2026-09-26-billing/mutations/empty-total.diff |
| src/billing/tax.test.ts::adds tax twice | C | src/billing/tax.test.ts::applies tax once | same contract, one table row now | 2026-09-26-billing/mutations/tax-once.diff |
| src/billing/legacy.test.ts | D | none: exercises a deleted export | export removed in 2026-06, test only imports it | - |
```

**Test.** `<repo-path>` for a whole file, or `<repo-path>::<declaration name>`.
A declaration name resolves only in one of these forms, on a line that is not a
comment:

- a quoted string opening a call to `it`, `test`, `describe`, `context` or
  `specify`, optionally `.only`, `.skip`, `.todo` or `.concurrent`
  (`it("sums line items", ...)`, `test.skip('rounds')`); the call must not be a
  method or the tail of a longer name, so `x.test("a")` and `submit("a")` are not
  tests;
- `t.Run("case", ...)` (Go subtests);
- `pass "name"` (shell suites that report a check by name) and `@test "name"` (bats);
- a test-named function: `def test_sums` (Python), `func TestSums` (Go).

A test in any other form, including `.each` tables, gets a whole-file row. The
verifier fails a name it cannot find in these forms at `baseline_sha`, so an
unsupported format or a typo is caught rather than read as "already deleted".
Two declarations may share a name; each D or C row accounts for one of them.

**Mark.**

| Mark | Meaning | Keeper or contract | Evidence | Mutation |
|---|---|---|---|---|
| `R` | retain | the contract it guards | why it stays | `-` |
| `F` | retain the contract, repair the assertion | the contract | what was wrong with it | **required** |
| `C` | consolidate into a keeper | the keeper, `<path>::<name>` | **required**: why the keeper covers it | **required** |
| `D` | delete | the keeper `<path>::<name>`, or `none: <reason>` | **required**: the proof that remains, or why no contract exists | `-` |

F and C are the rows where the audit moved or rewrote an assertion, which is
where coverage silently drops, so each needs a mutation the keeper catches: the
`.diff` path, relative to this file, kept under `<YYYY-MM-DD>-<slug>/mutations/`
beside the ledger. A caught run of `ensemble-mutation-check` writes
`<diff>.caught`, a receipt keyed to the diff's content; the verifier requires it,
so a diff that was never run, or was edited after the run, fails. Commit the
receipts with the diffs. A D row with a keeper needs none: the keeper predates
the audit.

**Cells.** No `|` inside a cell; the verifier treats a row with the wrong
number of cells as malformed rather than guessing where it splits. Backticks
around paths are fine.

**What needs a row.** In batch mode, every declaration in every file the batch
judged, retained ones included, so each retained false positive is on record. A
file the batch never opened needs none. In campaign mode, see below.

**Paths.** Every path in a Test, Keeper or Mutation cell resolves inside the
repository. A `../` or absolute path is a violation.

## Removals

`--tree` compares every file the ledger names, and every changed file under
`scope` that matches `test_glob`, between `baseline_sha` and the working tree.
Each declaration that is gone needs its own D or C row, and each R or F row's
test must still be there. A deletion the ledger does not mention, in any test
file, therefore fails the verifier, which is why `test_glob` is required in
both modes.

`--tree` also requires the ledger, its diffs and their receipts to be staged
exactly as checked, so the commit carries the evidence the verifier saw.

## Whole-file rows

A `Test` cell with no `::name`. The file must exist at `baseline_sha`. A D or C
whole-file row requires the file to be gone from the working tree. A C row's
keeper is always `<path>::<name>`, never a bare path.

## Seams removed

Optional. Test-only production seams (exports, flags, reset hooks, injection
parameters) the batch deleted because only tests called them:

```markdown
## Seams removed

| Path | Reason |
|---|---|
| src/billing/reset-for-tests.ts | every caller was a test |
```

These paths may be staged with the batch; a `--resume` accepts them.

## Campaign sections

A campaign ledger adds two tables, and a stricter coverage rule.

```markdown
## Lanes

| Lane | Files |
|---|---|
| inbound | src/billing/inbound.test.ts, src/billing/parse.test.ts |
| outbound | src/billing/send.test.ts |

## Product defects

| Defect | Fix commit | Control evidence |
|---|---|---|
| rounding drops a cent on refunds | 9e1f2a0 | reverting 9e1f2a0 turns total.test.ts::refund rounding red |
```

- Every file under `scope` matching `test_glob` is in exactly one lane.
- Every declaration in those files at `baseline_sha`, in a supported form, has
  its own row, unless its file has a whole-file row. A file in an unsupported
  format therefore needs a whole-file row.
- Every Product defects cell is required.

## Rebaselining

A campaign that merges main moves `baseline_sha` to main's merged SHA and records
the previous value as `rebaselined_from`. Main's side still has every test the
campaign deleted, and has what main added, so deletions and new declarations are
both checked against the one baseline. In every in-scope test file main changed
between `rebaselined_from` and `baseline_sha`, each declaration main added or
changed needs its own row whose Evidence starts `reconciled:` (or the file a
whole-file `reconciled:` row). A declaration's extent runs from its line to the
next declaration, so an edit inside a test's body counts as a change. A changed
assertion is judged again instead of silently deleted.
