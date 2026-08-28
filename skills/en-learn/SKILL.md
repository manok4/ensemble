---
name: en-learn
description: "Compounding wiki maintainer for docs/learnings/. Capture is gated: the default is to write NOTHING, and an entry must clear three conditions — not recoverable from the code, changes a named future decision, outlives its occasion — because coding agents already read code well and a wiki restating it makes them read more to learn less. Six modes: capture (default; gate-checked, one learning per run, one paragraph until it earns more; syncs architecture/foundation/plan, moves plan to completed); ingest <path-or-url>; --refresh (audit staleness); --pack <library>; --lint (graph health — orphans, broken links, contradictions); --bootstrap-patterns (one-time retrofit, seeds patterns/ from existing codebase). Always-on cross-reference maintenance. Trigger phrases: 'capture this', 'learn from', 'ingest', 'pack docs', 'audit learnings', 'wiki health'."
# What this skill needs. Every path is skill-relative and must exist here.
# A skill is self-contained: nothing outside this directory is listed.
requires:
  - agents/learnings-research.md
  - agents/repo-research.md
  - references/adr-format.md
  - references/agent-dispatch.md
  - references/architecture-update-rules.md
  - references/artifact-types.md
  - references/capture-gate.md
  - references/glossary-rules.md
  - references/grounding-validation.md
  - scripts/ensemble-validate-claims
  - references/learn-bootstrap-patterns.md
  - references/learn-cross-ref-maintenance.md
  - references/learn-index-format.md
  - references/learn-ingest.md
  - references/learn-lint.md
  - references/learn-log-format.md
  - references/learning-frontmatter-schema.md
  - references/pack-reference-template.md
  - references/peer-contract.md
  - references/research-dispatch.md
  - references/templates/architecture-template.md
  - references/templates/adr-template.md
  - references/templates/context-template.md
  - references/templates/learning-template.md

---


# `/en-learn`

> **Dispatching a bundled agent.** This skill carries its agents in `agents/`. Dispatch by name as usual; when the name is not registered (a lone skill directory), resolve it from the bundled definition per `references/agent-dispatch.md`.


Maintain `docs/learnings/` as a compounding interlinked wiki — not a flat folder. Adopts Karpathy's LLM Wiki pattern: agent-maintained, with `index.md` + `log.md` for navigation and `--lint` for graph health.

> **Severity vocabulary.** This skill emits findings graded P0-P3. Those levels,
> and the confidence scale beside them, are defined in
> `references/peer-contract.md` and mean the same thing to every skill that
> reads them.

## Modes

| Mode | Trigger | Output |
|---|---|---|
| `capture` (default) | After feature ships, bug fixed, or synthesis emerges | `docs/learnings/<category>/<slug>-<date>.md` + side effects |
| `ingest <path-or-url>` | Reading external engineering material | `docs/learnings/sources/<slug>-<date>.md` + 5-15 page back-refs |
| `--refresh` | Audit content staleness (~monthly) | Per-entry: keep / update / replace / archive |
| `--pack <library>` | Curate external library reference | `docs/references/<library>-llms.txt` |
| `--lint` | Wiki-graph health check | JSON report of orphans, missing back-refs, etc.; `--fix` auto-applies |
| `--bootstrap-patterns` | Retrofit existing project (one-time during/after `/en-foundation --retrofit`) | 5-10 entries in `docs/learnings/patterns/` flagged `source: bootstrap`, `confidence: 6`, `requires_validation: true` |

## Always-on behaviors (across `capture` and `ingest`)

After every write:

1. **Active cross-reference maintenance** — walk new entry's `related: []`; add reciprocal back-refs to each cited page. Per `references/learn-cross-ref-maintenance.md`.
2. **Index update** — append a one-line entry to `docs/learnings/index.md` under the appropriate category. Per `references/learn-index-format.md`.
3. **Log append** — single line to `docs/learnings/log.md`: `## [YYYY-MM-DD] <op> | <subject>` for most ops; **`capture` mode appends `| <head-sha>` from `git rev-parse --short HEAD`** as the baseline marker for `/en-ship`'s learning checkpoint. Per `references/learn-log-format.md`. Other ops (`refresh`, `ingest-url`, `lint-fix`, `pack`, `capture-from-conversation`) don't write SHA — only `capture` resets the baseline.

## Process — Mode A: `capture` (default)

2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, skip (no peer review on capture).
3. **Detect input source.**
   - **Default** (post-build / post-qa) — read recent commits + branch summary.
   - **`--from-conversation`** — take user-confirmed synthesis as input (fired by D21 capture-from-synthesis).
   - **Explicit subject** — user describes what to capture.
4. **Apply the capture gate — read `references/capture-gate.md` and follow it.** This runs BEFORE any other work and decides whether to write at all. **The default is to write nothing.** Three conditions, all required, each answered by naming something: the file an agent would read to learn this (condition 1), the decision this changes and who makes it (condition 2), and whether it survives a rewrite of the code that prompted it (condition 3). An unnamed answer is a failed condition, not a judgment call.

   Coding agents reconstruct *what* and *how* from the tree without help. Capture only what reading cannot recover: constraints living outside the code, paths tried and abandoned, deliberate deviations from the obvious, failure modes that do not announce themselves.

   **On failure, write nothing and report which condition failed and what could not be named** (format in the reference). A reported skip is a normal successful outcome. Then continue to step 8 — the always-on behaviors and the plan-lifecycle flip in step 11 still run, because bookkeeping is not conditional on filing content.

   **One learning per run.** A session holding two distinct durable lessons gets two runs; batching pushes the weaker through on the stronger one's merit.

5. **Route to an artifact type — read `references/artifact-types.md` and follow it.** The gate decided *whether* to write; this decides *which artifact*, and the three differ in shape, lifecycle, and write path.

   A candidate that says **what a word means here** is a **term** (`docs/CONTEXT.md`). One that records **a choice and the rules that now hold** is a **decision** (`docs/decisions/NNNN-<slug>.md`). One that records **a solved problem whose lesson outlives the fix** is a **solution** (`docs/learnings/<slug>-<date>.md`).

   **Matching two types is normal.** Write the more durable one — `term > decision > solution` — and let it cite the other. Never write both: that reintroduces the duplication the gate's generalization step exists to prevent.

6. **Gather what the entry needs.** Read the relevant commits and search `docs/learnings/` for overlap — an existing entry to extend beats a near-duplicate. Dispatch a sub-agent only when the search is genuinely broad; a gate-passing learning is usually a few sentences whose material you already hold, and three parallel sub-agents to produce a paragraph costs more than it returns.
7. **Compose entry.** Per `references/templates/learning-template.md`. **One paragraph until it earns more** — lead with the conclusion, name specifics (paths, constants, error strings), say why rather than what. The four optional sections are added only when they carry something the paragraph cannot.
8. **Write to the routed path.** A **term** is appended to `docs/CONTEXT.md` per `references/glossary-rules.md` (amend an existing entry rather than adding a second). A **decision** takes the next unused number at `docs/decisions/NNNN-<slug>.md` per `references/adr-format.md`. A **solution** generates `<slug>-<date>` (lowercase, alphanumeric + hyphens, ≤60 chars + `-YYYY-MM-DD`) at `docs/learnings/<slug>-<date>.md`.
9. **Ground the claims — run `scripts/ensemble-validate-claims <written-file>` and read `references/grounding-validation.md`.** The artifact is about to become knowledge future agents act on without re-verifying. Check it before that happens, not after someone follows a dead reference.

   Exit **0** clean, **1** findings to adjudicate, **2** the validator could not run. **Adjudicate, never auto-apply:** a solution doc legitimately cites a path the fix deleted or describes a pre-fix state.

   **Exit 2 means the artifact is unverified.** Record degraded verification and say so in the report — a run whose grounding could not execute must not be reported as grounded. That is the case which otherwise looks identical to clean.

10. **Vocabulary accretion — read `references/glossary-rules.md`.** Independent of what was routed above: if the work surfaced a term whose meaning was not obvious, define it in `docs/CONTEXT.md`. Friction is what surfaces peripheral terms, so a capture is when they are visible.

   **Report the outcome even when nothing qualified.** "No new terms" is a result; silence is indistinguishable from having skipped the step. Do not invent a term to have something to report — the bar is that a new engineer would need it defined.

11. **Apply always-on behaviors** (cross-refs, index update, log append).
12. **Sync `docs/architecture.md`** if material structural change (new module, changed boundaries, new infrastructure, dependency direction shifts, new external integration). Surgical edits only — never regenerate. Bump `updated:`. Per `references/architecture-update-rules.md`.
13. **Sync `foundation.md`** if scope, decisions, or top-level direction changed.
14. **Plan-lifecycle handling.** Step 14 splits into two sub-steps that separate **lifecycle bookkeeping** (always runs) from **documentation-tense rewrites** (only runs on actual capture). Rationale: previously this step was bundled — if the user opened `/en-learn` and said "skip — no learnings to capture," the lifecycle flip was collateral damage and the plan got orphaned at `status: in_progress`. The unbundle ensures the lifecycle flip happens whenever `/en-learn capture` is invoked, regardless of whether a learning was actually filed. The en-ship plan-completion checkpoint (per `docs/en-ship-plan-completion-checkpoint-spec.md`) is the backstop for cases where `/en-learn` isn't invoked at all.

   **11a. Lifecycle flip (always runs when a plan_id is in context).** If `/en-learn capture` was invoked within the context of a specific plan (derivable from the current branch name per `<plan_id>-<slug>` convention, or passed via `--plan <plan-path>`), perform the lifecycle flip:
   - Read frontmatter; check `status:`.
   - If `status: in_progress` OR `status: open`: flip to `status: completed`, set `shipped: <today>`. Both `open` and `in_progress` flow into this path — the `open` case preserves the recovery for builds that skipped the `open → in_progress` flip (interrupted build, manual resume, etc.).
   - If `status: completed`: no-op; plan already moved.
   - If `status: draft` OR `status: abandoned`: skip the flip; surface a one-line notice (`/en-learn` shouldn't be flipping a draft plan to completed).
   - `git mv docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md docs/plans/completed/<PREFIX><NN>-<plan_type>_<slug>.md` (filename preserved verbatim during the move).
   - Stage the rename + frontmatter edit.

   **11a always runs**, even when the user picked "skip — no learnings worth filing" earlier in the capture flow. The flip is lifecycle bookkeeping; it shouldn't be tied to whether wiki content was filed.

   **11b. Documentation-tense updates (only runs when a learning was actually captured).** If a learning was captured during this `/en-learn capture` invocation (i.e. step 7's compose-entry produced a real file in `docs/learnings/<category>/`), AND 11a ran (plan was moved), also:
   - Replace plan-tense ("we will", "this should") with documentation-tense ("we did", "this does").
   - Note any deviations from the plan (sections of the plan that didn't ship as written, or that landed differently).

   **11b is skipped when the user said "skip — no learnings worth capturing"** earlier in the flow; lifecycle flip (11a) still happens, just without the documentation-tense rewrite.

   **Edge case: no plan_id in context.** If `/en-learn capture` is invoked outside any plan context (no plan branch, no `--plan` argument), step 11 is a silent no-op — there's nothing to flip.
15. **Sync `AGENTS.md` / `CLAUDE.md`** only if the artifact directory or top-level guidance changed (rare).
16. **Update `docs/README.md` index** if it exists.
17. **Regenerate `docs/generated/learning-index.md`** by appending the new entry; bump `total_entries`.

## Process — Mode B: `ingest <path-or-url>`

Per `references/learn-ingest.md`:

1. **Read source.** File: `Read`. URL: `WebFetch` with Wayback fallback (per A13).
2. **Off-topic check.** LLM-judged relevance against `foundation.md`. Threshold 0.3 / 1.0 (per A18). Below → silently skip with note ("This source appears off-topic for an engineering wiki — skipped. Re-run with `--force` to ingest anyway."). `--force` overrides.
3. **Discuss takeaways.** Brief — one or two paragraphs.
4. **Write summary.** `docs/learnings/sources/<slug>-<date>.md` with frontmatter including `source_type: file|url`, `source_uri: <path-or-url>`, `fetched: YYYY-MM-DD`.
5. **Walk 5–15 related pages.** Use `learnings-research` agent (or grep + read). Add reciprocal back-refs.
6. **Apply always-on behaviors.**

Optional: `--category {sources|patterns|decisions}` (default `sources`).

## Process — Mode C: `--refresh`

Audit *content* staleness (distinct from `--lint`'s structural health):

1. List all entries in `docs/learnings/` (excluding `archive/`).
2. For each entry:
   - Read frontmatter + TL;DR.
   - Determine: keep / update / replace / archive.
   - User confirms each disposition (or `--auto` for non-judgment cases).
3. **archive** → move to `docs/learnings/archive/`; update `index.md` (remove entry); append log line.
4. **replace** → write a new entry citing the old via `replaced_by:`; mark old `status: superseded`.
5. **update** → in-place edit; bump frontmatter `date:` doesn't change (immutable); add a "Last updated YYYY-MM-DD" inline note.

Useful periodically (~monthly) or after a big architectural shift.

## Process — Mode D: `--pack <library>`

Per `references/pack-reference-template.md`:

1. Resolve library identifier via Context7 (`mcp__context7__resolve-library-id`).
2. Pull docs (`mcp__context7__get-library-docs` or `query-docs`).
3. Optionally augment with WebSearch for recent best-practice content.
4. Flatten to `docs/references/<library>-llms.txt` with frontmatter header.
5. Add entry to `docs/references/index.md`.
6. Append `log.md`: `## [<date>] pack | <library>`.
7. Surface in `AGENTS.md` "Where things live" if the library is project-significant.

Always re-fetches and re-flattens (per A12 — explicit invocation, fresh by default).

## Process — Mode E: `--lint` / `--lint --fix`

Per `references/learn-lint.md`. Audits the wiki *graph*:

- Orphans, missing back-refs, broken links, contradictions, missing pages, stale references, index drift, log drift, data gaps.
- `--fix` auto-applies mechanical fixes (back-refs, broken-link repair, index regen, log append).
- Judgment items (orphans, contradictions, missing-page candidates) → surfaced for the user.

Output: JSON-lines + markdown summary.

## Process — Mode F: `--bootstrap-patterns`

Seeds `docs/learnings/patterns/` from an existing project's codebase. **One-time** retrofit step — meant to give a State-2 project a starting wiki rather than waiting months for organic capture. Per `references/learn-bootstrap-patterns.md`.

2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, exit.
3. **Refuse if already bootstrapped.** Scan `docs/learnings/patterns/` for entries with frontmatter `source: bootstrap`. If any exist, refuse with: *"Bootstrap was already run on `<date>`. Use `/en-learn --refresh` to validate or update existing bootstrapped patterns. Force re-run with `--force`."*
4. **Confirm with user.** Surface: *"Will dispatch `repo-research` to identify 5–10 strong conventions in this codebase and file them as `patterns/` entries flagged `requires_validation: true`. These are reconstructions, not captures from real moments — lower confidence by design. Continue? (y/n)"*
5. **Dispatch `repo-research`.** Prompt structured per `references/learn-bootstrap-patterns.md` § "Research prompt." Asks the agent to identify durable conventions in: file layout, naming, dependency direction, error-handling shape, test placement, common abstractions, framework idioms. Returns 5–10 candidates as JSON.
6. **Cap at 10.** If the research agent returns more than 10, take the top 10 by `confidence` field. Fewer than 5 → surface a warning; the codebase may not have strong conventions yet (typical for very young or scattered repos).
7. **Compose entries.** For each candidate, write `docs/learnings/patterns/<slug>-<date>.md` using `references/templates/learning-template.md` with:
   - Frontmatter: `source: bootstrap`, `confidence: 6`, `requires_validation: true`, `bootstrap_run: <YYYY-MM-DD>`.
   - Body: the convention as a paragraph, plus **Where this applies** (file paths/globs), **How to follow it** (concrete rules), **Citations** (`file:line` examples that exhibit it), and a **Confidence note** (why this is 6 and what would raise it).
   - **Exempt from the capture gate, deliberately and narrowly.** These entries fail condition 1 by construction — a convention read out of the codebase is by definition recoverable from the codebase. Bootstrap is not trying to record something unrecoverable; it is giving a retrofit project a starting index of what its own conventions already are. That is why every entry is stamped `confidence: 6` and `requires_validation: true`, and why the mode is one-time and opt-in. Never route ordinary capture through this exemption, and treat a bootstrap entry that reaches `confidence: 8`+ while still `requires_validation: true` as a lint finding rather than a success.
8. **Apply always-on behaviors.** Cross-refs (none on first run), index update (one line per entry under "Patterns"), log append (one summary line: `## [<date>] bootstrap | <count> patterns from repo-research`).
9. **Surface a follow-up suggestion.** *"Bootstrap complete. <count> patterns filed in `docs/learnings/patterns/` with `requires_validation: true`. Review and validate as you encounter them in `/en-review`, `/en-resolve-pr`, or via `/en-learn --refresh`. Validated entries clear the flag."*

Flags:

| Flag | Effect |
|---|---|
| `--force` | Re-run even if previous bootstrap entries exist (existing bootstrap entries are kept; new ones append) |
| `--dry-run` | Print the candidates the research agent returns without writing files |
| `--max-patterns <N>` | Cap number of entries (default 10) |

Cross-review: **off**. Bootstrap entries are explicitly lower-confidence; peer review on each one would be theater.

## Auto-invoke triggers (per A3 / D26)

`/en-learn` auto-runs after `/en-build` and `/en-qa`. Soft prompt:

> "Capture learnings from this build? (yes / skip)"

User accepts → invoke `capture` mode. User declines → no-op.

Also fires on D21 (capture-from-synthesis) when `/en-plan`, `/en-review`, or `/en-brainstorm` ends with a synthesis worth filing.

## Cross-review

**Off by default in all modes.** `--peer` enables Outside Voice on the entry before write (rare; usually unnecessary for learnings).

## Reference files

- `references/learn-bootstrap-patterns.md` — Mode F prompt + entry shape
- `references/capture-gate.md` — whether to write a learning at all; the default is not to
- `references/templates/learning-template.md` — body structure for capture/ingest writes
- `references/learning-frontmatter-schema.md` — frontmatter rules + examples
- `references/learn-cross-ref-maintenance.md` — always-on back-ref behavior
- `references/learn-index-format.md` — `index.md` structure
- `references/learn-log-format.md` — `log.md` structure
- `references/learn-ingest.md` — file + URL ingest flow with Wayback fallback
- `references/learn-lint.md` — check catalog and auto-fix rules
- `references/architecture-update-rules.md` — when to touch `docs/architecture.md`
- `references/pack-reference-template.md` — `*-llms.txt` structure

## Failure protocol

| Failure | Behavior |
|---|---|
| Source unreadable on `ingest` (404, 403, paste declined) | Log; exit non-zero; no partial write |
| Off-topic skip | Log; exit 0 with one-line note |
| Cross-ref walk partial failure | Primary write succeeds; surface partial; `--lint` self-heals later |
| Frontmatter schema validation fails | Log diff vs expected; user fixes manually |
| `docs/architecture.md` sync conflict (concurrent edit) | Stop sync; surface; user resolves |
| Plan move active→completed but plan still has open units | Refuse the move; surface "FR07 has 2 incomplete units; not moving to completed/" |
| `--lint` finds 100+ violations | Cap report at top 50; note total count; suggest running `--fix` |
| Slug collision (same date, same title) | Append `-<short-hash>` to disambiguate |
