---
project: Ensemble
type: foundation
status: draft
created: 2026-04-28
updated: 2026-04-28
owner: Mano K
depth: deep
plan_id_prefix: EN
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

1. **Document-as-source-of-truth.** Every phase produces a durable artifact (`AGENTS.md`/`CLAUDE.md`, `foundation.md`, `docs/architecture.md`, `docs/designs/*.md`, `docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md`, `docs/learnings/**/*.md`) and the next phase reads it. The repo is the system of record — anything not in the repo is illegible to the agent.
2. **Map, not encyclopedia.** Top-level `AGENTS.md` and `CLAUDE.md` are short pointer indexes (~100 lines) that lead the agent into deeper sources of truth in `docs/`. SKILL.md files follow the same principle — process logic in the file, templates and long checklists in `references/`.
3. **Cross-agent peer review.** Claude Code and Codex review each other's work via CLI subprocess at high-leverage gates: end of `en-plan`, per unit during `en-build`, and on demand via `/en-review --peer`.
4. **Compounding knowledge.** Every solved problem, pattern, and decision is captured in `docs/learnings/` with frontmatter, queryable by future runs. `en-learn` updates `docs/architecture.md` after material changes; `en-sweep` runs event-driven drift cleanup (on every PR merge to `main`) so doc debt gets paid down continuously.
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
- **G11.** A living `docs/architecture.md` that always reflects the current architectural reality of the project, maintained event-driven by `en-learn` and drift-driven by `en-sweep`.
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
- **UC5. Ad-hoc peer review.** `/en-review --peer <path|ref|branch>` to ship any artifact to the peer agent for an outside-voice critique. Merged into `/en-review` on 2026-09-01 (D54); it was a second copy of the same peer stack differing only in target resolution.
- **UC6. Documentation pass.** `en-learn` invoked standalone after a feature ships, or `learn --refresh` to update stale learnings.

### 3.3 Out of scope for v1

- Long-running autonomous loops (no `/lfg`-style orchestrator).
- Slack or external-system integration during planning.
- Multi-agent parallel implementation across more than two agents.

---

## 4. Product Decisions

### 4.1 Key decisions (D-IDs)

- **D1. Foundation captures intent; `docs/architecture.md` captures reality.** `foundation.md` holds product requirements, technical direction, and architectural intent (the vision and rationale at project start, plus durable decisions). `docs/architecture.md` is the living document that reflects the *current* state of the system — components, dependencies, layer rules, data flows. Foundation is the answer to "what did we set out to build and why"; `docs/architecture.md` is the answer to "what does the code actually look like today." Sections scale by depth.
- **D2. Plans, not feature docs.** Per-feature implementation plans live in `docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md` while in-flight, then move to `docs/plans/completed/` after `en-learn` flips them post-ship. The lifecycle is `draft → open → in_progress → completed`; `<PREFIX>` comes from foundation's `plan_id_prefix:` (default `FR`); `<plan_type>` is one of `feature` / `improvement` / `bug`. Each plan carries stable U-IDs per implementation unit. They become living documentation after `en-build` completes (per D16).
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
- **D13. `docs/architecture.md` as a living, code-accurate document.** Lives in `docs/` alongside other system-of-record artifacts. Pointed to from `AGENTS.md`. Initial draft seeded by `en-foundation` from the architectural intent. Continuously updated by `en-learn` after every material structural change ships (new module, changed boundaries, new infrastructure). Drift-detected and fix-PR'd by `en-sweep` on each PR-merge run.
- **D14. Scheduled doc-drift cleanup with activity gate (`en-sweep`).** A separate skill that runs on a configurable schedule (default weekly) with an activity gate that skips runs when no non-sweep commits have landed since the last sweep. Scans the repo against doc artifacts and lints, opens small doc-only PRs, and auto-merges them after `en-review` clears them. Manual invocation (`/en-sweep` or `workflow_dispatch`) also supported. Originally event-driven on every PR merge to `main`; revised to scheduled-with-gate on 2026-05-05 to address the cost concern that most merges introduce no detectable drift, making every-merge fire 70–90% wasted work.
- **D15. Project-level `AGENTS.md` and `CLAUDE.md` as map, not encyclopedia.** Two pointer documents at repo root, ~100 lines each. **`AGENTS.md`** is the canonical, host-agnostic map — it orients any agent (Codex, Claude Code, or otherwise) toward deeper sources of truth in `docs/`. **`CLAUDE.md`** opens with a one-line cross-reference to `AGENTS.md` and contains *only* Claude-Code-specific guidance (slash command preferences for this project, skill invocation priority, auto-memory notes, status line / hook references, plugin pointers). No content duplicated from `AGENTS.md`. Doc lint `claude-md.no-shared-content` flags any duplication. Both files created by `en-foundation`, kept current by `en-learn` and `en-sweep`.
- **D16. Plans split by lifecycle.** `docs/plans/active/` for in-flight plans, `docs/plans/completed/` for shipped ones, `docs/plans/tech-debt-tracker.md` as the canonical place for "noticed but deferred" items. `en-learn` moves plans from active to completed at ship time.
- **D17. ~~Pack-reference is a mode of `en-learn`, not a separate skill.~~ SUPERSEDED by EN14 (`--pack` removed; external docs are looked up during research, not stored).** `learn --pack <library>` fetches docs once via Context7 + WebSearch and writes a flattened `docs/references/<lib>-llms.txt`. `en-plan`, `en-build`, and `en-brainstorm` consult these local references before falling back to network calls.
- **D18. Mechanical doc lints catch drift before it compounds.** A small `bin/ensemble-lint` script + `references/doc-lints.md` enforces frontmatter validity, ID stability (R-IDs, U-IDs, FRXX), cross-link integrity, no-absolute-paths, status correctness on plans, freshness on `docs/architecture.md`. `en-review` runs lint as pre-flight; `en-sweep` opens fix-up PRs.
- **D19. Learning store as a wiki, not a flat list.** Adopt Karpathy's "LLM Wiki" pattern: the `docs/learnings/` directory is a structured, interlinked, agent-maintained knowledge base, not a dumb folder of frontmatter files. New entries actively walk related pages and add reciprocal back-links. Two helper artifacts navigate the graph: `docs/learnings/index.md` (content catalog the agent reads first) and `docs/learnings/log.md` (append-only chronological record). `learn --lint` keeps the graph healthy (orphans, missing back-refs, contradictions, missing pages for frequently-cited concepts).
- **D20. ~~`learn ingest <source>` for proactive knowledge capture.~~ SUPERSEDED by EN14 (`ingest` removed; a summary of lookupable material is a second copy that goes stale).** Distinct from `capture` (which is reactive, post-fix). `ingest` reads any engineering-relevant source — a file path or a URL — and writes a structured summary to `docs/learnings/sources/<slug>-<date>.md`, then walks 10–15 related pages and updates them. Use cases: library evaluation articles, design references from elsewhere, customer-call summaries, best-practice posts. URL inputs use WebFetch; file inputs use Read.
- **D21. Capture-from-synthesis reflex.** When `en-plan`, `en-review`, or `en-brainstorm` produces a durable synthesis (a comparison, a non-obvious connection, a pattern across multiple files, an extracted lesson), the skill ends with a soft "**Capture this as a learning?**" prompt rather than letting the synthesis disappear into chat. The user accepts → `en-learn capture --from-conversation` files it.
- **D22. Skill-name prefix `en-`.** All skills use the `en-` prefix consistently across slash commands, directory names, and skill identifiers (`en-brainstorm`, `en-foundation`, `en-plan`, `en-build`, `en-review`, `en-qa`, `en-learn`, `en-ship`, `en-sweep`, `en-setup`). Avoids namespace collision with other plugins.
- **D23. Cross-review peer is always the *other* agent.** Resolved by host-detect on every invocation. Claude Code → peer is Codex. Codex → peer is Claude. No model-defaults table to maintain; the host *is* the routing.
- **D24. `en-foundation` emits a bootstrap `<PREFIX>01-feature_project-setup` plan only for new projects.** `<PREFIX>` is the `plan_id_prefix` resolved during foundation (default `FR`). Detection: `docs/foundation.md` does not yet exist *and* the repo has no source code (or initial-commit state). Existing projects skip the bootstrap plan entirely.
- **D25. `en-build` batch size is dynamic.** Derived from the feature being implemented — tightly-coupled units batch together, independent units allow larger batches, complex/sensitive units (auth, payments, migrations) batch alone. No fixed default.
- **D26. The learning-capture checkpoint is a SINGLE structured step at `/en-build`'s completion.** (Relocated from en-ship's preflight to en-build's completion by EN04; consolidated to en-build-only by the EN04 follow-up — `/en-qa` and `/en-ship` no longer prompt for learnings.) It fires at the **very end of `/en-build`'s post-build phase — after the branch-level simplify + Outside Voice review + evidence audit — so capture reflects the fully reviewed build.** Structured and non-droppable (not a soft prompt): it detects "X commits since last capture" and surfaces a yes/skip/details prompt, recording `learning_checkpoint: <captured (N learnings) | intentionally_skipped | up_to_date | ci_environment>` in the en-build report so the decision can never be silently dropped. Consequence: capture is a build-time concern — a change shipped without `/en-build` gets no learning checkpoint (accepted trade-off for one unambiguous capture point). Baseline detection uses the `| <head-sha>` field on `capture` entries in `docs/learnings/log.md` (precise) with legacy date-fallback for older entries.
- **D27. `en-sweep` is strictly doc-only and scheduled.** Runs as `.github/workflows/en-sweep.yml` on a configurable cron (default weekly Mon 9am UTC) plus `workflow_dispatch`. An activity gate (`bin/ensemble-sweep-activity-check`) skips scheduled runs when no non-sweep commits have landed since the last sweep. Opens *doc-only* PRs that auto-merge after `en-review` clears. Code-level findings go to `docs/plans/tech-debt-tracker.md` instead of being acted on. Originally `push: branches: [main]` (every-merge fire); changed to scheduled-with-gate on 2026-05-05.
- **D28. Worktrees are opt-in per dispatch.** Following Compound Engineering's pattern, skills pass `isolation: "worktree"` on subagent dispatch when isolation is beneficial — primarily `en-build` for per-unit work. Not a repo-wide setting.
- **D29. ~~Per-unit code simplification before peer review.~~ SUPERSEDED by D35 (branch-level review model).** *Original (historical): during `en-build`, the `code-simplifier` agent ran against each unit's diff before a per-unit Outside Voice peer review.* Field experience showed per-unit simplify+review on every unit is the dominant source of build latency — and on doc/skill-style work it reviews the same surface N times. **D35 replaces it:** ordinary units run implement+test+lint+commit only; the code-simplifier and Outside Voice review run ONCE over the whole branch diff in `en-build`'s post-build phase (mirrors compound-engineering's `lfg`). Destructive/`gated:true` units keep a dedicated per-unit peer pass — those are too consequential to fold into a branch-level pass.
- **D30. Peer reports, host applies.** This is the core contract for every Outside Voice cross-review across every skill (`en-foundation`, `en-plan`, `en-build`, `en-review`). The peer agent **only reports findings** in structured JSON. It does **not** edit files, run commands, modify state, or make commits. The host (the agent running the skill) is the sole code-modifier — it parses the peer's findings, decides which it agrees with, and applies the agreed ones. Peer outputs are advisory; host has agency. This separation keeps the peer's role bounded (cheap, stateless, parallelizable) and prevents the two agents from racing on the same files.
- **D31. Single-agent fallback when only one CLI is available.** If the user has only Claude Code installed (no Codex), or only Codex (no Claude Code), Outside Voice cross-review degrades to a **fresh-instance fallback**: the host shells out to its own CLI in a clean subprocess (e.g., `claude -p` from within Claude Code, `codex exec` from within Codex). The fresh context still catches things the implementing session has rationalized away — Superpowers' subagent-driven-development pattern relies on exactly this. **The contract from D30 still holds:** the fresh instance only reports findings; the host applies them. The peer's response carries a `peer_mode` field (`cross-agent` vs `single-agent-fallback`) so the user always knows which mode they're in. Same-agent fallback is a degraded mode — same model means same systematic biases — so the prompt is augmented with explicit "be more aggressive, bias toward finding problems" framing to maximize the value of the fresh context. Setup script detects on install and recommends installing the other CLI; doesn't block.
- **D32. `/en-plan` (and follow-up `/en-foundation`) auto-branch off the default branch.** When invoked from the repo's default branch (per three-source detection: `gh defaultBranchRef` → `git symbolic-ref` → hardcoded fallback `main|master|develop|trunk`), the new step-12 checkpoint prompts the user before committing. Default action: create a feature branch `<plan_id>-<slug>` (matching `/en-build`'s convention) and commit there. Reverses an earlier "commit on current branch" default — the friction of plans landing on `main` (bypassing PR review, mixing design/implementation history) outweighed the discoverability benefit. Users who genuinely want plans on the default branch get an explicit `current` opt-out right in the prompt — surfaced, not hidden. Three terminal response options: `y` (auto-branch + commit), `no-commit` (leave uncommitted), `current` (commit on default branch anyway); plus a non-terminal `details` (diagnostic, re-prompts). Outcomes recorded in the report: `auto_branched`, `no_commit_requested`, `committed_to_default_branch`. The checkpoint runs at step 12 of `/en-plan` (BEFORE the plan-file write at step 13) so resume cases never hit "untracked working tree file would be overwritten" on `git checkout`. Scope: literal default branch only; broader "protected branches" coverage is a future extension via `.ensemble/config.local.yaml` `protected_branches:` list. `/en-foundation` gets analogous treatment in a follow-up.
- **D33. Autonomous execution is the contract; agent-initiated pauses are forbidden inside the inter-unit / inter-flow main loop.** `/en-build` and `/en-qa` are designed to execute plans autonomously after user authorization at plan time. Only documented pause cases (universal safety gates, opt-in `--pause` flag, failure protocols, Phase 1 system-check failures for QA, ambiguous-bug user-judgment cases for QA) are legitimate within the contract window. Agent-initiated checkpoints based on independent judgment — "this next unit is bigger," "let me verify before continuing," "should I proceed?" — are explicit anti-patterns. The contract is **scoped to the in-loop window** (step 9 onward for /en-build; already-runnable QA flows for /en-qa); preflight handlers (sub-state matrix, URL discovery, Playwright bootstrap) have their own documented prompts and are explicitly out of scope. Rationale: the user already authorized the work at plan time (peer-reviewed plan, `status: open`, hash recorded); per-unit pauses bypass that authorization. The safety net for "things go wrong" is the failure-protocol table (gate failures, peer rejects, hash mismatches, etc.), not agent self-judgment. When in doubt, advance; surface observations in per-unit progress reports via `Note:` lines, not as gating prompts. **Gating surface is two narrow categories only** (reinforced 2026-06-28): `risk: destructive` (irreversible data loss) and `gated: true` (production-state-changing actions only — flag flips, prod backfills, real prod-side-effect APIs, API contract breaks, prod config). Non-production external side effects are NOT gated; they rely on the verification gate + post-build review. `/en-build` surfaces a preflight gate-count summary so the (rare) gates are expected, not surprises — over-gating trains users to autopilot through prompts and erodes the signal of the gates that matter.
- **D34. Source of truth for `in_progress → completed` is `/en-learn capture` step 11a, with `/en-ship` preflight as backstop.** The plan-status lifecycle moves through three flips: `/en-plan` finalize loop (`draft → open`), `/en-build` step 4b (`open → in_progress`), and `/en-learn capture` step 11a (`in_progress → completed`). The final flip is bundled with the file move from `docs/plans/active/` to `docs/plans/completed/` and the `shipped:` date set. Field-observed friction: `/en-learn` is soft-auto-invoked, and step 11 was previously bundled with actually-captured-a-learning, so a "skip capture" decision orphaned the plan at `in_progress`. Resolution: (a) step 11 unbundles into 11a (always-runs lifecycle flip — fires whenever `/en-learn capture` is invoked in a plan context, regardless of whether a learning was filed) and 11b (documentation-tense + deviation notes — only on actual capture); (b) `/en-ship` preflight gains a plan-completion checkpoint as backstop — catches plans whose `/en-learn` invocation got dropped entirely. The checkpoint is informational (doesn't gate ship); it surfaces stuck-at-`in_progress` (or `open` for the recovery path) plans and offers a structured y/skip/details flip. Build completeness is checked via `bin/ensemble-verify-peer-evidence` — a unit counts as complete when it has per-unit peer evidence OR is covered by a branch-level `review-verdict:` (per D35's `--branch-coverage`); plan-init commits and merge commits are excluded. Mutation is atomic with the ship commit; placement late in preflight (after lint/typecheck/secret-scan/scope-confirm) prevents the lifecycle from advancing before ship is committed to going out. Outcomes: `completed_and_moved | skipped_by_user | up_to_date | not_applicable | incomplete_build`.
- **D35. Branch-level review model for `en-build` (supersedes D29).** The per-unit inner loop is implement → test + lint → commit (`phase:` trailer only). After all units build, a single post-build phase runs `/en-simplify` on the branch diff, then **`/en-review --peer-only`** on the branch diff — en-review's peer-only mode dispatches a **cross-agent Outside Voice review** on the **peer** agent as the sole reviewer (Claude host → Codex; Codex host → Claude — D23/D30; the host just implemented, so the reviewer must be the other agent, with no host-side personas). The host applies eligible fixes and records a `review-verdict:` git trailer listing the `units_covered` and the `reviewer` (`cross-agent` normally; `single-agent-fallback` / `en-review-host-fallback` when no peer). The cross-agent peer machinery has a single implementation inside `/en-review`; en-build calls it rather than duplicating the dispatch. Build-completeness evidence is then **per-unit OR branch-level**: `bin/ensemble-verify-peer-evidence` gained a `review-verdict:` trailer type and a `--branch-coverage` range mode; a unit is "reviewed" if it carries per-unit peer evidence OR appears in a branch-level `review-verdict.units_covered`. `en-ship`'s plan-completion checkpoint accepts either. **Exception preserved:** `risk: destructive` and `gated: true` units still require a dedicated per-unit peer pass (`--require-peer-resolution` rejects branch-level coverage for them). Rationale: collapse the dominant build-latency source (N per-unit peer passes) into one branch-level pass without weakening the high-consequence gate.
- **D37. Plan-content quality gates in `/en-plan` (EN03).** Three lean, gated upgrades adapted from compound-engineering's `ce-plan`, chosen to lift plan→build quality without per-plan overhead. (1) **Test-scenario specificity** — feature-bearing units must enumerate real scenarios across happy/edge/error/integration with concrete inputs/actions/outcomes; non-feature units use `Test expectation: none — <reason>`. Enforced by an en-plan pre-write check and the `unit.test-scenarios` lint (P2 advisory — a nudge, not a P1 blocker). (2) **Conditional `Decisions, assumptions & risks` section** — one optional plan section that appears only when there's real substance (a non-obvious decision, a rejected alternative, an inferred assumption, or a genuine risk), giving research findings + inferred bets a reviewable home; omitted on trivial plans (no boilerplate tax). (3) **Technical-design load-bearing audit** — architecture-complexity triggers (≥3 components, ≥3-step protocol, state machine, ≥3 data-flow stages, DSL/public-API design) require a plan-level `## Technical design` section, verified at pre-write; self-gating (simple plans pay nothing). Deliberately NOT adopted from ce: status-free plan model (our `draft→open→in_progress→completed` lifecycle is load-bearing), unified single-artifact/in-plan Product Contract (foundation owns requirements), HTML rendering, approach-altitude, input-classification/knowledge-work routing.
- **D38. Hands-off `/en-ship` with a local self-heal loop (EN04).** `/en-ship` is **hands-off by default** (a deliberate breaking change to its prior stop-and-ask contract, acceptable pre-1.0): preflight checkpoints (scope-confirm, plan-completion) auto-resolve. **Safety floor** - secret-scan match, push to the default branch, and destructive-guardrail hits always hard-stop, even hands-off; `--interactive` restores the prior prompts. The **learning checkpoint is relocated from en-ship preflight to `/en-build` completion** as a structured, non-droppable step (updates D26's location; the anti-drop rationale from the PR #18 fix is unchanged - capture now happens at the point of insight while the user is present). The plan-completion checkpoint stays in en-ship as the lifecycle backstop but auto-`y`s a verifiably-complete build under hands-off. **Self-heal is LOCAL, not in CI.** After the PR opens, `/en-ship` runs a session-bound **local watch-and-fix loop**: it polls the PR for CI status + review-model findings, drives `/en-resolve-pr` to fix them **on the developer's machine** (their checkout, their credentials - `/en-resolve-pr` commits + pushes), then re-validates and loops until all checks are green and no unresolved review threads remain, bounded to `watch.max_cycles` rounds (default 3) then escalates the remainder as `needs-human`. **CI's role is read-only**: run tests and let a review model (the Anthropic Code Review action, CodeRabbit, `/en-sweep`'s review) post findings - the *fixing* never happens in CI. This deliberately keeps repo-write access and API secrets **off** CI (no `workflow_run` pwn-request surface, no new secret). Default stops at a green, mergeable PR; `--auto-merge` arms native `gh pr merge --auto --squash`; `--no-watch` opens the PR and stops. The loop is session-bound (it runs while the `/en-ship` session is open). **Design note:** an earlier EN04 draft put the fix loop *in* CI (a `workflow_run` self-heal workflow + write token); that was reversed - fixing is local, CI reviews.
- **D39. Brainstorm product-rigor upgrades + explicit `performance > speed ≥ cost` priority (EN05).** `/en-brainstorm` adopts the highest-leverage, lowest-overhead product-rigor lenses from compound-engineering's `ce-brainstorm`, kept deliberately lean (NOT ce's full 318-line machinery). **Three self-gating rigor lenses** (each fires only when it adds value, so simple work pays no tax) plus **one elicitation-modality change**: (1) a **Product pressure test** before approaches, scan for rigor gaps (evidence, specificity, counterfactual, attachment; + durability for Deep) and fire one **open-ended** probe per gap that actually exists (a well-framed opening earns zero); (2) an **integration check** before approaches, combine user-stated X + Y + default Z and probe the non-obvious downstream consequence one-question-at-a-time dialogue misses (distinct from the after-recommendation devil's-advocate pass); (3) **verify-before-claiming**, any absence claim about the codebase is verified against the repo or labeled an unverified assumption (a lightweight rule, not a verifier sub-agent). The modality change: **default to the host's blocking question tool** (`$QUESTION_TOOL` per host-detect — `AskUserQuestion` on Claude Code, `request_user_input` on Codex; host-neutral, not hardcoded) for narrowing questions, with an open-vs-closed discipline (reserve open-ended for genuinely-narrative answers). This is **not** a self-gating gate or added ceremony; it is a lighter *how-we-ask* for the narrowing questions the skill already poses, and it is consistent with **D10** (D10 governs the *light* question-tool form and avoiding heavy decision-brief ceremony; it does not restrict using the blocking tool for ordinary narrowing). Rigor/integration probes count toward the depth question budget (Lightweight caps at one). Deliberately NOT adopted from ce-brainstorm: visual probes, HTML output mode, the universal/non-software route, model tiers, the async grounding-scout dossier, and the unified single-artifact model (the last already rejected, foundation owns requirements; keep design doc and plan separate). **Priority principle (stated in both `/en-brainstorm` and `/en-plan`): `performance > speed ≥ cost`**, optimize first for outcome quality (right thing, built well), then speed, then token/tool cost; rigor and research depth are worth their cost when they lift build quality, kept self-gating so lightweight work stays fast.
- **D40. `/en-loop` — bounded autonomous-loop orchestrator wrapping gnhf (EN06).** A new manual-invoke skill for bounded, objective-driven autonomous loops (the ralph / good-night-have-fun pattern): keep an agent working one committed test-gated slice per iteration until an evidence-based stop condition. **Engine: wrap the gnhf CLI, not a native reimplementation** (the EN04 lesson, do not rebuild robust unattended-loop infra; gnhf already provides interrupt handling, commit-on-success / rollback-on-failure, retries, worktrees, process supervision, and an exit summary, agent-agnostic across Claude and Codex). Ensemble's value-add is two layers on top: the per-iteration **test-gate worker contract** (implement one slice, run test + lint, commit only on green, no fake success) and the **branch-level cross-agent review** at checkpoints. **Cadence: test-gate per iteration + checkpoint review, not per-iteration peer review** (a full Outside Voice pass every iteration is too slow and costly for an overnight loop): `/en-review --peer-only --mode headless` runs every `--review-every N` iterations and at loop end (branch-level model, D35), and its findings become the next iterations' acceptance criteria. Two modes (**Hands-Off**, **Companion**) plus a **Morning Review** that reconstructs state from git / logs / processes, never memory. **Evidence-based stop conditions are required**: en-loop refuses a vague `--stop-when` ("looks good") and demands an Ensemble-observable condition (suite green, `/en-review` clean, lint 0). **Core rule: the host orchestrates, gnhf executes; completion is not acceptance** (a gnhf stop means the worker stopped, not that the result is accepted; Morning Review verifies independently before anything is called mergeable). The loop **never auto-merges**: its output is a reviewed feature branch plus the exit summary, and shipping stays an explicit `/en-ship`. The external gnhf dependency (`npm i -g gnhf`) is surfaced as an optional, non-blocking install by `/en-setup` (State 2 offer, State 3 status). Priority principle D39 (`performance > speed ≥ cost`) drives the cadence choice: high overnight throughput while still producing a peer-reviewed, evidenced branch. Deliberately NOT in scope: a native or hybrid loop engine, upstream changes to gnhf, and auto-merge / auto-ship from the loop.
- **D41. Auditable post-build simplify+review gate in `/en-build` (EN07).** The post-build phase (step 10) required `/en-simplify` and the branch-level `/en-review` in **prose**, but the only mechanical gate (`ensemble-verify-peer-evidence --branch-coverage`) inspected **review evidence only** - it had no concept of simplify. Field-observed on the EN06 build: the simplify pass could be skipped (or the review could run via single-agent fallback without recording why) and the build still finished "clean." **The defect was the silence, not the skip.** EN07 turns the prose requirement into an **auditable stop gate**: a durable **`simplify-verdict:` git trailer** (parallel to `review-verdict:`; `outcome` = `completed | not_applicable | failed`, with a REQUIRED `reason` for the latter two - `docs-only`, `trivial:<10-lines`, `--no-simplify`, `all-destructive-gated`) emitted on the post-build commit; the verifier gains `validate_simplify_verdict()` and, in `--branch-coverage`, derives two fields - **`simplify_pass`** (`completed | not_applicable | failed | missing`) and **`branch_review_pass`** (`completed | fallback_completed | failed | missing`). A new **`--require-simplify`** flag (passed by `/en-build` step 10.5, NOT by en-ship's read-only coverage read) makes a `missing`/`failed` simplify or review a **non-zero exit**. Two visible outcome lines (`simplify_pass:` / `branch_review_pass:`) are mandatory in every build summary as the human-visible echo of the trailers. **Fallback rule:** the single-agent peer path is ONLY a fallback for `/en-review`; the `review-verdict.reviewer` value (`single-agent-fallback` / `en-review-host-fallback`) IS the recorded reason and maps to `branch_review_pass: fallback_completed` - a fallback with no recorded reviewer fails. **The learning checkpoint and the `/en-review → /en-qa → /en-ship` success path are BLOCKED until the audit passes** (the learning-checkpoint deferral guard now also defers on a `missing`/`failed` simplify or review). This **hardens D35's branch-level review model** (simplify is now first-class evidence alongside review) and **gates D26's learning checkpoint** (capture only after a fully-evidenced build). Additive and flag-gated: without `--require-simplify` the verifier's exit codes and en-ship's coverage read are unchanged.
- **D42. en-review lite-gate transparency + auditable mutation boundary (EN08).** Applies **D41's prose-to-auditable-gate pattern** (visible outcome line + fail-closed rule instead of prose) to `/en-review`, after two field failures on a `--lite` interactive run: the fail-closed lite gate silently overrode `--lite` (full roster ran, no reason surfaced), and the reviewing agent implemented findings wholesale, past the mode's mutation contract. **Gate 1 — lite-gate transparency:** every run emits exactly one mandatory **`lite_gate:`** outcome line (`applied` / `overridden (<reasons>)` / `not-requested`) so a missing line is distinguishable from a not-requested lite and an override is never silent; override reasons use the canonical enum named in `references/diff-signal-detection.md` (`unknown-line-count`, `exec-lines-out-of-range`, `uncounted-files`, `risk-signal`, `conditional-persona:<alphabetically-sorted-+-joined names>`) with a deterministic multi-reason grammar (fixed order, dedup, comma+space); the JSON envelope carries the structured `lite_gate` object from which the line derives. **Gate 2 — auditable mutation boundary (two-phase):** the pre-review working-tree baseline and the frozen mode-permitted finding set are fixed BEFORE any edit; `applied_fixes[]` (entries `{finding_id, tier, files[]}`) derives from the actual before-vs-after tree delta with pre-existing changes excluded; the mandatory **`review_fixes:`** line (`applied <N> (<ids/tiers>)` / `none` / `none (report-only)`) is derived from the array under strict consistency invariants (N equals unique entries; ascending ID order; `none` requires an empty array). Boundaries, fail-closed: interactive auto-applies `safe_auto` and announces `gated_auto` per the severity.md matrix; headless is `safe_auto`-only; report-only applies nothing; `manual` findings are NEVER applied without the user's explicit pick; **any P0 finding halts ALL automatic mutation** until severity.md's P0 pause-and-ask; en-review MUST NOT implement findings outside the mode-permitted, announced, and recorded `applied_fixes[]` set — wholesale implementation is a contract violation (implementing belongs to `/en-build` / `/en-resolve-pr`). severity.md's action matrix is unchanged (referenced, not duplicated); the lite gate's classification is unchanged (only made visible). Enforcement tier: drift tests on the skill/reference text (`tests/lint/en-review-mutation-gate.test.sh`) — en-review runs in-session without commits, so there is no git-trailer surface; a runtime tree-diff enforcer was deliberately deferred unless breaches recur.
- **D43. en-guardrail hardening — close verified destructive-op gaps (EN09).** A review of the `en-guardrail` `PreToolUse` hook (empirically probed with crafted commands) found real holes; EN09 extends the hook's **behavioral matchers and its test suite** (the mechanical guarantee), following D41/D42's turn-prose-into-enforced-behavior pattern. **Filesystem (threat A):** the `rm -rf` artifact exemption is now a **positive allowlist** — exempt ONLY a literal plain in-tree relative path whose final segment is a known artifact; absolute (`/build`), home (`~/dist`, `$HOME/…`), shell-expanded (`${HOME}/dist`, `$PWD/dist`, `$(pwd)/dist`), globbed, or parent-escaping targets prompt (closes the old `*/build|build` globs that greenlit root/home deletes). New matchers cover non-recursive deleters (`find -delete`/`-exec rm`, `rsync --delete`, `shred`, `truncate -s 0`, `unlink`) and a symlink-aware `>`-truncation contract (allow new-file creation; ask on truncating an existing regular file or a symlink; fail closed when unresolvable). **Database / production (threat B):** SQL fed from a file/stdin/pipe against a non-local target prompts (the hook can't inspect it); `UPDATE` without a **top-level** `WHERE` prompts (a Python scope analysis strips comments + literals and requires a `WHERE` at parenthesis-depth 0, so a `WHERE` in a comment/literal/subquery/later-statement can't mask a mass update); ORM destroyers (`prisma migrate reset`, `rails db:drop|reset`, `drizzle-kit push`, …) prompt; and a **second `PreToolUse` matcher covers DB-writing MCP tools** (`mcp__*__run_sql`-family + server-qualified `mcp__Postgres__query|execute`) via per-tool adapters that read the statement and the *controlling target field* — the local exemption comes only from that authoritative field (never SQL text), remote-only providers (Neon) never exempt, and a write-named tool with no adapter fails closed. **Bypass:** the model-writable inline `ENSEMBLE_GUARDRAIL=off` prefix is removed; the bypass is now read ONLY from the hook's own process env (`ENSEMBLE_GUARDRAIL_BYPASS`), which the human exports before launch, so the agent cannot self-exempt within a session. **Framing (deliberately not fully solved):** the working-folder boundary stays the host permission system's job (the guardrail is a pattern brake, not a path sandbox — A4); "production" is inferred by exemption, with an optional positive production-marker recorded as a future extension (B4). Enforcement tier: behavioral tests in `tests/en-guardrail/` (the hook is a real script, unlike EN08's prose surface).
- **D44. Host-resolved `PEER_TURNS` for the Codex `--max-turns` removal (EN10).** The current Codex CLI (`codex exec`, 0.144.0) **removed `--max-turns`** and is inherently single-shot (runs to completion and exits), so passing it errors with `unexpected argument`; `claude -p` still supports it. Ensemble's cross-agent peer contract had hardcoded `$PEER_CMD $PEER_FORMAT --max-turns 1` at every call site, which broke every Codex-peer review and made the `./setup` smoke test report a false "flag mismatch". **Fix:** `bin/ensemble-detect-host` resolves and emits **`PEER_TURNS`** per peer agent — `--max-turns 1` for a `claude -p` peer, **empty** for `codex exec` — and every executable peer call site (`references/outside-voice.md`, `cli-wrappers.md`, `build-handoff.md`, `recursion-guard.md`, and the `en-plan` / `en-foundation` / `en-review` skills) uses `$PEER_CMD $PEER_FORMAT $PEER_TURNS "$prompt"` (empty collapses for Codex). Same host-neutral parameterization as `PEER_FORMAT` and D39's `$QUESTION_TOOL`. The Codex **worker** guidance in `build-orchestration.md` (which told workers to pass `--max-turns 30`) is dropped for the same reason. The `./setup` smoke test now **classifies** a probe failure from stderr — argument-parse error → flag drift; recognized auth error → "sign in first"; otherwise a neutral probe-failed line — instead of always blaming flags (a fresh un-authenticated machine is not a flag mismatch). Enforcement tier: a drift test (`tests/lint/en-codex-flag-drift.test.sh`) that fails if any peer-contract file or `setup` re-introduces a hardcoded `codex exec … --max-turns` or a hardcoded `$PEER_CMD … --max-turns`, plus stub-driven checks of the smoke-test classification. (D43 is EN09's guardrail-hardening decision, above; D44 was numbered to avoid colliding with it while that PR was in flight.)
- **D45. Default-on cross-agent peer in `/en-review`, two-source reconciliation, and a policy/binding/call-site split for peer models (EN11).** `/en-review` defaulted to host personas only, with the cross-agent peer opt-in behind `--peer`, so a direct review of code the host just wrote was **same-stack**: the persona sub-agents have fresh context but share the host's weights and blind spots. The field evidence was one-sided - EN09's 6 guardrail parser bypasses and EN10's 4 findings were **all** peer-only. **Default flip, deliberately scoped by mode AND availability:** peer is on by default when `PEER_MODE=cross-agent` and the mode is `interactive`/`headless`; `--no-peer` opts out (naming consistent with `/en-plan`), `--peer` becomes a back-compat no-op. Two carve-outs are load-bearing rather than incidental. **`report-only` never runs a peer**, because `/en-sweep` invokes `/en-review` in that mode inside CI and **D38 deliberately keeps API secrets and repo-write off CI** - a naive default-flip would have silently required peer CLI credentials there. **`single-agent-fallback` defaults peer off** (opt in with `--peer`), because en-review's personas are *already* fresh-context instances of the host stack, so a redundant same-model subprocess buys no independent perspective; the calculus differs in `/en-build`, where the alternative is the host reviewing its own inline work, so that path keeps the fallback. Because the peer is **blind** to persona findings, the peer subprocess is dispatched in the **same parallel batch** as the persona agents rather than serially after them, hiding its latency (`peer_timeout_seconds` defaults to 600). **Two-source reconciliation** replaces the flat merge: findings carry `source`, and a distinct **reconciliation record** (`sources[]`, `canonical`, `contributing[]`) buckets them as **corroborated** (host AND peer, confidence `+2`, since two independent architectures agreeing is materially stronger than two same-stack personas agreeing - same-source overlap keeps its `+1`), **peer-only**, **host-only**, or **conflicting**. One global algorithm keeps the buckets a true partition: conflict stage first (consuming both members, so a contradiction is never masked by a similarity match), corroboration on the remainder, then singles, with `finding_id` tie-breaks and an asserted "every raw finding lands in exactly one record" invariant; conflict detection is **independent of** the `0.7` title-similarity predicate, because incompatible claims are frequently dissimilar in title. **Blind-peer is now a named invariant:** `persona-dispatch.md` had claimed the peer reads the persona findings "to confirm or counter them", but `bin/ensemble-build-peer-prompt` has no such flag and en-review never passed them - the prose was wrong and the implementation was right, since anchoring the peer on host findings would destroy the independence that makes corroboration meaningful, so the doc was corrected rather than the feature built. **Peer model/effort** is split three ways, generalizing D44's flag-drift lesson from flags to model IDs: **policy** (`references/peer-model-policy.md`, the stable ladder - `high` first for security/migrations/architectural/destructive/gated, `low` only for `is_small_and_safe`, `medium` as floor), **binding** (`bin/ensemble-peer-flags`, a pure translator that reads no config), and **call sites** (`$PEER_MODEL` / `$PEER_EFFORT` only). `/en-review` is the sole resolver (`--effort` → repo config → user config → ladder). **No concrete model ID lives anywhere in Ensemble**: the Claude peer pins a tier *alias* (auto-resolves to the latest), and the Codex peer pins **nothing**, inheriting the operator's `~/.codex/config.toml` model while Ensemble overrides only `model_reasoning_effort` - this fixed a real defect where every Codex peer review silently inherited an operator's interactive `model_reasoning_effort = "high"`. Fail-soft (a `flagdrift`-classified rejection triggers one bounded retry dropping only the offending fragment) lives in an **executable** helper `bin/ensemble-peer-invoke`, not prose, because D41's lesson is that a prose invariant cannot be behaviorally tested. A shared `bin/ensemble-config-get` finally implements the repo-then-global cascade (previously only en-sweep's bespoke awk read `.ensemble/config.local.yaml`), and `setup` now **merges** missing keys into an existing config instead of skipping the file, so new settings reach already-configured machines. Enforcement tier: drift tests plus behavioral checks driving the real helpers against stub CLIs (`tests/lint/en-review-peer-default.test.sh`).
- **D46. `/en-build`'s post-build review is peer + personas, not peer-only (amends D35).** D35 specified `/en-review --peer-only` for the branch-level review, reasoning that because the host implemented every ordinary unit the review must come from the *other* agent "with no host-side personas". The cross-agent requirement was right; the exclusion was not. **`--peer-only` discarded every host-only finding** - exactly the **standards / testing / maintainability** categories, which are the ones that most depend on project context, `CLAUDE.md` conventions, and alignment with the plan being built. That is a strange thing to drop from a review whose whole subject is "did this branch implement this plan correctly". **The implementer ≠ reviewer property survives the change** because en-review's personas are **fresh-context sub-agents**: they never saw the implementing session's reasoning, so they are not the implementer in any meaningful sense, and the cross-agent peer still provides the independent-architecture perspective. Step 10.3 therefore invokes **`/en-review --cross`** (spelled `--peer` until 2026-09-01, when en-review's flags were renamed so that `--peer` means peer-sole and `--cross` means peer-plus-personas; the behaviour D46 requires is unchanged, only the word for it): the peer remains **mandatory** (a build whose peer did not run still records a fallback reason and still fails the `--require-simplify` audit), and the personas are **additive**. `review-verdict.reviewer` keeps its exact prior meaning - whether the CROSS-AGENT property held (`cross-agent` / `single-agent-fallback` / `en-review-host-fallback`) - so the step 10.5 audit gate is unchanged; persona contribution is carried separately in the envelope. Findings now arrive bucketed per D45, so the host triages `corroborated` first and **never auto-applies `conflicting`** ones. **Scope is deliberately `/en-build` only:** `/en-loop` keeps `--peer-only` at its checkpoints, because those fire every `--review-every N` iterations inside an unattended overnight loop where adding a full persona roster per checkpoint multiplies token cost in exactly the place cost compounds. Enforcement tier: `tests/lint/en-build-review-model.test.sh` asserts the `--peer` call, guards the specific reversion to a peer-sole call, requires the "peer is mandatory" wording, and separately asserts the peer-sole mode still exists in en-review because `/en-loop` depends on it.
- **D47. `/en-brainstorm` cost + latency pass, then three adopted mechanisms.** Follows a benchmark review against `ce-brainstorm`, `agent-skills/skills/engineering/codebase-design`, and `grill-with-docs`/`grilling`. **Cost:** the step-5 context scan is now bounded (frontmatter → `grep -n '^#'` section index → `sed -n` on matching sections); reading `docs/foundation.md` whole cost ~51K tokens on this repo and was 85% of a Standard run's pre-dialogue context. The design doc is now lint-validated before `/en-plan` consumes it. **Latency:** asking cadence moves from strict one-question-per-turn to **frontier rounds** on Standard/Deep (adapted from `grilling`) — model open decisions as a design tree, ask each round's *independent* frontier in one numbered batch with a recommended answer per question. The dependency rule (a question depending on one still open this round waits for the next) is what makes batching safe; batching without it is plain question-stacking and is strictly worse than one-per-turn. One-per-turn is retained on Lightweight and for all rigor probes, which are deliberately open-ended. Facts in the environment are looked up **non-blocking** (only downstream questions wait), never asked — the skill's first parallelism. Deep runs go from 9–14 sequential round trips to ~3–4 rounds. **Three adopted mechanisms**, both heavy ones behind gates in their own reference files so a run that doesn't trigger them pays nothing: (1) **resume** — an open design doc matching the topic is offered and updated in place rather than duplicated, mirroring `/en-plan`'s existing shape; (2) **blindspot pass** (`references/brainstorm-blindspot.md`, adapted from `ce-brainstorm`) — when the user cannot *evaluate* a territory, map its decision surface (3–7 decisions/hazards with options and recommended defaults) before interviewing into it, guarded against over-firing on a merely-undecided user, and skipped entirely in non-interactive runs; (3) **divergent approach generation** (`references/brainstorm-approaches.md`, the Design-It-Twice pattern) — on Deep, or Standard with 3+ live directions, generate approaches via parallel sub-agents each held to a *different* constraint (smallest-thing / invert-the-default / optimize-common-case / remove-the-binding-constraint), because serial single-context generation anchors and returns B and C as variants of A; each returned approach must clear an anti-genericness bar, and convergent agents yield one approach reported as convergence. **Guard recalibration:** en-brainstorm's drift assertions were the densest in the repo (0.26/skill-line) on an output the repo itself calls "informational, not load-bearing", and they *mandated* the duplication they were meant to prevent. Cut from 28 wording/provenance assertions to 17 behavior assertions, then back to 23 as the three new mechanisms landed with their own guards, every new one negative-controlled (target broken, guard confirmed red). Assertion density should track blast radius. Deliberately still NOT adopted from `ce-brainstorm` (D39's list stands): visual probes, HTML output mode, the universal/non-software route, model tiers, the async grounding-scout dossier, and the unified single-artifact model.
- **D48. `/en-plan` correctness fixes, bounded reads, frontier rounds, and design-doc reuse.** Companion pass to D47, applying the same review method to `/en-plan`. **Correctness:** four numeric `step N` cross-references had rotted out of sync with the process list. The worst shipped as a real behavioural bug — the peer-`reject`-override row in the failure protocol pointed at the Outside Voice review loop instead of the status flip, so overriding a rejection re-entered peer review rather than promoting the plan. Two others (`draft` until "step 11"; the legacy-README back-reference "handled in step 12") pointed at unrelated steps. **All step cross-references are now by name**, `11a` is folded into a flat 1–20 list, and a drift guard fails the build on any numeric `step N` or non-sequential numbering — this is the third time numbering drift has produced a defect. **Portability:** the `foundation §17.4` citation was removed; §17 exists only in Ensemble's own foundation, while the template that generates user projects stops at 14 sections. **Cost:** the foundation read is now bounded (frontmatter + `grep -n '^#'` section index + only the Functional Requirements / Technical Direction sections), and the default-branch checkpoint's prompt, handlers and diagnostics move to a gated `references/plan-default-branch-checkpoint.md` read only when the checkpoint actually fires — most runs are already on a feature branch. **Latency:** planning questions adopt D47's frontier rounds (architecture in round 1; file boundaries, test strategy, dependencies and migrations together in round 2), cutting 5 sequential round trips to 2, with one-per-turn retained on Lightweight. **Streamlining the brainstorm→plan seam:** a matching design doc with `status: open|accepted` has its settled decisions carried into the plan rather than re-asked, with the doc's `## Assumptions & unverified claims` explicitly carved out as *not* settled; a `superseded` design doc is not carried at all. Adapted in part from `to-spec`'s no-interview posture. Deliberately NOT changed: per-unit `Files:` paths stay required despite `to-spec` arguing specs should omit them — `en-plan` hands to `/en-build` within the hour and the phase loop needs the file list, so the staleness argument does not apply at this handoff distance.
- **D49. Peer finalize loop capped at two passes, severity-gated; peer invocation unified; brainstorm escalates on thin context.** Three changes from the cross-cutting peer-loop analysis. **(1) Two passes, not three.** `/en-plan`'s finalize loop capped at Standard/Deep = 2 re-loops (3 total peer passes); it is now **1 re-loop at every depth** — review, apply, one verification pass, done. `--max-iterations` and `--no-reloop` remain as escape hatches. Rationale: a single-shot peer (`--max-turns 1`) re-reviewing a whole artifact largely resamples its first pass, which is why the "do not re-flag" suppression list already existed — repeat findings were being observed and worked around rather than prevented. **(2) Severity-gated re-loop.** The loop was severity-blind: three `P3` advisories triggered the same full second pass as a `P0` data-loss finding. It now re-invokes only when a pass produced at least one `P0` or `P1`; an advisory-only pass applies what is cheap, records the rest, and exits with an auditable `reloop_skipped: advisory-only`. Measured context: the peer prompt for a 211-line plan is ~6.1K tokens of which **93% is the artifact** — Ensemble's own scaffolding is only ~453 tokens, so the cost of a pass is the artifact, and the only real saving is not running the pass. **(3) One peer invocation path.** `peer-model-policy.md` stated `/en-review` is the only resolver, and it was — but `/en-plan`, `/en-foundation` and `/en-review` each hand-rolled `$PEER_CMD $PEER_FORMAT $PEER_TURNS`, so they had no `timeout` wrapper discipline, no failure classification (`auth` / `unknown` / `timeout`), and emitted no `peer_decision`. All three now route through `bin/ensemble-peer-invoke`, and a drift guard fails the build on any hand-rolled `$PEER_CMD` invocation. **Also: `/en-plan` escalates to `/en-brainstorm` on thin context, not on a missing design doc.** The old soft-nudge fired purely on design-doc absence — noisy for a well-specified request, and silent about the real problem. It is replaced by a context-sufficiency check with three decidable conditions (problem unstated / approach genuinely open / scope has no edges); insufficient context recommends `/en-brainstorm`, sufficient-but-undocumented keeps the one-line nudge. Still never a hard gate (gating-shrink philosophy): proceeding is always allowed and each unresolved gap is recorded as an explicit assumption in the plan's `## Decisions, assumptions & risks` rather than buried in a unit's `Approach:`.
- **D50. Peer prompt carries its own contract; findings anchor and report coverage.** Inspection of the actual generated prompt (not the prose describing it) found five defects. **(1) A referenced section was never emitted.** The rules told the peer to honor `## Previous review context`, but `bin/ensemble-build-peer-prompt` dumped the resolutions raw with no header, wedged between the artifact and the JSON contract — so same-finding suppression had nothing to anchor to. This mattered more after D49 capped the loop, because pass 2 is now the only verification pass. **(2) Severity was named, never defined.** The prompt said `P0-P3` and stopped; `references/severity.md` was never sent. D49 made that boundary load-bearing (the re-run gate keys off P0/P1) while leaving the peer to invent the scale. Definitions are now inline. **(3) Plan dimensions covered only safety metadata** — `risk:`, `gated:`, dependency-phase. Nothing asked whether the plan achieves its goal, whether units decompose sensibly, whether test scenarios are real, or what the plan assumes without saying so. `/en-plan` self-checks some of this pre-write, but a self-check is anchored and a peer is exactly who should verify it independently. Dimensions A–G now cover both. **(4) `references/finding-schema.md` was cited to a fresh subprocess** with no reliable cwd; the keys are stated inline instead. **(5) No scope boundary**, so findings could be spent on prose style in a markdown plan. **Return path:** `finding_id` is now required and must be *reused* when re-raising (a re-minted id breaks suppression); `u_id` is requested on plan reviews (it was already in the schema and already consumed by `/en-build` per-unit dispatch, but the prompt never asked for it, so it was never populated); and a new `coverage: {reviewed, not_reviewed}` field makes an exhausted single-shot review visible instead of letting a partial pass read as a clean `approve`. **Scaffold budget raised 200 → 300 words, deliberately**: the base scaffold now carries the severity definitions and coverage field, costing ~90 tokens per call against a ~5,600-token artifact (<2%). The guard stays live at the new ceiling — it is a cost regression guard, not a formality, and it caught this change.
- **D51. Recover the JSON envelope locally instead of spending a retry round; JSONL rejected.** Every malformed-response path in Ensemble read "retry once with 'respond with valid JSON only'", and nothing anywhere stripped markdown fences or prose before parsing — so the single most common reviewer-output defect cost a full extra peer or persona invocation. `bin/ensemble-extract-json` (sourceable, awk, no new dependency) scans for the first **balanced** top-level `{...}`: fences need no special handling because ```` ```json ```` carries no brace, and trailing prose falls after the closing brace. It is string-aware (braces and escaped quotes inside string literals do not move the depth counter) and validates with `jq` when present, so balanced-but-invalid bodies fail rather than propagate. Wired into `bin/ensemble-peer-invoke`, so all four peer-invoking skills get it without re-implementing it; on failure the out-file is left byte-for-byte intact so the existing retry is never pre-empted. **JSONL was considered and rejected.** It resilies against truncation, which is not the failure mode here — a peer review response is ~1-2K tokens, far under any output cap, and the single-shot peer streams nothing long. It does not help with fences or preamble, which is what actually goes wrong; a fenced JSONL block is equally unparseable and has no object boundary to locate. It also has nowhere to put the envelope (`verdict`, `summary`, `peer_mode`, `coverage`, and `en-review`'s `personas` aggregate) short of inventing a header record, and it would touch 18 consumers (5 skills, 7 reviewer agents, 6 references) while both CLIs already wrap output in `--output-format json`. Hardening the parse fixes the real failure in one place with no schema change.
- **D52. The host implements every unit; the peer reviews once, after simplify (supersedes D35's two flavors, amends D46).** D29/D35 gave `/en-build` two flavors chosen by host detection: build-by-orchestration dispatched Codex as a **worker** that edited files, build-handoff had Codex implement natively with Claude as peer. Both guaranteed implementer ≠ reviewer by swapping who implements. That guarantee now comes from the review instead: **the host implements every unit on every host**, and the cross-agent property is supplied by step 10.3's `/en-review --peer`, which dispatches the other agent. One flavor, no worker dispatch, no `--orchestrate` / `--handoff`. D46's per-unit peer pass for destructive and gated units is also removed: peer involvement is now exactly once per build, at step 10.3, after `/en-simplify`. Consequently unit commits carry only the `phase:` trailer, the branch-level `review-verdict:` is the evidence for every unit including destructive ones, and the step 10.5 audit no longer has a per-unit evidence path. **What this costs:** a finding on a destructive unit now surfaces after the whole branch is built rather than before that unit commits, so it is cheaper to have caught it earlier and more expensive to fix. That is accepted because `/en-build` **writes** destructive code rather than executing it — a `DROP TABLE` in a migration is not run until deploy — and because the user-facing safety gates are unchanged: a destructive unit still requires the typed `"run unit U<N>"` confirmation and a gated unit still requires y/skip/abort, neither of which was ever peer review. **What it buys:** roughly 530 lines of two-flavor machinery deleted, one execution path to reason about instead of two, and an end to the recurring confusion between a *peer* (reviews, never edits) and a *worker* (implements, edits files) that the two-flavor design institutionalised.
- **D53. `/en-build` runs the full test suite once, after review remediation (latency pass).** Measured against a real 7h10m build (FR78, 2026-08-26): the full backend suite consumed **2h48m across twelve launches**, of which **three completed** and **eight were interrupted** before producing a result. Peer review and `/en-simplify` were not the bottleneck — the review agents took 27m of wall time and the simplifier 11m; the cost was remediation followed by another full suite. The sequencing caused it: after-phase verification ran the full suite at every phase boundary, step 10.1 ran it again before `/en-simplify` and `/en-review`, and applying review findings required yet another. A four-phase build paid five times before review had said anything, on an implementation review was about to change. **Now:** after-phase verification runs lint, typecheck and the tests covering that phase's files; step 10.1 is a lint-and-typecheck gate measured in seconds; review findings are applied in one batch; and the full suite runs **once**, at 10.4, after remediation. A running suite is never interrupted — it is bounded, and on overrun reported with its elapsed time rather than killed and retried, because eight discarded launches is where most of that 2h48m went. Elapsed suite time is surfaced in the summary so a suite worth sharding is visible to the user. **What this costs:** a late-phase change that breaks an earlier phase's test outside the targeted set now surfaces at 10.4 rather than at the phase boundary, so that debug window is longer when it happens. Accepted against 2h48m of suite time and eight wasted runs. Sharding the suite, resetting database state deterministically, and slow-test reporting are project concerns, not `/en-build`'s; the skill surfaces the timing that makes them worth doing.
- **D54. `/en-cross-review` merged into `/en-review` as its `--peer` mode.** The two skills dispatched the same peer, with the same brief, through the same `ensemble-peer-invoke`, parsing the same finding schema. They differed in target resolution and nothing else, and en-cross-review carried a second copy of the entire peer stack to express that difference. Its capabilities moved into en-review: `--focus` biases the peer's attention (narrowing emphasis, never coverage — a P0 outside the focus is still reported), and target resolution now accepts a ref range, a branch, uncommitted work via `--base HEAD`, and **a path to a file, reviewed as it stands rather than as a diff**. That last case is the only one en-review could not already express, and it carries its own rule: a file target has no base ref and no plan unit, so the spec axis does not apply and Coverage says which target shape produced the findings. **What it removes:** 4,147 lines, one duplicate peer stack, and one more place for the two copies to drift. It also deleted `build-handoff.md` and `build-orchestration.md` outright — 514 lines documenting `/en-build`'s two execution flavors, which D52 removed; en-build dropped them then and en-cross-review was their last carrier. **A consequence worth recording:** with en-build no longer emitting peer evidence per unit (D52) and en-cross-review gone, **no skill emits `peer-verdict:` or `peer-resolution:` trailers**. `/en-ship` still reads them on a documented legacy path for branches built before D52, and `ensemble-verify-peer-evidence` still parses them, so the format is read-only rather than retired. The assertions that checked a now-deleted file documented that schema were removed rather than repointed, because no surviving file documents a format nothing writes.
- **D55. A skill's payload is derived from its own body, not declared (supersedes EN13's `requires:` manifest).** EN12 inferred payload by walking every mention and produced 422 files where 193 were needed: one sentence in `learn-lint.md` naming `ensemble-lint` *to contrast against it* pulled a 45KB script and 56KB of references into `en-learn`. EN13 concluded that mentions are not dependencies and replaced the walk with a hand-written `requires:` block. That block was a second copy of the truth. It could answer "did someone list this?" and never "does the flow reach it?" or "does what this names exist?", so it carried `cli-wrappers.md` — a file calling itself the single source of truth for CLI flags while nothing read it — and never noticed that `en-setup` named a `scripts/check-health` it did not carry, breaking State-3 diagnostics on a lone install. The walk returns with the discriminator EN12 lacked: **a path counts only when backticked, a markdown link, or inside a fence**; bare prose never counts, which is exactly the `ensemble-lint` contrast sentence. Rules live in `tests/lib/skill-payload.py`, each commented with the file that taught it, and are proven on fixtures as well as on the tree. Validated before adoption: the derived set reproduced the hand-maintained manifest exactly in 13 of 16 skills, and each of the three differences was a payload bug, not a derivation error. **What this costs:** the rules are heuristics over prose, so a genuinely new way of naming a file is invisible until someone notices — the manifest could at least be read. The mitigation is that both directions now fail closed: an unreached carried file and an unresolvable named path each break the suite, so a missed edge shows up as a test failure rather than as silent drift. **What it buys:** 224 hand-maintained declarations deleted, two questions answered that the manifest structurally could not, and a frontmatter surface of `name` and `description` on all 16 skills, plus `disable-model-invocation` on the 6 that must not be model-invoked. `requires:` and `argument-hint` are both gone. **The one remaining non-spec key is deliberate:** `disable-model-invocation` is load-bearing in Claude Code, this suite's primary host, and dropping it would let those six be invoked automatically. Whether it blocks a claude.ai upload is unverified; revisit if publishing there becomes a goal. Enforcement tier: `tests/lint/skill-payload.test.sh`, both directions on the real tree plus seven fixtures, including a bare-prose case that fails if the EN12 inference returns.
- **D56. `/en-foundation` subtracts what it already knows, and checks that its ID graph connects.** The skill mints seven ID families (R, A, F, G, AE, D, Q) and, until 2026-09-01, never checked whether any of them connected: a goal no requirement served, or a requirement with no acceptance example, shipped silently into the document every downstream plan cites. It also asked 30–45 questions on a Deep run while its own orient step had just read the answers out of the repo. Six changes: **(1)** orient emits a **known-facts ledger** per discovery group and the discovery loop asks only what the ledger left open, confirming a detected group in one line instead of asking its full question set; **(2)** a **traceability gate** before synthesis, phrased as a judgment check — *every goal or actor that affects behavior is served by a requirement, or explicitly deferred with a reason* — and conditional on the section existing, so a Lightweight run that legitimately has no §8/§9 does not trip it; **(3)** a **precision rule** at draft time: report at the precision you actually have, never upgrade a directional goal into a measurable one, no invented metrics, no surviving placeholders, keep the user's terminology; **(4)** the retrofit **scopes before it scans**, taking hot spots from `git log` rather than sweeping the whole tree; **(5)** §9 requires a **second structurally distinct architecture** screened against four red flags (shallow module, information leakage, temporal decomposition, pass-through), with the rejected shape recorded as a D-ID; **(6)** 454 lines cut — `learnings-research` and `web-research`, which no step ever dispatched and which survived only on a backticked mention in a documentation list, plus `architecture-update-rules.md` (the seeded `architecture.md` cited a skill-internal path that means nothing in the consuming project) and `diff-signal-detection.md`. **The traceability gate is deliberately not a tally.** `ce`'s own traceability plan tried "every ID appears" and discarded it: a mechanical count invites requirements written to satisfy the counter, which then reach plans as real work. **What this costs:** a judgment check is easier for an agent to wave through than a count, and a one-line confirmation is easier to rubber-stamp than an open question — both trade a hard guarantee for the absence of padding, and both are enforced only as far as prose and drift tests reach. Design-it-twice adds a second architecture sketch to every Standard and Deep run. **Amends the D44 ladder's reach:** `diff-signal-detection` also leaves `/en-plan`, because `is_small_and_safe` is computed from a diff and scoped to `/en-review --lite`; a skill peer-reviewing a document it just wrote has no diff, so rung 2 is unevaluable and the fail-closed default lands it on the rung-3 medium floor. A prior pass declined this unlink, reasoning the ladder genuinely depends on the definition — true of the ladder, but not of the two skills that can never reach rung 2. Enforcement tier: `tests/lint/en-foundation-discovery.test.sh`, 32 assertions, each negative-controlled; one clause was found decorative that way and split in two. **The same check, run against `/en-learn`, found the same defect:** it carried a `repo-research` definition its flow never dispatched, orphaned when the one-time pattern-seeding mode that justified it was retired, and kept reachable by two carried files describing what *en-sweep* and *en-foundation* do with that agent. Cut, and the invariant behind it written down where it belongs: **en-learn scouts the wiki, never the codebase**, because it captures what reading the code cannot recover — so an agent whose job is reading the code answers a question it is not asking. Its one real dispatch site said "dispatch a sub-agent" without naming one, which is the vagueness that let the definitions drift out of any relation to the flow; it now names `learnings-research` and states that it is the only agent the skill dispatches. Both skills also gained an explicit row in the shared dispatch matrix, because in each case the contradiction survived on the matrix being silent about them.

- **D57. `/en-ship` resolves state before it acts, and ends in one named outcome.** A Codex post-mortem on a shipped PR, an internal audit, and six external skills reviewed `/en-ship` independently and converged on one defect class: the skill asserting things that had stopped being true. **The stale claim that mattered:** its plan-completion checkpoint accepted a per-unit evidence path that **D52 abolished** — en-build writes only `phase:` on unit commits now — so a branch that had shipped U1-U7, deliberately held U8 behind a production gate, and *had* been reviewed still reported `incomplete_build`. That single outcome conflated three situations needing three different responses, and is replaced by **`complete` / `partial_expected` / `complete_evidence_missing` / `incomplete_unexpected`**; `partial_expected` required a plan-side `Ship scope: in | deferred | production_pending`, because an outcome nothing can trigger is decorative. **The safety changes came from a real incident:** preflight never fetched, so a branch reached push time needing an unplanned rebase, during which an untracked file vanished — preflight now fetches, reports ahead/behind, predicts conflicts with `git merge-tree`, inventories untracked files and re-checks them after, and **never rewrites a published branch** without explicit approval. Staging became a five-case state machine and `git add .` is forbidden by name; the failure protocol no longer offers "stage all" on a dirty tree. **The watch loop became state-driven:** a doctor check before the first cycle and after any failed one, stale-SHA cancellation, **feedback before CI** (a comment pass that pushes invalidates every CI result on the old SHA, so repairing CI first spends a cycle on an orphaned commit), a cycle redefined as a repair-and-push rather than a poll with 15/30/60s backoff, and exactly one named terminal state. The delegate bound runs both ways: `/en-resolve-pr` may fix, commit, push, reply and resolve but never merge, rebase or force-push, and en-ship edits nothing itself. **`/en-resolve-pr` stays a separate skill.** `ce` splits the same way - `ce-babysit-pr` runs the loop and delegates finding-level work - and en-flow, en-debug and en-setup all reach en-resolve-pr without going through en-ship. The division of labour was right; only the contract between the halves was missing. **What this costs:** the preflight is slower by a fetch and a `merge-tree` on every run, and the five-case staging machine will occasionally refuse to guess where the old behaviour would have committed something plausible - both are deliberate, and the second is the point. Also **+31 lines**, not the flat outcome estimated: the step-8 collapse paid for less than the mechanisms cost. Enforcement tier: `tests/lint/en-ship-preflight.test.sh` and an extended `en-ship-watch-loop.test.sh`, 65 assertions, with all 36 prose clauses plus 5 structural and absence clauses negative-controlled; zero decorative on the first pass, which scoping every grep to a single file is what bought. **Deferred to a plan:** the verification receipt, structured state helpers, and a test-impact map - a cross-skill protocol touching en-build, en-ship, a pre-push hook Ensemble does not yet model, and AGENTS.md.
- **D58. A verification receipt lets one layer skip what another already proved (EN15, Tier 2 of D57).** A measured PR had four layers verifying the same tree with no way to see each other: `/en-build` ran the full suite, `/en-ship` ran lint and targeted tests, the project's pre-push hook ran 439 more *seconds later on an identical tree*, and CI ran the authoritative suite at 16m. `ensemble-verification-receipt` records which checks passed against an exactly-identified tree, in `.git/ensemble/` so it is per-clone, already ignored, and gone with the checkout. **Validity is a conjunction with no partial credit:** fingerprint, base SHA, dependency hashes, repo path and TTL must all hold, or the checks run. The fingerprint covers the committed tree, every tracked modification, and the *content* of untracked non-ignored files — a new source file is where a stale receipt would be most wrong, since the tests covering it do not exist in the committed tree at all. **Two things were deliberately not built.** Codex proposed "run tests covering the incoming base delta" as a receipt branch; that is test-impact analysis, which the same review shows this project cannot do reliably, and a receipt that silently under-tests is worse than none — a guard now fails if that path is reintroduced. And Ensemble **publishes a hook contract but never installs or edits a hook**: a hook is where a project encodes its own policy. Also shipped: two read-only state helpers (`ensemble-ship-preflight`, `ensemble-plan-checkpoint`) replacing prose that re-derived git and plan state, and a `test_impact:` map in **AGENTS.md** — not `.ensemble/config.local.yaml`, which is gitignored and so cannot be shared with CI. **What this costs:** a fingerprint on every ship, a TTL that will occasionally discard a receipt that would still have been sound, and a new format two skills must agree on. The TTL is the one invalidation input not derivable from the tree, and it exists because a toolchain can move under an unchanged tree. **Codex's headline framing was rejected:** it presented this as en-build-to-en-ship reuse, but its own post-mortem branch was rebased before ship, which changes the tree and invalidates any receipt — the reliable win is en-ship-to-hook, seconds apart. Enforcement tier: `tests/verification-receipt/` (68 behavioural tests against real fixture repos, one per refusal reason and per checkpoint outcome) plus prose-drift clauses in `en-ship-preflight.test.sh` and `en-build-suite-sequencing.test.sh`, every clause negative-controlled. **Two defects the tests found in the implementation itself:** the dependency-comparison path was untested because both fixtures also moved the fingerprint, and fingerprinting spawned one process per untracked file — 7s for 200 files, which would have made a large tree slower to fingerprint than to test.
- **D59. The `/en-ship` to `/en-resolve-pr` contract is stated from both sides (completes D57).** D57 wrote the delegate bound into `/en-ship` and nowhere else. `/en-resolve-pr` had never heard of it, and three consequences were live rather than theoretical: it could call a blocking question tool inside `/en-ship`'s **unattended** watch loop, waiting on a human who was not coming; its own 3-pass cycle nested inside the caller's 2 repair cycles, so six rounds of fix-and-push could run while the caller believed it had spent two; and its `--enable-auto-merge` could arm a merge that `/en-ship` deliberately holds back until its loop reports clean. A contract stated by one side is a hope. `--orchestrated` now carries the fact of being driven: **never blocks** (a `needs-human` item returns as a result and the open thread is the escalation ledger), **runs exactly one pass** (the caller owns the retry budget), and **refuses `--enable-auto-merge`** (merge policy belongs to whoever owns the PR's lifecycle). `/en-ship` passes it always, and both skills now state the same exclusions — merge, rebase, force-push, approve-checks — so neither is the only place the bound is written down. `--yes` is the opposite case: a human's standing consent to resolve `needs-human` items unattended, mutually exclusive with `--orchestrated`, which has no user to have consented. **Three rules the resolver owed on its own:** a reviewer-reported bug now owes a **regression test that fails before the fix and passes after it**, escalation reads **convergence rather than round count** (a flat or rising thread count is waste at round two, and a counter cannot tell that from progress at round three), and a `DIRTY` merge state has a path instead of a dead end — preserve both intents, never invent behaviour to make a conflict disappear, never `--abort`. Rebasing stays excluded and is now explained: it invalidates the review that approved the old head and the verification receipt D58 relies on (`base-moved`), so spending it is the caller's call. **What this costs:** a flag the caller must remember to pass — omitting it silently restores every failure above, which is why a guard asserts `/en-ship` passes it. The regression-test rule also slows a genuine one-line fix, and is written with an explicit escape that must be stated in the reply rather than taken silently. Enforcement tier: `tests/lint/en-resolve-pr-seam.test.sh`, 31 assertions including cross-skill clauses that both sides list the same exclusions; all 21 prose clauses and 3 structural ones negative-controlled, zero decorative.
- **D60. `/en-simplify` carries only what the pass it runs needs, and its reviewers are read-only.** 963 lines to 436. **The third D52 desync this campaign has found:** `code-simplifier-dispatch.md` was headed "(D29)" and described a per-unit pass — one dispatch per `U<N>`, between two verification gates, with its own triviality heuristic — while `/en-build` has run one branch-level pass since D52. The real model was appended to the old document as a footnote. Rewritten for the pass that exists, with the triviality heuristic **dropped rather than duplicated**: the caller owns that decision and two copies drift. **390 lines of host detection went** — step 1 sourced `host-detect.md` for one row of a tool-translation table, carried with 179 lines of peer machinery and a 211-line detection script, in a skill that invokes no peer; `recursion-guard.md` followed it, having been reachable only through it and documenting how to *set* a variable this skill only reads. **The reviewers are now declared read-only.** `code-simplifier`'s own description says it may modify files, which is true of it elsewhere and must not be true here: three run **concurrently against one working tree**, and three writers on the same files is a race whose losing edits vanish without an error. Because they only find and the parent applies, this is evidence-tier work — `ce-simplify-code` reached the same conclusion independently and runs its three reviewers mid-tier. **Four mechanisms adopted from it:** a **kind gate, never a size gate** before dispatch (three agents no longer read a lockfile diff, while a three-line scope the user named still runs); **inspect widely, edit narrowly** (reading beyond scope is expected, editing beyond it is not); an **unshipped-only interface is not behavior**, so a compatibility shim introduced earlier in the very work being simplified can go; and **backpressure is not failure** — a concurrency limit requeues, an undispatchable reviewer runs inline with the same rubric and the substitution is disclosed, and a partial roster is never reported as a pass. A caller-supplied scope that resolves empty is now a **result to return, not a question to ask**, because `/en-build` invokes this inside a phase whose autonomy contract permits pauses in seven enumerated cases and this is not one. **What this costs:** the kind gate will occasionally decline a scope whose only code is a one-line fix buried in generated churn, and the inline fallback produces a weaker review than a fresh context — which is why it must be disclosed rather than counted as equivalent. Enforcement tier: `tests/lint/en-simplify.test.sh`, 30 assertions, all 15 prose clauses and 3 structural ones negative-controlled including a **cross-skill clause asserting `/en-build` still describes the pass as branch-level**, so a fourth desync fails rather than accumulates.
- **D61. `/en-qa` selects a browser driver, and tests only what the change touched.** Two defects, both of them the skill assuming a world it does not get to assume. **It was locked to one stack:** Playwright named 16 times, with *"Verify Playwright MCP. If unavailable -> run Phase 1 only"* — so on a host carrying a perfectly good native browser, en-qa declined to do its job and reported a gap. It now selects a driver in order — host-native surface, then Playwright MCP, then Phase 1 only — **never introduces a third stack** (a project with no driver is reporting a fact about itself; installing one turns a QA pass into a setup task nobody asked for), and **keeps one driver for the whole run**, because element references, screenshots and auth state do not survive a switch and a mixed run produces a report whose earlier evidence describes a session that no longer exists. **And it tested everything, always:** the `needs_browser` detector decided *whether* Phase 2 ran, never *what* ran inside it, so a one-route change walked the entire §6 catalogue. **This is QA of a change, not a release regression sweep.** Changed files are attributed to the flows they can reach and only those run; `--all-flows` is the explicit opt-in for the sweep. Critically, **incomplete attribution does not expand the run** — unattributable files are reported under "impact undetermined" rather than triggering a silent full pass, because expanding trades a stated gap for an unstated cost and the reader can no longer tell which flows were implicated from which were swept up. Three further rules: **every in-scope flow ends Pass, Fail or Skip-with-reason** and none may be absent (an absent flow reads as one that passed); a flow needing **external interaction** — OAuth, email, SMS, real payments — is skipped with that reason rather than faked; and a regression test must **exercise a real interface**, since a test whose only evidence is a source string proves nothing when the text is dead or a refactor moves it. **The orchestrated seam, third instance:** `/en-build` and `/en-loop` both hand off here and `/en-loop` runs unattended overnight, so URL discovery, driver selection and framework bootstrap each become a Skip rather than a question — a question asked with nobody watching does not fail, it waits, which is worse. **What this costs:** attribution is a heuristic over imports and routes, so a change whose blast radius it under-reads gets less QA than a full sweep would have given — accepted, because the alternative buries the finding that matters in a wall of green, and the undetermined-impact list is what keeps the gap visible. Enforcement tier: `tests/lint/en-qa-browser-detector.test.sh`, 27 assertions, all 17 prose clauses plus 2 structural ones negative-controlled including the driver **order**, since a preference listed second is decorative.
- **D62. `/en-debug` classifies a fix before applying it, and shows its findings before asking.** The safety change is **convergent vs divergent**, an idea the skill contained zero occurrences of. A convergent fix restores behavior everyone agrees is correct; a **divergent** one would reverse a deliberate decision and is surfaced rather than applied. The case that catches people: **a failing test may be asserting the behavior that is correct** — it fails because the change deliberately reversed what it asserts, so "fixing" it deletes a guarantee someone wrote on purpose. When the side is unclear the fix is treated as divergent, because the cost of asking is a question and the cost of guessing wrong is a silently removed invariant. **The gate now shows its work first:** the findings block is written in full before the blocking question opens, because a question tool renders only its own stem on a modal surface — and *naming the options is not presenting the findings*. **The pre-fix scope is recorded before any edit** (HEAD, tree cleanliness, files already carrying changes, then a running list of fix-owned files): afterwards it cannot be reconstructed, and without it the handoff cannot tell the skill's changes from the user's — the same class as D57's untracked-file inventory. Three investigation techniques from `systematic-debugging`: **instrument component boundaries before theorising** (log what enters and leaves each seam, run once to find *which* boundary breaks — the same correlation telemetry mode does across spans, done by hand when there is no telemetry); **find something that works and diff it**, without filtering the differences, since "that can't matter" is the judgement that hides the cause; and **three failed fixes is a signal about the design, not a fourth hypothesis** — the tell is the shape, each fix revealing new coupling elsewhere or needing a large refactor to land. **Payload:** `learnings-research` was carried and never dispatched (fourth instance after en-foundation, en-learn and en-simplify) — a telemetry hypothesis is anchored in the log line in front of it, not in prior write-ups. **`research-dispatch.md` stays, and cutting it was this pass's first and wrong move:** it has no `en-debug` row, which made it look vestigial, but `repo-research` follows its evidence-dossier protocol. The payload check caught it; the fix was the missing row, not the removal. **A negative finding worth recording:** nothing in Ensemble invokes `/en-debug` — `/en-ship` routes a failing check to `/en-resolve-pr` and `/en-build` hands off — so code mode's blocking gate is **deliberate**, not the unattended-stall defect found in en-resolve-pr, en-simplify and en-qa. Adding an orchestrated mode here would be machinery for a caller that does not exist. **What this costs:** the divergent classification will occasionally escalate a fix that was convergent all along, and the boundary-instrumentation pass costs a run before any hypothesis is formed. Both are deliberate: the first is asymmetric in the safe direction, the second replaces an hour spent in the wrong layer. Enforcement tier: `tests/lint/en-debug-fix-loop.test.sh`, 27 assertions, all 14 prose clauses plus 4 structural ones negative-controlled — including the **ordering** of findings before gate, since that is A2's entire content. One clause was caught weak before testing: a bare `"which"` would have passed for any input.
- **D63. `/en-setup` carries nothing it dispatches, and its own step numbers now resolve.** 4,581 lines to 3,626. **Two agents and the matrix they live in, none of it used:** SKILL.md named `repo-research` and `learnings-research` **zero** times each and en-setup had **no row** in the dispatch matrix; all three were reachable only through `research-dispatch.md` and `agent-dispatch.md`. Fifth instance after en-foundation, en-learn, en-simplify and en-debug — and unlike en-debug, where cutting the matrix was wrong because a dispatched scout followed its dossier protocol, here nothing dispatches anything, so the three go together. Removing them left `agent-dispatch.md` carried by a skill with no `agents/` directory, which the guard added in the compression pass caught immediately. **`HOST` was set at step 1 and read nowhere** — 179 lines of `host-detect.md` plus a 211-line detection script populating two variables no later step consults. en-setup writes the same `AGENTS.md` and `CLAUDE.md` on either host, offers the same guardrail, and invokes no peer; `recursion-guard.md` followed, reachable only through host-detect and documenting how to *set* a variable this skill only reads. **The step numbering was broken in two ways:** a step numbered `13a` sat between 14 and 15, and **five of nine internal citations were off by one** — the bin-script step cited *itself* as the sweep-workflow step, and the verification table pointed at 13/15/12/11 where 14/16/13/12 were meant. Nothing checked it: `cross-file-step-citations` guards citations *between* files, and intra-file ones were unguarded suite-wide. **New repo-wide guard, with its limit stated:** `intra-file-step-citations.test.sh` catches a citation to a step that does not exist and a step list that goes backwards; it **cannot** catch a citation naming a real but wrong step, since "step 13" resolves fine when 14 was meant, so those five are pinned individually to the artifact each step installs. Its first draft reported nine false positives — nested sub-steps written `**9a. ...**` were not counted as defined, and numbering legitimately restarts at each `## ` heading. **This entry also fixes the decision log itself:** D57 through D61 had been written in *descending* order, each pass anchoring on its predecessor and inserting before it. A guard now requires the numbers to ascend. **What this costs:** the pinned citations are maintenance — inserting a State-2 step now means updating a test, which is the point but is friction — and the general guard's pass means "none dangle and the order is sane", never "the citations are correct". Enforcement tier: `intra-file-step-citations.test.sh` repo-wide, plus 27 assertions in `en-setup-scaffold.test.sh`, all negative-controlled including reproducing the 13a-after-14 defect. One clause was the rule forbidding its own explanation — it matched `PEER_AVAILABLE` in the sentence saying the variable is gone, the same shape as the harness hash guard, and was fixed the same way.
- **D64. `/en-guardrail`'s documentation now matches its architecture, and EN09's hardening is guarded.** **The behaviour was already sound.** 28 adversarial probes against the live hook — `rm` option ordering, compound commands, SQL comment spoofing, `UPDATE` scoping, redirection truncation, the artifact-exemption boundary, and agent self-exemption — **all fail closed**, and no bypass was found. The defect was that the skill described a different program. **`check-guardrail.sh` contains zero pattern matches**; all 46 live in `guardrail_analyze.py`, because EN09 moved them there when bash-regex parsing proved bypassable in six named classes. But "How it works" still described the wrapper as matching a catalogue, and the failure protocol told a maintainer to *"tighten the regex in `bin/check-guardrail.sh`"* — a file with no regex. In a security skill that is not cosmetic: following it means either failing, or **adding a bash regex back into the wrapper and reopening the class EN09 closed**. The protocol now points at the analyzer and says explicitly not to add matching to the wrapper. "Reference files" listed one of three scripts, leaving **623 of 818 lines undocumented**, including the analyzer where all behaviour lives. **The tests were canonical-form heavy** — 101 assertions, almost all of them `rm -rf /tmp/foo`-shaped, which pass whether or not the parsing is real. A regression suite now covers one fixture per bypass class, recorded as confirmed-passing rather than as a fix still to make. Its value was checked by breaking the analyzer three ways: crippling the shell tokeniser fires 5 fixtures, widening the artifact allowlist to a substring test fires 2, and deciding the local exemption from raw SQL text instead of the parsed connection target — the exact spoof EN09 removed — fires 3. **What this costs:** the fixtures pin current behaviour, so a deliberate change to a rule now means updating a test, which is the point but is friction. **A note on method:** for a security skill, probing the live hook was better evidence than a structural comparison, and no external analogue was worth forcing. One fixture of mine asserted the wrong expectation — that an `UPDATE` with a top-level `WHERE` containing a subquery should prompt — which the analyzer correctly refused; a wrong expectation in a security test is worse than no test, since it would have been "fixed" by making the guard over-prompt. Both directions are now pinned. Enforcement tier: `tests/en-guardrail/check-guardrail.test.sh`, 154 assertions.
- **D65. `/en-sweep`'s activity gate could be silenced by an ordinary human commit, and nothing tested it.** `SWEEP_PATTERN` included `chore(docs):`, a scope humans reach for constantly. A repo whose only new commit was `chore(docs): fix a typo` got `should-run=false`: the commit was picked as `LAST_SWEEP_SHA` **and** subtracted by `--invert-grep`, and both errors push the same way, toward skipping. That is the green-but-inert failure this project already shipped once (FR01 U11), reached by a different route, and it was invisible because a skipped cycle posts no PR, no comment and no log a user reads. The scope was there legitimately: sweep's lint batch authored `chore(docs): fix N lint findings`. **The rule now is that every scope the gate treats as sweep's own must be one a human would not type**, so the lint batch ships as `chore(sweep):` and `docs` is gone. Repos with older history carry `chore(docs):` sweep commits the pattern no longer recognises; those cycles run when they might have skipped, which is the safe direction. The gate had **zero assertions** before this; it has 14, and the fixture for this case fails against the old pattern. **`sweep-loop-guards.md` described a program that was replaced.** It was written for the `push` trigger, where sweep fired on its own auto-merged PRs, and five guards existed to break that cycle. Sweep is scheduled now, so two of the five cannot fire, and the file still explained them as live, argued "why all five", and listed a five-test plan covering guards with no trigger. Worse, `SKILL.md` and the reference **numbered the same guards differently**, and `SKILL.md` used both schemes in one file: its own list called the depth cap Guard 3 while a later line said "Guard 5 enforces". The retired two are now gone rather than demoted, their numbers are not reused, and both files count to three the same way. **`agents/learnings-research.md` was carried and never dispatched** (150 lines, the sixth instance this campaign). en-sweep's one scout is `repo-research`, for architecture drift; the wiki-graph check runs `/en-learn --lint`, a skill, not an agent. It stayed reachable through the tier table in `agent-dispatch.md`, which names all three scouts generically and so vouches for each of them in every skill that carries it. The fix is the missing matrix row, not just the deletion. **The Configuration block named the wrong file:** `~/.ensemble/config.json`, which is real but holds `peer_mode_override` for host detection. Sweep reads `.ensemble/config.local.yaml`. It also advertised `ci_timeout_minutes`, which nothing substituted into the workflow's hardcoded `timeout-minutes: 30`, and omitted `max_drafts_per_run`, which `triage-findings` actually parses. **What this costs:** the `chore(sweep):` rename means sweep's own scope vocabulary is now load-bearing, so adding a batch type is a decision about collision, not just naming. **A correction worth recording:** the audit first called `max_prs_per_run` and `auto_merge_enabled` dead too. They are read, by the skill's own steps 11 and 14. An LLM-executed setting is a real setting, just one whose reliability is the step that cites it, and the config block now says which kind each key is. Enforcement tier: `tests/en-sweep/activity-gate/activity-gate.test.sh` (14) and `tests/parity/research-dispatch-parity.test.sh` (15).
- **D66. A skill may not refer to itself by its repo path, and the dispatch matrix must have a row for every skill that carries it.** Both invariants were held by convention and broken in practice. `skills/en-sweep/scripts/x` resolves only from the root of this checkout; skills install one directory at a time into `~/.claude/skills/`, where no `skills/` parent exists. en-sweep had three such paths **beside eleven correct `$SKILL_DIR` uses in the same file**, which is what let them survive: each new one looked like the ones already there. The repo-wide guard found eight more in three other skills, including a live bug: `en-setup/scripts/check-health` probed for its lint at a repo-rooted path, so in any consuming project it took the "Reinstall the plugin" branch and reported the lint missing while it sat two directories up. The guard allows an env-anchored absolute path (`${ENSEMBLE_HOME:-...}`), which is how `/en-guardrail` writes its hook command into `settings.json`: that is a path into the source checkout chosen at install time, not one a running skill resolves. The allowance is line-scoped, confirmed by adding a bare path to that same skill and watching it fail. The second invariant is the mechanism behind D65's third finding and three before it: a carried scout stays alive when the matrix has no row denying it. Asserting the row surfaced a fourth case immediately, en-review carrying the matrix with no entry. **What this costs:** a new skill that carries the dispatch matrix now has to declare its dispatches before the suite goes green, and the self-path guard forbids a citation form that reads naturally when you are working from the repo root. **A correction:** the row assertion's first reading was that en-review also carried a `repo-research` definition it never dispatched. It does not carry one; its only defect was the missing row. Enforcement tier: `tests/lint/skill-self-path.test.sh` (16).
---

## 5. Skill Catalog

Fourteen skills total: the lifecycle skills (brainstorm → foundation → plan → build → review → qa → learn → ship → resolve-pr) plus orthogonal skills (`en-debug`, `en-guardrail`, `en-loop`, `en-sweep`, `en-setup`). All prefixed `en-` to namespace cleanly alongside other plugins.

### 5.1 Skill summary

| # | Skill | One-line purpose | Primary input | Primary output | Cross-review | Host-detect |
|---|---|---|---|---|---|---|
| 1 | `en-brainstorm` | Q&A + research + 2–3 approaches with trade-offs | Idea, problem, or rough description | `docs/designs/YYYY-MM-DD-<topic>.md` | Off (default) | Optional |
| 2 | `en-foundation` | Combined PRD + technical direction + initial architecture for a new product. Asks for `plan_id_prefix` (2–3 uppercase letters; default `FR`). | Brainstorm design doc OR direct invocation | `docs/foundation.md`, `docs/architecture.md`, `AGENTS.md`, `CLAUDE.md` | On (default Yes) | Yes |
| 3 | `en-plan` | Feature/component/refactor plan with stable U-IDs and `plan_type` (feature \| improvement \| bug). Modes: default; `--resume <plan>` (promote a draft); `--from-legacy <path>` (migrate legacy plan into Ensemble flow). | Brainstorm output, foundation, direct request, or legacy plan | `docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md` | On (default Yes) | Yes |
| 4 | `en-build` | Execute the plan with branch/worktree, batched. Flips `status: open → in_progress` at start. | Plan path | Code + commits on a feature branch | On (per unit) | Yes |
| 5 | `en-review` | Multi-persona code review of current branch. **Confidence-gated** — sub-threshold findings file as TD entries, not surfaced. | Branch with changes | Review report + applied auto-fixes; sub-threshold → tech-debt-tracker.md | Off (default), `--peer` to enable | Yes |
| 6 | `en-qa` | System checks + browser end-to-end testing | Branch + optional URL | Bug fixes + new regression tests | Off | Optional |
| 7 | `en-learn` | Compounding wiki maintainer. **`capture`** (default): gate, route to one of three artifact types, ground the claims, sync architecture / foundation / plan, maintain cross-refs. **`--refresh`**: audit content staleness per artifact type. **`--lint`**: graph health. **`--migrate`**: move a project off the retired category layout. | Commits/branch, or an existing learning store | A term, decision, or solution; doc updates; index/log updates; cross-refs | Off | Optional |
| 8 | `en-ship` | Pre-flight + commit + push + PR. `--auto-merge` enables `gh pr merge --auto` from the start. | Branch with clean changes | Commit + PR (with optional auto-merge) | Off | Optional |
| 9 | `en-resolve-pr` | Address incoming PR review feedback. 6-verdict triage (`fixed` / `fixed-differently` / `replied` / `not-addressing` / `declined` / `needs-human`). Vendored GraphQL helpers; reports merge readiness; `--enable-auto-merge` flag. | Current branch's PR (or PR# / comment URL) | Code commits + replies + resolved threads | Off | Yes |
| 10 | `en-debug` | Telemetry-driven debugging. Reads structured logs per `references/observability-conventions.md`; correlates by trace_id / request_id / event; surfaces hypothesis with file:line + confidence. **Read-only.** | Trace ID, request ID, error message, file:line, or none (tail) | Hypothesis + suggested next-step skill | Off | Yes |
| 12 | `en-sweep` | Event-driven doc-drift cleanup on every PR merge to `main`. Opens auto-merging doc-only PRs. **Continuous monitoring** (opt-in): dead-code + dep-vuln scans with size-based triage (trivial → TD; pattern/severe → draft plan in `docs/plans/active/`). | Repo state (post-merge) | Auto-merging cleanup PRs + TD entries + draft plans | Off | Yes |
| 13 | `en-guardrail` | Always-on `PreToolUse` hook that prompts before destructive Bash commands (recursive rm, DROP TABLE, force-push, terraform destroy, aws s3 rm --recursive, etc.). Localhost+test/dev DB exemption. Per-command bypass via `ENSEMBLE_GUARDRAIL=off`. Installed globally via `~/.claude/settings.json` or project-scoped via `<repo>/.claude/settings.json`. | Bash tool input (intercepted) | Permission prompt or pass-through | Off | Optional |
| 14 | `en-setup` | Project-level bootstrap and diagnostics. Detects state (1 / 2 / 3); for State 2 retrofit: archives non-conforming legacy plans, creates skeleton, generates `AGENTS.md` + `CLAUDE.md`, installs `.github/workflows/en-sweep.yml`, offers guardrail / Anthropic Code Review action / Codex Code Review action installs, checks repo-level `allow_auto_merge`, surfaces `CONTEXT.md seeding` offer. | Repo state | Project skeleton, config files, GH Action workflows, diagnostic report | Off | Yes |
| 15 | `en-loop` | Bounded, objective-driven autonomous loop (wraps the `gnhf` CLI): one committed test-gated slice per iteration until an evidence-based stop condition; branch-level cross-agent review at checkpoints (`--review-every N` + loop end). Manual-invoke only; never auto-merges. | Objective + evidence-based stop condition | Reviewed feature branch + gnhf exit summary | On (branch-level, at checkpoints) | Yes |
| 16 | `en-flow` | Pipeline runner: chains skills end to end for a single unit of work. | A task description | A completed pass through the chained skills | Off | Optional |
| 17 | `en-simplify` | Behaviour-preserving simplification of the branch diff across reuse / quality / efficiency. Called by en-build post-build and usable ad hoc. | Branch diff vs base | Simplified working tree, unchanged behaviour | Off | Optional |

### 5.2 Skill details

#### 5.2.1 `en-brainstorm`

- **Purpose.** Explore an idea through Q&A, research prior art, propose 2–3 approaches with trade-offs, run a devil's-advocate pass, and write a design doc.
- **Process (high-level).** (`skills/en-brainstorm/SKILL.md` is canonical; this is a summary.)
  1. Detect host (light — only needed for path conventions).
  2. Scope check (Lightweight / Standard / Deep).
  3. Existing context scan (`docs/foundation.md`, `docs/plans/`, recent commits, related code).
  4. Q&A via **frontier rounds** — model open decisions as a design tree, ask each round's independent frontier in one numbered batch with a recommended answer per question (one-per-turn retained on Lightweight and for rigor probes); facts are looked up non-blocking, never asked; default to the host blocking question tool `$QUESTION_TOOL`, open-ended only when genuinely open (D39).
  4b. **Resume or start fresh** — an open `docs/designs/*.md` matching the topic is offered for resume and updated in place, never duplicated (D47).
  4c. **Blindspot gate** — when the user cannot *evaluate* part of the territory (not merely undecided), map its decision surface before interviewing into it; territory-scoped, once per territory, never in a non-interactive run (D47).
  5. **Product pressure test** — self-gating rigor-gap probes before approaches (evidence / specificity / counterfactual / attachment / durability; EN05/D39).
  6. **Integration check** — probe non-obvious combination consequences before approaches (EN05/D39).
  7. Optional research via `web-research` agent (Context7, WebSearch).
  8. Propose 2–3 approaches with trade-offs and a recommendation — **divergently generated** via parallel constraint-diverged sub-agents on Deep, or Standard with 3+ live directions (D47).
  9. Devil's advocate — stress-test the recommendation.
  10. Present design and get user approval.
  11. **Verify-before-claiming** — verify absence-claims against the repo or label them unverified assumptions (EN05/D39).
  12. Write to `docs/designs/YYYY-MM-DD-<topic>-design.md`.
  13. Hand off — suggest `en-foundation` (new product) or `en-plan` (feature).
- **Hard gate.** Does not invoke implementation skills.
- **Cross-review.** Off by default. Brainstorming is exploratory; outside critique here is premature.
- **Reference files.**
  - `references/socratic-questions.md`
  - `references/research-dispatch.md`
  - `references/templates/design-doc-template.md`

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

- **Purpose.** Turn a feature, component, or refactor into a concrete implementation plan with stable U-IDs and `plan_type`. Reads `foundation.md` and any relevant brainstorm design doc.
- **Modes.**
  - **Default** — fresh plan from a request.
  - **`--resume <plan-path>`** — promote an auto-generated draft (typically from `/en-sweep`'s continuous-monitoring) into a full peer-reviewed plan. Preserves `plan_id`, `plan_type`, `created`, `generator`.
  - **`--from-legacy <path>`** — read content from a legacy plan (typically `docs/plans/legacy/<file>.md` archived by `/en-setup`'s State 2 step 2). Legacy file is **not modified or moved**; this flag uses it as input to mint a *new* Ensemble plan with frontmatter `migrated_from: <legacy-path>` for traceability.
- **Process (high-level).**
  1. Detect host. Resolve peer.
  2. Resume / `--from-legacy` / create fresh.
  3. Source the request: brainstorm doc, foundation, bug report, legacy plan, or rough description. Foundation is read **bounded** (frontmatter + section index + only the sections needed), never whole. A matching design doc's settled decisions are **carried, not re-asked** (D48). **Infer `plan_type`** (`feature` / `improvement` / `bug`); confirm if ambiguous.
  4. Right-size depth (Lightweight / Standard / Deep).
  5. Phase 1 research — dispatch `repo-research` and `learnings-research` agents in parallel. Optionally `web-research`.
  5b. **Context-sufficiency check** — when the problem, the approach, or the scope is genuinely unresolved, recommend `/en-brainstorm` first; never a hard gate, and gaps recorded as explicit assumptions if the user proceeds (D49).
  6. Resolve planning questions via **frontier rounds** — architecture in round 1, then file boundaries / test strategy / dependencies / migrations together in round 2, each with a recommended answer; one-per-turn retained on Lightweight (D48).
  7. Break the work into implementation units with stable U-IDs (`U1`, `U2`, …).
  8. For each unit: Goal, Requirements covered, Dependencies, Files, Approach, Execution note, Patterns to follow, Test scenarios, Verification.
  9. Resolve `plan_id_prefix` from `foundation.md` (default `FR`); auto-increment `<NN>` per-prefix.
  10. Write to `docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md` with `status: draft`. (User flips to `open` after acceptance; `/en-build` flips to `in_progress`; `/en-learn capture` flips to `completed` and moves the file.)
  11. **Outside Voice review** — peer agent critiques the plan; user incorporates agreed findings.
  12. Confidence check; capture-from-synthesis reflex.
  13. Hand off to `en-build`.
- **Cross-review.** On by default.
- **Reference files.**
  - `references/templates/plan-template.md`
  - `references/host-detect.md`
  - `references/outside-voice.md`
  - `references/research-dispatch.md`
  - `references/stable-ids.md`

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

- **Purpose.** Multi-persona code review of current branch changes against the plan and project conventions. Confidence-gated — sub-threshold findings are filed as TD entries instead of cluttering review output.
- **Process (high-level).**
  1. Detect host. Determine diff base (PR target, default branch fallback).
  2. Read plan(s) referenced by the branch.
  3. Always-on personas: `correctness`, `testing`, `maintainability`, `standards`. Plus `learnings-research`.
  4. Conditional personas based on diff content: `security`, `performance`, `migrations`.
  5. Each persona returns structured JSON with `confidence: 1-10`. Synthesis merges, dedups, classifies.
  6. **Confidence gate.** Findings with `confidence < threshold` (default `7`, configurable via `~/.ensemble/config.json` → `review.confidence_threshold`) are filed as TD entries with marker `Filed by /en-review (confidence <N>)`. P0 findings always surface regardless of confidence (with `low_confidence: true` flag if rated low). Skipped in `report-only` mode (sub-threshold findings returned in `sub_threshold_findings: []` instead). Per `references/review-confidence-gating.md`.
  7. Apply `safe_auto` fixes automatically.
  8. Present `gated_auto`, `manual`, and `advisory` findings grouped by severity.
  9. User picks which to apply.
  10. Optional `--peer` flag enables Outside Voice cross-review on top of personas.
  11. Output review report (markdown) and a JSON envelope (for programmatic callers). Both include `sub_threshold_filed_count`.
- **Modes.** Three modes determine whether `en-review` may modify files:
  - **`interactive`** (default for direct user invocation) — auto-applies `safe_auto` fixes, presents `gated_auto`/`manual` findings to the user. May write to the working tree.
  - **`headless`** (default for skill-to-skill invocation in non-CI contexts) — auto-applies `safe_auto` fixes silently and returns structured JSON for the calling skill. May write to the working tree. Used by `en-build` per-unit and `/en-review`.
  - **`report-only`** — strictly read-only. No file edits, no commits. Returns findings JSON only. **Required mode when `en-review` is invoked from CI** (e.g., by `en-sweep`). The reason: mutation in CI would push a commit, which retriggers sweep — and more fundamentally, a "verification gate" that mutates is conceptually muddled. Verification and repair are separate steps.

  Mode is selected by the calling skill, with these mandatory rules:
  - When `en-build` invokes `en-review` per-unit → `headless`.
  - When `en-sweep` invokes `en-review` to gate a PR → `report-only` (always; not configurable).
  - When the user invokes `/en-review` directly → `interactive`.
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
- **Modes.** `capture` (default), `--refresh`, `--lint`, `--migrate` (one-time retrofit; seeds `patterns/` from existing codebase via `repo-research`; entries flagged `source: bootstrap` and `requires_validation: true`, default `confidence: 6`).
- **Always-on behavior for `capture`:**
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
  8. **Move the relevant plan** from `docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md` to `docs/plans/completed/<…>.md` — flip status from `in_progress` (or `open`) to `completed`, set `shipped: <date>`, replace plan-tense with documentation-tense. Note any deviations from the plan.
  9. **Sync `AGENTS.md` / `CLAUDE.md`** if the artifact directory or top-level guidance changed (rare).
  10. Update `docs/README.md` index.

##### Mode C: `--refresh`

Audit existing learnings for *content* staleness. For each entry: keep, update, replace, or archive (move to `docs/learnings/archive/`). Useful periodically (~monthly) or after a big architectural shift.

Distinct from `--lint`, which audits *structural* health.

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
- **Output.** A report grouped by check, with severity (P1 = orphan, broken link, missing back-ref; P2 = missing page, data gap, log drift; P3 = contradiction needing human judgment). For mechanical findings (P1, most P2), `learn --lint --fix` auto-applies fixes (add the missing back-ref, repair the broken link, regenerate `index.md`). Contradictions and content-judgment items go to the user.
- **Cadence.** On demand (`/en-learn --lint`), or invoked by `en-sweep` as part of its post-merge pass. `en-sweep` invokes `en-learn --lint` and routes the output through its PR-batching flow.

- **Cross-review.** Off by default in all modes (`--peer` to enable).
- **Reference files.**
  - `references/learning-template.md`
  - `references/learning-frontmatter-schema.md`
  - `references/learn-cross-ref-maintenance.md` (the always-on behavior)
  - `references/learn-index-format.md` (curated `index.md` structure)
  - `references/learn-log-format.md` (append-only log conventions)
  - `references/learn-lint.md` (the check catalog and auto-fix rules)
  - `references/architecture-update-rules.md` (when to touch `docs/architecture.md`, what counts as material)

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

#### 5.2.10 `en-sweep`

- **Purpose.** Doc-drift cleanup that runs *automatically after every PR merge to `main`*. Scans the merged code against documentation artifacts, identifies what drifted, opens *doc-only* fix-up PRs, and auto-merges them after `en-review` clears them. Pays down doc debt continuously without ever modifying code.
- **Strict scope: doc-only.** `en-sweep` **never** modifies source code, configuration, tests, or any non-doc artifact. If it notices a code-level pattern that should be refactored (a duplicated helper, a layer-rule violation, a hand-rolled util that has a shared equivalent), it files the observation as an entry in `docs/plans/tech-debt-tracker.md` for `en-plan` / `en-build` to handle later. This separation is non-negotiable: `en-sweep` running unattended (auto-triggered, auto-merged) means it must touch only artifacts where the blast radius is bounded to documentation.
- **Trigger model — scheduled with activity gate.** Default trigger: **cron schedule** (default `0 9 * * 1` — Monday 9am UTC; configurable via `sweep.schedule` in `.ensemble/config.local.yaml`: `daily` / `weekly` / `monthly` named values, or a literal cron expression). Manual invocation also supported via `workflow_dispatch` (Actions UI) or `/en-sweep` slash command. Implemented as `.github/workflows/en-sweep.yml` installed by `/en-setup`.

  **Activity gate.** Before the sweep job runs, `bin/ensemble-sweep-activity-check` walks `git log` for the most recent sweep-authored commit on `main` (matches the same `chore(sweep|arch|plans|learnings|maps|docs):` patterns sweep produces) and counts non-sweep commits since then. Zero → skip silently (no LLM calls, no PRs, no comments). Non-zero → run. Manual `workflow_dispatch` always bypasses the gate.
- **Why scheduled-with-gate beats every-merge.** Every-merge fires sweep on commits that introduce no detectable drift (typo fixes, test renames, peripheral changes). The activity gate alone wouldn't help in that model because there's always activity per-merge by construction. A scheduled cadence with the activity gate gives predictable cost (one sweep per cadence) while the gate skips quiet weeks entirely. Drift detection latency (up to one cadence cycle) is the trade-off; for most projects, weekly is fine.
- **Why a separate skill from `en-learn`.** `en-learn` captures lessons in conversation, in real time, in the user's working session. `en-sweep` runs unattended in CI. Different cadence (event-driven vs invocation-driven), different scope (doc drift vs lesson capture), different blast radius (auto-merge vs human-confirmed).
- **Process (high-level).**
  1. Triggered by `push` to `main`. CI checks out the repo and runs `/en-sweep`.
  2. Detect host (CI runner). Resolve peer for any `en-review` invocations within sweep's PRs.
  3. Run doc lints (`bin/ensemble-lint`) — file-shape checks. Capture violations.
  4. Run `en-learn --lint` — wiki-graph checks (orphans, missing back-refs, etc.). Capture violations.
  5. Compare `docs/architecture.md` against current code via `repo-research` agent: are documented components still present? Are dependency rules still honored? Are layer boundaries still clean?
  6. Cross-check `docs/plans/active/` for plans whose work has shipped on `main` — they should be moved to `completed/`. (`en-learn` handles the move during normal flow, but if the user shipped without invoking `en-learn`, sweep catches it.)
  7. Cross-check `AGENTS.md` and `CLAUDE.md` against current `docs/` structure — pointer-map drift.
  8. Categorize findings strictly into doc batches; surface code-level findings to `tech-debt-tracker.md`:
     - `chore(docs): fix broken cross-refs in foundation.md`
     - `chore(arch): document new ProvidersV2 boundary in docs/architecture.md`
     - `chore(plans): move EN03 to completed/`
     - `chore(learnings): add missing back-refs in patterns/`
     - `chore(learnings): archive 4 superseded entries`
     - `chore(maps): update AGENTS.md pointer to new docs/references/ entry`
  8a. **Continuous monitoring (opt-in).** When `.ensemble/config.local.yaml` declares `sweep.continuous_monitoring.dead_code: true` or `dep_audit: true`, run `skills/en-sweep/scripts/continuous-monitor` (wraps `ts-prune` / `vulture` / Go `deadcode` / `npm audit` / `pip-audit` / `cargo audit`) and pipe through `skills/en-sweep/scripts/triage-findings`. Output is partitioned by **size**:
     - Trivial / mechanical (single dead function; dep-vuln with auto-fix; `loc_estimate` < `sweep.auto_plan_threshold_loc`) → append to `tech-debt-tracker.md` with marker `Filed by /en-sweep (continuous-monitor)`.
     - Pattern / structural / decision-required (≥ `sweep.auto_plan_threshold_locations` dead-code findings clustered in same area; severe CVE without auto-fix) → write a draft plan in `docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md` with `status: draft`, `generator: en-sweep`, `generator_run: <merge-sha>`, `generator_checks: [dead-code|dep-audit]`, `area: <subtree>`. Capped at `sweep.max_drafts_per_run` (default 3); overflow rolls to TD with a "would have been a plan" note.
     - Idempotency: skip if an existing plan with `generator: en-sweep` and matching `area:` is still open. Per `references/sweep-checks.md`.
  9. For each batch, open a focused PR with a single conventional commit.
  10. Each PR runs `en-review` automatically. If `en-review` returns clean (no P0/P1 findings), the PR auto-merges.
  11. If `en-review` finds anything, the PR stays open for human resolution.
  12. Summary report posted as a comment on the original triggering PR: what was fixed, what was deferred to `tech-debt-tracker.md`, what was filed as a draft plan, what needs human judgment.
- **What goes to `tech-debt-tracker.md` instead of a sweep PR.** Anything that requires modifying source code, config, or tests. Examples: "this helper duplicates `formatDate` in `src/utils/`", "Routes module imports from Config layer — violates layer rule", "test coverage gap on payment retry path." These get appended with category, severity, file paths, and date. `en-plan` reads `tech-debt-tracker.md` when planning new work.
- **Cross-review.** Off by default. Each sweep PR goes through `en-review` (in `mode:report-only`), which is the quality gate.

##### CI execution model

A slash command is an interactive-host concept, not a CI executable. The GitHub Action workflow doesn't invoke `/en-sweep` literally — it runs a wrapper command that maps to the host CLI's headless mode.

**Wrapper resolution (in CI runner):**

```bash
# bin/en-sweep-ci  (installed by ./setup; lives in the plugin's bin/)
# Resolves which CLI is available in the runner and invokes it headlessly.

if command -v claude >/dev/null 2>&1; then
  claude -p --output-format json \
    --max-turns 50 \
    --skill en-sweep \
    "$@"
elif command -v codex >/dev/null 2>&1; then
  codex exec --json --skill en-sweep "$@"
else
  echo "ERROR: en-sweep requires claude or codex CLI in the CI runner. Install one." >&2
  exit 1
fi
```

**Required runner environment:**
- One of `claude` or `codex` on PATH.
- LLM provider auth: `ANTHROPIC_API_KEY` (or OAuth via `claude` setup) for Claude; equivalent for Codex.
- `GITHUB_TOKEN` (auto-provided by GitHub Actions) for opening PRs.
- Default timeout: **30 minutes**. Hard cap, configurable via workflow input.
- Non-interactive — the wrapper passes `-p` (Claude) or `exec` (Codex), and the skill operates without `AskUserQuestion`/`request_user_input` calls.

**Branch naming for sweep PRs:** `en-sweep/<source-merge-sha-short>/<batch-name>` (e.g., `en-sweep/a3f1b9c/architecture-doc-update`).

**Fallback if no CLI is available:** the workflow fails with a clear error and posts a comment on the source PR. Does not block the source PR; just notifies the user that sweep is non-operational until a CLI is installed in the runner.

##### Loop guards (preventing self-trigger cascades)

Sweep runs on `push` to `main`. Its auto-merging PRs are themselves pushes to `main`. Without guards, this creates an infinite loop. Five guards in place:

1. **Skip sweep-authored commits.** The workflow's first step inspects `${{ github.event.head_commit.author.name }}` and `${{ github.event.head_commit.message }}`. If the author is `ensemble-sweep[bot]` *or* the message starts with `chore(en-sweep):`, exit immediately (status: skipped).
2. **Concurrency group.** GitHub Actions `concurrency:` keyed on `en-sweep-${{ github.ref }}` with `cancel-in-progress: false` — only one sweep run per branch at a time. Subsequent triggers queue, not stack.
3. **Sweep PR labeling.** Every sweep-opened PR carries the label `en-sweep`. The workflow's first step also exits immediately if the merge that just happened was a PR carrying this label (detected via `gh pr view --json labels`).
4. **No-material-diff termination.** After running all checks, if no fix-PR batches were generated, exit silently. No notification, no commit, no PR.
5. **Recursion depth cap.** The workflow checks `${{ env.ENSEMBLE_SWEEP_DEPTH }}`; defaults to `0`, increments on each spawn. Hard cap at depth 1 — sweep never spawns sweep. (Defense-in-depth; guards 1+3 should already prevent this.)

##### Doc-only enforcement at runtime

Sweep is contractually doc-only (D27). Implementation enforces this with a runtime guard:

- After staging files for a PR, the workflow runs `git diff --cached --name-only` and verifies every changed path is under `docs/`, `AGENTS.md`, `CLAUDE.md`, or `.github/workflows/en-sweep.yml`. Any path outside this allowlist → abort the PR creation, fail loudly with the offending path, and post to source PR.
- The allowlist is enforced in `bin/ensemble-doc-only-check`, called as a workflow step before `gh pr create`.

##### When `en-sweep` invokes `en-review`

In CI, `en-sweep` invokes `en-review` in `mode:report-only` (not the default interactive mode). Why:

- `en-review` in interactive/headless mode auto-applies `safe_auto` fixes, which would push another commit to the sweep PR's branch. That's tolerable but adds noise.
- More importantly, allowing mutation in CI risks the gate making changes that then need re-review — recursive ambiguity.
- `mode:report-only` makes `en-review` strictly a verifier: it returns findings as JSON, no file edits. Sweep parses the JSON and decides whether to auto-merge (clean) or leave open (P0/P1 findings).

This is documented in `en-review` (§5.2.5) and reinforced by `en-sweep`'s wrapper passing `EN_REVIEW_MODE=report-only` when invoking it.

##### Auto-merge security model

Default-safe configuration:

- **Use `GITHUB_TOKEN` (auto-provided), not a PAT.** Least-privilege.
- **Workflow permissions** (declared in workflow YAML): `contents: write`, `pull-requests: write`, `issues: write` (for comments). No `actions: write`, no admin.
- **No fork-triggered runs.** Workflow uses `on: push: branches: [main]` only — never `pull_request_target` from forks (which would expose credentials to attacker-controlled code).
- **Branch protection respected.** If the repo's branch protection requires N reviews on PRs to `main`, sweep PRs queue for review rather than auto-merge. Sweep detects this via `gh api /repos/.../branches/main/protection` and exits gracefully if its PRs can't be auto-merged. Surfaces in the source-PR comment.
- **Doc-only enforcement** (above) prevents any source-file edit even if a finding mistakenly suggested one.
- **Auto-merge disabled on detection failure.** If any guard check errors out (rate-limited GitHub API, auth failure, allowlist check throws), sweep leaves all PRs open for human review and does not auto-merge.

- **Reference files.**
  - `references/host-detect.md`
  - `references/sweep-checks.md` (the catalog of doc drift checks)
  - `references/sweep-trigger-workflow.yml` (template `.github/workflows/en-sweep.yml` installed by setup)
  - `references/sweep-loop-guards.md` (the five guards above)
  - `references/sweep-security-model.md` (permission model + fork policy)
  - `references/tech-debt-tracker-format.md` (entry schema for code-level findings)
  - `references/doc-lints.md` (shared with `en-review`)
  - `bin/en-sweep-ci` (the CLI wrapper)
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
  - **State 1 — Greenfield handoff.** Don't pre-create artifacts. Recommend the user start with `/en-brainstorm` to explore the idea, then proceed to `/en-foundation` to establish the foundation document and emit the bootstrap `<PREFIX>01-feature_project-setup` plan (per A1; `<PREFIX>` is the `plan_id_prefix` chosen during foundation, default `FR`). `en-setup` doesn't own greenfield bootstrap; `/en-foundation` does, with `/en-brainstorm` typically preceding it. Output a one-paragraph guide naming both skills and the order.
  - **State 2 — Retrofit bootstrap.** Run all of these in order:
    1. **Detect State 2 sub-variant** (2a / 2b / 2c / 2d) and stage the `AGENTS.md` / `CLAUDE.md` actions accordingly.
    2. **Existing-plans archival.** If `docs/plans/` already exists, run `bin/ensemble-classify-plans` to partition into conforming / non-conforming / subdirs / tech-debt. If non-conforming files exist, prompt to `git mv` them into `docs/plans/legacy/` with a `README.md` explaining the convention. Migrate any later via `/en-plan --from-legacy <path>`.
    3. **Create directory skeleton:** `docs/{plans/{active,completed},learnings/{bugs,patterns,decisions,sources},references,generated,designs}/`. Seed `docs/learnings/index.md` and `docs/learnings/log.md` with empty templates.
    4. **Seed `docs/generated/plan-index.md` and `learning-index.md`** with `generated: true` frontmatter and zero entries.
    5. **Generate or merge `AGENTS.md`** per the sub-variant. When merging, never overwrite existing user content — append the Ensemble pointer index as a new section if one isn't already present.
    6. **Generate or merge `CLAUDE.md`** per the sub-variant. Same merge discipline. The first line must be the cross-reference to `AGENTS.md` (per D15); if an existing `CLAUDE.md` doesn't have it, prepend it. Append-merge any Claude-Code-specific Ensemble guidance into a new section.
    7. **Add `.gitignore` entries:** `.ensemble/config.local.yaml`. Optionally `docs/learnings/archive/` (ask the user).
    8. **Install `.github/workflows/en-sweep.yml`** from `references/templates/github-workflow-en-sweep.yml`. Surface required permissions/secrets per A20.
    9. **Create `.ensemble/config.local.example.yaml`** (committed). Offer to create `.ensemble/config.local.yaml` (gitignored).
    10. **Guardrail check.** Run `skills/en-guardrail/bin/install-guardrail status`. If neither scope is installed, prompt: install project-scoped now (`p`) / print global one-liner (`g`) / skip (`s`).
    11. **Claude Code Review action check.** Detect `.github/workflows/claude-code-review.yml`. If absent, offer to install from `references/templates/github-workflow-claude-review.yml` (per `docs/integrations/anthropic-code-review-action.md`). The Codex review path (`docs/integrations/codex-code-review-action.md`) is informational only — user runs it manually if they want a second AI perspective.
    12. **Auto-merge repo-setting check.** `gh api repos/<owner>/<repo> --jq .allow_auto_merge`. If `false`, surface advisory (manual repo setting; agent doesn't flip it).
    14. **Recommend next steps.** Output a one-paragraph guide naming `/en-foundation --retrofit` (recommended) or `/en-plan` (if jumping into a feature first).
  - **State 3 — Diagnostic mode.** Run health checks: required directories present? `AGENTS.md` / `CLAUDE.md` current (no doc-lint failures)? `.github/workflows/en-sweep.yml` installed? Anthropic Code Review action installed? Guardrail hook registered? Repo-level `allow_auto_merge` enabled? `bin/ensemble-lint` available? Required CLIs (`gh`, `git`, `jq`) on PATH? MCP servers (Playwright, Context7) configured? Plugin version current? Mirrors CE's `scripts/check-health` pattern. Offer repairs for missing pieces.

- **Output.** A diagnostic report with `🟢` / `🟡` / `🔴` per check, plus any artifacts created or repaired. Recommends next-step skill (per state).
- **Cross-review.** Off — mechanical setup work, no peer review needed.
- **Reference files.**
  - `references/host-detect.md`
  - `references/templates/agents-md-template.md`
  - `references/templates/claude-md-template.md`
  - `references/templates/agents-md-merge-rules.md` (append-merge logic for variants 2b–2d)
  - `references/templates/github-workflow-en-sweep.yml`
  - `references/templates/github-workflow-claude-review.yml`
  - `references/templates/config-local-example.yaml`
  - `references/setup-state-detection.md` (state-1 / state-2 sub-variants / state-3 heuristics)
  - `bin/ensemble-classify-plans` (used in step 2)
  - `skills/en-guardrail/bin/install-guardrail` (used in step 10)
  - `scripts/check-health` (the diagnostic runner)

#### 5.2.12 `en-resolve-pr`

- **Purpose.** Address incoming PR review feedback systematically — humans, the Anthropic Claude Code Review action, the Codex review, CodeRabbit, etc. all land here. Triages new vs already-handled items, applies fixes, replies on the right comment-type API, resolves threads (except `needs-human`), reports merge readiness, optionally enables auto-merge.
- **Argument.** `(none)` — current branch's PR; `<PR-number>` — that PR; `<comment-or-thread-URL>` — targeted single thread.
- **Triage taxonomy.** Three feedback types (`review_threads`, `pr_comments`, `review_bodies`) partitioned into new / pending-decision / silent-drop (CodeRabbit/Codex/Gemini/Copilot wrappers, "looks good!", CI bot output). Per `references/resolve-pr-triage.md`.
- **6 verdicts.** `fixed` / `fixed-differently` / `replied` / `not-addressing` (cite evidence) / `declined` (cite specific harm + source: `CLAUDE.md`, `AGENTS.md`, `docs/learnings/patterns/`) / `needs-human` (rare; structured `decision_context` for the user). Per `references/resolve-pr-rubric.md`.
- **Reply mechanics.** Inline review threads → GraphQL `addPullRequestReviewThreadReply` + `resolveReviewThread`. Top-level PR comments / review bodies → `gh pr comment` (no resolve API). Replies always lead with `> [quoted excerpt]` for thread continuity. Per `references/resolve-pr-reply-format.md`.
- **Iteration.** Up to 2 fix-verify cycles per invocation; cycle 3 escalates as recurring pattern.
- **Auto-merge integration.** `--enable-auto-merge` flag flips on `gh pr merge --auto --squash` after addressing. Final summary reports `repo_allows_auto_merge` / `auto_merge_enabled` / `merge_state_status` / `review_decision` / failing/pending checks via `scripts/check-merge-status`.
- **Capture-from-synthesis (D21).** When a `declined` or `needs-human` verdict surfaces a real anti-pattern, soft-prompt to file a learning via `/en-learn capture --from-conversation`.
- **Tech-debt routing.** Out-of-scope `replied` verdicts file as `TD<N>` in `docs/plans/tech-debt-tracker.md`.
- **Cross-review.** Off — review feedback already came from a review pass.
- **Reference files.**
  - `references/resolve-pr-triage.md`
  - `references/resolve-pr-rubric.md`
  - `references/resolve-pr-reply-format.md`
  - `skills/en-resolve-pr/scripts/{get-pr-comments, get-thread-for-comment, reply-to-pr-thread, resolve-pr-thread, check-merge-status}` — wrappers around GitHub's GraphQL API (`reviewThreads`, `addPullRequestReviewThreadReply`, `resolveReviewThread`)

#### 5.2.13 `en-debug`

- **Purpose.** Telemetry-driven debugging. Reads structured logs per `references/observability-conventions.md`, correlates by `trace_id` / `request_id` / event field, identifies the failing code path, and surfaces a hypothesis with `file:line` and confidence 1–10. **Read-only** — never writes code; suggests next step (typically `/en-build`, `/en-resolve-pr`, `/en-plan`, or `/en-learn capture`).
- **Argument shapes.** `<trace-id>` (trace mode) / `<request-id>` / `"<error message>"` / `<file>:<line>` / `(none)` (tail mode).
- **Log source.** `.ensemble/config.local.yaml` `observability.log_source` — `stdout` / `file` / `command`. `log_command` is constrained to an allowlist (`docker`, `kubectl`, `journalctl`, `gh run view`, `datadog-cli`, `aws logs`, `gcloud logging`, plus user-extended). Defends against prompt-injection from log content.
- **Span → source mapping.** 5-priority algorithm: `error.stack` (highest confidence, 9–10) → structured `event` field heuristic (6–7) → span-name correlation (6) → full-text `msg` search (4–5) → `repo-research` agent dispatch (variable). Per `references/observability-debug-mapping.md`.
- **Output format.** Per `references/observability-hypothesis-format.md` — Hypothesis (with confidence/10), Anchor log line (with secret + PII redaction), Span timeline, Suggested next step. Plain text by default; `--markdown` for formatted output.
- **Confidence cap.** Without structured logs (no trace_id, no event field), falls back to plain-text correlation; caps confidence at 6/10. Suggests adopting structured logging as a follow-up.
- **Cross-review.** Off — analysis only, no code changes.
- **Reference files.**
  - `references/observability-conventions.md` (the log shape contract)
  - `references/observability-debug-mapping.md`
  - `references/observability-hypothesis-format.md`
  - `references/secret-patterns.md` (redaction patterns)

#### 5.2.14 `en-guardrail`

- **Purpose.** Always-on safety guardrail. `PreToolUse` hook on every Bash tool call; inspects the command for destructive patterns and forces a permission prompt. Defends against accidental destruction during agent autonomy.
- **Activation model.** Globally via `~/.claude/settings.json` (`PreToolUse` → `Bash` matcher → `bin/check-guardrail.sh`). Project-scoped fallback via `<repo>/.claude/settings.json`. The `install-guardrail` helper script handles both via JSON-aware merge that preserves existing hooks.
- **Patterns flagged.**
  - Recursive `rm -r` / `rm -rf` / `rm --recursive`
  - SQL: `DROP TABLE`, `DROP DATABASE`, `TRUNCATE`, `DELETE FROM ... ;` without `WHERE`
  - Git: `push --force` / `push -f`, `reset --hard`, `checkout .`, `restore .`, `branch -D`, `tag -d`, `worktree remove --force`
  - Cluster: `kubectl delete`
  - Docker: `rm -f`, `system prune`
  - IaC / cloud: `terraform destroy`, `aws s3 rm --recursive`, `gcloud … delete`
- **Safe exceptions.**
  - `rm -rf` of build artifacts (`node_modules`, `.next`, `dist`, `__pycache__`, `.cache`, `build`, `.turbo`, `coverage`)
  - DB ops against an *explicit local test/dev DB* (both `-h localhost` / `-h 127.0.0.1` AND a DB name containing `test` / `dev` / `local` after `/`, `-d`, `dbname=`, or `database=`)
- **Per-command bypass.** Prefix with `ENSEMBLE_GUARDRAIL=off`. Don't `export` it globally — defeats the guard for the rest of the session.
- **Security.** Command extraction uses Python `json.loads` (not grep) — handles escaped quotes inside the command, e.g. `psql -c "DROP TABLE users"`.
- **Cross-review.** Off — guardrail is a safety primitive, not a review surface.
- **Reference files.**
  - `skills/en-guardrail/bin/check-guardrail.sh` — the hook script
  - `skills/en-guardrail/bin/install-guardrail` — JSON-aware installer (status / install-project / install-global / uninstall-project)
  - Vendored from `gstack/careful` with extensions; attribution preserved in script headers.

#### 5.2.15 `en-loop`

- **Purpose.** Run a bounded, objective-driven autonomous loop (the ralph / good-night-have-fun pattern): keep an agent working one committed test-gated slice per iteration until an evidence-based stop condition. Wraps the `gnhf` CLI for the loop engine; adds Ensemble's per-iteration test-gate worker contract and branch-level cross-agent review at checkpoints. Manual-invoke only (`disable-model-invocation: true`); the user always starts an overnight loop explicitly.
- **When to use (vs neighbors).**
  - vs `/en-flow` — en-flow is a fixed one-shot pipeline for a defined plan; en-loop is open-ended (scope not fully enumerated, chipped one slice per iteration until a natural-language stop condition).
  - vs the built-in `/loop` — `/loop` re-invokes a prompt on a fixed interval in-session; en-loop is objective-driven with commit / rollback / retry and a supervised gnhf process that survives the session.
  - vs `/en-build` — en-build executes known plan units; en-loop discovers its slices in the loop. A peer-reviewed plan belongs in `/en-build`, not en-loop.
- **Process (high-level).** (`skills/en-loop/SKILL.md` is canonical; this is a summary.)
  1. Preflight: host-detect the worker agent (host-neutral: `claude` on Claude, `codex` on Codex); verify `gnhf` on PATH (else print `npm i -g gnhf` and stop, never native-fallback); clean git; resolve project test / lint commands; require an evidence-based `--stop-when`.
  2. Compose the per-iteration test-gate worker prompt (implement one slice, run test + lint, commit only on green, no fake success).
  3. Launch gnhf with the prompt + caps + `--stop-when` (feature branch or `--worktree`).
  4. Checkpoint cadence is en-loop's own mechanic (gnhf has no mid-run callback): run gnhf in bounded chunks capped at `--review-every N` iterations; at each chunk boundary and at loop end run `/en-review --peer-only --mode headless` over the branch diff, record a `review-verdict:` trailer, then relaunch on the same branch with findings folded in as the next chunk's acceptance criteria.
  5. On final exit: Morning Review (reconstruct state from git / logs / processes, never memory) → `/en-learn capture` → hand off `/en-review` → `/en-qa` → `/en-ship`. Never auto-merge.
- **Modes.** Hands-Off (bounded, walk away), Companion (steer between chunks via `/en-review`, findings become the next bounded prompt), plus Morning Review on return.
- **Dependency.** The `gnhf` CLI (`npm i -g gnhf`), agent-agnostic; surfaced as an optional, non-blocking install by `/en-setup` (including a `scripts/check-health` advisory). en-loop wraps gnhf rather than reimplementing the loop (the EN04 lesson, D40).
- **Cross-review.** Branch-level at checkpoints (every `--review-every N` and at loop end), not per iteration; per-iteration is a fast test-gate only (D39 `performance > speed ≥ cost`).
- **Safety.** Preserve user changes; no destructive git (worker-prompt rule for every worker); `en-guardrail` covers a `claude` worker (Claude Code PreToolUse hook) while `codex` / other workers rely on the worker-prompt rules + gnhf rollback + `--worktree`; bounded caps (`--max-iterations` / `--max-tokens`, plus en-loop-owned `--max-runtime` via `timeout` / `gtimeout`); never auto-merge; completion is not acceptance.
- **Reference files.**
  - `references/host-detect.md`
  - gnhf CLI (external; `npm i -g gnhf`) — the loop engine this skill wraps

---

## 6. Agent Catalog

> EN13 retired seven reviewer agents (correctness, testing, maintainability,
> standards, security, performance, migrations). Their scopes were absorbed into
> the per-skill peer briefs; `references/peer-contract.md` owns the output format
> and severity scale they used to restate. Five agents: the four research and simplification agents, plus a single parameterized `dimension-reviewer` that replaced the seven (TD9). **See TD9** — five
> skills still name the retired seven as `subagent_type`.

Eleven agents total: 7 reviewers (read-only) + 3 researchers (read-only) + 1 refiner (read-write). Short specialist prompts (~40–120 lines each), not multi-thousand-line monsters. Skills dispatch them via the platform's task primitive (Claude Code Agent tool, Codex `spawn_agent`).

### 6.1 Reviewer agents (7)

**Always-on (4):**

| Agent | Focus | Dispatched by |
|---|---|---|

**Conditional (3) — fire when the diff matches:**

| Agent | Fires when diff touches | Dispatched by |
|---|---|---|

### 6.2 Research agents (3)

| Agent | Purpose | Dispatched by |
|---|---|---|
| `repo-research` | Scan codebase for patterns, conventions, file paths, existing implementations | `en-plan`, `en-foundation`, `en-sweep`, `en-learn` (for `docs/architecture.md` sync) |
| `learnings-research` | Query `docs/learnings/` for relevant past bugs, patterns, decisions | `en-plan`, `en-review`, `en-brainstorm`, `en-foundation` |
| `web-research` | External docs (Context7) and best-practice search (WebSearch). Optional. | `en-plan`, `en-brainstorm`, `learn --pack`, `learn ingest <url>` |

### 6.3 Refiner agents (1)

Distinct from reviewers (which return findings) and researchers (which return data) — refiners *modify* code directly and return a diff summary.

| Agent | Purpose | Dispatched by | Source |
|---|---|---|---|
| `code-simplifier` | Refine recently modified code for clarity, consistency, and project-standards compliance while preserving exact functionality. Reduces nesting, eliminates redundancy, applies CLAUDE.md / AGENTS.md conventions, avoids over-simplification (no nested ternaries, no clever-at-cost-of-readable). Model: opus. | `en-build` (per unit, before peer review) | [Anthropic claude-plugins-official](https://github.com/anthropics/claude-plugins-official/blob/main/plugins/code-simplifier/agents/code-simplifier.md) |
| `dimension-reviewer` | Reviews a diff along ONE named dimension (correctness, testing, maintainability, standards, security, performance, migrations); the dimension, focus and scope arrive in the prompt. Read-only. | `en-review`, `en-build`, `en-plan`, `en-foundation` |

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

> **Intent vs reality.** This section captures Ensemble's *architectural intent* — what the toolkit was designed to be. The *current architectural reality* of any project that uses Ensemble lives in that project's own `docs/architecture.md`, maintained continuously by `en-learn` (event-driven) and `en-sweep` (drift-driven). For Ensemble itself, once we start building, this section becomes the seed; the living architecture moves to `docs/architecture.md` at the repo root.

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
│  │  docs/plans/<PREFIX><NN>-<plan_type>_<slug>.md          │    │
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
                  └──► plan ─────► docs/plans/<PREFIX><NN>-… ◄──┤
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
| `en-learn` | `repo-research` (for `docs/architecture.md` sync), `web-research` (no longer used — external lookup moved to research-time skills), Context Analyzer / Solution Extractor / Related Docs Finder sub-tasks (in-process) |
| `en-ship` | none; uses git + gh directly |
| `en-sweep` | `repo-research` + invokes `en-review` on each batch PR (which dispatches its own personas) |

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
│   ├── architecture.md                 # living architectural reality; updated by learn + sweep
│   ├── golden-principles.md            # mechanical opinionated rules used by sweep (optional)
│   ├── core-beliefs.md                 # agent-first operating principles (optional, advanced)
│   ├── quality.md                      # per-domain quality grades, drift tracking (optional)
│   ├── designs/                        # brainstorm outputs (decision artifacts)
│   │   └── 2026-04-28-<topic>-design.md
│   ├── plans/                          # feature/refactor plans (<PREFIX><NN> numbered)
│   │   ├── active/                     # draft / open / in_progress; <PREFIX><NN>-<plan_type>_<slug>.md
│   │   ├── completed/                  # shipped; same filename, status: completed
│   │   ├── legacy/                     # archived non-Ensemble plans (created on retrofit)
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

**Why this layout.** Root files are *agent discovery surfaces* — the first thing any agent reads when it joins a session. They are intentionally minimal. Everything else lives in `docs/`, the system-of-record directory, where `en-learn` and `en-sweep` curate it continuously.

**Mandatory (every Ensemble project gets these — created by `/en-setup` State 2 or `/en-foundation` State 1):** `AGENTS.md`, `CLAUDE.md`, `docs/foundation.md`, `docs/architecture.md`, `docs/plans/active/`, `docs/plans/completed/`, `docs/learnings/{index.md,log.md,bugs,patterns,decisions,sources}/`, `docs/generated/{plan-index.md,learning-index.md}` (regenerated by `en-learn`), `docs/README.md`.

**Optional (added when valuable):** `docs/golden-principles.md` (recommended once `en-sweep` is in regular use), `docs/core-beliefs.md` (Standard/Deep projects), `docs/quality.md` (large projects), `docs/references/` (added on first `en-learn --pack`), `docs/designs/` (added on first `en-brainstorm`).

**Note on `docs/generated/`.** Originally listed as optional but is now mandatory because `bin/ensemble-lint` requires `docs/generated/plan-index.md` and `docs/generated/learning-index.md` to exist for index-coverage checks (§18.1). `/en-setup` and `/en-foundation` seed the directory with empty stub indexes (frontmatter `generated: true` + zero entries); `/en-learn` regenerates them on every relevant write.

### 10.2 Stable IDs

| ID | Where assigned | Format | Stability rule |
|---|---|---|---|
| `R<N>` | `foundation.md` Section 5 (Functional Requirements) | `R1`, `R2`, … | Append-only. Removed requirements get marked deprecated, not deleted. |
| `A<N>` | `foundation.md` Section 3 (Users & Actors) | `A1`, `A2`, … | Append-only. |
| `F<N>` | `foundation.md` Section 6 (User Experience) | `F1`, `F2`, … | Append-only. |
| `AE<N>` | `foundation.md` Section 5 (Acceptance Examples) | `AE1`, `AE2`, … | Append-only. |
| `U<N>` | Plan files under `docs/plans/{active,completed}/` Implementation Units | `U1`, `U2`, … per plan | Never renumbered after assignment within a plan. Splitting keeps original ID on original concept. |
| `<PREFIX><NN>` | Plan filename prefix; `plan_id:` field | `EN01`, `FR07`, … (prefix from `foundation.md plan_id_prefix:`; default `FR`) | Auto-incremented per-prefix from highest existing across `active/` + `completed/`. Legacy `fr_id:` accepted as alias for one release. |

### 10.3 Cross-references

- Plan units cite the requirement IDs they cover: `Requirements: R3, R7, AE2`.
- Tests cite acceptance examples they cover: `Covers AE2`.
- Commits include the U-ID in the message body: `feat(auth): add token refresh — U3`.
- Review findings cite the U-ID they relate to: `[P1] U5 — missing edge case for empty token`.

### 10.4 Protected paths

The following are pipeline artifacts. `en-review`, `en-qa`, `en-learn`, and `en-sweep` will never flag them for deletion or gitignore:

- `AGENTS.md`, `CLAUDE.md` (repo root)
- `docs/foundation.md`, `docs/architecture.md`, `docs/golden-principles.md`, `docs/core-beliefs.md`, `docs/quality.md`
- `docs/designs/`
- `docs/plans/{active,completed,tech-debt-tracker.md}`
- `docs/learnings/` (including `index.md`, `log.md`, `archive/`, and `sources/` subcategory)
- `docs/references/`
- `docs/generated/`
- `docs/README.md`

Files in `docs/generated/` are auto-derived — doc lints flag any direct human edit and `en-sweep` regenerates them.

---

## 11. Compounding Learning Store

### 11.1 Three artifact types

Captured knowledge takes three forms. They are not flavours of one thing: they
differ in **shape**, **lifecycle**, and **write path**, which is what makes the
split load-bearing.

| Type | Path | Shape | Lifecycle |
|---|---|---|---|
| **Term** | `docs/CONTEXT.md` | Definition plus retired synonyms, in one shared file | Amended in place; the file accretes |
| **Decision** | `docs/decisions/NNNN-<slug>.md` | Title states the claim; no frontmatter; invariants section | Append-only; dated `## Update` sections |
| **Solution** | `docs/learnings/<slug>-<date>.md` | Six-field frontmatter; one paragraph until it earns more | Goes stale against code; refreshed |

**Routing** is by what the candidate *is*, not what it is about, with an explicit
tie-break for candidates that match two types: `term > decision > solution`. The
more durable form outlives the occasion and can cite the other. Only one artifact
is written — writing both reintroduces the duplication the capture gate's
generalization step exists to prevent. Rules in
`skills/en-learn/references/artifact-types.md`.

**The gate comes first.** `capture-gate.md` decides *whether* to write at all;
routing only sees candidates that already passed. The default is to write
nothing, and a rejected capture reports which condition failed.

This replaced a `bugs | patterns | decisions | sources` taxonomy (TD5, closed by
EN14). Those four produced the same artifact in different directories, and the
boundary between a "pattern" and a "decision" was not one a writer could apply
twice the same way. Two of the three types above did not previously exist:
nothing captured domain vocabulary, and decisions recorded what was chosen
without stating the rules that followed from it.

### 11.2 Solution frontmatter (`docs/learnings/<slug>-<date>.md`)

Six required fields. Terms and decisions carry **none** — nothing queries them by
field, so every field would be bookkeeping nobody reads and nothing keeps current.

```yaml
---
title: <one-line title>
applies_when: <the situation that should surface this entry>
date: YYYY-MM-DD
tags: [...]
related: [<paths-to-other-learnings>]
status: active | deprecated | superseded
---
```

`applies_when` is **the retrieval field** and sits second for that reason: it is
what decides whether an entry is ever found again. Write the situation, not the
subject — a future agent does not search for your entry's topic, it is in the
middle of some work and needs to recognise that the entry is about the work it is
doing. Full schema in `skills/en-learn/references/learning-frontmatter-schema.md`.

### 11.2a Grounding

A written artifact becomes knowledge future agents act on **without
re-verifying**. Before it is indexed, `scripts/ensemble-validate-claims` checks
the claims it can: cited paths, links, SHAs, and unrendered template
placeholders.

Advisory, never a gate — a solution doc legitimately cites a path the fix deleted
or describes a pre-fix state. Three exit codes, and the third carries the weight:
`0` clean, `1` findings to adjudicate, `2` the validator could not run. A run that
exits 2 may **not** be reported as grounded; collapsing 2 into 1 would make "this
doc has a dead link" indistinguishable from "nothing checked this doc".

### 11.3 Query mechanism

`learnings-research` reads `docs/learnings/index.md` first (the curated catalog),
then drills into the section that looks relevant. **Three sources need three
retrieval paths** — frontmatter filtering reaches solutions only, because terms
and decisions deliberately carry none:

| Source | Matched on |
|---|---|
| `docs/CONTEXT.md` | term headings and their definition sentences |
| `docs/decisions/*.md` | the H1 claim and the `## Invariants this creates` section |
| `docs/learnings/*.md` | `applies_when` first, then `tags` |

A frontmatter-first search would silently miss two thirds of the store.

### 11.4 Lifecycle

- **Capture.** `learn capture` (default mode) writes after a feature ships, a bug is fixed, or a synthesis worth keeping emerges in `en-plan` / `en-review` / `en-brainstorm` (`--from-conversation`).
- **Migrate.** A repo carrying the retired directories is migrated before capture writes into it (`references/layout-migration.md`). Legacy decisions become ADRs rather than flattening into solutions.
- **Refresh.** `learn --refresh` audits content staleness across the store: keep, update, replace, or archive each learning.
- **Lint.** `learn --lint` audits *structural* health of the wiki graph: orphans, missing back-refs, broken links, missing pages for frequently-cited concepts, contradictions, data gaps. `--lint --fix` auto-applies mechanical repairs; non-mechanical findings go to the user.
- **Surface.** `en-plan`, `en-review`, `en-brainstorm`, `en-foundation` query the store (and `docs/references/`) automatically. The `learnings-research` agent reads `docs/learnings/index.md` *first* to find candidate pages, then drills into them — Karpathy's pattern of indexing-as-cheap-RAG. Matches are surfaced in the artifact with a citation.

### 11.5 Architecture-doc sync (the second compounding loop)

`en-learn` updates `docs/architecture.md` after material structural change ships. `en-sweep` checks `docs/architecture.md` against current code on every PR-merge run and opens fix-up PRs when they drift apart. Together they keep `docs/architecture.md` honest — anything in there is a current claim about the code, not a stale aspirational drawing.

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

**Active cross-reference maintenance (always-on in `capture`).** When a new entry is written:

1. Resolve `related: [...]` from the new entry's frontmatter.
2. For each related page, append a reciprocal back-reference. Forward refs without back-refs leave the graph one-directional and orphans accumulate.
3. Optionally, surface a one-line update to each related page where the new entry materially changes its claims (a contradiction, a stronger version of the same insight, a new example).

**Two helper artifacts:**

- **`docs/learnings/index.md`** — content catalog. Organized by category (`bugs/`, `patterns/`, `decisions/`, `sources/`). Each entry: link, one-line summary, date, `related-count`. Maintained by `en-learn` on every write. Read first by `learnings-research` agent before drilling into specific pages — keeps token cost bounded at moderate scale (~hundreds of pages) without embedding-based RAG infrastructure. Karpathy's observation: this approach scales surprisingly well; reach for vector search only when the store crosses ~500 entries.

- **`docs/learnings/log.md`** — append-only chronological record. Format: `## [YYYY-MM-DD] <op> | <subject>` (grep-friendly: `grep "^## \[" log.md | tail -5` gives recent activity). Every `en-learn` mode appends one line. Used by `--lint` to detect drift between log and store, and by `en-sweep` to see "what's happened recently" without re-scanning.

**Structural health (`learn --lint`).** Distinct from `--refresh` (which is content staleness). Lint audits the wiki *graph*:

- Orphan pages (zero inbound references)
- Missing back-refs (asymmetric `related:` fields)
- Broken links (target file moved or deleted)
- Missing pages (concepts referenced by name in 3+ pages without a dedicated entry → suggest creating one)
- Contradictions (claims across pages that conflict — LLM judgment)
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
| **Headless mode** on `en-review`, `en-qa`, `en-learn` | No AskUserQuestion overhead when called by other skills. |

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

- [ ] `en-learn` (4 modes: `capture` + `--refresh` + `--lint` + `--migrate`; cross-ref maintenance; `index.md` + `log.md` upkeep; `docs/architecture.md` sync; plan move active→completed)
- [ ] `en-ship` (commit/push/PR)

### 14.6 Phase 5 — Maintenance skill

- [ ] `en-sweep` (drift scan + cleanup PRs; depends on doc-lints, golden-principles, `docs/architecture.md`, repo-research)

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

- **Q1 → A1.** `en-foundation` emits a bootstrap `<PREFIX>01-feature_project-setup` plan **only when starting a new project** (`<PREFIX>` is the `plan_id_prefix` resolved during foundation; default `FR`). Detection: empty repo or no existing `docs/foundation.md`. Existing projects skip the bootstrap plan entirely.
- **Q2 → A2.** `en-build` derives batch size dynamically from the feature: tightly-coupled units batch together, independent units can be larger batches, complex/sensitive units (auth, payments, migrations) batch alone. No fixed default.
- **Q3 → A3.** `en-learn` runs automatically at the end of `en-build` and `en-qa`. Soft auto-invoke with a one-line announcement; user can decline.
- **Q4 → A4.** Ad-hoc peer review does not log prompts/responses to disk. Keep it lean.
- **Q5 → A5.** One round of cross-review per artifact. No multi-round verify.
- **Q6 → A6.** All skills prefixed `en-` (e.g., `/en-brainstorm`, `/en-build`, `/en-sweep`). Underlying skill identifiers, directory names, and slash commands all use the prefix.
- **Q7 → A7.** Worktrees are opt-in per skill via the dispatching call, mirroring Compound Engineering's pattern (`isolation: "worktree"` on subagent dispatch). `en-build` is the primary user — opt-in when the build benefits from per-unit isolation.
- **Q8 → A8.** Peer reviewer is always the *other* agent, resolved by host-detect. Running `/en-build` from Claude Code → peer is Codex. Running `/en-build` from Codex → peer is Claude. Same rule for every peer-review invocation across every skill.
- **Q9 → A9.** `en-sweep` triggers on **`push` to `main`** (i.e., right after a PR merges), not on a daily/weekly schedule. Installed as `.github/workflows/en-sweep.yml` by the setup script. Manual invocation also supported.
- **Q10 → A10.** `en-sweep` auto-merges its own PRs after `en-review` clears them, **and** `en-sweep` is strictly doc-only. It never modifies source code, configuration, or tests. Code-level findings get filed to `docs/plans/tech-debt-tracker.md` for `en-plan`/`en-build` to handle later.
- **Q11 → A11.** `docs/core-beliefs.md` is seeded from a templated starter at `references/core-beliefs-starter.md`. User edits or extends after.
- **Q12 → A12.** *(superseded by EN14 — the mode this describes was removed.)* `en-learn --pack <library>` always re-fetches and re-flattens. The user invokes it explicitly, so always-fresh is the right default.
- **Q13 → A13.** *(superseded by EN14 — the mode this describes was removed.)* `en-learn ingest <url>` automatically tries the Wayback Machine if the original URL returns 403 / Cloudflare-blocked. Surfaces an error only if both fail.
- **Q14 → A14.** `en-learn --lint --fix` opens one PR per fix category (back-refs / broken-links / index-drift / etc.), mirroring `en-sweep`'s pattern. Each PR is small and reviewable.
- **Q15 → A15.** Capture-from-synthesis is a **soft prompt** at the end of `en-plan`, `en-review`, `en-brainstorm`. Fires only when the final synthesis exceeds a structure/insight threshold; quietly skipped otherwise.
- **Q16 → A16.** *(superseded by EN14 — the mode this describes was removed.)* `en-learn ingest` silently skips low-signal / off-topic sources with a one-line note ("This source appears off-topic for an engineering wiki — skipped. Re-run with `--force` to ingest anyway."). No thin summary written.

### 16.2 Resolved v1-implementation questions (2026-04-28)

- **Q17 → A17.** New-project detection in `en-foundation`: `docs/foundation.md` does not exist *and* repo has no source code outside `node_modules/`/`vendor/`/equivalents (or is in initial-commit state).
- **Q18 → A18.** *(superseded by EN14 — the mode this describes was removed.)* Off-topic detector for `en-learn ingest`: LLM-judged relevance score against the project's `foundation.md`. Threshold: **0.3 / 1.0**. Below threshold → silently skip with note (per A16); `--force` overrides.
- **Q19 → A19.** `docs/plans/tech-debt-tracker.md` carries stable IDs `TD1`, `TD2`, … assigned append-only. `en-plan` cites them as `Resolves: TD7` in unit metadata when a plan addresses tracked debt.
- **Q20 → A20.** GitHub Action permissions/secrets for `en-sweep` are documented during setup. The setup script generates a checklist (`docs/generated/sweep-setup-checklist.md`) listing required workflow permissions, optional PAT for cross-repo PRs, and trigger configuration.

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
- A golden principle is missing → add it to `docs/golden-principles.md` so `en-sweep` enforces it.
- A plan unit was too coarse → adjust the plan template's unit-granularity guidance.

This is the meta-loop. Every skill failure is feedback; every feedback gets encoded.

### 17.2 The repository is the system of record

If knowledge isn't in the repo, the agent can't see it. Slack discussions, design conversations in chat, decisions made in someone's head — all illegible. Anytime a durable decision happens in conversation, capture it (a learning, an `docs/architecture.md` update, a foundation amendment) before moving on. `en-brainstorm` and `en-plan` will reflexively offer to capture decisions that surface during their flows.

### 17.3 Map, not encyclopedia

Top-level docs (`AGENTS.md`, `CLAUDE.md`, `foundation.md`) are short and point to deeper sources of truth. SKILL.md files are the same — process logic in the file, templates and long checklists in `references/` loaded on demand. A doc that tries to be everything ends up being nothing — too long to read fully, too monolithic to keep current, too easy to ignore.

### 17.4 Boring tech is easier for agents

When choosing dependencies, frameworks, or patterns: composability, API stability, and strong representation in the training set matter more than novelty. If a "boring" library does the job, prefer it. If working around an opaque upstream library costs more than reimplementing a focused subset, reimplement.

### 17.5 Enforce boundaries centrally; allow autonomy locally

Mechanical enforcement of architecture, naming, and structural rules via lints, custom error messages, and `en-sweep`. Within those boundaries, agents (and humans) get freedom in how they express solutions. The output doesn't have to match human stylistic preference — it has to be correct, maintainable, and legible to future agent runs.

### 17.6 Pay technical debt continuously, not in bursts

`en-sweep` runs on every PR merge to `main`. Small, focused cleanup PRs. Auto-merge when `en-review` is clean. Never let cleanup become a once-a-quarter project — by then the drift has compounded and the rewrite is the easier-looking option, which is almost always wrong.

### 17.7 Throughput changes the merge philosophy

In a fast agent-driven loop, blocking gates that would be sensible at human pace become counterproductive. Test flakes get re-run; corrections are cheap; PRs are short-lived. This is opinionated and project-dependent — we recommend it but don't enforce it. Document the chosen merge philosophy in `AGENTS.md` so the agent knows.

---

## 18. Doc Lints

Mechanical checks on the knowledge store. Catch drift early, before it compounds.

### 18.1 What gets checked

- **Frontmatter validity.** Every artifact's frontmatter parses, has required fields, uses valid enum values (per `references/learning-frontmatter-schema.md`, etc.).
- **ID stability.** R-IDs in `foundation.md` are append-only (no renumbering). U-IDs in plans are stable (no renumbering after assignment). Plan IDs (`<PREFIX><NN>`) are unique. The `plan_id_prefix:` in foundation drives new plans; legacy `FR` plans are honored alongside.
- **Cross-link integrity.** Every `(see R3)`, `(see U5)`, `(see EN07)` / `(see FR07)`, `(see <path>)` resolves. Broken cross-refs are P1 lints. The plan-prefix matcher reads `plan_id_prefix:` from foundation plus all prefixes observed in `docs/plans/{active,completed}/`.
- **Status correctness.** `docs/plans/active/*.md` files have `status: draft | open | in_progress | abandoned`. `docs/plans/completed/*.md` files have `status: completed`. Mismatches are P1. `plan_type` must be one of `feature`, `improvement`, `bug`.
- **No absolute paths.** No artifact contains `/Users/...`, `C:\...`, or other absolute filesystem paths. Repo-relative only.
- **Freshness.** `docs/architecture.md` `updated:` field is within the freshness window (30 days by default, configurable). Stale → P2 advisory; very stale (90+ days) → P1.
- **Generated-file integrity.** Files in `docs/generated/` carry `generated: true` frontmatter and a generator-id; no human edits except via the generator.
- **Index coverage.** Every plan has an entry in `docs/generated/plan-index.md`; every learning in `docs/generated/learning-index.md`.
- **`CLAUDE.md` discipline.** First line of `CLAUDE.md` cross-references `AGENTS.md`. No heading or content block in `CLAUDE.md` duplicates `AGENTS.md` (rule: `claude-md.no-shared-content`). P1.
- **Map length budget.** `AGENTS.md` body ≤ ~150 lines (target 100); `CLAUDE.md` body ≤ ~80 lines (target 60). Soft limit, P2 advisory if exceeded.
- **Structured logging (opt-in).** When `.ensemble/config.local.yaml` declares `observability.structured_logging_required: true`, the `logging.unstructured` rule (P2 advisory) flags `console.log` / `print` / `fmt.Println` / `println!` outside `observability.logging_dev_paths`. Per `references/observability-conventions.md`.
- **Architecture fitness (opt-in).** When `.ensemble/config.local.yaml` declares `fitness.enabled: true`, the lint runner invokes the project's `bin/check-fitness` (or configured equivalent) and surfaces its JSON-lines findings as `architecture.layer-violation` / `architecture.fitness-violation` etc. Missing checker → `architecture.fitness-checker-missing` (P3). Per `references/architecture-fitness.md`.
- **Bootstrap pattern validation (advisory).** `learnings.bootstrap-unvalidated` (P3) — counts entries with `source: bootstrap` and `requires_validation: true` more than 30 days old. Reminds the user to validate via `/en-learn --refresh` or manual edit.

### 18.2 Where it runs

- `en-review` runs lint as a pre-flight check on the diff. Lint failures surface as P1 findings.
- `en-sweep` runs lint across the whole repo on every PR-merge pass and opens fix-up PRs.
- `en-sweep` also invokes `learn --lint` (wiki-graph health) on the same pass, routing its output through the same PR-batching flow.
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
│   ├── en-sweep/
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
- An `en-sweep` workflow that doesn't enforce doc-only could push a source-file edit unnoticed in a 3am auto-merge.
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
| **`en-sweep` dry-run batching tests** | Run `en-sweep` against fixture repos with seeded drift. Verify: correct number of PRs, correct file allocation per PR, no source-file edits, loop guards reject self-triggered runs. | `tests/en-sweep/dry-run/` |
| **Doc-only enforcement** | Adversarial fixture: a `sweep` run that *attempts* to edit a source file. Verify `bin/ensemble-doc-only-check` rejects it and the workflow aborts. P0 regression test. | `tests/en-sweep/doc-only-enforcement/` |
| **Auto-merge security** | Simulate fork-PR triggers, missing branch protection, missing GITHUB_TOKEN scope. Verify sweep refuses to auto-merge in each unsafe configuration. | `tests/en-sweep/security/` |
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
- **CI:** runs on every PR via `.github/workflows/ensemble-tests.yml` (a separate workflow from `en-sweep`). Hermetic suite blocks merge; integration suite is opt-in via PR label.
- **Pre-release:** integration suite must pass before bumping the plugin version.

### 20.6 Golden-test failure protocol

If a doc-lint rule's golden test fails after a code change to the lint, **the lint code is wrong, not the fixture** — by definition. The fixture is the contract. Update the fixture only when the rule's intent has changed (and update both the passing and violating fixtures to match the new intent). Document the change in the test commit message: "lint(<rule>): change <X> behavior; fixtures updated to match".

This protocol prevents drift where lints "evolve" silently and the fixtures are ratcheted to whatever the implementation happens to do.

### 20.7 Roadmap impact

`tests/` is a Phase 1 deliverable. Tests get written **alongside** each reference, lint, and skill — not bolted on at the end. Specifically:

- Phase 1 (Shared references) writes the golden fixtures + frontmatter tests in lockstep with the schemas.
- Phase 2 (Planning skills) writes host-detect tests + sample-repo fixtures.
- Phase 3 (Execution skills) writes mock cross-review fixtures + parser tests.
- Phase 5 (Maintenance skill) writes the `en-sweep` dry-run + doc-only enforcement + security tests.

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
plan_id_prefix: <2-3 uppercase letters>  # e.g. EN, ENS, FR. Used by /en-plan when minting plan IDs. Falls back to FR if absent.
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
last_drift_check: YYYY-MM-DD      # bumped by sweep on every PR-merge pass
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
related_plan: <plan_id, e.g. EN03 — or empty>
replaced_by: <plan_id>          # optional; only when status is superseded
---
```

`status` starts at `open` and is closed out by `/en-plan` when a plan built from
this design reaches `status: open`: `accepted` when the plan carries the design's
recommendation, `superseded` when planning committed to a different approach.
`/en-plan` writes `related_plan` at the same moment, and the plan's own
`related_design` points back, so the pair is navigable in both directions.

A design that never produces a plan stays `open`. That is correct: an unplanned
exploration is still an open question, and `/en-brainstorm`'s resume scan should
still offer it.

### C.3 `docs/plans/{active,completed}/<PREFIX><NN>-<plan_type>_<slug>.md` frontmatter

```yaml
---
type: plan
plan_type: feature | improvement | bug   # the kind of change this plan delivers
plan_id: <PREFIX><NN>                    # PREFIX from foundation's plan_id_prefix (default FR); e.g. EN03, FR07. Legacy: fr_id: <ID>
title: <descriptive title>
status: draft | open | in_progress | completed | abandoned
location: active | completed             # draft/open/in_progress/abandoned live in active/; completed lives in completed/
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
> - 2026-04-28 (revision 1): added `en-sweep` as skill #10; folded `pack-reference` into `learn --pack`; promoted architecture to a first-class living artifact (initially placed at root); added `AGENTS.md`/`CLAUDE.md` as project-level pointer maps; split plans into `active/` and `completed/`; added doc lints (§18); added Operating Philosophy (§17). Sources: harness-engineering essay (OpenAI, Feb 2026).
> - 2026-04-28 (revision 2): moved architecture from `/ARCHITECTURE.md` (root) to `docs/architecture.md` for layout consistency (root keeps only agent-discovery files: `AGENTS.md`, `CLAUDE.md`, `README.md`); added strict CLAUDE.md content rules (cross-reference required, Claude-Code-specific only, no duplication of AGENTS.md content) and matching `claude-md.no-shared-content` lint; added `references/claude-md-template.md`.
> - 2026-04-28 (revision 3): adopted Karpathy's "LLM Wiki" pattern for `docs/learnings/`. Expanded `en-learn` from 3 modes (`capture` + `--refresh` + `--pack`) to 5 modes (added `ingest <path-or-url>` and `--lint`). Added always-on cross-reference maintenance (reciprocal back-refs after every write) and two new helper artifacts: `docs/learnings/index.md` (content catalog the agent reads first — Karpathy's tip that this scales surprisingly well at moderate scale and avoids embedding-based RAG) and `docs/learnings/log.md` (append-only chronological record, grep-friendly). New subcategory `docs/learnings/sources/` for external material brought in via `ingest`. `en-learn ingest` accepts both file paths and URLs (URLs use WebFetch with Wayback fallback for Cloudflare-blocked sites). Capture-from-synthesis reflex added to `en-plan`, `en-review`, `en-brainstorm`. `en-learn --lint` handles wiki-graph health (orphans, missing back-refs, contradictions, missing pages, data gaps); `bin/ensemble-lint` continues to handle file-shape checks. Added decisions D19–D21 and open questions Q13–Q16. Source: Karpathy gist (`gist.github.com/karpathy/442a6bf555914893e9891c11519de94f`).
> - 2026-04-28 (revision 4): closed all initial open questions Q1–Q16 and propagated architectural resolutions into new decisions D22–D28. Skill prefix `en-` adopted across all 10 skills. `en-sweep` rewritten to be strictly doc-only and PR-merge-triggered (was: scheduled, allowed code refactors). `en-build` batch size is now dynamic per-feature (was: fixed default 3). `en-learn` auto-runs after `en-build` and `en-qa` (soft auto-invoke). `en-foundation` emits `FR01-project-setup` only for new projects. Cross-review peer is always the other agent via host-detect — no model-defaults table. Worktrees opt-in per dispatch (CE pattern). Added 4 new v1-implementation questions Q17–Q20.
> - 2026-04-28 (revision 5): closed Q17–Q20. Added `code-simplifier` as the 11th agent, sourced from Anthropic's claude-plugins-official. First refiner agent — modifies code rather than returning findings. New §6.3 Refiner agents category with stricter invariants (orchestrating skill must run verification immediately after, revert on test failure). Added decision D29: per-unit code-simplification pass during `en-build`, between verification-gate-1 (tests+lint) and per-unit Outside Voice review. Two verification gates protect against simplifier breakage. Skipped on trivial units or with `--no-simplify`. New reference `references/code-simplifier-dispatch.md`. Source: `github.com/anthropics/claude-plugins-official/.../code-simplifier.md`.
> - 2026-04-28 (revision 6): made the "peer reports, host applies" contract explicit and unambiguous (D30). Peer agents in any cross-review never modify files, run commands, or make commits — they only return structured findings. Host (the skill-running agent) is the sole code-modifier and decides per-finding: apply, defer to tracker, or disagree. User is surfaced only on contention (host disagrees with P0; host wants to defer high-confidence security/architecture finding; peer verdict = reject). Updated `en-build` per-unit flow with the three host responses and re-verification after host applies changes. Updated §7.6 Verdict handling. Baked the no-modify constraint into the Outside Voice prompt (Appendix A) so the peer is told its role explicitly. Prevents two-agent race on the same files.
> - 2026-04-28 (revision 7): clarified the symmetry between `en-build` flavors. Both flavors guarantee implementer ≠ reviewer. **Build-by-orchestration** (host = Claude in Claude Code): Claude dispatches Codex to implement each unit, then Claude reviews the returned diff itself — no separate subprocess for peer review because Codex already implemented and Claude is naturally reviewing. **Build-handoff** (host = Codex in Codex): Codex implements natively, then shells out `claude -p` per unit for peer-review findings; Codex parses JSON and applies what it agrees with. Removed leftover "end-of-batch" wording that conflicted with §7.2's per-unit default. Per-unit step now explicitly describes how peer review is invoked in each flavor.
> - 2026-04-28 (revision 8): added single-agent fallback for users who only have one CLI installed (D31). When only Claude Code or only Codex is available, cross-review degrades to a fresh-instance subprocess of the host's own CLI. Same model, fresh context — still catches what the implementing session rationalized away (Superpowers' subagent-driven-development pattern). The contract from D30 still holds: peer reports, host applies. Peer's JSON response carries `peer_mode: "cross-agent" | "single-agent-fallback"` so the user always knows which mode they're in. Single-agent prompt is augmented with explicit "be more aggressive, bias toward finding problems" framing. New config option `peer_mode_override: "auto" | "cross-agent-only" | "single-agent-only" | "off"`. Setup script warns when only one CLI is detected; doesn't block. Required dependencies relaxed: at least one of Claude Code or Codex (was: both). Both still strongly recommended for full cross-agent perspective.
> - 2026-04-28 (revision 9): added installation and project-setup design (§19). Hybrid distribution: Claude Code plugin marketplace as primary (lowest friction); direct git-clone + `./setup` script as universal fallback. Native plugin manifests per host (`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`) — no Bun-based converter (skipped CE's complexity). Added `en-setup` as the 11th skill — handles project-level bootstrap with three states: new project (defers to `/en-foundation`), existing-without-Ensemble (creates skeleton, generates `AGENTS.md`/`CLAUDE.md` from templates, installs GH Action), existing-with-Ensemble (diagnostic mode mirroring CE's `check-health` pattern). New config files: `~/.ensemble/config.json` (machine-global), `<repo>/.ensemble/config.local.yaml` (per-developer per-repo, gitignored), `<repo>/.ensemble/config.local.example.yaml` (committed template). Skipped: gstack-style auto-update polling, telemetry, cross-machine memory sync, skill prefix toggling. Updated §14 Phase 7 with concrete deliverables for plugin distribution + setup tooling + project bootstrap.
> - 2026-04-28 (revision 10): three corrections to the install/setup design. (1) Path 1 (direct clone + `./setup`) is now the *preferred* install path; Path 2 (Claude Code marketplace) is the alternative. Direct clone handles multi-host installs in one operation and works regardless of marketplace availability. (2) `/en-setup` State 1 (new project) now recommends `/en-brainstorm` first, then `/en-foundation` — captures the typical greenfield flow rather than jumping straight to foundation. (3) `/en-setup` State 2 (existing without Ensemble) refined to handle four sub-variants based on what's already present: 2a no maps, 2b CLAUDE.md only, 2c AGENTS.md only, 2d both. Append-merge discipline: never overwrite existing user content; append Ensemble pointer index / Claude-specific section as new sections only if missing. The State-2 trigger broadened to "missing `docs/foundation.md` OR missing `docs/learnings/`" regardless of map presence. Added `references/templates/agents-md-merge-rules.md` to the reference list.
> - 2026-04-28 (revision 11): Codex review pass — addressed nine cleanup items. **Consistency:** added `depth: deep` to foundation frontmatter (was failing the lint schema it was about to ship); D22 fixed from "ten skills" to "eleven"; UC5 prefixed `cross-review` → `/en-cross-review`; D2 paths now point at `docs/plans/active/` and `docs/plans/completed/`; §19.8 contradictory "marketplace primary" wording fixed to align with §19.2 (Path 1 preferred). **`en-sweep` trigger normalization:** removed all stale "scheduled / cron / daily / weekly / scheduled pass" language; uniformly described as event-driven on `push` to `main`. **CI execution model for `en-sweep`:** added subsection covering wrapper script (`bin/en-sweep-ci`) that resolves `claude -p` or `codex exec`, required runner env (auth, timeout, branch naming), fallback when no CLI is available. **`en-sweep` loop guards:** added five-guard mechanism (skip sweep-authored commits, GH Actions concurrency group, sweep-PR labeling, no-material-diff termination, recursion depth cap) preventing self-trigger cascades. **Doc-only enforcement at runtime:** `bin/ensemble-doc-only-check` allowlist enforces non-doc paths can't be staged. **Auto-merge security model:** explicit GITHUB_TOKEN least-privilege, no PAT default, no fork-triggered runs, branch protection respected, fail-closed on detection errors. **`en-review` mode contract:** spelled out three modes and which mode every caller uses — particularly that `en-sweep` always uses `mode:report-only` so the gate doesn't mutate. **`en-build` flavor responsibilities:** distinguished WORKER dispatch (build-by-orchestration, may edit) from PEER-REVIEWER dispatch (build-handoff, must not edit per D30). Clarified D30 applies to peer-reviewer dispatch only. **New §20 Verification and Test Strategy:** golden frontmatter tests, doc-lint rule tests, host-detection tests, mock CLI fixtures (record/replay), sample repos for State 1/2a/2b/2c/2d/3, dry-run + doc-only enforcement + auto-merge security tests. Tests ship alongside each artifact, not bolted on at the end. **Design gaps:** `requirements_pending: true` frontmatter field for State-2 plans before foundation retrofit (P3 advisory; upgrades to P1 once foundation has R-IDs). `docs/generated/` promoted to mandatory with `plan-index.md` + `learning-index.md` seeded by setup. New §13.5 marks model names and CLI flags as defaults-to-verify, not promises — isolated to `references/cli-wrappers.md` so flag changes propagate from one update.
