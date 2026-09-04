---
name: en-foundation
description: "Produce or retrofit the foundational artifacts: docs/foundation.md (PRD, tech direction, architecture), docs/architecture.md, AGENTS.md, CLAUDE.md; the draft is peer-reviewed. Trigger phrases: 'create foundation', 'foundation doc', 'new product', 'retrofit foundation', 'PRD and architecture'."
---


# `/en-foundation`

> **Running a bundled script.** Anchor every call to this skill's own directory: `SKILL_DIR="<absolute path of the directory containing this SKILL.md>"; bash "$SKILL_DIR/scripts/<name>"`. The trailing `;` is load-bearing. See `references/script-invocation.md`.


> **Dispatching a bundled agent.** This skill carries its agents in `agents/`. Dispatch by name as usual; when the name is not registered (a lone skill directory), resolve it from the bundled definition per `references/agent-dispatch.md`.


Combined PRD + technical direction + initial architecture seed for a project. Run **once** at project start (or `--retrofit` for an existing project); thereafter `/en-learn` keeps `docs/architecture.md` and the pointer maps current.

> **Hard gate.** This skill writes documents only — `docs/foundation.md`, `docs/architecture.md`, `AGENTS.md`, `CLAUDE.md`, and (for new projects) the bootstrap plan `docs/plans/active/<PREFIX>01-feature_project-setup.md` where `<PREFIX>` is the resolved `plan_id_prefix` (default `FR`). **No implementation, no PR, no source-code edits.**

> **Peer contract.** Severity, confidence, autofix class, the `peer_decision`
> object and its reason enum are defined once in `references/peer-contract.md`
> and are byte-identical across every skill that exchanges findings. What this
> skill *does* with a finding is its own policy, not part of that contract.

## Process

1. **Detect host.** Source `references/host-detect.md`. Resolve `PEER_CMD`, `PEER_MODE` for the Outside Voice pass.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, skip the Outside Voice pass.
3. **Detect mode.**
   - `--retrofit` flag, or `docs/foundation.md` exists with `status: draft` → retrofit/edit mode.
   - Otherwise → fresh mode.
4. **Orient, and write down what you already know.** Read in parallel:
   - Existing `docs/foundation.md` (if any).
   - Brainstorm design docs in `docs/designs/`.
   - `docs/learnings/index.md` if present. Read it inline — this skill does not dispatch a learnings scout (see `references/research-dispatch.md`).
   - For retrofits: the codebase via the `repo-research` agent. **Scope before you scan.** If the user named a subsystem, take it. Otherwise run `git log --oneline -n 200 --name-only` and let the files that keep recurring pull attention first, widening only if the changes are scattered with no hot spot. A foundation retrofit describes what the project *is*, and the parts under active change are the parts whose shape is still load-bearing; an even scan over a large codebase spends its budget on code nobody touches.

   **Output a known-facts ledger** before moving on: for each discovery group (§1, §2, §3, §5, §6, §7, §8, §9, §10, §11, §13, §14), record `answered` (with the value and where it came from), `partial`, or `unknown`. The ledger is what step 6 subtracts against, and it is the difference between a Deep run costing 30–45 questions and costing what is genuinely still open. Surface it in one line: *"Orient answered §7 (stack: TypeScript/Bun/Postgres, from package.json) and §10 (12 routes, from src/api/); §1–§6 and §14 are open."*
5. **Right-size depth.** Lightweight / Standard / Deep — picks based on project complexity. Default Standard.
6. **Discovery loop.** Walk the topic groups in `references/foundation-questions.md`:
   - §1 Executive identity & problem
   - §2 Goals & non-goals (G-IDs)
   - §3 Users & roles (A-IDs)
   - §5 Functional requirements (R-IDs assigned here, append-only thereafter; AE-IDs for acceptance examples)
   - §6 User experience (F-IDs)
   - §7 Technical direction (stack, hosting, security model)
   - §8 Data architecture (Standard / Deep)
   - §9 Architecture intent (Standard / Deep)
   - §10 API surface
   - §11 Deployment & infra (Deep)
   - §13 Security & privacy (Deep)
   - §14 Risks & open questions
   
   **One question per turn**, multiple-choice when natural. Honor the question-count band per `references/foundation-questions.md`.

   **Ask only what the ledger left open.** Skip groups the depth tier excludes, *and* skip every question step 4 already answered. A group marked `answered` is not asked — it is **confirmed in one line** (*"Detected TypeScript/Bun/Postgres from package.json — correct?"*), which is one turn instead of the group's full question set. A group marked `partial` is asked only for its gaps. Re-asking what orient just read is the single largest avoidable cost in this skill, and on a retrofit it is also the most annoying: the answers are sitting in the repo the user is pointing you at.

   **The user can stop at any point.** "That's enough", "just write it", or similar moves straight to step 6a with what exists; unanswered groups become `## Open questions` entries with Q-IDs rather than blocking the draft.
6a. **Traceability gate.** Before synthesizing, check that the ID graph connects. For every goal (G-ID) and every actor (A-ID) captured, confirm at least one requirement (R-ID) serves it, and that every requirement carries at least one acceptance example (AE-ID).

    **This is a judgment check, not a tally.** The rule is *every goal or actor **that affects behavior** is served by a requirement, or is explicitly deferred with a reason* — never "every ID appears somewhere". A mechanical count invites exactly the padding it is meant to prevent: requirements written to satisfy a counter, which then propagate into plans as real work. The load-bearing words are "affects behavior"; a goal that is context rather than a commitment needs no requirement.

    **Deferral is a first-class outcome.** An uncovered goal is recorded as deferred with its reason, not silently dropped and not force-fitted to a requirement.

    **Conditional on the section existing.** Depth tiers legitimately omit sections — Lightweight has no §8/§9, and a project may have no distinct actors. A gate that fires on an absent section is noise, and produces empty headers and dangling IDs in the draft. Check only the groups this run actually captured.

    Surface the result in one line, whichever way it goes: *"Traceability: 4 goals, 7 requirements, 12 acceptance examples. G2 (developer onboarding) deferred — no requirement this release, recorded in §14."*

7. **Synthesize.** Present a structured summary for approval before writing:
   ```
   Here's what I have:
     §1: <one-paragraph product summary>
     §2: <bulleted goals>
     §5: 7 requirements (R1–R7) with acceptance examples
     §7: TypeScript / Bun / Postgres
     §9: 3 components (auth, billing, dashboard)
     §14: 3 risks
   
   Ready to write the foundation? (y / let me revise X)
   ```
8. **Resolve `plan_id_prefix`.** Derive a 2–3 uppercase-letter suggestion from `{{PROJECT_NAME}}` (e.g. `Ensemble` → `EN`; `Ella Website` → `EW`; `User Dashboard Service` → `UDS`). Ask the user to accept or override:
   > "Plan-ID prefix for this project? Suggested: `EN` (used like `EN03`). Press enter to accept, or type a 2–3 uppercase-letter alternative."
   Validate: 2–3 chars, `[A-Z]+`, not in the reserved set `{R, U, AE, TD}`. On retrofit (foundation already exists with a `plan_id_prefix:`), keep the existing value — never silently change it after plans have been minted. If the user declines to set one, use `FR` as the fallback.
9. **Draft `docs/foundation.md`** using `references/templates/foundation-template.md`.

    **Report at the precision you actually have.** This document is the root every plan in the project cites, so a number invented here is load-bearing for the life of the repo.
    - **Never upgrade a directional goal into a measurable one.** If the user said "faster onboarding", write that. Do not render it as "onboarding under 5 minutes" because a target reads better — nobody committed to that number.
    - **No invented metrics.** A success measure the user did not give is `TBD`, not a plausible figure.
    - **No placeholder text survives.** A section is written with real content or removed. `[TODO]` must not appear in the output; an unresolved item is a Q-ID in §14, where it is visible as open rather than disguised as answered.
    - **Use the user's terminology.** Mirror their words for their domain; do not translate them into generic product vocabulary. The glossary the project inherits is the one written here.

    Apply the depth-scaled trim, and drop any template section this run has no real content for. Apply the depth-scaled trim (Lightweight skips §8/§9/§11–§13; Standard skips §11–§13 unless relevant). Substitute `{{PROJECT_NAME}}`, `{{ONE_LINE_PURPOSE}}`, `{{TODAY}}`, `{{OWNER}}`, `{{DEPTH}}`, `{{PLAN_ID_PREFIX}}`. Set `status: draft`.
10. **Section-by-section review with the user.** Walk each section briefly; user can revise inline before peer review.
11. **Outside Voice review.** If `PEER_AVAILABLE=true`, ship the draft to the peer:
    - Build the Outside Voice prompt by shelling out to `$SKILL_DIR/scripts/ensemble-build-peer-prompt --brief "$SKILL_DIR/references/peer-brief.md" --project-context "<one-line from §1>" --goal "Foundation review" --artifact-file docs/foundation.md --peer-mode "$PEER_MODE"`. Don't assemble the prompt by reasoning.
    - Set `ENSEMBLE_PEER_REVIEW=true` env var.
    - **Invoke via `$SKILL_DIR/scripts/ensemble-peer-invoke`** with `ENSEMBLE_PEER_REVIEW=true`, passing `$PEER_CMD`, `$PEER_FORMAT`, `$PEER_TURNS`, the prompt file, and `--peer-mode "$PEER_MODE"`. **Do not restate the invocation or retry algorithm** — the helper owns the `timeout` wrapper, failure classification (`auth` / `unknown` / `timeout`), the single bounded retry, and the fallback, so the behaviour is executable and testable rather than prose (D41). It returns a `peer_decision` object per `references/peer-contract.md`; surface its `peer`/`reason` in the run report so a skipped or degraded peer can never read as a normal one. A document review runs at the peer's default tier; this skill passes no effort flag.
    - Parse the JSON response (per `references/finding-schema.md`).
    - Apply, defer, or disagree per the routing table in `references/peer-brief.md`.
    - Surface the verdict + applied changes to the user.
12. **Seed `docs/architecture.md`** using `references/templates/architecture-template.md`. Pull components from §9, layer rules from §9.2, data flows from §9 / §8. Set `status: seed`. For retrofits, dispatch `repo-research` to populate components from the actual codebase.
13. **Write `AGENTS.md`** using `references/templates/agents-md-template.md`. Substitute `{{BUILD_CMD}}`, `{{TEST_CMD}}`, etc. detected from the project (or `<unset>` if not detectable).
14. **Write `CLAUDE.md`** using `references/templates/claude-md-template.md`. Strict structure: first non-frontmatter line is the AGENTS.md cross-reference; body Claude-Code-specific only.
15. **Detect new vs existing project (per A1 / D24).**
    - New project: `docs/foundation.md` did not exist before this run AND repo has no source code outside `node_modules/`/`vendor/`/equivalents (or initial-commit state) → emit `docs/plans/active/<PREFIX>01-feature_project-setup.md` using `references/templates/plan-template.md` with `plan_type: feature`, units for repo init, dependencies, CI, baseline tests. `<PREFIX>` is the resolved `plan_id_prefix`.
    - Existing project → skip the bootstrap plan entirely.
16. **Final save.** Flip `docs/foundation.md` `status:` from `draft` to `active` after the user accepts the peer-reviewed version.
17. **Hand off.** Suggest next step:
    - New project: "Run `/en-build docs/plans/active/<PREFIX>01-feature_project-setup.md` to bootstrap the repo."
    - Existing project: "Run `/en-plan` for the first feature."

## Retrofit mode (`--retrofit`)

Used by `/en-setup` State 2 to back-fill the foundation for an existing project. Differences from fresh mode:

- Heavy use of the `repo-research` agent in step 4, hot-spot-scoped — the codebase is the source of truth for §7 (stack), §8.1 (entities), §9 (components), and §10 (API surface).
- Those four groups arrive at step 6 already marked `answered` in the ledger, so they are **confirmed in one line each**, not asked. This is where the ledger pays for itself: a retrofit's most mechanically-answerable sections are also its most tedious to ask about.
- Remaining discovery questions tilt toward "what is", not "what should be".
- §5 (Functional requirements) is the trickiest: the agent reads the codebase and infers requirements from observed behavior, then asks the user to confirm/correct.
- No bootstrap `<PREFIX>01-feature_project-setup` plan (project already exists).
- `docs/architecture.md` `status:` flipped to `active` immediately if the codebase has shipped features.

## Cross-review

**On by default.** Skip with `--no-peer`. Skip automatically when `PEER_AVAILABLE=false`.

When peer is available:

- Cross-agent (both CLIs installed) → peer is the *other* agent (per D23).
- Single-agent fallback → fresh subprocess of host's CLI (per D31). The prompt builder adds the fallback framing itself when `--peer-mode single-agent-fallback` is passed.

## Capture-from-synthesis (D21)

If the discovery surfaced a non-obvious decision (e.g., "we picked Drizzle over Prisma because…"), end with a soft prompt:

> "Section 4 captured a decision worth filing as a learning. Capture?"

User accepts → `/en-learn capture --from-conversation` files it as `decisions/`.

## Output

After the run completes, output a structured report. Substitute the resolved `<PREFIX>` (from `plan_id_prefix:`) into the bootstrap-plan path — the example below uses `EN`:

```
Project: {{PROJECT_NAME}}
Depth: standard
Mode: fresh

Created:
  - docs/foundation.md (1850 lines, 7 R-IDs, 4 D-IDs)
  - docs/architecture.md (status: seed)
  - AGENTS.md (98 lines)
  - CLAUDE.md (52 lines)
  - docs/plans/active/EN01-feature_project-setup.md (4 units)

Peer review: cross-agent (codex). Verdict: revise. Applied 3 of 5 findings.

Next: Run /en-build docs/plans/active/EN01-feature_project-setup.md to bootstrap the repo.
```

## Reference files

- `references/templates/foundation-template.md` — body template + depth-scaled trim
- `references/foundation-questions.md` — Q&A library + count bands
- `references/templates/architecture-template.md` — initial architecture seed
- `references/templates/agents-md-template.md` — AGENTS.md template
- `references/templates/claude-md-template.md` — CLAUDE.md template
- `references/templates/plan-template.md` — for the bootstrap `<PREFIX>01-feature_project-setup` plan
- `references/host-detect.md` — host detection
- `references/outside-voice.md` — peer-review prompt and verdict handling
- `references/peer-brief.md` — what the peer is asked, and how its findings route
- `references/peer-contract.md` — severity, confidence and the `peer_decision` object, shared
- `references/finding-schema.md` — peer JSON shape
- `references/research-dispatch.md` — when to dispatch `repo-research`, and why this skill reads learnings inline instead of scouting
- `references/stable-ids.md` — R-IDs / A-IDs / F-IDs / AE-IDs / D-IDs / Q-IDs

## Failure protocol

| Failure | Behavior |
|---|---|
| User abandons mid-discovery | Save partial draft as `docs/foundation.md` with `status: draft`; user can resume |
| Peer review subprocess fails or times out | Note in foundation: "Peer review skipped due to subprocess failure"; continue without |
| `repo-research` returns malformed output (retrofit mode) | Surface; ask user to fill in §7 / §8 / §9 manually |
| User declines peer's findings on a P0 → host disagrees | Pause and surface to user; do not proceed without explicit user judgment |
| Concurrent `docs/foundation.md` edit detected (file changed since orient step) | Stop and ask user — don't overwrite |
