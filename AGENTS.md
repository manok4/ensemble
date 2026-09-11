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
- **Metrics:** `bin/ensemble-metrics --peer-value | --time | --selection` — three named reports over `~/.ensemble/analytics/<repo>.jsonl`, the one-line-per-run rollup the skills write. Read-only. Set `ENSEMBLE_ANALYTICS_DIR` to point it somewhere else; every test run must.

## Test impact

```yaml
test_full_seconds: 286
test_changed_command: './tests/select-for.sh {files}'
lint_changed_command: 'for f in {files}; do case "$f" in docs/*.md|AGENTS.md|CLAUDE.md) bin/ensemble-lint --scope "$f" || exit 1 ;; esac; done'
test_paths_command: 'for t in {tests}; do ./tests/run.sh -k "$t" || exit 1; done'
```

**While iterating, run `./tests/select-for.sh <changed paths>`. Run
`./tests/run.sh` in full before you commit.** That split is the point: 19s for
the thirteen files a skill edit can break, against 286s for all 260. Four
consecutive branches lost time to the same pattern, a small edit followed by the
whole suite, ten times over, and this repo declared nothing `ensemble-test-select`
could use, so every selection came back `empty`.

The selection is **approximate on purpose and must not be trusted as final**.
Many tests here anchor on file *content* — they grep for a clause inside a
SKILL.md they are not named after — and no path-based rule finds those from the
path that changed. Editing anything under `tests/lib/` or `tests/run.sh` skips
the approximation and runs everything.

`test_full_seconds` is a measurement, not a budget: 286s for 260 files on
2026-09-09. It is **over** `/en-build`'s 120s cheap-suite threshold, so a unit
gate resolves the `graph` tier through `test_changed_command` rather than
preferring the whole suite. Re-measure when it crosses five minutes.

`lint_changed_command` runs the doc lint over the changed markdown only. The
whole-`docs/` run is 68s and a single file is 3s. Its `case` matches the same
paths as `.github/workflows/ensemble-lint.yml`, and for the same reason: pointed
at a template under `skills/`, the lint reports the `{{TODAY}}` placeholders as
malformed dates, which is correct for a document and wrong for a template.

`test_paths_command` exists because `./tests/run.sh` takes `-k <pattern>` and not
a list of paths, so the default `<test command> <paths>` form would hand it a
flag it rejects. A unit that edits or adds a test file then runs exactly those
files, in under a second.

`test_changed_command` wins outright over the path tiers when
`ensemble-test-select` resolves a set, which is what makes `/en-build`'s unit
gate and `/en-ship`'s preflight select something here instead of reporting
`empty`.

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
