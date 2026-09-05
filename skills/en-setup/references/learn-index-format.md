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

## Terms

Defined in `docs/CONTEXT.md`, listed here so the index is a complete map. One
line per term, no link target of its own — the glossary is a single file.

- **Carrier** — a skill holding a byte-identical copy of a shared reference.
- **Declaration closure** — a declared file may not name an undeclared one.

## Decisions

- [`../decisions/0002-requires-over-walking.md`](../decisions/0002-requires-over-walking.md) — Declare each skill's files rather than inferring them by walking references.
- [`../decisions/0001-flat-solution-store.md`](../decisions/0001-flat-solution-store.md) — Store solutions flat; split artifacts by type rather than by topic.

## Solutions

- [`single-flight-cache-2026-03-20.md`](./single-flight-cache-2026-03-20.md) — Single-flight cache for per-user side-effecting operations. (related: 3)
- [`refresh-token-race-2026-04-15.md`](./refresh-token-race-2026-04-15.md) — Refresh token race when two requests arrive within the rotation window. (related: 2)

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

### Entry rules per type

One rule cannot serve three shapes: terms have no `date:` and no `related:`, and
ADRs have no frontmatter at all.

| Section | Line format | Sort |
|---|---|---|
| Terms | `- **<Term>** — <definition's first clause>` | alphabetical |
| Decisions | `- [\`NNNN-<slug>.md\`](../decisions/NNNN-<slug>.md) — <H1 claim>` | descending by number |
| Solutions | `- [\`<slug>-<date>.md\`](./<slug>-<date>.md) — <title>. (related: N)` | most recent first by `date:` |

`total_entries` counts all three sections, so a store with terms and decisions and
no solutions is not "empty".

## Frontmatter

| Field | Value |
|---|---|
| `type` | `learning-index` |
| `generated` | `true` (so `bin/ensemble-lint` knows not to flag direct edits) |
| `generator` | `en-learn` |
| `updated` | `YYYY-MM-DD` of last regeneration |
| `total_entries` | Integer count across all categories |

## When `index.md` is regenerated

- After every `en-learn capture` (incremental: just append the new entry to its category section, bump `total_entries` and `updated`).
- After `en-learn --refresh` archives or supersedes entries (incremental: remove the affected line, add an `archive/` link if the page moved).
- After `en-learn --lint --fix` (full regeneration if drift was detected).
- After `en-sweep` runs and detects drift (full regeneration via `en-learn --lint --fix`).

## Empty-state

When the wiki is empty (just initialized), `index.md` is seeded with empty sections, ordered by durability:

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

## Terms

_(no entries yet)_

## Decisions

_(no entries yet)_

## Solutions

_(no entries yet)_

## Drift

`en-learn --lint`'s `index-drift` check compares all three sections against their sources (`docs/CONTEXT.md`, `docs/decisions/`, `docs/learnings/`) and `--fix` regenerates the file. `bin/ensemble-lint` does not read this file; its `index-coverage` rules cover the generated indexes under `docs/generated/`.
