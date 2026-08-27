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
   `--pause` opts into per-phase confirmation. **Universal safety gates**
   (every `risk: destructive` unit and every `gated: true` unit) ALWAYS
   require explicit confirmation, regardless of flags, regardless of
   whether phasing is on, and regardless of whether the unit is being run
   as part of a phase or via `--unit` / `--from`. The skill never silently
   runs through destructive or gated work on any code path.
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

**Phase placement is determined solely by `risk:`.** Risk class → phase
mapping is fixed (`destructive` → P4, `high` → P3, `medium` → P2 or P3
depending on `category` only when `risk` is `medium` AND `category in
{migration, backfill, schema-evolution}` (those sit in P3); all other
`medium` → P2; `low` → P1 if `category in {observability, diagnostics,
read-only}`, else P2). `category` carries no other authority over phase
placement; it's metadata for human readability and ordered classification
inputs. `reversibility` is informational only.

### Inference fallback (for plans without `risk:`)

Plans drafted before #4 lands have no `risk:` field. Inference is a **single
ordered classifier** — rules are evaluated top-to-bottom, **first match
wins**, no backtracking:

1. **Destructive patterns** (highest priority). Approach mentions any of:
   `DROP TABLE`, `DROP SCHEMA`, `DROP DATABASE`, mass `DELETE` without a
   `WHERE` clause, `TRUNCATE`, `rm -rf` against data dirs, `aws s3 rm
   --recursive`, `kubectl delete` against persistent resources, `terraform
   destroy` → `risk: destructive`, `category: deletion`.
2. **Destructive migrations**. Files under `migrations/` or `alembic/` AND
   approach mentions `ALTER COLUMN` (drop/rename/type-change), `DROP
   COLUMN`, `DROP INDEX` on a populated index, or destructive data
   transforms → `risk: high`, `category: migration`.
3. **Additive migrations**. Files under `migrations/` or `alembic/` AND
   approach is purely additive (`CREATE TABLE`, `ADD COLUMN` with default,
   `CREATE INDEX CONCURRENTLY`) → `risk: medium`, `category:
   migration-additive`.
4. **Backfill**. Approach mentions iterating existing rows (`UPDATE` with
   batch loop, ETL backfill script) → `risk: high`, `category: backfill`.
5. **Observability / read-only**. Files entirely under `tests/`, `docs/`,
   or configured observability paths → `risk: low`, `category:
   observability`.
6. **Fallback**. None of the above → `risk: medium`, `category: feature`.

The destructive rule fires first deliberately — a unit that *both* lives
under `migrations/` *and* contains `DROP TABLE` is destructive, not "just"
a migration.

When inference fires, surface a notice before phasing:

> Plan has no `risk:` metadata. Inferred classification:
> P1 (3), P2 (5), P3 (2), P4 (1). Review before continuing? (y/n)

### Cycle / dependency-respecting placement

The placement algorithm is constrained by two invariants that must hold
together:

- **(A)** A unit cannot land before any unit it depends on.
- **(B)** A phase contains only units of its own risk class. P4 is
  destructive-only; P3 is migration / backfill / high-risk only; P2 is
  additive / medium only; P1 is measurement / low only.

Algorithm:

1. Compute each unit's natural phase `nat_phase(U)` from its `risk:` (and
   `category` for the medium-vs-P3 carve-out, per the rules above).
2. For each dependency edge `U → V` (U depends on V), check
   `nat_phase(V) <= nat_phase(U)`. If yes, the edge is satisfiable.
3. **If any edge has `nat_phase(V) > nat_phase(U)`** — i.e. a low-risk
   unit depends on a higher-risk unit — the plan is **rejected as a
   planning error**. `/en-build` does **not** silently push U into V's
   phase; doing so would violate invariant (B) (e.g. burying a low-risk
   unit in P4 makes P4 no longer destructive-only and lets it land
   *after* a `"run phase 4"` confirmation that the user typed for
   destructive work, not for that low-risk unit).

Rejection message:

> Plan structure violates phase invariants:
> - U12 (risk: low) depends on U10 (risk: destructive).
>   U12 cannot land in P1 (its natural phase) without U10 already complete,
>   but P4 must be destructive-only.
>
> Restructure options:
> - Remove the dependency if U12 doesn't actually need U10.
> - Promote U12's `risk:` if it really must run alongside destructive work.
> - Split U12 into a part that doesn't depend on U10 and a follow-up.
>
> Re-run `/en-plan` or hand-edit and re-run `/en-build`.

This is the same severity as a unit declaring `Depends: U99` where U99
doesn't exist — a structural plan bug, surfaced loudly, no auto-fix.

### Empty phases

Collapsed silently. A plan with only P2 + P4 units shows the two phases, not
"P1 (empty), P2, P3 (empty), P4."

---

## Universal safety gates (apply on every code path)

Safety gates are decoupled from phase grouping. They run on **every** path
that executes a unit — phasing on, phasing off, `--unit U<N>`, `--from
U<N>`, `--no-phasing`, `--from-phase`, manual interactive resume — without
exception. The phase loop layers *on top*; it does not replace these.

For every unit selected for execution, `/en-build` performs unit
classification (using the unit's `risk:` field, falling back to the
ordered inference classifier) and then enforces:

| Classification | Gate (cannot be bypassed by any flag) |
|---|---|
| `risk: destructive` | Literal-string confirmation `"run unit U<N>"` typed verbatim, with the unit's goal, files, and approach surfaced first. |
| `gated: true` | y/skip/abort confirmation, with the unit's goal and approach surfaced first. |
| `risk: high` AND `--strict-destructive` | Literal-string confirmation `"run unit U<N>"`. |
| Anything else | No mandatory gate at the unit level. |

**This is the primary safety boundary.** The phase-level prompts (P4
`"run phase 4"`, optional `--pause` between phases) are conveniences that
group multiple units' confirmations into one when phasing is active. With
phasing on, accepting `"run phase 4"` covers every destructive unit in the
phase; `/en-build` does not re-prompt per unit. With phasing off (or
`--unit U<N>` selecting a destructive unit alone), the unit-level gate
fires instead. **No code path skips the unit-level classification check.**

There is no flag that disables the safety gates. `--no-phasing` disables
phase grouping but never the gates. `--unit` and `--from` change which
units run but never which gates apply to them.

## Execution flow

After phase classification, `/en-build` step 9 (per-unit loop) is wrapped:

```
# Phasing-on path:
for each phase in [P1, P2, P3, P4]:
    if phase is empty: continue

    surface phase plan to user (units, files, risk summary)

    # Phase-level mandatory gates (group-confirm destructive work):
    if phase == P4:
        require literal-string confirmation: "run phase 4"
        # Accepting this covers all destructive units in the phase;
        # per-unit destructive gates are NOT re-prompted within P4.
    if --strict-destructive AND phase == P3:
        require literal-string confirmation: "run phase 3"

    # Opt-in per-phase pause (--pause flag):
    if --pause AND not already-confirmed-above:
        ask y/pause/n

    for each unit in phase (dependency order, today's loop):
        # Universal safety gates — fire whenever the corresponding
        # phase-level gate did NOT cover this unit:
        if unit.gated == true:
            require explicit y/skip/abort confirmation
        if unit.risk == "destructive" AND not (phase == P4 already-confirmed):
            require literal-string "run unit U<N>"
        if unit.risk == "high" AND --strict-destructive
                AND not (phase == P3 already-confirmed):
            require literal-string "run unit U<N>"

        run today's flow (steps 8a–8j)
        if any unit fails irrecoverably:
            stop phase; surface state; do not advance to next phase

# Phasing-off path (--no-phasing, --unit, --from, single-unit plans):
for each unit in selected_units (dependency order):
    # Universal safety gates ALWAYS fire on this path:
    classify(unit)  # uses risk: + inference fallback
    if unit.gated == true:
        require explicit y/skip/abort confirmation
    if unit.risk == "destructive":
        require literal-string "run unit U<N>"
    if unit.risk == "high" AND --strict-destructive:
        require literal-string "run unit U<N>"

    run today's flow (steps 8a–8j)

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
| User Ctrl-C mid-phase | **Stop cleanly. Do not auto-commit.** Surface: current branch, current unit (with completion state), dirty files, last successful commit. Provide explicit resume instructions (`/en-build --from U<N>` or `--from-phase P<M>`). If the user wants a WIP branch, they invoke a separate `/en-build --commit-wip` (new flag) or stash manually — `/en-build` itself never does signal-time git operations. |
| Plan file modified during build | Hash check at phase boundary. Hash covers **immutable plan-input fields only**: per-unit `goal`, `files`, `approach`, `risk`, `category`, `gated`, `Depends`, plus plan-level `depth`, `data_scale`. Mutable fields managed by `/en-build` itself (iteration log, per-unit `status`, `peer_review_resolutions`) are **excluded** from the hash. `bin/ensemble-plan-hash` is the single implementation of this canonicalization; `/en-plan` and `/en-build` both call it rather than re-deriving it from this paragraph. Baseline hash is recorded at build start in the plan's `peer_review_plan_hash` frontmatter (added by `/en-plan` per finalize-loop spec); `/en-build` re-computes at each phase boundary and refuses to advance on mismatch. (Aligns with finalize-loop spec's deferred hand-edit detection — different surface, same root protection.) |
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
| `/en-build --unit U5` | Bypasses phasing; runs only U5. Safety gates apply if U5 is destructive or `gated: true`. |
| `/en-build --from U3` | Bypasses phasing; runs U3 onward in dependency order. Safety gates apply per unit. |
| `/en-build --dry-run` | Shows phase plan + per-unit plan; doesn't write |
| Plan without `risk:` metadata | Inference + user confirmation before phasing |
| `/en-build` on a phasing-triggered plan | Rolls through P1 → P2 → P3 continuously; pauses mandatorily before P4 and before any `gated: true` unit |
| `/en-build --pause` on the same plan | Prompts y/pause/n between every phase boundary |
| `--no-peer-per-unit` | Unchanged; works inside phasing |
| `--worktree` | Unchanged; works inside phasing |

### New flags

| Flag | Effect |
|---|---|
| `--no-phasing` | Force phasing off. Safety gates still fire per unit. |
| `--phasing` | Force phasing on (even if triggers don't fire) |
| `--from-phase P<N>` | Resume at phase N |
| `--pause` | Pause and prompt between phases (default is auto-roll). Mandatory destructive / gated-unit confirmations always fire regardless of this flag. |
| `--strict-destructive` | Add literal-string confirmation requirement for `risk: high` and Phase 3 (P4 / `risk: destructive` always require it). |

**No flag disables safety gates.** Every flag changes phasing or pacing;
none turn off the universal gates defined above.

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

11. **Universal safety gates are decoupled from phasing.** Destructive and
    gated-unit confirmations fire on every execution path — phasing on,
    phasing off, `--unit`, `--from`, manual resume. No flag disables them.
    Phase-level confirmations (`"run phase 4"`, `"run phase 3"` under
    `--strict-destructive`) are conveniences that *group* per-unit
    confirmations when phasing is active; they don't replace the
    per-unit gates on other code paths.

12. **Dependency-vs-phase conflicts reject the plan.** If a low-risk unit
    depends on a higher-risk unit, `/en-build` does not silently push the
    low-risk unit into the higher phase (which would violate the
    "phase contains only its own risk class" invariant). It refuses with
    a structural-error message and asks the user to restructure or
    promote the unit's `risk:`.

13. **Plan-hash drift detection covers immutable fields only.** The hash
    excludes the iteration log, per-unit `status`, and
    `peer_review_resolutions` — the fields `/en-build` itself updates.
    Baseline is captured at build start; mismatch at a phase boundary
    means an external edit to plan structure, which refuses advance.

14. **No signal-time git operations.** Ctrl-C surfaces state and resume
    instructions; it does not auto-commit, auto-stash, or auto-branch.
    WIP commits are user-initiated only.

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
- **U6** — **Universal safety-gate handler** (runs on EVERY execution path:
  phasing-on, phasing-off, `--unit`, `--from`, resume). Classifies the
  selected unit and enforces destructive / gated / `--strict-destructive`
  confirmations. This is the primary safety boundary.
- **U7** — Phase loop wrapping today's per-unit loop: phase-level
  group-confirm for P4, opt-in `--pause` per-phase prompts, after-phase
  verification with project-default test suite. Defers per-unit
  destructive prompts within P4 to U6 unless covered by the phase-level
  confirmation.
- **U8** — Dependency-vs-phase conflict detector: structural-error
  rejection with restructure guidance (no silent burying).
- **U9** — `--from-phase`, `--no-phasing`, `--phasing`, `--pause`,
  `--strict-destructive`, `--commit-wip` flag handling. Default is
  auto-roll. Verify no flag combination skips U6's gates.
- **U10** — Resume semantics + working-tree contract checks at phase
  boundaries; commit-message trailer (`phase: P<N>`); plan-hash baseline
  capture at build start; per-phase-boundary hash comparison limited to
  immutable fields.
- **U11** — Ctrl-C clean-stop handler: surface state + resume instructions;
  no signal-time git ops.
- **U12** — Tests in `tests/en-build/` covering: phasing-off path with
  destructive unit (gate must fire), `--unit U<destructive>` (gate must
  fire), each phasing trigger, ordered classifier (destructive-first wins
  over migration-pattern match), dependency-conflict rejection, P4
  group-confirm covering all P4 units, `--strict-destructive` extending
  to high-risk units, `--pause` opt-in path, resume from each phase,
  hash-drift detection on immutable fields only, Ctrl-C clean stop.

Final: update `docs/workflow-and-catalog.md` with the phasing lifecycle.
