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

## Test impact

```yaml
test_full_seconds: 230
lint_changed_command: 'for f in {files}; do case "$f" in docs/*.md|AGENTS.md|CLAUDE.md) bin/ensemble-lint --scope "$f" || exit 1 ;; esac; done'
test_paths_command: 'for t in {tests}; do ./tests/run.sh -k "$t" || exit 1; done'
```

`test_full_seconds` is a measurement, not a budget: 226s for 146 files on
2026-09-08. It is under `/en-build`'s cheap-suite threshold, so a phase boundary
runs the whole suite rather than approximating one. That is the right call here
because many tests anchor on file *content* (`grep` for a clause in a SKILL.md),
and no path-based selection can find those from the file that changed. Re-measure
it when the suite crosses five minutes.

`lint_changed_command` runs the doc lint over the changed markdown only. The
whole-`docs/` run is 68s and a single file is 3s. Its `case` matches the same
paths as `.github/workflows/ensemble-lint.yml`, and for the same reason: pointed
at a template under `skills/`, the lint reports the `{{TODAY}}` placeholders as
malformed dates, which is correct for a document and wrong for a template.

`test_paths_command` exists because `./tests/run.sh` takes `-k <pattern>` and not
a list of paths, so the default `<test command> <paths>` form would hand it a
flag it rejects. A unit that edits or adds a test file then runs exactly those
files, in under a second.

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
- **Ad-hoc peer review** → `/en-review --peer <path-or-ref>`
- **Diagnose project setup** → `/en-setup`

## Notes for Claude Code users

See [`CLAUDE.md`](./CLAUDE.md) for slash-command preferences, skill priorities, and Claude-specific guidance for this project. (Codex users can ignore that file.)

## Operating philosophy

The repo is the system of record. Maps are short; encyclopedias are long. Failure means a missing capability, not "try harder" — see `docs/foundation.md` §17 for the principles.
