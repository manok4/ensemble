# Learning frontmatter schema

Every solution at `docs/learnings/<slug>-<date>.md` carries this YAML frontmatter. Terms live in `docs/CONTEXT.md` and decisions in `docs/decisions/`; neither carries frontmatter — see `artifact-types.md`. Validated by `bin/ensemble-lint`.

## Schema

```yaml
---
title: <one-line title>
applies_when: <the situation that should surface this entry>
date: YYYY-MM-DD
tags: [<tag>, ...]
related: [<paths-to-other-learnings>]
status: active | deprecated | superseded
---
```

## Field rules

| Field | Required | Notes |
|---|---|---|
| `title` | yes | One line; no markdown formatting; quotes in YAML if it contains a colon |
| `applies_when` | yes | **The retrieval field.** The situation that should surface this entry, written so a future agent recognises the situation it is in. See below. |
| `date` | yes | `YYYY-MM-DD`; immutable after creation |
| `tags` | yes | List; lowercase-kebab-case; 1–6 tags |
| `related` | yes | Repo-relative paths to other learnings; can be empty `[]` for net-new pages |
| `status` | yes | `active` (current), `deprecated` (no longer applies), `superseded` (replaced — `replaced_by:` field optional) |

## Writing `applies_when`

Every other field is bookkeeping. `applies_when` is the field that decides whether
the entry is ever found again, so it carries the weight.

Write the **situation**, not the subject. A future agent does not search for the
topic of your entry; it is in the middle of some work and needs to recognise that
this entry is about the work it is doing.

| Instead of | Write |
|---|---|
| `Guard scripts` | `Writing any guard, assertion, or verification step` |
| `The peer helper` | `A helper returns structured output that a caller trusts without checking` |
| `Migrations` | `Adding a column that existing rows have no value for` |

The left column names a component; the right names a moment. Only the right column
matches when the agent has not already guessed which entry it is looking for.

Keep it to one sentence. If it needs two, the entry is probably two entries — or a
class that has not been named yet (see `capture-gate.md`).

## `replaced_by` field

When `status: superseded`, add a `replaced_by:` field pointing to the replacement page:

```yaml
status: superseded
replaced_by: docs/learnings/auth-rotation-2026-09-15.md
```

## Worked examples

### Bug

```yaml
---
title: "Refresh token race when two requests arrive within rotation window"
applies_when: "Multiple requests from one user can race during token rotation"
date: 2026-04-15
tags: [auth, refresh-token, race-condition]
related:
  - docs/learnings/single-flight-cache-2026-03-20.md
status: active
---
```

### Pattern

```yaml
---
title: "Single-flight cache for per-user side-effecting operations"
applies_when: "Operation has side effects and must run at most once per user-key, with concurrent callers awaiting the same result"
date: 2026-03-20
tags: [cache, concurrency, deduplication]
related:
  - docs/learnings/refresh-token-race-2026-04-15.md
status: active
---
```

A decision is not a solution: it routes to `docs/decisions/NNNN-<slug>.md` with no frontmatter (`artifact-types.md`).
