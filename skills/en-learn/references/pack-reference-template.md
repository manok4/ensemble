# Pack-reference template — `docs/references/<library>-llms.txt`

Used by `/en-learn --pack <library>` to flatten an external library's docs into a single in-context lookup file. Eliminates most network round-trips on subsequent `/en-plan`, `/en-build`, and `/en-brainstorm` runs.

## Substitution variables

| Variable | Source |
|---|---|
| `{{LIBRARY}}` | The library identifier (e.g., `drizzle-orm`, `react`, `clerk`) |
| `{{VERSION}}` | The version pinned during pack (resolved via Context7 or package metadata) |
| `{{SOURCE}}` | Source URL or "Context7" |
| `{{FETCHED}}` | `YYYY-MM-DD` |

## Header / frontmatter

The first lines of the `.txt` file (yes — frontmatter even in a `.txt`):

```text
---
type: pack-reference
library: {{LIBRARY}}
version: {{VERSION}}
source: {{SOURCE}}
fetched: {{FETCHED}}
generated: true
generator: en-learn-pack
---
```

## Body structure

Loose; depends on the library. Typical shape:

```text
# {{LIBRARY}} ({{VERSION}}) — flattened reference for in-context lookup

## Overview

<one-paragraph summary of what the library does, its primary API, and any
opinionated patterns the project should follow>

## Installation

<install command from official docs>

## Core API

<function/class/component signatures with one-line descriptions>

## Common patterns

<code excerpts demonstrating idiomatic usage; lifted verbatim from official docs>

## Gotchas / footguns

<documented pitfalls; version-specific changes; deprecated APIs>

## Recipes

<copy-paste-ready snippets for tasks the project will likely do>

## Source

- Context7: <library_id>
- Official docs: <URL>
- Fetched: {{FETCHED}}

## Version notes

<changelog excerpts for versions newer than {{VERSION}}, if any>
```

## Length budget

Target 5K–30K tokens per pack. Larger libraries (e.g., React, Next.js, Tailwind):

- Split by domain (`react-hooks-llms.txt`, `react-server-components-llms.txt`).
- Each split has its own frontmatter + index-entry in `docs/references/index.md`.

## Index entry

Every `.txt` file gets a one-line entry in `docs/references/index.md`:

```markdown
- [`drizzle-orm-llms.txt`](./drizzle-orm-llms.txt) — Drizzle ORM 0.31.x. Schema, queries, migrations. (fetched 2026-04-25)
```

Sorted by library name.

## Re-pack triggers

`/en-learn --pack <library>` always re-fetches and re-flattens (per A12). The user invokes it explicitly, so always-fresh is the right default. Common reasons to re-pack:

- Library version bumped in the project's `package.json` / lockfile.
- The cached pack is older than 90 days.
- The library introduced a breaking change.

## What this isn't

- **Not a tutorial.** Don't include "getting started" walkthroughs unless the project genuinely needs onboarding context. Flattened references are for lookup during planning/build, not learning.
- **Not a complete dump.** Lifting all of the official docs verbatim is wasteful. Curate.
- **Not a substitute for the lock file.** The pack records the version that informed our context, not the version the project is bound to.

## Worked example header

```text
---
type: pack-reference
library: drizzle-orm
version: 0.31.2
source: Context7
fetched: 2026-04-25
generated: true
generator: en-learn-pack
---

# drizzle-orm (0.31.x) — flattened reference

## Overview

Drizzle is a TypeScript ORM with a query-builder approach (vs Prisma's schema
generator). Compiles to SQL at build time. First-class edge-runtime support.

Project chose this over Prisma per docs/learnings/decisions/drizzle-over-
prisma-2026-02-10.md (edge-runtime requirement).

## Installation

bun add drizzle-orm
bun add -d drizzle-kit

## Core API

- `drizzle()` — connection factory. Pass a postgres-js / better-sqlite3 / etc client.
- Schema definition: `pgTable(name, columns)`, `mysqlTable`, `sqliteTable`.
- Queries: `.select().from(table).where(condition)`, etc.
- Migrations: `drizzle-kit generate:pg`, `drizzle-kit migrate`.

[... 200-500 more lines depending on library size ...]
```

## When in doubt

If a library's docs are short and cohesive (< 5K tokens raw), `/en-learn ingest <url>` may be a better fit than `--pack`. Ingest writes a structured summary to `docs/learnings/sources/`. Pack is for libraries the project will reference repeatedly during planning and build.
