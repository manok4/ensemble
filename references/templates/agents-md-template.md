# Template — `AGENTS.md`

Used by `/en-foundation` and `/en-setup` to seed the project-level `AGENTS.md` (host-agnostic pointer map).

> **Strict rules:**
> - Target ≤ 100 lines body (~150 hard ceiling — soft P2 lint at >150).
> - Host-agnostic. Read by Claude Code, Codex, and any other agent.
> - Map, not encyclopedia. Every section points to a deeper source of truth in `docs/`.
> - Never inline content that belongs in `foundation.md`, `architecture.md`, or `learnings/`.

## Substitution variables

| Variable | Source |
|---|---|
| `{{PROJECT_NAME}}` | `foundation.md` `project:` |
| `{{ONE_LINE_PURPOSE}}` | `foundation.md` Section 1 (Executive Summary) — first sentence |
| `{{TODAY}}` | `YYYY-MM-DD` at generation time |
| `{{BUILD_CMD}}` | Detected from project (e.g., `bun build`, `npm run build`); `<unset>` if not found |
| `{{TEST_CMD}}` | Detected from project; `<unset>` if not found |
| `{{LINT_CMD}}` | Detected from project; `<unset>` if not found |
| `{{TYPECHECK_CMD}}` | Detected from project; `<unset>` if not found |
| `{{DEV_CMD}}` | Detected from project; `<unset>` if not found |
| `{{LANG}}` | Detected from project (e.g., `TypeScript`, `Python`, `Rust`) |

## Template body

```markdown
---
project: {{PROJECT_NAME}}
type: agent-map
host: any
created: {{TODAY}}
updated: {{TODAY}}
target_length_lines: 100
---

# {{PROJECT_NAME}} — agent map

> {{ONE_LINE_PURPOSE}}

This file is the **canonical project map**. Any agent (Codex, Claude Code, others) should read it first to orient. Deeper sources of truth live in `docs/`. Keep this file short — point to where the answer lives, don't inline it.

## Project shape

- **Language:** {{LANG}}
- **Build:** `{{BUILD_CMD}}`
- **Test:** `{{TEST_CMD}}`
- **Lint:** `{{LINT_CMD}}`
- **Typecheck:** `{{TYPECHECK_CMD}}`
- **Dev server:** `{{DEV_CMD}}`

## Where things live

| Topic | Source of truth |
|---|---|
| Product vision, requirements, decisions | [`docs/foundation.md`](./docs/foundation.md) |
| Current architecture (components, layers, data flows) | [`docs/architecture.md`](./docs/architecture.md) |
| In-flight feature plans | [`docs/plans/active/`](./docs/plans/active/) |
| Shipped feature plans (living documentation) | [`docs/plans/completed/`](./docs/plans/completed/) |
| Tracked technical debt | [`docs/plans/tech-debt-tracker.md`](./docs/plans/tech-debt-tracker.md) |
| Compounding learnings (bugs, patterns, decisions) | [`docs/learnings/`](./docs/learnings/) — start at [`index.md`](./docs/learnings/index.md) |
| External library references | [`docs/references/`](./docs/references/) |
| Brainstorm / design exploration | [`docs/designs/`](./docs/designs/) |

## Conventions

- **Repo-relative paths only** in artifacts. No absolute paths (`/Users/...`, `C:\...`).
- **Stable IDs:** `R<N>` for foundation requirements, `U<N>` for plan units (never renumbered), `FR<NN>` for plan filenames, `TD<N>` for tracked debt.
- **Conventional commits:** `<type>(<scope>): <subject>` — types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`. Subject ≤ 50 chars, imperative.
- **Doc-as-source-of-truth:** if a decision isn't in `docs/`, the agent can't see it. Capture it via `/en-learn capture` before moving on.

## Working with this project

- **Start a new feature** → `/en-plan`
- **Implement a plan** → `/en-build <plan-path>`
- **Review code** → `/en-review`
- **End-to-end test in browser** → `/en-qa`
- **Capture a learning after a fix** → `/en-learn capture`
- **Ad-hoc cross-review** → `/en-cross-review <path-or-ref>`
- **Diagnose project setup** → `/en-setup`

## Notes for Claude Code users

See [`CLAUDE.md`](./CLAUDE.md) for slash-command preferences, skill priorities, and Claude-specific guidance for this project. (Codex users can ignore that file.)

## Operating philosophy

The repo is the system of record. Maps are short; encyclopedias are long. Failure means a missing capability, not "try harder" — see `docs/foundation.md` §17 for the principles.
```

## Notes on generation

- The template above is the **starting** state. `en-learn` and `en-garden` will refine it as the project evolves (adding entries to "Where things live" if `docs/references/` gains content, dropping rows if a section is empty).
- When the project has no `foundation.md` yet (State 2 retrofit), substitute `{{ONE_LINE_PURPOSE}}` with `<TODO: run /en-foundation to seed this>`.
- When commands aren't detected, leave the value as `<unset>` rather than guessing.
- The `host: any` frontmatter is critical — it's how `bin/ensemble-lint` knows this file is the host-agnostic map.

## Append-merge mode (State 2b/2c/2d)

When an existing `AGENTS.md` is present, `/en-setup` does **not** overwrite it. Instead:

1. Parse existing content.
2. Check for the presence of an Ensemble pointer index (heuristic: a "Where things live" section, or any link to `docs/foundation.md`).
3. If absent → append the **"Where things live" + "Working with this project" + "Notes for Claude Code users"** sections as a new section block (heading: `## Ensemble pointer map`).
4. If present → no-op. The user already has Ensemble integration.
5. Never modify existing user content.

See `references/templates/agents-md-merge-rules.md` for the full append-merge logic.
