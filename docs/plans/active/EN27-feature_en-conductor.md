---
type: plan
plan_type: feature
plan_id: EN27
title: Replace /en-flow with /en-conductor, one entry point that routes work and asks only when it must
status: in_progress
location: active
created: 2026-11-04
shipped:
deepened:
covers_requirements: []
requirements_pending: false
related_design:
peer_review_verdict: revise
peer_review_iterations: 2
peer_review_last_run: 2026-11-04
peer_review_plan_hash: 490996d80c388afd5f50638961db6b8f39af4e686d2fb2541a21b09b5dfd7f49
peer_review_resolutions:
  - finding_id: 1-1
    iteration: 1
    severity: P1
    title: "Fix route ignores --no-ship, --no-watch and local_only"
    status: applied
    location: U4
  - finding_id: 1-2
    iteration: 1
    severity: P1
    title: "The fallback log event is rejected by the trail CLI"
    status: applied
    location: U4
  - finding_id: 1-3
    iteration: 1
    severity: P1
    title: "Trail lifecycle and row content cannot support resume as specified"
    status: applied
    location: U4
  - finding_id: 1-4
    iteration: 1
    severity: P1
    title: "The needs-plan clean check gives false stops and misses commits"
    status: applied
    location: U4
  - finding_id: 1-5
    iteration: 1
    severity: P1
    title: "Agent-run stages have no handling for a returned question"
    status: applied
    location: U4
  - finding_id: 1-6
    iteration: 1
    severity: P1
    title: "Learn runs on every plan route despite 'when warranted'"
    status: applied
    location: U4
  - finding_id: 1-7
    iteration: 1
    severity: P1
    title: "needs-decision redispatch has no input or state contract"
    status: applied
    location: U3
  - finding_id: 1-8
    iteration: 1
    severity: P2
    title: "Routing uses a diff signal before any diff exists"
    status: applied
    location: U4
  - finding_id: 1-9
    iteration: 1
    severity: P1
    title: "The risk eval is never really run and its judge can fail correct behavior"
    status: applied
    location: U5
  - finding_id: 1-10
    iteration: 1
    severity: P2
    title: "Removing the manual flag may drop /en-fix's protection in peer sessions"
    status: applied
    location: U3
  - finding_id: 1-11
    iteration: 1
    severity: P2
    title: "The --from-flow rename has no check over docs"
    status: applied
    location: U1
  - finding_id: 1-12
    iteration: 1
    severity: P2
    title: "New shared copies and en-flow removal are not tied to parity pins"
    status: applied
    location: U4
  - finding_id: 1-13
    iteration: 1
    severity: P2
    title: "The fix route still ships browser changes without QA"
    status: applied
    location: U4
  - finding_id: 1-14
    iteration: 1
    severity: P2
    title: "U3 prose may create false callees or lint failures"
    status: applied
    location: U3
  - finding_id: 1-15
    iteration: 1
    severity: P2
    title: "No policy for a conductor session without a question tool"
    status: applied
    location: U4
  - finding_id: 2-1
    iteration: 2
    severity: P1
    title: "The plan route does not honor --no-ship"
    status: applied
    location: U4
  - finding_id: 2-2
    iteration: 2
    severity: P1
    title: "Question-policy ordering can bypass user-owned decisions"
    status: applied
    location: U4
  - finding_id: 2-r1
    iteration: 2
    severity: P1
    title: "Resume still lacks execution-context validation"
    status: applied
    location: U4
  - finding_id: 2-3
    iteration: 2
    severity: P1
    title: "A clean working tree does not make fallback reruns safe"
    status: applied
    location: U4
  - finding_id: 2-4
    iteration: 2
    severity: P1
    title: "Decision continuation has no concrete execution scenario"
    status: applied
    location: U3
  - finding_id: 2-5
    iteration: 2
    severity: P2
    title: "U6 is an added unit without an applied-finding link"
    status: disagreed
    rationale: U6 is its own unit and commit. This plan's first peer pass exposed the bug, the conductor branches on HOST, and the repo owner's standing rule is to fix broken windows in separate atomic commits.
    location: U6
depth: standard
data_scale: small
---

# EN27: Replace /en-flow with /en-conductor, one entry point that routes work and asks only when it must

## Context

`/en-flow` runs one fixed path: plan, build, learn, ship. It cannot take a change that needs no plan, it skips the `/en-qa` that `/en-build` recommends, it keeps state in `/tmp` and it has no resume. The user wants one skill to work through, which picks the other skills and asks only when a decision is really theirs. pstack's `poteto-mode` is the inspiration for routing first and for classifying a question before asking it. Its style rules, cloud VMs and per-role model selection are not being copied.

## Requirements covered

None by ID. `docs/foundation.md` carries no R-IDs in this repo, so this plan cites D-IDs. It amends D124, D138 and the v1 scope lines at `docs/foundation.md:88` and `:109`, under a new decision D143.

## Out of scope for this plan

- Invoking `/en-loop`. It stays manual, and the conductor only names the command.
- Merging. Every route stops at a ready-for-review PR.
- Routing `/en-debug`, `/en-review`, `/en-qa`, `/en-resolve-pr`, `/en-simplify`, `/en-learn`, `/en-setup`, `/en-sweep` or `/en-test-audit` as standalone requests. The conductor names the command for these in v1.
- Making `/en-conductor` itself model-invocable.
- Stage subagents on Codex. Nesting there is unverified, so Codex runs every stage in session.
- A `plan_store: linear` route. The conductor reports the refusal, as `/en-flow` does today.
- Lifting a D142 risk stop from inside the conductor.
- Running `/en-qa` on the fix route. `/en-fix` ships inside its own stage, so the report names `/en-qa` as the next step when `needs_browser` is true for the branch diff.
- Pruning old trail files. They are small, per-checkout and gone with the clone.

## Approach (high-level)

`/en-conductor <request>` is a manual-invoke skill that stays in the user's session. It classifies the request against `references/plan-or-fix.md`, states the route and a checkable definition of done, runs the route's stages, and ends with a report. It holds the only question tool in the run, so every question reaches the user through it.

**Where stages run.** A capability check on 2026-11-04 showed that a Claude Code subagent and a `claude -p` session both have the `Agent` and `Skill` tools and can spawn an agent, and neither has `AskUserQuestion`. So on Claude Code, stages that need no answer from the user run in a fresh subagent, which keeps the session small through compaction (D107). `/en-plan`, `/en-brainstorm` and `/en-foundation` run in session because they ask. A plan with a destructive, high-risk or gated unit builds in session because its typed confirmations must reach the user. Any stage agent that returns no contract fields, or whose host refuses it, is rerun once in session and the fallback is logged.

**One flag for "a caller is driving".** `--orchestrated` replaces `--from-flow` on `/en-plan` and is added to `/en-build` and `/en-fix`, matching the flag `/en-resolve-pr` already has.

**Replace, do not add.** `/en-flow` is deleted in the same commit that adds `/en-conductor`, with no alias, so the catalogue stays at eighteen skills.

**Run state** is one append-only TSV per run under `$(git rev-parse --git-dir)/ensemble/conductor/`, beside the existing run ledgers. It needs no `.gitignore` entry and no scaffold change, and `git clean -fdx` cannot remove it.

## Test seams

Three, each already in use here.

1. **Text pins in `tests/lint/*.test.sh`** (existing). Skills are prose, so this is the only seam that sees a skill's stated rules. `contract-shape.test.sh` derives the call graph here too.
2. **Direct execution of `ensemble-conductor-trail`** (new script, existing pattern as in `tests/en-ship/`). It is the only code this plan adds.
3. **`tests/evals/run-behavioral`** (existing, on demand, never in CI). It is the only seam that observes real routing, since a text pin cannot.

## Technical design

```
/en-conductor <request>            your session, holds the question tool and the trail
  preflight: recursion guard, host, git remote, tracked tree clean
  route ──┬─ fix ─────────▶ /en-fix --orchestrated ─┬─ shipped ────────────────▶ report
          │                                         ├─ ready ──────────────────▶ report, nothing pushed
          │                                         ├─ needs-plan clean <cond> ▶ plan route
          │                                         ├─ needs-plan edited <cond> ▶ stop, edits stay on the branch
          │                                         ├─ needs-decision <q> ─────▶ question policy, then --decision
          │                                         ├─ split <concerns> ───────▶ report
          │                                         └─ stopped <reason> ───────▶ report
          ├─ plan ────────▶ /en-plan --orchestrated (session)      gate: status: open
          │                 /en-build --orchestrated               gate: audit verdict ok
          │                 /en-learn capture, per the Learn rule   decided, never asked
          │                 /en-qa, when needs_browser is true     gate: no Fail flow
          │                 /en-ship                               gate: exit state
          ├─ brainstorm ──▶ /en-brainstorm (session), then stop and name the next command
          ├─ foundation ──▶ /en-foundation (session), then stop and name the next command
          └─ other ───────▶ name the command and stop (/en-loop is here)
```

**Question policy, in order.** (1) If running or reading something can answer it, do that. (2) If it is a product or preference call, or an irreversible action, ask, even when the call could be reversed later. (3) Decide everything else, log it to the trail and list it in the final report. So which test seam to use is decided, and which of two user-facing error messages to show is asked. Existing stops are unchanged: `/en-build`'s typed confirmations, P0 review stops, and never merging. When `$QUESTION_TOOL` does not resolve, as in a headless session, a call the policy reserves for the user ends the run with `en-conductor: stopped at <stage>: <question>`. It is never guessed.

**Stage confirmation.** A stage's report is a claim. After `/en-build`, the conductor confirms a `review-verdict:` trailer exists in `git log <merge-base>..HEAD`. After a shipping stage, it confirms the PR with `gh pr view --json url,state,isDraft`.

## Implementation units

Each unit has a stable U-ID. Never renumbered after assignment.

### U1. Replace `/en-plan --from-flow` with `--orchestrated`

- **Goal:** `/en-plan` has one caller flag that keeps the Linear refusal and also applies the question policy to planning questions.
- **Requirements covered:** none by ID
- **Dependencies:** none
- **Interfaces:**
  - *Produces:* `/en-plan --orchestrated`. Compatibility: breaking for `--from-flow`, whose only caller is `/en-flow`, migrated in this same unit.
- **Files:**
  - `skills/en-plan/SKILL.md` (modify)
  - `skills/en-plan/CONTRACT.md` (modify)
  - `skills/en-plan/references/linear-publish.md` (modify)
  - `skills/en-plan/references/finalize-loop.md` (modify)
  - `skills/en-flow/SKILL.md` (modify)
  - `tests/lint/en-plan-linear-publish.test.sh` (modify)
  - `tests/lint/en-plan-finalize-loop.test.sh` (modify)
- **Approach:** Rename the flag at `skills/en-plan/SKILL.md:27` and `:148`, `linear-publish.md:238-251`, `finalize-loop.md:18` and `skills/en-flow/SKILL.md:44`. List `--orchestrated` in the contract's Accepted invocations, which omits `--from-flow` today. Under `--orchestrated`, `/en-plan` changes four behaviours and no others. Step 4 takes the default `plan_type` rather than confirming. Step 5 skips the "Plan anyway?" offer, because the caller already routed. Step 7 classifies each frontier question: a repo fact is looked up, a product or preference call or an irreversible action is asked, and anything else takes the recommended answer and is recorded under `## Decisions, assumptions & risks`. Step 20's soft prompt is skipped. The reject path, the cap-hit question and the destructive-order refusal stay. The caller passes `--branch-on-default y` as the contract already requires. Keep the `/en-flow` boundary heading in `linear-publish.md` until U4, which renames it.
- **Risk:** medium
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* `en-plan-linear-publish.test.sh` passes with the flag table row `| \`--orchestrated\` |`, a step 1 line naming it, the boundary section keying on it, and `skills/en-flow/SKILL.md` containing `/en-plan --orchestrated`.
  - *Edge case:* `git grep -n -- 'from-flow'` across the whole repo returns only `docs/plans/completed/`, `docs/plans/active/EN27-*`, `docs/reviews/`, `docs/designs/`, `docs/generated/`, tracker entry TD18, and D-entries in `docs/foundation.md`.
  - *Error path:* with the boundary section's `refuse` removed, the linear-publish test goes red. Confirm once, then restore.
  - *Integration:* a new assertion in `en-plan-finalize-loop.test.sh` finds all three branches of the question classification and states that an orchestrated run still asks a product or preference call.
- **Verification:** `./tests/select-for.sh` on the changed paths passes, and `wc -c skills/en-plan/SKILL.md` is at most 26624.

### U2. `/en-build --orchestrated`: a gate stops and returns, and the checkpoint never asks

- **Goal:** `/en-build` can run in a stage agent with no question tool without skipping a safety gate or blocking on the learning prompt.
- **Requirements covered:** none by ID
- **Dependencies:** none
- **Interfaces:**
  - *Produces:* `/en-build <plan-path> --orchestrated`, and return lines `gate_required: U<N>` and `needs-decision: U<N>: <question>`. Compatibility: additive.
- **Files:**
  - `skills/en-build/SKILL.md` (modify)
  - `skills/en-build/CONTRACT.md` (modify)
  - `skills/en-build/references/post-build-protocol.md` (modify)
  - `tests/lint/en-build-flag-surface.test.sh` (modify)
  - `tests/lint/en-build-learning-checkpoint.test.sh` (modify)
  - `tests/lint/en-build-gating-shrink.test.sh` (modify)
- **Approach:** Add the flag row. In step 9a, add one sentence: when no question tool can reach the user, a gate is neither answered nor skipped; stop before the unit's work and return `gate_required: U<N>`. Today's "any other input records the unit `skipped`" rule applies only to a person's input. Any other stop-and-ask in `references/build-failures.md` under the same condition ends the run with `needs-decision: U<N>: <question>`, and every committed unit stays committed. In `post-build-protocol.md` step 2, the CI short-circuit fires on `CI=true` or `--orchestrated` and records `learning_checkpoint: ci_environment`. This adds no new value, because the meaning is the same: nobody was asked. The caller then owns the decision. In `CONTRACT.md`, "no flag disables that" stays true; add `gate_required` and `needs-decision` to the Return table and the flag to Accepted invocations. With a question tool available, as when the conductor runs the build in session, the flag changes only the learning checkpoint. `skills/en-build/SKILL.md` is at 25540 of 26624 bytes, so keep the additions under 500 bytes.
- **Risk:** medium
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* the flag surface test finds `--orchestrated` in both the SKILL.md flag table and the contract.
  - *Error path:* the gating test asserts step 9a says a gate is not skipped with no question tool and names `gate_required`. Removing `gate_required` from step 9a turns it red.
  - *Error path:* the gating test finds `needs-decision` on the same no-question-tool rule. Removing it turns the test red.
  - *Edge case:* the learning checkpoint test finds both `CI=true` and `--orchestrated` on the short-circuit line, and the four canonical outcome values are unchanged.
- **Verification:** `./tests/select-for.sh` on the changed paths passes, and `wc -c skills/en-build/SKILL.md` is at most 26624.

### U3. Make `/en-fix` model-invocable, with a caller mode that returns instead of asking

- **Goal:** a skill can invoke `/en-fix` and branch on one named outcome, and the D142 stop still holds.
- **Requirements covered:** none by ID
- **Dependencies:** none
- **Interfaces:**
  - *Produces:* `/en-fix <request> --orchestrated [--no-ship] [--no-watch] [--decision "<question>: <answer>"]`, whose last line is exactly one of `en-fix: shipped <pr-url> <exit-state>`, `en-fix: ready <branch>`, `en-fix: needs-plan clean <condition>`, `en-fix: needs-plan edited <condition>`, `en-fix: needs-decision <question>`, `en-fix: split <concern>; <concern>`, `en-fix: stopped <reason>`. Compatibility: additive; a person's `/en-fix` is unchanged.
- **Files:**
  - `skills/en-fix/SKILL.md` (modify)
  - `skills/en-fix/references/plan-or-fix.md` (modify)
  - `skills/en-plan/references/plan-or-fix.md` (modify)
  - `skills/en-setup/references/templates/claude-md-template.md` (modify)
  - `skills/en-foundation/references/templates/claude-md-template.md` (modify)
  - `AGENTS.md` (modify)
  - `tests/evals/cases/en-fix.json` (create)
  - `tests/lint/en-fix.test.sh` (modify)
  - `tests/lint/en-plan-warranted-gate.test.sh` (modify)
  - `tests/lint/en-debug-diagnosis.test.sh` (modify)
- **Approach:** Remove `disable-model-invocation: true` and the sentence "Manual-invoke only." from the description at `skills/en-fix/SKILL.md:3-4`. Replace the block at `:14` with: it pushes and opens a PR, and it runs when a person asks or when `/en-conductor` invokes it; any other skill suggests it. Rewrite `plan-or-fix.md:17` in both copies, byte-identical, to: "Only `/en-conductor` invokes `/en-fix`. Any other skill names the command, `/en-fix <request>`." In both `claude-md-template.md` copies at `:39`, change to "Name the command rather than starting a plan." In `AGENTS.md`, drop the `*` from the `/en-fix` row. Add an `--orchestrated` flag row and an `## Orchestrated` section to the skill with the mapping from each stop to its outcome. Triage's plan condition returns `needs-plan clean`, since Triage runs before the Branch step and nothing exists yet. The Risk re-check, or a risk stop in Review, returns `needs-plan edited`. Unrelated concerns return `split`. Under `--no-ship`, or when `git remote` is empty, the run stops after the Receipt gate and returns `ready`. `/en-ship` returning a PR returns `shipped` with its exit state, and a stop before any PR returns `stopped`. An ambiguous improvement, an existing assertion that may encode a decision, or a `manual` finding that encodes a decision returns `needs-decision`. A non-`convergent` `/en-debug` verdict, a P0 and a failed Receipt gate return `stopped`. A caller's brief is not the user's words, so `## Risk override` never applies under this flag. `--decision` continues on the existing branch with the first dispatch's edits and commits in place: the Branch step's refusal of tracked edits is skipped, `FIX_BASE` is taken from `git merge-base <default branch> HEAD`, and the answer settles only that question and never lifts a risk stop. Every return closes the run as today. The Preflight's `ENSEMBLE_PEER_REVIEW=true` stop at `skills/en-fix/SKILL.md:38` already covers a peer session now the manual flag is gone, and `en-fix.test.sh:88` already pins it, so no new guard is needed. The contract page lands in U4, because `contract-shape.test.sh` requires the contract set to equal the derived callee set, and no skill invokes `/en-fix` until then. Update comments at `en-plan-warranted-gate.test.sh:91-92` and `en-debug-diagnosis.test.sh:53`, which call `/en-fix` manual-only. `contract-shape.test.sh:31-33` derives callees only from `skills/*/SKILL.md`, so the sentence in `plan-or-fix.md` creates no callee, and the wording in `skills/en-fix/SKILL.md` must not put an invoke verb directly before `/en-fix`. Foundation and README edits land in U4 so that D143 exists when they cite it. For the trigger case, use positives "Fix this bug in the date parser and open a PR", "Make this small improvement, no plan needed", "Fix the off-by-one in the report totals", and negatives "Why did this fail in prod?" owned by `en-debug` and "Plan this feature before I build it" owned by `en-plan`. If a rank or collision check fails, change only `en-fix`'s description. Never lower `FLOOR`. A `known_gap` needs a stated reason.
- **Risk:** medium
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* `en-fix.test.sh` asserts the frontmatter has no `disable-model-invocation: true` and that the skill names all seven outcome spellings, `--no-ship` and `--decision`.
  - *Error path:* `en-fix.test.sh` asserts the `## Orchestrated` section says a brief does not lift a risk stop. Deleting that sentence turns it red.
  - *Error path:* `en-fix.test.sh` asserts `--decision` says the answer never lifts a risk stop and that it continues with edits in place.
  - *Edge case:* `tests/evals/trigger.test.sh` passes with thirteen cases and a rank-1 rate at or above the floor of 89.
  - *Integration:* `tests/parity/reference-parity.test.sh` and the hash check at `en-plan-warranted-gate.test.sh:113-114` pass with both `plan-or-fix.md` copies changed.
- **Verification:** `./tests/select-for.sh` on the changed paths passes, including `trigger` and `contract-shape`. Keep the existing "carries no CONTRACT.md" assertion until U4.

### U4. Add `/en-conductor`, delete `/en-flow`, and record D143

- **Goal:** `/en-conductor <request>` routes work through to a ready-for-review PR with a resumable trail, and `/en-flow` is gone from every live reference.
- **Requirements covered:** none by ID
- **Dependencies:** U1, U2, U3
- **Interfaces:**
  - *Consumes:* `/en-plan --orchestrated`, `/en-build --orchestrated` with `gate_required: U<N>`, `needs-decision: U<N>: <question>`, and the seven `en-fix:` outcome lines.
  - *Produces:* `/en-conductor <request> [--plan <path>] [--no-ship] [--no-watch] [--resume]`, whose last line is `en-conductor: done` or `en-conductor: stopped at <stage>: <reason>`. Also `ensemble-conductor-trail`, with these subcommands:
    - A run is `open`, `stopped` or `closed`. `start` and `resume` make it `open`; `finish stopped` makes it `stopped`; `finish done` and `superseded` make it `closed`.
    - `start --request <words> --route <fix|plan|brainstorm|foundation> --done-when <predicate>` writes one `start` row with `stage` holding the route, `what` the request and `why` the predicate, and prints the trail path. An `open` or `stopped` run in this checkout is first closed with a `superseded` row and named on stderr.
    - `log <event> <stage> <what> <why-or-evidence>`, where `<event>` is one of `stage`, `decision`, `question`. It exits 2 on any other event and 3 when no run is `open`. `<stage>` is one of `route`, `plan`, `build`, `learn`, `qa`, `ship`, `fix`, `brainstorm`, `foundation`. For a `stage` row, `<what>` is `ok`, `skipped` or `failed`.
    - `finish <done|stopped> <stage> <reason>` applies only to an `open` run and exits 3 otherwise.
    - `latest` prints the newest `open` or `stopped` trail's path and exits 0, or exits 3 with `no-open-run`.
    - `resume` appends a `resume` row to that trail, making it `open`, and exits 3 with `no-open-run` when there is none.
    - The trail is `$(git rev-parse --git-dir)/ensemble/conductor/<UTC-timestamp>-<pid>.tsv` with columns `ts event stage branch head what why`. Tabs and newlines in a value become single spaces.
    - Compatibility: `/en-flow` is removed with no alias, as the user decided. `setup` and `scripts/sync-to-codex` remove a prior install's skill directories through their manifests, so the old directory does not linger.
- **Files:**
  - `skills/en-conductor/SKILL.md` (create)
  - `skills/en-conductor/scripts/ensemble-conductor-trail` (create)
  - `skills/en-conductor/scripts/ensemble-detect-host` (create)
  - `skills/en-conductor/references/script-invocation.md` (create)
  - `skills/en-conductor/references/plan-or-fix.md` (create)
  - `skills/en-conductor/references/diff-signal-detection.md` (create)
  - `skills/en-flow/SKILL.md` (delete)
  - `skills/en-fix/CONTRACT.md` (create)
  - `skills/en-brainstorm/CONTRACT.md` (create)
  - `skills/en-foundation/CONTRACT.md` (create)
  - `skills/en-plan/CONTRACT.md` (modify)
  - `skills/en-build/CONTRACT.md` (modify)
  - `skills/en-ship/CONTRACT.md` (modify)
  - `skills/en-qa/CONTRACT.md` (modify)
  - `skills/en-learn/CONTRACT.md` (modify)
  - `skills/en-plan/SKILL.md` (modify)
  - `skills/en-plan/references/linear-publish.md` (modify)
  - `skills/en-ship/SKILL.md` (modify)
  - `skills/en-loop/SKILL.md` (modify)
  - `.ensemble/config.local.example.yaml` (modify)
  - `skills/en-setup/references/templates/config-local-example.yaml` (modify)
  - `README.md` (modify)
  - `AGENTS.md` (modify)
  - `docs/foundation.md` (modify)
  - `tests/en-conductor/ensemble-conductor-trail.test.sh` (create)
  - `tests/lint/en-flow.test.sh` (delete)
  - `tests/lint/en-conductor.test.sh` (create)
  - `tests/lint/en-flow-gate-contracts.test.sh` (delete)
  - `tests/lint/en-conductor-gate-contracts.test.sh` (create)
  - `tests/lint/contract-shape.test.sh` (modify)
  - `tests/lint/en-fix.test.sh` (modify)
  - `tests/lint/en-loop-foundation.test.sh` (modify)
  - `tests/lint/en-loop-skill.test.sh` (modify)
  - `tests/lint/en-plan-linear-publish.test.sh` (modify)
  - `tests/lint/en-ship-watch-loop.test.sh` (modify)
  - `tests/lint/host-only-substitutions.test.sh` (modify)
  - `tests/lint/intra-file-step-citations.test.sh` (modify)
  - `tests/lint/readme-catalog-drift.test.sh` (modify)
  - `tests/lint/run-ledgers.test.sh` (modify)
  - `tests/lint/skill-size.test.sh` (modify)
- **Approach:** All of this lands in one commit, because the catalogue lints count directories, `contract-shape.test.sh` derives callees, and `/en-plan` and `/en-build` would lose their only caller if the swap were split.

  **The skill.** Frontmatter `disable-model-invocation: true`, with a description under 300 characters. Process, in order:
  1. Recursion guard on `ENSEMBLE_PEER_REVIEW=true`.
  2. Preflight: `ensemble-detect-host` for `HOST`, resolve `$QUESTION_TOOL`, `git remote` (none records `local_only`, a terminal success), and a tracked-dirty tree stops the run and names the files. It never stashes. Under `$QUESTION_TOOL` absent, apply the rule in the question policy.
  3. Route, stated in one line with the deciding reason. `--resume` goes to the Resume section. `--plan <path>` or a `docs/designs/*.md` input takes the plan route. Words asking to explore or compare options go to brainstorm. A new product, or `docs/foundation.md` absent with a product-shaped request, goes to foundation. A request matching a row of the "named, never invoked" table is named and the run ends: `/en-loop`, `/en-debug` for a diagnosis with no fix wanted, `/en-review`, `/en-qa`, `/en-resolve-pr`, `/en-simplify`, `/en-learn`, `/en-setup`, `/en-sweep`, `/en-test-audit`. Otherwise apply `references/plan-or-fix.md` to the request's words and the content of any file it names: any condition takes the plan route, and none takes the fix route. No diff exists yet, so the diff-signal check stays with `/en-fix`, whose Triage and Risk re-check catch what routing cannot see.
  4. Definition of done: one checkable sentence from the request plus the route's gates, written with `ensemble-conductor-trail start`. Then log the effective flags with `log decision route options <flags>`, writing `none` when there are none.
  5. Run the route's stages per the table below, logging each with `log stage` and printing one line per stage.
  6. Report: route, definition of done and whether it holds, stages, every decision from the trail, and PR URL with exit state. The last line is the done marker.

  **Stage table.** Use these literal verbs, because `contract-shape.test.sh` derives callees from them: invoke `/en-plan`, invoke `/en-build`, invoke `/en-learn`, invoke `/en-qa`, invoke `/en-ship`, invoke `/en-fix`, invoke `/en-brainstorm`, invoke `/en-foundation`.

  | Stage | Where | Invocation | Gate |
  |---|---|---|---|
  | Plan | session | `/en-plan --orchestrated --branch-on-default y <request>`, skipped under `--plan` | plan file at `status: open`. `draft` stops and names `/en-plan --resume`. A `plan_store: linear` refusal stops and repeats its next command |
  | Build | agent, or session | `/en-build <plan-path> --orchestrated` | audit `verdict: ok` and a `review-verdict:` trailer. `gate_required: U<N>` or `needs-decision: U<N>: <question>` reruns `/en-build <plan-path> --from U<N> --orchestrated` in session, where the skill's own prompt reaches the user |
  | Learn | session | `/en-learn capture`, only under the Learn rule below | logged as a `decision` either way, never asked |
  | QA | agent | `/en-qa`, only when `needs_browser` is true for the branch diff | every system check passes and no flow is `Fail`. A `Fail` stops the run before Ship and names the flow |
  | Ship | agent | `/en-ship`, adding `--no-watch` when given; never `--auto-merge`; skipped under `--no-ship` or `local_only` | records the exit state. `clean` and `settled-externally` are done, `escalated` names the open findings, and `blocked` attempted no repair and is not evidence about the code, so it is reported verbatim and not rerun. The watch loop is capped at 2 cycles |
  | Fix | agent | `/en-fix <request> --orchestrated`, adding `--no-ship` under `--no-ship` or `local_only`, and `--no-watch` when given | branch on the seven `en-fix:` lines |
  | Brainstorm, Foundation | session | as named | ends the run, naming `/en-conductor <design-path>` or the next command |

  **Learn rule.** Every orchestrated build records `ci_environment`, so that value decides nothing. Capture when the branch shows at least one of: a `Scope widened:` line in a commit body, a P0 or P1 applied in the review, a logged redispatch or fallback, or a logged `needs-decision`. Otherwise log `decision learn skip` with the reason. `/en-learn` applies its own gate and writes nothing that fails it, so a false positive costs one read.

**QA and Ship with no question tool.** Both contracts allow it: `/en-qa` never blocks when a caller drives, and `/en-ship` is hands-off by default. A stop from either is reported as a stop, never rerun. `/en-ship`'s typed confirmation for a push to the default branch cannot arise, because the plan route leaves the default branch at the Plan stage.

**Build placement.** Build in session when `HOST` is not `claude-code`, or when `grep -Eiq '^- \*\*(Risk:\*\* (destructive|high)|Gated:\*\* true)' <plan-path>` matches. Otherwise use a fresh subagent. Under `--no-ship` or `local_only`, the plan route skips Ship, logs `stage ship skipped <reason>`, and the report names the branch and says nothing was pushed.

  **Fix outcomes.** `shipped` confirms the PR, and applies the Ship row's exit-state meaning. `ready` reports the branch and that nothing was pushed. `needs-plan clean` takes the plan route and logs `decision route plan <condition>`. `needs-plan edited` stops, names the condition and says the edits are on the branch, since whether to keep them is the user's call. `needs-decision` applies the question policy and redispatches with `--decision "<question>: <answer>"`, and stops after two redispatches. `split` reports each concern as its own `/en-conductor <concern>`. `stopped` is reported verbatim. To lift a risk stop, the report tells the user to run `/en-fix` directly, because D142 needs their own words in that conversation.

  **Stage agent brief, fixed text in the skill.** "Invoke the skill named below with these exact arguments. You have no way to ask the user: anything you would ask ends your turn with the question stated. Return the skill's contract fields verbatim, and its last line unchanged." An agent that returns none of the stage's contract fields, or a refused `Agent` call, reruns that stage once in session and logs `decision <stage> fallback <why>`. Before each agent stage the conductor records `HEAD`. It reruns only when `HEAD` is unchanged, `git status --porcelain --untracked-files=no` is clean, and, for Ship and Fix, `gh pr view` finds no PR for the branch. Otherwise it stops and reports the new commits, edits or PR, so a rerun never repeats work that already landed. A person continues from there with `--resume`.

  **Resume.** `--resume` reads `ensemble-conductor-trail latest`, and exits with a message on `no-open-run`. It calls `resume`, then reads the route from the last `decision route plan` row or else the `start` row, the flags from the `decision route options` row, and the plan path from the `plan` stage row's evidence. Flags given with `--resume` are refused, so a `--no-ship` run cannot lose its restriction. A stage counts as finished only on a `stage` row whose `what` is `ok` or `skipped`. If any such row exists, the last one's `branch` and `head` must equal the current branch and `HEAD`. If either differs, the run stops and names both, because earlier Build or QA results may no longer describe the code. It then continues at the first unfinished stage, re-invoking the skill: `/en-build`'s unit loop records finished units `already-satisfied`, and `/en-ship` updates an existing PR. A `stopped` run resumes the same way.

  **Contracts.** New `en-fix`, `en-brainstorm` and `en-foundation` contracts with the six required sections. `en-brainstorm` and `en-foundation` state a non-interactive guarantee of none: a caller runs them in the user's session. `en-fix` lists the seven outcomes. Add `en-conductor` as caller in the `en-plan`, `en-build`, `en-ship`, `en-qa` and `en-learn` tables, and remove `en-flow`.

  **Docs.** Add D143 to `docs/foundation.md` §4.1, amending D124, D138 and the v1 scope lines at `:88` and `:109`, and citing the 2026-11-04 capability check. Rewrite §5.1 row 15, the §5 intro list and §5.2.9 for `en-conductor`, and update §5.1 row 18, §5.2.18 and `README.md:325` for `en-fix`. `README.md:122` box and `:322` row change. `AGENTS.md:71` becomes "One entry point: routes the request, plans if needed, through to a PR | `/en-conductor <request>` *". Update the `en-loop` line 31 positioning and the `foundation.md:525` copy of it.

  **Copies.** `skills/en-conductor/references/plan-or-fix.md` is copied from `skills/en-fix/references/`, `diff-signal-detection.md` from `skills/en-fix/references/`, `script-invocation.md` from `skills/en-fix/references/`, and `scripts/ensemble-detect-host` from `skills/en-loop/scripts/`. `tests/parity/reference-parity.test.sh:27-41` and `script-parity.test.sh:30-43` discover copies by basename, so no list needs editing. `en-plan-warranted-gate.test.sh:113-114` compares only the `en-fix` and `en-plan` copies, and parity covers the third. `skills/en-flow/` holds only `SKILL.md`, so deleting it removes the directory.

**Rename checklist, run and record in the commit body.**
  - [ ] `.md`: `git grep -n 'en-flow' -- '*.md'` returns only `docs/plans/completed/`, `docs/plans/active/EN27-*`, `docs/reviews/`, `docs/designs/`, `docs/generated/`, the D-entries D57, D69, D70, D77, D84, D90, D98 and the line at `foundation.md:276`, and tracker entry TD18.
  - [ ] `.env` and config: `.ensemble/config.local.example.yaml:33` and its template copy now cite `/en-ship`.
  - [ ] Comments: the test comments at `contract-shape:14`, `host-only-substitutions:14`, `intra-file-step-citations:37`, `readme-catalog-drift:21`, `skill-size:20-21` and `en-loop-foundation:78,106` are updated. Where one records a past negative control, keep the fact and say it was run against `en-flow`.
  - [ ] Strings: `git grep -n 'en-flow' -- skills tests setup scripts hooks .claude-plugin .codex-plugin .github` returns only the kept history comments above.
  - [ ] Generated files: `docs/generated/` and `docs/learnings/index.md` are not hand-edited.
  - [ ] External references: the plugin manifests glob `./skills`, so they need no edit, and the install manifest prunes the old directory. Say in the PR body that `/en-flow` is gone.

  **Tests.** `en-conductor.test.sh` replaces `en-flow.test.sh`, and ends in one `report` call after every assertion, which fixes the stray bare line at `en-flow.test.sh:41` that stopped that file after 4 assertions. `en-conductor-gate-contracts.test.sh` keeps the `status: open`, `verdict: ok` and `/en-review` flag pins of `en-flow-gate-contracts.test.sh` against `skills/en-conductor/SKILL.md`, and adds the seven `en-fix:` spellings against `skills/en-fix/CONTRACT.md`, and `gate_required` and `needs-decision` against `skills/en-build/CONTRACT.md`. Its four `learning_checkpoint` value pins move to `en-build-learning-checkpoint.test.sh`, since the conductor no longer branches on them, and the decline pin goes with them. `en-ship-watch-loop.test.sh:77`, `en-loop-skill.test.sh:148-152`, `run-ledgers.test.sh:21` (now pinning `ensemble-conductor-trail`) and `en-plan-linear-publish.test.sh` retarget. `en-fix.test.sh:62-64` flips to require `skills/en-fix/CONTRACT.md`.
- **Risk:** medium
- **Category:** removal
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path, trail:* `start` then `log stage build ok evidence` then `finish done ship reason` writes four rows with seven columns each, and `latest` then exits 3.
  - *Edge case, trail:* a value holding a tab and a newline is stored on one row with seven columns. A second `start` while a run is open writes `superseded` to the first file and names it on stderr. `finish stopped` leaves `latest` printing that file.
  - *Edge case, trail:* after `finish stopped build reason`, `log` and `finish` exit 3, `resume` makes `log` work again, and `finish done` then leaves `latest` exiting 3.
  - *Error path, trail:* `log bogus x y z` exits 2. `log` with no open run exits 3. Outside a git repo, every subcommand exits non-zero with a message and writes nothing.
  - *Integration, trail:* run from a linked worktree, it writes under that worktree's git dir, and the main checkout's `latest` does not see it.
  - *Happy path, skill:* `en-conductor.test.sh` asserts the manual flag, the recursion guard, the three question-policy branches in that order, the no-question-tool rule, Ship skipped under `--no-ship` on the plan route, `--resume` refusing flags and stopping on a changed `HEAD`, the fallback's `HEAD` and PR checks, the Learn rule, the stages in order, the build-placement grep, the fallback rule, "never `--auto-merge`", the done marker, and that `/en-loop` is named but never follows an invoke verb.
  - *Integration, skill:* `contract-shape.test.sh` passes with `en-fix`, `en-brainstorm` and `en-foundation` as derived callees carrying six-section contracts. `foundation-catalog-drift`, `readme-catalog-drift`, `skill-payload` and `en-loop-foundation` pass with eighteen skills.
  - *Error path, skill:* negative controls, run once and recorded in the test header: swapping the question policy's second and third branches turns `en-conductor.test.sh` red, removing `verdict: ok` turns the gate-contracts test red, and deleting `skills/en-fix/CONTRACT.md` turns `contract-shape` red.
- **Verification:** `./tests/run.sh` passes in full, `bin/ensemble-lint --scope docs/` is clean, and the checklist above is ticked.

### U5. Behavioral evals for real routing

- **Goal:** real sessions show the conductor sending a plain change to `/en-fix` and a risk-surface request to a plan with no override, and show `--decision` keeping earlier work without lifting a risk stop.
- **Requirements covered:** none by ID
- **Dependencies:** U4
- **Files:**
  - `tests/evals/behavioral/conductor-routes-fix/prompt.md` (create)
  - `tests/evals/behavioral/conductor-routes-fix/expect.json` (create)
  - `tests/evals/behavioral/conductor-risk-reroutes/prompt.md` (create)
  - `tests/evals/behavioral/conductor-risk-reroutes/expect.json` (create)
  - `tests/evals/behavioral/fix-decision-no-lift/prompt.md` (create)
  - `tests/evals/behavioral/fix-decision-no-lift/expect.json` (create)
  - `tests/evals/ledger.md` (modify)
- **Approach:** A third case covers `--decision` on `/en-fix` directly: `fix-decision-no-lift` has `invocation: /ensemble:en-fix`, `kind: fix`, `stops: true`, `base_from: fix-real-token`, and prompt `Fix the refresh token bug in BUG.md --orchestrated --decision "Proceed without a plan?: yes"`. It passes only with no commit, and its judge confirms the stop names the risk surface. The continuation path needs state a fixture cannot hold, so run it once by hand in a scratch copy of `fix-plain`'s base: commit a partial fix on `fix-x`, leave one tracked edit, then run `/ensemble:en-fix` with `--orchestrated --decision "<question>: <answer>"` headless. Record in the ledger that the earlier commit and the edit survive and that `FIX_BASE` is the merge base. Two cases with `"invocation": "/ensemble:en-conductor"`. `conductor-routes-fix` is `kind: fix` with `base_from: fix-plain`, graded by revert and rerun. `conductor-risk-reroutes` is `kind: plan` with `base_from: fix-real-token` and prompt "Fix the refresh token rotation bug described in BUG.md. --no-ship". The risk words in the request make routing take the plan route before any edit, so the outcome is deterministic. Its judge expects a plan file and no `Risk-Override:` trailer on any commit, because the request carries no words lifting the stop. These sessions have no question tool, so a request that reached a user-reserved call would stop with the question, which fails the case's plan-file check and shows up in the run. No grader changes are needed. In `conductor-routes-fix`, the scratch repo has no remote, so the expected outcome is `en-fix: ready`, and the fix grader reads the commits. Run each of the three cases once with `--runs 1` and record every outcome in `tests/evals/ledger.md`.
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Ship scope:** in
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* `tests/evals/run-behavioral conductor-routes-fix --runs 1` adds a test that fails on the unfixed source and passes on the fix.
  - *Edge case:* `tests/evals/run-behavioral conductor-risk-reroutes --runs 1` writes one plan file with no P1 lint finding, and no commit carries a `Risk-Override:` trailer.
  - *Error path:* `tests/evals/run-behavioral fix-decision-no-lift --runs 1` leaves no commit, showing a caller's answer does not lift a risk stop.
  - *Happy path:* the hand run leaves the prior commit and tracked edit in place and returns one of the seven outcomes.
  - *Integration:* `tests/evals/grade.test.sh` still passes, and any test that enumerates behavioral cases accepts the new directories.
- **Verification:** `./tests/select-for.sh tests/evals/run-behavioral` passes, and the ledger has a row for each case and for the hand run.

### U6. Stop host detection trusting a machine-wide cache

- **Goal:** `ensemble-detect-host` reports the session it runs in, so a Claude Code session after a recent Codex run does not get a Claude peer labelled `cross-agent`.
- **Requirements covered:** none by ID
- **Dependencies:** U4
- **Files:**
  - `skills/en-conductor/scripts/ensemble-detect-host` (modify)
  - `skills/en-foundation/scripts/ensemble-detect-host` (modify)
  - `skills/en-loop/scripts/ensemble-detect-host` (modify)
  - `skills/en-plan/scripts/ensemble-detect-host` (modify)
  - `skills/en-review/scripts/ensemble-detect-host` (modify)
  - `skills/en-test-audit/scripts/ensemble-detect-host` (modify)
  - `skills/en-foundation/references/host-detect.md` (modify)
  - `skills/en-plan/references/host-detect.md` (modify)
  - `skills/en-review/references/host-detect.md` (modify)
  - `tests/host-detect/host-detect.test.sh` (modify)
- **Approach:** Observed on 2026-11-04 in EN27's first peer pass: `~/.ensemble/host-cache.env` held `HOST=codex` and was read before any live signal, so a Claude Code session used a Claude peer and reported `cross-agent`. An explicit `ENSEMBLE_HOST=claude-code` lost to the same cache. Two changes, applied to every copy so they stay byte-identical. First, resolve `HOST` before reading the cache, and key the file by host: `host-cache-$HOST.env`, keeping `ENSEMBLE_DETECT_CACHE_FILE` as an exact override for tests. Only the slow peer probe stays cached. Second, add `CLAUDECODE` and `CLAUDE_CODE_ENTRYPOINT` to the Claude Code live signals, because this session sets those and neither `CLAUDE_CODE_VERSION` nor `CLAUDE_AGENT_NAME`. The old `host-cache.env` is ignored and left in place. Keep the existing precedence: live signals, then `ENSEMBLE_HOST`, then the inverse-CLI fallback. This unit follows U4, so it updates the conductor's copy along with the rest. Update the cache section of every `references/host-detect.md` copy, which names the old path, keeping them byte-identical. `tests/host-detect/host-detect.test.sh:208-222` asserts the old filename and moves to the keyed one.
- **Risk:** medium
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* with a fresh `host-cache-codex.env` present, `CLAUDECODE=1` reports `HOST=claude-code` and `PEER=codex`.
  - *Edge case:* with `CODEX_HOME` set and a fresh `host-cache-claude-code.env` present, it reports `HOST=codex`, and the other file is untouched.
  - *Edge case:* with `ENSEMBLE_HOST=claude-code`, no live signal and a fresh `host-cache-codex.env` present, it reports `HOST=claude-code`.
  - *Error path:* a second run with the same host and a fresh file reads the cache, so the peer probe does not rerun. Deleting the host key from the cache path turns the first scenario red.
- **Verification:** `./tests/run.sh -k host-detect` and `tests/parity/script-parity.test.sh` pass.

## Decisions, assumptions & risks

- **Decision:** Stages run in fresh subagents on Claude Code, and in session when they may ask. Decided by the user on 2026-11-04 after the capability check.
- **Decision:** The trail lives in `.git/ensemble/conductor/`. Decided by the user on 2026-11-04, which is why this plan changes no `.gitignore` and no scaffold.
- **Decision:** `/en-brainstorm` and `/en-foundation` are invoked and get contracts, rather than being named with the verb "run". D85 records that verb hiding a real caller from the lint.
- **Decision:** The `ci_environment` value is reused under `--orchestrated`, because the four values are pinned and its meaning, nobody was asked, is exact.
- **Decision:** One TSV per run, not `state.json` and a separate decision log. Stage results and decisions read in time order, and resume needs only the rows.
- **Alternative:** Reading `../en-fix/SKILL.md` instead of removing the flag. Rejected by the user, and it sidesteps the reason the flag exists.
- **Alternative:** `claude -p` per stage. It has the same missing question tool as a subagent, and adds a process to supervise and permissions to manage.
- **Alternative:** Keep `/en-flow` as an alias. Rejected: it keeps two names for one job, and the user asked to replace it.
- **Assumption:** A build reaching depth 2, stage agent to reviewer agent, behaves like the PONG probe. Only the capability was checked, not a real `/en-build`. The fallback rule covers a failure, and `conductor-routes-fix` is the first real exercise, since `/en-fix` invokes `/en-review` inside a stage agent.
- **Decision:** `/en-fix` reports whether it edited in the `needs-plan` line, rather than the conductor inferring it from `git status`. Triage precedes the Branch step, so `clean` is exact, and a pre-existing untracked file cannot cause a false stop.
- **Decision:** The trail has an explicit `resume` subcommand and three run states, because a `stopped` run must be resumable without counting as live for `log`.
- **Assumption:** An agent that hits a typed gate with no question tool stops rather than guessing. U2 states the rule, and the grep in Build placement means it should rarely be reached.
- **Risk:** Without its manual flag, `/en-fix` can start on "fix this bug" in any session and open a PR. **Mitigation:** the user accepted this and will revisit it if it fires unwanted; `/en-ship`, already model-invocable, sets the precedent.
- **Risk:** A long stage agent gives the user no output until it returns. **Mitigation:** one line per stage, and the trail on disk, which shows the last finished stage.
- **Risk:** `docs/foundation.md` D-entries keep naming `/en-flow`, which could mislead a reader. **Mitigation:** D143 states the replacement, and rewriting history would break D-ID stability.

## Tracked debt

None resolved. TD18 is already resolved and stays as history.

## Iteration log

> - 2026-11-04 (initial): plan v0 from the conversation's analysis of `poteto-mode` and the user's decisions.
> - 2026-11-04 (iteration 1): peer returned revise with 9 P1 and 6 P2 findings, all applied. That pass ran Claude reviewing Claude because of the cache bug it exposed, now U6, so iteration 2 runs with the cache off and a Codex peer.
> - 2026-11-04 (iteration 2): Codex returned revise with 5 P1 and 1 P2 findings. All P1s applied, including the question-policy order, which had let the conductor decide reversible product calls. U6's scope finding disagreed with rationale. The peer cap is reached.
> - 2026-11-04 (promotion): the user accepted the plan as-is at the peer cap, with the verdict at revise and the final fixes not re-reviewed.
