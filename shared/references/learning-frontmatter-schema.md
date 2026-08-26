# Learning frontmatter schema

Every file in `docs/learnings/<category>/` carries this YAML frontmatter. Validated by `bin/ensemble-lint`.

## Schema

```yaml
---
title: <one-line title>
date: YYYY-MM-DD
category: bugs | patterns | decisions | sources
problem_type: <enum below>
component: <module or area>
applies_when: <one-line description of when this applies>
tags: [<tag>, ...]
related: [<paths-to-other-learnings>]
confidence: 1-10
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
| `date` | yes | `YYYY-MM-DD`; immutable after creation |
| `category` | yes | One of `bugs`, `patterns`, `decisions`, `sources` |
| `problem_type` | yes | See enum below; `category=sources` may use `external` |
| `component` | yes | Module/area name; lowercase-kebab-case preferred (e.g., `auth-middleware`) |
| `applies_when` | yes | One sentence; the agent surfaces this when matching against current work |
| `tags` | yes | List; lowercase-kebab-case; 1–6 tags |
| `related` | yes | Repo-relative paths to other learnings; can be empty `[]` for net-new pages |
| `confidence` | yes | Integer 1–10; how strongly the learning's claim is supported |
| `status` | yes | `active` (current), `deprecated` (no longer applies), `superseded` (replaced — `replaced_by:` field optional) |
| `source_type` | sources/ only | `file` or `url` |
| `source_uri` | sources/ only | Repo-relative path for files; full URL for URLs |
| `fetched` | sources/ only | `YYYY-MM-DD`; date the source was read |

## `problem_type` enum

- `correctness` — Logic bugs, incorrect behavior, edge-case failures
- `concurrency` — Race conditions, ordering, locks, async bugs
- `data` — Schema, migrations, data integrity, isolation
- `security` — Auth, permissions, input handling, secrets
- `performance` — Latency, throughput, query plans, caching
- `api-design` — Public interface choices, contract evolution
- `tooling` — Build, test, lint, package manager, CI
- `process` — Workflow, conventions, team practices
- `architecture` — Component boundaries, layering, dependencies, infrastructure
- `external` — External-source summary (sources/ only)

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
date: 2026-04-15
category: bugs
problem_type: concurrency
component: auth-middleware
applies_when: "Multiple requests from one user can race during token rotation"
tags: [auth, refresh-token, race-condition]
related:
  - docs/learnings/patterns/single-flight-cache-2026-03-20.md
confidence: 9
status: active
---
```

### Pattern

```yaml
---
title: "Single-flight cache for per-user side-effecting operations"
date: 2026-03-20
category: patterns
problem_type: concurrency
component: shared-utils
applies_when: "Operation has side effects and must run at most once per user-key, with concurrent callers awaiting the same result"
tags: [cache, concurrency, deduplication]
related:
  - docs/learnings/bugs/refresh-token-race-2026-04-15.md
confidence: 8
status: active
---
```

### Decision

```yaml
---
title: "Chose Drizzle over Prisma for edge-runtime support"
date: 2026-02-10
category: decisions
problem_type: architecture
component: database
applies_when: "Choosing an ORM for a project that targets edge runtimes (Cloudflare Workers, Vercel Edge)"
tags: [database, orm, edge-runtime]
related:
  - docs/learnings/sources/edge-runtime-orm-comparison-2026-01-30.md
confidence: 8
status: active
---
```

### External source

```yaml
---
title: "OpenAI harness-engineering essay summary"
date: 2026-04-20
category: sources
problem_type: external
component: agents-tooling
applies_when: "Designing agent-driven development workflows; deciding on map-vs-encyclopedia documentation patterns"
tags: [agents, harness, openai]
related:
  - docs/learnings/decisions/agents-md-as-pointer-map-2026-04-21.md
confidence: 7
status: active
source_type: url
source_uri: https://openai.com/index/harness-engineering/
fetched: 2026-04-20
---
```
