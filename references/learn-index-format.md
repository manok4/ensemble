# `docs/learnings/index.md` format

The content catalog the `learnings-research` agent reads **first** before drilling into individual pages. Maintained by `en-learn` on every write.

> **Why this exists.** Karpathy's observation: a curated index file scales surprisingly well at moderate scale (~hundreds of entries) and avoids the operational complexity of embedding-based RAG. Reach for vector search only when the store crosses ~500 entries.

## Structure

```markdown
---
type: learning-index
generated: true
generator: en-learn
updated: YYYY-MM-DD
total_entries: <N>
---

# Learnings — index

> Auto-maintained by `en-learn`. Do not hand-edit. Run `en-learn --lint --fix` to repair drift.

## Bugs

- [`bugs/refresh-token-race-2026-04-15.md`](./bugs/refresh-token-race-2026-04-15.md) — Refresh token race when two requests arrive within rotation window. (related: 2)
- [`bugs/empty-cart-state-2026-03-08.md`](./bugs/empty-cart-state-2026-03-08.md) — Empty-cart state crash on mobile. (related: 1)

## Patterns

- [`patterns/single-flight-cache-2026-03-20.md`](./patterns/single-flight-cache-2026-03-20.md) — Single-flight cache for per-user side-effecting operations. (related: 3)
- [`patterns/typed-action-creators-2026-02-28.md`](./patterns/typed-action-creators-2026-02-28.md) — Typed action creators for the redux-toolkit boundary. (related: 0)

## Decisions

- [`decisions/drizzle-over-prisma-2026-02-10.md`](./decisions/drizzle-over-prisma-2026-02-10.md) — Chose Drizzle over Prisma for edge-runtime support. (related: 1)

## Sources

- [`sources/openai-harness-engineering-2026-04-20.md`](./sources/openai-harness-engineering-2026-04-20.md) — OpenAI harness-engineering essay summary. (related: 4)
```

## Entry format

Each line follows the pattern:

```markdown
- [`<relative-path>`](<relative-path>) — <title>. (related: <count>)
```

| Element | Source |
|---|---|
| `<relative-path>` | Repo-relative from `docs/learnings/` |
| Link text | Same path in backticks |
| `<title>` | The page's `title:` frontmatter, verbatim |
| `(related: <count>)` | Number of items in the page's `related:` field |

Sort order within each category: **most recent first** (descending by `date:`).

## Frontmatter

| Field | Value |
|---|---|
| `type` | `learning-index` |
| `generated` | `true` (so `bin/ensemble-lint` knows not to flag direct edits) |
| `generator` | `en-learn` |
| `updated` | `YYYY-MM-DD` of last regeneration |
| `total_entries` | Integer count across all categories |

## When `index.md` is regenerated

- After every `en-learn capture` or `en-learn ingest` (incremental: just append the new entry to its category section, bump `total_entries` and `updated`).
- After `en-learn --refresh` archives or supersedes entries (incremental: remove the affected line, add an `archive/` link if the page moved).
- After `en-learn --lint --fix` (full regeneration if drift was detected).
- After `en-garden` runs and detects drift (full regeneration via `en-learn --lint --fix`).

## Empty-state

When the wiki is empty (just initialized), `index.md` is seeded with empty category sections:

```markdown
---
type: learning-index
generated: true
generator: en-learn
updated: <DATE>
total_entries: 0
---

# Learnings — index

> Auto-maintained by `en-learn`. Do not hand-edit.

## Bugs

_(no entries yet)_

## Patterns

_(no entries yet)_

## Decisions

_(no entries yet)_

## Sources

_(no entries yet)_
```

`/en-setup` State 2 seeds this when creating `docs/learnings/`.

## Lint rule

`bin/ensemble-lint` checks:

- `index-coverage.missing` — page exists but is not in `index.md` (P1).
- `index-coverage.stale-entry` — `index.md` line points to a non-existent or moved page (P1).
- `index-coverage.title-drift` — `index.md` line title differs from page's `title:` frontmatter (P2).
- `index-coverage.related-count-drift` — count in `index.md` differs from page's `related:` length (P2).

`--fix` regenerates `index.md` to match the underlying pages.
