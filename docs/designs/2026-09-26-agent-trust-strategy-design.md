---
type: design
created: 2026-09-26
topic: What pstack's throughput is built on, and which pieces Ensemble should adopt, in what order
status: accepted
related_plan: EN22
---

# What pstack's throughput is built on, and what Ensemble should take from it

## Sources

- Talk: Lauren Tan (@poteto), "here's how i shipped 2,500 PRs last month to production", posted on X 2026-09-21, 38 min. The spoken number in the talk is 2,000. Slides supplied by the operator.
- Plugin: `cursor/plugins/pstack` at v0.15.5, read in full on 2026-09-26 apart from the seven `why` source playbooks.
- Ensemble: capability map of `skills/en-*`, `bin/`, `tests/` and `docs/` taken on 2026-09-26 at `982a700`.

A caveat before any of this. The PR count never appears in the pstack repo. Its README says throughput without quality is not the goal. Two conditions behind the count do not carry over to Ensemble users. She built Dune greenfield, as a framework locked down for agents from day one, and she runs Cursor cloud agents with a fleet of models. Most Ensemble targets are brownfield repos driven from one laptop by Claude Code or Codex. The mechanisms transfer. The number does not.

## How she does it

Everything in the talk hangs off one claim. You can only run many agents unattended once you trust their output without reading it, and that trust comes from the environment rather than from the prompt. She builds it in three layers and runs a loop on top.

### 1. The agent proves its own work

She started here, and everything downstream depends on it. Each app gets a generated verification skill (`create-verification-skill`) with five fixed parts:

- **Launch.** The exact command, a readiness signal and a teardown.
- **Doctor.** One read-only health check: process up, right build, port owned by this run, auth valid.
- **Drive.** Real selectors (ARIA roles, data attributes, CLI commands) wrapped in a repo-local CLI, so every session drives the app the same way and nobody writes one-off scripts.
- **Evidence.** The real user path, not setters or test endpoints. The action and the resulting state are captured, and the evidence outlives teardown at a named path.
- **Cleanup.** Kill only what this run started.

The feature map sits next to it. It has one file per feature with exactly four sections: sub-features with short IDs, every user entry point, how to drive each one with exact commands ending in a named proof artifact, and gotchas. The map is what lets an agent act on a vague bug report like a cropped screenshot with "???". A generated skill does not count until it has launched, driven one feature and kept its evidence. `maintain-verification-skill` runs on a schedule and ends in exactly one of three outcomes: clean, one PR, or blocked. It includes a live pass even when the source looks unchanged, and it treats a product regression as a bug to report, never as doc drift to paper over.

### 2. Skills that make the agent work like an engineer

`poteto-mode` is a sticky router. It maps task shapes to skills: `how` before nontrivial change, `architect` when code crosses a boundary, `interrogate` for contested designs, `no-comments` before review, `show-me-your-work` for unattended runs. It also carries an index of 23 one-rule principle skills that the agent has to read in full before citing. The principle behind most of her results is `encode-lessons-in-structure`: a repeated instruction becomes the strongest mechanism available, in the order unrepresentable state, then lint, then helper, then runtime check.

### 3. The codebase is the memory

This is the part she stresses most. Agents copy whatever they see, so one workaround becomes the pattern within weeks. Her slide makes the point directly: each copy makes the next copy likelier. When she corrects an agent, she fixes it at the strongest layer that works:

1. The codebase itself, so the mistake becomes impossible.
2. Static analysis: lint, compiler, CI.
3. Rules and Bugbot.
4. Skills.
5. The style guide, which only a human reviewer enforces and which cannot keep up with this volume.

Dune applies this to a real Electron app:

- **Five nouns.** Feature, Entrypoint, Transcript card, Client, Host. Each has one place in the tree and one job at runtime.
- **Process boundaries are folders.** The import graph decides what may import what, so renderer code cannot pull in main-process code.
- **One owned path per write.** Every write goes through React view, Client command, source adapter, Host, events, snapshot, with one writer per durable value.
- **Reserved filenames instead of a shared registry.** A feature is a folder with `entrypoint.ts`, `view.tsx` and `index.ts`, and the build discovers it. Two agents adding two features never touch the same file.
- **Guardrails at five stages.** Edit time, build, renderer start, lint, test. Every diagnostic names the expected owner or API. Her priority order is types, then build checks, then scaffolds, then prose.
- **Comments are banned.** Agents cited the comments next to a workaround as the reason to extend it rather than fix the cause.

Her gardening loop runs in three steps: delete the debt you have, keep one paved path, and lint against each anti-pattern as soon as you see it. The lint stops the spread even before anyone cleans up the existing instances.

### 4. The loop that turns trust into volume

- **Parallel work in isolation.** One worktree or branch per agent, one writer per branch. Cheap fast models write code and strong models do judgment.
- **Small PRs.** The rule is five narrow PRs over one large one, stacked, with a short briefing body (Why, Scope, Tradeoffs, Blast Radius, Verification).
- **A verifier who didn't write the code.** Each PR gets one that posts PASS or FAIL. Only the contiguous run of verified PRs lands. A verdict survives a rebase only when `git patch-id` is unchanged.
- **An orchestrator that never writes code.** It keeps a ledger of units, verdicts keyed by PR and head SHA, an inbox, and parked human gates. Briefs have a fixed set of fields, and a brief missing one is refused. It runs about ten units in flight and escalates only irreversible actions and product calls.
- **An outer loop.** In Benny, a Slack report goes to triage, which posts a verdict marker and files a tracker ticket. A repro agent reproduces the bug twice through the real UI, with video. After a rejection window it makes a bounded root-cause fix, proves it twice on the patched build, and opens a draft PR. Humans merge.
- **Review load kept low.** Bugbot findings are triaged skeptically, CI failures are classified before any retry, and an adversarial review may surface at most five items to act on.

Read in order, the reasoning goes like this. Self-verification makes a single agent trustworthy. Structure keeps the next agent from copying a bad pattern. An independent verifier per PR replaces a human reading every line. Only once all three hold does parallelism and an outer loop add volume instead of slop.

## Where Ensemble stands

Ensemble is already ahead in the review and evidence chain:

- a blind cross-agent peer review;
- `review-verdict:` and `simplify-verdict:` trailers, audited by `ensemble-verify-peer-evidence`;
- unit gates that commit only on green;
- plan hashes;
- a tree-fingerprint verification receipt, which serves the same purpose as her patch-id verdicts;
- secret scanning;
- a parser-based guardrail hook;
- a watch loop that resolves trusted review threads.

`en-plan`'s ordered units with test scenarios already match `sequence-verifiable-units`.

The gaps are in the three layers underneath, and the first one is the largest.

| Her mechanism | Ensemble today | Gap |
|---|---|---|
| Per-app verify skill: launch, doctor, drive CLI, evidence, cleanup | `en-qa` phase 2 drives a browser from prose only, with no scripts. There is no app driver and no path for CLI, desktop or mobile apps | Large |
| Machine-readable feature map | Foundation §6 F-IDs are prose, and `en-qa` guesses which flows a file affects | Large |
| Proof in the PR | Screenshots stay in `.test-output/qa/`. The PR body gets one line | Medium |
| Corrections routed to the strongest layer | Foundation §17.1 states the principle, but no skill applies it. `en-learn` writes prose only. `golden-principles.md` and the architecture-fitness check are specified but were never built | Large |
| Code-level lint in target repos | `en-setup` installs a doc linter only. Layer rules in `architecture.md` are prose, and drift is checked by an LLM that files TD entries | Large |
| Gardening | `en-sweep` touches docs only. `continuous-monitor` finds dead code and files TDs, but nothing blocks growth | Medium |
| Independent live verifier per PR | The peer reviews the diff, not the running app | Medium |
| Parallel build fan-out | Not present, by decision D52 (the host builds every unit) | Deliberate |
| Outer loop from issue reports | Not present. `en-debug` reproduces one issue on request | Large, but blocked on the verify harness |
| Small PRs: five narrow ones over one large one, each independently verified | A whole plan ships as one branch and one PR | Medium. Every PR is harder to verify, and a single failure blocks all its units |

## Recommendation

Adopt her ordering. Build verification first, then correction routing, then target-repo structure, then volume. Every later piece consumes the earlier ones. Benny cannot reproduce anything without a drive CLI and a feature map, and a verifier per PR is only as good as the harness it runs. Each step below is sized to become one `/en-plan`.

### Leanness rule: replace, don't add

Skills exist to produce a solid product, and every step they add costs the model context and the user time. So each item below must meet one of two conditions:

1. **It replaces or shrinks an existing cycle.**
   - The harness's scripted drives replace `en-qa`'s model-driven clicking.
   - A live PASS from the verifier becomes the evidence that lets low-risk diffs skip the host persona reviewers, once `ensemble-metrics` shows the verifier catches what they catch.
2. **It stays off the hot path.** Anything that is neither sits in a step that already runs, costs at most one question, or runs off-hours and opt-in. The hot path is `en-build`, `en-review`, `en-resolve-pr` and `en-ship`. EN22 is the first application: it changes none of those four.

Two process rules follow:

- **Every plan sets a byte budget for each SKILL.md it touches, and the build checks it and records the growth in the commit body.** The skill-size lint caps a file's total size; the budget caps what one plan adds. It is checked at build time rather than pinned by a test, because a permanent size assertion would fail every later, unrelated edit to the file (EN22 learned this in review).
- **In peer review, a fix that adds machinery needs a reason.** When a second round's findings land inside the first round's fixes, simplify rather than patch. The repo already records this lesson (`docs/learnings/repeated-review-rejects-are-a-design-signal-2026-09-11.md`). EN22's first version broke this rule and was cut from six units to five, with one carrier set halved and one script removed.

Verification steps are the exception that proves the rule. Launching the app and driving a feature are real added steps, but they are the product check itself, not overhead. The test is whether a step replaces weaker work, not whether a step was added.

### Track A: Ensemble skills

**A1. Verify harness generator.** New skill, or an `en-setup` phase.

- It interviews the repo (surface, run, drive, observe, isolate) and writes a repo-local verify skill with the five parts plus a small CLI under the target repo's own tree.
- It must execute one feature end to end before declaring done. A harness that never ran counts as a draft, the same rule as her "a generated skill that was never executed is a draft".
- Ensemble work covers CLIs and HTTP services from day one, not just web, because most of the operator's repos include one.
- Decision to make in the plan: where the harness lives (`.ensemble/verify/` or `.claude/skills/verify-<app>/`) so that both Claude Code and Codex can load it.

**A2. Feature map replaces prose F-IDs.**

- Keep F-IDs as the stable IDs. Each becomes one file with her four sections, and foundation §6 points at the files instead of holding prose.
- `en-qa` selects flows from the map's entry points rather than by reasoning, and reports a file that no feature claims as unmapped.

**A3. `en-qa` drives through the harness and proof reaches the PR.**

- The flow ledger records the feature ID, the entry point and the artifact paths.
- The receipt carries them, and `ensemble-pr-body` renders a Verification section that lists each proof.
- A skipped entry point is reported as skipped, never as verified by some other route.

**A4. Harness maintenance in `en-sweep`.**

- Adds a verify-drift pass with her three outcomes: clean, one PR, blocked.
- The live pass is required, and a product regression becomes a bug report, never a doc edit.

**A5. Correction router.** Planned as EN22. It carries out §17.1, and it follows the existing memory rule that prose invariants need auditable gates.

- **Where it runs.** Three places:
  - `en-learn capture`, in a step that already runs once per build;
  - an opt-in sweep scan, where a comment recurring across two merged PRs is the trigger;
  - an audit mode over a repo's existing prose rules.

  Review, resolve-pr and the other hot-path skills are unchanged.
- **How it classifies.** The strongest layer that works wins: a structure change, then a lint or test, then an AGENTS.md rule, then a skill, and only then prose.
- **What it produces.** Layers 1 to 4 become TD entries proposing the change. A lint rule rejects any layer 1 or 2 entry that names no concrete check.
- **The lever, now or later.** For a layer 1 or 2 check in the current repo, capture asks whether to add it on the branch now. This is her "write the lint when you see the mistake", kept to one question.

**A6. Independent verifier on ship.**

- `en-ship` runs one fresh verification of the running app through the harness. The verifier must be an agent that did not write the code; the cross-agent peer is the natural candidate.
- The receipt keys that verdict to the tree fingerprint, so it survives a rebase that leaves the tree unchanged.
- Blocked on A1 to A3.

**A7. Volume, later and only with evidence.**

- Two candidates:
  - an `en-flow` queue mode: several plans, one worktree each, a ledger of verdicts, human gates parked;
  - a Benny-style intake: tracker or Slack report, then triage, then `en-debug` reproducing twice through the harness, then a draft PR.
- Both go against D52 or add infrastructure, so they should wait until A1 to A6 show in `ensemble-metrics` that unattended PRs pass the verifier without rework.

**A8. Smaller PRs.** This one is to be designed, not planned yet.

- Her trust scales partly because each PR is small enough for one verifier to prove. Ensemble ships a whole plan as one PR.
- The candidate is for `en-ship` to open one PR per contiguous group of units, stacked on each other. Each PR carries its own receipt and verifier verdict, and only the verified run at the bottom of the stack lands.
- This only pays off once A6 exists, because small PRs without a live verifier just multiply review work. Brainstorm it after A6.

### Track B: making target repos agent-friendly

Ensemble can't write Dune for anyone. What it can do is install the mechanics that make a brownfield repo drift toward being one. The first three are Ensemble features; B4 is a practice.

**B1. Architecture layer rules become a boundary config.**

- `en-foundation` and `en-setup` turn `architecture.md`'s layer rules into the stack's import-boundary tool: dependency-cruiser or eslint-plugin-boundaries for TS, import-linter for Python, depguard for Go. The result runs in CI.
- This finally builds the specified architecture-fitness check. It is the direct counterpart of her folder-as-process-boundary slide.

**B2. `docs/golden-principles.md` as a lint catalog, not an essay.**

- Each principle names the rule that enforces it, or is marked "unenforced" with a TD entry.
- A5 appends to it. Sweep reports the count of unenforced principles.

**B3. Anti-pattern census in `en-sweep`.**

- For each banned pattern, a baseline count checked into the repo. CI fails when the count goes up. Cleanup PRs bring it down.
- This is her "lint first to stop the spread" applied to a brownfield repo that can't be fixed in one pass.

**B4. Paved-path inventory.**

- For each recurring concern (data fetch, new route, new feature folder, error handling, config), AGENTS.md names one canonical example file.
- Where the repo can support it, reserved filenames or a scaffold command replace a shared registry, so parallel agents don't edit the same root.
- `en-setup`'s health check scores this.

**B5. Comment policy, opt-in per repo.**

- Her total ban fits a locked-down framework and would fight many existing codebases.
- Take the narrower rule that caused her ban: a comment explaining a workaround is a finding. `en-simplify` or the correction router turns it into a type, a test or a lint, or deletes it.

### What not to adopt

- **Her 23 principle skills as separate files.** Ensemble already has the per-skill trim series and a deliberate duplication trade. Where a principle is missing, put it into an existing skill's rules; don't add a principle layer.
- **Cursor-specific machinery.** Model-role routing files, `/automate`, cloud-agent sleepers and Bugbot. Keep the ideas and ignore the plumbing.
- **Autopilot-full's merge-on-verdict.** It depends on the verifier being trusted first, and Ensemble has no live verifier yet. Revisit after A6 has a track record.
- **A headline PR count as a target.** Measure the things that produce trust instead: the share of PRs carrying live proof, the share of corrections landing at layer 1 or 2, and human interventions per build.

## Proposed sequence

1. **A5 correction router (EN22, slimmed).** Small, with no dependencies, and it touches no hot path. It is proven on Emble through `/en-learn --enforce-audit`, whose TD entries seed an Emble plan.
2. **A1 and A2, harness plus feature map, as `en-verify init` on Emble.** This is the next plan after EN22. It is the step that makes Ensemble verification-driven; A5 does not. Pilot on Emble before generalizing.
3. **A3, then A4.** A3 retires `en-qa`'s model-driven clicking in favour of scripted drives.
4. **B1 and B2** on the same pilot repo.
5. **B3, B4, B5.**
6. **A6.** Measure which layer catches each defect from the first PR it runs on.
7. **A8 smaller PRs**, brainstormed once A6 has a track record.
8. **A7**, only if the metrics from steps 1 to 7 say unattended output holds up.

## Decisions (2026-09-26)

**Pilot repo is Emble** (`../emble`): FastAPI and React, Clerk auth, a control-plane database plus one Postgres database per tenant, 14 file routes under `frontend/src/routes/_layout/`, an existing Playwright suite with `auth.setup.ts`, and `backend/tests/test_architecture_invariants.py`. It exercises the web path of the harness. Track B starts from what Emble already has. Its AGENTS.md holds prose rules that A5 should turn into invariant tests or lint rules. Two examples are "never branch on `source_system`" and "routes never call `useAuthFetch` directly".

**The harness is generated per repo, against a contract Ensemble owns.**

- Ensemble owns:
  - a versioned contract with five commands: `launch`, `doctor`, `drive <feature> <entry-point>`, `evidence`, `cleanup`;
  - fixed exit codes, including a distinct blocked code;
  - an evidence manifest with feature ID, entry point, artifact paths, run ID and tree fingerprint;
  - the feature-map format and a validator;
  - a new `en-verify` skill with two modes. `init` generates the harness and drives one feature end to end before it reports done. `maintain` checks for drift and is called by `en-sweep`.
- `en-setup` offers `en-verify init` but doesn't contain it, because TD14 leaves it 52 bytes under the size lint.
- The repo owns the driver, the drive scripts and the feature map, under `.ensemble/verify/`. AGENTS.md points to them.
- Health checks and sweep compare the repo's contract version against Ensemble's. Ensemble already copies `ensemble-lint` into target repos, and this works the same way.
- For Emble:
  - `doctor` refuses unless `DATABASE_URL` and `DEFAULT_TENANT_DATABASE_URL` are local and Clerk uses test keys.
  - Drives reuse the existing Playwright setup.
  - Connectors are stubbed only at the `pipelines/<src>_source.py` seam.

**The live verifier adds to the diff review and replaces none of it.**

- The two catch different failures. The enum-mapping learning in Emble is a bug that reads correctly in the diff and breaks on the first page load.
- The verifier:
  - runs in parallel with the peer review;
  - never sees the builder's transcript, only the plan's acceptance criteria, the feature map and the harness;
  - runs on the other CLI;
  - runs only when the diff touches a mapped feature;
  - records its verdict in the receipt, tied to the tree fingerprint.
- Emble's pre-push hook reads that verdict and never runs the verifier itself.
- It is local-only until it has a track record. CI needs Clerk test auth and databases on the runners.
- `ensemble-metrics` records which layer caught each defect, so any later trimming is based on data.

## Harness performance

A verification run is slow when an agent works out every click and screenshot itself, one model turn per action. That is how `en-qa` phase 2 runs today. The harness is designed so the model stays out of the click loop:

1. **Scripted drives.** Each feature map entry compiles to a Playwright script under `.ensemble/verify/drives/`, and `drive` runs it without the model. The agent writes a drive once per new feature, judges the evidence against acceptance criteria, and investigates failures.
2. **A warm instance.** `launch` is idempotent. If a healthy instance from this worktree is already up, `doctor` confirms it and the run reuses it, so a session pays the cold start once.
3. **A template database.** Migrate once, then create each run's tenant database with `CREATE DATABASE ... TEMPLATE`. The template is rebuilt only when migration files change.
4. **Tiers scoped to the diff.** The ship verifier drives the golden path only, for features the diff touches. `en-qa` adds edge cases. Agent exploration is kept for bug reproduction and features with no script yet.
5. **Parallel drives.** Independent drives run at once against one warm app, each with its own browser context and tenant.
6. **Light evidence.** An ARIA snapshot plus a screenshot by default. Video only on FAIL or bug reproduction.
7. **Hard budgets.** Each step has a timeout and each run a total budget. An exhausted budget ends as BLOCKED, naming the step that stalled.

The first unit of the pilot measures cold launch, warm `doctor`, and one existing spec (`connection-settings.spec.ts`) run as a drive. It records `verify_launch_seconds` and `verify_drive_seconds` in Emble's AGENTS.md, the same way `test_full_seconds` is recorded. Ship-time policy keys off those numbers. If the cold launch is the slow part, the fix is keeping an instance warm, not verifying less.

None of this runs in Emble's production runtime. The other costs are small:

- lint rules piling up in pre-commit, which A5 limits by adding rules to tools Emble already runs;
- import-graph lint, which runs in CI and at pre-push rather than on every commit;
- the verifier's token cost per PR, which is capped by running it only for mapped features and reusing receipts.
