# Learning frontmatter schema

Every file in `docs/learnings/<category>/` carries this YAML frontmatter. Validated by `bin/ensemble-lint`.

## Schema

```yaml
---
title: <one-line title>
applies_when: <the situation that should surface this entry>
date: YYYY-MM-DD
category: bugs | patterns | decisions | sources
tags: [<tag>, ...]
related: [<paths-to-other-learnings>]
status: active | deprecated | superseded
# sources/ subcategory adds:
source_type: file | url
source_uri: <path or URL>
fetched: YYYY-MM-DD
---
```

## Field rules

| Field | Required | Notes |
|---|---|---|
| `title` | yes | One line; no markdown formatting; quotes in YAML if it contains a colon |
| `applies_when` | yes | **The retrieval field.** The situation that should surface this entry, written so a future agent recognises the situation it is in. See below. |
| `date` | yes | `YYYY-MM-DD`; immutable after creation |
| `category` | yes | One of `bugs`, `patterns`, `decisions`, `sources`. Selects the directory. |
| `tags` | yes | List; lowercase-kebab-case; 1–6 tags |
| `related` | yes | Repo-relative paths to other learnings; can be empty `[]` for net-new pages |
| `status` | yes | `active` (current), `deprecated` (no longer applies), `superseded` (replaced — `replaced_by:` field optional) |
| `source_type` | sources/ only | `file` or `url` |
| `source_uri` | sources/ only | Repo-relative path for files; full URL for URLs |
| `fetched` | sources/ only | `YYYY-MM-DD`; date the source was read |

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
replaced_by: docs/learnings/patterns/auth-rotation-2026-09-15.md
```

## Worked examples

### Bug

```yaml
---
title: "Refresh token race when two requests arrive within rotation window"
applies_when: "Multiple requests from one user can race during token rotation"
date: 2026-04-15
category: bugs
tags: [auth, refresh-token, race-condition]
related:
  - docs/learnings/patterns/single-flight-cache-2026-03-20.md
status: active
---
```

### Pattern

```yaml
---
title: "Single-flight cache for per-user side-effecting operations"
applies_when: "Operation has side effects and must run at most once per user-key, with concurrent callers awaiting the same result"
date: 2026-03-20
category: patterns
tags: [cache, concurrency, deduplication]
related:
  - docs/learnings/bugs/refresh-token-race-2026-04-15.md
status: active
---
```

### Decision

```yaml
---
title: "Chose Drizzle over Prisma for edge-runtime support"
applies_when: "Choosing an ORM for a project that targets edge runtimes (Cloudflare Workers, Vercel Edge)"
date: 2026-02-10
category: decisions
tags: [database, orm, edge-runtime]
related:
  - docs/learnings/sources/edge-runtime-orm-comparison-2026-01-30.md
status: active
---
```

### External source

```yaml
---
title: "OpenAI harness-engineering essay summary"
applies_when: "Designing agent-driven development workflows; deciding on map-vs-encyclopedia documentation patterns"
date: 2026-04-20
category: sources
tags: [agents, harness, openai]
related:
  - docs/learnings/decisions/agents-md-as-pointer-map-2026-04-21.md
status: active
source_type: url
source_uri: https://openai.com/index/harness-engineering/
fetched: 2026-04-20
---
```
