---
project: Ensemble
type: reference
status: current
created: 2026-04-30
updated: 2026-04-30
---

# Ensemble — Workflow + Skill & Agent Catalog

A scannable reference for the workflow, every skill, and every agent built into Ensemble. For the full design rationale and decision log, see [`foundation.md`](./foundation.md).

---

## Table of contents

- [The workflow](#the-workflow)
- [Cross-cutting properties](#cross-cutting-properties)
- [Skills (11 total)](#skills-11-total)
  - [1. `/en-setup`](#1-en-setup--project-bootstrap-and-diagnostics)
  - [2. `/en-brainstorm`](#2-en-brainstorm--exploration-and-design-doc)
  - [3. `/en-foundation`](#3-en-foundation--prd--tech-direction--architecture-seed)
  - [4. `/en-plan`](#4-en-plan--featurerefactor-plan-with-stable-u-ids)
  - [5. `/en-build`](#5-en-build--execute-a-plan-unit-by-unit)
  - [6. `/en-review`](#6-en-review--multi-persona-code-review)
  - [7. `/en-qa`](#7-en-qa--system-checks--browser-end-to-end)
  - [8. `/en-learn`](#8-en-learn--compounding-wiki-maintainer)
  - [9. `/en-ship`](#9-en-ship--commit-push-and-pr)
  - [10. `/en-cross-review`](#10-en-cross-review--ad-hoc-peer-review)
  - [11. `/en-garden`](#11-en-garden--event-driven-doc-drift-cleanup)
- [Agents (11 total)](#agents-11-total)
  - [Always-on reviewers (4)](#always-on-reviewers-4--read-only-return-findings-json)
  - [Conditional reviewers (3)](#conditional-reviewers-3--fire-when-the-diff-matches)
  - [Research agents (3)](#research-agents-3--read-only-return-data)
  - [Refiner (1)](#refiner-1--modifies-code-wrapped-in-two-verification-gates)
- [Agent invariants](#agent-invariants-64)
- [Dispatch matrix](#at-a-glance--dispatch-matrix)

---

## The workflow

The eight-skill lifecycle pipeline plus three orthogonal skills:

```text
                                ┌──────────────┐
                                │  /en-setup   │  Project bootstrap (one-time per repo)
                                │ (state 1/2/3)│  Detects greenfield, retrofit, or already-set-up
                                └──────┬───────┘
                                       │
                       ┌───────────────┴───────────────┐
                       ▼                               ▼
                ┌──────────────┐                ┌──────────────┐
                │/en-brainstorm│                │/en-foundation│  PRD + tech direction + initial architecture
                │  (optional)  │ ─────────────▶ │              │  Outside Voice peer review on draft
                └──────────────┘                └──────┬───────┘
                                                       │
                                                       ▼
                                                ┌──────────────┐
                                                │  /en-plan    │  FRXX plan with stable U-IDs
                                                │              │  Outside Voice peer review on draft
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
                                                │  /en-review  │  Multi-persona (4 always + 3 conditional)
                                                │              │  Modes: interactive | headless | report-only
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
                                                │  /en-learn   │  capture / ingest / refresh / pack / lint
                                                │              │  Auto-syncs architecture.md; moves plan to completed/
                                                └──────┬───────┘
                                                       │
                                                       ▼
                                                ┌──────────────┐
                                                │   /en-ship   │  Pre-flight + secret scan + conventional commit
                                                │              │  + push + gh pr create
                                                └──────┬───────┘
                                                       │
                                                       │  PR merge to main
                                                       ▼
                                                ┌──────────────┐
                                                │  /en-garden  │  Event-driven; doc-only PRs that auto-merge
                                                │   (CI-only)  │  after en-review (mode:report-only) clears
                                                └──────────────┘

   Orthogonal skill, available at any point in the flow:

                                                ┌──────────────┐
                                                │/en-cross-rev │  Ad-hoc Outside Voice peer review of any artifact
                                                │              │  --focus security|performance|tests|all
                                                └──────────────┘
```

---

## Cross-cutting properties

Every skill that runs cross-review enforces these:

- **D30: Peer reports, host applies.** The peer agent only returns structured JSON findings; the host (skill-running agent) is the sole code modifier.
- **D31: Single-agent fallback.** If only one CLI is installed, peer is a fresh subprocess of the host's own CLI (same model, fresh context). The `peer_mode` field tracks which mode you're in.
- **D23: Cross-agent peer is the *other* agent.** Resolved by host-detect on every invocation. Claude Code → Codex; Codex → Claude.
- **Recursion guard** via `ENSEMBLE_PEER_REVIEW=true` env var — prevents peer subprocesses from spawning more peer subprocesses.

---

## Skills (11 total)

### 1. `/en-setup` — project bootstrap and diagnostics

| | |
|---|---|
| **Purpose** | Per-repo bootstrap. Distinct from the global `./setup` (machine install). |
| **States** | **State 1** (greenfield: empty + no foundation) → recommend `/en-brainstorm` then `/en-foundation`; don't pre-create artifacts. **State 2** (existing project, no Ensemble) → create `docs/` skeleton, generate or append-merge `AGENTS.md`/`CLAUDE.md`, install GH Action workflow, `.ensemble/` config. **State 3** (already integrated) → diagnostic mode via `scripts/check-health`. |
| **State 2 sub-variants** | **2a** (no maps) — generate both. **2b** (CLAUDE.md only) — generate AGENTS.md, append-merge CLAUDE.md. **2c** (AGENTS.md only) — append-merge AGENTS.md, generate CLAUDE.md. **2d** (both maps) — append-merge each; never overwrite user content. |
| **Cross-review** | Off — mechanical setup. |

### 2. `/en-brainstorm` — exploration and design doc

| | |
|---|---|
| **Purpose** | Q&A → research → 2-3 approaches with trade-offs → recommendation → devil's-advocate stress test → design doc. |
| **Output** | `docs/designs/YYYY-MM-DD-<topic>-design.md` |
| **Depth scaling** | Lightweight (2-4 questions, 2 approaches) / Standard (5-8, 2-3) / Deep (9-14, 3 with thorough trade-offs) |
| **Cross-review** | Off (exploratory; outside critique here is premature) |
| **Capture-from-synthesis** | Soft prompt at end: "This produced [X]. Capture as a learning?" → `/en-learn capture --from-conversation` |

### 3. `/en-foundation` — PRD + tech direction + architecture seed

| | |
|---|---|
| **Purpose** | Combined product requirements + technical direction + initial architecture intent. Run once per project. |
| **Output** | `docs/foundation.md` (with stable R-IDs / A-IDs / F-IDs / AE-IDs / D-IDs / Q-IDs), `docs/architecture.md` (status: seed), `AGENTS.md`, `CLAUDE.md`, plus `FR01-project-setup` plan for greenfield only |
| **Modes** | Fresh (new product) and `--retrofit` (use `repo-research` to back-fill from existing code) |
| **Cross-review** | On by default; `--no-peer` to disable |
| **Discovery** | Walks 11 topic groups (identity, goals, users, requirements, UX, stack, data, architecture, API, deploy, security/risks); depth-scaled question count |

### 4. `/en-plan` — feature/refactor plan with stable U-IDs

| | |
|---|---|
| **Purpose** | Concrete implementation plan with per-unit Goal / Files / Approach / Execution note / Test scenarios / Verification |
| **Output** | `docs/plans/active/FR<NN>-<slug>.md` (auto-incremented FRXX) |
| **U-ID stability** | Never renumbered after assignment; splitting keeps original ID on original concept |
| **Research** | Phase 1 parallel dispatch: `repo-research` + `learnings-research`; `web-research` conditional |
| **Cross-review** | On by default; auto-skipped if `< skip_peer_below_lines` (default 50) or Lightweight depth |
| **State-2 fallback** | Plans before foundation retrofit carry `requirements_pending: true` and `covers_requirements: []`; lint emits P3 advisory until foundation has R-IDs |

### 5. `/en-build` — execute a plan unit-by-unit

| | |
|---|---|
| **Purpose** | Implement a plan with cross-agent peer review at every per-unit gate |
| **Two flavors** | **Build-by-orchestration** (host=Claude → dispatch Codex as WORKER); **Build-handoff** (host=Codex → implement natively, dispatch Claude as PEER-REVIEWER) |
| **Per-unit pipeline** | Implement → Gate 1 (tests + lint) → `code-simplifier` → Gate 2 (revert simplifier on failure) → Outside Voice peer review → host applies findings (apply / defer to TD-tracker / disagree) → re-verify → commit |
| **Batch sizing** | Dynamic per feature: tightly-coupled units batch together; auth/payments/migrations batch alone |
| **Cross-review** | On per-unit; `--no-peer-per-unit` disables |
| **Auto-invokes `/en-learn`** | Soft prompt at end of build |

### 6. `/en-review` — multi-persona code review

| | |
|---|---|
| **Purpose** | Multi-persona, confidence-gated review of the current branch |
| **Modes** | **interactive** (default for direct user invocation; auto-applies `safe_auto`, surfaces others) / **headless** (skill-to-skill; auto-applies silently, returns JSON) / **report-only** (mandatory for CI/garden; strictly read-only) |
| **Always-on personas** | correctness, testing, maintainability, standards (+ learnings-research) |
| **Conditional personas** | security, performance, migrations (fire when diff content matches) |
| **Synthesis** | Parallel dispatch → dedup by location + title-similarity → boost confidence on overlap → severity reorder → unified envelope |
| **Optional `--peer`** | Cross-agent Outside Voice on top of personas |

### 7. `/en-qa` — system checks + browser end-to-end

| | |
|---|---|
| **Purpose** | Test the work like a real user |
| **Phase 1 (system)** | Lint + typecheck + test suite. Stop on failure. |
| **Phase 2 (browser)** | Playwright MCP. Walks each F-ID flow with edge cases (empty state, error state, slow network, double-click, navigate-mid-action, keyboard-only, mobile viewport) |
| **Bug protocol** | Reproduce → root cause → fix → regression test → atomic commit `fix(qa): ...` → re-verify |
| **Cross-review** | Off — bug fixes are mechanical |
| **Auto-invokes `/en-learn`** | After QA wraps, soft-prompt to capture each fixed bug |

### 8. `/en-learn` — compounding wiki maintainer

| | |
|---|---|
| **Purpose** | Maintain `docs/learnings/` as a compounding interlinked wiki (Karpathy's LLM Wiki pattern) |
| **5 modes** | **capture** (default; post-ship/post-fix or `--from-conversation`) / **ingest \<path-or-url\>** (proactive; URLs use Wayback fallback) / **--refresh** (content staleness audit) / **--pack \<library\>** (flatten library docs to `docs/references/<lib>-llms.txt`) / **--lint** (graph health: orphans, missing back-refs, broken links, contradictions, missing pages) |
| **Always-on side effects** | Walk `related: []` and add reciprocal back-refs; append to `index.md`; append one line to `log.md` |
| **Architecture sync** | After material structural change, surgical edit to `docs/architecture.md` (per `references/architecture-update-rules.md`); flips `status: seed` → `active` on first material update |
| **Plan lifecycle** | Moves plan from `active/` to `completed/`; sets `shipped:` field |

### 9. `/en-ship` — commit, push, and PR

| | |
|---|---|
| **Purpose** | Get clean changes onto the remote with a meaningful commit and PR |
| **Pre-flight** | Lint + typecheck + targeted tests on changed files; merge-conflict check; default-branch protection |
| **Secret scan** | High-confidence regexes (AWS keys, GH PATs, OpenAI/Anthropic keys, private keys) + file-name red flags (.env, *.pem, credentials.json) |
| **Commit** | Conventional Commits format; HEREDOC for body to preserve formatting |
| **PR** | `gh pr create` with auto-generated body (Summary + Test plan + plan reference) |
| **Auto-merge** | Off by default; `--auto-merge` opts in |
| **Cross-review** | Off — by this point review and QA have passed |

### 10. `/en-cross-review` — ad-hoc peer review

| | |
|---|---|
| **Purpose** | Ad-hoc Outside Voice peer review of any artifact (file, diff, branch, current uncommitted work) |
| **Resolves target** | No arg → current diff; `<path>` → file; `<git-ref>` → diff between refs; `<branch>` → diff vs default |
| **`--focus` flag** | `security` / `performance` / `tests` / `correctness` / `maintainability` / `all` (default) |
| **Cross-review** | This skill **is** the cross-review |
| **D30 violation detection** | Git stash before/after subprocess; revert any peer-introduced changes; do not trust findings |

### 11. `/en-garden` — event-driven doc-drift cleanup

| | |
|---|---|
| **Purpose** | Doc-drift cleanup automatically after every PR merge to `main` |
| **Trigger** | `push` to `main` (NOT scheduled). Manual `/en-garden` also supported |
| **Strict scope** | **Doc-only.** Never modifies source code, config, or tests. Code-level findings file to `docs/plans/tech-debt-tracker.md` |
| **Checks** | File-shape lints + wiki-graph lints + architecture drift + plan-lifecycle drift + pointer-map drift + tech-debt hygiene |
| **PR batching** | One PR per category; up to `max_prs_per_run` (default 6); branch `en-garden/<source-merge-sha>/<batch-name>` |
| **Auto-merge** | After `/en-review` (in `mode:report-only`) returns no P0/P1 |
| **Loop guards (5)** | Skip garden-authored commits / concurrency group / garden-PR label match / no-material-diff termination / recursion depth cap |
| **Security model** | `GITHUB_TOKEN` least-privilege; no PAT; no fork triggers; branch protection respected; fail-closed on detection error |

---

## Agents (11 total)

### Always-on reviewers (4) — read-only, return findings JSON

| Agent | Focus | Dispatched by |
|---|---|---|
| **`correctness-reviewer`** | Logic errors, edge cases, state bugs, error propagation, off-by-one, broken invariants, concurrency | `en-review`, `en-build` (per-unit) |
| **`testing-reviewer`** | Coverage gaps, weak assertions, brittle tests, missing categories, missing regression test for bug fixes | `en-review`, `en-build` (per-unit) |
| **`maintainability-reviewer`** | Coupling, complexity, naming, dead code, abstraction debt, layer violations, long functions; honors "three similar lines is better than premature abstraction" | `en-review` |
| **`standards-reviewer`** | CLAUDE.md/AGENTS.md compliance, file naming, conventional commits, frontmatter validity, stable IDs, repo-relative paths, status correctness | `en-review` |

### Conditional reviewers (3) — fire when the diff matches

| Agent | Fires when diff touches | Dispatched by |
|---|---|---|
| **`security-reviewer`** | Auth, public endpoints, user input, secret handling, permissions, CORS/CSP, cookie config, OAuth flows. Severity: P0 = exploitable in production; P1 = likely exploitable | `en-review` |
| **`performance-reviewer`** | DB queries (N+1, unbounded, unindexed), hot paths, async/concurrency pitfalls, caching, memory, render performance. Estimates magnitude where possible | `en-review` |
| **`migrations-reviewer`** | Schema migration files, backfills, data isolation, multi-tenancy boundaries, locking + downtime risk, backwards-compat. Suggests staged rollouts | `en-review` |

### Research agents (3) — read-only, return data

| Agent | Purpose | Dispatched by |
|---|---|---|
| **`repo-research`** | Scan codebase for patterns, conventions, file paths, prior art. Returns `patterns[]`, `conventions[]`, `prior_art[]`, `structure{}`. Token budget tiered by depth (5K-25K) | `en-plan`, `en-foundation` (esp. `--retrofit`), `en-garden` (architecture drift), `en-learn` (architecture sync) |
| **`learnings-research`** | Query `docs/learnings/` for relevant past entries via `index.md` first (Karpathy's index-first pattern). Returns top 5-10 matches with relevance scores; full-reads only strong matches to bound token cost | `en-plan`, `en-review`, `en-brainstorm`, `en-foundation` |
| **`web-research`** | External docs (Context7) and best-practice search (WebSearch); URL fetch with Wayback fallback. Returns `findings[]` with quote-supported claims, `conflicts[]`, `open_questions[]`. Cost-conscious — fires conditionally | `en-plan` (conditional), `en-brainstorm` (on-request), `en-learn --pack` and `ingest <url>` (always) |

### Refiner (1) — modifies code; wrapped in two verification gates

| Agent | Purpose | Dispatched by | Source |
|---|---|---|---|
| **`code-simplifier`** | Refines recently modified code for clarity, consistency, project-standards compliance while preserving exact functionality. Returns `summary` + `changes_made[]`. Avoids over-simplification (no nested ternaries, no clever-at-cost-of-readable). The only file-modifying agent. **Verification contract:** orchestrating skill (`en-build`) runs Gate 1 before invoking, Gate 2 after; on Gate 2 failure, `git restore` reverts the simplifier's changes and the original implementation proceeds | `en-build` per unit, between Gate 1 and peer review | Anthropic [`claude-plugins-official`](https://github.com/anthropics/claude-plugins-official) |

---

## Agent invariants (§6.4)

- **Reviewer and research agents are read-only.** They never edit files; they return structured JSON. The orchestrating skill applies any fixes.
- **Refiner agents may write files**, but the orchestrating skill must run verification (project tests + lint) immediately after; on failure, revert via `git restore`. This safety contract is what lets us trust a code-modifying agent.
- **Confidence ≥ 7 surfaces in main report; 5–6 surfaces with caveat; <5 suppressed unless severity = P0.**
- **No agent invokes another agent.** Skills orchestrate; agents specialize.

---

## At a glance — dispatch matrix

| Skill | Agents it may dispatch |
|---|---|
| `en-brainstorm` | `web-research` (optional), `learnings-research` (optional) |
| `en-foundation` | `repo-research`, `learnings-research`, `web-research` (optional) |
| `en-plan` | `repo-research`, `learnings-research`, `web-research` (conditional) |
| `en-build` | `code-simplifier` (per unit, before peer review) |
| `en-review` | 4 always-on reviewers + 3 conditional reviewers + `learnings-research` |
| `en-qa` | None — uses Playwright MCP directly |
| `en-learn` | `repo-research` (architecture sync), `web-research` (`--pack` and `ingest <url>`) |
| `en-ship` | None — uses git + gh directly |
| `en-cross-review` | None — pure subprocess wrapper |
| `en-garden` | `repo-research` + invokes `en-review` per batch PR |
| `en-setup` | None — mechanical setup |

---

## Where to learn more

- [`foundation.md`](./foundation.md) — full design (1,922 lines) with the rationale, decisions D1–D31, open-question resolutions, risks, and operating philosophy.
- [`../README.md`](../README.md) — install paths and quick start.
- [`../tests/README.md`](../tests/README.md) — hermetic test suite (119 assertions across 7 categories).
- Each skill's `SKILL.md` under [`../skills/`](../skills/).
- Each agent's prompt under [`../agents/`](../agents/).
- Cross-cutting references under [`../references/`](../references/) — process logic externalized so SKILL.md files stay lean.
