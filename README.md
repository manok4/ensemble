# Ensemble

> An engineering harness for **Claude Code** and **Codex** with cross-agent peer review, structured plans, a compounding learnings wiki, and event-driven doc-drift cleanup.

Ensemble is a 14-skill, 11-agent toolkit that turns rough ideas into shipped, peer-reviewed code and keeps the project's documentation honest as it goes. Every skill detects whether it's running under Claude Code or Codex and adapts tool names, peer-review CLI invocations, and platform-specific behaviors automatically.

## What problem this solves

Solo and small-team development with AI agents tends to accumulate three kinds of debt that compound silently:

1. **Documentation drift** — the code outpaces the docs; future contributors (human or agent) work from stale context.
2. **Lost lessons** — bug fixes and design decisions vanish into git history; the next agent re-discovers them at full cost.
3. **Single-perspective work** — one agent's blind spot becomes the codebase's blind spot.

Ensemble fixes each by design:

- **Document-as-source-of-truth** — every phase produces a durable artifact in `docs/`; the next phase reads it. The repo *is* the system of record.
- **Compounding wiki** — `docs/learnings/` accumulates bug fixes, patterns, and decisions. `/en-learn` links them, prunes them, and surfaces them when planning new work.
- **Cross-agent peer review** — Claude Code and Codex review each other's work via subprocess CLI calls. Single-agent fallback when only one CLI is installed.
- **Always-on safety** — `/en-guardrail` prompts before destructive Bash commands; `/en-sweep` cleans up doc drift after every PR merge.

## Five design pillars

1. **Document-as-source-of-truth.** Foundation, architecture, plans, learnings — all live in `docs/`. Anything not in the repo is illegible to the agent.
2. **Map, not encyclopedia.** `AGENTS.md` and `CLAUDE.md` are pointer indexes (~100 lines each); SKILL.md files run 150–400 lines with templates externalized to each skill's own `references/`.
3. **Cross-agent peer review.** `claude -p ↔ codex exec`. Outside Voice catches blind spots a single agent misses.
4. **Compounding knowledge.** Every solved problem and decision gets captured. Future runs query the wiki automatically.
5. **Lean by design.** Skills are small. Agents are short specialist prompts. The scaffolding earns its keep.

---

## Workflow

The lifecycle pipeline with four orthogonal skills:

```text
                          ┌──────────────┐
                          │  /en-setup   │  Project bootstrap (one-time per repo)
                          │ (state 1/2/3)│  Detects greenfield, retrofit, or already-set-up
                          └──────┬───────┘
                                 │
                  ┌──────────────┴──────────────┐
                  ▼                             ▼
         ┌──────────────┐              ┌──────────────┐
         │/en-brainstorm│ ───────────▶ │/en-foundation│  PRD + tech direction + architecture seed
         │  (optional)  │              │              │  Asks for plan_id_prefix; Outside Voice review
         └──────────────┘              └──────┬───────┘
                                              │
                                              ▼
                                       ┌──────────────┐
                                       │  /en-plan    │  <PREFIX><NN> plan with stable U-IDs + plan_type
                                       │              │  --resume / --from-legacy modes; peer review
                                       └──────┬───────┘
                                              │
                                              ▼
                                       ┌──────────────┐
                                       │  /en-build   │  Per-unit: implement → gate1 → simplifier
                                       │              │  → gate2 → peer review → host applies → commit
                                       └──────┬───────┘
                                              │
                                              ▼
                                       ┌──────────────┐
                                       │  /en-review  │  Multi-persona; confidence-gated
                                       │              │  Sub-threshold → TD entries
                                       └──────┬───────┘
                                              │
                                              ▼
                                       ┌──────────────┐
                                       │   /en-qa     │  System checks + Playwright browser flows
                                       │              │  Atomic bug-fix + regression test commits
                                       └──────┬───────┘
                                              │
                                              ▼
                                       ┌──────────────┐
                                       │  /en-learn   │  capture / ingest / refresh / pack / lint /
                                       │              │  bootstrap-patterns. Syncs architecture.md
                                       └──────┬───────┘
                                              │
                                              ▼
                                       ┌──────────────┐
                                       │   /en-ship   │  Pre-flight + secret scan + PR
                                       │              │  + push + gh pr create (--auto-merge optional)
                                       └──────┬───────┘
                                              │
                                              ▼  [PR opened]
                                              │
                ┌─────────────────────────────┴─────────────────────────────┐
                ▼                                                           ▼
       Anthropic Claude Code                                        Codex review
       Review action fires                                          (Cloud or self-hosted)
                │                                                           │
                └─────────────────────────────┬─────────────────────────────┘
                                              ▼
                                       ┌──────────────┐
                                       │/en-resolve-pr│  6-verdict triage; fixes + replies +
                                       │              │  resolve threads. --enable-auto-merge
                                       └──────┬───────┘
                                              │
                                              │  PR merged to main
                                              ▼
                                       ┌──────────────┐
                                       │   /en-sweep  │  Doc-drift cleanup; auto-merging PRs
                                       │              │  + continuous monitoring (dead-code +
                                       │              │  dep-vuln) → TD or draft plan
                                       └──────────────┘

   Orthogonal skills, available at any point in the flow:

         ┌────────────────┐  ┌────────────────┐  ┌────────────────┐
         │/en-cross-review│  │   /en-debug    │  │  /en-guardrail │
         │  Ad-hoc peer   │  │  Trace-driven  │  │  Always-on     │
         │  review of any │  │  bug repro;    │  │  PreToolUse    │
         │  artifact      │  │  read-only     │  │  hook on Bash  │
         └────────────────┘  └────────────────┘  └────────────────┘
```

## Quick start

A typical cycle:

```text
/en-plan "Add SSO via Okta"
/en-build docs/plans/active/EN03-feature_sso-okta.md
/en-review
/en-qa
/en-ship --auto-merge
# PR opens. Reviewers (humans + Anthropic action + optional Codex) leave comments.
/en-resolve-pr
# All comments addressed; auto-merge flips green; merge.
# /en-sweep auto-runs post-merge to clean doc drift.
# /en-learn capture auto-prompts to file what you learned.
```

For a focused bug investigation:

```text
/en-debug "trace_id 4bf92f3577…"
# Hypothesis: error originates at src/auth/refresh.ts:42, confidence 9/10.
/en-build docs/plans/active/EN12-bug_refresh-null-email.md
/en-resolve-pr
```

To bring a legacy plan into Ensemble's flow:

```text
/en-plan --from-legacy docs/plans/legacy/q3-roadmap.md
# Reads the legacy plan, runs Q&A + research, produces a properly-structured
# Ensemble plan with R-IDs, U-IDs, and peer review. Legacy file untouched.
```

---

## New project vs existing project

`/en-setup` detects which state your repo is in and runs the right flow. The two paths look meaningfully different.

### State 1 — New project (greenfield)

Empty repo or initial commit only, no `docs/foundation.md`.

```bash
cd my-new-project
git init
/en-setup
```

`/en-setup` detects greenfield and **doesn't pre-create artifacts**. Instead it points you at the right next steps:

```
1. Run /en-brainstorm to explore what you're building.
2. Run /en-foundation to lock product+technical scope, generate
   AGENTS.md / CLAUDE.md / docs/architecture.md, and emit the
   bootstrap <PREFIX>01-feature_project-setup plan.
```

The flow then becomes:

```text
/en-brainstorm "build a multi-tenant analytics dashboard"
/en-foundation
# Asks for plan_id_prefix (e.g., 'AN' for Analytics) — used in plan IDs.
# Asks Q&A about product, users, requirements, stack, architecture.
# Writes docs/foundation.md, docs/architecture.md, AGENTS.md, CLAUDE.md.
# Emits AN01-feature_project-setup.md as the bootstrap plan.

/en-build docs/plans/active/AN01-feature_project-setup.md
# Sets up repo: dependencies, CI, baseline tests.

# From here on: /en-plan → /en-build → /en-review → ...
```

### State 2 — Existing project (retrofit)

Has source code; missing `docs/foundation.md` or `docs/learnings/`.

```bash
cd my-existing-project
/en-setup
```

`/en-setup` runs a 14-step retrofit flow:

1. Detect sub-variant (which of `AGENTS.md` / `CLAUDE.md` exist).
2. **Existing-plans archival** — if you already have plans in some other format, offers to move them to `docs/plans/legacy/` so Ensemble's lint/build flows ignore them. Migrate them later via `/en-plan --from-legacy`.
3. Create `docs/` skeleton.
4. Seed empty `index.md`, `log.md`, generated indexes.
5. Generate or merge `AGENTS.md` (preserving any existing content).
6. Generate or merge `CLAUDE.md`.
7. Add `.gitignore` entries.
8. Install `.github/workflows/en-sweep.yml`.
9. Create `.ensemble/config.local.example.yaml`.
10. **Guardrail check** — offer to install `/en-guardrail` (project-scoped or global).
11. **Claude Code Review action check** — offer to install Anthropic's PR-review action.
12. **Auto-merge repo-setting check** — surface if `allow_auto_merge` is off at the repo level.
13. **Bootstrap-patterns offer** — informational; surfaces `/en-learn --bootstrap-patterns` for after `/en-foundation --retrofit`.
14. Recommend next steps.

After `/en-setup`, the typical retrofit path is:

```text
/en-foundation --retrofit
# Reads the codebase, asks targeted Q&A, fills foundation.md + architecture.md
# from observed reality.

/en-learn --bootstrap-patterns
# Optional: dispatches repo-research to identify 5-10 strong conventions
# already in the codebase, files them as docs/learnings/patterns/ entries
# with requires_validation: true. Gives the wiki a starting point without
# pretending to be capture-fresh.

# Now jump into normal flow: /en-plan for the next feature.
```

### State 3 — Already integrated

Diagnostic mode — runs health checks, surfaces 🟢/🟡/🔴 per check, offers repairs for missing pieces.

---

## Installation

Both paths require at least one of `claude` (Claude Code) or `codex` CLI installed. **Both is recommended** for full cross-agent peer review; single-agent fallback works with one.

### Path 1 — Direct clone + `./setup` (preferred)

Works for Claude Code, Codex, or both, on any host:

```bash
git clone https://github.com/manok4/ensemble.git ~/.ensemble-source
cd ~/.ensemble-source && ./setup
```

The `./setup` script auto-detects which CLIs are installed and symlinks (or copies on Windows) the skills and agents into the right places. Run with `--verify-only` to check without making changes.

### Path 2 — Claude Code marketplace (alternative)

```text
/plugin marketplace add manok4/ensemble
/plugin install ensemble@ensemble
```

For a Codex sidecar install on the same machine, see [`docs/foundation.md` §19.2](./docs/foundation.md#192-phase-a--machine-level-install-one-time-per-machine).

### Verifying the install

```bash
~/.ensemble-source/scripts/check-health
```

Prints 🟢/🟡/🔴 across host detection, MCP servers, required CLIs, and skill/agent install paths.

### Optional integrations

After `/en-setup` is run in a project, you can install:

- **Anthropic's Claude Code Review action** — automatic Claude review on every PR. See [`docs/integrations/anthropic-code-review-action.md`](./docs/integrations/anthropic-code-review-action.md). OAuth (Pro/Max subscription) or API key.
- **OpenAI Codex review** — managed via Codex Cloud or self-hosted via `openai/codex-action@v1`. See [`docs/integrations/codex-code-review-action.md`](./docs/integrations/codex-code-review-action.md).

You can run both simultaneously for two AI perspectives.

---

## Skill catalog

14 skills total — 9 lifecycle, 5 orthogonal. All prefixed `en-`.

### Lifecycle skills (9)

| # | Skill | Purpose |
|---|---|---|
| 1 | `/en-brainstorm` | Q&A + research + 2–3 approaches with trade-offs. Outputs a design doc. |
| 2 | `/en-foundation` | Combined PRD + technical direction + initial architecture. Asks for `plan_id_prefix`; Outside Voice peer review. Emits `foundation.md`, `architecture.md`, `AGENTS.md`, `CLAUDE.md`, plus a bootstrap plan for greenfield. |
| 3 | `/en-plan` | Feature/refactor plan with stable U-IDs + `plan_type` (feature \| improvement \| bug). Modes: default; `--resume <plan>` (promote a draft); `--from-legacy <path>` (migrate legacy plan with proper R-ID/U-ID assignment + peer review). |
| 4 | `/en-build` | Execute a plan unit-by-unit. Per-unit flow: implement → gate1 (tests + lint) → simplifier → gate2 → peer review → host applies findings → commit. Flips `status: open → in_progress` at start. |
| 5 | `/en-review` | Multi-persona code review (correctness / testing / maintainability / standards always-on; security / performance / migrations conditional). **Confidence-gated** — sub-threshold findings file as TD entries instead of cluttering review output. Modes: interactive / headless / report-only. |
| 6 | `/en-qa` | System checks + Playwright browser end-to-end testing. Atomic bug-fix + regression test commits. |
| 7 | `/en-learn` | Compounding wiki maintainer. Modes: `capture` (default, auto-fires post-build/qa); `ingest <path-or-url>`; `--refresh` (audit staleness); `--pack <library>` (flatten library docs); `--lint` (graph health); `--bootstrap-patterns` (one-time retrofit, seeds `patterns/` from existing codebase). |
| 8 | `/en-ship` | Pre-flight (lint + typecheck + targeted tests) + secret scan + conventional commit + push + `gh pr create`. `--auto-merge` enables `gh pr merge --auto --squash`. |
| 9 | `/en-resolve-pr` | Address incoming PR review comments. 6-verdict triage (`fixed` / `fixed-differently` / `replied` / `not-addressing` / `declined` / `needs-human`). Reports merge readiness; `--enable-auto-merge` flag flips on auto-merge after addressing. Up to 2 fix-verify cycles per invocation. |

### Orthogonal skills (5)

| # | Skill | Purpose |
|---|---|---|
| 10 | `/en-debug` | Telemetry-driven debugging. Reads structured logs (per `references/observability-conventions.md`), correlates by `trace_id` / `request_id` / event field, surfaces hypothesis with `file:line` and confidence 1–10. **Read-only** — never writes code. |
| 11 | `/en-cross-review` | Ad-hoc Outside Voice peer review of any artifact (file, diff, branch, current uncommitted work). `--focus security \| performance \| tests \| correctness \| maintainability \| all`. |
| 12 | `/en-guardrail` | Always-on `PreToolUse` hook that prompts before destructive Bash commands (recursive `rm`, `DROP TABLE`, force-push, `terraform destroy`, `aws s3 rm --recursive`, etc.). Localhost+test/dev DB exemption. Per-command bypass via `ENSEMBLE_GUARDRAIL=off`. Installed globally or project-scoped. |
| 13 | `/en-sweep` | Event-driven doc-drift cleanup. Auto-fires on `push` to `main`. Opens auto-merging doc-only PRs. **Continuous monitoring** (opt-in): dead-code (`ts-prune` / `vulture` / Go `deadcode`) + dep-vuln (`npm audit` / `pip-audit` / `cargo audit`) with size-based triage — trivial → TD entry; pattern → draft plan. |
| 14 | `/en-setup` | Project-level bootstrap and diagnostics. Detects state 1/2/3; for retrofits: archives non-conforming plans, creates skeleton, generates AGENTS.md/CLAUDE.md, installs en-sweep workflow + guardrail + Claude Code Review action, checks `allow_auto_merge`, surfaces bootstrap-patterns offer. |

For full process detail, mode flags, and reference files per skill, see [`docs/workflow-and-catalog.md`](./docs/workflow-and-catalog.md).

---

## Agent catalog

11 agents total. Skills orchestrate; agents specialize. **No agent invokes another agent.**

### Always-on reviewers (4) — read-only, return findings JSON

| Agent | Specialty |
|---|---|
| `correctness-reviewer` | Logic errors, race conditions, edge cases, type-safety violations |
| `testing-reviewer` | Coverage gaps, brittle assertions, missing failure-path tests |
| `maintainability-reviewer` | Naming, complexity, premature abstraction, dead code |
| `standards-reviewer` | Project conventions (CLAUDE.md / AGENTS.md / `docs/learnings/patterns/`) |

### Conditional reviewers (3) — fire when the diff matches

| Agent | Triggers on |
|---|---|
| `security-reviewer` | Auth, sessions, tokens, crypto, SQL, file uploads, secrets |
| `performance-reviewer` | DB queries, hot paths, N+1, cache strategy, large data sets |
| `migrations-reviewer` | Schema changes, data migrations, backwards-compat shims |

### Research agents (3) — read-only, return data

| Agent | Specialty |
|---|---|
| `repo-research` | Scan codebase for patterns, conventions, file paths, prior art |
| `learnings-research` | Query `docs/learnings/` for relevant prior bugs/patterns/decisions |
| `web-research` | External docs (Context7) and best-practice search (WebSearch) with Wayback fallback |

### Refiner (1) — modifies code, wrapped in two verification gates

| Agent | Role |
|---|---|
| `code-simplifier` | Per-unit cleanup pass during `/en-build`. Runs between gate 1 (tests pass) and gate 2 (re-verify after simplifier). On gate 2 failure, simplifier edits revert automatically. |

For agent invariants, dispatch matrix, and per-agent prompts, see [`docs/workflow-and-catalog.md`](./docs/workflow-and-catalog.md) and [`shared/agents/`](./shared/agents).

---

## Repository layout

Every skill directory is **self-contained**: it carries its own copy of every
reference, template, script and agent it reads, so the folder works wherever it
lands. Nothing inside a skill resolves a path above itself.

```
ensemble/
├── .claude-plugin/                # Claude Code plugin manifest
├── .codex-plugin/                 # Codex plugin manifest
├── skills/                        # 17 skills (en-*)
│   └── en-plan/                   # every skill has the same shape:
│       ├── SKILL.md
│       ├── CONTRACT.md            #   what other skills may rely on (callable skills only)
│       ├── references/            #   its own copies — generated + skill-owned
│       ├── agents/                #   its own copies of the agents it dispatches
│       └── scripts/               #   its own copies of the scripts it runs
├── shared/                        # BUILD INPUT — never installed, never read at runtime
│   ├── references/                #   42 files: canonical text with 2+ consumers
│   ├── bin/                       #   15 scripts: ensemble-lint, ensemble-plan-hash, …
│   ├── agents/                    #   11 agent definitions
│   ├── manifest.json              #   which skill receives which file
│   └── README.md                  #   how to work in here — read this before editing
├── agents/                        # generated flat set, published for host dispatch
├── scripts/
│   ├── sync-shared                # propagates shared/ into the skills that read it
│   ├── check-health
│   └── sync-to-codex
├── hooks/                         # Optional SessionStart hook
├── docs/
│   ├── foundation.md              # Full design (PRD + TDD + architecture intent)
│   ├── workflow-and-catalog.md    # Scannable skill + agent reference
│   ├── plans/                     # active/, completed/, tech-debt-tracker.md
│   └── integrations/              # Anthropic + Codex code-review action setup
├── tests/                         # 70 test files
├── setup                          # Bash install script
└── package.json
```

## Editing shared material

Anything two or more skills read lives once in `shared/` and is copied into each
consumer. There are 399 such copies. **Never edit a copy under `skills/`.** Edit
the file in `shared/`, then propagate:

```bash
scripts/sync-shared
```

One edit to `shared/references/host-detect.md` updates all 17 copies.

`scripts/sync-shared --check` verifies without writing. It fails when a
generated copy has drifted, when a skill names a relative path with no file
behind it, and when the manifest grants a file to a skill that never reads it.
That check runs in CI and in `./setup`, which refuses to install a tree whose
copies are stale rather than shipping a mixture of old and new.

If you edit a copy by mistake, the check tells you where to go instead:

```
✗ drift: skills/en-plan/references/severity.md differs from shared/references/severity.md
✗        do not edit the generated copy — change shared/references/severity.md, then run scripts/sync-shared
```

Adding a consumer is one line in `shared/manifest.json` plus a sync. Full
details in [`shared/README.md`](./shared/README.md).

---

## Configuration

Per-project config lives in `.ensemble/config.local.yaml` (gitignored). All keys are optional. Highlights:

```yaml
# Cross-review behavior
peer_mode_override: auto                # auto | cross-agent-only | single-agent-only | off
skip_peer_below_lines: 50

# Review confidence gate (sub-threshold → TD entries)
review:
  confidence_threshold: 7

# Telemetry harness — /en-debug log source + structured-logging lint
observability:
  log_source: file
  log_path: ./logs/app.jsonl
  structured_logging_required: true

# Architecture fitness — project provides bin/check-fitness
fitness:
  enabled: true

# Sweep continuous monitoring
sweep:
  continuous_monitoring:
    dead_code: true
    dep_audit: true
  auto_plan_threshold_loc: 50
  auto_plan_threshold_locations: 2
  max_drafts_per_run: 3
```

Full schema in [`shared/references/templates/config-local-example.yaml`](./shared/references/templates/config-local-example.yaml).

---

## Documentation

- **[Foundation](./docs/foundation.md)** — full design (PRD + TDD + architecture intent). Decisions, rationale, open questions.
- **[Workflow + Catalog](./docs/workflow-and-catalog.md)** — scannable reference for every skill and agent.
- **[Anthropic Code Review setup](./docs/integrations/anthropic-code-review-action.md)** — install Claude on your PRs.
- **[Codex Code Review setup](./docs/integrations/codex-code-review-action.md)** — install Codex on your PRs (managed or self-hosted).
- **[CHANGELOG](./CHANGELOG.md)** — what landed in each release.

## Tests

```bash
./tests/run.sh
```

13 test files, 268 assertions. CI runs the suite via `.github/workflows/ensemble-tests.yml`.

## Status

**Phases 0–6 complete.** Foundation document, all 14 skills, 11 agents, all cross-cutting references, plugin manifests, install script, CI tooling, and integration guides are in place.

## License

[MIT](./LICENSE)
