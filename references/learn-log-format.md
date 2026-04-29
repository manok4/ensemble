# `docs/learnings/log.md` format

Append-only chronological record of every `en-learn` operation. Grep-friendly format (Karpathy's tip).

## Structure

```markdown
---
type: learning-log
generated: true
generator: en-learn
updated: YYYY-MM-DD
---

# Learnings — log

> Append-only. One line per `en-learn` operation. Grep with: `grep "^## \[" docs/learnings/log.md | tail -10`

## [2026-04-28] capture | Single-flight cache for per-user side-effecting operations
## [2026-04-27] ingest-url | OpenAI harness-engineering essay summary
## [2026-04-26] capture | Refresh token race when two requests arrive within rotation window
## [2026-04-25] pack | drizzle-orm
## [2026-04-24] lint-fix | Repaired 3 missing back-refs
## [2026-04-23] refresh | Archived 2 entries; updated 4
## [2026-04-22] capture-from-conversation | Plan-vs-reality drift in FR03
```

## Line format

```markdown
## [YYYY-MM-DD] <op> | <subject>
```

| Element | Required | Notes |
|---|---|---|
| `## ` | yes | Markdown H2 — makes `grep "^## \[" log.md` give clean results |
| `[YYYY-MM-DD]` | yes | Date in brackets; immutable after write |
| `<op>` | yes | One of the operations below |
| ` \| ` | yes | Pipe separator |
| `<subject>` | yes | Short description; usually the page's `title:` for capture/ingest, the action for lint/refresh/pack |

## `<op>` values

| Op | Triggered by |
|---|---|
| `capture` | `en-learn capture` (default mode) |
| `capture-from-conversation` | `en-learn capture --from-conversation` (synthesis-driven) |
| `ingest-file` | `en-learn ingest <path>` |
| `ingest-url` | `en-learn ingest <url>` |
| `pack` | `en-learn --pack <library>` |
| `refresh` | `en-learn --refresh` (audit pass) |
| `lint-fix` | `en-learn --lint --fix` (auto-repair pass) |
| `archive` | Page moved to `archive/` (during refresh) |
| `supersede` | Page marked superseded with `replaced_by:` |
| `garden-update` | `en-garden` invoked `en-learn` for drift cleanup |

## Why this format

- **Grep-friendly.** `grep "^## \[" log.md | tail -10` shows the last 10 ops without scanning the whole file.
- **One line per op.** No multi-line entries; no nested headings; consistent shape.
- **Append-only.** No edits; no deletes. If something was wrong, the next op corrects forward.
- **Human-readable.** Renders as a clean H2 list when viewed as markdown.

## When log entries are written

- Every `en-learn` mode appends one line at the **end** of its run.
- Multiple ops in a single run (e.g., `--lint --fix` repairs 3 things) → one entry, with the count in the subject (`Repaired 3 missing back-refs`).
- `en-garden` invocations of `en-learn --lint` → entry includes `garden-update` op.

## Used by

- `en-learn --lint` checks for **log drift**: every page's most-recent op (per its `updated:` frontmatter) should have a corresponding line in the log. Mismatches surface as P2 advisories. Auto-fix appends the missing line.
- `en-garden` reads the last 30 days of log entries to summarize "what's happened recently" without re-scanning the whole wiki.
- Future `en-learn --refresh` may read the log to identify pages overdue for re-evaluation.

## Empty-state

When the wiki is initialized, `log.md` is seeded:

```markdown
---
type: learning-log
generated: true
generator: en-learn
updated: <DATE>
---

# Learnings — log

> Append-only. One line per `en-learn` operation.

_(no operations logged yet)_
```

`/en-setup` State 2 seeds this when creating `docs/learnings/`. The first `en-learn capture` removes the placeholder line and adds its own entry.
