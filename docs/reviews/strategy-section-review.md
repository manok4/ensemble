# The `vision` skill and an Ensemble strategy section

Review date: 2026-11-24
Skill studied: `kunchenguid/vision` @ `acf4d65` (one commit, repo created 2026-08-09)
Sample repository: `kunchenguid/no-mistakes`, `VISION.md` as of 2026-11-22
Ensemble revision: `main` @ `f0dd93b`

---

## 1. What the skill does

`/vision` writes one document: a project vision phrased as an acceptance policy.
It goes in `VISION.md` when the repo already has one, otherwise in a `## Vision` section of `STRATEGY.md`, created if missing.
The skill touches nothing else in `STRATEGY.md` and only proposes edits to sections that repeat the vision.

The pipeline has seven steps.

1. **Parse target and author.** The author defaults to the repo owner, whose merged work is the evidence.
2. **Pick the target.** `VISION.md` wins, then `STRATEGY.md`, then a new `STRATEGY.md`. An existing vision switches the run to delta mode, which proposes only line-level changes backed by evidence newer than the baseline.
3. **Mine evidence.** 30 to 100 merged PR titles and 8 to 15 full bodies via `gh`, falling back to `git log`. The output is a private evidence sheet mapping each value to PRs, commits or files. With no readable history the skill stops rather than invent values.
4. **Draft.** A fixed anatomy, 40 to 70 lines: an identity opener ("X exists so that ... It owns exactly one thing"), 3 to 6 principle sections, a concrete Scope with non-goals, and a closing pair, "A change aligns when ..." and "A change should be resisted when ...".
5. **Hypotheticals.** 8 to 12 proposals aimed at the draft's fault lines: tempting off-mission features, principle collisions, slippery slopes, scope expansions, open identity questions. Each one steelmans both sides. A hypothetical whose answer the agent can predict gets replaced.
6. **Review board.** A fixed HTML template and stylesheet (12.5KB), served by `npx -y lavish-axi`, shows the full draft beside a stack of cards. The author gives a verdict per card; the agent folds the reasoning into the prose and replies with a changelog line per verdict. It loops until the author approves.
7. **Finish.** Write the approved text, add `<!-- vision: author-approved YYYY-MM-DD -->` in section mode, apply only the consolidation edits the author said yes to, and confirm no answers file or transcript lands in the repo.

### What is good

- **Evidence over vibes, enforced by a stop.** Refusing to run without real history is the right failure mode. Ensemble's `/en-foundation` greenfield path has nothing like it, and its retrofit path reads code, not the author's merge history.
- **The hypothetical stress-test.** "Delete any hypothetical whose answer you can predict" is a sharp quality bar. It produces the lines that matter most in the no-mistakes sample, such as the refusal to ever send a run backward through completed steps.
- **The output is testable.** The aligns/resisted pair is written so a reviewer, human or agent, can apply it to a single PR. That is the property most product docs lack.
- **Hands off other writers' text.** The rule that every byte outside the Vision section stays unchanged, with consolidation proposed one edit at a time, is a careful contract for a shared file.

### What is weak

- **Authoring only, no consumption.** The skill writes the policy and stops. Nothing in it makes a planner, builder or reviewer read the vision, and nothing detects a change that violates it. The value of the document depends entirely on other tooling.
- **No stable IDs.** Principles are unnumbered prose. no-mistakes code already cites VISION.md rules by number, rule 1 and rule 4 (`internal/pipeline/steps/review.go:525`, `.agents/skills/repository-routing-security/SKILL.md`), and the file numbers nothing. Citations to the vision are already unresolvable.
- **Unpinned runtime dependency.** The board runs `npx -y lavish-axi` with no version pin, fetching and executing third-party code on every run. That conflicts with Ensemble's install model and its guardrail posture.
- **Immature.** One commit, no tests, no evals for triggering or output quality.
- **Root-level file.** `STRATEGY.md` at the repo root breaks the `docs/` convention Ensemble and its adopting repos follow.

## 2. The sample: no-mistakes `VISION.md`

67 lines, 7 sections: an identity opener, six principle sections ("One gate, one meaning", "Never lose work", "Judgment stays human, mechanics do not", "The pipeline runs forward", "Independent, adversarial validation", "Evidence over confidence", "Humans and agents are both first-class users") and "Scope and evaluation" with the aligns/resisted pair.

What it does well:

- **Refusals are explicit and reasoned.** "Neither a deterministic boundary on what a step may touch nor a rigid guard bolted on after it belongs in the gate" comes with its reason, so a reviewer can apply it to a PR that proposes such a guard.
- **It states priorities between principles.** "A refused push is annoying, a lost commit is unforgivable" settles a safety-vs-convenience collision in one line.
- **It changes with the code.** Five commits since 2026-07-20, two of them inside feature PRs (#819 the PR enforcement action, #887 CI repair continuity). Feature work amends the vision in the same PR, which keeps it current.
- **Code cites it.** Config defaults and review logic point at it in comments (`internal/config/config.go:885`, `:906`, `:936`), and a repo skill rejects a design because it would "contradict VISION's never stacked".

Where it strains:

- **Sentence length.** "One sentence per line" produced lines of 60 to 80 words, such as the cost rule and the deterministic-guard rule. They are hard to quote or test.
- **The citation problem above.** The repo wants to reference individual commitments and has no IDs to do it with.
- **Accretion.** "The pipeline runs forward" has nine lines, several of which read as incident fixes written up as policy. The 40 to 70 line target is holding, but only just.

## 3. What Ensemble has today

Ensemble's strategy-level content lives inside `docs/foundation.md`, which is 1,928 lines and never read whole (`en-plan` and `en-brainstorm` read a section index, then one or two sections).
The relevant parts are §1 Executive Summary, §2 Goals and Non-Goals, §3.3 Out of scope, and §17 Operating Philosophy, with 140-odd D-IDs in §4.1 carrying the decisions.

Three gaps follow.

1. **The principles have drifted and nothing noticed.** §1 says "an 11-skill, 11-agent toolkit"; `skills/` holds 18. D9 and the line "No telemetry. No analytics events on skill invocation." still stand while D106 and D129 make every sustained skill write a run record to `~/.ensemble/analytics/<repo>.jsonl`. That ledger is local and may be fine, but the principle was never amended to say so. The D-IDs are maintained because each change writes one; the principles are not, because no change is ever checked against them.
2. **No review checks product alignment.** `en-review`'s peer brief checks plan coverage, including "Unasked-for: scope the plan did not authorize" (`skills/en-review/references/peer-brief.md:33`). That is scope against the plan, not against the product. An `/en-fix` run has no plan, so it gets no alignment check at all. A change that quietly turns `/en-conductor` into something that merges is caught only because D143 happens to have tests.
3. **No short, loadable accept/resist test.** An agent that wants to know "should Ensemble do this?" must find it across four sections of a 1,928-line file. §17 states principles but not the resist side.

## 4. Recommendation

Do not install `/vision` as an Ensemble skill or adopt a root `STRATEGY.md` or `VISION.md`. Take its document shape and its stress-test, call the result a **strategy**, give its principles stable IDs, and wire a consumption path into the skills that already run. The consumption side is where the value is, and the external skill does not have one.

"Strategy" over "vision" because the section is an acceptance policy: what the project owns, what it refuses, and how to judge a change. That is strategy in the plain sense, and it keeps one word for one concept across the docs.

Concretely, in priority order:

1. **A `Strategy` section in `docs/foundation.md`, with stable IDs.** Retitle §1 "Strategy" and give it the `/vision` anatomy: identity opener, 3 to 6 principles numbered `ST1..STn` (append-only, never renumbered, like R- and D-IDs), concrete non-goals, and the aligns/resisted pair, capped at about 70 lines. The first line under the heading is `<!-- strategy: author-approved YYYY-MM-DD -->`, which gives skills a mechanical way to find it and tells delta runs where the baseline starts. `ST` is free in `references/stable-ids.md`; a bare `S` would collide with "S3" in adopting repos, and `P` is taken by the P0 to P3 severities. Fold §2.2 non-goals and the testable parts of §17 into it so there is one source, not two. Keeping it in foundation rather than a new file preserves G2 (one foundation document).
2. **Consume it in the review that already runs, without adding a persona.** Pass the aligns/resisted pair into `en-review`'s existing peer prompt next to `--goal`, and add a "Strategy" row to the peer brief that titles findings `Strategy: ST<N> ...`. This covers `/en-fix` changes, which have no plan. It replaces nothing and adds no dispatch, which matches the rule that new checks stay off the hot path. `en-plan` intake reads the same section and names the ST-IDs a plan touches, the way it names R-IDs.
3. **Borrow the stress-test into `/en-foundation`.** Mine merged PR or commit history for revealed values, then run 8 to 12 fault-line hypotheticals through `AskUserQuestion`, one at a time, before the draft goes to the peer. No HTML board and no `lavish-axi`. Carry the "replace any predictable hypothetical" rule word for word. The same flow runs in delta mode when the section exists, which is how a strategy gets revised later.
4. **Drift detection in `/en-sweep`.** Add a check that a strategy line's factual claims (skill counts, "no telemetry") still match the repo, and a lint that an `ST<N>` cited in code or docs exists. That fixes the problem no-mistakes already has with its numbered citations.
5. **Amend the strategy in the PR that changes it.** no-mistakes does this and it is why its vision stays current. A change that `en-review` flags under an ST-ID either changes course or amends the ST line with a D-ID that says why.

This needs a plan, since it has open decisions (the ST-ID lint severity, whether `/en-fix` triage reads the strategy), touches five skills and changes `en-review`'s peer contract. Start with `/en-plan`. A useful first unit is writing Ensemble's own strategy section by hand from §1, §2, §17 and the D-ID history, which tests the anatomy on a real repo before any skill changes.

## 5. Retrofitting repos that already run Ensemble

Skill changes reach every repo on their own: the skills install once per machine (`./setup`, the plugin), so a new `en-review` brief is live everywhere the moment it ships. What does not arrive is the per-repo artifact, the Strategy section itself. The retrofit question is who writes it and who notices it is missing.

### Neither `/en-sweep` nor `/en-setup` should write it

- **`/en-sweep` is the wrong writer.** It runs unattended from launchd through `codex exec`, is doc-only, and auto-merges its own PR once review clears it. A strategy is the author's judgment, and the stress-test needs the author answering questions. An unattended agent that drafts a repo's principles and merges them inverts the rule the whole idea rests on: the author owns the strategy.
- **`/en-setup` is the wrong writer too.** Its hard rule is "mechanical setup work, no implementation", and it hands anything ambiguous to `/en-foundation`. It already has the exact precedent: for a legacy learning store it detects, reports, and hands off to `/en-learn` rather than migrating itself, because entries need a human.

### Who does what

| Role | Skill | Change |
|---|---|---|
| Write and revise | `/en-foundation --strategy` | A new mode scoped to the Strategy section: mine history, draft, stress-test, peer-review the draft, write the section in place. Delta mode when the marker exists. It replaces §1's body, leaves §2.2's heading with a one-line pointer to §1 so existing §-references still resolve, and proposes each other consolidation edit for a yes or no, as `/vision` does. It offers a `Strategy` row for `AGENTS.md`'s "Where things live" table, since `/en-setup`'s append-merge never rewrites an existing `AGENTS.md`. |
| New repos | `/en-foundation` and `--retrofit` | Write the Strategy section as part of the normal flow. `/en-setup` State 2 already routes here, so nothing changes in `/en-setup` for new adopters. |
| Notice it is missing, on demand | `/en-setup` State 3 | One more diagnostic row: 🟡 when `docs/foundation.md` has no strategy marker, with "Run `/en-foundation --strategy`." No repair offer, because there is nothing mechanical to repair. |
| Notice it is missing, across all repos | `/en-sweep` | One check: no strategy marker files a single tech-debt entry ("No Strategy section; run `/en-foundation --strategy`"), deduped by its text so it is not re-filed weekly. Once the section exists, the drift check from §4 step 4 takes over. Sweep never drafts strategy text. |
| Keep working before migration | `en-review`, `en-plan`, lint | With no strategy marker the Strategy row is omitted from the peer prompt, `en-plan` names no ST-IDs, and the ST-ID lint is a P3 advisory, never a P1. This copies the `requirements_pending: true` rule `en-plan` already uses for repos without R-IDs. A repo nobody migrates keeps working exactly as today. |

The sweep entry is what makes this reach the whole fleet without anyone remembering. Every repo in `~/.ensemble/sweep-repos` gets a tracked, visible TD on its next scheduled run, and the TD closes when `/en-foundation --strategy` writes the section.

### Rollout order

1. Ship graceful degradation first: `en-review`, `en-plan` and the lint treat a missing section as a no-op. Without this, step 3 floods every repo with findings.
2. Ship `/en-foundation --strategy`, then dogfood it on Ensemble, replacing the hand-written section from §4's first unit if the skill's draft is better.
3. Ship the `/en-setup` diagnostic row and the `/en-sweep` check together, so detection appears only once the fix it points to exists.
4. Run `/en-foundation --strategy` in each adopting repo when its TD comes up. It is interactive and needs the author, so it cannot be batched.

### What this does not settle

- **Repos with older foundation layouts.** A foundation written before the current template may not have a §1 Executive Summary. Skills find the section by its marker, not its number, so the layout only matters for where `--strategy` inserts it on the first run: before the first `##` after the title block, the same rule `/vision` uses.
- **Repos with thin history.** `/vision` stops when it cannot read real history. `--strategy` should do the same and say so, rather than draft principles from the code alone.

## 6. Trade-offs

- **Cost.** Every `en-review` peer prompt grows by about 70 lines. That is the price of the check; a shorter strategy is the lever.
- **False flags.** A vague principle produces vague findings. The stress-test exists to make the lines testable, so step 3 is not optional if step 2 ships.
- **Single author.** The `/vision` model assumes one author whose merges are the evidence. That fits Ensemble today (§3.1). A team adopting Ensemble would need a rule for whose verdicts count, which this recommendation does not settle.
- **A one-off experiment with `/vision`** on this repo would produce a useful first draft cheaply. It writes a root `STRATEGY.md` and fetches an unpinned `lavish-axi`, so run it in a scratch clone and copy the text across.

## Sources

- `kunchenguid/vision`: `README.md`, `skills/vision/SKILL.md`, `skills/vision/assets/`
- `kunchenguid/no-mistakes`: `VISION.md`, its commit history via the GitHub API, and the files citing it listed in §2
- Ensemble: `docs/foundation.md` §1, §2, §3.3, §4.1 (D9, D106, D129, D143), §17, line 1539; `skills/en-review/references/peer-brief.md`; `skills/en-setup/SKILL.md` (State 3, legacy learning store); `skills/en-sweep/SKILL.md`; `skills/en-setup/references/stable-ids.md`; `skills/en-plan/SKILL.md` (`requirements_pending`)
