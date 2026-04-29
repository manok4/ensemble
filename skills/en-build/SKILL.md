---
name: en-build
description: "Execute an implementation plan unit-by-unit on a feature branch (or worktree). Picks one of two flavors based on host detection: build-by-orchestration (Claude host dispatches Codex as worker) or build-handoff (Codex host implements natively, dispatches Claude as peer-reviewer). Each unit goes through verification gate 1 (tests + lint), code-simplifier pass, verification gate 2, per-unit Outside Voice peer review, host applies findings, re-verify, commit. Auto-invokes /en-learn at the end. Use whenever the user has a plan in docs/plans/active/ ready to implement. Trigger phrases: 'build this plan', 'implement FRXX', 'start building', 'execute the plan', 'build /en-plan output'."
---

# `/en-build`

Execute a plan, unit by unit, with cross-agent peer review at every per-unit gate. Two flavors based on host detection — both guarantee implementer ≠ reviewer.

> **Hard preconditions.** A plan in `docs/plans/active/FR<NN>-*.md` with `status: active`, all U-IDs present, no unblocked dependencies. The skill verifies these at start.

## Process

1. **Detect host.** Source `references/host-detect.md`. Resolve `HOST`, `PEER`, `PEER_MODE`, `PEER_CMD`, `PEER_FORMAT`.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, skip all peer-review subprocess calls (host implements + reviews inline).
3. **Choose flavor.**
   - HOST = Claude Code → **build-by-orchestration** (Codex as worker). See `references/build-orchestration.md`.
   - HOST = Codex → **build-handoff** (Claude as peer-reviewer). See `references/build-handoff.md`.
   - User can override with `--orchestrate` or `--handoff`.
   - If the dispatched agent's CLI isn't available, fall back gracefully:
     - build-by-orchestration with no Codex → degrade to native implement + peer review (build-handoff with same-agent fallback).
     - build-handoff with no Claude → fall back to single-agent peer review (`codex exec` fresh subprocess).
4. **Load plan.** Read `<plan-path>`. Verify all U-IDs present and unblocked. Verify each unit has Goal, Files, Approach, Test scenarios. If not, surface and stop.
5. **Set up branch.**
   - If on default branch → create `<fr-id>-<slug>` feature branch.
   - If on a feature branch → use it.
   - If working tree is dirty → ask user: stash, commit, or abort.
   - **Worktree** (D28): if user passed `--worktree`, create one at `../<repo>-<fr-id>/` and dispatch in there.
6. **Read context.** Foundation, related plan files (deps from this plan's `related:`), `CLAUDE.md`, `AGENTS.md`, project conventions.
7. **Plan review with user.** Surface concerns: "Plan touches 12 files; some intersect with FR05 (in-flight). Continue, pause, or split?" Address before starting.
8. **Determine batch size.** Per A2 / D25 — derive from the plan:
   - Independent units → larger batch (3–5).
   - Tightly-coupled units → smaller batch (1–2).
   - Auth/payments/migrations → batch alone.
9. **For each unit (in dependency order):**
   - **8a. Honor execution note** (test-first / characterization-first / pragmatic).
   - **8b. Implement** via the flavor's flow (worker dispatch or native).
   - **8c. Verification gate 1.** Run unit tests + project lint. Failures → fix before proceeding (don't advance to simplifier or review on broken unit).
   - **8d. Code-simplifier pass.** Per `references/code-simplifier-dispatch.md`. Skip on trivial units, on `--no-simplify`, or with the auto-skip heuristics.
   - **8e. Verification gate 2.** Re-run unit tests after simplifier. On failure: revert simplifier's changes (`git restore` for files in `changes_made[]`); proceed with original implementation; surface regression.
   - **8f. Outside Voice peer review.** Per the chosen flavor (`build-orchestration.md` or `build-handoff.md`). Set `ENSEMBLE_PEER_REVIEW=true` for any subprocess call.
   - **8g. Host applies findings** per `references/severity.md`: agree-and-apply / agree-and-defer-to-tech-debt-tracker / disagree-with-rationale.
   - **8h. Surface to user** if peer reports a P0 the host disagrees with, or a security/architecture finding (confidence ≥ 8) the host wants to defer, or peer verdict = `reject`. All other host decisions proceed without confirmation.
   - **8i. Re-verify** if any code changed in 8g — unit tests + lint. On failure: revert; surface.
   - **8j. Commit.** Conventional message including U-ID. Body lists peer findings handled (applied / deferred / disagreed). Format per `references/build-orchestration.md` or `build-handoff.md`.
10. **After all units:**
    - Full test suite, lint, typecheck.
    - Summary: completion status per U-ID, deviations, simplifier changes, peer-review verdicts.
    - **Auto-invoke `/en-learn`** (soft prompt — A3): "Build complete. Capture learnings? (yes / skip)". User accepts → invoke; user declines → no-op.
    - Suggest next: `/en-review` → `/en-qa` → `/en-ship`.

## Flags

| Flag | Effect |
|---|---|
| `--orchestrate` | Force build-by-orchestration regardless of host |
| `--handoff` | Force build-handoff regardless of host |
| `--no-simplify` | Skip code-simplifier on every unit |
| `--no-peer-per-unit` | Skip per-unit Outside Voice peer review |
| `--worktree` | Run in a worktree (`../<repo>-<fr-id>/`) |
| `--unit U<N>` | Build only the named unit; don't auto-advance |
| `--dry-run` | Show what would happen; don't write or commit |
| `--from U<N>` | Resume from a specific unit (skip earlier ones) |

## Cross-review

**On per unit by default.** Disable globally with `--no-peer-per-unit`. Auto-skipped:

- When `PEER_AVAILABLE=false`.
- When `ENSEMBLE_PEER_REVIEW=true` (recursion guard).
- On units with diff < `skip_peer_below_lines` (default 50).
- On Lightweight depth plans IF `skip_peer_on_lightweight: true`.

When peer is available:
- Cross-agent → peer is the *other* agent (D23).
- Single-agent fallback → fresh subprocess of host's CLI (D31). Prompt augmented per `references/single-agent-fallback.md`.

## Code simplification

**On per unit by default.** Skipped on:

- Trivial units (renames, single-line config tweaks, pure deletions).
- `--no-simplify` flag.
- Units where the diff exceeds `simplifier.max_lines_to_run` (default 2000).

Two verification gates protect against simplifier breakage. On Gate-2 failure, revert the simplifier's edits and continue with the original implementation (per `references/code-simplifier-dispatch.md`).

## Per-unit progress report

After each unit commits, surface a one-line summary:

```
✓ U3 — feat(auth): wrap rotateRefreshToken in singleFlight
  Implementer: codex (worker) | Simplifier: 2 changes | Peer: applied 1, deferred 1
  Tests: 7 added, 7 passing | Commit: a3f1b9c
```

## Final summary

After all units complete:

```
Build summary — FR07-auth-rotation (5 units)

✓ U1: Add singleFlight helper (feat: 12 files, 4 tests)
✓ U2: Wire Redis connection (feat: 3 files)
✓ U3: Wrap rotateRefreshToken (feat: 2 files, 3 tests, peer applied 1)
✓ U4: Migration for refresh_token_rotated_at (feat: 1 file, manual review surfaced)
✓ U5: Update test coverage (test: 6 files, 12 tests)

Full suite: 247 passing, 0 failing.
Lint: clean.
Typecheck: clean.

Code-simplifier: 4 of 5 units; 7 file changes total.
Peer review: cross-agent (codex). 4 findings applied, 2 deferred to tech-debt-tracker (TD11, TD12).

Auto-invoking /en-learn (capture learnings? y/n) →
```

## Reference files

- `references/host-detect.md` — host detection
- `references/build-orchestration.md` — Claude-host flow (worker dispatch)
- `references/build-handoff.md` — Codex-host flow (peer-reviewer dispatch)
- `references/code-simplifier-dispatch.md` — when/how to run simplifier; revert protocol
- `references/outside-voice.md` — peer-review prompt and verdict handling
- `references/single-agent-fallback.md` — fallback when only one CLI installed
- `references/finding-schema.md` — peer JSON shape
- `references/severity.md` — apply / defer / disagree routing
- `references/recursion-guard.md` — ENSEMBLE_PEER_REVIEW env var
- `references/stable-ids.md` — U-ID stability rules

## Failure protocol

| Failure | Behavior |
|---|---|
| Plan has unmet dependency (`Depends: U7` but U7 not present) | Stop; surface; suggest plan revision |
| Verification gate 1 fails on a unit | Pause; show test output; ask user: retry, skip, abort |
| Verification gate 2 fails | Revert simplifier edits automatically; proceed with original; surface regression |
| Peer review verdict = `reject` | Pause and surface to user before commit |
| Peer subprocess attempts to modify files (D30 violation) | Detect via git status; revert; do not trust this round of findings; log violation |
| Worker dispatch returns malformed diff | Retry once; on second failure, surface and ask user to take over the unit |
| `git restore` fails on a revert | Surface; abort the build; do not leave the working tree corrupted |
| User asks to abort mid-unit | Commit the unit's progress so far on a WIP branch; surface state |

## What this skill never does

- **Never modifies a plan.** Plan changes are `/en-plan` territory.
- **Never opens a PR.** PRs are `/en-ship` territory.
- **Never deletes files outside the unit's scope.**
- **Never bypasses verification gates.** A gate failure stops or reverts; never proceeds anyway.
- **Never invokes `/en-build` recursively.** Recursion guard ensures this.
