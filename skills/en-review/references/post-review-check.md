# Post-review check: ask the receipt first, then run only what is unproved

`/en-review` edits code when it applies a fix, and a fix can be wrong. The check
after step 12 is what catches that. It is also the point where a review can hand
`/en-ship` evidence, so that a review followed by a ship does not run lint and
the targeted tests twice on an identical tree minutes apart.

## When it runs

- **After any applied fix** (`applied_fixes[]` is non-empty), on any target.
- **On the bare branch diff** (step 4, no target) even when nothing was applied.
  That base is the one `/en-ship` asks about, so a passing run there is evidence
  it can honour.
- **Never in `report-only`.** That mode is CI and strictly read-only; it runs
  nothing and writes nothing.
- **Not on any other target when nothing was applied** (`--base <ref>`, a ref
  range, a branch name, a file). A run there would prove a set nobody downstream
  asks about.

Every run reports one `post_review_check:` line in the markdown summary:
`skipped (receipt by <writer>, <age>m, <checks>)`, `ran (selection: graph |
approximate, <n> tests)`, `failed (<what>)`, or `not-run (report-only |
no-default-target)`. A skip nobody can see is indistinguishable from a check
that never existed.

## 1. Ask whether another layer already proved this exact tree

```bash
bash "$SKILL_DIR/scripts/ensemble-verification-receipt" verify --requires lint,typecheck,full_suite --json
```

On `check-not-recorded` alone, ask once more with
`--requires lint,typecheck,targeted_tests`. Two questions are not partial
credit: each names a complete set, and the second is exactly the set this check
would run itself, so a receipt `/en-ship --preflight` or an earlier `/en-review`
wrote against the identical tree is the same evidence.

- **Exit 0 → skip** lint, typecheck and the tests. Report what was skipped,
  which checks the receipt covered, how old it is, and who wrote it. An applied
  edit moves the fingerprint, so exit 0 is
  only possible when nothing was applied; a receipt never excuses re-testing a fix.
- **Any non-zero → run everything**, and surface the refusal reason verbatim
  (`fingerprint-mismatch`, `base-moved`, `dependency-changed`, `wrong-repo`,
  `expired`, `check-not-recorded`, `no-receipt`).

There is no partial credit. The validity argument is en-ship's
verification-receipt reference and is not repeated here.

## 2. Run

- The project's `lint` command from `AGENTS.md`.
- Its `typecheck` command, if applicable.
- Tests: `test_changed_command` from `AGENTS.md`, the graph-selected set;
  report `selection: graph`. When the project declares none, the unit suite
  (the `test` command), reported `selection: approximate`. Not the full suite:
  a full run here re-proves files the fix never touched, and `/en-build` and CI
  own that run. An empty selection is reported as empty, never as a pass.

## 3. Act on the outcome

- **Failure after an applied fix.** Revert the applied edits (restore from the
  Phase 1 baseline) and surface the regression with the failing test names.
  `applied_fixes[]` is derived from the tree delta, so the reverted entries
  leave it and `review_fixes:` reflects what actually stands.
- **Failure with nothing applied.** The fault is pre-existing. Surface it as a
  P1 finding at the failing test's location and write no receipt.
- **Success on the bare branch diff.** Write a receipt for what this run proved:

  ```bash
  bash "$SKILL_DIR/scripts/ensemble-verification-receipt" write --check lint=passed --check typecheck=passed --check targeted_tests=passed --base origin/<base> --by en-review
  ```

  plus `--dep <path>` for each lockfile the project has. It records
  `targeted_tests`, never `full_suite`. Never fatal: a failed write is a warning.
- **Success on any other target.** Write nothing. `targeted_tests` names a set
  selected against a base, and a receipt from `--base HEAD` would record a set
  chosen from the uncommitted delta alone; `/en-ship` would read it as its own.
