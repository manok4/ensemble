---
project: Ensemble
type: agent-map
host: any
created: 2026-08-28
updated: 2026-08-28
target_length_lines: 100
---

# Ensemble — agent map

> A set of self-contained Claude Code / Codex skills for plan-driven development with cross-agent peer review.

This file is the **canonical project map**. Any agent (Codex, Claude Code, others) should read it first to orient. Deeper sources of truth live in `docs/`. Keep this file short — point to where the answer lives, don't inline it.

## Project shape

- **Language:** Shell (POSIX sh / bash) + Markdown
- **Build:** `<unset>`
- **Test:** `./tests/run.sh`
- **Lint:** `bin/ensemble-lint --scope docs/`
- **Typecheck:** `<unset>`
- **Dev server:** `<unset>`

## Where things live

| Topic | Source of truth |
|---|---|
| Product vision, requirements, decisions | [`docs/foundation.md`](./docs/foundation.md) |
| Current architecture (components, layers, data flows) | [`docs/architecture.md`](./docs/architecture.md) |
| In-flight feature plans | [`docs/plans/active/`](./docs/plans/active/) |
| Shipped feature plans | [`docs/plans/completed/`](./docs/plans/completed/) |
| Tracked technical debt | [`docs/plans/tech-debt-tracker.md`](./docs/plans/tech-debt-tracker.md) |
| Domain vocabulary — what words mean here | [`docs/CONTEXT.md`](./docs/CONTEXT.md) |
| Decisions and the rules they create | [`docs/decisions/`](./docs/decisions/) |
| Solved problems whose lesson outlives the fix | [`docs/learnings/`](./docs/learnings/) — start at [`index.md`](./docs/learnings/index.md) |
| Brainstorm / design exploration | [`docs/designs/`](./docs/designs/) |

## Conventions

- **Repo-relative paths only** in artifacts. No absolute paths (`/Users/...`, `C:\...`).
- **Stable IDs:** `R<N>` for foundation requirements, `U<N>` for plan units (never renumbered), `EN<NN>` for plan filenames, `TD<N>` for tracked debt.
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
