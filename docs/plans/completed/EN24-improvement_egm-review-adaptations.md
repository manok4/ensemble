---
type: plan
plan_type: improvement
plan_id: EN24
title: Adapt the useful parts of the Elephant-Goldfish Model into review and planning
status: completed
location: completed
created: 2026-10-29
shipped: 2026-10-30
deepened:
covers_requirements: []
requirements_pending: false
related_design:
peer_review_verdict: revise
peer_review_iterations: 2
peer_review_last_run: 2026-10-29
peer_review_plan_hash: 3183570c119316afa7beca4a95f50e47ad6c45ffa90e4f758f2b0637ddeb7144
# Machine-readable resolution log written by /en-plan as findings are
# applied/deferred/disagreed/superseded. /en-build pre-flight reads this
# directly — never the iteration-log prose.
peer_review_resolutions:
  - finding_id: 1-1
    iteration: 1
    severity: P1
    title: Remaining tools can bypass read-only restrictions
    status: applied
    rationale: U1 goal narrowed to what frontmatter can enforce; residual Write/Bash recorded as a risk with the hook alternative and why it was rejected
    location: U1
  - finding_id: 1-2
    iteration: 1
    severity: P1
    title: Severity caps can downgrade build-changing defects
    status: applied
    location: U3, U5, U6, Decisions (re-raised in iteration 2 for U5; H no longer capped, goal-less units route to check A)
  - finding_id: 1-3
    iteration: 1
    severity: P1
    title: File existence lint rejects valid multi-unit plans
    status: applied
    location: U4
  - finding_id: 1-4
    iteration: 1
    severity: P1
    title: Growth counts cannot identify what was added
    status: applied
    location: U7
  - finding_id: 1-5
    iteration: 1
    severity: P1
    title: Escalation routing assumes a conditional question occurs
    status: applied
    location: U8, Decisions
  - finding_id: 2-1
    iteration: 2
    severity: P1
    title: Metrics emission adds mandatory hot-path output
    status: applied
    location: U9
  - finding_id: 2-2
    iteration: 2
    severity: P1
    title: Live restriction test lacks an effective negative control
    status: applied
    location: U10
depth: deep
data_scale: small
---

# EN24 — Adapt the useful parts of the Elephant-Goldfish Model into review and planning

## Context

Google's Elephant-Goldfish Model (EGM) reviews design docs with zero-context reviewer agents. A static comparison (`docs/reviews/elephant-goldfish-model-comparison.md`) and a follow-up outline (`docs/reviews/egm-adaptation-outline.md`, 2026-10-29) picked out nine pieces worth adapting: enforced read-only agents, fail-closed reviewers, an evidence rule for rejecting peer findings, three plan-review checks, a plan file-reference check, a scope-growth check and transcript-based behaviour tests. A tenth, `omitClaudeMd`, is postponed. This plan builds the nine.

Hard constraint, from the outline: **no new latency.** No new model call, dispatch or stage; no new re-review trigger; no new point where a run waits for the user; no added output tokens on a hot-path call. Every unit states how it meets this.

## Requirements covered

none. Ensemble's foundation carries no R-IDs for review internals; the outline is the source.

## Out of scope for this plan

- Item 10 of the outline (`omitClaudeMd` on retrieval agents). Postponed with revisit conditions recorded in the outline.
- EGM's five-stage pipeline, duplicate A/B reviewers, synthesizer, Structural and Style agents, persona brainstorm lenses. Rejected in the outline.
- A plan-peer reuse check. It needs `--access read-tree`, which doubles the peer's timeout budget (600 s to 1200 s). Reuse stays with `repo-research`.
- `en-resolve-pr`'s six-verdict rubric for human comments. It is a separate path from peer resolutions.
- Per-agent read-only enforcement on Codex. Codex custom-agent TOML has no `tools` field and cannot override `sandbox_mode` per agent; subagents inherit the parent session's sandbox (Codex docs, checked 2026-10-29). See Decisions.

## Approach (high-level)

Four phases in the outline's order. **Phase A** (U1-U4) is local: agent frontmatter, one reviewer status, one pre-write check, one lint rule. None touches a shared contract except the `finding-schema.md` field in U2, which is optional and additive. **Phase B** (U5-U7) changes only en-plan's peer brief, finalize loop and its prompt builder. **Phase C** (U8-U9) changes the shared resolution-status enum, so every carrier of `peer-contract.md` and the skills that record resolutions change together on one branch, with the parity tests holding them in step. **Phase D** (U10) adds opt-in live tests for U1 and U2's behaviour, off CI.

Everything lands in files that already run. Prompt additions go into prompts that are already sent. Checks are either deterministic (lint, counts) or the host's own reasoning at a step it already performs. The two places that could have added a re-review (U3, U5) are pinned to P2/P3, which `finalize-loop.md` never re-invokes on. The one place that could have added a user wait (U8's `escalated`) joins questions the loop already asks.

## Test seams

All existing; no new seam.

- **Lint fixtures through `bin/ensemble-lint`** (`tests/lint/lint-rules.test.sh`): plan-shape rules, the resolution-status enum.
- **The built peer prompt** (`tests/build-peer-prompt/build-peer-prompt.test.sh`): what en-plan actually sends the peer, observed as the builder's output, not the brief's prose.
- **Text guards over skill and agent files** (`tests/lint/*.test.sh`, the established pattern): presence of a rule in the file the model reads, each with a negative control recorded in the test.
- **Parity tests** (`tests/parity/peer-contract-parity.test.sh`, `tests/parity/script-parity.test.sh`, `tests/parity/reference-parity.test.sh`): byte-identity of every copied file this plan edits.
- **Opt-in live transcripts** (`tests/portability/`, the `live-anchor-hosts.test.sh` pattern): U10 only.

## Technical design

Triggered: more than three changed components. Directional only.

```
plan drafting ──► plan-prewrite (U3 zero-decision, host reasoning)
      │
      ▼
plan file ──► bin/ensemble-lint (U4 Files markers + existence)  ◄── already run by finalize-loop
      │
      ▼
ensemble-build-peer-prompt (en-plan)
   brief: + check H (U5, P2/P3) + summary = paraphrase (U6) + zero-decision P2 line (U3)
   --plan-before on the re-review only: counts + capped diff (U7)
      │
      ▼
peer findings ──► host routing (peer-brief table)
   disagreed needs readable evidence; else escalated (U8)
   escalated ──► existing P1<7 surface / cap-hit question; hands-off: stays escalated
      │
      ▼
peer_review_resolutions (status enum + escalated, U8) ──► lint enum, en-build preflight
run record outcome event (+escalated, U9)

review personas (en-review --cross/--host):
dimension-reviewer (tools: Read, Grep, Glob; U1) ──► {"status":"incomplete","unreadable":[...]} (U2)
   ──► persona-dispatch: drop, name in report, no retry
```

Key interface names, used verbatim across units:

- Reviewer response, optional top-level fields: `"status": "complete" | "incomplete"` (absent means `complete`) and `"unreadable": ["<path>", ...]`.
- Resolution status enum: `applied | deferred | disagreed | superseded | escalated`.
- Lint rules: `unit.files-missing` (P1), `unit.files-unmarked` (P2).
- Files markers: `(create)`, `(modify)`, `(delete)`; `(new)` accepted as an alias of `(create)`.
- Prompt-builder flag: `--plan-before <path>` (the plan as it stood when the previous pass reviewed it).
- Live-test switch: `ENSEMBLE_LIVE_BEHAVIOUR_TEST=1`.

## Implementation units

Each unit has a stable U-ID. Never renumbered after assignment.

### U1. Enforce read-only on bundled agents through frontmatter

- **Goal:** Every bundled agent that calls itself read-only loses, by Claude Code configuration rather than by prose, every mutating tool it has no use for. Agents that still need `Write` (scratch dossiers) or `Bash` (`git blame`) keep exactly that tool, and the residual is recorded, not claimed as enforced.
- **Requirements covered:** none
- **Dependencies:** none
- **Files:**
  - `skills/en-review/agents/dimension-reviewer.md` (modify)
  - `skills/en-test-audit/agents/test-lane-auditor.md` (modify)
  - `skills/en-plan/agents/repo-research.md` (modify)
  - `skills/en-debug/agents/repo-research.md` (modify)
  - `skills/en-foundation/agents/repo-research.md` (modify)
  - `skills/en-sweep/agents/repo-research.md` (modify)
  - `skills/en-plan/agents/learnings-research.md` (modify)
  - `skills/en-learn/agents/learnings-research.md` (modify)
  - `skills/en-review/agents/learnings-research.md` (modify)
  - `skills/en-plan/agents/web-research.md` (modify)
  - `skills/en-brainstorm/agents/web-research.md` (modify)
  - `skills/en-brainstorm/agents/repo-fact-lookup.md` (modify)
  - `skills/en-simplify/agents/code-simplifier.md` (modify)
  - `tests/lint/agent-tool-restrictions.test.sh` (create)
- **Approach:** Three groups, because the research agents write evidence dossiers to `/tmp/ensemble/...` with `Write`, and taking `Write` away would push them onto the inline fallback, which adds output tokens to the host:
  - **Pure readers**, `dimension-reviewer` and `test-lane-auditor`: `tools: Read, Grep, Glob`. The reviewer reads the diff from the file en-review writes (`en-review/SKILL.md:56`), so it needs no shell; the auditor's `grep -n` is the Grep tool.
  - **Research agents that write a dossier**, `repo-research`, `learnings-research`, `repo-fact-lookup`, `web-research`: `disallowedTools: Edit, NotebookEdit, Bash`. A denylist, not an allowlist, so `web-research` keeps its Context7 MCP tools, whose names differ between plugin and standalone installs. `Write` stays for the dossier.
  - **`code-simplifier`**: `disallowedTools: Edit, Write, NotebookEdit`. It keeps `Bash` for `git blame` (`code-simplifier.md:31`).
  **What this does not enforce.** Claude Code documents no path-scoped form of `tools` (`Write(/tmp/**)`), a specifier in `disallowedTools` removes the whole tool, and frontmatter `hooks` are ignored for plugin-installed subagents (sub-agents docs, read 2026-10-29). So the four research agents can still `Write` anywhere and `code-simplifier` can still run any `Bash`; for those two tools the prose rule and the parent session's permissions remain the control. Each affected agent's body gets one sentence naming the one permitted use (`Write` only to `/tmp/ensemble/<skill>/<run-id>/`; `Bash` only for `git blame`, `git log` and `git show`), and the residual is listed under Decisions.
  Keep every copy of a duplicated agent byte-identical. Add the field after `effort:` so setup's effort rewrite (`setup:253-257`) leaves it untouched. The test reads every `skills/*/agents/*.md`; for each whose description says "Read-only" or whose body forbids edits, it requires a `tools:` line that lists none of Edit, Write, NotebookEdit, or a `disallowedTools:` line that includes Edit and NotebookEdit. It also checks that the Codex TOML render still succeeds with the new field present (re-using the setup harness from `tests/install/codex-toml-agents.test.sh` by running that test, not duplicating it).
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* all 13 agent files carry their group's line → the test passes, and `tests/install/codex-toml-agents.test.sh` still passes.
  - *Error path:* remove the `tools:` line from `dimension-reviewer.md` → the test fails naming that file (negative control, recorded in the test header).
  - *Error path:* add `Edit` to `test-lane-auditor.md`'s `tools:` list → the test fails.
  - *Edge case:* a `disallowedTools:` line that omits `NotebookEdit` → the test fails.
  - *Edge case:* a research agent whose body lacks the sentence limiting `Write` to `/tmp/ensemble/` → the test fails; the same for `code-simplifier` and its `Bash` sentence.
  - *Integration:* run `./setup --copy` into a temp HOME with an `agent_effort_claude_*` key set → the rendered copy keeps the `tools:`/`disallowedTools:` line next to the injected `effort:`.
- **Verification:** `tests/lint/agent-tool-restrictions.test.sh` and `tests/install/codex-toml-agents.test.sh` pass; negative controls confirmed red; `tests/lint/agent-dispatch-resolves.test.sh` still passes.

### U2. A reviewer that cannot read its inputs returns `incomplete`

- **Goal:** A persona that could not open the diff file or a named reference reports that, instead of returning an empty findings array that reads as a clean pass.
- **Requirements covered:** none
- **Dependencies:** none
- **Files:**
  - `skills/en-review/agents/dimension-reviewer.md` (modify)
  - `skills/en-review/references/persona-dispatch.md` (modify)
  - `skills/en-review/references/finding-schema.md` (modify)
  - `skills/en-plan/references/finding-schema.md` (modify)
  - `skills/en-build/references/finding-schema.md` (modify)
  - `skills/en-foundation/references/finding-schema.md` (modify)
  - `skills/en-test-audit/references/finding-schema.md` (modify)
  - `tests/lint/reviewer-fail-closed.test.sh` (create)
- **Approach:**
  - `finding-schema.md` (all five copies, byte-identical): add two optional top-level fields, `status` (`complete` | `incomplete`, absent means `complete`) and `unreadable` (array of paths), with one row each in the field table. An `incomplete` response carries `findings: []` and `verdict: approve` is not allowed with it.
  - `dimension-reviewer.md`: under "What you return", add the rule. If the diff file or a reference named in your prompt cannot be read, return `"status": "incomplete"` with the paths in `unreadable`. Keep the existing "Return an empty findings array when you find nothing" sentence and scope it to a review that read its inputs.
  - `persona-dispatch.md`: Synthesis step 1 treats `incomplete` as a failed persona: drop it from synthesis and name the persona and its unreadable paths in the summary, as a timed-out persona is today. Add a Failure protocol row: "One persona returns `incomplete`: drop, name the unreadable paths, **no retry** (a retry cannot make a missing file readable)."
  - The test greps each file for its rule and runs the reference-parity check on the five schema copies.
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* the five `finding-schema.md` copies are byte-identical and each documents `status` and `unreadable` → test passes.
  - *Error path:* delete the no-retry row from `persona-dispatch.md` → test fails (negative control).
  - *Error path:* edit one `finding-schema.md` copy only → parity fails naming the drifted copy.
  - *Edge case:* `dimension-reviewer.md` still says "Return an empty findings array" without scoping it to inputs that were read → test fails.
- **Verification:** new test passes with its negative controls; `tests/parity/reference-parity.test.sh` passes; full suite green.

### U3. Settle every decision in the plan, not in the build

- **Goal:** A unit that leaves the implementer to choose a schema, API path, dependency or edge-case policy is caught before the plan is written, and by the peer at its impact-based severity if it slips through.
- **Requirements covered:** none
- **Dependencies:** none
- **Files:**
  - `skills/en-plan/references/plan-prewrite.md` (modify)
  - `skills/en-plan/SKILL.md` (modify)
  - `skills/en-plan/references/peer-brief.md` (modify)
  - `tests/build-peer-prompt/build-peer-prompt.test.sh` (modify)
  - `tests/lint/en-plan-zero-decision.test.sh` (create)
- **Approach:**
  - `plan-prewrite.md`: add a sixth check, **Zero decisions left to the implementer**: for each unit, could a worker holding only this unit build it without choosing a schema, API path or signature, dependency, or edge-case or error policy? If not, settle the choice in the unit or record it under `## Decisions, assumptions & risks`. Heading becomes "The six checks".
  - `SKILL.md` step 13: "run its five checks" becomes "run its six checks" and the list gains "zero decisions left to the implementer". Byte cost under 60 bytes; check the SKILL.md budget test.
  - `peer-brief.md`: add dimension **H0** (named so U5's H stays free) under "What the peer is asked": "A unit buildable only after the implementer chooses a schema, API path, dependency or edge-case policy the plan does not fix." Severity stays impact-based, as the brief already requires: **P1** when the open choice changes a signature another unit consumes, or is a bet the plan states nowhere (both already P1 today, so this adds no new re-review trigger); **P2** otherwise, with the fix stated as the decision to write in. The pre-write check exists so these are settled before the peer sees the plan.
  - Extend the prompt-builder test to assert the H0 line appears in en-plan's built prompt.
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* `ensemble-build-peer-prompt --brief skills/en-plan/references/peer-brief.md ...` output contains the H0 text and both severity lines (P1 for a cross-unit signature or unstated bet, P2 otherwise) → passes.
  - *Error path:* a brief that caps H0 at P2 unconditionally → the test fails.
  - *Error path:* remove the sixth check from `plan-prewrite.md` → `en-plan-zero-decision.test.sh` fails (negative control).
  - *Edge case:* SKILL.md says "five checks" while `plan-prewrite.md` lists six → the test fails on the count mismatch.
- **Verification:** both tests pass; `tests/lint/en-plan-cost-contract.test.sh` and `tests/lint/skill-size.test.sh` pass.

### U4. Mark plan file paths and lint that cited files exist

- **Goal:** A plan that cites a file to modify or delete that does not exist fails lint at planning time, and a plan without markers gets one advisory.
- **Requirements covered:** none
- **Dependencies:** none
- **Files:**
  - `skills/en-plan/references/templates/plan-template.md` (modify)
  - `skills/en-foundation/references/templates/plan-template.md` (modify)
  - `bin/ensemble-lint` (modify)
  - `skills/en-setup/references/templates/ensemble-lint` (modify)
  - `tests/lint/lint-rules.test.sh` (modify)
  - `tests/linear-plan/linear-plan.test.sh` (modify)
- **Approach:**
  - Template (both copies byte-identical): the `Files:` line shows markers, `<path> (create|modify|delete)`; the Files-field generation notes require one marker per path, accept `(new)` as `(create)`, and keep globs. The worked excerpt's `(new)` entries stay valid. Add both new rules to the template's "Lint rules" list.
  - `bin/ensemble-lint`, plan scope only, alongside the existing `unit.*` rules. Parse each unit's `Files:` field, inline or as nested bullets; take each backticked path with its marker.
    - `unit.files-missing` (**P1**): a `(modify)` or `(delete)` path that does not exist relative to the repo root (for a glob, matches nothing) **and** is not marked `(create)` by a unit listed earlier in the plan. Plan order is the build order (en-build runs units in plan order), so a file created in U1 and modified in U2 passes, while one created only in a later unit is reported as "modified before it is created".
    - `unit.files-unmarked` (**P2**): any path with no marker. Emit **once per plan**, naming the count and the first unit, not once per path. Older plans in `active/` therefore pass with an advisory.
    - Paths marked `(create)` are never checked for existence (EGM: proposed files are not findings).
    - Skip the existence check for plans with `status: completed` or under `completed/`; their files may since have moved.
  - Copy the edited `bin/ensemble-lint` over `skills/en-setup/references/templates/ensemble-lint` (`tests/lint/bin-template-sync.test.sh` enforces identity).
  - The Linear field parser anchors on `- **Files:**` (`en-build/references/linear-plan-format.md:39`); markers sit inside the value, so the anchor is unchanged. Add one marked-line fixture to `tests/linear-plan/linear-plan.test.sh` to prove it.
  - No new lint invocation: `finalize-loop.md:9` and the status-flip step already run `bin/ensemble-lint` on the plan.
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* fixture plan with `` `bin/ensemble-lint` (modify) `` and `` `tests/new.test.sh` (create) `` → no `unit.files-*` finding.
  - *Error path:* `` `bin/does-not-exist` (modify) `` and no unit creates it → one P1 `unit.files-missing` naming the unit and path.
  - *Happy path:* U1 marks `` `tests/new.test.sh` (create) ``, U2 marks it `(modify)` → no finding.
  - *Error path:* U3 marks `` `tests/later.test.sh` (create) ``, U2 marks it `(modify)` → P1 "modified before it is created".
  - *Error path:* `` `skills/*/agents/nope-*.md` (delete) `` → P1, the glob matches nothing.
  - *Edge case:* a plan with five unmarked paths across three units → exactly one P2 `unit.files-unmarked`.
  - *Edge case:* `` `src/x.ts` (new) `` for a missing file → no finding.
  - *Edge case:* a completed plan citing a since-deleted file as `(modify)` → no finding.
  - *Integration:* the Linear parser reads a marked `Files:` line into the same field value it read before.
- **Verification:** `tests/lint/lint-rules.test.sh`, `tests/lint/bin-template-sync.test.sh`, `tests/linear-plan/linear-plan.test.sh` pass; `bin/ensemble-lint --scope docs/plans/active` reports only P2 advisories on existing plans.

### U5. Peer check H: plans that build more than the goal needs

- **Goal:** The plan peer flags speculative configuration, premature optimization and abstractions with one caller, judged from the plan text, without triggering a re-review.
- **Requirements covered:** none
- **Dependencies:** U3 (both edit `peer-brief.md`'s dimension list)
- **Files:**
  - `skills/en-plan/references/peer-brief.md` (modify)
  - `tests/build-peer-prompt/build-peer-prompt.test.sh` (modify)
- **Approach:** Add dimension **H. Builds more than the goal needs** to "What the peer is asked": a unit or design element that serves a future or speculative need, caching, queues or partitioning with no stated bottleneck, configuration nobody asked for, or an abstraction the plan gives a single caller. Scope: a unit that serves **no** stated goal is not H; it is check A at check A's existing severity, P1 included. H covers only work that does serve the goal but is bigger than the goal needs, which leaves the right thing built, so its guidance is **P2** when cutting it removes a unit or component and **P3** otherwise. H adds no new P1 class, so it adds no re-review trigger, without capping anything check A already reports. The routing table already applies cheap P2s and defers the rest. Reuse is explicitly not part of H; the peer has no repo access (`--access none`).
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* en-plan's built prompt contains the H text and the sentence routing goal-less units to check A → passes.
  - *Error path:* drop the check-A routing sentence from the brief → the test fails (negative control).
  - *Error path:* a brief that says "never P1" for H → the test fails (a cap on H must not exist).
- **Verification:** `tests/build-peer-prompt/build-peer-prompt.test.sh` passes.

### U6. The plan peer's summary is a paraphrase the host checks against GOAL

- **Goal:** A plan whose units each make sense but do not add up to the goal is caught, at no extra output cost.
- **Requirements covered:** none
- **Dependencies:** U5 (same file)
- **Files:**
  - `skills/en-plan/references/peer-brief.md` (modify)
  - `skills/en-plan/references/finalize-loop.md` (modify)
  - `tests/build-peer-prompt/build-peer-prompt.test.sh` (modify)
  - `tests/lint/en-plan-finalize-loop.test.sh` (modify)
- **Approach:**
  - `peer-brief.md`, "What the peer is asked": for a plan review, `summary` is "what this plan builds, in your own words, 2-3 sentences", not an overall assessment. The schema and its length are unchanged, so en-review and en-foundation are untouched and output tokens do not grow.
  - `finalize-loop.md`, Verdict handling: after parsing, the host compares `summary` with the plan's Context and unit Goals. A mismatch the plan's wording caused is recorded as a host finding (`finding_id` `<iteration>-h<index>`) and fixed by editing the plan. Its severity follows impact: if the paraphrase shows a goal no unit covers, that is check A's existing **P1**; a wording or framing gap is **P2**. A mismatch from a peer misreading is noted in the iteration log only. A host finding never re-invokes the peer by itself; the re-review runs only on the peer's own P0/P1, as today.
  - Note in `finalize-loop.md` that progress reports for plan reviews show the paraphrase, so readers know why it is not an assessment.
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* en-plan's built prompt asks for the paraphrase in `summary`; en-review's built prompt does not → passes.
  - *Error path:* remove the "a host finding never re-invokes the peer by itself" sentence from `finalize-loop.md` → `en-plan-finalize-loop.test.sh` fails (negative control).
  - *Edge case:* the paraphrase omits a deliverable named in Context → the host records a P1 under check A, not a P2.
  - *Edge case:* the host-finding id form `<iteration>-h<index>` passes `bin/ensemble-lint`'s `peer-review-resolutions.schema` check (finding_id is free text) → asserted by running lint on a fixture plan.
- **Verification:** both tests pass; lint fixture clean.

### U7. The re-review flags growth no finding required

- **Goal:** When the finalize loop re-reviews, the peer sees exactly what the applied fixes changed and flags additions no finding required.
- **Requirements covered:** none
- **Dependencies:** U6 (same `finalize-loop.md`)
- **Interfaces:**
  - *Produces:* `ensemble-build-peer-prompt --plan-before <path>`; the plan file as the previous pass reviewed it. The builder renders a `## Plan changes since the last pass` section: unit count and byte size before and after, then `diff -u <before> <artifact-file>` capped at 200 lines, with the number of lines cut stated when the cap bites.
- **Files:**
  - `skills/en-plan/scripts/ensemble-build-peer-prompt` (modify)
  - `skills/en-plan/references/finalize-loop.md` (modify)
  - `skills/en-plan/references/peer-pass.md` (modify)
  - `tests/build-peer-prompt/build-peer-prompt.test.sh` (modify)
- **Approach:**
  - Before applying a pass's fixes, the host copies the plan to `$D/plan-before.md` (the pass's existing temp dir from `peer-pass.md` step 3). Deterministic, milliseconds.
  - `peer-pass.md`: the re-review command gains `--plan-before "$D/plan-before.md"`.
  - The builder computes the counts (`grep -c '^### U[0-9]'`, `wc -c`) and the capped unified diff itself, so the host cannot get them wrong, and renders them with one instruction: "Each hunk should trace to a finding in the previous review context. Flag any added unit, component or section that no applied finding required. Severity P2." An unreadable `--plan-before` exits 2 with a message. The flag is accepted only with `--iteration-context-file`, since changes only exist on a re-review.
  - Cost: the diff adds **input** tokens to a re-review that already runs, bounded by the 200-line cap; it adds no call and no output.
  - This rides the re-review that P0/P1 already triggered; the iteration cap of 1 means its findings cannot start a third pass. Only en-plan's builder changes (it is already a distinct variant; `tests/parity/script-parity.test.sh` pins which copies must match).
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* a before-file lacking a `## Rollout` section the artifact has → output shows both counts and a diff hunk adding `## Rollout`, plus the P2 instruction.
  - *Edge case:* before-file identical to the artifact → section rendered with equal counts and "no changes".
  - *Edge case:* one paragraph replaced by another of identical byte length and no unit added → counts equal, but the diff shows the replaced lines (the case counts alone cannot see).
  - *Edge case:* a 900-line diff → 200 lines rendered and "700 lines not shown" stated.
  - *Error path:* `--plan-before /nonexistent` → exit 2 naming the path.
  - *Error path:* `--plan-before` without `--iteration-context-file` → exit 2.
  - *Edge case:* no flag → output byte-identical to today's for the same inputs.
- **Verification:** `tests/build-peer-prompt/build-peer-prompt.test.sh` and `tests/parity/script-parity.test.sh` pass.

### U8. Rejecting a peer finding needs evidence; otherwise it is `escalated`

- **Goal:** A host can mark a peer finding `disagreed` only by citing something the peer could read; evidence outside that becomes `escalated` and reaches the user through a question the run already asks.
- **Requirements covered:** none
- **Dependencies:** U6, U7 (Phase C runs after Phase B; shares `finalize-loop.md` and en-plan's builder)
- **Files:**
  - `skills/en-plan/references/peer-contract.md` (modify)
  - `skills/en-review/references/peer-contract.md` (modify)
  - `skills/en-build/references/peer-contract.md` (modify)
  - `skills/en-foundation/references/peer-contract.md` (modify)
  - `skills/en-learn/references/peer-contract.md` (modify)
  - `skills/en-setup/references/peer-contract.md` (modify)
  - `skills/en-sweep/references/peer-contract.md` (modify)
  - `skills/en-test-audit/references/peer-contract.md` (modify)
  - `skills/en-plan/references/templates/plan-template.md` (modify)
  - `skills/en-foundation/references/templates/plan-template.md` (modify)
  - `bin/ensemble-lint` (modify)
  - `skills/en-setup/references/templates/ensemble-lint` (modify)
  - `skills/en-plan/scripts/ensemble-build-peer-prompt` (modify)
  - `skills/en-review/scripts/ensemble-build-peer-prompt` (modify)
  - `skills/en-test-audit/scripts/ensemble-build-peer-prompt` (modify)
  - `skills/en-foundation/scripts/ensemble-build-peer-prompt` (modify)
  - `skills/en-plan/references/peer-brief.md` (modify)
  - `skills/en-plan/references/finalize-loop.md` (modify)
  - `skills/en-review/SKILL.md` (modify)
  - `skills/en-foundation/SKILL.md` (modify)
  - `skills/en-build/references/build-preflight.md` (modify)
  - `tests/lint/lint-rules.test.sh` (modify)
  - `tests/build-peer-prompt/build-peer-prompt.test.sh` (modify)
  - `tests/lint/peer-resolution-evidence.test.sh` (create)
- **Approach:**
  - `peer-contract.md`, "Resolution status" (all eight copies byte-identical): the enum becomes `applied · deferred · disagreed · superseded · escalated`. Add the four rules:
    1. A `disagreed` rationale cites something the peer could read: a `file:line`, a plan section or unit, or a decision ID (`D<N>`).
    2. When the evidence exists only outside that, such as a verbal decision or team convention, the status is `escalated`, with a rationale naming what the user must decide.
    3. A host that thinks a finding's severity is wrong disagrees with the finding and says why; it never lowers the severity silently.
    4. Context is not added to an artifact only to satisfy a reviewer that lacked it; escalate instead.
  - Template (both copies) and `bin/ensemble-lint` (+ its template copy): add `escalated` to the status enum; `rationale` required for it as for `disagreed`. Lint does not judge whether a rationale cites evidence: that is prose, and a regex over it would be a guard that cannot fail honestly.
  - Prompt builders (all four; en-review and en-test-audit stay byte-identical): "Never re-flag anything ... marks applied, deferred or disagreed" gains "or escalated".
  - en-plan routing (`peer-brief.md` table and `finalize-loop.md`). Three paths, none adding a stop:
    1. **A question is already being asked this run** (the "P1, confidence < 7: surface; the user decides" step, the cap-hit question, or a reject): the escalation is listed in it with its rationale. The user's answer converts it to `applied`, `deferred` or `disagreed` (the user's word is the evidence, recorded as `user decision <date>`).
    2. **No question is scheduled** (an otherwise clean pass): the entry stays `escalated`. Escalated counts as **non-blocking** for promotion: the host has judged the finding wrong and only the evidence is out of the peer's reach, so the plan is built as written. The verdict and the `draft → open` flip follow the other findings exactly as today. The run report and the hand-off line list each escalation, so the user sees it without being asked.
    3. **Non-interactive run** (`--from-flow`, automation): as path 2.
  - en-review (`SKILL.md` step 12) and en-foundation (`SKILL.md`, its peer resolution step): same rule and same routing into the questions each already asks, one sentence each pointing at `references/peer-contract.md`.
  - en-build `build-preflight.md`: an `escalated` entry never blocks and never adds a prompt. Pre-flight lists open escalations in the summary it already prints before the first unit; when the draft-plus-revise recovery prompt fires for other reasons, they are listed in it too. For that prompt's "all resolved" test, `escalated` counts as resolved, like `disagreed`.
  - `peer-resolution-evidence.test.sh`: asserts the four rules in the contract, `escalated` in every enum site (contract, template, lint, builders, preflight), and the "no new stop" sentence in `finalize-loop.md`.
- **Risk:** medium
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* fixture plan with a resolution `status: escalated, rationale: "team convention on X, user to confirm"` → lint clean.
  - *Error path:* `status: escalated` with no rationale → lint P1 `peer-review-resolutions.schema`.
  - *Error path:* `status: escalated-ish` → lint P1 naming the allowed five.
  - *Edge case:* edit one `peer-contract.md` copy only → `tests/parity/peer-contract-parity.test.sh` fails naming it.
  - *Integration:* en-plan's built re-review prompt, given a context file listing an escalated finding, tells the peer not to re-flag it.
  - *Scenario, existing question:* a pass with a P1 at confidence 6 and an escalation → `finalize-loop.md` routes both into the one existing question (asserted on the text).
  - *Scenario, no question:* a clean pass plus one escalation → plan flips to `open`, entry stays `escalated`, report lists it (asserted on `finalize-loop.md` and the status-flip text).
  - *Scenario, non-interactive:* same as no question; `build-preflight.md` lists it in the pre-flight summary and treats it as resolved for the recovery test.
  - *Error path:* remove "or escalated" from en-review's builder only → `tests/parity/script-parity.test.sh` fails (en-review and en-test-audit copies diverge) and the new test fails.
- **Verification:** new test passes with negative controls; parity tests, `lint-rules.test.sh`, `bin-template-sync.test.sh`, `build-peer-prompt.test.sh` pass; full suite green.

### U9. Count escalations in run records

- **Goal:** en-review's `outcome` event records how many findings were escalated, so the run ledger shows how often the evidence rule sends a decision to the user.
- **Requirements covered:** none
- **Dependencies:** U8
- **Files:**
  - `skills/en-build/scripts/ensemble-run-metrics` (modify)
  - `skills/en-fix/scripts/ensemble-run-metrics` (modify)
  - `skills/en-foundation/scripts/ensemble-run-metrics` (modify)
  - `skills/en-learn/scripts/ensemble-run-metrics` (modify)
  - `skills/en-plan/scripts/ensemble-run-metrics` (modify)
  - `skills/en-qa/scripts/ensemble-run-metrics` (modify)
  - `skills/en-resolve-pr/scripts/ensemble-run-metrics` (modify)
  - `skills/en-review/scripts/ensemble-run-metrics` (modify)
  - `skills/en-ship/scripts/ensemble-run-metrics` (modify)
  - `skills/en-simplify/scripts/ensemble-run-metrics` (modify)
  - `skills/en-test-audit/scripts/ensemble-run-metrics` (modify)
  - `skills/en-review/SKILL.md` (modify)
  - `skills/*/references/run-metrics.md` (modify)
  - `tests/lint/ensemble-run-metrics.test.sh` (modify)
  - `tests/lint/en-review-outcome-event.test.sh` (modify)
- **Approach:** Add `"escalated"` to the `outcome` allowlist after `"disagreed"` in every `ensemble-run-metrics` copy (byte-identical; `script-parity.test.sh`). In en-review's emit call at step 13, include `"escalated":<n>` **only when n > 0**, and state that an absent key means zero; readers (`bin/ensemble-metrics`, the `outcome` row docs) treat it that way. A review with no escalations, the common case, emits exactly the payload it emits today, so the hot path gains no output tokens; the few tokens appear only on the rare run that escalated something. Add `escalated` to the `outcome` row of each `run-metrics.md` copy that carries the table. `bin/ensemble-metrics` needs no change if it passes unknown outcome keys through; the build confirms this by running `bin/ensemble-metrics` over a fixture ledger containing the new key.
- **Risk:** low
- **Category:** observability
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* `emit --kind outcome --json '{"verdict":"revise","escalated":2,...}'` → the ledger line keeps `escalated: 2`.
  - *Edge case:* en-review's documented emit template for a run with no escalations is byte-identical to today's (asserted on `SKILL.md` step 13 text); `bin/ensemble-metrics` reads a ledger line without the key as zero escalations.
  - *Error path:* before the change the same emit drops `escalated` and names it on stderr; after, nothing is dropped (the test asserts the after state; the before state is the negative control).
  - *Edge case:* one `ensemble-run-metrics` copy left without the key → `script-parity.test.sh` fails.
  - *Integration:* `bin/ensemble-metrics` over a fixture ledger with `escalated` → runs without error and does not lose the other counts.
- **Verification:** `ensemble-run-metrics.test.sh`, `en-review-outcome-event.test.sh`, `script-parity.test.sh` pass.

### U10. Opt-in live tests that read real transcripts

- **Goal:** Prove, against real model runs on Claude Code and Codex, that report-only review edits nothing and that a reviewer facing an unreadable input reports `incomplete`, and on Claude that `dimension-reviewer` calls only its allowed tools.
- **Requirements covered:** none
- **Dependencies:** U1, U2
- **Files:**
  - `tests/portability/live-behaviour.test.sh` (create)
  - `tests/README.md` (modify)
- **Approach:** Same opt-in shape as `tests/portability/live-anchor-hosts.test.sh`: skip with a pass unless `ENSEMBLE_LIVE_BEHAVIOUR_TEST=1`; never on CI. Assertions read the native event stream, never the model's prose: Claude via `claude -p --output-format stream-json --verbose` (`tool_use` records, including the subagent's), Codex via `codex exec --json` (`command_execution` and `file_change` items). Each case runs in a temp git repo with a two-file fixture diff.
  - **Case 1, both hosts:** `/en-review --mode report-only` on the fixture. Assert zero Edit/Write/NotebookEdit `tool_use` (Claude) and zero `file_change` items (Codex), and the tree is unchanged (`git status --porcelain` empty).
  - **Case 2, Claude only:** prove the restriction stops a tool the agent actually tries to use. Two isolated agent copies built from `dimension-reviewer.md`, identical except that one carries U1's `tools: Read, Grep, Glob` and the control has no `tools:` line, are each given the same harmless explicit task: "run `cat fixture.txt` with Bash and report the planted token". Assert the restricted copy makes no successful Bash `tool_use` and does not return the token, while the control does return it. If the control fails to return the token, the case reports inconclusive rather than pass. Codex is excluded because Codex agents cannot carry a per-agent tool list (see Decisions).
  - **Case 3, both hosts:** give the reviewer a prompt naming a reference file made unreadable with `chmod 000`. Assert the final JSON has `"status": "incomplete"` and lists that path in `unreadable`, and (Claude) that a `Read` `tool_use` on the path exists with an error `tool_result`, so the verdict follows an actual failed read.
  - Each case records its negative control in the header: Case 1 with a fixture skill copy whose report-only branch is edited to write a file; Case 2's control copy is built in, run every time, and must return the planted token for the case to count; Case 3 with the file left readable (status must then be absent or `complete`).
  - `tests/README.md`: one line documenting the switch and its token cost.
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* with the switch set and both CLIs installed, all five host-case runs pass.
  - *Edge case:* switch unset → the test passes immediately as skipped and calls no CLI.
  - *Edge case:* switch set, `codex` absent → Codex cases report skipped with the reason; Claude cases still run.
  - *Error path:* each negative control above turns its case red (run once by hand, result recorded in the header with the date).
- **Verification:** run once with `ENSEMBLE_LIVE_BEHAVIOUR_TEST=1`, record results and negative controls in the header; without the switch the suite stays hermetic.

## Decisions, assumptions & risks

- **Decision:** Research agents use a `disallowedTools` denylist, not a `tools` allowlist. They write evidence dossiers with `Write`, and `web-research` needs Context7 MCP tools whose names differ between plugin and standalone installs. A pure allowlist would break both.
- **Decision:** Codex agents get no per-agent restriction. Codex custom-agent TOML has no `tools` field and `sandbox_mode` cannot be overridden per agent (OpenAI docs, `learn.chatgpt.com/docs/agent-configuration/subagents`, read 2026-10-29). `features.shell_tool = false` exists but would also remove a Codex agent's way to read files. Codex read-only rests on the parent session's sandbox; the peer subprocess already runs `codex exec -s read-only`.
- **Decision:** U7 passes a capped diff, not only counts (peer finding 1-4): counts cannot tell an added section from a rewritten one. The diff is input to a call that already runs, capped at 200 lines.
- **Decision:** Severity stays impact-based everywhere (peer finding 1-2). U3's H0 and U6's paraphrase mismatch are P1 only where the existing contract already makes the defect P1 (a cross-unit signature, an unstated bet, an uncovered goal), so they add no re-review the plan would not already earn. U5's check H is P2/P3 because over-building does not make a build fail or build the wrong thing. U3's pre-write check settles most H0 cases before the peer runs.
- **Decision:** `escalated` never creates a new user stop and never blocks promotion or build (peer finding 1-5). It joins a question already being asked when there is one; otherwise it is reported in the run report, the hand-off line and en-build's pre-flight summary. The host has already judged the finding wrong; escalation records that the evidence is outside the peer's reach, so the user can overrule later.
- **Decision:** Lint checks the `escalated` enum and rationale presence, not whether a rationale cites evidence. Judging prose with a regex would be a guard that passes or fails for the wrong reasons.
- **Alternative:** Running the plan peer with `--access read-tree` so it could check reuse and file references itself. Rejected: it doubles the peer timeout budget. U4 does the file check deterministically instead.
- **Assumption:** `bin/ensemble-metrics` passes unknown `outcome` keys through. Checked in U9 by running it over a fixture ledger; if it filters keys, U9 adds `escalated` to its list.
- **Assumption:** The research for this plan was gathered in the planning session by direct reads at `c08d027` and written to `/tmp/ensemble/en-plan/EN24-research.md` (2026-10-29); it was not re-verified by `repo-research`.
- **Risk:** U8 touches 24 files across eight skills. **Mitigation:** the parity tests fail on any copy left behind, and U8 lands as its own commit after Phase B.
- **Risk:** A `disallowedTools` or `tools` line the installed Claude Code version does not understand could stop an agent launching. **Mitigation:** U1's integration scenario installs into a temp HOME; U10 Case 2 confirms a real launch.
- **Risk:** Research agents keep `Write` and `code-simplifier` keeps `Bash`, so U1 does not make them read-only (peer finding 1-1). **Mitigation:** each body names the one permitted use; en-guardrail's Bash hook still applies inside subagents. **Alternative rejected:** per-agent `PreToolUse` hooks limiting `Write` to `/tmp/ensemble/` and `Bash` to `git blame|log|show`. Claude Code ignores frontmatter hooks for plugin-installed subagents, the hook command would need an install-path-dependent location, and a Bash allowlist needs a real parser per the guardrail lessons; that is more machinery than this gap warrants today.
- **Risk:** The bundled-definition fallback in `references/agent-dispatch.md` (a lone skill directory with no registered agent) passes the definition as a prompt, where frontmatter is not enforced. **Mitigation:** none in this plan; the registered path is the normal one. Recorded so the gap is visible.

## As built (2026-10-30)

Deviations from the units above, each recorded in its commit:

- **U1** shipped as allowlists that keep Bash: readers carry `tools: Read, Bash`, the repo research agents `tools: Read, Bash, Write`, web-research keeps its denylist. Claude Code 2.1.312 exposes no Grep or Glob tool, so the planned `Read, Grep, Glob` left agents unable to search (branch review). The allowlists also drop every MCP tool; Bash stays bounded by prose.
- **U4** skips both Files rules on completed plans, and checks existence only while a plan is draft or open: lint exits non-zero on any finding, and a built (delete) removes a path its own plan names.
- **U8** put en-review's rule in `references/mutation-protocol.md`, not `SKILL.md`, which had 52 bytes left under its budget. `script-parity` does not pin the code-review builder copies, so the new test does.
- **U10** case 2 tests the shipped tools line against `Write`, with a neutral probe body. Codex results after the review are unrecorded: every Codex call timed out on the re-run.

## Iteration log

> - 2026-10-29 (initial): plan v0 from `docs/reviews/egm-adaptation-outline.md` and the planning-session research.
> - 2026-10-29 (iteration 1): Codex peer, verdict revise, five P1s, all applied. U1 now claims only what frontmatter enforces and records the Write/Bash residual. Severity is impact-based in U3, U5 and U6 instead of capped. U4 accepts a modify of a file an earlier unit creates. U7 passes a capped diff instead of counts (`--plan-before`). U8 defines the no-question path: escalations are reported, never block, never add a stop.
> - 2026-10-29 (iteration 2): Codex peer, verdict revise, three P1s, all applied without a third pass (cap reached). 1-2 re-raised for U5: check H no longer says never P1; goal-less units route to check A. 2-1: U9 emits `escalated` only when non-zero, so a normal review's payload is unchanged. 2-2: U10 Case 2 uses a restricted and an unrestricted agent copy on an explicit Bash task, so the control can go red.
