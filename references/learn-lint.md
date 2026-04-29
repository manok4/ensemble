# `en-learn --lint` — wiki-graph health checks

Audits the structural health of `docs/learnings/`. Distinct from `--refresh` (content staleness) and `bin/ensemble-lint` (file-shape).

> **Division of responsibility:**
> - `bin/ensemble-lint` → file-shape (frontmatter validity, ID stability, cross-link integrity, status correctness, freshness).
> - `learn --lint` → wiki-graph (orphans, missing back-refs, contradictions, missing pages, data gaps, index/log drift).
> - Together they give full coverage. `en-garden` runs both.

## Check catalog

| Check | What it detects | Severity | Auto-fix? |
|---|---|---|---|
| `orphans` | Pages with **zero** inbound `related:` references | P2 | No (judgment) |
| `missing-back-refs` | A.related contains B but B.related doesn't contain A | P1 | Yes (`--fix`) |
| `broken-links` | A.related points to a path that doesn't exist | P1 | Sometimes (auto when target moved is obvious; surface otherwise) |
| `contradictions` | Claims across pages that conflict | P3 | No (judgment) |
| `missing-pages` | Concept named in 3+ pages without a dedicated entry | P2 | No (suggest creating) |
| `stale-references` | Links pointing to files moved or deleted | P1 | Sometimes |
| `index-drift` | `index.md` doesn't match underlying pages | P1 | Yes (regenerate) |
| `log-drift` | Operations missing from `log.md` (compared against git log of `docs/learnings/`) | P2 | Yes (append) |
| `data-gaps` | Thin areas where `learn ingest` would add value | P3 | No (suggest queries) |

## How each check runs

### `orphans`

For every page in `docs/learnings/` (excluding `index.md`, `log.md`, `archive/`):

```
inbound_count = number of other pages whose `related:` field includes this page's path
if inbound_count == 0:
  emit P2 finding
```

### `missing-back-refs`

For every page A and every path B in A's `related:` field:

```
if B exists and B's `related:` does NOT contain A's path:
  emit P1 finding
  if --fix: append A's path to B's related; bump B's updated date
```

### `broken-links`

For every `related:` entry:

```
if target file does not exist:
  search for a moved-to candidate (same slug at different path, or fuzzy title match in archive/)
  if obvious match found and --fix:
    update the related: entry to the new path
  else:
    emit P1 finding for human resolution
```

### `contradictions`

LLM-judged. The lint runs an analysis pass with a prompt:

```
You are auditing a learning wiki for contradictions. Below are pairs of claims from
different pages that overlap in topic but may conflict. For each pair, output:
  - "consistent" if they agree
  - "contradicts" with a 1-sentence explanation if they disagree
  - "context-dependent" if both are valid in different scenarios

Only emit "contradicts" with high confidence (≥7).
```

Pairs are found by overlapping `tags` and `component` fields. Output: P3 advisory with both citations. No auto-fix (always judgment).

### `missing-pages`

Concept extraction: scan all page bodies for noun-phrase mentions of capitalized terms or quoted phrases. Count occurrences. If a term appears in 3+ pages and there's no page with that term in `title:`:

- Emit P2 advisory: "Concept 'X' appears in 3+ pages without a dedicated entry. Consider creating one."

No auto-fix.

### `stale-references`

Same as `broken-links` but for cross-doc references **outside** `docs/learnings/` (e.g., a learning that cites `src/auth/middleware.ts:42` but the file no longer exists). Auto-fix when obvious; otherwise surface.

### `index-drift`

Compare `index.md` against actual pages:

- Page exists but missing from `index.md` → P1 (auto-fix: add).
- `index.md` line points to a non-existent page → P1 (auto-fix: remove or update path).
- Title in `index.md` differs from page's `title:` frontmatter → P2 (auto-fix: sync).
- `(related: <count>)` differs from page's `related:` length → P2 (auto-fix: update).

### `log-drift`

For every page in `docs/learnings/` (excluding `archive/`):

- Compute the most recent `en-learn` operation on that page (per its `updated:` field).
- Look for a corresponding `log.md` entry on or near that date.
- If missing → P2 (auto-fix: append a `## [<date>] capture | <title>` line).

### `data-gaps`

Heuristic: identify topical clusters (via tag co-occurrence) where the wiki has < 3 pages. For each thin area:

- Emit P3 advisory with suggested search queries:

> "Sparse coverage on `[performance, database]` (1 page). Suggested ingest queries: `database query performance optimization`, `n+1 query patterns`, `query plan analysis`."

No auto-fix.

## CLI

```bash
/en-learn --lint                # Report only
/en-learn --lint --fix          # Auto-apply mechanical fixes; report judgment items
/en-learn --lint --fix --dry-run # Show what would change without applying
```

## Output format

JSON-lines for machine consumption (one finding per line) plus a markdown summary at the end.

```json
{"check":"missing-back-refs","severity":"P1","page":"docs/learnings/patterns/single-flight-cache-2026-03-20.md","missing_from":"docs/learnings/bugs/refresh-token-race-2026-04-15.md","fixable":true}
{"check":"orphans","severity":"P2","page":"docs/learnings/decisions/old-decision-2025-11-01.md","inbound_count":0,"fixable":false}
{"check":"contradictions","severity":"P3","pages":["docs/learnings/patterns/A.md","docs/learnings/patterns/B.md"],"summary":"<explanation>","fixable":false}
```

```markdown
## Wiki lint summary

- **Auto-fixed (with --fix):** 5
  - 3 missing back-refs added
  - 2 index-drift entries reconciled
- **Need human judgment:** 4
  - 2 orphans
  - 1 contradiction
  - 1 missing-page suggestion
- **Suggested ingests:** 1 data-gap query in `[performance, database]`
```

## Cadence

- On demand: `/en-learn --lint`
- Invoked by `en-garden`: every PR-merge pass. Auto-fixes go into garden's batch PRs (separate batches per fix category).

## When `en-garden` invokes `--lint --fix`

Garden routes the output through its PR-batching flow:

- One PR per fix category (back-refs / broken-links / index-drift / log-drift).
- Each PR has its own conventional-commit message: `chore(learnings): fix N missing back-refs`, `chore(learnings): regenerate index.md`, etc.
- Judgment items (orphans, contradictions, missing-pages, data-gaps) → posted as a comment on the source PR for human attention. Garden does not auto-fix these.
