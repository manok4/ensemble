---
project: Ensemble
type: agent-map
host: any
created: 2026-08-28
updated: 2026-11-02
target_length_lines: 100
---

# Ensemble agent map

> A set of self-contained Claude Code and Codex skills for plan-driven development with cross-agent peer review.

Put shared agent guidance here, never in `CLAUDE.md`, which only imports this file.

## Project shape

`ensemble-unit-verify` and `ensemble-test-select` parse these bullets. Keep the ``- **Key:** `command` `` form with nothing backticked after the command, and write `<unset>` when there is none.

- **Language:** Shell (POSIX sh / bash) + Markdown
- **Build:** `<unset>`
- **Test:** `./tests/run.sh`
- **Lint:** `bin/ensemble-lint --scope docs/`
- **Typecheck:** `<unset>`
- **Dev server:** `<unset>`
- **Metrics:** `bin/ensemble-metrics --peer-value | --time | --selection`

`ensemble-metrics` prints three read-only reports over `~/.ensemble/analytics/<repo>.jsonl`, the one-line-per-run rollup the skills write. `ENSEMBLE_ANALYTICS_DIR` points it elsewhere. `tests/run.sh` sets it and gives every test a scratch run ledger, so stub peers never reach real metrics.

## Repo layout

| Path | Holds |
|---|---|
| `skills/<name>/` | One self-contained skill: `SKILL.md` plus its own `references/`, `scripts/` and, where it dispatches them, `agents/` |
| `bin/` | `ensemble-lint` (a copy of `skills/en-setup/references/templates/ensemble-lint`) and `ensemble-metrics` |
| `scripts/` | `check-health`, and `sync-to-codex`, which links skills into `~/.codex/` |
| `setup` | Machine install for Claude Code, Codex or both |
| `tests/` | `run.sh` runs every `*.test.sh`; `select-for.sh` picks the tests a change can break; `parity/` pins duplicated files |
| `tests/evals/` | `trigger-rank` checks skill descriptions route their prompts (in CI); `run-behavioral` drives real headless sessions on demand, never in CI |
| `hooks/hooks.json` | Plugin hooks, light on purpose |
| `.claude-plugin/`, `.codex-plugin/` | Plugin and marketplace manifests |
| `.ensemble/` | Repo config. `config.local.yaml` is per-developer and gitignored; the example is tracked |
| `.github/workflows/ensemble-tests.yml` | CI: doc lint and tests, changed-only on a PR and in full on `main` |

## Where things live

| Topic | Source of truth |
|---|---|
| Product vision, requirements, skill and agent catalog, architecture | [`docs/foundation.md`](./docs/foundation.md): §5 skills, §6 agents, §9 architecture, §18 doc lints |
| Decisions and the rules they create | D-IDs in `docs/foundation.md` §4.1. `/en-learn` writes new ADRs to `docs/decisions/NNNN-<slug>.md`, created on first use |
| In-flight plans | [`docs/plans/active/`](./docs/plans/active/) |
| Shipped plans | [`docs/plans/completed/`](./docs/plans/completed/), listed in [`docs/generated/plan-index.md`](./docs/generated/plan-index.md) |
| Tracked technical debt | [`docs/plans/tech-debt-tracker.md`](./docs/plans/tech-debt-tracker.md) |
| Domain vocabulary | [`docs/CONTEXT.md`](./docs/CONTEXT.md) |
| Solved problems whose lesson outlives the fix | [`docs/learnings/`](./docs/learnings/), start at [`index.md`](./docs/learnings/index.md) |
| Brainstorms and design docs | [`docs/designs/`](./docs/designs/) |
| Skill audits and reviews | [`docs/reviews/`](./docs/reviews/) |
| CI code-review action setup | [`docs/integrations/`](./docs/integrations/) |

## Routing work

Route by what a plan settles, not by size (D138). Use `/en-plan` when the work has an open decision, a risk surface (auth, payments, migrations, external contracts, destructive data), parts that must land in order or that a reviewer could judge apart, more than one session of work, or a design doc behind it. Otherwise use `/en-fix <request>`, however many files it touches.

| Intent | Command |
|---|---|
| Explore an idea before planning | `/en-brainstorm` |
| New product, or retrofit the foundation | `/en-foundation` |
| Plan a feature, refactor or fix | `/en-plan` |
| Implement a plan | `/en-build <plan-path>` |
| One change, no plan, through to a PR | `/en-fix <request>` |
| One entry point: routes the request, plans if needed, through to a PR | `/en-conductor <request>` * |
| Bounded autonomous loop | `/en-loop` * |
| Diagnose a bug | `/en-debug` |
| Simplify the branch diff | `/en-simplify` |
| Review the branch | `/en-review`; ad-hoc peer review: `/en-review --peer <path-or-ref>` |
| End-to-end browser test | `/en-qa` |
| Commit, push and open a PR | `/en-ship` |
| Address PR review comments | `/en-resolve-pr` |
| Capture a learning | `/en-learn capture` |
| Prune the test suite | `/en-test-audit [<path>]` * |
| Diagnose project setup | `/en-setup` * |
| Clean doc drift | `/en-sweep` *, scheduled weekly by default; leave routine doc drift to it rather than opening a bespoke PR |

`*` marks manual-invoke skills (`disable-model-invocation: true`). Name the command for the user; do not start the work some other way. `en-guardrail` is always on through PreToolUse hooks and needs no command.

When several skills could apply: use the one the user names; else the most specific (`en-build` over a generic implementation skill, `en-foundation` over `en-plan` for a new product); if still ambiguous, ask once with two options.

## Conventions

- **Repo-relative paths only** in artifacts. No absolute paths (`/Users/...`, `C:\...`).
- **Stable IDs:** `R<N>` requirements, `D<N>` decisions, `U<N>` plan units (never renumbered), `EN<NN>` plans (`plan_id_prefix: EN`), `TD<N>` tracked debt.
- **Conventional commits:** `<type>(<scope>): <subject>`, types `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`. Subject ≤ 50 chars, imperative.
- **Skills are self-contained.** A file two skills share is copied byte-identical into each. Edit every copy in the same change; `tests/parity/` fails on drift. Edit `ensemble-lint` in its `en-setup` template, then copy it to `bin/` (`tests/lint/bin-template-sync.test.sh`).
- **Generated files are never hand-edited:** `docs/generated/` and `docs/learnings/index.md`.
- **Docs are the source of truth.** A decision outside `docs/` is invisible to the next agent; capture it with `/en-learn capture`. Agent memory holds user preferences and feedback only; project facts go in the repo.

## Test impact

```yaml
test_changed_command: './tests/select-for.sh {files}'
lint_changed_command: 'for f in {files}; do case "$f" in docs/*.md|AGENTS.md|CLAUDE.md) bin/ensemble-lint --scope "$f" || exit 1 ;; esac; done'
test_paths_command: 'for t in {tests}; do ./tests/run.sh -k "$t" || exit 1; done'
```

**Iterate with `./tests/select-for.sh <changed paths>`; run `./tests/run.sh` in full before you commit.** A selection takes seconds; the suite takes several minutes. Four consecutive branches lost time re-running the whole suite after each small edit.

- **The selection is approximate and never final.** Many tests grep for a clause inside a `SKILL.md` they are not named after, and no path rule finds those. A change under `tests/lib/` or to `tests/run.sh` runs everything.
- **`test_changed_command`** wins over the path tiers in `ensemble-test-select`, so `/en-build`'s unit gate and `/en-ship`'s preflight select from it instead of reporting `empty`.
- **`lint_changed_command`** lints changed markdown only: 3s a file against 68s for all of `docs/`. Its `case` keeps the lint off templates under `skills/`, where `{{TODAY}}` placeholders read as malformed dates.
- **`test_paths_command`** exists because `run.sh` takes `-k <pattern>`, not a list of paths. A unit that edits a test file runs exactly that file.
- **No `test_full_seconds`, on purpose.** It only makes a checkpoint run the whole suite when the figure is 300s or less. This suite is slower than that, and a hand-kept figure drifts: it read 286 while the suite took 447s, which sent the EN21 build through the full suite twice.

## Host notes

- **Claude Code:** deferred tools such as `AskUserQuestion`, `CronCreate` and `TaskCreate` need a `ToolSearch` load before first use.

## Operating philosophy

The repo is the system of record. Maps are short; encyclopedias are long. Failure means a missing capability, not "try harder". `docs/foundation.md` §17 has the principles.
