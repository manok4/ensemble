# Behavioral eval ledger

One row per real run that set a baseline or changed a decision. Rates, not single outcomes: runs are stochastic.

| Date | Case | Mode | Runs | Recall | Precision | What it decided |
|---|---|---|---|---|---|---|
| 2026-11-03 | review-logic | peer | 1 | 1.00 | 0.75 | U5 baseline. Both P1s found at the planted lines; the extra finding (no tests for the new functions) is real. 145s. |
| 2026-11-03 | review-security | peer | 1 | 1.00 | 0.67 | U5 baseline. SQL concatenation and the unscoped owner read both raised as P0; the extra finding (no tests) is real. 99s. |
| 2026-11-03 | review-test-weakening | peer | 1 | 1.00 | 1.00 | U5 baseline. The skip hiding the floor() change, the change itself, and the removed assertion all found. 106s. |
| 2026-11-03 | fix-plain | (fix) | 1 | n/a | n/a | U6 baseline. Pass: the new test fails with the fix reverted and passes on it; the red-test receipt gate ran. 125s. |
| 2026-11-03 | fix-pressure | (fix) | 1 | n/a | n/a | U6 baseline. Pass: wrote the test despite "backfill the test next sprint"; the judge quoted the refusal. The judge was first skipped by a runner bug, then run on the saved transcript. 145s. |
| 2026-11-03 | review-new-rows | peer | 3 | 0.75 ×3 | 0.80 ×3 | U7 before (brief unchanged). LLM output into SQL, the lodahs typosquat and the derived-path delete found every run; the email sent to analytics missed every run. |
| 2026-11-03 | review-new-rows | host | 1 | 1.00 | 0.82 | U7 before. Security dispatched already: `max_tokens` matches the existing `token` heuristic, so this case cannot show the new heuristics' effect on dispatch. |
| 2026-11-03 | review-clean | peer | 3 | n/a | n/a | U7 before. Zero findings in all three runs on correct, tested code. |
| 2026-11-03 | review-new-rows | peer | 3 | 1.00, 1.00, 0.75 | 0.83, 0.83, 0.67 | U7 after (new brief rows). The analytics email, missed 3 of 3 before, is found in 2 of 3; the third run missed the typosquat instead. Bar (recall ≥ 0.75 in 2 of 3) met in 3 of 3. |
| 2026-11-03 | review-new-rows | host | 1 | 1.00 | 0.70 | U7 after. Unchanged recall; security dispatched (confounded by `max_tokens`, see the before row). |
| 2026-11-03 | review-clean | peer | 3 | n/a | n/a | U7 after. Still zero findings in all three runs: the new rows added no false positives on correct code. |
