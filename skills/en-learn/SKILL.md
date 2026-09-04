---
name: en-learn
description: "Capture durable learnings into the repo's knowledge store as a term, a decision, or a solution. Gated: writes nothing unless the entry is unrecoverable from the code and changes a future decision. Trigger phrases: 'capture this', 'learn from', 'audit learnings', 'wiki health', 'migrate learnings'."
---


# `/en-learn`

> **Running a bundled script.** Anchor every call to this skill's own directory: `SKILL_DIR="<absolute path of the directory containing this SKILL.md>"; bash "$SKILL_DIR/scripts/<name>"`. The trailing `;` is load-bearing. A bare `scripts/<name>` resolves against the user's project, not this directory, and exits 127.

> **Dispatching a bundled agent.** This skill carries its agents in `agents/`. Dispatch by name as usual; when the name is not registered (a lone skill directory), resolve it from the bundled definition per `references/agent-dispatch.md`.


Maintain `docs/learnings/` as a compounding interlinked wiki — not a flat folder. Adopts Karpathy's LLM Wiki pattern: agent-maintained, with `index.md` + `log.md` for navigation and `--lint` for graph health.

## Modes

| Mode | Trigger | Output |
|---|---|---|
| `capture` (default) | After feature ships, bug fixed, or synthesis emerges | `docs/learnings/<slug>-<date>.md` + side effects |
| `--refresh` | Audit content staleness (~monthly) | Per-entry: keep / update / replace / archive |
| `--lint` | Wiki-graph health check | JSON report of orphans, missing back-refs, etc.; `--fix` auto-applies |
| `--migrate` | A project still on the retired `bugs/`/`patterns/`/`decisions/` layout | Entries moved to the artifact-type layout; legacy decisions converted to ADRs |

## Always-on behaviors

After every write:

1. **Active cross-reference maintenance — solutions only.** Walk the new entry's `related: []` and add reciprocal back-refs to each cited page. Terms and ADRs carry no frontmatter and so no `related:` field; they are cross-referenced by being cited in prose, which needs no reciprocal bookkeeping. Per `references/learn-cross-ref-maintenance.md`.
2. **Index update** — append a one-line entry to `docs/learnings/index.md` under the appropriate category. Per `references/learn-index-format.md`.
3. **Log append** — single line to `docs/learnings/log.md`: `## [YYYY-MM-DD] <op> | <subject>` for most ops; **`capture` mode appends `| <head-sha>` from `git rev-parse --short HEAD`** as the baseline marker `/en-build`'s learning checkpoint reads (D26). Per `references/learn-log-format.md`. Other ops (`refresh`, `lint-fix`, `migrate`, `capture-from-conversation`) don't write SHA — only `capture` resets the baseline.

## Process — Mode A: `capture` (default)

1. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, skip (no peer review on capture).
2. **Legacy-layout check.** If `docs/learnings/bugs/`, `patterns/`, `decisions/`, or `sources/` exists, this repo predates the artifact-type layout. Surface it and offer the migration — **read `references/layout-migration.md` and follow it**. Until it runs, entries under those directories are invisible to the new paths without being deleted, which is the failure mode that loses a knowledge base quietly. Do not capture into a half-migrated store.

3. **Detect input source.**
   - **Default** (post-build / post-qa) — read recent commits + branch summary.
   - **`--from-conversation`** — take user-confirmed synthesis as input (fired by D21 capture-from-synthesis).
   - **Explicit subject** — user describes what to capture.
4. **Apply the capture gate — read `references/capture-gate.md` and follow it.** This runs BEFORE any other work and decides whether to write at all. **The default is to write nothing.** Three conditions, all required, each answered by naming something: the file an agent would read to learn this (condition 1), the decision this changes and who makes it (condition 2), and whether it survives a rewrite of the code that prompted it (condition 3). An unnamed answer is a failed condition, not a judgment call.

   Coding agents reconstruct *what* and *how* from the tree without help. Capture only what reading cannot recover: constraints living outside the code, paths tried and abandoned, deliberate deviations from the obvious, failure modes that do not announce themselves.

   **On failure, write nothing and report which condition failed and what could not be named** (format in the reference). A reported skip is a normal successful outcome. Then skip to step 11: the plan-lifecycle flip and the always-on behaviors still run, because bookkeeping is not conditional on filing content.

   **One learning per run.** A session holding two distinct durable lessons gets two runs; batching pushes the weaker through on the stronger one's merit.

5. **Route to an artifact type — read `references/artifact-types.md` and follow it.** The gate decided *whether* to write; this decides *which artifact*, and the three differ in shape, lifecycle, and write path.

   A candidate that says **what a word means here** is a **term** (`docs/CONTEXT.md`). One that records **a choice and the rules that now hold** is a **decision** (`docs/decisions/NNNN-<slug>.md`). One that records **a solved problem whose lesson outlives the fix** is a **solution** (`docs/learnings/<slug>-<date>.md`).

   **Matching two types is normal.** Write the more durable one — `term > decision > solution` — and let it cite the other. Never write both: that reintroduces the duplication the gate's generalization step exists to prevent.

6. **Gather what the entry needs.** Read the relevant commits and search `docs/learnings/` for overlap — an existing entry to extend beats a near-duplicate. Dispatch the `learnings-research` agent only when the search is genuinely broad; a gate-passing learning is usually a few sentences whose material you already hold, and three parallel sub-agents to produce a paragraph costs more than it returns. **That agent is the only one this skill dispatches** — it does not scout the codebase, because what it captures is what reading the code cannot recover.
7. **Compose, per the routed type.** Each type has its own shape, so each has its own template. Using the solution template for all three would give a term frontmatter it must not carry and an ADR a form its format forbids.

   - **Term** → `references/glossary-rules.md`. A definition sentence, optional `_Avoid:_` aliases. No frontmatter.
   - **Decision** → `references/templates/adr-template.md`. Title states the claim, `## Invariants this creates`. No frontmatter.
   - **Solution** → `references/templates/learning-template.md`. Six-field frontmatter, **one paragraph until it earns more** — lead with the conclusion, name specifics.

8. **Write to the routed path.** A **term** is appended to `docs/CONTEXT.md` per `references/glossary-rules.md` (amend an existing entry rather than adding a second). A **decision** takes the next unused number at `docs/decisions/NNNN-<slug>.md` per `references/adr-format.md`. A **solution** generates `<slug>-<date>` (lowercase, alphanumeric + hyphens, ≤60 chars + `-YYYY-MM-DD`) at `docs/learnings/<slug>-<date>.md`.
9. **Vocabulary accretion — read `references/glossary-rules.md`.** **This is a declared second write, and the one exception to "one artifact per run."** The routing tie-break decides where the *candidate* goes; accretion is a side effect of having done the work, not a second candidate competing with it. A run may therefore touch two files: the routed artifact and `docs/CONTEXT.md`. Both are grounded together in the next step.

   Independent of what was routed above: if the work surfaced a term whose meaning was not obvious, define it in `docs/CONTEXT.md`. Friction is what surfaces peripheral terms, so a capture is when they are visible.

   **Report the outcome even when nothing qualified.** "No new terms" is a result; silence is indistinguishable from having skipped the step. Do not invent a term to have something to report — the bar is that a new engineer would need it defined.

10. **Ground every artifact this run wrote — run `$SKILL_DIR/scripts/ensemble-validate-claims` on each, and read `references/grounding-validation.md`.** Usually one file; a run that also accreted a term (step 9) has two, and both are checked before either is indexed. The artifact is about to become knowledge future agents act on without re-verifying. Check it before that happens, not after someone follows a dead reference.

   Exit **0** clean, **1** findings to adjudicate, **2** the validator could not run. **Adjudicate, never auto-apply:** a solution doc legitimately cites a path the fix deleted or describes a pre-fix state.

   **Exit 2 means the artifact is unverified.** Record degraded verification and say so in the report — a run whose grounding could not execute must not be reported as grounded. That is the case which otherwise looks identical to clean.

11. **Plan-lifecycle handling.** Step 11 splits into two sub-steps: **lifecycle bookkeeping**, which always runs, and **documentation-tense rewrites**, which run only on an actual capture. Bundled, a user's "skip — no learnings to capture" once orphaned plans at `status: in_progress`. `/en-ship`'s plan-completion checkpoint is the backstop when `/en-learn` is never invoked (D34).

   **11a. Lifecycle flip (always runs when a plan_id is in context).** If `/en-learn capture` was invoked within the context of a specific plan (derivable from the current branch name per `<plan_id>-<slug>` convention, or passed via `--plan <plan-path>`), perform the lifecycle flip:
   - Read frontmatter; check `status:`.
   - If `status: in_progress` OR `status: open`: flip to `status: completed`, set `shipped: <today>`. Both `open` and `in_progress` flow into this path — the `open` case preserves the recovery for builds that skipped the `open → in_progress` flip (interrupted build, manual resume, etc.).
   - If `status: completed`: no-op; plan already moved.
   - If `status: draft` OR `status: abandoned`: skip the flip; surface a one-line notice (`/en-learn` shouldn't be flipping a draft plan to completed).
   - `git mv docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md docs/plans/completed/<PREFIX><NN>-<plan_type>_<slug>.md` (filename preserved verbatim during the move).
   - Stage the rename + frontmatter edit.

   **11a always runs**, even when the user picked "skip — no learnings worth filing" earlier in the capture flow. The flip is lifecycle bookkeeping; it shouldn't be tied to whether wiki content was filed.

   **11b. Documentation-tense updates (only runs when a learning was actually captured).** If a learning was captured during this `/en-learn capture` invocation (step 8 wrote a real file), AND 11a ran (plan was moved), also:
   - Replace plan-tense ("we will", "this should") with documentation-tense ("we did", "this does").
   - Note any deviations from the plan (sections of the plan that didn't ship as written, or that landed differently).

   **11b is skipped when the user said "skip — no learnings worth capturing"** earlier in the flow; lifecycle flip (11a) still happens, just without the documentation-tense rewrite.

   **Edge case: no plan_id in context.** If `/en-learn capture` is invoked outside any plan context (no plan branch, no `--plan` argument), step 11 is a silent no-op — there's nothing to flip.
12. **Apply always-on behaviors** (cross-refs, index update, log append).
13. **Sync `docs/architecture.md`** if material structural change (new module, changed boundaries, new infrastructure, dependency direction shifts, new external integration). Surgical edits only — never regenerate. Bump `updated:`. Per `references/architecture-update-rules.md`.
14. **Sync `foundation.md`** if scope, decisions, or top-level direction changed.
15. **Sync `AGENTS.md` / `CLAUDE.md`** only if the artifact directory or top-level guidance changed (rare).
16. **Update `docs/README.md` index** if it exists.
17. **Regenerate `docs/generated/learning-index.md`** by appending the new entry; bump `total_entries`.

## Process — Mode B: `--refresh`

Audit *content* staleness — distinct from `--lint`, which audits structure. Run
periodically (~monthly) or after a big architectural shift.

**1. Ground the store first.** Run `$SKILL_DIR/scripts/ensemble-validate-claims` over every
artifact. An entry citing three paths that no longer resolve is *evidence* of
staleness; reading it and judging is opinion. Lead with what the validator found,
then judge what it cannot see.

**2. Each artifact type has its own lifecycle.** They differ in how they age, so
one disposition set cannot serve all three.

| Type | Dispositions |
|---|---|
| **Solutions** (`docs/learnings/`) | keep / update / replace / archive |
| **Decisions** (`docs/decisions/`) | keep / **amend** / **reverse** — never silently replaced |
| **Terms** (`docs/CONTEXT.md`) | keep / refine / retire |

**Solutions** describe a solved problem against a codebase that moves, so they go
stale and can be superseded. `replace` writes a successor citing the old via
`replaced_by:` and marks it `status: superseded`; `archive` moves it to
`docs/learnings/archive/` and drops it from the index; `update` edits in place
and adds a "Last updated YYYY-MM-DD" note, leaving `date:` immutable.

**Decisions are append-only.** A decision that no longer holds is still what was
decided, and why, at the time.

**Amend** covers everything short of reversal: a dated `## Update, YYYY-MM-DD`
section saying what changed and what now holds. This is the common case, and it
keeps one decision's whole history in one file.

**Reverse** is the exception, and it is not the same as replace. When the
*decision itself* is overturned, write a **new ADR** stating the new claim, and
add reciprocal links: the new one names what it supersedes, the old one gets a
final dated Update pointing forward. The old file is never deleted or rewritten —
a superseded decision with no trace of the reasoning is how a team relearns the
same lesson. This matches `adr-format.md`, which permits a successor ADR only on
reversal.

**Terms accrete.** `refine` sharpens a definition or adds a retired synonym;
`retire` moves a word that left the domain into the `## Flagged ambiguities` tail
rather than deleting it, because "we stopped using that word" is itself worth
recording.

**3. Confirm each disposition** with the user, or `--auto` for the non-judgment
cases (a citation the validator resolved as a pure path move, an index line that
drifted).

## Process — Mode C: `--lint` / `--lint --fix`

Per `references/learn-lint.md`. Findings are graded P0-P3 with the confidence scale beside them, both defined in `references/peer-contract.md` and meaning the same thing to every skill that reads them. Audits the wiki *graph*:

- Orphans, missing back-refs, broken links, contradictions, missing pages, stale references, index drift, log drift, data gaps.
- `--fix` auto-applies mechanical fixes (back-refs, broken-link repair, index regen, log append).
- Judgment items (orphans, contradictions, missing-page candidates) → surfaced for the user.

Output: JSON-lines + markdown summary.

## Process — Mode D: `--migrate`

Runs the layout migration directly, for a project that predates the artifact-type
layout. **Read `references/layout-migration.md` and follow it** — the same
procedure capture's legacy-layout check invokes. One procedure, two entry points; two
descriptions would drift and the drift would only be discovered mid-migration.

Use this when upgrading an existing project. Capture's legacy-layout check is a safety net
for someone who reaches for capture first, not the intended route: a project
holding a hundred entries should not have to start writing a new learning to be
told the old ones are about to stop being read.

Reports what moved, what converted to an ADR, what was renamed to avoid a
collision, and anything left for classification.


## Who invokes it

- `/en-build`'s learning checkpoint, the **sole** capture prompt in the lifecycle (D26, D38), and `/en-loop` at loop end, invoke `capture`. `/en-qa` never prompts for learnings.
- `/en-brainstorm`, `/en-foundation` and `/en-resolve-pr` invoke `capture --from-conversation` when a synthesis clears the gate (D21).
- `/en-sweep` invokes `--lint` in CI.
- A person runs any mode. When a caller drives `capture`, the gate decides and nothing is asked.

## Cross-review

**Off.** This skill invokes no peer and carries no peer machinery; its severity vocabulary is the shared contract's, nothing more.

## Reference files

- `references/capture-gate.md` — whether to write a learning at all; the default is not to
- `references/templates/learning-template.md` — body structure for a solution entry
- `references/learning-frontmatter-schema.md` — frontmatter rules + examples
- `references/learn-cross-ref-maintenance.md` — always-on back-ref behavior
- `references/learn-index-format.md` — `index.md` structure
- `references/learn-log-format.md` — `log.md` structure
- `references/learn-lint.md` — check catalog and auto-fix rules
- `references/architecture-update-rules.md` — when to touch `docs/architecture.md`

## Failure protocol

| Failure | Behavior |
|---|---|
| Off-topic skip | Log; exit 0 with one-line note |
| Cross-ref walk partial failure | Primary write succeeds; surface partial; `--lint` self-heals later |
| Frontmatter schema validation fails | Log diff vs expected; user fixes manually |
| `docs/architecture.md` sync conflict (concurrent edit) | Stop sync; surface; user resolves |
| Plan move active→completed but plan still has open units | Refuse the move; surface "FR07 has 2 incomplete units; not moving to completed/" |
| `--lint` finds 100+ violations | Cap report at top 50; note total count; suggest running `--fix` |
| Slug collision (same date, same title) | Append `-<short-hash>` to disambiguate |
