---
name: en-plan
description: "Turn a feature, component, or refactor into a concrete implementation plan with stable U-IDs (never renumbered). Reads docs/foundation.md and any related brainstorm design doc, runs research agents (repo-research + learnings-research, web-research conditionally), breaks the work into implementation units with files / dependencies / test scenarios / execution notes (test-first vs characterization-first vs pragmatic), then runs cross-agent peer review on the draft. Outputs to docs/plans/active/FRXX-<name>.md with auto-incremented FRXX. Use whenever the user is about to implement something non-trivial: new feature, refactor, migration, multi-file change. Trigger phrases: 'plan this', 'plan a feature', 'implementation plan', 'break this down', 'before I build', 'plan FR'."
---

# `/en-plan`

Concrete implementation plan with stable U-IDs and Outside Voice peer review. Hands off to `/en-build`.

> **Hard gate.** Plan only — no code, no commits, no PR. Output is a markdown plan file plus the peer-review verdict.

## Process

1. **Detect host.** Source `references/host-detect.md`. Resolve `PEER_CMD`, `PEER_MODE`.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, skip the Outside Voice pass.
3. **Resume or create.** If a plan in `docs/plans/active/` already matches the user's request (by title or `related_design`), offer to resume rather than create a new one.
4. **Source the request.** Identify input:
   - Brainstorm design doc (`docs/designs/*.md`) — pre-explored, recommendation already on the table.
   - `docs/foundation.md` — pulling a requirement (R-ID) for the next slice of work.
   - Direct rough description from the user.
   - Bug report or tracked debt item (`Resolves: TD<N>`).
5. **Right-size depth.**
   - Lightweight: 1–3 units, single file or two, no architecture changes.
   - Standard: 3–10 units, several files, possible new components.
   - Deep: 10+ units, structural change, multi-week work.
   Depth is asked or inferred; default Standard.
6. **Phase 1 research (parallel).** Per `references/research-dispatch.md`:
   - `repo-research` — patterns, conventions, file paths, prior art (Standard/Deep always).
   - `learnings-research` — relevant entries from `docs/learnings/` via `index.md` (Lightweight optional, Standard/Deep always).
   - `web-research` — only if a 3rd-party library not used elsewhere AND the library has known footguns AND the user hasn't said "skip web research".
7. **Resolve planning questions.** One per turn:
   - Which architecture do we land on (if multiple were on the table)?
   - File boundaries — new files vs extending existing?
   - Test strategy — unit, integration, end-to-end? Test-first / characterization-first / pragmatic?
   - Dependencies — any new packages? (Bias toward boring tech — see foundation §17.4.)
   - Migrations — schema, data, config?
8. **Break into units (U-IDs).**
   - Each unit: one logical change, peer-reviewable, atomically committable.
   - Tightly-coupled changes batch into one unit; independent concerns become separate units.
   - Auth/payments/migrations always get their own unit even if small.
   - **Never renumber after assignment** (per `references/stable-ids.md`).
9. **Per-unit metadata.** For each U-ID:
   - **Goal:** one line.
   - **Requirements covered:** R-IDs and AE-IDs from foundation. (For State-2 retrofit projects without a foundation yet, leave `covers_requirements: []` and set `requirements_pending: true`.)
   - **Dependencies:** other U-IDs that must complete first.
   - **Files:** repo-relative paths.
   - **Approach:** how the unit will be implemented.
   - **Execution note:** `test-first` / `characterization-first` / `pragmatic`.
   - **Patterns to follow:** citations to `docs/learnings/patterns/` if relevant.
   - **Test scenarios:** explicit list.
   - **Verification:** what counts as done (tests passing, lint clean, manual check).
   - **Resolves (optional):** `TD<N>` IDs from `docs/plans/tech-debt-tracker.md`.
10. **Auto-increment FRXX.** Scan `docs/plans/active/` and `docs/plans/completed/` for the highest existing FRXX. Increment. Zero-pad to 2 digits.
11. **Write to `docs/plans/active/FR<NN>-<slug>.md`** using `references/templates/plan-template.md`. Substitute fields. Status: `draft` → `active` after user accepts.
12. **Outside Voice review.** If `PEER_AVAILABLE=true`:
    - Build the prompt per `references/outside-voice.md`.
    - Set `ENSEMBLE_PEER_REVIEW=true`.
    - Invoke `$PEER_CMD $PEER_FORMAT --max-turns 1` with the prompt.
    - Parse JSON; apply, defer, or disagree per `references/severity.md`.
    - Surface verdict + applied changes.
13. **Confidence check.** Identify low-confidence sections (typically integrations or unfamiliar libraries); offer to deepen with a research dispatch or to leave as-is and resolve during build.
14. **Capture-from-synthesis reflex (D21).** If a non-obvious connection or pattern emerged during planning, soft-prompt to capture as a learning.
15. **Hand off to `/en-build`.** Suggest the build command:
    > "Plan written: `docs/plans/active/FR07-auth-rotation.md` (5 units). Ready to build with `/en-build docs/plans/active/FR07-auth-rotation.md`?"

## Cross-review

**On by default.** Skip with `--no-peer`. Skipped automatically when:

- `PEER_AVAILABLE=false`.
- The plan has < 50 lines (`skip_peer_below_lines` config).
- Depth is Lightweight AND `skip_peer_on_lightweight: true`.

When peer is available:

- Cross-agent (both CLIs installed) → peer is the other agent.
- Single-agent fallback → fresh subprocess of host's CLI; prompt augmented per `references/single-agent-fallback.md`.

## Tech-debt resolution

If the user mentions a tech-debt item or the plan addresses one:

1. Read `docs/plans/tech-debt-tracker.md`.
2. Cite the TD-ID(s) in the plan's per-unit metadata: `Resolves: TD7, TD12`.
3. Frontmatter: append to the plan's `resolves:` field (if extending the schema for the project).
4. Don't delete the tech-debt entry — `/en-learn` will mark it resolved when the plan ships.

## State-2 retrofit fallback

If `docs/foundation.md` doesn't exist yet (the user is using `/en-plan` before `/en-foundation` for retrofits):

- Set `covers_requirements: []` and `requirements_pending: true` in the plan's frontmatter.
- Surface the gap: "No `docs/foundation.md` yet. Plan will reference requirements as `requirements_pending: true`. Run `/en-foundation --retrofit` later to back-fill R-IDs."
- `bin/ensemble-lint` emits a P3 advisory (not a P1 blocker) for plans in this state. Once foundation has R-IDs, the rule upgrades to P1 and `/en-learn` back-fills `covers_requirements` based on plan content.

## Output

After the run completes:

```
Plan: docs/plans/active/FR07-auth-rotation.md (5 units, 380 lines)

Units:
  - U1: Add singleFlight<K, V> helper (test-first)
  - U2: Wire Redis connection (pragmatic)
  - U3: Wrap rotateRefreshToken in singleFlight (test-first)  ← critical path
  - U4: Migration for refresh_token_rotated_at column (characterization-first)
  - U5: Update tests covering AE2, AE3 (test-first)

Peer review: cross-agent (codex). Verdict: revise. Applied 2 of 3 findings (1 deferred to TD8).

Next: /en-build docs/plans/active/FR07-auth-rotation.md
```

## Reference files

- `references/templates/plan-template.md` — body template
- `references/host-detect.md` — host detection
- `references/outside-voice.md` — peer-review prompt and verdict handling
- `references/single-agent-fallback.md` — fallback mode contract
- `references/finding-schema.md` — peer JSON shape
- `references/severity.md` — apply / defer / disagree routing
- `references/research-dispatch.md` — when to dispatch which research agent
- `references/stable-ids.md` — U-ID stability rules

## Failure protocol

| Failure | Behavior |
|---|---|
| Plan touches > 30 files | Surface size warning; offer to split into multiple FRs |
| Two units claim the same file with conflicting changes | Flag as a planning bug; don't write the plan |
| User accepts plan but peer review hasn't returned yet | Wait for peer (with timeout); if peer times out, plan is written without peer verdict; surface "peer review timed out" in the report |
| Peer rejects the plan (verdict: reject) | Pause and ask user; do not flip status to `active` until user explicitly accepts |
| FRXX collision (race condition) | Re-scan; increment; retry. Lint will catch if it actually slips through |
