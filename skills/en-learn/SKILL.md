---
name: en-learn
description: "Compounding wiki maintainer for docs/learnings/. Five modes: 'capture' (default — file a learning after a feature ships, a bug is fixed, or a synthesis emerges; sync architecture.md / foundation / plans; move plan from active to completed); 'ingest <path-or-url>' (proactive — read external source, write summary, walk 5-15 related pages and add back-refs); '--refresh' (audit content staleness; keep/update/replace/archive entries); '--pack <library>' (flatten library docs to docs/references/<lib>-llms.txt); '--lint' (wiki-graph health: orphans, missing back-refs, broken links, contradictions, missing pages). Always-on cross-reference maintenance after every write. Use after building/QA, after a bug fix, when reading external engineering material, when curating library references, or to audit wiki health. Trigger phrases: 'capture this', 'learn from', 'ingest', 'pack docs for', 'audit learnings', 'lint learnings', 'wiki health'."
---

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

## Always-on behaviors (across `capture` and `ingest`)

After every write:

1. **Active cross-reference maintenance** — walk new entry's `related: []`; add reciprocal back-refs to each cited page. Per `references/learn-cross-ref-maintenance.md`.
2. **Index update** — append a one-line entry to `docs/learnings/index.md` under the appropriate category. Per `references/learn-index-format.md`.
3. **Log append** — single line to `docs/learnings/log.md`: `## [YYYY-MM-DD] <op> | <subject>`. Per `references/learn-log-format.md`.

## Process — Mode A: `capture` (default)

1. **Detect host (light).** Source `references/host-detect.md`.
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
6. **Compose entry.** Body shape from `references/templates/learning-template.md` (TL;DR / Context / What didn't work / Root cause / Fix / Why it works / Prevention / Related / Citations).
7. **Slug + path.** Generate `<slug>-<date>` (lowercase, alphanumeric + hyphens, ≤60 chars + `-YYYY-MM-DD`). Write to `docs/learnings/<category>/<slug>-<date>.md`.
8. **Apply always-on behaviors** (cross-refs, index update, log append).
9. **Sync `docs/architecture.md`** if material structural change (new module, changed boundaries, new infrastructure, dependency direction shifts, new external integration). Surgical edits only — never regenerate. Bump `updated:`. Per `references/architecture-update-rules.md`.
10. **Sync `foundation.md`** if scope, decisions, or top-level direction changed.
11. **Move the relevant plan** from `docs/plans/active/FRXX-*.md` to `docs/plans/completed/FRXX-*.md` — flip `status: active` → `completed`, set `shipped: <date>`, replace plan-tense with documentation-tense, note any deviations from the plan.
12. **Sync `AGENTS.md` / `CLAUDE.md`** only if the artifact directory or top-level guidance changed (rare).
13. **Update `docs/README.md` index** if it exists.
14. **Regenerate `docs/generated/learning-index.md`** by appending the new entry; bump `total_entries`.

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

## Auto-invoke triggers (per A3 / D26)

`/en-learn` auto-runs after `/en-build` and `/en-qa`. Soft prompt:

> "Capture learnings from this build? (yes / skip)"

User accepts → invoke `capture` mode. User declines → no-op.

Also fires on D21 (capture-from-synthesis) when `/en-plan`, `/en-review`, or `/en-brainstorm` ends with a synthesis worth filing.

## Cross-review

**Off by default in all modes.** `--peer` enables Outside Voice on the entry before write (rare; usually unnecessary for learnings).

## Reference files

- `references/templates/learning-template.md` — body structure for capture/ingest writes
- `references/learning-frontmatter-schema.md` — frontmatter rules + examples
- `references/learn-cross-ref-maintenance.md` — always-on back-ref behavior
- `references/learn-index-format.md` — `index.md` structure
- `references/learn-log-format.md` — `log.md` structure
- `references/learn-ingest.md` — file + URL ingest flow with Wayback fallback
- `references/learn-lint.md` — check catalog and auto-fix rules
- `references/architecture-update-rules.md` — when to touch `docs/architecture.md`
- `references/pack-reference-template.md` — `*-llms.txt` structure
- `references/host-detect.md`

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
