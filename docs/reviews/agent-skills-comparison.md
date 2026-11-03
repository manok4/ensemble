# Comparison: addyosmani/agent-skills against ensemble

Reviewed 2026-11-03. Detailed designs and two corrections are in `docs/reviews/agent-skills-recommendations.md`. Source: `github.com/addyosmani/agent-skills` at `301b02b` (2026-11-01), 418 commits since 2026-08-01. Ensemble at `9ddbb3b`.

## The two repos solve different problems

agent-skills is a catalog of engineering judgment. Its 25 skills each teach one discipline (TDD, API design, security hardening, observability, deprecation) through a fixed anatomy: when to use, process, a table of common rationalizations, red flags, and an exit checklist. Four review personas and nine slash commands sit on top. It has almost no runtime machinery.

Ensemble is a workflow engine. Its 18 skills drive multi-step runs with plan IDs, cross-agent peer review, fail-closed verifiers, run ledgers and guardrail hooks. Most of its weight is orchestration, and that machinery is the product.

So "they have more skills" is not the finding. What matters is where their engineering practice beats ours, and what that says about our footprint.

## Size at a glance

| Measure | agent-skills | ensemble |
|---|---|---|
| Skills | 25 | 18 |
| `SKILL.md` words, total | about 55k | 47.6k |
| Reference and template words | about 25k | 166k |
| Agent/persona words | 3.7k | 8.9k |
| Skill scripts | a few small files | 103 files, 28.5k lines |
| Byte-identical copies under `skills/` | none | 147 files, 1.44 MB of 2.9 MB |
| Description characters, always loaded | 9,568 | 5,332 |
| Tests | node `--test` suites, seconds | 190 `*.test.sh`, about 447s |
| Tests proving a skill fires or changes behavior | yes, three tiers | none |

## Where they outperform us

### 1. They measure whether skills work. We measure whether sentences exist.

This is the largest gap. Their `evals/` has three tiers:

1. **Structural lint** runs in CI. It checks frontmatter, a 500-line `SKILL.md` budget (warning only), reference links, command parity across hosts, and manifest versions.
2. **Trigger and routing evals** also run in CI, and they are deterministic. Every skill ships `evals/cases/<skill>.json` with at least 3 positive prompts and 2 negative ones. A stemmed TF-IDF ranker checks that each positive prompt ranks its skill first. CI fails below a 95% rank-1 rate, against a checked-in baseline of 100%. A negative prompt names its `owner` skill, and the runner asserts that the owner outranks the skill under test, so a negative case cannot pass by matching nothing. Two descriptions at 75% or more similarity fail the build.
3. **Behavioral evals** run on demand. Each case runs headless `claude -p` in a throwaway git repo seeded from `evals/fixtures/` (28 fixtures). An LLM grader then checks `expectations[]` against the full tool-call trace. The discipline skills add pressure cases that argue for skipping the workflow: "the tech lead says it's a one-liner, the hotfix window closes in ten minutes, backfill tests next sprint."

On top of those, `claude plugin eval` cases score each prompt with and without the plugin and report the delta. Their results are concrete. A description fix took code-simplification from 0 of 9 fires to 8 of 9. A ledger, `evals/skill-impact.md`, records the changes that evals rejected.

Ensemble has nothing like this. 101 of our 139 lint tests `grep` a `SKILL.md` for a literal phrase: "Preflight gate summary", "two narrow categories", "performance > speed ≥ cost". Those tests catch accidental deletion. They cannot tell us whether `/en-review` finds the bug, whether `/en-fix` holds up under time pressure, or whether a description change made a skill fire less. They also make the code heavier. Every pinned sentence is one we cannot cut without editing a test, which works against the trim pass we want.

### 2. Their tests are fast

Their CI is a set of `node --test` files plus two validators, and it finishes in seconds. Our suite takes about 447s, and AGENTS.md already records branches losing time to it. Per-test timing later showed the wording tests cost about 28s; repeated `./setup` runs in `tests/install/` cost the most. See `agent-skills-recommendations.md`.

### 3. Uniform skill anatomy, with anti-rationalization built in

Every skill of theirs closes with "Common Rationalizations | Reality", "Red Flags" and "Verification". `docs/skill-anatomy.md` documents the shape and the lint enforces it. Only 1 of our 18 skills has a rationalization or red-flags section. Our skills state rules. Theirs also name the excuse an agent will reach for and answer it, and the pressure evals check that the answer holds. That is the cheapest robustness gain available to us, because it is prose and needs no machinery.

### 4. A guard against weakening the quality bar

`constraint-driven-development` ships `references/floor-guard.md`. It is a diff-scoped checker for five ways an agent lowers the bar: a threshold edited down, a test skipped or deleted or stripped of its assertion, a new suppression comment (`@ts-ignore`, `eslint-disable`), a stub or empty `catch`, and a new exceptions row. Exit 2 means "could not run" and never reads as clean, which matches our own fail-closed rule.

Nothing in `/en-review` or `/en-build` checks for this. Only `en-test-audit/references/ledger-format.md` mentions skipped tests. "Never skip, weaken, or disable tests" is a top-level user rule, and we enforce it only by trusting the agent.

### 5. Breadth of engineering knowledge

They cover security hardening, performance, API and interface design, frontend UI, observability, CI/CD, deprecation and migration, ADRs and context engineering. They back these with shared checklists under `references/` (security 2k words, performance 2.1k, accessibility, observability, definition of done).

Our host `dimension-reviewer` gets a dimension name and a focus line. The default `--peer` mode instead sends `peer-brief.md`, which already has security and performance tables, though they lack LLM, supply-chain and privacy rows. Their checklists are a concrete standard a reviewer can be held to. I would not import these as skills, since 25 more descriptions would blow our description budget. I would add their missing rows to `peer-brief.md` and have host reviewers read the same rows.

### 6. Description discipline backed by data

Their descriptions follow a rule they have measured: say what the skill does and when to use it, never summarize the workflow, and name the literal requests that should trigger it, "even when the code is pasted inline." They found that process-shaped descriptions fire on process-shaped prompts and miss the plain ones ("fix this bug", "write a commit message for this diff"). We have never tested our descriptions against real phrasing.

### 7. Contributor scaffolding

They have a skill-anatomy guide, `CONTRIBUTING.md`, a `skill-gap` issue template, and a CI rule that a new skill without an eval case file fails. Ours lives in AGENTS.md and the foundation doc, which is fine for one maintainer. It will not scale to outside contributors.

### 8. Host portability

They document and test about ten hosts: Claude Code, Codex, Gemini CLI, Cursor, Copilot, Windsurf, OpenCode, Antigravity and others, and `validate-commands.js` keeps the command copies in sync. We support two hosts, by design. This only matters if ensemble aims beyond the Claude Code and Codex pair.

### 9. Small, tested hooks

`sdd-cache` caches doc fetches but revalidates with `If-None-Match` on every reuse, so a cache hit is still a fresh check. `simplify-ignore` hides annotated blocks from the simplifier. Each hook ships its own test script.

## Where we are ahead, briefly

- **Cross-agent peer review.** Their "multi-model review" is a paragraph of advice. Ours is a protocol with a contract, a receipt and trailers.
- **Fail-closed audit trails.** Plan IDs, verification receipts and peer-resolution trailers have no counterpart there.
- **Guardrail hooks.** They have no destructive-command protection.
- **Knowledge store and metrics.** `/en-learn`, `/en-sweep` and `bin/ensemble-metrics` have no equivalent.
- **Description budget.** Our lint holds the always-loaded list under Codex's 8,000-character budget. Their 25 descriptions total 9,568 characters, over that budget, so Codex likely truncates part of their catalog. Their `AGENTS.md` also tells OpenCode to invoke a skill at "even 1% chance". That is a heavy router, and their own docs warn against it on Claude Code and Codex.

## Bloat assessment

1. **Reference weight.** We carry 166k words of references against their 25k. The references load on demand. For example, `run-metrics.md` (2k words) is a pointer that loads only when a contract question comes up. So the context cost per run is lower than the raw total suggests. But every reference is something an agent may open and a maintainer must keep current. The largest ones: `persona-dispatch.md` 2.6k, the plan template 2.6k (two copies), `linear-publish.md` 2.4k, `build-preflight.md` 2.3k.
2. **Duplication.** Half the bytes under `skills/` are byte-identical copies. The largest are `ensemble-run-metrics` (30 KB ×11), `ensemble-config-get` (×12), `run-metrics.md` (13 KB ×11), `ensemble-peer-invoke` (40 KB ×4) and `script-invocation.md` (×16). Self-contained skills are a deliberate trade, and I am not proposing to consolidate them. But each kilobyte trimmed from one of these files saves ten or more copies, so the planned per-skill trim pass gets the most per edit by starting here.
3. **Tests as dead weight.** Some phrase-pinning tests guard real cross-file invariants, such as D39 stated identically in two skills. Many only pin wording. Those tests are the main thing that makes prose expensive to cut. They are not what makes the suite slow: they run in about 28s in total.
4. **Per-skill size is on par.** Our `SKILL.md` files average 2.6k words against their 2.2k, all well under their 500-line budget. The excess lives in references, scripts and copies.

## Recommendations, ranked

Each one follows our rule that new checks replace an existing cycle or stay off the hot path.

1. **Add trigger and routing evals, and retire phrase-pinning tests as they become redundant.** A deterministic ranker over 18 descriptions, plus 3 positive and 2 owner-tagged negative prompts per skill, runs in CI in seconds. Run it under the existing doc-lint job. Then audit the 101 grep tests with `/en-test-audit tests/lint/`. Keep those that guard cross-file invariants and delete those that only pin wording. Net effect: prose we can trim, and real coverage.
2. **Add a floor guard to the review path.** Have `/en-review`'s testing dimension, or `/en-ship` preflight, run one diff-scoped script that detects skipped or deleted tests, stripped assertions, new suppressions and edited-down thresholds, with exit 2 as fail-closed. It replaces a judgment call that reviewers make today without help.
3. **Add a rationalizations and red-flags block to the five skills that bend under pressure:** `/en-fix`, `/en-build`, `/en-review`, `/en-ship`, `/en-qa`. This is prose only, at about 150 words a skill.
4. **Write two or three behavioral pressure cases with fixtures.** Start with `/en-fix` under "skip the test, hotfix window." Run them on demand, never in CI. One case that fails would teach us more than any number of grep tests that pass.
5. **Extend the review brief.** Add the missing security, performance and standards rows to `peer-brief.md`, and pass the same section to host reviewers. Do not add new skills or new checklist files.
6. **Trim the most-copied files first** in the planned trim pass: `ensemble-run-metrics`, `ensemble-config-get`, `run-metrics.md`, `script-invocation.md`.

Not recommended: adopting their catalog breadth as new skills, or a session-start router. Both add always-loaded context, and our narrower catalog routes cleanly under the Codex budget.
