---
project: Ensemble
type: foundation
status: draft
created: 2026-04-28
updated: 2026-04-28
owner: Mano Kulasingam
depth: deep
---

# Ensemble — Foundation

> A cohesive set of product-development skills and specialist agents that work across Claude Code and Codex, with cross-agent peer review and a compounding learning store. This document combines product requirements, technical design, and architecture into a single living foundation.

---

## Table of Contents

- [1. Executive Summary](#1-executive-summary)
- [2. Goals and Non-Goals](#2-goals-and-non-goals)
- [3. User and Use Cases](#3-user-and-use-cases)
- [4. Product Decisions](#4-product-decisions)
- [5. Skill Catalog](#5-skill-catalog)
- [6. Agent Catalog](#6-agent-catalog)
- [7. Cross-Agent Peer Review](#7-cross-agent-peer-review)
- [8. Cross-Host Portability](#8-cross-host-portability)
- [9. Architecture](#9-architecture)
- [10. Artifact Directory and Stable IDs](#10-artifact-directory-and-stable-ids)
- [11. Compounding Learning Store](#11-compounding-learning-store)
- [12. Token-Efficiency Principles](#12-token-efficiency-principles)
- [13. Tech Stack and Dependencies](#13-tech-stack-and-dependencies)
- [14. Implementation Roadmap](#14-implementation-roadmap)
- [15. Risks and Mitigations](#15-risks-and-mitigations)
- [16. Open Questions](#16-open-questions)
- [17. Operating Philosophy](#17-operating-philosophy)
- [18. Doc Lints](#18-doc-lints)
- [19. Installation and Project Setup](#19-installation-and-project-setup)
- [20. Verification and Test Strategy](#20-verification-and-test-strategy)
- [Appendix A — Outside Voice Prompt Template](#appendix-a--outside-voice-prompt-template)
- [Appendix B — Host Detection Snippet](#appendix-b--host-detection-snippet)
- [Appendix C — Frontmatter Schemas](#appendix-c--frontmatter-schemas)

---

## 1. Executive Summary

Ensemble is an **11-skill, 11-agent** product-development toolkit that takes work from rough idea to shipped, documented, peer-reviewed code. It is host-agnostic — every skill detects whether it is running under Claude Code or Codex and adapts tool names, peer-review CLI invocations, and platform-specific behaviors accordingly.

The toolkit has five design pillars:

1. **Document-as-source-of-truth.** Every phase produces a durable artifact (`AGENTS.md`/`CLAUDE.md`, `foundation.md`, `docs/architecture.md`, `docs/designs/*.md`, `docs/plans/active/FRXX-*.md`, `docs/learnings/**/*.md`) and the next phase reads it. The repo is the system of record — anything not in the repo is illegible to the agent.
2. **Map, not encyclopedia.** Top-level `AGENTS.md` and `CLAUDE.md` are short pointer indexes (~100 lines) that lead the agent into deeper sources of truth in `docs/`. SKILL.md files follow the same principle — process logic in the file, templates and long checklists in `references/`.
3. **Cross-agent peer review.** Claude Code and Codex review each other's work via CLI subprocess at high-leverage gates: end of `en-plan`, per unit during `en-build`, and on demand via `en-cross-review`.
4. **Compounding knowledge.** Every solved problem, pattern, and decision is captured in `docs/learnings/` with frontmatter, queryable by future runs. `en-learn` updates `docs/architecture.md` after material changes; `en-garden` runs event-driven drift cleanup (on every PR merge to `main`) so doc debt gets paid down continuously.
5. **Lean by design.** SKILL.md files target 150–400 lines; agents are short specialist prompts (~40–120 lines). Conditional dispatch, depth-scaled questioning, mid-tier model defaults for peer review.

Ensemble replaces the existing `prod-dev-skills` set, borrowing selectively from Superpowers (TDD discipline, worktree isolation, two-stage review), Gstack (live browser QA, confidence-calibrated findings), Compound Engineering (persona-driven review, autofix-class routing, learnings store, stable IDs), and OpenAI's harness-engineering essay (map-not-encyclopedia AGENTS.md, plans split by lifecycle, doc lints, recurring drift cleanup, failure-→-capability-gap operating principle).

---

## 2. Goals and Non-Goals

### 2.1 Goals (G-IDs)

- **G1.** A single coherent toolkit for both new product development and feature work in existing projects.
- **G2.** One foundation document per product that combines product requirements, technical design, and architecture — no PRD/TDD split.
- **G3.** Plans capture requirements, design, and technical detail in one document with stable per-unit identifiers.
- **G4.** Build phase honors per-unit execution posture (test-first, characterization-first, or pragmatic) without enforcing iron-law TDD.
- **G5.** Code review is multi-persona, confidence-gated, and routes findings by autofix class.
- **G6.** QA exercises real browser flows via Playwright MCP and produces atomic bug-fix commits with regression tests.
- **G7.** Every meaningful learning is captured to a queryable store and reused by future skills automatically.
- **G8.** Cross-agent peer review (Claude Code ↔ Codex) at high-leverage gates with cost controls and recursion guards.
- **G9.** Skills work identically across Claude Code and Codex with host-aware adaptations.
- **G10.** Token-efficient — lean SKILL.md, on-demand reference loading, conditional agent dispatch, depth-scaled questioning.
- **G11.** A living `docs/architecture.md` that always reflects the current architectural reality of the project, maintained event-driven by `en-learn` and drift-driven by `en-garden`.
- **G12.** Recurring drift cleanup so technical debt gets paid down continuously, not in painful bursts.
- **G13.** Mechanical doc lints that catch knowledge-base drift before it compounds (frontmatter validity, ID stability, cross-link integrity, freshness).

### 2.2 Non-Goals

- A separate, classical PRD/TDD/architecture split (collapsed into one foundation doc).
- Iron-law red-green-refactor TDD as a global gate (kept as per-unit signal).
- A 50-agent reviewer zoo (kept lean: 4 always-on, 3 conditional reviewers, 3 research agents).
- Multi-platform support beyond Claude Code and Codex (no Cursor, Gemini, Copilot, etc. in scope for v1).
- Cross-machine memory sync, telemetry, or update-check infrastructure.
- A heavy AskUserQuestion ritual (decision-brief format with completeness scores, ELI10 paragraphs, etc.).
- An auto-orchestrator that runs the full pipeline unattended (autonomous mode is out of scope for v1).

---

## 3. User and Use Cases

### 3.1 Primary user

- **Mano Kulasingam** — solo operator using Claude Code as the primary harness, with Codex available for peer review and execution. Builds in TypeScript, JavaScript, occasional Ruby/Rails. Values comprehensive documentation in artifacts but lean prompt files in skills. Wants automation but with explicit confirmation before destructive or external actions.

### 3.2 Use cases (UC-IDs)

- **UC1. New product, end-to-end.** Start with `en-brainstorm` to think out loud → `en-foundation` to lock product+technical scope → `en-plan` for the first feature(s) → `en-build` → `en-review` → `en-qa` → `en-learn` → `en-ship`.
- **UC2. New feature in an existing project.** `en-brainstorm` (optional) → `en-plan` → `en-build` → `en-review` → `en-qa` → `en-learn` → `en-ship`. `en-foundation` already exists from a prior run.
- **UC3. Refactor or migration.** `en-brainstorm` (to explore approaches) → `en-plan` (with characterization-first execution notes) → `en-build` → `en-review` → `en-qa` → `en-learn` → `en-ship`.
- **UC4. Bug fix.** Skip directly to `en-build` (with bare-prompt input) or use a future `debug` skill (out of scope for v1) → `en-review` → `en-qa` → `en-learn` → `en-ship`.
- **UC5. Ad-hoc cross-review.** `/en-cross-review <path|description>` to ship any artifact to the peer agent for an outside-voice critique.
- **UC6. Documentation pass.** `en-learn` invoked standalone after a feature ships, or `learn --refresh` to update stale learnings.

### 3.3 Out of scope for v1

- Long-running autonomous loops (no `/lfg`-style orchestrator).
- Slack or external-system integration during planning.
- Multi-agent parallel implementation across more than two agents.

---

## 4. Product Decisions

### 4.1 Key decisions (D-IDs)

- **D1. Foundation captures intent; `docs/architecture.md` captures reality.** `foundation.md` holds product requirements, technical direction, and architectural intent (the vision and rationale at project start, plus durable decisions). `docs/architecture.md` is the living document that reflects the *current* state of the system — components, dependencies, layer rules, data flows. Foundation is the answer to "what did we set out to build and why"; `docs/architecture.md` is the answer to "what does the code actually look like today." Sections scale by depth.
- **D2. Plans, not feature docs.** Per-feature implementation plans live in `docs/plans/active/FRXX-*.md` while in-flight, then move to `docs/plans/completed/FRXX-*.md` after `en-learn` flips them post-ship. Each plan carries stable U-IDs per implementation unit. They become living documentation after `en-build` completes (per D16).
- **D3. Multi-persona code review with autofix-class routing.** 4 always-on reviewer personas + 3 conditional. Findings tagged with severity (P0–P3), confidence (1–10), and autofix class (`safe_auto` / `gated_auto` / `manual` / `advisory`).
- **D4. Cross-agent peer review.** End of `en-plan`, per unit during `en-build`, optionally on `en-foundation` and `en-review`. Implemented via `claude -p` ↔ `codex exec` subprocess calls. Recursion-guarded by `ENSEMBLE_PEER_REVIEW=true` env var.
- **D5. Live browser QA.** `en-qa` uses Playwright MCP for click-through end-to-end testing, on top of project-native lint/typecheck/test suite checks.
- **D6. Compounding learnings.** `en-learn` writes structured frontmatter docs to `docs/learnings/{bugs,patterns,decisions}/`. `learnings-research` agent queries them on every subsequent `en-plan` and `en-review`.
- **D7. Stable IDs.** R-IDs in `foundation.md` (requirements), U-IDs in plans (implementation units), FRXX in plan filenames (auto-incremented). U-IDs never renumber after assignment.
- **D8. Host-agnostic skills.** Every skill begins with a host-detection step that sets `HOST`, `PEER`, `PEER_CMD`, and platform-specific tool names. Single source of truth lives in `references/host-detect.md`.
- **D9. No bash preambles, no telemetry.** Skills start with a brief mode-detection and host-detection block (~10 lines), not a 100-line runtime initialization.
- **D10. Light AskUserQuestion ritual.** Recommendation + 2–4 options + one-line rationale. No decision-brief format; reserved for genuinely opaque trade-offs.
- **D11. Right-size by depth.** Every skill classifies work into Lightweight / Standard / Deep. Question count, section count, agent dispatch, and review depth all scale.
- **D12. No iron-law TDD.** Per-unit `Execution note` (test-first, characterization-first, pragmatic) lives in plans. `en-build` honors the note; user can always override.
- **D13. `docs/architecture.md` as a living, code-accurate document.** Lives in `docs/` alongside other system-of-record artifacts. Pointed to from `AGENTS.md`. Initial draft seeded by `en-foundation` from the architectural intent. Continuously updated by `en-learn` after every material structural change ships (new module, changed boundaries, new infrastructure). Drift-detected and fix-PR'd by `en-garden` on each PR-merge run.
- **D14. Event-driven doc-drift cleanup as a first-class skill (`en-garden`).** A separate skill that runs on `push` to `main` (i.e., immediately after a PR merges) — not on a recurring schedule. Scans the repo against doc artifacts and lints, opens small doc-only PRs, and auto-merges them after `en-review` clears them. Manual invocation (`/en-garden`) also supported. Continuous payment of doc debt instead of painful bursts.
- **D15. Project-level `AGENTS.md` and `CLAUDE.md` as map, not encyclopedia.** Two pointer documents at repo root, ~100 lines each. **`AGENTS.md`** is the canonical, host-agnostic map — it orients any agent (Codex, Claude Code, or otherwise) toward deeper sources of truth in `docs/`. **`CLAUDE.md`** opens with a one-line cross-reference to `AGENTS.md` and contains *only* Claude-Code-specific guidance (slash command preferences for this project, skill invocation priority, auto-memory notes, status line / hook references, plugin pointers). No content duplicated from `AGENTS.md`. Doc lint `claude-md.no-shared-content` flags any duplication. Both files created by `en-foundation`, kept current by `en-learn` and `en-garden`.
- **D16. Plans split by lifecycle.** `docs/plans/active/` for in-flight plans, `docs/plans/completed/` for shipped ones, `docs/plans/tech-debt-tracker.md` as the canonical place for "noticed but deferred" items. `en-learn` moves plans from active to completed at ship time.
- **D17. Pack-reference is a mode of `en-learn`, not a separate skill.** `learn --pack <library>` fetches docs once via Context7 + WebSearch and writes a flattened `docs/references/<lib>-llms.txt`. `en-plan`, `en-build`, and `en-brainstorm` consult these local references before falling back to network calls.
- **D19. Learning store as a wiki, not a flat list.** Adopt Karpathy's "LLM Wiki" pattern: the `docs/learnings/` directory is a structured, interlinked, agent-maintained knowledge base, not a dumb folder of frontmatter files. New entries actively walk related pages and add reciprocal back-links. Two helper artifacts navigate the graph: `docs/learnings/index.md` (content catalog the agent reads first) and `docs/learnings/log.md` (append-only chronological record). `learn --lint` keeps the graph healthy (orphans, missing back-refs, contradictions, missing pages for frequently-cited concepts).
- **D20. `learn ingest <source>` for proactive knowledge capture.** Distinct from `capture` (which is reactive, post-fix). `ingest` reads any engineering-relevant source — a file path or a URL — and writes a structured summary to `docs/learnings/sources/<slug>-<date>.md`, then walks 10–15 related pages and updates them. Use cases: library evaluation articles, design references from elsewhere, customer-call summaries, best-practice posts. URL inputs use WebFetch; file inputs use Read.
- **D21. Capture-from-synthesis reflex.** When `en-plan`, `en-review`, or `en-brainstorm` produces a durable synthesis (a comparison, a non-obvious connection, a pattern across multiple files, an extracted lesson), the skill ends with a soft "**Capture this as a learning?**" prompt rather than letting the synthesis disappear into chat. The user accepts → `en-learn capture --from-conversation` files it.
- **D22. Skill-name prefix `en-`.** All eleven skills use the `en-` prefix consistently across slash commands, directory names, and skill identifiers (`en-brainstorm`, `en-foundation`, `en-plan`, `en-build`, `en-review`, `en-qa`, `en-learn`, `en-ship`, `en-cross-review`, `en-garden`, `en-setup`). Avoids namespace collision with other plugins.
- **D23. Cross-review peer is always the *other* agent.** Resolved by host-detect on every invocation. Claude Code → peer is Codex. Codex → peer is Claude. No model-defaults table to maintain; the host *is* the routing.
- **D24. `en-foundation` emits FR01-project-setup only for new projects.** Detection: `docs/foundation.md` does not yet exist *and* the repo has no source code (or initial-commit state). Existing projects skip FR01 entirely.
- **D25. `en-build` batch size is dynamic.** Derived from the feature being implemented — tightly-coupled units batch together, independent units allow larger batches, complex/sensitive units (auth, payments, migrations) batch alone. No fixed default.
- **D26. `en-learn` auto-runs after `en-build` and `en-qa`.** Soft auto-invoke with a one-line announcement; user can decline. Removes the friction of remembering to capture lessons.
- **D27. `en-garden` is strictly doc-only and PR-merge-triggered.** Runs as `.github/workflows/en-garden.yml` on `push` to `main`. Opens *doc-only* PRs that auto-merge after `en-review` clears. Code-level findings go to `docs/plans/tech-debt-tracker.md` instead of being acted on.
- **D28. Worktrees are opt-in per dispatch.** Following Compound Engineering's pattern, skills pass `isolation: "worktree"` on subagent dispatch when isolation is beneficial — primarily `en-build` for per-unit work. Not a repo-wide setting.
- **D29. Per-unit code simplification before peer review.** During `en-build`, after the unit passes verification gate 1 (tests + lint), the `code-simplifier` agent (Anthropic's official refiner) runs against the unit's diff. Verification gate 2 re-runs unit tests; if anything fails, the simplifier's edits are reverted and the original implementation proceeds. Only after both gates does the unit go to per-unit Outside Voice peer review. Reduces the noise the peer reviewer has to triage and applies project standards (CLAUDE.md / AGENTS.md) consistently. Skipped on trivial units (renames, single-line config tweaks, pure deletions) or with `--no-simplify`.
- **D30. Peer reports, host applies.** This is the core contract for every Outside Voice cross-review across every skill (`en-foundation`, `en-plan`, `en-build`, `en-cross-review`, optional `--peer` on others). The peer agent **only reports findings** in structured JSON. It does **not** edit files, run commands, modify state, or make commits. The host (the agent running the skill) is the sole code-modifier — it parses the peer's findings, decides which it agrees with, and applies the agreed ones. Peer outputs are advisory; host has agency. This separation keeps the peer's role bounded (cheap, stateless, parallelizable) and prevents the two agents from racing on the same files.
- **D31. Single-agent fallback when only one CLI is available.** If the user has only Claude Code installed (no Codex), or only Codex (no Claude Code), Outside Voice cross-review degrades to a **fresh-instance fallback**: the host shells out to its own CLI in a clean subprocess (e.g., `claude -p` from within Claude Code, `codex exec` from within Codex). The fresh context still catches things the implementing session has rationalized away — Superpowers' subagent-driven-development pattern relies on exactly this. **The contract from D30 still holds:** the fresh instance only reports findings; the host applies them. The peer's response carries a `peer_mode` field (`cross-agent` vs `single-agent-fallback`) so the user always knows which mode they're in. Same-agent fallback is a degraded mode — same model means same systematic biases — so the prompt is augmented with explicit "be more aggressive, bias toward finding problems" framing to maximize the value of the fresh context. Setup script detects on install and recommends installing the other CLI; doesn't block.
- **D18. Mechanical doc lints catch drift before it compounds.** A small `bin/ensemble-lint` script + `references/doc-lints.md` enforces frontmatter validity, ID stability (R-IDs, U-IDs, FRXX), cross-link integrity, no-absolute-paths, status correctness on plans, freshness on `docs/architecture.md`. `en-review` runs lint as pre-flight; `en-garden` opens fix-up PRs.

---

## 5. Skill Catalog

Eleven skills total: the ten lifecycle skills plus `en-setup` for project-level bootstrap and diagnostics. All prefixed `en-` to namespace cleanly alongside other plugins.

### 5.1 Skill summary

| # | Skill | One-line purpose | Primary input | Primary output | Cross-review | Host-detect |
|---|---|---|---|---|---|---|
| 1 | `en-brainstorm` | Q&A + research + 2–3 approaches with trade-offs | Idea, problem, or rough description | `docs/designs/YYYY-MM-DD-<topic>.md` | Off (default) | Optional |
| 2 | `en-foundation` | Combined PRD + technical direction + initial architecture for a new product | Brainstorm design doc OR direct invocation | `docs/foundation.md`, `docs/architecture.md`, `AGENTS.md`, `CLAUDE.md` | On (default Yes) | Yes |
| 3 | `en-plan` | Feature/component/refactor plan with U-IDs | Brainstorm output, foundation, or direct request | `docs/plans/active/FRXX-<name>.md` | On (default Yes) | Yes |
| 4 | `en-build` | Execute the plan with branch/worktree, batched | Plan path | Code + commits on a feature branch | On (per unit) | Yes |
| 5 | `en-review` | Multi-persona code review of current branch | Branch with changes | Review report + applied auto-fixes | Off (default), `--peer` to enable | Yes |
| 6 | `en-qa` | System checks + browser end-to-end testing | Branch + optional URL | Bug fixes + new regression tests | Off | Optional |
| 7 | `en-learn` | Compounding wiki maintainer. **`capture`** (default): file a learning + sync `docs/architecture.md` / foundation / plan + maintain cross-refs. **`ingest <path-or-url>`**: read external source, write summary, update related pages. **`--pack <lib>`**: flatten external docs to `docs/references/<lib>-llms.txt`. **`--refresh`**: audit stale entries. **`--lint`**: structural health (orphans, missing back-refs, contradictions, missing pages). | Commits/branch (capture), file path or URL (ingest), library name (pack), store path (refresh, lint) | Learning doc, doc updates, `index.md` + `log.md` updates, cross-ref edits, source summaries, or library reference | Off | Optional |
| 8 | `en-ship` | Pre-flight + commit + push + PR | Branch with clean changes | Commit + PR (or merge) | Off | Optional |
| 9 | `en-cross-review` | Ad-hoc peer review of any artifact | File path or git ref | Critique + applied fixes | Always on (it IS the peer call) | Yes |
| 10 | `en-garden` | Recurring drift scan against `docs/golden-principles.md`, `docs/architecture.md`, plans, and doc lints. Opens small targeted refactor PRs that auto-merge after `en-review` clears them. | Repo state | Auto-merging cleanup PRs | Off | Yes |
| 11 | `en-setup` | Project-level bootstrap and diagnostics. Detects state (new / existing-without-Ensemble / existing-with-Ensemble), creates the directory skeleton, generates `AGENTS.md` + `CLAUDE.md` from templates, installs the `en-garden` GitHub Action, sets up `.ensemble/` config files, runs health checks. | Repo state | Project skeleton, config files, GH Action workflow, diagnostic report | Off | Yes |

### 5.2 Skill details

#### 5.2.1 `en-brainstorm`

- **Purpose.** Explore an idea through Q&A, research prior art, propose 2–3 approaches with trade-offs, run a devil's-advocate pass, and write a design doc.
- **Process (high-level).**
  1. Detect host (light — only needed for path conventions).
  2. Scope check (Lightweight / Standard / Deep).
  3. Existing context scan (`docs/foundation.md`, `docs/plans/`, recent commits, related code).
  4. Q&A (one question per turn, multiple-choice preferred where natural).
  5. Optional research via `web-research` agent (Context7, WebSearch).
  6. Propose 2–3 approaches with trade-offs and a recommendation.
  7. Devil's advocate — stress-test the recommendation.
  8. Present design and get user approval.
  9. Write to `docs/designs/YYYY-MM-DD-<topic>-design.md`.
  10. Hand off — suggest `en-foundation` (new product) or `en-plan` (feature).
- **Hard gate.** Does not invoke implementation skills.
- **Cross-review.** Off by default. Brainstorming is exploratory; outside critique here is premature.
- **Reference files.**
  - `references/socratic-questions.md`
  - `references/research-guide.md`
  - `references/design-doc-template.md`

#### 5.2.2 `en-foundation`

- **Purpose.** Produce the foundational artifact set for a new product: `foundation.md` (vision, decisions, technical direction), `docs/architecture.md` (initial architectural reality seed), `AGENTS.md` and `CLAUDE.md` (project-level pointer maps). Run once when a project starts; thereafter `en-learn` keeps the architecture reality and pointer maps current.
- **Process (high-level).**
  1. Detect host. Resolve peer for Outside Voice.
  2. Orient — read existing `foundation.md`, brainstorm design docs, and any code in the repo.
  3. Discovery (one question per turn) across these topic groups, depth-scaled:
     - Product identity & problem
     - Users & roles
     - Goals & success criteria
     - Scope boundaries (in / out / deferred)
     - Functional requirements (R-IDs assigned here)
     - User experience
     - Technical direction (stack, hosting, security model)
     - Data architecture (tables, isolation, key entities)
     - API surface
     - Deployment & infrastructure
     - Risks & open questions
  4. Synthesize — present a structured summary for approval.
  5. Draft `foundation.md` using the template.
  6. Section-by-section review with the user.
  7. **Outside Voice review** — ship the draft to the peer agent; user picks which findings to incorporate.
  8. Seed `docs/architecture.md` with the initial architecture (component diagram, layer rules if specified, primary data flows). Marked as `status: seed` until `en-learn` writes its first reality-driven update after the first plan ships.
  9. Write `AGENTS.md` as the canonical, host-agnostic pointer map (~100 lines) using `references/agents-md-template.md`. Indexes `foundation.md`, `docs/architecture.md`, `docs/plans/active/`, `docs/learnings/`, and `docs/references/`. Lists key project commands (build, test, lint), conventions, and entry points — anything an agent (any agent) needs to orient itself.
  10. Write `CLAUDE.md` using `references/claude-md-template.md`. **Strict structure:**
      - **First line** — exactly: `> See [AGENTS.md](./AGENTS.md) for the project map and shared agent guidance.`
      - **Body** — Claude-Code-specific content **only**. No content duplicated from `AGENTS.md`. Allowed sections:
        - **Slash command preferences** for this project (e.g., "Use `/en-plan` before `/en-build` for any feature with > 3 files").
        - **Skill invocation priority** when multiple skills could apply.
        - **Auto-memory guidance** specific to Claude Code's `~/.claude/projects/.../memory/` system.
        - **Status line / hook references** (paths to project-specific hooks if any).
        - **Plugin/marketplace pointers** if the project uses specific Claude Code plugins.
        - **Tool-name notes** specific to Claude Code (e.g., "AskUserQuestion is deferred — preload via `ToolSearch` before first use").
      - **Forbidden** in CLAUDE.md (belongs in AGENTS.md): project structure, coding conventions, build/test/lint commands, architecture descriptions, anything readable by Codex.
      - Doc lint `claude-md.no-shared-content` flags any heading or content block that duplicates AGENTS.md.
  11. Final save and hand off (suggest `en-plan` for the first feature).
- **Hard gate.** No code; no PRs; no scaffolding.
- **Cross-review.** On by default. Skip with `--no-peer`.
- **Reference files.**
  - `references/foundation-template.md` (depth-scaled)
  - `references/foundation-questions.md`
  - `references/architecture-template.md` (initial seed)
  - `references/agents-md-template.md`
  - `references/claude-md-template.md`
  - `references/host-detect.md`
  - `references/outside-voice.md`

#### 5.2.3 `en-plan`

- **Purpose.** Turn a feature, component, or refactor into a concrete implementation plan with stable U-IDs. Reads `foundation.md` and any relevant brainstorm design doc.
- **Process (high-level).**
  1. Detect host. Resolve peer.
  2. Resume existing plan if one matches, otherwise create fresh.
  3. Source the request: brainstorm doc, foundation, bug report, or rough description.
  4. Right-size depth (Lightweight / Standard / Deep).
  5. Phase 1 research — dispatch `repo-research` and `learnings-research` agents in parallel. Optionally `web-research` if external best-practice context is needed.
  6. Resolve planning questions (architecture, file boundaries, test strategy, dependencies).
  7. Break the work into implementation units with stable U-IDs (`U1`, `U2`, …).
  8. For each unit: Goal, Requirements (R-IDs covered), Dependencies (other U-IDs), Files (repo-relative), Approach, optional Execution note, Patterns to follow, Test scenarios, Verification.
  9. Write to `docs/plans/active/FRXX-<name>.md` with auto-incremented FRXX (continuing from highest existing number across both `active/` and `completed/`).
  10. **Outside Voice review** — peer agent critiques the plan; user incorporates agreed findings.
  11. Confidence check — flag low-confidence sections, optionally deepen.
  12. Hand off to `en-build`.
- **Cross-review.** On by default.
- **Reference files.**
  - `references/plan-template.md`
  - `references/host-detect.md`
  - `references/outside-voice.md`
  - `references/research-dispatch.md`

#### 5.2.4 `en-build`

- **Purpose.** Execute a plan. Runs in two flavors based on host detection. Both flavors guarantee the same cross-agent property: the agent that *implements* a unit is **not** the agent that *reviews* it.
- **Two dispatch roles** (used in different flavors). It's important to keep these distinct because they have different constraints:
  - **WORKER dispatch** — the host dispatches the other agent to *do implementation work*. The worker may edit files, write code, run tests within scope. The worker returns its diff. Used in build-by-orchestration. This is **not** subject to D30 ("peer reports, host applies") because D30 governs *peer-review* dispatch, not worker dispatch.
  - **PEER-REVIEWER dispatch** — the host dispatches the other agent to *review and report findings only*. The peer-reviewer **must not** edit files, run commands, or commit (D30 + Appendix A). Used in build-handoff and in any cross-review.
- **Flavors.**
  - **Build-by-orchestration** (default in Claude Code). Claude is the host. For each unit, Claude dispatches Codex as a **WORKER** (`codex exec` with explicit "implement this unit" scope) — Codex writes the code and returns the diff. Claude then reviews the diff itself (`code-simplifier` + lint + tests + own judgment) and applies findings. If applying a finding requires further code edits, Claude has two options:
    1. Apply the fix itself (Claude has the working tree).
    2. Dispatch Codex as WORKER again with explicit "apply this specific fix" instructions, then re-verify.
    Either is fine — Codex remains in WORKER role; Claude remains the host. No D30 violation. The cross-agent property holds because Codex implemented and Claude reviewed; no separate `claude -p`/`codex exec` peer-reviewer subprocess is needed.
  - **Build-handoff** (default in Codex). Codex is the host. For each unit, Codex implements natively, runs `code-simplifier`, then dispatches Claude as a **PEER-REVIEWER** via `claude -p`. Claude returns structured findings only — does not modify any files (D30 + Appendix A). Codex parses the findings, applies the ones it agrees with, defers others to `tech-debt-tracker.md`, disagrees with the rest, then commits. The cross-agent property holds because Codex implemented and Claude (as peer-reviewer) reviewed.
- **Why the asymmetry.** The choice of dispatch role depends on which agent is the host:
  - Host = Claude (Claude Code) → Codex is dispatched as WORKER (Claude is naturally the reviewer-of-Codex's-output).
  - Host = Codex → Claude is dispatched as PEER-REVIEWER (Codex implements natively).
  - Either way: implementer ≠ reviewer, and the host always holds the write pen on commits.
- **D30 applies to peer-reviewer dispatch only.** Worker dispatch (build-by-orchestration) does *not* invoke D30 — the worker is implementing, not reviewing. The dispatching prompt must clearly identify which role it's invoking; the wrapper in `references/build-orchestration.md` does this with explicit role markers in the dispatch prompt.
- **Process (high-level).**
  1. Detect host. Choose flavor.
  2. Load plan; verify all U-IDs present and unblocked.
  3. Set up branch (or worktree if available). Auto-stash dirty tree with confirmation.
  4. Read foundation, related plan files, CLAUDE.md / AGENTS.md, project conventions.
  5. Plan review with the user — concerns, clarifications, dependency installs needed.
  6. For each unit (in dependency order):
     - Honor `Execution note` (test-first / characterization-first / pragmatic).
     - Implement via current host or dispatch peer (build-by-orchestration mode).
     - **Verification gate 1.** Run unit-level tests + project lint/typecheck. If anything fails, fix before proceeding — do not advance to simplification or peer review on a broken unit.
     - **Code simplification pass.** Dispatch the `code-simplifier` agent against the unit's diff. The agent refines recently modified code for clarity, consistency, and project-standards compliance (CLAUDE.md / AGENTS.md), preserving functionality. Skip on trivial units (renames, single-line config tweaks, pure deletions); skip with `--no-simplify` on the invocation. The simplifier modifies files directly and returns a `summary` + `changes_made[]`.
     - **Verification gate 2.** Re-run unit-level tests after the simplifier. If anything fails, **revert the simplifier's changes** (`git restore` the affected files to their pre-simplifier state) and proceed with the original implementation. Surface the regression in the unit's progress report.
     - **Per-unit Outside Voice peer review.** A different agent than the implementer reviews the simplified unit diff and returns structured findings only. **The reviewer never modifies files** (D30 + Appendix A).
       - In **build-by-orchestration** (host = Claude, implementer = Codex): Claude reads Codex's returned diff and forms findings itself. No separate subprocess; the cross-agent property is already satisfied because Codex implemented and Claude is reviewing.
       - In **build-handoff** (host = Codex, implementer = Codex natively): Codex shells out via `claude -p --output-format json "<peer prompt>"` with `ENSEMBLE_PEER_REVIEW=true` set. Claude reads the diff, returns findings JSON, and exits. Codex parses the JSON.
     - **Host applies findings it agrees with.** The host walks each finding and chooses one of three responses:
       1. **Agree and apply** — host modifies the unit's code to address the finding. Mechanical fixes (typos, naming, simple refactors) and clear correctness fixes apply autonomously. Note in commit body: `Addresses peer finding: <title>`.
       2. **Agree but defer** — finding is valid but out of scope for this unit. Append an entry to `docs/plans/tech-debt-tracker.md` (with TD-ID per A19) citing the unit. Move on.
       3. **Disagree with rationale** — host believes the peer is wrong. Note one-line rationale in the unit progress report. Move on.
     - **Surface to user.** If the peer reports a P0 finding the host disagrees with, *or* a security/architectural finding marked confidence ≥ 8 the host wants to defer, pause and ask the user before committing. All other host decisions proceed without confirmation.
     - **Re-verification.** If host applied any code changes in response to peer findings, re-run unit tests + lint before commit. Failures revert host's changes (`git restore`) and surface to user.
     - Commit with conventional message including the U-ID; commit body lists peer findings handled (applied / deferred / disagreed).
  7. After all units: full test suite, lint, typecheck.
  8. Summary: completion status per U-ID, deviations, simplifier changes (if any), next-step recommendation. Auto-invokes `/en-learn` (soft prompt) → suggests `/en-review` → `/en-qa` → `/en-ship`.
- **Cross-review.** On per unit. Disable with `--no-peer-per-unit`.
- **Code simplification.** On by default per unit. Disable with `--no-simplify`.
- **Reference files.**
  - `references/host-detect.md`
  - `references/outside-voice.md`
  - `references/build-orchestration.md` (per-unit dispatch logic)
  - `references/build-handoff.md` (Codex-native flow)
  - `references/code-simplifier-dispatch.md` (when to skip, what to pass, revert protocol)

#### 5.2.5 `en-review`

- **Purpose.** Multi-persona code review of current branch changes against the plan and project conventions.
- **Process (high-level).**
  1. Detect host. Determine diff base (PR target, default branch fallback).
  2. Read plan(s) referenced by the branch.
  3. Always-on personas: `correctness`, `testing`, `maintainability`, `standards`. Plus `learnings-research`.
  4. Conditional personas based on diff content: `security`, `performance`, `migrations`.
  5. Each persona returns structured JSON. Synthesis merges, dedups, classifies.
  6. Apply `safe_auto` fixes automatically.
  7. Present `gated_auto`, `manual`, and `advisory` findings grouped by severity.
  8. User picks which to apply.
  9. Optional `--peer` flag enables Outside Voice cross-review on top of personas.
  10. Output review report (markdown) and a JSON envelope (for programmatic callers).
- **Modes.** Three modes determine whether `en-review` may modify files:
  - **`interactive`** (default for direct user invocation) — auto-applies `safe_auto` fixes, presents `gated_auto`/`manual` findings to the user. May write to the working tree.
  - **`headless`** (default for skill-to-skill invocation in non-CI contexts) — auto-applies `safe_auto` fixes silently and returns structured JSON for the calling skill. May write to the working tree. Used by `en-build` per-unit and `en-cross-review`.
  - **`report-only`** — strictly read-only. No file edits, no commits. Returns findings JSON only. **Required mode when `en-review` is invoked from CI** (e.g., by `en-garden`). The reason: mutation in CI would push a commit, which retriggers garden — and more fundamentally, a "verification gate" that mutates is conceptually muddled. Verification and repair are separate steps.

  Mode is selected by the calling skill, with these mandatory rules:
  - When `en-build` invokes `en-review` per-unit → `headless`.
  - When `en-garden` invokes `en-review` to gate a PR → `report-only` (always; not configurable).
  - When the user invokes `/en-review` directly → `interactive`.
  - When `en-cross-review` invokes `en-review` against a target → `headless`.
- **Cross-review.** Off by default; available via `--peer`.
- **Reference files.**
  - `references/host-detect.md`
  - `references/outside-voice.md`
  - `references/persona-dispatch.md`
  - `references/finding-schema.md`
  - `references/severity-and-routing.md`

#### 5.2.6 `en-qa`

- **Purpose.** Test the work like a real user. System checks first, then live browser end-to-end via Playwright MCP. Find bugs, fix them with atomic commits, regenerate regression tests, re-verify.
- **Process (high-level).**
  1. System checks: lint, typecheck, project test suite. Stop and report if anything fails.
  2. If a URL is provided (or auto-detected from the branch), proceed to browser QA.
  3. Bootstrap test framework if absent; otherwise read existing test conventions.
  4. Click through golden-path flows.
  5. Click through edge cases: empty states, error states, slow network, double-click, navigate-mid-action.
  6. For each bug:
     - Reproduce.
     - Identify root cause.
     - Fix in source code.
     - Add regression test.
     - Atomic commit `fix(qa): <description>`.
     - Re-verify.
  7. Output QA report with before/after evidence.
- **Cross-review.** Off — bug fixes are mechanical.
- **Reference files.**
  - `references/qa-flows.md`
  - `references/playwright-helpers.md`

#### 5.2.7 `en-learn`

- **Purpose.** Maintain `docs/learnings/` as a compounding, interlinked wiki — not a flat folder. Capture engineering events, ingest external sources, keep architecture/foundation/plans honest, curate external library references, and check graph health.
- **Modes.** `capture` (default), `ingest <path-or-url>`, `--refresh`, `--pack <library>`, `--lint`.
- **Always-on behavior across modes that write entries (capture, ingest):**
  - **Active cross-reference maintenance.** After writing the new entry, walk through every page in its `related: []` field and append a reciprocal back-reference to those pages' frontmatter. Forward refs without back-refs make the graph one-directional and orphans accumulate.
  - **Index update.** Append a one-line entry to `docs/learnings/index.md` under the appropriate category, with date and one-line summary.
  - **Log append.** Append a single line to `docs/learnings/log.md` in the format `## [YYYY-MM-DD] <op> | <subject>` (grep-friendly — Karpathy's tip).

##### Mode A: `capture` (default)

Run after a feature ships, after a bug is fixed, or anytime there is a durable insight worth preserving. Also invoked as `capture --from-conversation` when `en-plan`, `en-review`, or `en-brainstorm` ends with a synthesis worth filing.

- **Process (high-level).**
  1. Detect what just shipped (recent commits, branch summary) — or, in `--from-conversation` mode, take the user-confirmed synthesis as input.
  2. Identify the learning category: `bugs/`, `patterns/`, `decisions/`.
  3. Spawn parallel sub-tasks:
     - **Context Analyzer** — extract problem, symptoms, root cause from conversation and commits.
     - **Solution Extractor** — capture the fix, why it works, prevention strategies.
     - **Related Docs Finder** — search `docs/learnings/` for overlap; flag near-duplicates; identify pages that should back-link.
  4. Write `docs/learnings/<category>/<slug>-<date>.md` with frontmatter.
  5. Apply the always-on behaviors (cross-refs, index update, log append).
  6. **Sync `docs/architecture.md`** if material structural change (new module, changed boundaries, new infrastructure, dependency direction shifts, new external integration). Surgical edits to drifted sections only — never regenerate the whole doc. Bump `updated: YYYY-MM-DD`.
  7. **Sync `foundation.md`** if scope, decisions, or top-level direction changed.
  8. **Move the relevant plan** from `docs/plans/active/FRXX-*.md` to `docs/plans/completed/FRXX-*.md` — flip status from `active` to `completed`, replace plan-tense with documentation-tense. Note any deviations from the plan.
  9. **Sync `AGENTS.md` / `CLAUDE.md`** if the artifact directory or top-level guidance changed (rare).
  10. Update `docs/README.md` index.

##### Mode B: `ingest <path-or-url>`

Proactive knowledge capture. Bring an engineering-relevant external source into the wiki. Use cases: library evaluations, design references from elsewhere, customer-call summaries, best-practice articles, design docs, papers.

- **Input handling.**
  - **File path** (e.g., `learn ingest path/to/article.md`) — read with the platform's read tool.
  - **URL** (e.g., `learn ingest https://example.com/article`) — fetch via WebFetch (Claude Code) / equivalent (Codex). On 403/Cloudflare blocks, fall back to Wayback Machine (`https://web.archive.org/web/<URL>`); if that fails too, ask the user to paste the content.
- **Optional flag.** `--category {sources|patterns|decisions}` — defaults to `sources/`. Use `--category decisions` when the source is itself a decision-log entry, `--category patterns` when it documents a pattern worth promoting (rare; usually patterns emerge from our own work, not external reads).
- **Process.**
  1. Read the source (file or URL).
  2. Briefly discuss key takeaways with the user (one or two paragraphs of "here's what I'm extracting").
  3. Write a summary page at `docs/learnings/sources/<slug>-<date>.md` with frontmatter including `source_type: file|url`, `source_uri: <path-or-url>`, `fetched: YYYY-MM-DD`.
  4. Identify 5–15 related pages across the wiki using the Related Docs Finder agent; for each, add a one-line update or a citation to the new source. Walk `related: []` and add reciprocal back-refs.
  5. Apply the always-on behaviors (index update, log append).
- **Boundaries.** Engineering-relevant sources only. If the user wants a personal knowledge base for unrelated topics, they should run a different system. Lint may flag obviously off-topic ingests for review.

##### Mode C: `--refresh`

Audit existing learnings for *content* staleness. For each entry: keep, update, replace, or archive (move to `docs/learnings/archive/`). Useful periodically (~monthly) or after a big architectural shift.

Distinct from `--lint`, which audits *structural* health.

##### Mode D: `--pack <library>`

Flatten an external library's docs into `docs/references/<library>-llms.txt` for in-context lookup, eliminating most network round-trips on subsequent `en-plan`, `en-build`, and `en-brainstorm` runs.

- **Process.**
  1. Resolve library identifier via Context7 (`mcp__context7__resolve-library-id`).
  2. Pull docs via Context7 (`mcp__context7__get-library-docs` or `query-docs`).
  3. Optionally augment with WebSearch for recent best-practice content.
  4. Flatten to a single `.txt` file at `docs/references/<library>-llms.txt` with a frontmatter header (library, version, source, fetched date).
  5. Add an entry to `docs/references/index.md`.
  6. Append a line to `docs/learnings/log.md`.
  7. Surface the new reference in `AGENTS.md` / `CLAUDE.md` map.

##### Mode E: `--lint`

Structural health check on the wiki graph. Distinct from `--refresh`, which is content-staleness; `--lint` is graph-shape.

- **Checks.**
  - **Orphans** — pages with zero inbound references.
  - **Missing back-refs** — page A's frontmatter has `related: [B]` but page B does not have A in its `related:`. Asymmetric forward refs.
  - **Contradictions** — claims across pages that conflict (LLM judgment, not mechanical). Surface with both citations.
  - **Missing pages** — concepts mentioned by name in 3+ pages without a dedicated entry. Suggest creating a page.
  - **Stale references** — links pointing to files that have moved or been deleted.
  - **Index drift** — entries in `index.md` that no longer match underlying pages, or pages that exist but are missing from `index.md`.
  - **Log drift** — operations missing from `log.md` (compare against git log of `docs/learnings/`).
  - **Data gaps** — areas where the wiki is thin and would benefit from a `learn ingest` of an external source. Suggest specific search queries.
- **Output.** A report grouped by check, with severity (P1 = orphan, broken link, missing back-ref; P2 = missing page, data gap, log drift; P3 = contradiction needing human judgment). For mechanical findings (P1, most P2), `learn --lint --fix` auto-applies fixes (add the missing back-ref, repair the broken link, regenerate `index.md`). Contradictions and content-judgment items go to the user.
- **Cadence.** On demand (`/en-learn --lint`), or invoked by `en-garden` as part of its post-merge pass. `en-garden` invokes `en-learn --lint` and routes the output through its PR-batching flow.

- **Cross-review.** Off by default in all modes (`--peer` to enable).
- **Reference files.**
  - `references/learning-template.md`
  - `references/learning-frontmatter-schema.md`
  - `references/learn-cross-ref-maintenance.md` (the always-on behavior)
  - `references/learn-index-format.md` (curated `index.md` structure)
  - `references/learn-log-format.md` (append-only log conventions)
  - `references/learn-ingest.md` (file + URL ingest flow, fallback handling)
  - `references/learn-lint.md` (the check catalog and auto-fix rules)
  - `references/architecture-update-rules.md` (when to touch `docs/architecture.md`, what counts as material)
  - `references/pack-reference-template.md` (frontmatter + structure for `*-llms.txt` files)

#### 5.2.8 `en-ship`

- **Purpose.** Get clean changes onto the remote with a meaningful commit message and PR.
- **Process (high-level).**
  1. Pre-flight: `git status`, current branch, diff stat. Stop on merge conflicts.
  2. Lint + typecheck + targeted tests on changed files.
  3. Secret scan on diff (.env files, AWS keys, private keys, common API-key patterns).
  4. Confirm scope of staging — show what will be committed.
  5. Conventional-commit message generated from the diff.
  6. Push: feature branch → `git push -u origin <branch>`, default branch → `git push origin <default>`.
  7. PR creation via `gh pr create` with summary auto-generated from commits and the plan.
  8. Optional merge if user confirms and CI is green.
- **Cross-review.** Off — by this point, `en-review` and `en-qa` have already passed.
- **Reference files.**
  - `references/conventional-commits.md`
  - `references/secret-patterns.md`

#### 5.2.9 `en-cross-review`

- **Purpose.** Ad-hoc peer review. Wraps any file, git diff, or branch and ships it to the peer agent.
- **Usage.** `/en-cross-review <path-or-ref> [--focus security|performance|tests|all]`
- **Process (high-level).**
  1. Detect host. Resolve peer.
  2. Resolve target (file, ref, branch, or current diff if no arg).
  3. Compose review prompt using `references/outside-voice.md` template.
  4. Set `ENSEMBLE_PEER_REVIEW=true` env var to prevent recursion.
  5. Invoke peer via subprocess.
  6. Parse JSON response; present findings grouped by severity and confidence.
  7. User picks which to apply.
- **Cross-review.** This is the cross-review.
- **Reference files.**
  - `references/host-detect.md`
  - `references/outside-voice.md`

#### 5.2.10 `en-garden`

- **Purpose.** Doc-drift cleanup that runs *automatically after every PR merge to `main`*. Scans the merged code against documentation artifacts, identifies what drifted, opens *doc-only* fix-up PRs, and auto-merges them after `en-review` clears them. Pays down doc debt continuously without ever modifying code.
- **Strict scope: doc-only.** `en-garden` **never** modifies source code, configuration, tests, or any non-doc artifact. If it notices a code-level pattern that should be refactored (a duplicated helper, a layer-rule violation, a hand-rolled util that has a shared equivalent), it files the observation as an entry in `docs/plans/tech-debt-tracker.md` for `en-plan` / `en-build` to handle later. This separation is non-negotiable: `en-garden` running unattended (auto-triggered, auto-merged) means it must touch only artifacts where the blast radius is bounded to documentation.
- **Trigger model — event-driven, not scheduled.** Default trigger: **`push` to `main`** (i.e., a PR just merged). Implemented as a GitHub Action workflow installed at `.github/workflows/en-garden.yml` by the setup script. Can also be invoked manually: `/en-garden`.
- **Why event-driven beats scheduled.** A PR merge is exactly when doc drift can be introduced. Scheduled runs either miss drift for hours/days or run when nothing has changed.
- **Why a separate skill from `en-learn`.** `en-learn` captures lessons in conversation, in real time, in the user's working session. `en-garden` runs unattended in CI. Different cadence (event-driven vs invocation-driven), different scope (doc drift vs lesson capture), different blast radius (auto-merge vs human-confirmed).
- **Process (high-level).**
  1. Triggered by `push` to `main`. CI checks out the repo and runs `/en-garden`.
  2. Detect host (CI runner). Resolve peer for any `en-review` invocations within garden's PRs.
  3. Run doc lints (`bin/ensemble-lint`) — file-shape checks. Capture violations.
  4. Run `en-learn --lint` — wiki-graph checks (orphans, missing back-refs, etc.). Capture violations.
  5. Compare `docs/architecture.md` against current code via `repo-research` agent: are documented components still present? Are dependency rules still honored? Are layer boundaries still clean?
  6. Cross-check `docs/plans/active/` for plans whose work has shipped on `main` — they should be moved to `completed/`. (`en-learn` handles the move during normal flow, but if the user shipped without invoking `en-learn`, garden catches it.)
  7. Cross-check `AGENTS.md` and `CLAUDE.md` against current `docs/` structure — pointer-map drift.
  8. Categorize findings strictly into doc batches; surface code-level findings to `tech-debt-tracker.md`:
     - `chore(docs): fix broken cross-refs in foundation.md`
     - `chore(arch): document new ProvidersV2 boundary in docs/architecture.md`
     - `chore(plans): move FR07 to completed/`
     - `chore(learnings): add missing back-refs in patterns/`
     - `chore(learnings): archive 4 superseded entries`
     - `chore(maps): update AGENTS.md pointer to new docs/references/ entry`
  9. For each batch, open a focused PR with a single conventional commit.
  10. Each PR runs `en-review` automatically. If `en-review` returns clean (no P0/P1 findings), the PR auto-merges.
  11. If `en-review` finds anything, the PR stays open for human resolution.
  12. Summary report posted as a comment on the original triggering PR: what was fixed, what was deferred to `tech-debt-tracker.md`, what needs human judgment.
- **What goes to `tech-debt-tracker.md` instead of a garden PR.** Anything that requires modifying source code, config, or tests. Examples: "this helper duplicates `formatDate` in `src/utils/`", "Routes module imports from Config layer — violates layer rule", "test coverage gap on payment retry path." These get appended with category, severity, file paths, and date. `en-plan` reads `tech-debt-tracker.md` when planning new work.
- **Cross-review.** Off by default. Each garden PR goes through `en-review` (in `mode:report-only`), which is the quality gate.

##### CI execution model

A slash command is an interactive-host concept, not a CI executable. The GitHub Action workflow doesn't invoke `/en-garden` literally — it runs a wrapper command that maps to the host CLI's headless mode.

**Wrapper resolution (in CI runner):**

```bash
# bin/en-garden-ci  (installed by ./setup; lives in the plugin's bin/)
# Resolves which CLI is available in the runner and invokes it headlessly.

if command -v claude >/dev/null 2>&1; then
  claude -p --output-format json \
    --max-turns 50 \
    --skill en-garden \
    "$@"
elif command -v codex >/dev/null 2>&1; then
  codex exec --json --skill en-garden "$@"
else
  echo "ERROR: en-garden requires claude or codex CLI in the CI runner. Install one." >&2
  exit 1
fi
```

**Required runner environment:**
- One of `claude` or `codex` on PATH.
- LLM provider auth: `ANTHROPIC_API_KEY` (or OAuth via `claude` setup) for Claude; equivalent for Codex.
- `GITHUB_TOKEN` (auto-provided by GitHub Actions) for opening PRs.
- Default timeout: **30 minutes**. Hard cap, configurable via workflow input.
- Non-interactive — the wrapper passes `-p` (Claude) or `exec` (Codex), and the skill operates without `AskUserQuestion`/`request_user_input` calls.

**Branch naming for garden PRs:** `en-garden/<source-merge-sha-short>/<batch-name>` (e.g., `en-garden/a3f1b9c/architecture-doc-update`).

**Fallback if no CLI is available:** the workflow fails with a clear error and posts a comment on the source PR. Does not block the source PR; just notifies the user that garden is non-operational until a CLI is installed in the runner.

##### Loop guards (preventing self-trigger cascades)

Garden runs on `push` to `main`. Its auto-merging PRs are themselves pushes to `main`. Without guards, this creates an infinite loop. Five guards in place:

1. **Skip garden-authored commits.** The workflow's first step inspects `${{ github.event.head_commit.author.name }}` and `${{ github.event.head_commit.message }}`. If the author is `ensemble-garden[bot]` *or* the message starts with `chore(en-garden):`, exit immediately (status: skipped).
2. **Concurrency group.** GitHub Actions `concurrency:` keyed on `en-garden-${{ github.ref }}` with `cancel-in-progress: false` — only one garden run per branch at a time. Subsequent triggers queue, not stack.
3. **Garden PR labeling.** Every garden-opened PR carries the label `en-garden`. The workflow's first step also exits immediately if the merge that just happened was a PR carrying this label (detected via `gh pr view --json labels`).
4. **No-material-diff termination.** After running all checks, if no fix-PR batches were generated, exit silently. No notification, no commit, no PR.
5. **Recursion depth cap.** The workflow checks `${{ env.ENSEMBLE_GARDEN_DEPTH }}`; defaults to `0`, increments on each spawn. Hard cap at depth 1 — garden never spawns garden. (Defense-in-depth; guards 1+3 should already prevent this.)

##### Doc-only enforcement at runtime

Garden is contractually doc-only (D27). Implementation enforces this with a runtime guard:

- After staging files for a PR, the workflow runs `git diff --cached --name-only` and verifies every changed path is under `docs/`, `AGENTS.md`, `CLAUDE.md`, or `.github/workflows/en-garden.yml`. Any path outside this allowlist → abort the PR creation, fail loudly with the offending path, and post to source PR.
- The allowlist is enforced in `bin/ensemble-doc-only-check`, called as a workflow step before `gh pr create`.

##### When `en-garden` invokes `en-review`

In CI, `en-garden` invokes `en-review` in `mode:report-only` (not the default interactive mode). Why:

- `en-review` in interactive/headless mode auto-applies `safe_auto` fixes, which would push another commit to the garden PR's branch. That's tolerable but adds noise.
- More importantly, allowing mutation in CI risks the gate making changes that then need re-review — recursive ambiguity.
- `mode:report-only` makes `en-review` strictly a verifier: it returns findings as JSON, no file edits. Garden parses the JSON and decides whether to auto-merge (clean) or leave open (P0/P1 findings).

This is documented in `en-review` (§5.2.5) and reinforced by `en-garden`'s wrapper passing `EN_REVIEW_MODE=report-only` when invoking it.

##### Auto-merge security model

Default-safe configuration:

- **Use `GITHUB_TOKEN` (auto-provided), not a PAT.** Least-privilege.
- **Workflow permissions** (declared in workflow YAML): `contents: write`, `pull-requests: write`, `issues: write` (for comments). No `actions: write`, no admin.
- **No fork-triggered runs.** Workflow uses `on: push: branches: [main]` only — never `pull_request_target` from forks (which would expose credentials to attacker-controlled code).
- **Branch protection respected.** If the repo's branch protection requires N reviews on PRs to `main`, garden PRs queue for review rather than auto-merge. Garden detects this via `gh api /repos/.../branches/main/protection` and exits gracefully if its PRs can't be auto-merged. Surfaces in the source-PR comment.
- **Doc-only enforcement** (above) prevents any source-file edit even if a finding mistakenly suggested one.
- **Auto-merge disabled on detection failure.** If any guard check errors out (rate-limited GitHub API, auth failure, allowlist check throws), garden leaves all PRs open for human review and does not auto-merge.

- **Reference files.**
  - `references/host-detect.md`
  - `references/garden-checks.md` (the catalog of doc drift checks)
  - `references/garden-trigger-workflow.yml` (template `.github/workflows/en-garden.yml` installed by setup)
  - `references/garden-loop-guards.md` (the five guards above)
  - `references/garden-security-model.md` (permission model + fork policy)
  - `references/tech-debt-tracker-format.md` (entry schema for code-level findings)
  - `references/doc-lints.md` (shared with `en-review`)
  - `bin/en-garden-ci` (the CLI wrapper)
  - `bin/ensemble-doc-only-check` (runtime allowlist enforcement)

#### 5.2.11 `en-setup`

- **Purpose.** Project-level bootstrap and diagnostics. Distinct from the global `./setup` script (which installs Ensemble onto a machine) — this skill prepares a *repository* for Ensemble. Runs three different flows based on detected state.
- **State detection.** Determined by which artifacts are present in the repo. Trigger for State 2 ("needs Ensemble bootstrap") is *missing `docs/foundation.md` OR missing `docs/learnings/`*, regardless of whether `AGENTS.md` or `CLAUDE.md` already exist.

  | State | Repo signals |
  |---|---|
  | **State 1 — New project** | Repo is empty or initial-commit only, AND `docs/foundation.md` doesn't exist |
  | **State 2 — Existing project, no Ensemble** | Repo has source code AND (`docs/foundation.md` is absent OR `docs/learnings/` is absent). May or may not have `AGENTS.md`/`CLAUDE.md` already |
  | **State 3 — Existing project with Ensemble** | `docs/foundation.md` exists AND `docs/learnings/` exists. All Ensemble bootstrap artifacts already present |

- **State 2 sub-variants** (each handled differently when generating maps):

  | Variant | What's already there | AGENTS.md action | CLAUDE.md action |
  |---|---|---|---|
  | 2a | Neither AGENTS.md nor CLAUDE.md | Generate from template | Generate from template |
  | 2b | CLAUDE.md only (no AGENTS.md) | Generate AGENTS.md from template; cross-reference existing CLAUDE.md | Append-merge: keep existing content; append Ensemble Claude-specific section if not present |
  | 2c | AGENTS.md only (no CLAUDE.md) | Append-merge: keep existing content; append Ensemble pointer index if not present | Generate from template (one-line cross-ref to AGENTS.md + Claude-specific guidance) |
  | 2d | Both AGENTS.md and CLAUDE.md | Append-merge each: keep existing content; append Ensemble pointer index / Claude-specific section if not present. Never overwrite existing user content. | Same |

- **Process per state.**
  - **State 1 — Greenfield handoff.** Don't pre-create artifacts. Recommend the user start with `/en-brainstorm` to explore the idea, then proceed to `/en-foundation` to establish the foundation document and emit the `FR01-project-setup` plan (per A1). `en-setup` doesn't own greenfield bootstrap; `/en-foundation` does, with `/en-brainstorm` typically preceding it. Output a one-paragraph guide naming both skills and the order.
  - **State 2 — Retrofit bootstrap.** Run all of these in order:
    1. **Detect State 2 sub-variant** (2a / 2b / 2c / 2d) and stage the `AGENTS.md` / `CLAUDE.md` actions accordingly.
    2. **Create directory skeleton:** `docs/{plans/{active,completed},learnings/{bugs,patterns,decisions,sources},references,generated,designs}/`. Seed `docs/learnings/index.md` and `docs/learnings/log.md` with empty templates.
    3. **Generate or merge `AGENTS.md`** per the sub-variant. When merging, never overwrite existing user content — append the Ensemble pointer index as a new section if one isn't already present.
    4. **Generate or merge `CLAUDE.md`** per the sub-variant. Same merge discipline. The first line must be the cross-reference to `AGENTS.md` (per D15); if an existing `CLAUDE.md` doesn't have it, prepend it. Append-merge any Claude-Code-specific Ensemble guidance into a new section.
    5. **Add `.gitignore` entries:** `.ensemble/config.local.yaml`. Optionally `docs/learnings/archive/` (ask the user — depends on whether the team wants archived learnings tracked in git).
    6. **Install `.github/workflows/en-garden.yml`** from `references/templates/github-workflow-en-garden.yml`. Surface required permissions/secrets per A20 in the same step.
    7. **Create `.ensemble/config.local.example.yaml`** (committed) with the full set of available settings. **Offer to create `.ensemble/config.local.yaml`** (gitignored) — ask the user; if accepted, copy from example and uncomment the most-likely-relevant defaults.
    8. **Recommend next steps.** Output a one-paragraph guide. Two paths:
       - "Run `/en-foundation` to retrofit `docs/foundation.md` and `docs/architecture.md` from your existing code." (Recommended for projects that will see continuing development with Ensemble.)
       - "Or jump straight to `/en-plan` for your next feature — `en-foundation` can be filled in later as you go." (For projects that want to start using Ensemble immediately on a feature without a full retrofit pass.)
  - **State 3 — Diagnostic mode.** Run health checks: are all required directories present? Are `AGENTS.md` and `CLAUDE.md` current (no doc-lint failures)? Is `.github/workflows/en-garden.yml` installed? Is `bin/ensemble-lint` available? Are required CLIs (`gh`, `git`, `jq`) on PATH? Are MCP servers (Playwright, Context7) configured? Is the plugin version current? Mirrors CE's `scripts/check-health` pattern. Offer repairs for missing pieces.

- **Output.** A diagnostic report with `🟢` / `🟡` / `🔴` per check, plus any artifacts created or repaired. Recommends next-step skill (per state).
- **Cross-review.** Off — mechanical setup work, no peer review needed.
- **Reference files.**
  - `references/host-detect.md`
  - `references/templates/agents-md-template.md`
  - `references/templates/claude-md-template.md`
  - `references/templates/agents-md-merge-rules.md` (append-merge logic for variants 2b–2d)
  - `references/templates/github-workflow-en-garden.yml`
  - `references/templates/config-local-example.yaml`
  - `references/setup-state-detection.md` (state-1 / state-2 sub-variants / state-3 heuristics)
  - `scripts/check-health` (the diagnostic runner)

---

## 6. Agent Catalog

Eleven agents total: 7 reviewers (read-only) + 3 researchers (read-only) + 1 refiner (read-write). Short specialist prompts (~40–120 lines each), not multi-thousand-line monsters. Skills dispatch them via the platform's task primitive (Claude Code Agent tool, Codex `spawn_agent`).

### 6.1 Reviewer agents (7)

**Always-on (4):**

| Agent | Focus | Dispatched by |
|---|---|---|
| `correctness-reviewer` | Logic errors, edge cases, state bugs, error propagation, off-by-one | `en-review`, `en-build` (per-unit) |
| `testing-reviewer` | Coverage gaps, weak assertions, brittle tests, missing categories | `en-review`, `en-build` (per-unit) |
| `maintainability-reviewer` | Coupling, complexity, naming, dead code, abstraction debt | `en-review` |
| `standards-reviewer` | CLAUDE.md / AGENTS.md compliance, repo conventions, file naming | `en-review` |

**Conditional (3) — fire when the diff matches:**

| Agent | Fires when diff touches | Dispatched by |
|---|---|---|
| `security-reviewer` | Auth, public endpoints, user input, secret handling, permissions | `en-review` |
| `performance-reviewer` | DB queries, hot paths, async, caching, data transforms | `en-review` |
| `migrations-reviewer` | Schema changes, migrations, backfills, data isolation | `en-review` |

### 6.2 Research agents (3)

| Agent | Purpose | Dispatched by |
|---|---|---|
| `repo-research` | Scan codebase for patterns, conventions, file paths, existing implementations | `en-plan`, `en-foundation`, `en-garden`, `en-learn` (for `docs/architecture.md` sync) |
| `learnings-research` | Query `docs/learnings/` for relevant past bugs, patterns, decisions | `en-plan`, `en-review`, `en-brainstorm`, `en-foundation` |
| `web-research` | External docs (Context7) and best-practice search (WebSearch); URL fetch for ingested sources. Optional. | `en-plan`, `en-brainstorm`, `learn --pack`, `learn ingest <url>` |

### 6.3 Refiner agents (1)

Distinct from reviewers (which return findings) and researchers (which return data) — refiners *modify* code directly and return a diff summary.

| Agent | Purpose | Dispatched by | Source |
|---|---|---|---|
| `code-simplifier` | Refine recently modified code for clarity, consistency, and project-standards compliance while preserving exact functionality. Reduces nesting, eliminates redundancy, applies CLAUDE.md / AGENTS.md conventions, avoids over-simplification (no nested ternaries, no clever-at-cost-of-readable). Model: opus. | `en-build` (per unit, before peer review) | [Anthropic claude-plugins-official](https://github.com/anthropics/claude-plugins-official/blob/main/plugins/code-simplifier/agents/code-simplifier.md) |

### 6.4 Agent invariants

- **Reviewer and research agents are read-only.** They never edit files; they return structured JSON. The orchestrating skill applies any fixes.
- **Refiner agents may write files**, but the orchestrating skill *must* run verification (project tests + lint) immediately after the refiner completes. If verification fails, the skill reverts the refiner's changes (`git restore` or equivalent) and proceeds with the original implementation. This is the safety contract that lets us trust a code-modifying agent.
- **Each reviewer agent returns:** `findings[]` (with severity, confidence, location, why-it-matters, suggested-fix) plus `summary`.
- **Each refiner agent returns:** `summary` (1–3 sentences on what it changed and why) plus `changes_made[]` (significant changes with file paths). The orchestrating skill posts this in its progress report.
- Confidence ≥ 7 surfaces in main report; 5–6 surfaces with caveat; <5 suppressed unless severity would be P0.
- No agent invokes another agent. Skills orchestrate.

---

## 7. Cross-Agent Peer Review

### 7.1 The mechanism

Cross-review is implemented via subprocess CLI calls, not in-process. Both Claude Code (`claude -p`) and Codex (`codex exec`) accept a prompt and return text or JSON. Skills shell out via Bash.

**Two modes, one contract:**

- **Cross-agent (preferred).** Both CLIs are installed. Host runs in CLI A; peer review runs in CLI B (the other one). Different models, different blind spots — this is the full-strength version.
- **Single-agent fallback.** Only one CLI is installed. Host shells out to a fresh instance of its own CLI for the review. Same model, fresh context — still catches things the implementing session rationalized away (this is the same principle Superpowers' subagent-driven-development uses). Degraded vs cross-agent because same model means same systematic biases. The peer prompt is augmented with explicit "be more aggressive, bias toward finding problems" framing to maximize the fresh-context advantage. The peer's JSON response carries `peer_mode: "single-agent-fallback"` so the user knows which mode they're in.

Both modes detect at host-detect time and use exactly the same JSON-only contract:

**Peer responsibility model (the core contract — see D30).** The peer agent **only reports findings** in structured JSON. It does **not** edit files, run commands, modify git state, or make commits. The host (the skill-running agent) is the sole code-modifier — it parses the peer's findings, decides which it agrees with, and applies the agreed ones. This holds for every cross-review invocation across every skill, *regardless* of whether the peer is cross-agent or single-agent fallback.

Why this matters:

- **No two-agent races on the same files.** Only one agent ever holds the write pen.
- **Peer is stateless and bounded.** It just reads inputs and returns findings. Cheap to run, parallelizable, easy to retry.
- **Host has agency.** It applies its own judgment over the peer's recommendations — accepting some, deferring some to `tech-debt-tracker.md`, disagreeing with others — rather than blindly applying everything the peer says.
- **The user stays in the loop only when contention emerges** (host disagrees with a P0, host wants to defer a high-confidence security finding). Otherwise the host operates autonomously.

The Outside Voice prompt template (Appendix A) bakes in the no-modify constraint at the prompt level, so the peer is told explicitly it must not edit, write, or run commands.

### 7.2 When it fires

| Skill | Default | Override |
|---|---|---|
| `en-brainstorm` | Off | `--peer` to enable |
| `en-foundation` | **On** | `--no-peer` to disable |
| `en-plan` | **On** | `--no-peer` to disable |
| `en-build` | **On per unit** | `--no-peer-per-unit` to disable; `--peer-final-only` for single end-of-build pass |
| `en-review` | Off | `--peer` to enable |
| `en-qa` | Off | `--peer` to enable |
| `en-learn` | Off | `--peer` to enable |
| `en-ship` | Off | n/a |
| `en-cross-review` | Always on | n/a |

### 7.3 Build flavors driven by host detection

```
HOST = claude-code (in CC) → flavor = build-by-orchestration
   • Claude orchestrates
   • Per unit: dispatches `codex exec` to implement
   • Per unit: reviews Codex's diff itself, asks Codex for fixes if needed
   • Commits in Claude's working tree

HOST = codex (in Codex) → flavor = build-handoff
   • Codex executes units natively
   • End of batch: dispatches `claude -p` for review
   • Codex applies agreed-with feedback before final commit
```

### 7.4 Recursion guard

When a skill invokes the peer agent, it sets `ENSEMBLE_PEER_REVIEW=true` in the subprocess environment. Every skill checks for this on entry and skips its own Outside Voice phase if set. This prevents infinite cross-review loops.

### 7.5 Cost controls

- **Default to mid-tier model on the peer.** Configurable via `~/.ensemble/config.json` (`peer_model_codex`, `peer_model_claude`). Defaults: `gpt-5-codex-mini` for Codex, `claude-sonnet-4-6` for Claude.
- **Skip on Lightweight tier.** Renames, typos, config-only changes don't get peer-reviewed.
- **Skip on artifacts <50 lines.** Below that threshold the cross-review costs more than it adds.
- **Wall-clock cap of 10 minutes.** Subprocess timeout. On timeout, surface and continue without.
- **Cache the artifact body** to disk (`/tmp/ensemble/peer-review/<run-id>.txt`); retries don't re-send.

### 7.6 Verdict handling

Peer returns `verdict: "approve" | "revise" | "reject"` plus a `findings[]` array. The host (not the peer) is responsible for deciding what to do with them — see §7.1 *Peer responsibility model*.

Default host behavior:

- **approve** — no findings to act on; record verdict in artifact metadata; continue.
- **revise** — host walks each finding and chooses one of three responses per finding:
  1. **Agree and apply** — host modifies the artifact / code itself to address the finding. Note the action in the commit body or progress report.
  2. **Agree but defer** — finding is valid but out of scope for the current artifact. Append to the relevant tracker (`docs/plans/tech-debt-tracker.md` for code, `docs/plans/active/<plan>.md` Deferred section for plans, etc.). Move on.
  3. **Disagree with rationale** — host believes the peer is wrong; one-line rationale recorded; move on.
  - For artifact-modifying skills (`en-build`), if the host applied any changes, re-verify (run tests + lint) before committing. Failures revert the host's response-edits and surface to user.
- **reject** — pause and ask user. Do not auto-revise more than once without explicit confirmation.

**When the host surfaces a finding to the user despite default-autonomous behavior:**

- Peer reports P0 *and* host wants to disagree.
- Peer reports security or architectural finding with confidence ≥ 8 *and* host wants to defer.
- Peer reports verdict `reject`.

User-configurable in `~/.ensemble/config.json`: `peer_reject_behavior: "pause" | "auto-revise-once" | "auto-revise-twice"`.

### 7.7 Failure handling

- Peer CLI not installed → skip with note: "Peer CLI not found at $(which $PEER_CMD). Install $PEER to enable cross-review. Skipping for this run."
- Peer auth missing → skip with installation hint.
- Peer subprocess errors → log error, continue without cross-review.

---

## 8. Cross-Host Portability

### 8.1 Single source of truth

`references/host-detect.md` defines the detection logic and the variables every skill exports. Skills load it on demand, not at every invocation.

### 8.2 Detection variables

| Variable | Set by detect | Used for |
|---|---|---|
| `HOST` | `claude-code` or `codex` | Branching logic in skills |
| `PEER` | `codex`, `claude`, or `<same-as-host>` (fallback) | Display in messages |
| `PEER_MODE` | `cross-agent` or `single-agent-fallback` | Determines prompt augmentation; surfaced in progress reports |
| `PEER_CMD` | `codex exec`, `claude -p`, or `<host's own CLI>` (fallback) | Cross-review subprocess invocation |
| `PEER_OUTPUT_FORMAT` | `--json` or `--output-format json` | Flag for structured output |
| `PEER_AVAILABLE` | `true` or `false` | If `false`, skip cross-review entirely with note (effectively `peer_mode_override: "off"`) |
| `QUESTION_TOOL` | `AskUserQuestion` or `request_user_input` | Blocking prompts |
| `BLOCKING_QUESTION_AVAILABLE` | `true` or `false` | Fall back to numbered prose options if false |
| `TASK_TOOL` | `TaskCreate/TaskUpdate` or `update_plan` | Per-task progress tracking |

**Detection logic:**

1. Identify host via `CLAUDE_CODE_VERSION` / `CODEX_HOME` env vars (or inverse-CLI presence as fallback).
2. Check whether the *other* CLI is on PATH and authenticated:
   - If yes → `PEER_MODE=cross-agent`, `PEER_CMD` = the other CLI.
   - If no → `PEER_MODE=single-agent-fallback`, `PEER_CMD` = the host's own CLI (e.g., `claude -p` from within a Claude Code session).
3. Check `~/.ensemble/config.json` for `peer_mode_override`:
   - `"off"` → `PEER_AVAILABLE=false` (skip all cross-review with a one-line note).
   - `"cross-agent-only"` → fail with note if cross-agent isn't possible (don't fall back).
   - unset/`"auto"` (default) → use detected mode.

### 8.3 Tool name adaptations

Skills do not hard-code Claude Code tool names. Where a built-in differs across hosts:

| Function | Claude Code | Codex |
|---|---|---|
| Block-on user question | `AskUserQuestion` (deferred — preload via `ToolSearch`) | `request_user_input` |
| Update task list | `TaskCreate` / `TaskUpdate` / `TaskList` | `update_plan` |
| Spawn subagent | `Agent` tool with `subagent_type` | `spawn_agent` |
| Run shell command | `Bash` | `shell` |
| Read file | `Read` | `read_file` |
| Edit file | `Edit` | `apply_patch` |

The host-detect reference maps these consistently.

### 8.4 Path conventions

All file references in artifacts use **repo-relative paths** (e.g., `src/auth/middleware.ts`), never absolute. Absolute paths break worktree, multi-machine, and teammate portability.

---

## 9. Architecture

> **Intent vs reality.** This section captures Ensemble's *architectural intent* — what the toolkit was designed to be. The *current architectural reality* of any project that uses Ensemble lives in that project's own `docs/architecture.md`, maintained continuously by `en-learn` (event-driven) and `en-garden` (drift-driven). For Ensemble itself, once we start building, this section becomes the seed; the living architecture moves to `docs/architecture.md` at the repo root.

### 9.1 High-level component diagram

```
┌──────────────────────────────────────────────────────────────────┐
│  User                                                            │
└────────────┬─────────────────────────────────────────────────────┘
             │ slash command
             ▼
┌──────────────────────────────────────────────────────────────────┐
│  Host (Claude Code or Codex)                                     │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Skill (loaded from ~/.claude/skills/ or ~/.codex/skills/) │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │  references/  (loaded on demand)                     │  │  │
│  │  │   host-detect.md, outside-voice.md, templates...     │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  │                                                            │  │
│  │  Phase pipeline:                                           │  │
│  │   detect host → orient → discover → research → synthesize  │  │
│  │   → produce artifact → optional Outside Voice → hand off   │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Tool calls:                                                     │
│   • Read / Edit / Write / Bash / Grep / Glob                     │
│   • Agent dispatch (subagents)                                   │
│   • MCP tools (Playwright for QA, Context7 for docs)             │
│   • Subprocess to peer (codex exec / claude -p)                  │
└────────────┬─────────────────────────────────────────────────────┘
             │ writes
             ▼
┌──────────────────────────────────────────────────────────────────┐
│  Repo: docs/, src/, tests/                                       │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │  docs/foundation.md                                      │    │
│  │  docs/designs/*.md                                       │    │
│  │  docs/plans/FRXX-*.md                                    │    │
│  │  docs/learnings/{bugs,patterns,decisions}/*.md           │    │
│  │  docs/README.md (auto-index)                             │    │
│  └──────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
```

### 9.2 Data flow

```
brainstorm → docs/designs/*.md
                  │
                  ├──► foundation → docs/foundation.md ────┐
                  │                                        │
                  └──► plan ─────► docs/plans/FRXX-*.md ◄──┤
                                          │               │
                                          ▼               │
                                       build ─────► commits + branch
                                          │               │
                                          ▼               │
                                       review ───► review report
                                          │               │
                                          ▼               │
                                       qa ────────► bug-fix commits + tests
                                          │               │
                                          ▼               │
                                       learn ───► docs/learnings/**/*.md
                                          │               │
                                          ▼               │
                                       ship ────► PR / merge
                                          │               │
                                          └── learnings-research feeds back ──┘
                                                              into future plan/review
```

### 9.3 Skill ↔ agent dispatch matrix

| Skill | Agents it may dispatch |
|---|---|
| `en-brainstorm` | `web-research` (optional), `learnings-research` (optional) |
| `en-foundation` | `repo-research`, `learnings-research`, `web-research` (optional) |
| `en-plan` | `repo-research`, `learnings-research`, `web-research` (conditional) |
| `en-build` | `code-simplifier` (per unit, before peer review); orchestrates peer agent or operates inline |
| `en-review` | 4 always-on reviewers + 3 conditional reviewers + `learnings-research` |
| `en-qa` | none; uses Playwright MCP directly |
| `en-learn` | `repo-research` (for `docs/architecture.md` sync), `web-research` (for `--pack` and `ingest <url>` modes), Context Analyzer / Solution Extractor / Related Docs Finder sub-tasks (in-process) |
| `en-ship` | none; uses git + gh directly |
| `en-cross-review` | none; pure subprocess wrapper |
| `en-garden` | `repo-research` + invokes `en-review` on each batch PR (which dispatches its own personas) |

---

## 10. Artifact Directory and Stable IDs

### 10.1 Directory layout

```
<repo-root>/
├── AGENTS.md                           # ~100-line pointer map for any agent (Codex, Claude, …)
├── CLAUDE.md                           # cross-refs AGENTS.md + Claude-Code-specific guidance only
├── README.md                           # traditional human-readable project README (optional)
├── docs/
│   ├── foundation.md                   # product vision, decisions, technical direction, intent
│   ├── architecture.md                 # living architectural reality; updated by learn + garden
│   ├── golden-principles.md            # mechanical opinionated rules used by garden (optional)
│   ├── core-beliefs.md                 # agent-first operating principles (optional, advanced)
│   ├── quality.md                      # per-domain quality grades, drift tracking (optional)
│   ├── designs/                        # brainstorm outputs (decision artifacts)
│   │   └── 2026-04-28-<topic>-design.md
│   ├── plans/                          # feature/refactor plans (FRXX numbered)
│   │   ├── active/                     # in-flight; FRXX-<name>.md
│   │   ├── completed/                  # shipped; FRXX-<name>.md
│   │   └── tech-debt-tracker.md        # noticed-but-deferred items
│   ├── learnings/                      # compounding wiki — agent-maintained, interlinked
│   │   ├── index.md                    # content catalog the agent reads first; one-line per page
│   │   ├── log.md                      # append-only chronological record of every learn op
│   │   ├── bugs/
│   │   │   └── <slug>-<date>.md
│   │   ├── patterns/
│   │   │   └── <slug>-<date>.md
│   │   ├── decisions/
│   │   │   └── <slug>-<date>.md
│   │   ├── sources/                    # external sources brought in via learn ingest
│   │   │   └── <slug>-<date>.md
│   │   └── archive/                    # superseded entries (managed by learn --refresh)
│   ├── references/                     # pre-flattened external library docs
│   │   ├── index.md
│   │   ├── <library>-llms.txt
│   │   └── ...
│   ├── generated/                      # auto-derived; humans don't hand-edit
│   │   ├── db-schema.md
│   │   ├── plan-index.md
│   │   └── learning-index.md
│   └── README.md                       # human-readable index of docs/, auto-maintained
```

**Why this layout.** Root files are *agent discovery surfaces* — the first thing any agent reads when it joins a session. They are intentionally minimal. Everything else lives in `docs/`, the system-of-record directory, where `en-learn` and `en-garden` curate it continuously.

**Mandatory (every Ensemble project gets these — created by `/en-setup` State 2 or `/en-foundation` State 1):** `AGENTS.md`, `CLAUDE.md`, `docs/foundation.md`, `docs/architecture.md`, `docs/plans/active/`, `docs/plans/completed/`, `docs/learnings/{index.md,log.md,bugs,patterns,decisions,sources}/`, `docs/generated/{plan-index.md,learning-index.md}` (regenerated by `en-learn`), `docs/README.md`.

**Optional (added when valuable):** `docs/golden-principles.md` (recommended once `en-garden` is in regular use), `docs/core-beliefs.md` (Standard/Deep projects), `docs/quality.md` (large projects), `docs/references/` (added on first `en-learn --pack`), `docs/designs/` (added on first `en-brainstorm`).

**Note on `docs/generated/`.** Originally listed as optional but is now mandatory because `bin/ensemble-lint` requires `docs/generated/plan-index.md` and `docs/generated/learning-index.md` to exist for index-coverage checks (§18.1). `/en-setup` and `/en-foundation` seed the directory with empty stub indexes (frontmatter `generated: true` + zero entries); `/en-learn` regenerates them on every relevant write.

### 10.2 Stable IDs

| ID | Where assigned | Format | Stability rule |
|---|---|---|---|
| `R<N>` | `foundation.md` Section 5 (Functional Requirements) | `R1`, `R2`, … | Append-only. Removed requirements get marked deprecated, not deleted. |
| `A<N>` | `foundation.md` Section 3 (Users & Actors) | `A1`, `A2`, … | Append-only. |
| `F<N>` | `foundation.md` Section 6 (User Experience) | `F1`, `F2`, … | Append-only. |
| `AE<N>` | `foundation.md` Section 5 (Acceptance Examples) | `AE1`, `AE2`, … | Append-only. |
| `U<N>` | `docs/plans/FRXX-*.md` Implementation Units | `U1`, `U2`, … per plan | Never renumbered after assignment within a plan. Splitting keeps original ID on original concept. |
| `FR<NN>` | `docs/plans/FRXX-*.md` filename prefix | `FR01`, `FR02`, … | Auto-incremented from highest existing FRXX. |

### 10.3 Cross-references

- Plan units cite the requirement IDs they cover: `Requirements: R3, R7, AE2`.
- Tests cite acceptance examples they cover: `Covers AE2`.
- Commits include the U-ID in the message body: `feat(auth): add token refresh — U3`.
- Review findings cite the U-ID they relate to: `[P1] U5 — missing edge case for empty token`.

### 10.4 Protected paths

The following are pipeline artifacts. `en-review`, `en-qa`, `en-learn`, and `en-garden` will never flag them for deletion or gitignore:

- `AGENTS.md`, `CLAUDE.md` (repo root)
- `docs/foundation.md`, `docs/architecture.md`, `docs/golden-principles.md`, `docs/core-beliefs.md`, `docs/quality.md`
- `docs/designs/`
- `docs/plans/{active,completed,tech-debt-tracker.md}`
- `docs/learnings/` (including `index.md`, `log.md`, `archive/`, and `sources/` subcategory)
- `docs/references/`
- `docs/generated/`
- `docs/README.md`

Files in `docs/generated/` are auto-derived — doc lints flag any direct human edit and `en-garden` regenerates them.

---

## 11. Compounding Learning Store

### 11.1 What gets captured

- **Bugs.** Symptom, what didn't work (failed hypotheses), root cause, fix, why-it-works, prevention.
- **Patterns.** A reusable approach surfaced during build that should be applied elsewhere (e.g., "use `expectTypeOf` for type-only assertions in this project").
- **Decisions.** Architectural or technical choices with durable rationale (e.g., "chose Drizzle over Prisma because of edge-runtime support; see commit X").

### 11.2 Frontmatter schema (`docs/learnings/<category>/<slug>-<date>.md`)

```yaml
---
title: <one-line title>
date: YYYY-MM-DD
category: bugs | patterns | decisions
problem_type: <enum from references/learning-frontmatter-schema.md>
component: <module or area>
applies_when: <one-line description of when this applies>
tags: [...]
related: [<paths-to-other-learnings>]
confidence: <1-10>
status: active | deprecated | superseded
---
```

### 11.3 Query mechanism

`learnings-research` agent uses grep-first filtering on frontmatter fields, then reads only frontmatter (first 30 lines) of candidates to score relevance, and finally fully reads only the strong matches. This keeps token cost bounded.

### 11.4 Lifecycle

- **Capture.** `learn capture` (default mode) writes after a feature ships, a bug is fixed, or a synthesis worth keeping emerges in `en-plan` / `en-review` / `en-brainstorm` (`--from-conversation`).
- **Ingest.** `learn ingest <path-or-url>` brings external sources into the wiki — articles, papers, design references, customer-call notes. URL inputs use WebFetch with Wayback fallback; file inputs use Read.
- **Refresh.** `learn --refresh` audits content staleness across the store: keep, update, replace, or archive each learning.
- **Pack.** `learn --pack <library>` creates a flattened external reference at `docs/references/<library>-llms.txt`. Re-pack when the library version bumps or the cached docs go stale.
- **Lint.** `learn --lint` audits *structural* health of the wiki graph: orphans, missing back-refs, broken links, missing pages for frequently-cited concepts, contradictions, data gaps. `--lint --fix` auto-applies mechanical repairs; non-mechanical findings go to the user.
- **Surface.** `en-plan`, `en-review`, `en-brainstorm`, `en-foundation` query the store (and `docs/references/`) automatically. The `learnings-research` agent reads `docs/learnings/index.md` *first* to find candidate pages, then drills into them — Karpathy's pattern of indexing-as-cheap-RAG. Matches are surfaced in the artifact with a citation.

### 11.5 Architecture-doc sync (the second compounding loop)

`en-learn` updates `docs/architecture.md` after material structural change ships. `en-garden` checks `docs/architecture.md` against current code on every PR-merge run and opens fix-up PRs when they drift apart. Together they keep `docs/architecture.md` honest — anything in there is a current claim about the code, not a stale aspirational drawing.

What counts as material (rules in `references/architecture-update-rules.md`):

- A new top-level component, service, module, or package
- Removed component, retired service, dropped dependency
- Changed component boundary or layer
- New or removed external integration
- New infrastructure (queue, cache, worker, datastore)
- Database schema additions/removals at the entity level (not field tweaks)
- Auth, permission, or trust-boundary changes

Cosmetic refactors, internal renames, bug fixes, and pure test additions don't trigger an `docs/architecture.md` update.

### 11.6 Wiki maintenance — the LLM Wiki pattern

The learning store is treated as an interlinked wiki, not a flat collection of frontmatter files. Inspired directly by Karpathy's "LLM Wiki" pattern (April 2026): humans abandon wikis because *bookkeeping* (cross-refs, summaries, contradictions, consistency across pages) outpaces value. LLMs don't get bored — they touch 15 files in one pass — so the bookkeeping cost approaches zero and the wiki actually stays maintained.

**Active cross-reference maintenance (always-on in `capture` and `ingest`).** When a new entry is written:

1. Resolve `related: [...]` from the new entry's frontmatter.
2. For each related page, append a reciprocal back-reference. Forward refs without back-refs leave the graph one-directional and orphans accumulate.
3. Optionally, surface a one-line update to each related page where the new entry materially changes its claims (a contradiction, a stronger version of the same insight, a new example).

**Two helper artifacts:**

- **`docs/learnings/index.md`** — content catalog. Organized by category (`bugs/`, `patterns/`, `decisions/`, `sources/`). Each entry: link, one-line summary, date, `related-count`. Maintained by `en-learn` on every write. Read first by `learnings-research` agent before drilling into specific pages — keeps token cost bounded at moderate scale (~hundreds of pages) without embedding-based RAG infrastructure. Karpathy's observation: this approach scales surprisingly well; reach for vector search only when the store crosses ~500 entries.

- **`docs/learnings/log.md`** — append-only chronological record. Format: `## [YYYY-MM-DD] <op> | <subject>` (grep-friendly: `grep "^## \[" log.md | tail -5` gives recent activity). Every `en-learn` mode appends one line. Used by `--lint` to detect drift between log and store, and by `en-garden` to see "what's happened recently" without re-scanning.

**Structural health (`learn --lint`).** Distinct from `--refresh` (which is content staleness). Lint audits the wiki *graph*:

- Orphan pages (zero inbound references)
- Missing back-refs (asymmetric `related:` fields)
- Broken links (target file moved or deleted)
- Missing pages (concepts referenced by name in 3+ pages without a dedicated entry → suggest creating one)
- Contradictions (claims across pages that conflict — LLM judgment)
- Data gaps (thin areas that would benefit from `learn ingest` — suggest specific search queries)
- Index drift (entries in `index.md` that don't match underlying pages, or pages missing from `index.md`)
- Log drift (operations missing from `log.md`)

Mechanical findings auto-fix via `--lint --fix`. Judgment-required findings (contradictions, data-gap suggestions, missing-page candidates) go to the user.

**Capture-from-synthesis reflex.** `en-plan`, `en-review`, and `en-brainstorm` end with a soft "**Capture this as a learning?**" prompt when their final synthesis contains durable value (a comparison, a non-obvious connection, a pattern across multiple files, an extracted lesson). User accepts → `learn capture --from-conversation` files it. Without this, valuable syntheses disappear into chat history and the wiki misses content it should have.

---

## 12. Token-Efficiency Principles

| Principle | Mechanism |
|---|---|
| **Lean SKILL.md** | Target 150–400 lines. Process and decision logic only. |
| **External templates** | Templates and long checklists in `references/`. Loaded on demand. |
| **No bash preambles** | Brief mode/host-detection block (~10 lines), no telemetry, no auto-update. |
| **Light AskUserQuestion** | Recommendation + 2–4 options + one-line rationale. No heavy decision-brief format. |
| **Conditional dispatch** | Reviewer agents fire only when diff matches. Research agents fire only when local context is thin. |
| **Right-size by depth** | Lightweight / Standard / Deep classification scales question count, sections, agent dispatch. |
| **Skip cross-review on trivial work** | Lightweight tier and artifacts <50 lines skip Outside Voice. |
| **Mid-tier models as defaults** | Peer review and conditional reviewers default to mid-tier. Heavyweight only when explicitly requested. |
| **Headless mode** on `en-review`, `en-qa`, `en-learn`, `en-cross-review` | No AskUserQuestion overhead when called by other skills. |

---

## 13. Tech Stack and Dependencies

### 13.1 Required

- **At least one of:** Claude Code *or* Codex CLI. Either alone is sufficient — Ensemble runs cross-review in single-agent fallback mode when only one is installed (see D31 and §7.1).
- **Git** (>= 2.30 for worktree commands).
- **GitHub CLI (`gh`)** for `en-ship` PR creation.

### 13.2 Strongly recommended

- **Both Claude Code and Codex CLI installed**, for full cross-agent peer review. Single-agent fallback works but loses the different-model perspective; install both when you can.
- **Playwright MCP server** for `en-qa` browser testing.
- **Context7 MCP server** for `web-research` library/framework docs.

### 13.3 Optional

- **Bun / Node** if testing JavaScript projects via `en-qa`.
- **Worktree-friendly setup** for isolated parallel build dispatch.

### 13.4 Runtime configuration

`~/.ensemble/config.json`:

```json
{
  "peer_mode_override": "auto",
  "peer_model_codex": "gpt-5-codex-mini",
  "peer_model_claude": "claude-sonnet-4-6",
  "peer_reject_behavior": "pause",
  "peer_timeout_seconds": 600,
  "skip_peer_below_lines": 50,
  "skip_peer_on_lightweight": true,
  "default_branch_fallback": "main",
  "learnings_cross_project": false
}
```

**`peer_mode_override` values:**

- `"auto"` (default) — use cross-agent if both CLIs are installed, else fall back to single-agent.
- `"cross-agent-only"` — require cross-agent; if the other CLI isn't installed, skip cross-review entirely with a note.
- `"single-agent-only"` — always use single-agent fallback even if the other CLI is installed (useful for testing or to avoid two-CLI cost).
- `"off"` — disable cross-review across all skills.

### 13.5 Model and CLI specifics — verify during implementation

The model names referenced in this document (`gpt-5-codex-mini`, `claude-sonnet-4-6`) and CLI flag specifics (`--output-format json`, `--max-turns`, etc.) are *defaults to verify*, not promises. Both ecosystems evolve quickly. During implementation:

- All model names live in `~/.ensemble/config.json` (or the per-repo overrides) — never hard-coded in skills.
- CLI flag handling is isolated to a single wrapper file: `references/cli-wrappers.md` documents the canonical `claude -p` and `codex exec` invocations; skills consult this rather than embedding flag strings.
- Verification step in setup (`bin/ensemble-detect-host`) tests the actual flags work against the installed CLIs; surfaces deprecation warnings if a flag is rejected.
- When the underlying CLI changes a flag (or a model is retired), one update in `cli-wrappers.md` propagates to every skill.

This isolation matters because LLM provider CLIs change frequently and embedding flags throughout the codebase produces silent breakage.

---

## 14. Implementation Roadmap

### 14.1 Phase 0 — Foundations (this document + scaffolding)

- [x] Write `docs/foundation.md` (this file).
- [ ] Iterate with user on scope, naming, and architecture.

### 14.2 Phase 1 — Shared references

Build the cross-cutting references first so every skill reuses them:

- [ ] `references/host-detect.md`
- [ ] `references/outside-voice.md`
- [ ] `references/finding-schema.md`
- [ ] `references/severity-and-routing.md`
- [ ] `references/learning-frontmatter-schema.md`
- [ ] `references/learn-cross-ref-maintenance.md`
- [ ] `references/learn-index-format.md`
- [ ] `references/learn-log-format.md`
- [ ] `references/learn-ingest.md`
- [ ] `references/learn-lint.md`
- [ ] `references/architecture-update-rules.md`
- [ ] `references/agents-md-template.md`
- [ ] `references/claude-md-template.md`
- [ ] `references/architecture-template.md`
- [ ] `references/doc-lints.md`
- [ ] `references/code-simplifier-dispatch.md` (when to skip, what to pass, revert protocol)
- [ ] `bin/ensemble-lint` (the file-shape lint runner)

### 14.3 Phase 2 — Planning skills

In dependency order:

- [ ] `en-brainstorm` (lightest; fewest dependencies)
- [ ] `en-plan` (depends on host-detect, outside-voice, learnings-research agent)
- [ ] `en-foundation` (depends on host-detect, outside-voice, repo-research, learnings-research; produces `foundation.md` + `docs/architecture.md` + `AGENTS.md` + `CLAUDE.md`)

### 14.4 Phase 3 — Execution skills

- [ ] `en-build` (orchestration + handoff flavors)
- [ ] `en-review` (multi-persona dispatch, modes)
- [ ] `en-qa` (Playwright integration)

### 14.5 Phase 4 — Closure skills

- [ ] `en-learn` (5 modes: `capture` + `ingest <path-or-url>` + `--refresh` + `--pack` + `--lint`; cross-ref maintenance; `index.md` + `log.md` upkeep; `docs/architecture.md` sync; plan move active→completed)
- [ ] `en-ship` (commit/push/PR)
- [ ] `en-cross-review` (ad-hoc peer review)

### 14.6 Phase 5 — Maintenance skill

- [ ] `en-garden` (drift scan + cleanup PRs; depends on doc-lints, golden-principles, `docs/architecture.md`, repo-research)

### 14.7 Phase 6 — Agents

- [ ] 4 always-on reviewers (`correctness`, `testing`, `maintainability`, `standards`)
- [ ] 3 conditional reviewers (`security`, `performance`, `migrations`)
- [ ] 3 research agents (`repo-research`, `learnings-research`, `web-research`)
- [ ] 1 refiner agent (`code-simplifier`, sourced from Anthropic claude-plugins-official)

### 14.8 Phase 7 — Installation and project bootstrap

**Plugin distribution:**
- [ ] `.claude-plugin/plugin.json` — Claude Code plugin manifest
- [ ] `.claude-plugin/marketplace.json` — marketplace manifest (`manok4/ensemble`)
- [ ] `.codex-plugin/plugin.json` — Codex plugin manifest (where supported)
- [ ] `package.json` — version + metadata
- [ ] `README.md` — install instructions, two-path layout
- [ ] `CHANGELOG.md`

**Setup tooling:**
- [ ] `setup` (bash) — multi-host install script with `--host`, `--symlink`/`--copy`, `--verify-only`, `--quiet` flags
- [ ] `bin/ensemble-detect-host` — host-detect helper used by skills
- [ ] `scripts/check-health` — diagnostic runner used by `/en-setup` state-3 mode
- [ ] `scripts/sync-to-codex` — symlink/copy helper for Codex install

**Project bootstrap skill:**
- [ ] `en-setup` SKILL.md (state detection, three flows)
- [ ] `references/setup-state-detection.md` — the heuristics
- [ ] `references/templates/config-local-example.yaml` — committed template

**Optional:**
- [ ] Migration helper from `prod-dev-skills` to Ensemble (mapping old artifacts to the new layout)
- [ ] Light `hooks/hooks.json` (SessionStart) — only if needed; default off

---

## 15. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Cross-agent peer review costs balloon on large artifacts | Medium | Medium | Mid-tier defaults; size threshold; Lightweight skip |
| Codex CLI interface changes | Medium | Medium | Wrap CLI invocation in `references/outside-voice.md`; single update point |
| Recursion in cross-review | Low | High | `ENSEMBLE_PEER_REVIEW=true` env-var guard; checked at skill entry |
| Persona reviewers produce duplicate findings | High | Low | Synthesis layer with merge/dedup pipeline |
| Plan U-IDs accidentally renumbered during edits | Medium | Medium | Stability rule documented; `en-learn` audits on doc updates |
| Foundation document grows unwieldy | Medium | Medium | `en-learn` runs `--optimize` pass; archives stale decisions to `docs/learnings/decisions/` |
| Host detection fails on a fresh setup | Low | High | Fallback to "claude-code" with warning; explicit override via `ENSEMBLE_HOST` env var |
| Playwright MCP unavailable when `en-qa` runs | Medium | Low | Skip browser portion with note; system checks still run |
| Two-window build-handoff flow disorienting | Medium | Low | Default to build-by-orchestration; handoff opt-in |

---

## 16. Open Questions and Resolutions

### 16.1 Resolved (2026-04-28)

All initial open questions have been answered. Resolutions captured here for the decision log; the most architectural ones also propagated into D-IDs in §4.

- **Q1 → A1.** `en-foundation` emits an `FR01-project-setup` plan **only when starting a new project**. Detection: empty repo or no existing `docs/foundation.md`. Existing projects skip FR01 entirely.
- **Q2 → A2.** `en-build` derives batch size dynamically from the feature: tightly-coupled units batch together, independent units can be larger batches, complex/sensitive units (auth, payments, migrations) batch alone. No fixed default.
- **Q3 → A3.** `en-learn` runs automatically at the end of `en-build` and `en-qa`. Soft auto-invoke with a one-line announcement; user can decline.
- **Q4 → A4.** `en-cross-review` does not log prompts/responses to disk. Keep it lean.
- **Q5 → A5.** One round of cross-review per artifact. No multi-round verify.
- **Q6 → A6.** All skills prefixed `en-` (e.g., `/en-brainstorm`, `/en-build`, `/en-garden`). Underlying skill identifiers, directory names, and slash commands all use the prefix.
- **Q7 → A7.** Worktrees are opt-in per skill via the dispatching call, mirroring Compound Engineering's pattern (`isolation: "worktree"` on subagent dispatch). `en-build` is the primary user — opt-in when the build benefits from per-unit isolation.
- **Q8 → A8.** Peer reviewer is always the *other* agent, resolved by host-detect. Running `/en-build` from Claude Code → peer is Codex. Running `/en-build` from Codex → peer is Claude. Same rule for every peer-review invocation across every skill.
- **Q9 → A9.** `en-garden` triggers on **`push` to `main`** (i.e., right after a PR merges), not on a daily/weekly schedule. Installed as `.github/workflows/en-garden.yml` by the setup script. Manual invocation also supported.
- **Q10 → A10.** `en-garden` auto-merges its own PRs after `en-review` clears them, **and** `en-garden` is strictly doc-only. It never modifies source code, configuration, or tests. Code-level findings get filed to `docs/plans/tech-debt-tracker.md` for `en-plan`/`en-build` to handle later.
- **Q11 → A11.** `docs/core-beliefs.md` is seeded from a templated starter at `references/core-beliefs-starter.md`. User edits or extends after.
- **Q12 → A12.** `en-learn --pack <library>` always re-fetches and re-flattens. The user invokes it explicitly, so always-fresh is the right default.
- **Q13 → A13.** `en-learn ingest <url>` automatically tries the Wayback Machine if the original URL returns 403 / Cloudflare-blocked. Surfaces an error only if both fail.
- **Q14 → A14.** `en-learn --lint --fix` opens one PR per fix category (back-refs / broken-links / index-drift / etc.), mirroring `en-garden`'s pattern. Each PR is small and reviewable.
- **Q15 → A15.** Capture-from-synthesis is a **soft prompt** at the end of `en-plan`, `en-review`, `en-brainstorm`. Fires only when the final synthesis exceeds a structure/insight threshold; quietly skipped otherwise.
- **Q16 → A16.** `en-learn ingest` silently skips low-signal / off-topic sources with a one-line note ("This source appears off-topic for an engineering wiki — skipped. Re-run with `--force` to ingest anyway."). No thin summary written.

### 16.2 Resolved v1-implementation questions (2026-04-28)

- **Q17 → A17.** New-project detection in `en-foundation`: `docs/foundation.md` does not exist *and* repo has no source code outside `node_modules/`/`vendor/`/equivalents (or is in initial-commit state).
- **Q18 → A18.** Off-topic detector for `en-learn ingest`: LLM-judged relevance score against the project's `foundation.md`. Threshold: **0.3 / 1.0**. Below threshold → silently skip with note (per A16); `--force` overrides.
- **Q19 → A19.** `docs/plans/tech-debt-tracker.md` carries stable IDs `TD1`, `TD2`, … assigned append-only. `en-plan` cites them as `Resolves: TD7` in unit metadata when a plan addresses tracked debt.
- **Q20 → A20.** GitHub Action permissions/secrets for `en-garden` are documented during setup. The setup script generates a checklist (`docs/generated/garden-setup-checklist.md`) listing required workflow permissions, optional PAT for cross-repo PRs, and trigger configuration.

### 16.3 New questions

None outstanding — all initial questions and v1-implementation questions resolved. New ones will be added here as they surface during skill drafting.

---

## 17. Operating Philosophy

These are the principles that shape how every Ensemble skill behaves. They override surface-level tactics; if a tactic conflicts with one of these, the principle wins.

### 17.1 Failure means a missing capability, not "try harder"

When a skill fails (a plan misses requirements, `en-build` deadlocks, a review surfaces patterns it should have caught earlier, the agent does the wrong thing), the response is *not* to retry with stronger prompting. It is to ask: **"what capability is missing, and how do we make it both legible and enforceable for the agent?"**

Concretely, that means one of:

- A reference doc is missing → write it; cite it from the relevant SKILL.md.
- A learning is missing → run `learn capture` so future runs catch it.
- A persona reviewer is missing → add an agent with a focused remit.
- A lint is missing → add it to `references/doc-lints.md` and `bin/ensemble-lint`.
- A golden principle is missing → add it to `docs/golden-principles.md` so `en-garden` enforces it.
- A plan unit was too coarse → adjust the plan template's unit-granularity guidance.

This is the meta-loop. Every skill failure is feedback; every feedback gets encoded.

### 17.2 The repository is the system of record

If knowledge isn't in the repo, the agent can't see it. Slack discussions, design conversations in chat, decisions made in someone's head — all illegible. Anytime a durable decision happens in conversation, capture it (a learning, an `docs/architecture.md` update, a foundation amendment) before moving on. `en-brainstorm` and `en-plan` will reflexively offer to capture decisions that surface during their flows.

### 17.3 Map, not encyclopedia

Top-level docs (`AGENTS.md`, `CLAUDE.md`, `foundation.md`) are short and point to deeper sources of truth. SKILL.md files are the same — process logic in the file, templates and long checklists in `references/` loaded on demand. A doc that tries to be everything ends up being nothing — too long to read fully, too monolithic to keep current, too easy to ignore.

### 17.4 Boring tech is easier for agents

When choosing dependencies, frameworks, or patterns: composability, API stability, and strong representation in the training set matter more than novelty. If a "boring" library does the job, prefer it. If working around an opaque upstream library costs more than reimplementing a focused subset, reimplement.

### 17.5 Enforce boundaries centrally; allow autonomy locally

Mechanical enforcement of architecture, naming, and structural rules via lints, custom error messages, and `en-garden`. Within those boundaries, agents (and humans) get freedom in how they express solutions. The output doesn't have to match human stylistic preference — it has to be correct, maintainable, and legible to future agent runs.

### 17.6 Pay technical debt continuously, not in bursts

`en-garden` runs on every PR merge to `main`. Small, focused cleanup PRs. Auto-merge when `en-review` is clean. Never let cleanup become a once-a-quarter project — by then the drift has compounded and the rewrite is the easier-looking option, which is almost always wrong.

### 17.7 Throughput changes the merge philosophy

In a fast agent-driven loop, blocking gates that would be sensible at human pace become counterproductive. Test flakes get re-run; corrections are cheap; PRs are short-lived. This is opinionated and project-dependent — we recommend it but don't enforce it. Document the chosen merge philosophy in `AGENTS.md` so the agent knows.

---

## 18. Doc Lints

Mechanical checks on the knowledge store. Catch drift early, before it compounds.

### 18.1 What gets checked

- **Frontmatter validity.** Every artifact's frontmatter parses, has required fields, uses valid enum values (per `references/learning-frontmatter-schema.md`, etc.).
- **ID stability.** R-IDs in `foundation.md` are append-only (no renumbering). U-IDs in plans are stable (no renumbering after assignment). FRXX numbers are unique and contiguous-or-gap.
- **Cross-link integrity.** Every `(see R3)`, `(see U5)`, `(see FR07)`, `(see <path>)` resolves. Broken cross-refs are P1 lints.
- **Status correctness.** `docs/plans/active/*.md` files have `status: active`. `docs/plans/completed/*.md` files have `status: completed`. Mismatches are P1.
- **No absolute paths.** No artifact contains `/Users/...`, `C:\...`, or other absolute filesystem paths. Repo-relative only.
- **Freshness.** `docs/architecture.md` `updated:` field is within the freshness window (30 days by default, configurable). Stale → P2 advisory; very stale (90+ days) → P1.
- **Generated-file integrity.** Files in `docs/generated/` carry `generated: true` frontmatter and a generator-id; no human edits except via the generator.
- **Index coverage.** Every plan has an entry in `docs/generated/plan-index.md`; every learning in `docs/generated/learning-index.md`.
- **`CLAUDE.md` discipline.** First line of `CLAUDE.md` cross-references `AGENTS.md`. No heading or content block in `CLAUDE.md` duplicates `AGENTS.md` (rule: `claude-md.no-shared-content`). P1.
- **Map length budget.** `AGENTS.md` body ≤ ~150 lines (target 100); `CLAUDE.md` body ≤ ~80 lines (target 60). Soft limit, P2 advisory if exceeded.

### 18.2 Where it runs

- `en-review` runs lint as a pre-flight check on the diff. Lint failures surface as P1 findings.
- `en-garden` runs lint across the whole repo on every PR-merge pass and opens fix-up PRs.
- `en-garden` also invokes `learn --lint` (wiki-graph health) on the same pass, routing its output through the same PR-batching flow.
- Optionally as a CI step (recommended template at `references/ci-templates/lint.yml`).
- Manually: `bin/ensemble-lint [--scope docs/]`.

**Division of responsibility.** `bin/ensemble-lint` (this section's tool) handles *file-shape* checks — frontmatter validity, ID stability, cross-link integrity, status correctness, no-absolute-paths, freshness, generated-file integrity, index coverage, CLAUDE.md discipline, length budgets. `learn --lint` (§5.2.7 Mode E) handles *wiki-graph* checks — orphans, missing back-refs, contradictions, missing pages, data gaps. They complement each other; running both gives full coverage.

### 18.3 Output

Lint reports in JSON-lines format for machine consumption, with a markdown summary appended. Each violation:

```json
{
  "rule": "frontmatter.required-field-missing",
  "file": "docs/plans/active/FR03-auth.md",
  "severity": "P1",
  "message": "Missing required frontmatter field: covers_requirements",
  "remediation": "Add 'covers_requirements: [R<N>, ...]' citing requirements from foundation.md Section 5"
}
```

The `remediation` field is critical — it gives the agent a direct fix path without round-tripping to a human.

---

## 19. Installation and Project Setup

Ensemble is distributed as an installable plugin and supports two distinct setup phases: machine-level install (one-time) and project-level bootstrap (per-repo).

### 19.1 Repo layout

```
ensemble/
├── .claude-plugin/
│   ├── plugin.json                 # Claude Code plugin manifest
│   └── marketplace.json            # marketplace manifest (manok4/ensemble)
├── .codex-plugin/
│   └── plugin.json                 # Codex plugin manifest (when supported natively)
├── skills/                         # 11 skills
│   ├── en-brainstorm/
│   ├── en-foundation/
│   ├── en-plan/
│   ├── en-build/
│   ├── en-review/
│   ├── en-qa/
│   ├── en-learn/
│   ├── en-ship/
│   ├── en-cross-review/
│   ├── en-garden/
│   └── en-setup/
├── agents/                         # 11 agent definitions
├── references/                     # cross-skill references + templates
├── bin/
│   ├── ensemble-lint               # doc-shape lint runner
│   └── ensemble-detect-host        # host-detect bash helper
├── hooks/
│   └── hooks.json                  # optional SessionStart hook (light)
├── scripts/
│   ├── check-health                # used by /en-setup diagnostic mode
│   └── sync-to-codex               # symlink/copy helper for Codex install
├── docs/
│   └── foundation.md               # this document
├── setup                           # bash, multi-host install
├── package.json                    # version + metadata
├── README.md
├── CHANGELOG.md
└── LICENSE
```

### 19.2 Phase A — machine-level install (one-time per machine)

Two paths, both supported. **Path 1 (direct clone + `./setup`) is the preferred path** — it works on any host, handles multi-CLI installs in one pass, and gives the user the most predictable result. Path 2 (Claude Code marketplace) is the alternative for users who already live in the marketplace ecosystem and only run Claude Code.

**Path 1 — Direct clone + `./setup` (preferred).** Works whether or not the user has marketplace access; works for Claude Code, Codex, or both:

```bash
git clone https://github.com/manok4/ensemble.git ~/.ensemble-source
cd ~/.ensemble-source && ./setup
```

The `./setup` script:

- Auto-detects which CLIs are installed (`~/.claude/`, `~/.codex/`, neither, or both).
- Symlinks (or copies, on Windows) skills and agents into each detected host's skill directory.
- Verifies dependencies: `git` (>= 2.30), `gh`, `jq`. Warns about missing optional deps (Playwright MCP server, Context7 MCP server).
- **Surfaces single-agent fallback warning** if only one host CLI is detected (per D31 / §7.1). Doesn't block install.
- Builds `bin/ensemble-lint` (no compilation needed — bash + node).
- Verifies `~/.ensemble/config.json` exists; creates with defaults if absent.
- **Does not touch any project repository.** Project setup is Phase B.

Flags supported by `./setup`:

| Flag | Effect |
|---|---|
| `--host claude\|codex\|both\|auto` | Override detection; `auto` is default |
| `--symlink` / `--copy` | Force symlink (default Unix) or copy (default Windows) |
| `--verify-only` | Run dependency + install checks without making changes |
| `--quiet` | Suppress non-error output |

**Path 2 — Claude Code marketplace (alternative).** For users on Claude Code who prefer the marketplace UX:

```
/plugin marketplace add manok4/ensemble
/plugin install ensemble@ensemble
```

For Codex on the same machine, supplement with the sidecar install:

```bash
git clone --depth 1 https://github.com/manok4/ensemble.git ~/.codex/ensemble
ln -s ~/.codex/ensemble/skills ~/.codex/skills/ensemble
ln -s ~/.codex/ensemble/agents ~/.codex/agents/ensemble
```

Path 2 is fine when only Claude Code is in play, but Path 1 is recommended because it handles both hosts in a single operation and gives a uniform install layout.

### 19.3 Phase B — project-level bootstrap (per-repo)

Handled by the `/en-setup` skill (§5.2.11). Distinguishes three states; behavior per state is documented there. In short:

- **New project** → defer to `/en-foundation`, which owns greenfield bootstrap.
- **Existing project, no Ensemble** → create directory skeleton, generate `AGENTS.md` + `CLAUDE.md`, install GH Action workflow, set up `.ensemble/` config files. Recommend `/en-foundation --retrofit` for retrofit, or `/en-plan` to start a feature.
- **Existing project with Ensemble** → diagnostic mode. Health-check report. Repair missing artifacts.

### 19.4 Configuration files

| Path | Scope | Committed? | Purpose |
|---|---|---|---|
| `~/.ensemble/config.json` | Per-machine, all projects | No (lives in home) | Global preferences: peer mode, model defaults, timeouts (see §13.4) |
| `<repo>/.ensemble/config.local.yaml` | Per-developer per-repo | **No** (gitignored) | This developer's preferences for this project — overrides global config |
| `<repo>/.ensemble/config.local.example.yaml` | Per-repo, shared | **Yes** (committed) | Template showing all available settings; teammates copy to `config.local.yaml` |

**Gitignore entries** (added by `/en-setup` if missing):

```
.ensemble/config.local.yaml
docs/learnings/archive/   # optional, depending on whether the team wants archived learnings tracked
```

### 19.5 Update mechanism

| Host | Update path |
|---|---|
| Claude Code | Marketplace auto-update (or `/plugin update ensemble`) |
| Codex (clone install) | `cd ~/.codex/ensemble && git pull` |
| Direct-clone install | `cd ~/.ensemble-source && git pull && ./setup` |

The `/en-setup` skill in diagnostic mode (state 3) flags out-of-date plugin versions and suggests the appropriate update command.

### 19.6 What we're skipping (vs Gstack)

- **No silent auto-update at session start.** Adds wall-clock time to every session and pollutes context. Update is explicit.
- **No telemetry.** No analytics events on skill invocation.
- **No cross-machine memory sync.** Out of scope for v1; users who want this can use git for `~/.ensemble/` themselves.
- **No skill prefix toggling.** All skills are `en-*` consistently — no opt-out (per D22).

### 19.7 What we're skipping (vs Compound Engineering)

- **No multi-host converter (`bunx @every-env/compound-plugin install`).** Native plugin manifests for each supported host instead, plus the universal `./setup` script. Lower runtime complexity.
- **No nested marketplace layout (`plugins/<plugin-name>/`).** Single-plugin marketplace; flatten to `.claude-plugin/plugin.json` at repo root.

### 19.8 What we're skipping (vs Superpowers)

- **No host-by-host install instruction matrix in the README.** One canonical install path: direct clone + `./setup` (preferred per §19.2), with the Claude Code marketplace as the alternative for users who only need Claude Code support.
- **No mandatory PR template / contributor guidelines block.** Out of scope until we have community contributors.

---

## 20. Verification and Test Strategy

Ensemble is non-trivial software — the kind of system that needs its own tests, not just "trust the design." This section defines what gets tested, how, and at what depth.

### 20.1 Why this matters

Ensemble's failure modes are subtle and high-blast-radius:

- A doc-lint that mis-classifies a finding can fail every PR.
- A host-detect bug routes peer review to the wrong CLI — quietly misconfigured for weeks.
- An `en-garden` workflow that doesn't enforce doc-only could push a source-file edit unnoticed in a 3am auto-merge.
- A frontmatter schema regression invalidates every existing learning in `docs/learnings/`.

These aren't catchable by "we'll see if it works." They need explicit tests.

### 20.2 Test categories

| Category | What it covers | Where it lives |
|---|---|---|
| **Frontmatter golden tests** | Every artifact-type frontmatter schema has a known-good fixture and a known-bad fixture. Lint runs against both; pass set is exact, fail set has expected violations. | `tests/golden/frontmatter/` |
| **Doc-lint rule tests** | Every lint rule (`bin/ensemble-lint`) has a fixture pair: a passing case and a violating case. Each rule is independently testable. | `tests/lint/<rule-name>/` |
| **Host-detection tests** | Mocked env vars (`CLAUDE_CODE_VERSION`, `CODEX_HOME`, `ENSEMBLE_HOST`) and mocked CLI presence. Verify `HOST` / `PEER` / `PEER_MODE` / `PEER_CMD` resolve correctly across all combinations. | `tests/host-detect/` |
| **Cross-review parsing tests** | Mock `claude -p` and `codex exec` fixtures (record/replay JSON responses) covering: clean-approve, revise-with-findings, reject, peer-mode-fallback, malformed JSON, timeout. Verify host parses each correctly. | `tests/cross-review/fixtures/` + `tests/cross-review/parser/` |
| **`en-setup` state-detection tests** | Sample repos for State 1 / State 2 (variants 2a/b/c/d) / State 3. Verify `en-setup` detects state correctly and produces the expected artifacts. | `tests/en-setup/sample-repos/` |
| **`en-garden` dry-run batching tests** | Run `en-garden` against fixture repos with seeded drift. Verify: correct number of PRs, correct file allocation per PR, no source-file edits, loop guards reject self-triggered runs. | `tests/en-garden/dry-run/` |
| **Doc-only enforcement** | Adversarial fixture: a `garden` run that *attempts* to edit a source file. Verify `bin/ensemble-doc-only-check` rejects it and the workflow aborts. P0 regression test. | `tests/en-garden/doc-only-enforcement/` |
| **Auto-merge security** | Simulate fork-PR triggers, missing branch protection, missing GITHUB_TOKEN scope. Verify garden refuses to auto-merge in each unsafe configuration. | `tests/en-garden/security/` |
| **Stable-ID invariants** | Add a unit to a plan; remove a different unit; verify U-IDs do not renumber. Same for R-IDs in foundation, FRXX in plan filenames. | `tests/stable-ids/` |
| **Cross-ref reciprocity** | Create a learning with `related: [foo]`. Verify `learn capture` adds reciprocal `related: [<new>]` to `foo`'s frontmatter. | `tests/learn/cross-ref/` |

### 20.3 Mock CLI fixtures

The cross-review tests don't actually invoke `claude -p` or `codex exec` — they use replay fixtures.

- Each fixture is a JSON file: `tests/cross-review/fixtures/<scenario>.json`.
- Format: `{ "input_prompt_match": "<regex>", "exit_code": 0, "stdout": "<verbatim peer JSON response>", "stderr": "" }`.
- A test harness (`tests/lib/mock-peer.sh`) installs a wrapper on PATH that intercepts `claude -p` / `codex exec` and replays the fixture matching the input.
- Real CLI calls happen only in opt-in integration tests (`tests/integration/`), gated by env var `ENSEMBLE_RUN_INTEGRATION=1`.

This keeps the test suite hermetic, fast, and reproducible — but allows full end-to-end validation when explicitly requested.

### 20.4 Sample repos for `en-setup`

Each state gets a fixture repo under `tests/en-setup/sample-repos/`:

| Fixture | What it represents |
|---|---|
| `state-1-greenfield/` | Empty repo (only `.git/` and `README.md`). Verifies `/en-setup` recommends `/en-brainstorm` then `/en-foundation`, doesn't pre-create artifacts. |
| `state-2a-no-maps/` | Source code + `package.json`, no `AGENTS.md`/`CLAUDE.md`/`docs/`. Verifies skeleton creation + both maps generated from templates. |
| `state-2b-claude-only/` | Existing `CLAUDE.md` with custom user content. Verifies `AGENTS.md` is generated, `CLAUDE.md` user content is preserved with append-merge. |
| `state-2c-agents-only/` | Existing `AGENTS.md` with custom content. Verifies `CLAUDE.md` is generated, `AGENTS.md` user content is preserved with append-merge. |
| `state-2d-both-maps/` | Existing `AGENTS.md` and `CLAUDE.md` both with user content. Verifies both are append-merged; cross-reference line on `CLAUDE.md` is prepended only if missing. |
| `state-3-fully-set-up/` | Complete Ensemble project. Verifies diagnostic mode runs and reports clean. |
| `state-3-partial/` | Has `docs/foundation.md` but missing `docs/learnings/log.md`. Verifies diagnostic mode flags the gap and offers repair. |

### 20.5 Test execution

- **Local development:** `bun test` (or `npm test`) runs the full hermetic suite.
- **CI:** runs on every PR via `.github/workflows/ensemble-tests.yml` (a separate workflow from `en-garden`). Hermetic suite blocks merge; integration suite is opt-in via PR label.
- **Pre-release:** integration suite must pass before bumping the plugin version.

### 20.6 Golden-test failure protocol

If a doc-lint rule's golden test fails after a code change to the lint, **the lint code is wrong, not the fixture** — by definition. The fixture is the contract. Update the fixture only when the rule's intent has changed (and update both the passing and violating fixtures to match the new intent). Document the change in the test commit message: "lint(<rule>): change <X> behavior; fixtures updated to match".

This protocol prevents drift where lints "evolve" silently and the fixtures are ratcheted to whatever the implementation happens to do.

### 20.7 Roadmap impact

`tests/` is a Phase 1 deliverable. Tests get written **alongside** each reference, lint, and skill — not bolted on at the end. Specifically:

- Phase 1 (Shared references) writes the golden fixtures + frontmatter tests in lockstep with the schemas.
- Phase 2 (Planning skills) writes host-detect tests + sample-repo fixtures.
- Phase 3 (Execution skills) writes mock cross-review fixtures + parser tests.
- Phase 5 (Maintenance skill) writes the `en-garden` dry-run + doc-only enforcement + security tests.

Every skill ships with its tests as part of the same PR. PRs that don't include tests for new behavior fail `en-review` with a P1 finding (`testing-reviewer` agent).

---

## Appendix A — Outside Voice Prompt Template

Single source of truth for all peer-review prompts. Loaded by `references/outside-voice.md`.

```
You are reviewing a {ARTIFACT_TYPE} produced by another AI agent in a peer-review setup.

YOUR ROLE: REPORTER, NOT FIXER.

You will read the artifact and return findings as structured JSON. You will NOT:
  - edit, write, or modify any files
  - run any commands (build, test, lint, git, anything)
  - make any commits, branch changes, or git operations
  - take any action other than analyzing and reporting

The HOST agent that dispatched you owns all code modifications. Your job is to surface
findings; the host decides which to apply. If you start trying to fix things, you'll
race with the host on the same files. Don't.

{IF PEER_MODE == "single-agent-fallback":}
NOTE: SINGLE-AGENT FALLBACK MODE.
You are a fresh instance of the same model that wrote this artifact. The user does not
have a second CLI installed, so you are filling the cross-review role with a clean
context. Be more aggressive than usual: bias toward finding problems, assume the
implementing instance was tired and may have rationalized issues away. The fresh-context
advantage is what makes this useful — surface what a second pair of eyes would catch
even if the model is the same.
{ENDIF}

PROJECT CONTEXT:
{ONE_LINE_PROJECT_CONTEXT}

GOAL OF THIS ARTIFACT:
{ONE_LINE_GOAL}

ARTIFACT (verbatim):
---
{ARTIFACT_BODY}
---

RETURN VALID JSON ONLY (no prose outside the JSON):
{
  "verdict": "approve | revise | reject",
  "peer_mode": "cross-agent | single-agent-fallback",
  "summary": "<2-3 sentence overall assessment>",
  "findings": [
    {
      "severity": "P0|P1|P2|P3",
      "confidence": <1-10>,
      "title": "<short title>",
      "location": "<file:line or section name or 'global'>",
      "why_it_matters": "<1-2 sentence rationale>",
      "suggested_fix": "<concrete change the host could apply — describe, don't apply>"
    }
  ]
}

RULES:
- Critique only. Do not restate the artifact.
- No cosmetic findings (whitespace, bikeshedding).
- Skip findings with confidence below 5.
- Be direct. Don't hedge. State a position.
- "suggested_fix" is a description of what the host should do. You are not doing it.
- "peer_mode" must echo the mode the host passed in.
- If the artifact is solid, "verdict: approve" with summary and zero findings is correct.
- Output JSON only. No commentary, no preamble, no closing remarks.
```

---

## Appendix B — Host Detection Snippet

Single source loaded by every skill that needs cross-host portability. Lives at `references/host-detect.md`.

```bash
# Host detection for Ensemble skills.
# Run this at the start of any cross-host skill.

# 1. Identify HOST
if [ -n "$CLAUDE_CODE_VERSION" ] || [ -n "$CLAUDE_AGENT_NAME" ]; then
  HOST="claude-code"
  HOST_CMD="claude -p"
  HOST_FORMAT="--output-format json"
  OTHER="codex"
  OTHER_CMD="codex exec"
  OTHER_FORMAT="--json"
elif [ -n "$CODEX_HOME" ] || [ -n "$CODEX_VERSION" ]; then
  HOST="codex"
  HOST_CMD="codex exec"
  HOST_FORMAT="--json"
  OTHER="claude"
  OTHER_CMD="claude -p"
  OTHER_FORMAT="--output-format json"
elif [ -n "$ENSEMBLE_HOST" ]; then
  HOST="$ENSEMBLE_HOST"
  # ... user override
else
  # Best-effort fallback by inverse-CLI presence
  if command -v codex >/dev/null 2>&1 && ! command -v claude >/dev/null 2>&1; then
    HOST="codex"; HOST_CMD="codex exec"; HOST_FORMAT="--json"
    OTHER="claude"; OTHER_CMD="claude -p"; OTHER_FORMAT="--output-format json"
  else
    HOST="claude-code"; HOST_CMD="claude -p"; HOST_FORMAT="--output-format json"
    OTHER="codex"; OTHER_CMD="codex exec"; OTHER_FORMAT="--json"
  fi
fi

# 2. Read user override
PEER_OVERRIDE=$(jq -r '.peer_mode_override // "auto"' ~/.ensemble/config.json 2>/dev/null || echo "auto")

# 3. Detect peer mode
if [ "$PEER_OVERRIDE" = "off" ]; then
  PEER_MODE="off"
  PEER_AVAILABLE="false"
elif command -v "${OTHER_CMD%% *}" >/dev/null 2>&1; then
  # Other CLI is installed -> cross-agent mode
  PEER_MODE="cross-agent"
  PEER="$OTHER"
  PEER_CMD="$OTHER_CMD"
  PEER_FORMAT="$OTHER_FORMAT"
  PEER_AVAILABLE="true"
elif [ "$PEER_OVERRIDE" = "cross-agent-only" ]; then
  # User insists on cross-agent but it's not possible
  PEER_MODE="off"
  PEER_AVAILABLE="false"
  echo "WARNING: peer_mode_override=cross-agent-only but $OTHER CLI is not installed. Skipping cross-review." >&2
else
  # Fall back to fresh instance of host's own CLI
  PEER_MODE="single-agent-fallback"
  PEER="$HOST"
  PEER_CMD="$HOST_CMD"
  PEER_FORMAT="$HOST_FORMAT"
  PEER_AVAILABLE="true"
fi

echo "HOST: $HOST"
echo "PEER_MODE: $PEER_MODE"
echo "PEER: ${PEER:-<none>}"
echo "PEER_CMD: ${PEER_CMD:-<none>}"
echo "PEER_AVAILABLE: $PEER_AVAILABLE"
```

**Setup-script behavior.** On first install, the setup script runs the detection and warns if `PEER_MODE` is `single-agent-fallback`:

> "Only $HOST CLI detected. Ensemble will run cross-review as single-agent fallback (fresh instance of $HOST). For full cross-agent peer review, install the other CLI: <install instructions>. To silence this warning, set `peer_mode_override: \"single-agent-only\"` in `~/.ensemble/config.json`."

---

## Appendix C — Frontmatter Schemas

### C.1 `foundation.md` frontmatter

```yaml
---
project: <product name>
type: foundation
status: draft | active | archived
created: YYYY-MM-DD
updated: YYYY-MM-DD
owner: <name>
depth: lightweight | standard | deep
---
```

### C.1b `docs/architecture.md` frontmatter

```yaml
---
project: <product name>
type: architecture
status: seed | active
created: YYYY-MM-DD
updated: YYYY-MM-DD               # bumped by learn after every material structural change
last_drift_check: YYYY-MM-DD      # bumped by garden on every PR-merge pass
freshness_target_days: 30
---
```

### C.1c `AGENTS.md` frontmatter

```yaml
---
project: <product name>
type: agent-map
host: any
created: YYYY-MM-DD
updated: YYYY-MM-DD
target_length_lines: 100
---
```

**`AGENTS.md` content rules.** Host-agnostic. The canonical project map. Indexes `docs/foundation.md`, `docs/architecture.md`, `docs/plans/active/`, `docs/learnings/`, `docs/references/`. Lists project commands, conventions, entry points. Read by Codex, Claude Code, and any other agent.

### C.1d `CLAUDE.md` frontmatter

```yaml
---
project: <product name>
type: agent-map
host: claude-code
created: YYYY-MM-DD
updated: YYYY-MM-DD
target_length_lines: 60
references: ./AGENTS.md
---
```

**`CLAUDE.md` content rules — strict.**

- **First line**, exactly:

  ```markdown
  > See [AGENTS.md](./AGENTS.md) for the project map and shared agent guidance.
  ```

- **Body** — Claude-Code-specific only. Allowed sections:
  - Slash command preferences for this project
  - Skill invocation priority
  - Auto-memory notes (`~/.claude/projects/.../memory/`)
  - Status line / hook references
  - Plugin / marketplace pointers
  - Tool-name notes specific to Claude Code (e.g., AskUserQuestion preload)

- **Forbidden in `CLAUDE.md`** (belongs in `AGENTS.md` instead): project structure, coding conventions, build / test / lint commands, architecture descriptions, anything Codex would also need.

- **Lint:** `claude-md.no-shared-content` parses both files and fails on any heading or content block in `CLAUDE.md` that duplicates `AGENTS.md`. P1 finding.

### C.2 `docs/designs/*.md` frontmatter

```yaml
---
type: design
created: YYYY-MM-DD
topic: <one-line topic>
status: open | accepted | superseded
related_plan: <FRXX or empty>
---
```

### C.3 `docs/plans/{active,completed}/FRXX-*.md` frontmatter

```yaml
---
type: plan
fr_id: FR<NN>
title: <descriptive title>
status: draft | active | completed | abandoned
location: active | completed             # mirrors directory; lint enforces match
created: YYYY-MM-DD
shipped: YYYY-MM-DD or empty             # set by learn when moved to completed/
deepened: YYYY-MM-DD or empty
covers_requirements: [R1, R3, R7]        # may be [] if requirements_pending: true
requirements_pending: true | false       # default false; true when foundation hasn't been retrofitted yet
related_design: <path to design doc or empty>
peer_review_verdict: approve | revise | reject | empty
---
```

**Requirements-traceability fallback for State-2 projects.** When an existing project starts using Ensemble before `/en-foundation` retrofits a `docs/foundation.md` with R-IDs, plans can carry `requirements_pending: true` and `covers_requirements: []`. Doc lint emits a **P3 advisory** (not P1 blocker) for these plans, with a remediation message: "Run `/en-foundation` to retrofit requirements, then backfill `covers_requirements`." Once `foundation.md` exists with at least one R-ID, lint upgrades the rule to P1 — every plan must cite at least one requirement after that point. Existing `requirements_pending: true` plans are migrated by `en-learn capture` (when run after a foundation-retrofit ships) which back-fills `covers_requirements` based on the plan's content and unsets `requirements_pending`.

### C.4 `docs/learnings/<category>/*.md` frontmatter

See [Section 11.2](#112-frontmatter-schema-docslearningscategoryslug-datemd).

---

> **Status: draft.** This document will iterate with the user before any skill or agent is implemented. The intent is alignment on shape and scope before code lands. See [Open Questions](#16-open-questions) for the items still being decided.
>
> **Iteration log.**
> - 2026-04-28 (initial): wrote foundation v0 — 9 skills, 10 agents.
> - 2026-04-28 (revision 1): added `en-garden` as skill #10; folded `pack-reference` into `learn --pack`; promoted architecture to a first-class living artifact (initially placed at root); added `AGENTS.md`/`CLAUDE.md` as project-level pointer maps; split plans into `active/` and `completed/`; added doc lints (§18); added Operating Philosophy (§17). Sources: harness-engineering essay (OpenAI, Feb 2026).
> - 2026-04-28 (revision 2): moved architecture from `/ARCHITECTURE.md` (root) to `docs/architecture.md` for layout consistency (root keeps only agent-discovery files: `AGENTS.md`, `CLAUDE.md`, `README.md`); added strict CLAUDE.md content rules (cross-reference required, Claude-Code-specific only, no duplication of AGENTS.md content) and matching `claude-md.no-shared-content` lint; added `references/claude-md-template.md`.
> - 2026-04-28 (revision 3): adopted Karpathy's "LLM Wiki" pattern for `docs/learnings/`. Expanded `en-learn` from 3 modes (`capture` + `--refresh` + `--pack`) to 5 modes (added `ingest <path-or-url>` and `--lint`). Added always-on cross-reference maintenance (reciprocal back-refs after every write) and two new helper artifacts: `docs/learnings/index.md` (content catalog the agent reads first — Karpathy's tip that this scales surprisingly well at moderate scale and avoids embedding-based RAG) and `docs/learnings/log.md` (append-only chronological record, grep-friendly). New subcategory `docs/learnings/sources/` for external material brought in via `ingest`. `en-learn ingest` accepts both file paths and URLs (URLs use WebFetch with Wayback fallback for Cloudflare-blocked sites). Capture-from-synthesis reflex added to `en-plan`, `en-review`, `en-brainstorm`. `en-learn --lint` handles wiki-graph health (orphans, missing back-refs, contradictions, missing pages, data gaps); `bin/ensemble-lint` continues to handle file-shape checks. Added decisions D19–D21 and open questions Q13–Q16. Source: Karpathy gist (`gist.github.com/karpathy/442a6bf555914893e9891c11519de94f`).
> - 2026-04-28 (revision 4): closed all initial open questions Q1–Q16 and propagated architectural resolutions into new decisions D22–D28. Skill prefix `en-` adopted across all 10 skills. `en-garden` rewritten to be strictly doc-only and PR-merge-triggered (was: scheduled, allowed code refactors). `en-build` batch size is now dynamic per-feature (was: fixed default 3). `en-learn` auto-runs after `en-build` and `en-qa` (soft auto-invoke). `en-foundation` emits `FR01-project-setup` only for new projects. Cross-review peer is always the other agent via host-detect — no model-defaults table. Worktrees opt-in per dispatch (CE pattern). Added 4 new v1-implementation questions Q17–Q20.
> - 2026-04-28 (revision 5): closed Q17–Q20. Added `code-simplifier` as the 11th agent, sourced from Anthropic's claude-plugins-official. First refiner agent — modifies code rather than returning findings. New §6.3 Refiner agents category with stricter invariants (orchestrating skill must run verification immediately after, revert on test failure). Added decision D29: per-unit code-simplification pass during `en-build`, between verification-gate-1 (tests+lint) and per-unit Outside Voice review. Two verification gates protect against simplifier breakage. Skipped on trivial units or with `--no-simplify`. New reference `references/code-simplifier-dispatch.md`. Source: `github.com/anthropics/claude-plugins-official/.../code-simplifier.md`.
> - 2026-04-28 (revision 6): made the "peer reports, host applies" contract explicit and unambiguous (D30). Peer agents in any cross-review never modify files, run commands, or make commits — they only return structured findings. Host (the skill-running agent) is the sole code-modifier and decides per-finding: apply, defer to tracker, or disagree. User is surfaced only on contention (host disagrees with P0; host wants to defer high-confidence security/architecture finding; peer verdict = reject). Updated `en-build` per-unit flow with the three host responses and re-verification after host applies changes. Updated §7.6 Verdict handling. Baked the no-modify constraint into the Outside Voice prompt (Appendix A) so the peer is told its role explicitly. Prevents two-agent race on the same files.
> - 2026-04-28 (revision 7): clarified the symmetry between `en-build` flavors. Both flavors guarantee implementer ≠ reviewer. **Build-by-orchestration** (host = Claude in Claude Code): Claude dispatches Codex to implement each unit, then Claude reviews the returned diff itself — no separate subprocess for peer review because Codex already implemented and Claude is naturally reviewing. **Build-handoff** (host = Codex in Codex): Codex implements natively, then shells out `claude -p` per unit for peer-review findings; Codex parses JSON and applies what it agrees with. Removed leftover "end-of-batch" wording that conflicted with §7.2's per-unit default. Per-unit step now explicitly describes how peer review is invoked in each flavor.
> - 2026-04-28 (revision 8): added single-agent fallback for users who only have one CLI installed (D31). When only Claude Code or only Codex is available, cross-review degrades to a fresh-instance subprocess of the host's own CLI. Same model, fresh context — still catches what the implementing session rationalized away (Superpowers' subagent-driven-development pattern). The contract from D30 still holds: peer reports, host applies. Peer's JSON response carries `peer_mode: "cross-agent" | "single-agent-fallback"` so the user always knows which mode they're in. Single-agent prompt is augmented with explicit "be more aggressive, bias toward finding problems" framing. New config option `peer_mode_override: "auto" | "cross-agent-only" | "single-agent-only" | "off"`. Setup script warns when only one CLI is detected; doesn't block. Required dependencies relaxed: at least one of Claude Code or Codex (was: both). Both still strongly recommended for full cross-agent perspective.
> - 2026-04-28 (revision 9): added installation and project-setup design (§19). Hybrid distribution: Claude Code plugin marketplace as primary (lowest friction); direct git-clone + `./setup` script as universal fallback. Native plugin manifests per host (`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`) — no Bun-based converter (skipped CE's complexity). Added `en-setup` as the 11th skill — handles project-level bootstrap with three states: new project (defers to `/en-foundation`), existing-without-Ensemble (creates skeleton, generates `AGENTS.md`/`CLAUDE.md` from templates, installs GH Action), existing-with-Ensemble (diagnostic mode mirroring CE's `check-health` pattern). New config files: `~/.ensemble/config.json` (machine-global), `<repo>/.ensemble/config.local.yaml` (per-developer per-repo, gitignored), `<repo>/.ensemble/config.local.example.yaml` (committed template). Skipped: gstack-style auto-update polling, telemetry, cross-machine memory sync, skill prefix toggling. Updated §14 Phase 7 with concrete deliverables for plugin distribution + setup tooling + project bootstrap.
> - 2026-04-28 (revision 10): three corrections to the install/setup design. (1) Path 1 (direct clone + `./setup`) is now the *preferred* install path; Path 2 (Claude Code marketplace) is the alternative. Direct clone handles multi-host installs in one operation and works regardless of marketplace availability. (2) `/en-setup` State 1 (new project) now recommends `/en-brainstorm` first, then `/en-foundation` — captures the typical greenfield flow rather than jumping straight to foundation. (3) `/en-setup` State 2 (existing without Ensemble) refined to handle four sub-variants based on what's already present: 2a no maps, 2b CLAUDE.md only, 2c AGENTS.md only, 2d both. Append-merge discipline: never overwrite existing user content; append Ensemble pointer index / Claude-specific section as new sections only if missing. The State-2 trigger broadened to "missing `docs/foundation.md` OR missing `docs/learnings/`" regardless of map presence. Added `references/templates/agents-md-merge-rules.md` to the reference list.
> - 2026-04-28 (revision 11): Codex review pass — addressed nine cleanup items. **Consistency:** added `depth: deep` to foundation frontmatter (was failing the lint schema it was about to ship); D22 fixed from "ten skills" to "eleven"; UC5 prefixed `cross-review` → `/en-cross-review`; D2 paths now point at `docs/plans/active/` and `docs/plans/completed/`; §19.8 contradictory "marketplace primary" wording fixed to align with §19.2 (Path 1 preferred). **`en-garden` trigger normalization:** removed all stale "scheduled / cron / daily / weekly / scheduled pass" language; uniformly described as event-driven on `push` to `main`. **CI execution model for `en-garden`:** added subsection covering wrapper script (`bin/en-garden-ci`) that resolves `claude -p` or `codex exec`, required runner env (auth, timeout, branch naming), fallback when no CLI is available. **`en-garden` loop guards:** added five-guard mechanism (skip garden-authored commits, GH Actions concurrency group, garden-PR labeling, no-material-diff termination, recursion depth cap) preventing self-trigger cascades. **Doc-only enforcement at runtime:** `bin/ensemble-doc-only-check` allowlist enforces non-doc paths can't be staged. **Auto-merge security model:** explicit GITHUB_TOKEN least-privilege, no PAT default, no fork-triggered runs, branch protection respected, fail-closed on detection errors. **`en-review` mode contract:** spelled out three modes and which mode every caller uses — particularly that `en-garden` always uses `mode:report-only` so the gate doesn't mutate. **`en-build` flavor responsibilities:** distinguished WORKER dispatch (build-by-orchestration, may edit) from PEER-REVIEWER dispatch (build-handoff, must not edit per D30). Clarified D30 applies to peer-reviewer dispatch only. **New §20 Verification and Test Strategy:** golden frontmatter tests, doc-lint rule tests, host-detection tests, mock CLI fixtures (record/replay), sample repos for State 1/2a/2b/2c/2d/3, dry-run + doc-only enforcement + auto-merge security tests. Tests ship alongside each artifact, not bolted on at the end. **Design gaps:** `requirements_pending: true` frontmatter field for State-2 plans before foundation retrofit (P3 advisory; upgrades to P1 once foundation has R-IDs). `docs/generated/` promoted to mandatory with `plan-index.md` + `learning-index.md` seeded by setup. New §13.5 marks model names and CLI flags as defaults-to-verify, not promises — isolated to `references/cli-wrappers.md` so flag changes propagate from one update.
