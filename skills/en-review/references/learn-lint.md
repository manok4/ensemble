# `en-learn --lint` — wiki-graph health checks

Audits the structural health of `docs/learnings/`. Distinct from `--refresh` (content staleness) and `bin/ensemble-lint` (file-shape).

> **Division of responsibility:**
> - `bin/ensemble-lint` → file-shape (frontmatter validity, ID stability, cross-link integrity, status correctness, freshness).
> - `learn --lint` → wiki-graph (orphans, missing back-refs, contradictions, missing pages, data gaps, index/log drift).
> - Together they give full coverage. `en-sweep` runs both.

## Check catalog

| Check | What it detects | Severity | Auto-fix? |
|---|---|---|---|
| `orphans` | Pages with **zero** inbound `related:` references | P2 | No (judgment) |
| `missing-back-refs` | A.related contains B but B.related doesn't contain A | P1 | Yes (`--fix`) |
| `broken-links` | A.related points to a path that doesn't exist | P1 | Sometimes (auto when target moved is obvious; surface otherwise) |
| `contradictions` | Claims across pages that conflict | P3 | No (judgment) |
| `missing-pages` | Project-specific term used in 3+ pages with no entry in `docs/CONTEXT.md` | P2 | No (suggest defining) |
| `stale-references` | Links pointing to files moved or deleted | P1 | Sometimes |
| `index-drift` | `index.md` doesn't match the three sources behind it | P1 | Yes (regenerate) |
| `log-drift` | Operations missing from `log.md` (compared against git log of `docs/learnings/`) | P2 | Yes (append) |

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

A term used in three or more pages with no entry in `docs/CONTEXT.md` is a
project-specific word nobody defined. That is the glossary's accretion trigger,
reached mechanically: capture's step 9 catches terms the work rubbed against,
and this catches the ones that were always there and never earned a definition.

Surfaced, never auto-written — whether a repeated word is domain vocabulary or
just a common noun is a judgment, and the bar is that a new engineer would need
it defined.

### `stale-references`

Same as `broken-links` but for cross-doc references **outside** `docs/learnings/` (e.g., a learning that cites `src/auth/middleware.ts:42` but the file no longer exists). Auto-fix when obvious; otherwise surface.

### `index-drift`

`index.md` has three sections and three sources behind them: **Terms** from
`docs/CONTEXT.md`, **Decisions** from `docs/decisions/`, and **Solutions** from
`docs/learnings/`. Drift in any one of them is drift.

Checking only the solutions would leave two thirds of the store able to fall out
of the index while the check reports clean.

Auto-fixable: regenerate from all three.

### `log-drift`

For every page in `docs/learnings/` (excluding `archive/`):

- Compute the most recent `en-learn` operation on that page (per its `updated:` field).
- Look for a corresponding `log.md` entry on or near that date.
- If missing → P2 (auto-fix: append a `## [<date>] capture | <title>` line).

