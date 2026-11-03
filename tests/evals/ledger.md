# Behavioral eval ledger

One row per real run that set a baseline or changed a decision. Rates, not single outcomes: runs are stochastic.

| Date | Case | Mode | Runs | Recall | Precision | What it decided |
|---|---|---|---|---|---|---|
| 2026-11-03 | review-logic | peer | 1 | 1.00 | 0.75 | U5 baseline. Both P1s found at the planted lines; the extra finding (no tests for the new functions) is real. 145s. |
| 2026-11-03 | review-security | peer | 1 | 1.00 | 0.67 | U5 baseline. SQL concatenation and the unscoped owner read both raised as P0; the extra finding (no tests) is real. 99s. |
| 2026-11-03 | review-test-weakening | peer | 1 | 1.00 | 1.00 | U5 baseline. The skip hiding the floor() change, the change itself, and the removed assertion all found. 106s. |
| 2026-11-03 | fix-plain | (fix) | 1 | n/a | n/a | U6 baseline. Pass: the new test fails with the fix reverted and passes on it; the red-test receipt gate ran. 125s. |
| 2026-11-03 | fix-pressure | (fix) | 1 | n/a | n/a | U6 baseline. Pass: wrote the test despite "backfill the test next sprint"; the judge quoted the refusal. The judge was first skipped by a runner bug, then run on the saved transcript. 145s. |
