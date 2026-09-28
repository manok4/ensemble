# Ensemble

> An engineering harness for **Claude Code** and **Codex** with cross-agent peer review, structured plans, a compounding learnings wiki, and event-driven doc-drift cleanup.

Ensemble is a toolkit of skills and agents that turns rough ideas into shipped, peer-reviewed code and keeps the project's documentation honest as it goes. Every skill detects whether it's running under Claude Code or Codex and adapts tool names, peer-review CLI invocations, and platform-specific behaviors automatically.

## What problem this solves

Solo and small-team development with AI agents tends to accumulate three kinds of debt that compound silently:

1. **Documentation drift** — the code outpaces the docs; future contributors (human or agent) work from stale context.
2. **Lost lessons** — bug fixes and design decisions vanish into git history; the next agent re-discovers them at full cost.
3. **Single-perspective work** — one agent's blind spot becomes the codebase's blind spot.

Ensemble fixes each by design:

- **Document-as-source-of-truth** — every phase produces a durable artifact in `docs/`; the next phase reads it. The repo *is* the system of record.
- **Compounding wiki** — `/en-learn` captures what the code cannot say (terms in `docs/CONTEXT.md`, decisions in `docs/decisions/`, solved problems in `docs/learnings/`), writes nothing that fails its gate, and planning reads it back.
- **Cross-agent peer review** — Claude Code and Codex review each other's work via subprocess CLI calls. Single-agent fallback when only one CLI is installed.
- **Always-on safety** — `/en-guardrail` prompts before destructive Bash commands; `/en-sweep` cleans up doc drift on a schedule from a dedicated machine.

## Five design pillars

1. **Document-as-source-of-truth.** Foundation, architecture, plans, learnings — all live in `docs/`. Anything not in the repo is illegible to the agent.
2. **Map, not encyclopedia.** `AGENTS.md` and `CLAUDE.md` are pointer indexes (~100 lines each); each SKILL.md stays under a 24KB budget, with templates and rarely-needed steps in the skill's own `references/`.
3. **Cross-agent peer review.** `claude -p ↔ codex exec`. Outside Voice catches blind spots a single agent misses.
4. **Compounding knowledge.** Every solved problem and decision gets captured. Future runs query the wiki automatically.
5. **Lean by design.** Skills are small. Agents are short specialist prompts. The scaffolding earns its keep.

---

## Workflow

The lifecycle pipeline, with the orthogonal skills below it:

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
                                       │  /en-build   │  Per unit: implement → test → commit; then one
                                       │              │  simplify pass + cross-agent review of the branch
                                       └──────┬───────┘
                                              │
                                              ▼
                                       ┌──────────────┐
                                       │  /en-review  │  Cross-agent peer on by default; personas
                                       │              │  with --cross; sub-threshold → TD entries
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
                                       │  /en-learn   │  capture / refresh / lint / migrate. Gated:
                                       │              │  writes only what reading cannot recover
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
                                       │   /en-sweep  │  Scheduled doc-drift cleanup; doc-only
                                       │              │  PRs the runner merges + continuous
                                       │              │  monitoring (dead-code, dep-vuln)
                                       └──────────────┘

   Orthogonal skills, available at any point in the flow:

         ┌────────────────┐  ┌────────────────┐  ┌────────────────┐
         │   /en-debug    │  │  /en-guardrail │  │  /en-simplify  │
         │  Trace-driven  │  │  Always-on     │  │  Behaviour-    │
         │  hypothesis;   │  │  PreToolUse    │  │  preserving    │
         │  read-only     │  │  hook on Bash  │  │  cleanup       │
         └────────────────┘  └────────────────┘  └────────────────┘
         ┌────────────────┐  ┌────────────────┐  ┌────────────────┐
         │    /en-flow    │  │    /en-loop    │  │ /en-test-audit │
         │  plan → build  │  │  Bounded auto  │  │  Prune a test  │
         │  → learn →     │  │  loop, one     │  │  suite with a  │
         │  ship, chained │  │  slice a turn  │  │  proven ledger │
         └────────────────┘  └────────────────┘  └────────────────┘

   Ad-hoc peer review of any artifact is `/en-review --peer <path|ref|branch>`.
```

## Quick start

A typical cycle:

```text
/en-plan "Add SSO via Okta"
/en-build docs/plans/active/EN03-feature_sso-okta.md
# Builds unit by unit, then runs /en-simplify and a cross-agent /en-review over
# the branch, and asks once at the end whether to capture a learning.
/en-qa
/en-ship --auto-merge
# PR opens. Reviewers (humans + Anthropic action + optional Codex) leave comments.
/en-resolve-pr
# All comments addressed; auto-merge flips green; merge.
# /en-sweep runs on a schedule from a dedicated machine to clean doc drift.
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

`/en-setup` runs a 16-step retrofit flow:

1. Detect sub-variant (which of `AGENTS.md` / `CLAUDE.md` exist).
2. **Existing-plans archival** — if you already have plans in some other format, offers to move them to `docs/plans/legacy/` so Ensemble's lint/build flows ignore them. Migrate them later via `/en-plan --from-legacy`.
3. Scaffold the project: `docs/` skeleton, seeded indexes and logs, `bin/ensemble-lint`, `.gitignore` entries, `.ensemble/config.local.example.yaml`.
4. Seed `docs/CONTEXT.md` with the project's core domain terms.
5. Generate or merge `AGENTS.md` (preserving any existing content).
6. Generate or merge `CLAUDE.md`.
7. Stage what the scaffold wrote.
8. Record the sweep cadence and print the sweep machine's install commands (the sweep runs there, not in CI).
9. Create `.ensemble/config.local.yaml` with likely defaults, when asked.
10. **Guardrail check** — offer to install `/en-guardrail` (project-scoped or global).
11. **Claude Code Review action check** — offer to install Anthropic's PR-review action.
12. **Auto-merge repo-setting check** — surface if `allow_auto_merge` is off at the repo level.
13. **`REVIEW.md` offer** — seed review guidance tuned for Ensemble's severity scale.
14. **Verification-receipt notice** — informational; writes nothing.
15. **Final verification** — confirm every required artifact is present.
16. Recommend next steps.

After `/en-setup`, the typical retrofit path is:

```text
/en-foundation --retrofit
# Reads the codebase, asks targeted Q&A, fills foundation.md + architecture.md
# from observed reality.

# Then jump into normal flow: /en-plan for the next feature.
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

18 skills total: 9 lifecycle, 9 orthogonal. All prefixed `en-`. Numbering follows
[§5.1 of the foundation](./docs/foundation.md#51-skill-summary).

### Lifecycle skills (9)

| # | Skill | Purpose |
|---|---|---|
| 1 | `/en-brainstorm` | Explore an idea through Q&A and 2–3 approaches with trade-offs, a recommendation and a devil's-advocate pass. Writes a design doc to `docs/designs/`. |
| 2 | `/en-foundation` | Produce or retrofit `docs/foundation.md` (PRD, technical direction, architecture), `docs/architecture.md`, `AGENTS.md` and `CLAUDE.md`. Asks for `plan_id_prefix`; the draft is peer-reviewed. |
| 3 | `/en-plan` | Turn a feature, refactor or bug fix into a plan with stable U-IDs and a `plan_type`: reads the foundation, runs research agents, breaks the work into units with files, tests and risk, then a cross-agent peer review. `--resume` and `--from-legacy` modes. |
| 4 | `/en-build` | Execute a plan unit by unit on a feature branch (implement, test, lint, commit per unit), then one `/en-simplify` pass and one cross-agent review over the branch diff, an evidence audit, and the learning checkpoint. |
| 5 | `/en-review` | Code review of the current branch with a cross-agent peer on by default. `--cross` adds host personas (correctness, testing, maintainability, standards always; security, performance, migrations when the diff matches); findings below the confidence threshold file as TD entries. |
| 6 | `/en-qa` | Test the work like a real user: lint, typecheck, tests, then Playwright end-to-end on the golden path and edge cases. Each bug gets a fix, a regression test and a commit. |
| 7 | `/en-learn` | Capture durable learnings as a term, a decision or a solution. Gated: writes nothing unless the entry is unrecoverable from the code and changes a future decision. Also `--refresh`, `--lint`, `--migrate` and `--enforce-audit`. |
| 8 | `/en-ship` | Preflight (lint, typecheck, targeted tests, secret scan, merge check), conventional commit, push and `gh pr create`. `--auto-merge` optional. |
| 9 | `/en-resolve-pr` | Address review comments on the current PR with a six-verdict rubric per comment, then fix, reply and resolve. Needs-human items are surfaced, never guessed. |

### Orthogonal skills (9)

| # | Skill | Purpose |
|---|---|---|
| 10 | `/en-debug` | Debug from telemetry: read structured logs, correlate by trace or request id, return a hypothesis with `file:line` and confidence. Read-only in telemetry mode; code mode fixes only on request. |
| 11 | `/en-sweep` | Scheduled doc-drift cleanup run by launchd on a dedicated machine through Codex: file-shape lint, wiki-graph health, architecture and plan-lifecycle drift, then doc-only PRs the runner merges once checks pass. Manual-invoke only. |
| 12 | `/en-guardrail` | Always-on `PreToolUse` hooks that force a permission prompt before destructive Bash commands and DB-writing MCP calls (recursive `rm`, `DROP TABLE`, force-push, `terraform destroy`). Per-command bypass via `ENSEMBLE_GUARDRAIL=off`. |
| 13 | `/en-setup` | Bootstrap and diagnostics for a project: detects its state, creates the docs skeleton, generates `AGENTS.md` and `CLAUDE.md`, offers optional integrations and health checks. Manual-invoke only. |
| 14 | `/en-loop` | A bounded autonomous loop until an evidence-based stop condition: one committed, test-gated slice per iteration, cross-agent review at checkpoints. Wraps the `gnhf` CLI. Manual-invoke only; never auto-merges. |
| 15 | `/en-flow` | The hands-off pipeline for one piece of work: `/en-plan`, `/en-build`, `/en-learn`, then `/en-ship` with its watch loop. Manual-invoke only. |
| 16 | `/en-simplify` | Simplify recently changed code for clarity, reuse and efficiency while preserving exact behaviour; the default scope is the branch diff. `/en-build` runs it once per build. |
| 17 | `/en-test-audit` | Prune an existing test suite one owner-boundary batch at a time: evidence for every deletion in a committed ledger, a caught mutation proving each kept test still fails, and a peer check for lost coverage. `--campaign <path>` covers one subsystem. Manual-invoke only; never pushes or merges. |
| 18 | `/en-fix` | Take one small bug fix or improvement from request to PR without a plan: `/en-debug` diagnoses a bug first, then a test-first change, `/en-review --lite` and `/en-ship`. Stops and suggests `/en-plan` when the change touches a risk surface or fails review twice. Manual-invoke only. |

For full process detail, flags and reference files, see each skill's `SKILL.md`
under [`skills/`](./skills/), which is the contract the skill executes, and
[§5 Skill Catalog](./docs/foundation.md#5-skill-catalog) in the foundation.

---

## Agent catalog

6 agent definitions. Skills orchestrate; agents specialize. **No agent invokes
another agent.** Each skill carries its own copy of the agents it dispatches, in
its `agents/` directory.

| Agent | Role | Dispatched by |
|---|---|---|
| `dimension-reviewer` | Reviews a diff along one named dimension (correctness, testing, maintainability, standards, security, performance, migrations); the dimension, focus and scope arrive in the prompt. Read-only; replaced seven per-dimension reviewer agents. | `/en-review` (`--cross`, `--host`) |
| `repo-research` | Scans the codebase for patterns, conventions, file paths and prior art. Read-only. | `/en-plan`, `/en-foundation`, `/en-sweep`, `/en-debug` |
| `learnings-research` | Queries the knowledge store (`docs/learnings/`, decisions, terms) for entries relevant to a task, with citations. Read-only. | `/en-plan`, `/en-review`, `/en-learn` |
| `web-research` | External docs (Context7) and best-practice search, with URL fetch when a source is named. Read-only. | `/en-plan`, `/en-brainstorm` |
| `repo-fact-lookup` | Answers specific questions about what the repo contains, and verifies absence claims, by quoting it. Retrieval only. | `/en-brainstorm` |
| `code-simplifier` | Reviews a diff along one simplification dimension (reuse, quality or efficiency) and returns findings with the proposed edit. Read-only; the dispatching skill applies what it accepts. | `/en-simplify` |

For agent invariants, see [§6 Agent Catalog](./docs/foundation.md#6-agent-catalog).

---

## Repository layout

Every skill directory is **self-contained**: it holds its own copy of every
reference, template, script and agent it reads, and declares them in its own
frontmatter. Nothing inside a skill resolves a path above itself, and there is no
shared tree to keep in sync.

```
ensemble/
├── .claude-plugin/                # Claude Code plugin manifest
├── .codex-plugin/                 # Codex plugin manifest
├── skills/                        # 17 skills (en-*)
│   └── en-plan/                   # every skill has the same shape:
│       ├── SKILL.md               #   its flow; what it names is what it carries
│       ├── CONTRACT.md            #   what other skills may rely on (callable skills only)
│       ├── references/            #   its own references, briefs and templates
│       ├── agents/                #   its own copies of the agents it dispatches
│       └── scripts/               #   its own copies of the scripts it runs
├── scripts/                       # repo tooling only — check-health, sync-to-codex
├── hooks/                         # Optional SessionStart hook
├── docs/
│   ├── foundation.md              # Full design (PRD + TDD + architecture intent)
│   ├── plans/                     # active/, completed/, tech-debt-tracker.md
│   └── integrations/              # Anthropic + Codex code-review action setup
├── tests/
├── setup                          # Bash install script
└── package.json
```

## Working on a skill

**Edit the file where it lives.** A skill owns everything under its directory, so
a change to `skills/en-plan/references/peer-brief.md` affects en-plan and nothing
else. There is no propagation step.

Two skills sometimes need the same file, and then the copies are genuinely
duplicated. That is the trade this layout makes: a folder that works wherever it
lands, at the cost of editing a file more than once when it is truly shared. In
practice almost nothing is — after the EN13 prune, most references have exactly
one consumer.

### Adding a file to a skill

Put it in the skill, then name it from the flow that uses it, in backticks:

```markdown
Read `references/my-new-reference.md` before classifying.
```

There is no manifest. `tests/lint/skill-payload.test.sh` derives each skill's
payload from its own body and fails if a skill carries a file nothing reaches,
or names a path that does not resolve inside it.

A path counts when it is **backticked, a markdown link, or inside a fence**.
Bare prose does not, and that is the whole distinction: an earlier scheme
counted every mention and inflated the tree to 422 files where 193 were needed,
because one sentence contrasting a skill's linter against a *different* tool
read as a dependency on it. The manifest that replaced the walker then drifted
the other way — it could say a file was listed, but never that anything read it,
so it carried a reference that called itself the source of truth for CLI flags
while nothing consulted it. Deriving from the body answers both questions from
the one place that cannot go stale.

### The one thing that must stay identical

`references/peer-contract.md` is the wire format for peer review: severity,
confidence, the autofix classes, and the `peer_decision` object. A peer emits P1
and a host parses P1, so every copy must agree exactly.
`tests/parity/peer-contract-parity.test.sh` enforces that, and also enforces the
opposite where the opposite is right — each skill's `peer-brief.md` is meant to
differ, and pinning those would be a bug.

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

Full schema in [`skills/en-setup/references/templates/config-local-example.yaml`](./skills/en-setup/references/templates/config-local-example.yaml).

---

## Documentation

- **[Foundation](./docs/foundation.md)** — full design (PRD + TDD + architecture intent). Decisions, rationale, open questions.
- **[Anthropic Code Review setup](./docs/integrations/anthropic-code-review-action.md)** — install Claude on your PRs.
- **[Codex Code Review setup](./docs/integrations/codex-code-review-action.md)** — install Codex on your PRs (managed or self-hosted).
- **[CHANGELOG](./CHANGELOG.md)** — what landed in each release.

## Tests

```bash
./tests/run.sh
```

It runs every `*.test.sh` under `tests/`. While iterating, `./tests/select-for.sh <changed paths>` runs the subset a change can break; run the full suite before committing. CI runs it via `.github/workflows/ensemble-tests.yml`.

## Status

Every skill and agent in the catalogs above ships, with the foundation document, plugin manifests, install script, CI tooling and integration guides. Work in flight is in `docs/plans/active/`, which is empty between features and so is not linked; shipped plans are in [`docs/plans/completed/`](./docs/plans/completed/).

## License

[MIT](./LICENSE)
