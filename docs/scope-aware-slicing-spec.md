---
title: Scope-aware slicing for /en-build — spec
status: draft
owner: mano
related:
  - skills/en-build/SKILL.md
  - skills/en-plan/SKILL.md
  - references/severity.md
  - references/templates/plan-template.md
  - docs/plan-finalize-loop-spec.md
---

# Scope-aware slicing for `/en-build`

## Problem

`/en-build` runs a plan unit-by-unit in dependency order until done. For a
15-unit deep plan with migrations, a 654k-row backfill, and a 6.5 GB
destructive delete (the Emble run), this means hours of compounding blast
radius with no built-in pause point. The `/en-build` agent's recommendation
to "narrow slice with `--unit U1`" leaned on the user to pick the slice; the
skill itself has no model of *which* slices are safer to land first.

This spec adds **phasing**: an automatic risk-class grouping that sits above
the existing dependency batches, with per-phase pauses by default. Plans that
don't trigger phasing keep today's behavior exactly.

This is **Improvement #4** from the workflow analysis. Improvements #1–#3 are
in [docs/plan-finalize-loop-spec.md](plan-finalize-loop-spec.md) and assumed
landed first.

---

## Resilience principles

Five contracts that govern the design:

1. **Phasing never reorders units.** Dependency order is preserved within
   and across phases. If U6 depends on U3, U6 lands in the same phase as U3
   or a later one — never earlier.
2. **A phase boundary is a clean commit boundary.** Every phase ends with a
   green test suite, lint, typecheck. Resume from a phase boundary is
   deterministic.
3. **No phase straddles a destructive op.** Once a Phase 4 unit lands, no
   later unit in the same phase can be additive — Phase 4 is destructive-only.
4. **Auto-roll is the default; pausing is opt-in — except where it's
   forced.** `/en-build` rolls through phases continuously by default.
   `--pause` opts into per-phase confirmation. P4 (Destructive) and any
   unit flagged `gated: true` ALWAYS pause and require explicit
   confirmation, regardless of flags. The skill never silently runs through
   destructive or gated work.
5. **Backward compat for plans without risk metadata.** Plans drafted before
   this spec lands fall back to inference; existing `--unit` / `--from`
   flags still work and bypass phasing.

---

## Detection — when does phasing fire?

After plan load (en-build step 4), the skill computes a `phasing_required`
boolean from these triggers:

| Trigger | Threshold | Source |
|---|---|---|
| Unit count | `>= 8` units | plan frontmatter / U-ID count |
| Depth | `depth: deep` | plan frontmatter |
| Any unit with `risk: destructive` | `>= 1` | per-unit metadata |
| Any unit with `risk: high` | `>= 2` | per-unit metadata |
| Migrations | `>= 2` units flagged `category: migration` | per-unit metadata |
| Data scale flag | `data_scale: large` (subjective; set in plan) | plan frontmatter |

**Any single trigger turns phasing on.** Below all thresholds → phasing off,
today's behavior.

User overrides:
- `--no-phasing` → force off, even if triggers fire.
- `--phasing` → force on, even if triggers don't fire.
- `--unit U<N>` / `--from U<N>` → bypass phasing entirely; build only what's
  asked.

---

## Phase classification

Four phases, in fixed order. Units are assigned by risk class + category.

| Phase | Name | Contains | Reversibility |
|---|---|---|---|
| **P1** | Measurement | `risk: low`, `category: observability\|diagnostics\|read-only` | Trivial |
| **P2** | Additive | `risk: low\|medium`, `category: feature\|api-additive\|migration-additive` | Reversible with revert |
| **P3** | Migration / Backfill | `risk: medium\|high`, `category: migration\|backfill\|schema-evolution` | Reversible only with explicit rollback |
| **P4** | Destructive | `risk: destructive`, `category: deletion\|drop\|removal` | Effectively irreversible |

### Risk-class metadata (additive to plan template)

Add to each unit in the plan template:

```yaml
- id: U6
  goal: ...
  risk: low | medium | high | destructive   # required for new plans
  category: feature | observability | diagnostics | api-additive |
            migration-additive | migration | backfill | schema-evolution |
            deletion | drop | removal | other
  reversibility: trivial | reversible | rollback-required | irreversible
```

`risk` is the single source of truth for phase placement. `category` is
descriptive (used in summaries and inference). `reversibility` is informational.

### Inference fallback (for plans without `risk:`)

Plans drafted before #4 lands have no `risk:` field. Fallback rules, applied
to each unit:

1. Files contain `migrations/` or `alembic/` AND approach mentions DROP /
   ALTER COLUMN / DELETE FROM → `risk: high`, `category: migration`.
2. Files contain `migrations/` AND approach is purely additive (CREATE TABLE,
   ADD COLUMN with default) → `risk: medium`, `category: migration-additive`.
3. Approach mentions DROP TABLE, DROP SCHEMA, mass DELETE without WHERE,
   `truncate`, `rm -rf` of data dirs → `risk: destructive`, `category:
   deletion`.
4. Files are entirely under `tests/`, `docs/`, or observability paths
   (configurable per project) → `risk: low`, `category: observability`.
5. Default → `risk: medium`, `category: feature`.

When inference fires, surface a notice before phasing:

> Plan has no `risk:` metadata. Inferred classification:
> P1 (3), P2 (5), P3 (2), P4 (1). Review before continuing? (y/n)

### Cycle / dependency-respecting placement

Algorithm:

1. Compute each unit's `min_phase` = the phase its risk class maps to.
2. For each unit U with `Depends: V`, set `U.min_phase = max(U.min_phase,
   V.min_phase)`. (A unit can never land before its dependencies.)
3. Iterate to a fixed point.
4. Result: each unit is assigned to its lowest legal phase.

If the algorithm pushes a unit into a higher-risk phase than its own risk
class warrants (e.g. a low-risk unit depends on a destructive one), surface
the issue:

> U12 (risk: low) depends on U10 (risk: destructive). U12 will land in P4.
> If U12 should run earlier, restructure to remove the dependency.

This is rare in practice but a real planning bug — flag it loudly.

### Empty phases

Collapsed silently. A plan with only P2 + P4 units shows the two phases, not
"P1 (empty), P2, P3 (empty), P4."

---

## Execution flow

After phase classification, `/en-build` step 9 (per-unit loop) is wrapped:

```
for each phase in [P1, P2, P3, P4]:
    if phase is empty: continue

    surface phase plan to user (units, files, risk summary)

    # Mandatory gates (cannot be bypassed by any flag):
    if phase == P4:
        require literal-string confirmation: "run phase 4"
    if --strict-destructive AND phase == P3:
        require literal-string confirmation: "run phase 3"

    # Opt-in per-phase pause (--pause flag):
    if --pause AND not already-confirmed-above:
        ask y/pause/n

    for each unit in phase (dependency order, today's loop):
        # Per-unit mandatory gate:
        if unit.gated == true:
            require explicit confirmation incl. unit summary

        run today's flow (steps 8a–8j)
        if any unit fails irrecoverably:
            stop phase; surface state; do not advance to next phase

    after-phase verification:
        full project test suite (not just per-unit)
        lint, typecheck
        if any fails: stop; surface; do not advance

    surface phase summary (units, commits, peer findings, simplifier changes)

    if not last phase AND --pause:
        ask y/pause/n for next phase
    # Default: roll into next phase without prompt.
```

### Per-phase pause prompt (only with `--pause`)

By default, `/en-build` rolls into the next phase without prompting. With
`--pause`, after each phase the user sees:

```
Phase 1 (Measurement) complete — 3 units, 5 commits.
  ✓ U1: pg_stat_statements wiring
  ✓ U2: Neon API diagnostic helper
  ✓ U15: Sentry alert config

Test suite: 247 passing. Lint: clean. Typecheck: clean.

Next: Phase 2 (Additive) — 4 units (U3, U4, U5, U7).
  Files: backend/scheduler.py, backend/admin/routes.py, ...
  Continue, pause, or stop? (y/pause/n)
```

### Phase 4 confirmation prompt (mandatory; cannot be bypassed)

```
Phase 4 (Destructive) — IRREVERSIBLE OPERATIONS.
  • U8: Delete tenant `acme-test-3` data (~6.5 GB, 654k rows)
  • U10: DROP control-plane DLT schema

This phase is not auto-rollable. Once these units commit, the operations
are effectively permanent.

Type 'run phase 4' to proceed, or anything else to stop:
```

The literal string `run phase 4` is required (not just `y`). No flag — not
`--auto`, not absence of `--pause` — bypasses this. `--strict-destructive`
extends the same literal-string requirement to Phase 3.

### Per-unit gated confirmation (mandatory; cannot be bypassed)

Any unit with `gated: true` in its plan metadata pauses before running,
regardless of phase or flags. Authors mark units as gated when manual
verification is required even though the unit isn't destructive — examples:
admin endpoint deployments, customer-facing flag flips, third-party API
calls with rate-limit risk.

```
Unit U7 is GATED — manual confirmation required before running.
  Goal: Enable scheduler job in production via admin endpoint
  Files: backend/admin/scheduler.py
  Approach: POST /admin/scheduler/enable

Continue with U7? (y/skip/abort)
```

`skip` advances to the next unit (recording a skipped status); `abort` ends
the build at this point.

### Resume semantics

`/en-build --from-phase P<N>` resumes at the start of phase N. Pre-flight:

1. Verify previous phases' commits are present on the current branch.
2. Verify working tree is clean.
3. Verify all units in earlier phases have `status: completed` in the
   plan's iteration log (added by step 8j today).
4. If any check fails → refuse with the specific reason.

`--from U<N>` continues to work as today (skips phase grouping; runs from
that unit onward in dependency order).

---

## Resilience — failure modes

| Failure | Behavior |
|---|---|
| Unit fails verification gate 1 (mid-phase) | Today's behavior: pause; ask retry/skip/abort. Phase does not advance. |
| Unit fails verification gate 2 (simplifier broke it) | Revert simplifier; continue with original (today's behavior). |
| After-phase full test suite fails | Stop. Do **not** advance to next phase. Surface failing tests; offer: investigate / commit-as-WIP / abort. |
| Peer subprocess timeout on a unit | Today's behavior: log; continue or fail per `--no-peer-per-unit`. Doesn't break phasing. |
| User Ctrl-C mid-phase | Commit progress on a `wip/<plan_id>-phase<N>` branch; surface state; phase incomplete. |
| Plan file modified during build | Detected via hash check at phase boundary. Surface; refuse to advance. (Aligns with finalize-loop spec's deferred hand-edit detection — different surface, same root protection.) |
| Branch state diverged (e.g. user committed mid-build) | At phase boundary: detect; surface; require user to clean up before resume. |
| Worker dispatch returns malformed diff | Today's behavior: retry once; on second failure, ask user. Doesn't break phasing. |
| Inference produces wrong risk class | User can override interactively when notice surfaces (see Inference fallback). Or pass `--no-phasing`. |

### Working-tree contract across phases

Between phases, the working tree MUST be:
- Clean (no uncommitted changes).
- On the expected feature branch.
- Up to the previous phase's last commit.

If any check fails, refuse to start the next phase. This makes resume
deterministic — `--from-phase P3` always knows what state it's looking at.

### Recursion guard

`ENSEMBLE_PEER_REVIEW=true` continues to suppress peer subprocess calls per
today. Phasing is independent — peer review still runs per unit (subject to
existing flags) within each phase.

### Worktree mode (`--worktree`)

Phasing works inside the worktree exactly as in-place. The worktree is
created once at the start of the build; phases commit into it; the user
inspects / merges / discards the worktree at the end.

---

## Backwards compatibility

| Existing behavior | After #4 |
|---|---|
| Small plan (e.g. 3 units, depth: lightweight) | Phasing off; runs as today |
| `/en-build --unit U5` | Bypasses phasing; runs only U5 |
| `/en-build --from U3` | Bypasses phasing; runs U3 onward in dependency order |
| `/en-build --dry-run` | Shows phase plan + per-unit plan; doesn't write |
| Plan without `risk:` metadata | Inference + user confirmation before phasing |
| `/en-build` on a phasing-triggered plan | Rolls through P1 → P2 → P3 continuously; pauses mandatorily before P4 and before any `gated: true` unit |
| `/en-build --pause` on the same plan | Prompts y/pause/n between every phase boundary |
| `--no-peer-per-unit` | Unchanged; works inside phasing |
| `--worktree` | Unchanged; works inside phasing |

### New flags

| Flag | Effect |
|---|---|
| `--no-phasing` | Force phasing off |
| `--phasing` | Force phasing on (even if triggers don't fire) |
| `--from-phase P<N>` | Resume at phase N |
| `--pause` | Pause and prompt between phases (default is auto-roll). Mandatory P4 / gated-unit confirmations always fire regardless of this flag. |
| `--strict-destructive` | Extend the literal-string confirmation requirement to P3 in addition to P4 |

---

## Plan template additions

The plan template (`references/templates/plan-template.md`) gains:

**Per unit:**
```yaml
risk: low | medium | high | destructive
category: feature | observability | diagnostics | api-additive |
          migration-additive | migration | backfill | schema-evolution |
          deletion | drop | removal | other
reversibility: trivial | reversible | rollback-required | irreversible
gated: true | false                       # default false; true = mandatory pause before running
```

**Plan-level (frontmatter, optional):**
```yaml
data_scale: small | medium | large    # subjective; trips a phasing trigger when "large"
```

`/en-plan` prompts for `risk:` per unit when drafting (one-line addition to
the per-unit metadata loop in step 9). Defaults to `medium` if user skips.

---

## Decisions (locked from #4 conversation)

1. **Default execution mode = auto-roll.** `/en-build` rolls through phases
   continuously by default. `--pause` opts into per-phase confirmation
   prompts. **Mandatory pauses that no flag can bypass:**
   - Phase 4 (Destructive) — literal-string confirmation `"run phase 4"`.
   - Any unit with `gated: true` — explicit y/skip/abort confirmation.
   - Phase 3 (Migration) when `--strict-destructive` is set — literal-string
     `"run phase 3"`.

2. **Strict variant** = `--strict-destructive` flag, not the default.
   Default is the in-flow P4 literal-string prompt. Users who want the
   "P4 must be a separate `/en-build` invocation" model use
   `--strict-destructive` plus `--from-phase P4` as two commands.

3. **Risk metadata** = required field on new plans (`risk:`); inference
   fallback for older plans, with user-confirmation surface.

4. **Migration granularity** = split by reversibility. Additive migration
   → P2; destructive migration → P3 or P4 depending on operation.

5. **Phase 4 confirmation literal** = `"run phase 4"` (typed verbatim).
   Same pattern for P3 under `--strict-destructive` (`"run phase 3"`).

6. **Auto-merge at phase boundaries** = out of scope. Belongs to `/en-ship`.

7. **Peer review cross-checks risk classification.** The `/en-plan` peer
   prompt explicitly asks the peer to flag obvious miscategorizations
   (e.g. a `DROP TABLE` unit marked `risk: low`, or a unit touching admin
   endpoints not flagged `gated: true`). One-line addition to
   `references/outside-voice.md`'s plan-review template.

8. **After-phase verification = project default test suite.** Whatever
   `npm test` / `pytest` / project-default runs at the post-build full-suite
   step today. Heavy end-to-end is opt-in via a future `--phase-e2e` flag if
   the need shows up.

9. **Phase commit-message trailer.** Append `phase: P<N>` to the trailer of
   each unit's commit (e.g. `phase: P3`). Helps `git log --grep`,
   `/en-ship` PR summaries, and `--from-phase` resume validation.

10. **Gated units** = new per-unit boolean field. Any unit with `gated: true`
    pauses before running, regardless of phase, regardless of flags. Authors
    mark gated when manual verification is required even though the unit
    isn't destructive (admin endpoints, flag flips, rate-limited APIs).

---

## Implementation outline

Roughly 8–10 units, Standard depth:

- **U1** — Plan template: add `risk`, `category`, `reversibility`, `gated`
  fields per unit; add `data_scale` to plan frontmatter.
- **U2** — `/en-plan` step 9: prompt for `risk:` and `gated:` per unit during
  drafting; default `medium` / `false` on skip.
- **U3** — `/en-plan` peer-review prompt: extend `references/outside-voice.md`
  to ask the peer to flag risk-classification mistakes and missing `gated`
  flags on sensitive units.
- **U4** — `/en-build` step 4 extension: detect `phasing_required` from
  triggers; surface phase classification.
- **U5** — Phase-classification algorithm: risk-class → phase mapping +
  dependency-respecting placement + inference fallback for legacy plans.
- **U6** — Phase loop wrapping today's per-unit loop: mandatory P4 / gated
  prompts, opt-in `--pause` per-phase prompts, after-phase verification with
  project-default test suite.
- **U7** — Per-unit gated-confirmation handler (mandatory, regardless of
  phase or flags).
- **U8** — `--from-phase`, `--no-phasing`, `--phasing`, `--pause`,
  `--strict-destructive` flag handling. Default is auto-roll.
- **U9** — Resume semantics + working-tree contract checks at phase
  boundaries; commit-message trailer (`phase: P<N>`).
- **U10** — Tests in `tests/en-build/` covering: phasing-off path, each
  trigger, inference fallback, P4 literal-string confirmation, gated-unit
  pause, `--pause` opt-in path, resume from each phase, failure recovery
  between phases.

Final: update `docs/workflow-and-catalog.md` with the phasing lifecycle.
