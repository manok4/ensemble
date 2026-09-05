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

## [2026-04-28] capture | Single-flight cache for per-user side-effecting operations | 4b0424d
## [2026-04-26] capture | Refresh token race when two requests arrive within rotation window | 7caca49
## [2026-04-24] lint-fix | Repaired 3 missing back-refs
## [2026-04-23] refresh | Archived 2 entries; updated 4
## [2026-04-22] capture-from-conversation | Plan-vs-reality drift in FR03
```

## Line format

```markdown
## [YYYY-MM-DD] <op> | <subject>                    # for non-capture operations
## [YYYY-MM-DD] capture | <subject> | <head-sha>    # for capture mode only (baseline reset)
```

`capture` mode writes an additional `| <head-sha>` field carrying the git short-SHA of HEAD at the moment of capture. This is the **baseline** that `/en-build`'s learning checkpoint reads to compute "commits since last capture" via `git log <head-sha>..HEAD`. Other operations (`refresh`, `lint-fix`, `migrate`, `capture-from-conversation`) don't carry a SHA — they don't reset the baseline; only explicit `capture` does.

Legacy entries without `| <head-sha>` continue to parse. The en-ship checkpoint falls back to a date-based baseline scan with a one-line "imprecise baseline" notice. The next `capture` operation re-establishes the precise baseline on the new entry.

| Element | Required | Notes |
|---|---|---|
| `## ` | yes | Markdown H2 — makes `grep "^## \[" log.md` give clean results |
| `[YYYY-MM-DD]` | yes | Date in brackets; immutable after write |
| `<op>` | yes | One of the operations below |
| ` \| ` | yes | Pipe separator |

## `<op>` values

| Op | Triggered by |
|---|---|
| `capture` | `en-learn capture` (default mode) |
| `capture-from-conversation` | `en-learn capture --from-conversation` (synthesis-driven) |
| `refresh` | `en-learn --refresh` (audit pass) |
| `migrate` | `en-learn --migrate` (layout migration) |
| `lint-fix` | `en-learn --lint --fix` (auto-repair pass) |
| `archive` | Page moved to `archive/` (during refresh) |
| `supersede` | Page marked superseded with `replaced_by:` |
| `sweep-update` | `en-sweep` invoked `en-learn` for drift cleanup |

## When log entries are written

- Every `en-learn` mode appends one line at the **end** of its run.
- Multiple ops in a single run (e.g., `--lint --fix` repairs 3 things) → one entry, with the count in the subject (`Repaired 3 missing back-refs`).
- `en-sweep` invocations of `en-learn --lint` → entry includes `sweep-update` op.

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
