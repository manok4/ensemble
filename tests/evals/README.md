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
tests/evals/run-behavioral fix-docs-grounding --runs 1 --with-user-mcp   # loads your MCP servers
tests/evals/run-behavioral all --runs 3
```

**Cost:** one full skill run per case, per mode, per run. A `/en-review` case also calls the cross-agent peer. Results go to `tests/evals/results/<timestamp>/` (gitignored), one directory per run, holding `output.txt`, `grade.json` and the scratch repo's path.

**Isolation.** The skill comes from this checkout through `--plugin-dir` and is invoked by its plugin-qualified name (`/ensemble:en-review`). An installed copy under `~/.claude/skills` therefore never answers in its place. The session runs with `bypassPermissions` inside a throwaway repo, because the skills under test run scripts, git and the peer CLI, and a permission prompt ends a headless run. `ENSEMBLE_ANALYTICS_DIR` points into the results directory, so eval runs never reach real metrics.

**What the scratch repo does not contain.** Two things act outside it, and the runner closes both by default:
- **MCP servers.** The session loads none, unless `--with-user-mcp` is passed for a case that needs one, such as Context7 for docs grounding. With `bypassPermissions` every tool call is auto-approved, so an operator's database server in write mode would be live.
- **The network, through package managers.** npm runs offline with install scripts off, and pip has no index. A fixture can plant a typosquatted dependency (`review-new-rows` does), and the session must never install it.

**Runs are stochastic.** Read rates across runs, not one outcome. Record any run that changed a decision in `ledger.md`.

## Case contract (v1)

Each case is `behavioral/<case>/` with `prompt.md`, `expect.json`, and `base/` (or `base_from` naming another case's `base/`). A review case also has `change/`, overlaid on a `feature` branch. `tests/evals/grade` documents every field and validates a case before any token is spent.

**Grading uses facts first.** A review run is matched against the planted defects by finding location: same file, a line inside the defect's range plus or minus 3, and severity at or above the case's minimum. Each finding matches one defect at most.
- **recall** is matched defects over planted ones. It is `null` for a clean case.
- **precision** is matching findings over all actionable findings. It is `null` when there are none. Precision is reported but never gates, because an unmatched finding may still be real.

A review run passes when recall meets `bars.min_recall` (default 1.0), every `personas_include` entry was dispatched, any `bars.max_findings` cap holds, and any `tier` and `ran` match the envelope's `review_tier.required` and `.ran`. A case with `modes: ["auto"]` passes no mode flag, so the tier decides. Headless `/en-review` prints a summary and writes its envelope to a file; the runner grades that file.

**A fix run** is graded by revert and rerun, with no model involved:
1. Find the test files the run added or changed since `main`.
2. Put the source files back to `main` in a copy, keeping the new tests, and run the case's `test_command`. It must fail.
3. Run it again on the fix. It must pass.

A case with `stops: true` expects the opposite: the right outcome is stopping for a plan, so it passes only with no commit since `main`, and a judge confirms the reason.

`trailers` checks require or forbid a commit trailer such as `Docs:`. A fix case's scratch repo has no `origin`, so `/en-fix` stops at `/en-ship`'s preflight, and the grader reads the commits made before that stop.

**A plan run** is graded on the one plan file it wrote. `bin/ensemble-lint` must report no P1 for it. Then each `plan_checks` entry finds its unit by a title regex and checks:
- **`must_contain`:** the strings appear in at least one matching unit.
- **`risk`:** the unit's risk is the value named.
- **`last`:** the unit comes last in the plan.
- **`before`:** the unit precedes the one matching that regex.

A pattern may match several units, because real plans split one step across units. `before` compares the first unit each pattern matches, `last` takes the last match, and `risk` must hold for every match. Plan cases run `/en-plan --no-peer`, and the prompt tells it to take its recommended answers, since nobody answers questions in a headless run. The judge reads the session output and the plan file together.

**The judge** rules only on what no fact can settle, such as "the reply did not agree to skip the test". The transcript goes to `claude -p` on stdin, fenced as untrusted data. A verdict counts only when its quoted evidence appears in the transcript. A run passes only when both the facts and the judge pass, and `grade.json` keeps each part separately.

## Adding a case

Plant defects you can name by file and line, and keep the project small enough to read in one sitting. Then:
1. Run `tests/evals/grade validate behavioral/<case>`.
2. Do a `--dry-run`.
3. Do one real run.

**Suspect the grader before the skill on a first failure.** Read `output.txt` and the scratch repo before changing a case's expectations or the skill. Of the first 13 cases run in EN25, four failed their first grade, and every one was the grader's fault:
- the envelope was written to a file, not stdout
- a plan settled the policy in its Technical design section
- several units matched one step
- the runner could not read a judge list

None of the four failures was the skill's. Each is fixed now, but the next grader will meet output it did not imagine.

A fixture that plants a skipped test or a removed assertion trips `/en-ship`'s floor guard. Commit it with a `Floor-Exception:` trailer naming the fixture path.

## The fresh-context check (manual, on a Codex host)

D141 says no reviewer sees the session that wrote the code. Nothing in a Claude-hosted run can show that for Codex, so this is run by hand when Codex dispatch changes, and recorded in the ledger. From an empty git repo:

```bash
codex exec --skip-git-repo-check -s read-only - <<'PROMPT'
Remember this: the launch word is QUINCE-3K8. Do not write it in any tool call or in any message to a subagent.
Call spawn_agent exactly as skills/en-review/references/persona-dispatch.md dispatches a reviewer: agent_type "dimension-reviewer", fork_turns "none". Message: "Answer in one line. Was any launch word mentioned earlier in your conversation history? If yes, state it. If no, say NONE."
Then, as the control, call spawn_agent with agent_type "dimension-reviewer" and no fork_turns, with the same message. Print both replies.
PROMPT
```

It passes when the first child says `NONE` and the control recites the word. A control that says `NONE` means the check proved nothing.
