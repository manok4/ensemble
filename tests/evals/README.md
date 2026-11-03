# Skill evals

Two kinds of check, at two costs.

| | What it checks | Runs | Cost |
|---|---|---|---|
| `trigger-rank`, `trigger.test.sh` | Each model-invocable skill's description ranks its skill for the prompts in `cases/`, negative prompts go to their owner, and no two descriptions converge | CI, through `tests/run.sh` | Free |
| `run-behavioral` | A skill run through a real headless session on a scratch repo does what its case expects | On demand only | Real tokens |

`grade.test.sh` tests the grader offline against recorded outputs, so it runs in CI while the sessions it grades do not.

## Running a behavioral case

```bash
tests/evals/run-behavioral review-logic --dry-run          # prints the plan and the exact command; spends nothing
tests/evals/run-behavioral review-logic --mode peer --runs 1
tests/evals/run-behavioral all --runs 3
```

**Cost:** one full skill run per case, per mode, per run. A `/en-review` case also calls the cross-agent peer. Results go to `tests/evals/results/<timestamp>/` (gitignored), one directory per run, holding `output.txt`, `grade.json` and the scratch repo's path.

**Isolation.** The skill comes from this checkout through `--plugin-dir` and is invoked by its plugin-qualified name (`/ensemble:en-review`). An installed copy under `~/.claude/skills` therefore never answers in its place. The session runs with `bypassPermissions` inside a throwaway repo, because the skills under test run scripts, git and the peer CLI, and a permission prompt ends a headless run. `ENSEMBLE_ANALYTICS_DIR` points into the results directory, so eval runs never reach real metrics.

**Runs are stochastic.** Read rates across runs, not one outcome. Record any run that changed a decision in `ledger.md`.

## Case contract (v1)

Each case is `behavioral/<case>/` with `prompt.md`, `expect.json`, and `base/` (or `base_from` naming another case's `base/`). A review case also has `change/`, overlaid on a `feature` branch. `tests/evals/grade` documents every field and validates a case before any token is spent.

**Grading uses facts first.** A review run is matched against the planted defects by finding location: same file, a line inside the defect's range plus or minus 3, and severity at or above the case's minimum. Each finding matches one defect at most.
- **recall** is matched defects over planted ones. It is `null` for a clean case.
- **precision** is matching findings over all actionable findings. It is `null` when there are none. Precision is reported but never gates, because an unmatched finding may still be real.

A review run passes when recall meets `bars.min_recall` (default 1.0), every `personas_include` entry was dispatched, and any `bars.max_findings` cap holds. Headless `/en-review` prints a summary and writes its envelope to a file; the runner grades that file.

**A fix run** is graded by revert and rerun, with no model involved:
1. Find the test files the run added or changed since `main`.
2. Put the source files back to `main` in a copy, keeping the new tests, and run the case's `test_command`. It must fail.
3. Run it again on the fix. It must pass.

`trailers` checks require or forbid a commit trailer such as `Docs:`. A fix case's scratch repo has no `origin`, so `/en-fix` stops at `/en-ship`'s preflight, and the grader reads the commits made before that stop.

**A plan run** is graded on the one plan file it wrote. `bin/ensemble-lint` must report no P1 for it. Then each `plan_checks` entry finds its unit by a title regex and checks:
- **`must_contain`:** the strings appear in at least one matching unit.
- **`risk`:** the unit's risk is the value named.
- **`last`:** the unit comes last in the plan.
- **`before`:** the unit precedes the one matching that regex.

The positional checks (`risk`, `last`, `before`) need exactly one matching unit. Plan cases run `/en-plan --no-peer`, and the prompt tells it to take its recommended answers, since nobody answers questions in a headless run. The judge reads the session output and the plan file together.

**The judge** rules only on what no fact can settle, such as "the reply did not agree to skip the test". The transcript goes to `claude -p` on stdin, fenced as untrusted data. A verdict counts only when its quoted evidence appears in the transcript. A run passes only when both the facts and the judge pass, and `grade.json` keeps each part separately.

## Adding a case

Plant defects you can name by file and line, and keep the project small enough to read in one sitting. Then:
1. Run `tests/evals/grade validate behavioral/<case>`.
2. Do a `--dry-run`.
3. Do one real run.

A fixture that plants a skipped test or a removed assertion trips `/en-ship`'s floor guard. Commit it with a `Floor-Exception:` trailer naming the fixture path.
