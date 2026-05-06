---
name: en-plan
description: "Turn a feature, refactor, or bug fix into a plan with stable U-IDs and plan_type (feature | improvement | bug). Reads foundation, runs research agents (repo-research + learnings-research; web-research conditional), breaks work into units with files / tests / execution notes; runs cross-agent peer review on the draft. Modes: --resume <plan> (promote a draft); --from-legacy <path> (migrate legacy plan). Outputs docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md. Trigger phrases: 'plan this', 'plan a feature', 'before I build', 'plan <id>'."
---

# `/en-plan`

Concrete implementation plan with stable U-IDs and Outside Voice peer review. Hands off to `/en-build`.

> **Hard gate.** Plan only — no code, no commits, no PR. Output is a markdown plan file plus the peer-review verdict.

## Process

1. **Detect host.** Source `references/host-detect.md`. Resolve `PEER_CMD`, `PEER_MODE`.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, skip the Outside Voice pass.
3. **Resume or create.**
   - **`--resume <plan-path>`** (explicit) — load the named plan; preserve its `plan_id`, `plan_type`, `created`, `generator` (if present); apply the rest of the planning flow (research, questions, U-IDs, peer review) to flesh it out. Used to promote auto-generated draft plans (from `/en-sweep`'s continuous monitoring) into full peer-reviewed plans. Status remains `draft` until step 11; only the user can flip to `open`.
   - **`--from-legacy <path>`** (explicit) — read content from a legacy plan (typically `docs/plans/legacy/<file>.md` archived during `/en-setup` retrofit). The legacy file is **not modified** and **not moved**; this flag uses it as input to mint a *new* Ensemble plan. Steps:
     - Read the legacy file's full content (no frontmatter assumed; treat all of it as narrative).
     - Pass it to the user as initial context; ask: *"Migrate this legacy plan into Ensemble. I'll run the normal plan flow (research → questions → U-IDs → peer review). The legacy file stays in `docs/plans/legacy/` untouched. Confirm? (y/n)"*.
     - On `y`, treat the legacy content as the **rough description** input (per step 4) and proceed normally — agent runs research, asks planning questions, breaks into U-IDs, mints a fresh `<PREFIX><NN>` ID, writes a new plan in `docs/plans/active/`.
     - The new plan's frontmatter carries `migrated_from: docs/plans/legacy/<file>.md` for traceability. The legacy README's "list of archived files" gets a back-reference: *"Migrated to <new plan path> on <date>."* (handled in step 12).
     - Use this to bring meaningful legacy plans into the active flow with proper R-ID/U-ID assignment and peer review — never an in-place auto-conversion.
   - **Auto-resume** (heuristic) — if a plan in `docs/plans/active/` already matches the user's request by title or `related_design`, offer to resume rather than create a new one.
   - **Create** — no match; mint a new plan.
4. **Source the request.** Identify input:
   - Brainstorm design doc (`docs/designs/*.md`) — pre-explored, recommendation already on the table.
   - `docs/foundation.md` — pulling a requirement (R-ID) for the next slice of work.
   - Direct rough description from the user.
   - Bug report or tracked debt item (`Resolves: TD<N>`).

   **Infer `plan_type`** from the request — `feature` (net-new behavior), `improvement` (refactor / perf / DX work, including TD), or `bug` (fix). Default `feature` when unclear; confirm with the user when the request is ambiguous.
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
   - **Risk:** `low | medium | high | destructive`. Drives `/en-build` phase placement and safety gates. Ask if unclear; default `medium` only when the unit is genuinely additive and reversible. Mark `destructive` for any DROP TABLE / DROP SCHEMA / mass DELETE / TRUNCATE / recursive removal of persistent data.
   - **Category:** one of `feature | observability | diagnostics | api-additive | migration-additive | migration | backfill | schema-evolution | deletion | drop | removal | other`. Metadata only; does not override `risk:`.
   - **Reversibility:** `trivial | reversible | rollback-required | irreversible`. Informational; helps the user judge risk.
   - **Gated:** `true | false`. Default `false`. Set `true` for admin endpoint deploys, customer-facing flag flips, third-party API calls with rate-limit risk, or any non-destructive unit that needs explicit confirmation before running.
   - **Execution note:** `test-first` / `characterization-first` / `pragmatic`.
   - **Patterns to follow:** citations to `docs/learnings/patterns/` if relevant.
   - **Test scenarios:** explicit list.
   - **Verification:** what counts as done (tests passing, lint clean, manual check).
   - **Resolves (optional):** `TD<N>` IDs from `docs/plans/tech-debt-tracker.md`.

   **Phase invariant check.** For every dependency edge `U → V` (U depends on V), verify `risk(V) <= risk(U)` in the order `low < medium < high < destructive`. A low-risk unit depending on a higher-risk unit is a structural error — `/en-build`'s phase loop refuses to run such plans. Surface and resolve before writing the plan: either remove the dependency, promote `U`'s `risk:`, or split `U` into a part that doesn't depend on the higher-risk unit.
10. **Resolve `plan_id_prefix`.** Read `plan_id_prefix:` from `docs/foundation.md` frontmatter. If absent (older project, retrofit, or `/en-foundation` not yet run), default to `FR`. Plans inherit the prefix in force at the time they are minted; the prefix is part of the plan's stable ID and never rewritten.
11. **Auto-increment plan number.** Scan `docs/plans/active/` and `docs/plans/completed/` for the highest existing plan number under the *current* `plan_id_prefix`. Legacy `FR` plans count toward `FR`'s numbering only; a new `EN` project starts at `EN01` even if `FR99` already exists. Zero-pad to 2 digits (3 once `99` is reached).
12. **Write to `docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md`** using `references/templates/plan-template.md`. Filename example: `EN03-improvement_dashboard-overview.md`. Substitute fields including `plan_id` (`<PREFIX><NN>`), `plan_type`, and `data_scale` (default `small`). Initialize `peer_review_iterations: 0` and `peer_review_resolutions: []`. Status starts as `draft`; the **finalize loop** in step 13 may flip to `open` automatically.
13. **Outside Voice review with finalize loop.** If `PEER_AVAILABLE=true` (and `--no-peer` not set):
    - Build the prompt by shelling out to `bin/ensemble-build-peer-prompt --artifact-type plan --project-context "<one-line>" --goal "<one-line>" --artifact-file <plan-path> --peer-mode "$PEER_MODE"` — the helper substitutes the plan-specific review-dimensions block and the single-agent fallback note for you. Do NOT assemble the prompt by reasoning; that's slow and produces drift from the canonical template in `references/outside-voice.md`.
    - Set `ENSEMBLE_PEER_REVIEW=true`.
    - Invoke `$PEER_CMD $PEER_FORMAT --max-turns 1` with the prompt.
    - Parse JSON per `references/finding-schema.md`. Mint `finding_id` as `<iteration>-<index>` for any finding the peer didn't supply one for.
    - Update frontmatter: `peer_review_verdict`, `peer_review_iterations` (+1), `peer_review_last_run` (ISO 8601 date).
    - **Re-review loop** (the finalize loop):
      - On `verdict: approve` → exit the loop. Proceed to step 14 (status flip).
      - On `verdict: revise` → walk findings, apply / defer / disagree per `references/severity.md`. Write each as a structured entry to `peer_review_resolutions:` with `finding_id`, `iteration`, `severity`, `title`, `status` (`applied | deferred | disagreed | superseded`), `rationale` (required for non-`applied`), and `location`. Update the human-readable iteration log narrative to match. Then **re-invoke the peer** with a `## Previous review context` section: assemble the section into a tempfile from `peer_review_resolutions:` (NEVER from the iteration-log prose) and pass it as `--iteration-context-file <path>` to `bin/ensemble-build-peer-prompt`. Continue looping until `approve` or the depth-aware iteration cap is hit.
        - **Iteration cap (depth-aware):** Lightweight = 1, Standard = 2, Deep = 2. `--max-iterations <N>` overrides. `--no-reloop` runs the initial pass only and never re-invokes.
        - **Cap-hit behavior:** Surface the latest findings; ask the user "accept as-is and flip to `open`, or stay in `draft`?". User keeps control.
        - **Same-finding-twice suppression:** If a finding the user disagreed with re-appears on the next pass, append it to a "do not re-flag" list in the next prompt. If it appears a third time despite suppression, treat the cap as hit early.
      - On `verdict: reject` → pause, surface to user, leave `status: draft`. Do not re-loop.
      - **Failure handling:** Peer timeout → surface, leave `status: draft`, no re-loop. Malformed JSON after one retry → same behavior.
14. **Promote to `open` (status flip).** The plan moves from `status: draft` to `status: open` in **every** path that produces a buildable plan, not just peer-approve. Specifically, flip to `open` when any of these is true:
    - Peer ran and the loop exited with `verdict: approve`.
    - `--no-peer` was passed (peer was deliberately skipped).
    - `PEER_AVAILABLE=false` from host detection (peer unavailable; no flag needed).
    - Peer was auto-skipped under `skip_peer_below_lines` (plan < 50 lines) or `skip_peer_on_lightweight: true` (Lightweight depth).
    - Loop hit the iteration cap with `verdict: revise` AND the user chose "accept as-is" at the cap-hit prompt (per failure protocol).
    - Peer returned `verdict: reject` AND the user explicitly overrode the rejection (per failure protocol).

    On promotion: compute `peer_review_plan_hash` (sha256 over canonicalized immutable plan-input fields — see `references/templates/plan-template.md` lifecycle and the scope-aware-slicing spec for the exact field list), write it to frontmatter alongside `peer_review_verdict`, and flip `status: draft → open`. The file stays in `active/` (the directory; not to be confused with status — there is no `status: active` value).

    The plan stays in `status: draft` ONLY when:
    - Peer returned `verdict: reject` AND the user did NOT override.
    - Peer subprocess timed out or returned malformed JSON (after one retry) AND the user has not yet decided.

    In those `draft`-stuck cases, do not advance to step 15 (commit) or step 18 (hand-off to `/en-build`); surface state and stop. `/en-build`'s pre-flight will offer the recovery path on the next attempt if findings get resolved later.
15. **Auto-commit the plan file.**
    - Branch policy: commit on the current branch (default `main` / `master` / `develop`, or whatever feature branch the user is on). Skip auto-commit on detached HEAD or unusual states; surface and ask.
    - Working-tree safety: refuse auto-commit if `git diff --cached` has unrelated staged changes; surface and ask the user to commit the plan manually. Untracked or unstaged changes to *other* files are fine — `git add` is invoked with the plan file path only, never `git add -A`.
    - Commit message (HEREDOC):
      ```
      docs(plan): <plan_id> <slug> (<N> units)

      Plan finalized after <peer_review_iterations> peer-review iteration(s).
      Verdict: approve. Generated by /en-plan.
      ```
    - Does not push. Does not open a PR. `/en-ship` owns those.
    - Flags: `--no-commit` (skip), `--commit-branch <name>` (create/switch to `<name>` first).
16. **Confidence check.** Identify low-confidence sections (typically integrations or unfamiliar libraries); offer to deepen with a research dispatch or to leave as-is and resolve during build.
17. **Capture-from-synthesis reflex (D21).** If a non-obvious connection or pattern emerged during planning, soft-prompt to capture as a learning.
18. **Hand off to `/en-build`.** Suggest the build command:
    > "Plan written and finalized: `docs/plans/active/EN07-feature_auth-rotation.md` (5 units, status: open, committed as <commit-sha>). Ready to build with `/en-build docs/plans/active/EN07-feature_auth-rotation.md`?"

## Cross-review and finalize loop

**On by default.** Skip with `--no-peer`. Skipped automatically when:

- `PEER_AVAILABLE=false`.
- The plan has < 50 lines (`skip_peer_below_lines` config).
- Depth is Lightweight AND `skip_peer_on_lightweight: true`.

**Finalize loop:** when peer runs and returns `revise`, `/en-plan` applies findings (per `references/severity.md`), records them in `peer_review_resolutions:`, and re-invokes the peer with the previous-review-context section (per `references/outside-voice.md`). The loop continues until `approve` or the depth-aware iteration cap is hit. Cap defaults: Lightweight = 1, Standard = 2, Deep = 2 (so total peer passes are 2 / 3 / 3 including the initial). Override with `--max-iterations <N>`; disable looping entirely with `--no-reloop`.

When the loop exits with `approve` (or `--no-peer` was used), `/en-plan` computes `peer_review_plan_hash`, flips `status: draft → open`, and auto-commits the plan file (per step 15).

## Flags

| Flag | Effect |
|---|---|
| `--no-peer` | Skip peer review entirely. Plan is left at `status: open` with `peer_review_verdict: null` (legacy/no-peer mode). |
| `--no-reloop` | Run the initial peer pass only; never re-invoke. (Pre-finalize-loop behavior.) |
| `--max-iterations <N>` | Override the depth-aware iteration cap. |
| `--no-commit` | Finalize (`status: open`) but do not auto-commit the plan file. |
| `--commit-branch <name>` | Create/switch to `<name>` before committing the plan file. |
| `--resume <plan-path>` | See process step 3. |
| `--from-legacy <path>` | See process step 3. |

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

The reported path is the file actually written this run — substitute the resolved `<PREFIX><NN>` and `<plan_type>_<slug>` values, not the literal example below. Example output for an `EN`-prefixed project planning an auth-rotation feature:

```
Plan: docs/plans/active/EN07-feature_auth-rotation.md (5 units, 380 lines)

Units:
  - U1: Add singleFlight<K, V> helper (test-first)
  - U2: Wire Redis connection (pragmatic)
  - U3: Wrap rotateRefreshToken in singleFlight (test-first)  ← critical path
  - U4: Migration for refresh_token_rotated_at column (characterization-first)
  - U5: Update tests covering AE2, AE3 (test-first)

Peer review: cross-agent (codex). Verdict: revise. Applied 2 of 3 findings (1 deferred to TD8).

Next: /en-build docs/plans/active/EN07-feature_auth-rotation.md
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
| Peer rejects the plan (verdict: reject) | Pause and surface the reject reason; leave `status: draft`. If the user explicitly overrides the rejection ("proceed anyway"), treat as approved: run step 14 (compute hash, flip `status: draft → open`, write `peer_review_verdict: reject` + a `peer_review_overridden: true` marker for audit) and continue to step 15 (auto-commit). The valid post-flip status is **`open`** — `active/` is the directory the file lives in, not a status value. |
| Finalize loop hits iteration cap with `verdict: revise` | Surface latest findings; ask user "accept as-is and flip to `open`, or stay in `draft`?". User keeps control. |
| Re-review surfaces a finding the user previously disagreed with | Append finding to "do not re-flag" list in the next prompt. If it appears a third time despite suppression, treat the cap as hit early. |
| Auto-commit refused due to unrelated staged changes | Surface and skip the commit step; user finalizes manually. Plan still flips to `open`; just isn't tracked yet. `/en-build` pre-flight will offer auto-commit on next attempt. |
| Plan structure violates phase invariant (low-risk depends on higher-risk) | Refuse to write. Surface the offending dependency and the three remediation options (remove dependency / promote risk / split unit). |
| FRXX collision (race condition) | Re-scan; increment; retry. Lint will catch if it actually slips through |
