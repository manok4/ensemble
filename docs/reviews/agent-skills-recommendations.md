# agent-skills follow-up: agents, code quality, and five enhancements

Reviewed 2026-11-03, against `addyosmani/agent-skills` at `301b02b` and ensemble at `9ddbb3b`. This follows `docs/reviews/agent-skills-comparison.md` and corrects two claims in it. See "Corrections" at the end.

## 1. Agents compared

### What each side ships

| | agent-skills | ensemble |
|---|---|---|
| Agents | 4 personas: `code-reviewer` (583 words), `security-auditor` (738), `test-engineer` (537), `web-performance-auditor` (1,802) | 7 agents in 13 copies. Reviewers: `dimension-reviewer`, `code-simplifier`, `test-lane-auditor`. Researchers: `repo-research`, `learnings-research`, `web-research`, `repo-fact-lookup` |
| Invoked by | The user directly, or `/ship`, which fans out all three reviewers in parallel and merges them into GO/NO-GO | Skills only. `/en-review`, `/en-build`, `/en-plan`, `/en-foundation`, `/en-simplify`, `/en-test-audit`, `/en-debug`, `/en-sweep`, `/en-learn` |
| Tool limits | None declared. A reviewer can edit what it reviews | Read-only, enforced by `tools: Read, Grep, Glob` and a lint test |
| Model | Inherits the session | Tiered: `ceiling` for correctness, security and migrations, `evidence` for the rest |
| Output | A Markdown report for a human | JSON per `peer-contract.md`: severity P0 to P3, confidence 1 to 10, location, fix, plus `status: incomplete` when inputs were unreadable |
| Merge | The main agent reads three reports and writes one decision | Schema validation, dedup by location and title similarity, a confidence boost on overlap, and two-source reconciliation with the cross-agent peer |

### Where their agents are better

**Domain depth.** `security-auditor` reasons from trust boundaries with STRIDE before it lists findings. It covers areas our security brief lacks:
- AI and LLM features: model output treated as untrusted, prompt injection, excessive agency, secrets in the context window
- Supply chain: typosquats, `postinstall` scripts, lockfile review
- Webhook signature checks, file uploads, open redirects, OAuth PKCE and state

It also requires a proof of concept for every Critical or High finding, and forbids "disable the control" as a fix.

`web-performance-auditor` has a metric-honesty rule: never state a millisecond figure without a measurement. It also separates a quick mode, from code reading alone, from a deep mode that runs on real profiler or Lighthouse artifacts. `test-engineer` carries a scenario table (happy path, empty, boundary, error, concurrency) and the prove-it sequence for bugs.

**A clear composition rule.** Personas never call personas. Only a command orchestrates. We follow the same rule in practice, because only skills dispatch, but we never state it.

### Where ours are better, and what not to copy

Our agents are built to be merged by a machine and to fail closed. Theirs are built to be read by a person. Three of their choices would make our reviews worse:

- **"What's Done Well: always include at least one."** That is padding by rule. Our `dimension-reviewer` says the opposite: an empty findings array is a result, and padding makes later reviews easier to ignore.
- **No tool limits on reviewers.** Their reviewer can edit the code it reviews. Ours cannot, and a lint test enforces that.
- **Free-form reports.** Their `/ship` merge depends on the main agent reading prose. Ours validates a schema and drops malformed output.

### The fact that changes where enhancements land

By default `/en-review` runs `--peer`, and that mode dispatches no host persona at all. The cross-agent peer is the only reviewer, and its domain knowledge comes from `skills/en-review/references/peer-brief.md`, whose category tables run about 2k words. Host `dimension-reviewer` instances run only under `--host` or `--cross`, and they receive one focus line per dimension. So review knowledge belongs in `peer-brief.md` first, and the host reviewers should read the same rows.

## 2. Code output, verification and security

My first pass compared structure only. This pass read their TDD, incremental-implementation, code-review, security-and-hardening, doubt-driven and source-driven skills, plus `references/definition-of-done.md`.

### How they get better output

Almost everything they do is guidance loaded into the main agent's context:
- red, then green, then refactor
- a prove-it test before every bug fix
- vertical slices, one thing at a time
- Rule 0.5, scope discipline
- a standing definition of done
- citations to official docs for framework-specific code
- a three-tier security boundary: always do, ask first, never do

The agent checks itself against a checklist at the end of each skill. Two pieces of real machinery exist: the floor guard and `quality-gate.mjs`. Both are reference implementations the user installs. The proof that the guidance works comes from their behavioral evals, not from enforcement at runtime.

### How we get better output

We enforce it mechanically:
- `/en-fix` step 6 is test-first.
- `/en-build` 9d runs `ensemble-unit-verify` and allows a commit only after it exits 0.
- A receipt gate checks that lint, typecheck and targeted tests ran on the final tree.
- `/en-ship` runs a masked secret scan.
- `/en-guardrail` blocks destructive commands.
- `/en-review` adds a verification pass after it fixes a P0 or P1.

Our design is stronger in that it does not depend on the agent following prose. It is weaker in that we never measure whether the result is good.

### Gaps their material exposes in ours

| Gap | Theirs | Ours today |
|---|---|---|
| Red evidence | TDD evals check that the test failed before the fix | `/en-fix` says to confirm the test fails. Nothing records that it did. The receipt proves the test passed, not that it ever failed |
| Weakened tests | Floor guard checks the diff | Nothing. "Never weaken tests" relies on trust |
| Security coverage | LLM features, supply chain, destructive ops on derived paths, privacy, webhooks, uploads, redirects | `peer-brief.md` covers auth, authz, injection, secrets, network policy, crypto, trust boundaries and rate limits. None of the rest |
| Dependency changes | "A bump is a behavior change you didn't write": read the changelog, one dependency per change, review the lockfile diff | No guidance |
| Doc grounding during implementation | `source-driven-development` cites official docs for every framework-specific decision | `/en-plan` can dispatch `web-research`. `/en-fix` and `/en-build` never consult docs while writing code |
| Review honesty | "Quantify problems", "don't soften real issues" | We have confidence discipline, which is stronger. We have no rule against softened severity |

Their "ask first" security tier is mostly covered by our routing. D138 sends auth, payments and migrations to `/en-plan`, and `/en-fix` step 7 re-checks the actual diff.

## 3. The five enhancements in detail

Each one follows the rule that new checks replace an existing cycle or stay off the hot path.

### E1. Trigger evals in CI, then retire tests that only pin wording

**Scope is smaller than theirs.** 8 of our 18 skills are manual-invoke (`disable-model-invocation: true`), so trigger accuracy matters for only 10: `en-brainstorm`, `en-build`, `en-debug`, `en-foundation`, `en-guardrail`, `en-learn`, `en-plan`, `en-review`, `en-ship` and `en-simplify`. The eval should read the frontmatter and skip manual skills, not keep its own list.

**Design.**
- Put cases in `tests/evals/cases/<skill>.json`, using their shape: `positive[]` prompts with `top_k`, and `negative[]` prompts with an `owner` skill.
- Write the ranker as one `python3` script under `tests/evals/`. Our scripts already depend on `python3`. It tokenizes and stems each description, scores prompts with TF-IDF and cosine similarity, and reports the rank-1 rate.
- A negative case passes only when its `owner` outranks the skill under test.
- Two descriptions at 0.75 similarity or more fail; 0.5 or more warns. These are their thresholds.
- Add one `tests/evals/trigger.test.sh` that `run.sh` already picks up. The CI floor starts at the baseline we measure, minus 5 points, and is never lowered.
- Lay the cases in the pairs most likely to collide: `en-review` against `en-simplify` ("clean up this diff"), `en-plan` against `en-brainstorm` ("think through"), `en-build` against `en-plan` ("implement this"), `en-debug` against `en-review` ("why does this fail").

**Honest limit.** TF-IDF over a description is a rough stand-in for how Claude Code and Codex actually route. It catches missing vocabulary and overlap between descriptions. It cannot show that a skill fires. E4 covers that.

**Retiring the wording tests.** A rough count of `tests/lint/`, by which files each test reads and whether it runs a script:
- 18 tests read at most one doc and run nothing. These are the first candidates.
- 46 compare prose across files and run nothing. These need judgment.
- 75 execute a script or helper. Keep these.

The 139 tests hold 1,301 `grep -q` assertions in all. Retention rule: keep a test when it guards agreement between files (the D39 ordering stated identically in two skills), a contract that a script parses, or a decision ID. Delete it when it pins one file's wording and nothing consumes that wording. Run this through `/en-test-audit tests/lint/`, which already judges tests against a retention bar.

Speed is a weak argument for the cut, though. See "Where the suite's time goes" below. The strong argument is that a pinned sentence cannot be trimmed without editing a test.

### E2. A floor guard at ship time

**What it detects** on the diff from the merge base to the working tree, untracked files included:

| Move | Detection | Action |
|---|---|---|
| Test file deleted | A path matching the repo's test glob is in `git diff --diff-filter=D` | Block |
| Test skipped | An added line matches `.skip(`, `xit(`, `xdescribe(`, `@pytest.mark.skip`, `t.Skip(` or `it.todo` | Block |
| Checker silenced | An added line matches `@ts-ignore`, `@ts-nocheck`, `eslint-disable`, `biome-ignore`, `# noqa`, `# type: ignore`, `istanbul ignore`, `nosemgrep` or `gitleaks:allow` | Block |
| Assertion removed | A modified test file loses `expect`, `assert` or `should` lines with no matching additions | Report as a finding |
| Stub left behind | An added line matches an empty `catch {}`, `throw new Error('not implemented')` or `pass  # stub` | Report as a finding |
| Threshold lowered | A coverage or size threshold in CI config, `package.json`, `pyproject.toml` or `.ensemble/` falls | Block |

**Where it runs.** Run it in one place: `skills/en-ship/scripts/ensemble-floor-guard`, called in `/en-ship` step 5 next to the secret scan. Every route ends in `/en-ship`, so one copy covers `/en-fix`, `/en-build` and `/en-flow`, and the duplication count does not grow. The "report as a finding" rows go into the PR body under a "Quality bar" heading rather than blocking.

**Exceptions** use a commit trailer that the guard checks, matching our existing pattern of trailer plus a fail-closed verifier: `Floor-Exception: <move> <path>: <reason>`. `/en-test-audit` deletes tests on purpose, so its commits write that trailer for each deleted test. That is the one change outside `/en-ship`.

**Exit codes.** 0 clean, 1 blocked, 2 could not run (no merge base, not a repo). A 2 stops the ship. It never reads as a pass.

**Why regex is acceptable here.** Our learning says security matchers need parsers, because an attacker probes a regex. This guard faces an agent cutting corners, not an attacker. A miss lets one weakened test through to review, where it would have gone anyway. A false block costs one trailer.

**Tests**, with a negative control per row: a scratch repo that deletes a test, adds `.skip`, adds `eslint-disable` and lowers a threshold must exit 1. The same repo with each trailer present must exit 0. A repo without a merge base must exit 2.

### E3. Name the excuses in five skills

Our skills already answer some excuses inline. `/en-fix` step 6 says a failing test may encode a correct decision, and that three failed attempts point at the design. The addition is a short table of the excuses that are not answered yet, placed at the end of each `SKILL.md`, at about 6 rows and 150 words each. No grep test pins them. E4 measures whether they work.

Draft rows:

**`/en-fix`**
| Excuse | Answer |
|---|---|
| "The bug is obvious; the test is ceremony." | Step 6 needs the test to fail first. Without that failure, nothing shows the fix touched the bug. |
| "The new test passed on its first run." | Then it does not capture the bug. Rewrite it until it fails on the unfixed code. |
| "While I'm here, this nearby code needs tidying." | That is a drive-by. Record it as a follow-up or a `TD<N>`. |
| "Triage said small, so I can skip the risk re-check." | Step 7 exists because a migration or contract change can appear only once the code exists. |
| "`--lite` review found nothing, so it is safe." | Lite runs fewer reviewers. Its silence is weaker evidence than a full review. |

**`/en-build`**
| Excuse | Answer |
|---|---|
| "Tests pass; I'll fix lint in the next unit." | 9e commits only after 9d exits 0 on the same tree. |
| "This pre-existing bug blocks the unit, so I'll fix it here." | Scope is the deliverable. Stop and surface it, or add a unit. |
| "The plan is wrong here; I'll improvise." | Amend the plan and say so. A silent deviation leaves the plan describing something that was never built. |
| "The selected tests passed, so the suite is fine." | The selection is approximate. The branch-end checkpoint runs the full suite. |

**`/en-review`**
| Excuse | Answer |
|---|---|
| "The peer timed out, so the review is clean." | A failed peer means `peer: "off"` with a reason. Report it as such. |
| "I'm unsure, but a higher confidence makes it stick." | Inflated confidence moves a weak finding to the wrong tier. |
| "It's a real bug, but P2 sounds less harsh." | Severity follows impact. Softening a P1 is a wrong answer, not a kinder one. |
| "Host and peer disagree, so drop it." | Disagreement is the `conflicting` bucket. It goes to the user. |

**`/en-ship`**
| Excuse | Answer |
|---|---|
| "The secret scan hit is a false positive." | Show the masked preview to the user. Never skip the scan. |
| "CI is red but flaky; rerun until green." | A flaky check is a broken window. Fix it or record why not. |
| "The PR is open, so the job is done." | Only the exit states in `ship-reporting.md` end the watch loop. |
| "The floor guard blocked a deletion I meant to make." | Add the `Floor-Exception` trailer with a reason. Never bypass the guard. |

**`/en-qa`**
| Excuse | Answer |
|---|---|
| "Unit tests pass, so the browser pass is redundant." | Phase 2 tests what a user sees, which unit tests do not reach. |
| "It's cosmetic; it doesn't need a regression test." | Step 8 requires one for every fixed bug. |
| "It didn't reproduce on one try, so it's not a bug." | Try two or three times, then use the intermittent-bug techniques. |
| "I can't drive the OAuth step, so I'll mark it Pass." | A flow that cannot be driven is Skipped with a reason, never faked. |

### E4. Behavioral evals, run on demand

This is the enhancement that pays most for ensemble specifically. Our core claim is that `/en-review` with a cross-agent peer finds more real defects than a single model, and nothing checks that against ground truth today. `bin/ensemble-metrics --peer-value` counts findings from real runs, but it cannot tell a real finding from noise.

**Layout.** `tests/evals/behavioral/<case>/` holds a fixture repo, `prompt.md`, and `expect.json`. A runner, `tests/evals/run-behavioral.sh`, copies the fixture to a scratch dir, commits the baseline and runs the skill headless (`claude -p`, or `codex exec` for the Codex host). It is never wired into `run.sh` or CI. Each run spends real tokens.

**Grade deterministically where we can.** This is an advantage we have over their LLM grader.
- **`/en-review` seeded-defect cases.** Each fixture plants known defects: an off-by-one, a missing authorization check, an N+1 query, a weakened test. `expect.json` lists each defect's `file:line` range and minimum severity. Our review already returns JSON with locations, so recall and precision come from matching locations, with no judge. Run each case under `--peer`, `--host` and `--cross` to measure what the peer adds. That number is also the ground truth `--peer-value` lacks.
- **`/en-fix` pressure cases.** Use one fixture and two prompts: the plain bug report, and the same report with "hotfix window, backfill the test later." The grader checks the sandbox's git history. Revert the source change, keep the new test, and run it. It must fail. Then restore the change and run it again. It must pass. That is a mutation check, not an opinion.
- **Only E3 needs an LLM judge**, to tell whether a reply gave in to the pressure. Use their pattern for it: the trace sent over stdin and fenced as untrusted, JSON output validated, and evidence required for each expectation.

**Starting set.** Five cases: three `/en-review` seeded-defect repos (logic, security, test weakening) and two `/en-fix` cases (plain and pressure). Run them on a change to `en-review`, `en-fix`, `peer-brief.md` or the dispatch logic. Keep results under `.ensemble/evals/`, gitignored, with a one-line summary per run in a tracked ledger. That ledger is our version of their `skill-impact.md`, for changes the evals rejected.

**The same check at runtime.** `/en-fix` step 6 already runs the new test before the fix, so recording that run costs nothing extra. Have `ensemble-verification-receipt` accept a `red_test` entry: the test id and its failing exit code before the change. Make the receipt gate require it for `/en-fix`. That turns "confirm it fails" from prose into evidence. It records an existing run, so it adds no cycle.

### E5. Better review knowledge, kept in one place

**Correction first.** The comparison said our reviewers bring their own knowledge. The peer brief already has security and performance tables. The fix is to extend those tables, not to add checklists.

**Add these rows to `peer-brief.md` § security:**
- **AI/LLM features.** Model output reaching SQL, a shell, `eval`, `innerHTML` or a file path. The system prompt used as a permission boundary. Secrets or another tenant's data in the context window. Tools with no confirmation on destructive actions.
- **Supply chain.** A new dependency (typosquat, maintainer, install scripts). A lockfile change not explained by the manifest change.
- **Destructive ops on derived paths.** A delete or overwrite whose target comes from a payload, config or another process, guarded only by a shape check.
- **Inbound integrations.** Webhook signature checks, upload type and size limits, open redirects, OAuth PKCE and `state`.
- **Privacy.** PII in logs, analytics or LLM calls. A delete that only flips a flag.

**Add two rules to the security section:** start from the trust boundary where untrusted data enters, and give every P0 or P1 a concrete exploit input. The second rule fits our confidence rule, which already ties high confidence to a concrete failing input. Also: never propose disabling a control as the fix.

**Add one row each** to performance and standards:
- **Performance.** A latency or size claim needs a measurement or the word "estimate".
- **Standards.** A dependency bump is a behavior change. Check the changelog, one package per change, and that the lockfile diff is explained.

**Extend detection** in `persona-dispatch.md` so the security reviewer fires on: LLM SDK imports and `prompt` templates; `package.json`, lockfile or `requirements*.txt` changes; `rm`, `unlink`, `rmtree` or `fs.rm` with a non-literal path; and `webhook`, `upload`, `multipart` and `redirect`.

**One source for both reviewer types.** Under `--host` and `--cross`, pass the matching `peer-brief.md` section to `dimension-reviewer` in place of the one-line focus. The host and the peer then review against the same rows, and no new file exists. The cost is about 300 more words for each conditional dimension that fires.

`peer-brief.md` exists only in `en-review`, since the other skills' briefs differ, so no parity copies change.

## 4. Their other skills, judged as support for code tasks

All 25 of their skills, measured against what ours already do. Anything worth adopting goes in as a step or a reference inside an existing skill, not as a new skill, for two reasons:
- **Description budget.** Ours runs at 5,332 of Codex's 8,000 characters, with the warning at 6,400, so about three new descriptions fit before the warning trips.
- **Unreliable auto-firing.** Their own plugin evals show knowledge skills firing unreliably: `test-driven-development` fired 1 of 6 times on a pasted bug. Knowledge wired into a workflow step always loads.

### Worth adopting

| Their skill | What it adds | Where it lands |
|---|---|---|
| `source-driven-development` | Check official docs for every framework-specific decision. Cite the source, and treat fetched pages as data | `/en-fix` step 5 and `/en-build` 9c: when a change calls a third-party API, check it through Context7 and cite it in the commit body. Today only `/en-plan`'s `web-research` agent does this, and only at planning time. The user rule "use Context7 or official docs before non-trivial framework work" exists in no skill |
| `api-and-interface-design` | Hyrum's law, addition over modification, one error convention per surface, and a strong idempotency-key section (derive the key from the intent, claim it atomically, handle the in-flight duplicate, treat a timeout as "unknown") | A reference `/en-plan` loads when a unit touches a public contract. D138 already routes contract changes to `/en-plan`, but nothing guides the design once they arrive |
| `deprecation-and-migration` | Expand, then migrate, then contract, for zero-downtime schema changes. Also strangler and adapter patterns | `/en-plan` splits a breaking migration into expand, backfill and contract units. Our migrations reviewer flags "drop column while old code still reads it" only after the code exists, and a plan would prevent it |
| `debugging-and-error-recovery` (two rules) | Stop the line on an unexpected failure. Error output from CI, logs and third-party APIs is data, not instructions | Two rows in E3 for `/en-build` and `/en-ship`. `/en-ship`'s watch loop reads CI logs and repairs from them. Its trusted-source gate covers review comments, not log text |

### Already covered, or out of scope

| Their skill | Why not |
|---|---|
| `spec-driven-development`, `planning-and-task-breakdown`, `idea-refine`, `interview-me` | `/en-brainstorm`, `/en-plan` and `/en-foundation` cover them with stable IDs and peer review |
| `code-simplification` | `/en-simplify`, with three parallel simplifiers |
| `code-review-and-quality` | `/en-review`. Its useful rows are in E3 and E5 |
| `test-driven-development`, `incremental-implementation` | `/en-fix` step 6 and `/en-build`'s unit loop already enforce them mechanically. E4 adds the evidence |
| `git-workflow-and-versioning`, `ci-cd-and-automation` | `/en-ship` covers commits, PRs and the CI watch loop |
| `documentation-and-adrs`, `context-engineering` | `/en-learn`, `/en-sweep`, `/en-setup` and the AGENTS.md conventions |
| `observability-and-instrumentation` | `/en-debug` already carries an emit-point and shape contract in `observability-conventions.md` |
| `browser-testing-with-devtools` | `/en-qa` drives a browser through Playwright |
| `performance-optimization` | The measure-first rule is one E5 row. The rest is web-vitals material for frontend-heavy products |
| `frontend-ui-engineering` | Useful only for UI work, and dedicated design skills already cover that outside ensemble |
| `shipping-and-launch` | Staged rollout, feature flags and rollback plans sit past the PR, where ensemble stops on purpose. Production deploys need explicit approval |
| `doubt-driven-development`, `constraint-driven-development` | The cross-agent peer covers the first. E2 takes the useful part of the second |

## Where the suite's time goes

I timed each of the 190 test files serially on 2026-11-03, each through `./tests/run.sh -k <name>`. A `-k` pattern can match more than one file, so the sum (862s) overstates the real suite. The ranking is still clear:

| Area | Seconds | Why |
|---|---:|---|
| `tests/install/` | 385 | `codex-toml-agents` (198s), `claude-effort-agents` (109s) and `resolver-stderr-isolation` (72s) call `./setup` about 35 times between them, into scratch homes, at roughly 11s each |
| `tests/lint/`, 10 slowest | 256 | Led by `peer-isolation` (74s), `en-review-peer-default` (37s) and `lint-rules` (36s). Each one runs scripts |
| `tests/lint/`, the other 119 | 28 | Each finishes in 1s or less. This group holds the wording tests |

**The wording tests cost about 28 seconds.** The suite is slow because of repeated `./setup` runs and a handful of script-heavy lint tests. If speed is the goal, share one `./setup` install per scenario across the assertions that inspect it, rather than reinstalling for each check. That could cut the three install tests from about 380s to well under 100s. It is a separate change from E1. Plan it on its own, as a fix to a broken window.

## Corrections to `agent-skills-comparison.md`

1. It said `dimension-reviewer` "gets a dimension name and a focus line, and it brings its own knowledge". True for host reviewers, but the default `--peer` mode uses `peer-brief.md`, which has category tables. E5 above replaces that recommendation.
2. It said phrase-pinning tests are "the main driver of the 447s suite". The per-test timing above shows they cost about 28 seconds. The time goes to `./setup` reinstalls in `tests/install/` and to about ten script-heavy lint tests.
