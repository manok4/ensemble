---
name: en-foundation
description: "Produce the foundational artifact set for a new product or retrofit one for an existing project: docs/foundation.md (combined PRD + technical direction + architecture intent), docs/architecture.md (initial seed), AGENTS.md and CLAUDE.md (project-level pointer maps). Walks the user through depth-scaled discovery (product identity, users, requirements with R-IDs, UX, stack, data, architecture, API, deployment, security, risks), runs cross-agent peer review on the draft, then writes everything. Use whenever the user is starting a new product, retrofitting an existing project to Ensemble, or revising the foundation document. Trigger phrases: 'create foundation', 'foundation doc', 'new product', 'retrofit foundation', 'set up foundation', 'PRD and architecture'."
---

# `/en-foundation`

Combined PRD + technical direction + initial architecture seed for a project. Run **once** at project start (or `--retrofit` for an existing project); thereafter `/en-learn` keeps `docs/architecture.md` and the pointer maps current.

> **Hard gate.** This skill writes documents only — `docs/foundation.md`, `docs/architecture.md`, `AGENTS.md`, `CLAUDE.md`, and (for new projects) the `FR01-project-setup` plan. **No implementation, no PR, no source-code edits.**

## Process

1. **Detect host.** Source `references/host-detect.md`. Resolve `PEER_CMD`, `PEER_MODE` for the Outside Voice pass.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, skip the Outside Voice pass.
3. **Detect mode.**
   - `--retrofit` flag, or `docs/foundation.md` exists with `status: draft` → retrofit/edit mode.
   - Otherwise → fresh mode.
4. **Orient.** Read in parallel:
   - Existing `docs/foundation.md` (if any).
   - Brainstorm design docs in `docs/designs/`.
   - For State-2 retrofits: existing source code via `repo-research` agent (top-level structure, package.json/Cargo.toml/etc., conventions).
   - `docs/learnings/index.md` if present.
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
   
   **One question per turn**, multiple-choice when natural. Skip groups not relevant to the depth tier. Honor the question-count band per `references/foundation-questions.md`.
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
8. **Draft `docs/foundation.md`** using `references/templates/foundation-template.md`. Apply the depth-scaled trim (Lightweight skips §8/§9/§11–§13; Standard skips §11–§13 unless relevant). Substitute `{{PROJECT_NAME}}`, `{{ONE_LINE_PURPOSE}}`, `{{TODAY}}`, `{{OWNER}}`, `{{DEPTH}}`. Set `status: draft`.
9. **Section-by-section review with the user.** Walk each section briefly; user can revise inline before peer review.
10. **Outside Voice review.** If `PEER_AVAILABLE=true`, ship the draft to the peer:
    - Build the Outside Voice prompt per `references/outside-voice.md`.
    - Set `ENSEMBLE_PEER_REVIEW=true` env var.
    - Invoke `$PEER_CMD $PEER_FORMAT --max-turns 1` with the prompt.
    - Parse the JSON response (per `references/finding-schema.md`).
    - Apply, defer, or disagree per `references/severity.md`.
    - Surface the verdict + applied changes to the user.
11. **Seed `docs/architecture.md`** using `references/templates/architecture-template.md`. Pull components from §9, layer rules from §9.2, data flows from §9 / §8. Set `status: seed`. For retrofits, dispatch `repo-research` to populate components from the actual codebase.
12. **Write `AGENTS.md`** using `references/templates/agents-md-template.md`. Substitute `{{BUILD_CMD}}`, `{{TEST_CMD}}`, etc. detected from the project (or `<unset>` if not detectable).
13. **Write `CLAUDE.md`** using `references/templates/claude-md-template.md`. Strict structure: first non-frontmatter line is the AGENTS.md cross-reference; body Claude-Code-specific only.
14. **Detect new vs existing project (per A1 / D24).**
    - New project: `docs/foundation.md` did not exist before this run AND repo has no source code outside `node_modules/`/`vendor/`/equivalents (or initial-commit state) → emit `docs/plans/active/FR01-project-setup.md` using `references/templates/plan-template.md` with units for repo init, dependencies, CI, baseline tests.
    - Existing project → skip FR01 entirely.
15. **Final save.** Flip `docs/foundation.md` `status:` from `draft` to `active` after the user accepts the peer-reviewed version.
16. **Hand off.** Suggest next step:
    - New project: "Run `/en-build docs/plans/active/FR01-project-setup.md` to bootstrap the repo."
    - Existing project: "Run `/en-plan` for the first feature."

## Retrofit mode (`--retrofit`)

Used by `/en-setup` State 2 to back-fill the foundation for an existing project. Differences from fresh mode:

- Heavy use of `repo-research` agent in step 4 — codebase is the source of truth for §7 (stack), §8.1 (entities), §9 (components).
- Discovery questions tilted toward "what is", not "what should be" — confirm detected values rather than ask open-ended.
- §5 (Functional requirements) is the trickiest: the agent reads the codebase and infers requirements from observed behavior, then asks the user to confirm/correct.
- No `FR01-project-setup` (project already exists).
- `docs/architecture.md` `status:` flipped to `active` immediately if the codebase has shipped features.

## Cross-review

**On by default.** Skip with `--no-peer`. Skip automatically when `PEER_AVAILABLE=false`.

When peer is available:

- Cross-agent (both CLIs installed) → peer is the *other* agent (per D23).
- Single-agent fallback → fresh subprocess of host's CLI (per D31). Prompt augmented per `references/single-agent-fallback.md`.

## Capture-from-synthesis (D21)

If the discovery surfaced a non-obvious decision (e.g., "we picked Drizzle over Prisma because…"), end with a soft prompt:

> "Section 4 captured a decision worth filing as a learning. Capture?"

User accepts → `/en-learn capture --from-conversation` files it as `decisions/`.

## Output

After the run completes, output a structured report:

```
Project: {{PROJECT_NAME}}
Depth: standard
Mode: fresh

Created:
  - docs/foundation.md (1850 lines, 7 R-IDs, 4 D-IDs)
  - docs/architecture.md (status: seed)
  - AGENTS.md (98 lines)
  - CLAUDE.md (52 lines)
  - docs/plans/active/FR01-project-setup.md (4 units)

Peer review: cross-agent (codex). Verdict: revise. Applied 3 of 5 findings.

Next: Run /en-build docs/plans/active/FR01-project-setup.md to bootstrap the repo.
```

## Reference files

- `references/templates/foundation-template.md` — body template + depth-scaled trim
- `references/foundation-questions.md` — Q&A library + count bands
- `references/templates/architecture-template.md` — initial architecture seed
- `references/templates/agents-md-template.md` — AGENTS.md template
- `references/templates/claude-md-template.md` — CLAUDE.md template
- `references/templates/plan-template.md` — for FR01-project-setup
- `references/host-detect.md` — host detection
- `references/outside-voice.md` — peer-review prompt and verdict handling
- `references/single-agent-fallback.md` — fallback mode contract
- `references/finding-schema.md` — peer JSON shape
- `references/severity.md` — apply/defer/disagree routing
- `references/research-dispatch.md` — when to use `repo-research`, `learnings-research`, `web-research`
- `references/stable-ids.md` — R-IDs / A-IDs / F-IDs / AE-IDs / D-IDs / Q-IDs

## Failure protocol

| Failure | Behavior |
|---|---|
| User abandons mid-discovery | Save partial draft as `docs/foundation.md` with `status: draft`; user can resume |
| Peer review subprocess fails or times out | Note in foundation: "Peer review skipped due to subprocess failure"; continue without |
| `repo-research` returns malformed output (retrofit mode) | Surface; ask user to fill in §7 / §8 / §9 manually |
| User declines peer's findings on a P0 → host disagrees | Pause and surface to user; do not proceed without explicit user judgment |
| Concurrent `docs/foundation.md` edit detected (file changed since orient step) | Stop and ask user — don't overwrite |
