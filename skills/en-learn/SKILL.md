---
name: en-learn
description: "Compounding wiki maintainer for docs/learnings/. Six modes: capture (default; file a learning post-build/qa, sync architecture/foundation/plan, move plan to completed); ingest <path-or-url>; --refresh (audit staleness); --pack <library>; --lint (graph health — orphans, broken links, contradictions); --bootstrap-patterns (one-time retrofit, seeds patterns/ from existing codebase). Always-on cross-reference maintenance. Trigger phrases: 'capture this', 'learn from', 'ingest', 'pack docs', 'audit learnings', 'wiki health'."
---

> **Helper resolution.** All `references/X` and `bin/Y` paths in this skill resolve relative to `$ENSEMBLE_ROOT` — the install root (skill at `$ENSEMBLE_ROOT/skills/<name>/`, shared helpers at `$ENSEMBLE_ROOT/{references,bin}/`). Compute once at start: `$ENSEMBLE_ROOT` env var if set; otherwise `$(realpath "$(dirname <this-SKILL.md>)/../..")`. Fail loudly if `$ENSEMBLE_ROOT/references/host-detect.md` does not resolve — that indicates a partial install (run `/en-setup` to repair).


# `/en-learn`

Maintain `docs/learnings/` as a compounding interlinked wiki — not a flat folder. Adopts Karpathy's LLM Wiki pattern: agent-maintained, with `index.md` + `log.md` for navigation and `--lint` for graph health.

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

1. **Active cross-reference maintenance** — walk new entry's `related: []`; add reciprocal back-refs to each cited page. Per `$ENSEMBLE_ROOT/references/learn-cross-ref-maintenance.md`.
2. **Index update** — append a one-line entry to `docs/learnings/index.md` under the appropriate category. Per `$ENSEMBLE_ROOT/references/learn-index-format.md`.
3. **Log append** — single line to `docs/learnings/log.md`: `## [YYYY-MM-DD] <op> | <subject>` for most ops; **`capture` mode appends `| <head-sha>` from `git rev-parse --short HEAD`** as the baseline marker for `/en-ship`'s learning checkpoint. Per `$ENSEMBLE_ROOT/references/learn-log-format.md`. Other ops (`refresh`, `ingest-url`, `lint-fix`, `pack`, `capture-from-conversation`) don't write SHA — only `capture` resets the baseline.

## Process — Mode A: `capture` (default)

1. **Detect host (light).** Source `$ENSEMBLE_ROOT/references/host-detect.md`.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, skip (no peer review on capture).
3. **Detect input source.**
   - **Default** (post-build / post-qa) — read recent commits + branch summary.
   - **`--from-conversation`** — take user-confirmed synthesis as input (fired by D21 capture-from-synthesis).
   - **Explicit subject** — user describes what to capture.
4. **Identify category.** `bugs/` (bug fixes), `patterns/` (reusable approach), `decisions/` (architectural/technical choice with rationale).
5. **Spawn parallel sub-tasks.**
   - **Context Analyzer** — extract problem, symptoms, root cause from conversation + commits.
   - **Solution Extractor** — capture the fix, why it works, prevention strategy.
   - **Related Docs Finder** — search `docs/learnings/` for overlap; flag near-duplicates; identify pages that should back-link.
6. **Compose entry.** Body shape from `$ENSEMBLE_ROOT/references/templates/learning-template.md` (TL;DR / Context / What didn't work / Root cause / Fix / Why it works / Prevention / Related / Citations).
7. **Slug + path.** Generate `<slug>-<date>` (lowercase, alphanumeric + hyphens, ≤60 chars + `-YYYY-MM-DD`). Write to `docs/learnings/<category>/<slug>-<date>.md`.
8. **Apply always-on behaviors** (cross-refs, index update, log append).
9. **Sync `docs/architecture.md`** if material structural change (new module, changed boundaries, new infrastructure, dependency direction shifts, new external integration). Surgical edits only — never regenerate. Bump `updated:`. Per `$ENSEMBLE_ROOT/references/architecture-update-rules.md`.
10. **Sync `foundation.md`** if scope, decisions, or top-level direction changed.
11. **Move the relevant plan** from `docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md` to `docs/plans/completed/<PREFIX><NN>-<plan_type>_<slug>.md` (filename preserved verbatim during the move) — flip `status: in_progress` (or `open`, if the build skipped the flip) → `completed`, set `shipped: <date>`, replace plan-tense with documentation-tense, note any deviations from the plan.
12. **Sync `AGENTS.md` / `CLAUDE.md`** only if the artifact directory or top-level guidance changed (rare).
13. **Update `docs/README.md` index** if it exists.
14. **Regenerate `docs/generated/learning-index.md`** by appending the new entry; bump `total_entries`.

## Process — Mode B: `ingest <path-or-url>`

Per `$ENSEMBLE_ROOT/references/learn-ingest.md`:

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

Per `$ENSEMBLE_ROOT/references/pack-reference-template.md`:

1. Resolve library identifier via Context7 (`mcp__context7__resolve-library-id`).
2. Pull docs (`mcp__context7__get-library-docs` or `query-docs`).
3. Optionally augment with WebSearch for recent best-practice content.
4. Flatten to `docs/references/<library>-llms.txt` with frontmatter header.
5. Add entry to `docs/references/index.md`.
6. Append `log.md`: `## [<date>] pack | <library>`.
7. Surface in `AGENTS.md` "Where things live" if the library is project-significant.

Always re-fetches and re-flattens (per A12 — explicit invocation, fresh by default).

## Process — Mode E: `--lint` / `--lint --fix`

Per `$ENSEMBLE_ROOT/references/learn-lint.md`. Audits the wiki *graph*:

- Orphans, missing back-refs, broken links, contradictions, missing pages, stale references, index drift, log drift, data gaps.
- `--fix` auto-applies mechanical fixes (back-refs, broken-link repair, index regen, log append).
- Judgment items (orphans, contradictions, missing-page candidates) → surfaced for the user.

Output: JSON-lines + markdown summary.

## Process — Mode F: `--bootstrap-patterns`

Seeds `docs/learnings/patterns/` from an existing project's codebase. **One-time** retrofit step — meant to give a State-2 project a starting wiki rather than waiting months for organic capture. Per `$ENSEMBLE_ROOT/references/learn-bootstrap-patterns.md`.

1. **Detect host.** Source `$ENSEMBLE_ROOT/references/host-detect.md`.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, exit.
3. **Refuse if already bootstrapped.** Scan `docs/learnings/patterns/` for entries with frontmatter `source: bootstrap`. If any exist, refuse with: *"Bootstrap was already run on `<date>`. Use `/en-learn --refresh` to validate or update existing bootstrapped patterns. Force re-run with `--force`."*
4. **Confirm with user.** Surface: *"Will dispatch `repo-research` to identify 5–10 strong conventions in this codebase and file them as `patterns/` entries flagged `requires_validation: true`. These are reconstructions, not captures from real moments — lower confidence by design. Continue? (y/n)"*
5. **Dispatch `repo-research`.** Prompt structured per `$ENSEMBLE_ROOT/references/learn-bootstrap-patterns.md` § "Research prompt." Asks the agent to identify durable conventions in: file layout, naming, dependency direction, error-handling shape, test placement, common abstractions, framework idioms. Returns 5–10 candidates as JSON.
6. **Cap at 10.** If the research agent returns more than 10, take the top 10 by `confidence` field. Fewer than 5 → surface a warning; the codebase may not have strong conventions yet (typical for very young or scattered repos).
7. **Compose entries.** For each candidate, write `docs/learnings/patterns/<slug>-<date>.md` using `$ENSEMBLE_ROOT/references/templates/learning-template.md` with:
   - Frontmatter: `source: bootstrap`, `confidence: 6`, `requires_validation: true`, `bootstrap_run: <YYYY-MM-DD>`.
   - Body: TL;DR, **Where this applies** (file paths/globs), **Pattern** (the convention), **Why** (rationale inferred from codebase signals), **How to follow it** (concrete rules), **Citations** (specific file:line examples that exhibit the pattern).
   - **Skip** the "What didn't work" / "Root cause" / "Fix" sections — those don't apply to forward-looking conventions.
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

- `$ENSEMBLE_ROOT/references/learn-bootstrap-patterns.md` — Mode F prompt + entry shape
- `$ENSEMBLE_ROOT/references/templates/learning-template.md` — body structure for capture/ingest writes
- `$ENSEMBLE_ROOT/references/learning-frontmatter-schema.md` — frontmatter rules + examples
- `$ENSEMBLE_ROOT/references/learn-cross-ref-maintenance.md` — always-on back-ref behavior
- `$ENSEMBLE_ROOT/references/learn-index-format.md` — `index.md` structure
- `$ENSEMBLE_ROOT/references/learn-log-format.md` — `log.md` structure
- `$ENSEMBLE_ROOT/references/learn-ingest.md` — file + URL ingest flow with Wayback fallback
- `$ENSEMBLE_ROOT/references/learn-lint.md` — check catalog and auto-fix rules
- `$ENSEMBLE_ROOT/references/architecture-update-rules.md` — when to touch `docs/architecture.md`
- `$ENSEMBLE_ROOT/references/pack-reference-template.md` — `*-llms.txt` structure
- `$ENSEMBLE_ROOT/references/host-detect.md`

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
