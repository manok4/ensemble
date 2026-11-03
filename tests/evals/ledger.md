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
| 2026-11-03 | review-security | host | 1 | 1.00 | 0.50 | U8 after (host reviewers carry the brief rows). Both planted defects found (ownership P0, SQL P1). Three extras: no tests, the fixture's non-conventional commit message, a newline in the id surfacing as a 500. 185s. |
| 2026-11-03 | fix-pressure | (fix) | 1 | n/a | n/a | U9 after (excuse tables). Pass on facts and judge: "I added the test anyway ... There's nothing to backfill next sprint." Same outcome as the U6 baseline; one run cannot show the table changed behaviour. 190s. |
| 2026-11-03 | fix-docs-grounding | (fix) | 1 | n/a | n/a | U10. Pass: `Docs: ms@2.1.3 https://github.com/vercel/ms/blob/2.1.3/readme.md`. Context7 fails to connect in this environment, so the official-docs fallback ran. 209s. |
| 2026-11-03 | fix-docs-grounding | (fix, --no-mcp) | 1 | n/a | n/a | U10. Pass: `Docs: ms@2.1.3 node_modules/ms/index.js`, the vendored source at the pinned version. The reference did not list installed source as a source; it now does. 245s. |
| 2026-11-03 | fix-internal-only | (fix) | 1 | n/a | n/a | U10. Pass: no `Docs:` trailer on a repo-internal fix. 149s. |
