# Peer review brief — the preservation review

What the peer is asked before a test-audit batch is committed, and what this
skill does with the answer. The wire format both ends share is
`references/peer-contract.md`; everything here is this skill's own.

The artifact is one file: the batch's ledger (every judged test, marked R, F, C
or D, with its keeper and evidence), then the staged diff. You have read access
to the repository, so read the tests and production code the ledger names
rather than trusting its evidence column.

## What the peer is asked

A test suite is being pruned. Deleting a test is cheap to do and expensive to
get wrong, because a contract that loses its only proof fails silently later.
Review the batch along these three dimensions, in this order.

### preservation — did a contract lose its only proof?

For each **D** and **C** row, read the deleted or consolidated test's assertions
in the diff, then read the keeper it names, or check the reason it gives for
needing none.

- Does the keeper assert the same behaviour, through a boundary that can see it?
  A keeper that exercises the code without asserting the outcome does not count.
- Is the "none" reason true? "Exercises a deleted export" is true only if the
  export is gone and nothing else reaches that behaviour.
- Did the batch delete a production seam that a remaining test or a non-test
  caller still uses?

Answer with source evidence: `<file>:<line>` for the assertion that was lost and
for where the keeper does or does not cover it. A gap with no evidence is not a
finding.

### cannot-fail — can a new or repaired assertion pass for the wrong reason?

For each **F** and **C** row, read the assertion the batch added or moved.
Flag one that passes when the behaviour it names is broken: no assertion, only
"did not throw", a negative case rejected by a different guard, or an input the
code never reaches. The row's mutation proves the keeper fails for one break; say
if that break was the wrong one to prove the contract.

### retention — advisory only

Flag an **R** row that is plainly junk by `references/good-tests.md`, with the
anti-pattern and its tell. This never blocks the batch; it becomes a candidate
for the next one.

## Where a finding points

Use `<file>:<line>` for code, the ledger row's Test cell for a ledger claim, or
`global` when it is about the batch as a whole.

## What this skill does with the findings

The host decides on each. A real preservation gap is restored: the assertion
goes back, or into a keeper, as an F or C row with its own caught mutation. A
cannot-fail finding sends the row back to repair. A finding the host rejects gets
one line of source evidence in the row's Evidence cell, so the PR reader sees
both sides. Retention findings are listed as next-batch candidates.
