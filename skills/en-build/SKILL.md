---
name: en-build
description: "Execute an implementation plan unit-by-unit on a feature branch. Picks build-by-orchestration (Claude host dispatches Codex worker) or build-handoff (Codex host with Claude peer reviewer) per host detection. Each unit: tests + lint → simplifier → re-verify → peer review → host applies → commit. Auto-invokes /en-learn at the end. Trigger phrases: 'build this plan', 'implement <plan_id>', 'start building', 'execute the plan'."
---

> **Helper resolution.** All `references/X` and `bin/Y` paths in this skill resolve relative to `$ENSEMBLE_ROOT` — the install root (skill at `$ENSEMBLE_ROOT/skills/<name>/`, shared helpers at `$ENSEMBLE_ROOT/{references,bin}/`). Compute once at start: `$ENSEMBLE_ROOT` env var if set; otherwise `$(realpath "$(dirname <this-SKILL.md>)/../..")`. Fail loudly if `$ENSEMBLE_ROOT/references/host-detect.md` does not resolve — that indicates a partial install (run `/en-setup` to repair).


# `/en-build`

Execute a plan, unit by unit, with cross-agent peer review at every per-unit gate. Two flavors based on host detection — both guarantee implementer ≠ reviewer.

> **Hard preconditions.** A plan in `docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md` (e.g. `EN03-improvement_dashboard-overview.md`; `<PREFIX>` from foundation's `plan_id_prefix`, default `FR`) with `status: open` (or `in_progress` when resuming), all U-IDs present, no unblocked dependencies. The skill verifies these at start. **Recoverable `status: draft`** (verdict `revise` with all findings resolved in `peer_review_resolutions:`) is offered a single finalize-and-build prompt instead of refused.

> **Universal safety gates** (apply on EVERY code path — phasing on/off, `--unit`, `--from`, `--from-phase`, manual resume): every unit with `risk: destructive` or `gated: true` requires explicit confirmation before running. **No flag disables these gates.** See "Universal safety gates" section below.

## Process

1. **Detect host.** Source `$ENSEMBLE_ROOT/references/host-detect.md`. Resolve `HOST`, `PEER`, `PEER_MODE`, `PEER_CMD`, `PEER_FORMAT`.

   **Plugin-install preflight (fail-fast).** Verify the skill's referenced files are accessible — observed failure mode: a partial plugin install that has only `SKILL.md` leaves the agent without the dispatch recipe, and peer review silently degrades to "skipped without recording why." For each of these reference paths, confirm the file exists:

   - `$ENSEMBLE_ROOT/references/host-detect.md`
   - `$ENSEMBLE_ROOT/references/build-orchestration.md`
   - `$ENSEMBLE_ROOT/references/build-handoff.md`
   - `$ENSEMBLE_ROOT/references/outside-voice.md`
   - `$ENSEMBLE_ROOT/references/severity.md`
   - `$ENSEMBLE_ROOT/references/finding-schema.md`
   - `$ENSEMBLE_ROOT/bin/ensemble-build-peer-prompt`
   - `$ENSEMBLE_ROOT/bin/ensemble-verify-peer-evidence`

   If any are missing, **fail at start with a clear error** — do not proceed with a degraded build. Surface the exact paths missing and tell the user to re-run `/en-setup` or sync the plugin.

2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, skip all peer-review subprocess calls (host implements + reviews inline). Each unit commit will record `peer-skipped: recursion-guard-active` so the gate at step 9k passes.
3. **Choose flavor.**
   - HOST = Claude Code → **build-by-orchestration** (Codex as worker). See `$ENSEMBLE_ROOT/references/build-orchestration.md`.
   - HOST = Codex → **build-handoff** (Claude as peer-reviewer). See `$ENSEMBLE_ROOT/references/build-handoff.md`.
   - User can override with `--orchestrate` or `--handoff`.
   - If the dispatched agent's CLI isn't available, fall back gracefully:
     - build-by-orchestration with no Codex → degrade to native implement + peer review (build-handoff with same-agent fallback).
     - build-handoff with no Claude → fall back to single-agent peer review (`codex exec` fresh subprocess).
4. **Load plan and run pre-flight.** Read `<plan-path>`. Verify all U-IDs present and unblocked. Verify each unit has Goal, Files, Approach, Test scenarios, **Risk, Gated** (or fall back to inference for legacy plans without `risk:`).

    **Pre-flight sub-state matrix** — read `peer_review_verdict` and the count of unresolved entries in `peer_review_resolutions:` (an entry is "unresolved" when its `status` is absent or anything other than `applied | deferred | disagreed | superseded`):

    | status | verdict | unresolved findings | git tracked | Pre-flight action |
    |---|---|---|---|---|
    | `open` | `approve` | 0 | yes | Proceed to step 4a |
    | `open` | `approve` | 0 | **no** | Offer auto-commit (one prompt), then proceed |
    | `draft` | `revise` | 0 | yes or no | **Offer finalize-and-build:** one prompt to re-run the peer pass via `/en-plan`'s finalize loop, on `approve` flip to `open`, auto-commit, then proceed |
    | `draft` | `revise` | > 0 | any | Refuse; list the unresolved findings; ask the user to apply/defer/disagree first via `/en-plan --resume` |
    | `open` | `null` | n/a | yes | Proceed (`--no-peer` was used; no peer expected) |
    | `open` | `null` | n/a | **no** | Offer auto-commit, then proceed |
    | `draft` | `null` | n/a | any | Refuse; peer review never ran. Suggest `/en-plan --resume <plan-path>`. |
    | `draft` | `reject` | any | any | Refuse; user must take over. Surface `peer_review_resolutions:` for context. |
    | `completed` / `abandoned` | any | any | any | Refuse |

    **Legacy inference** (plans drafted before the new frontmatter exists, i.e. no `peer_review_verdict` field):

    | Legacy signal | Inferred state |
    |---|---|
    | `status: draft` AND a parseable iteration log shows applied/deferred/disagreed entries | Treat as `peer_review_verdict: revise` + reconstructed `peer_review_resolutions` (best-effort, flagged `inferred: true`); offer finalize-and-build with a legacy notice |
    | `status: draft` AND no iteration log | Treat as `peer_review_verdict: null`; refuse |
    | `status: open` AND no peer-review fields | Treat as `peer_review_verdict: null` AND `--no-peer` was the path; accept |
    | `status: open` AND iteration log shows final `verdict: approve` | Treat as `peer_review_verdict: approve`; accept |
    | Any other ambiguous combination | Refuse with a clear instruction to re-run `/en-plan --resume <plan-path>` |

    Recovery prompt (when offering finalize-and-build):

    > Plan is in draft. Findings from the last peer review (verdict: revise) appear to be applied (resolutions: 8 applied, 0 deferred, 0 disagreed). I can finalize now: re-run the peer pass, flip to `open` on approve, and commit the plan. Then proceed with `/en-build`. (y / n / details)

    `--no-finalize` disables the recovery offer; `--finalize-only` runs finalize and stops without building.

   **4a. Plan-hash baseline.** If `peer_review_plan_hash` is present, record it as the build's baseline; the phase-boundary check will compare against it. If absent (legacy plan), compute one from current immutable fields and record it (but skip the boundary check this run; surface a notice).

   **4b. Status flip.** If `status: open`, flip to `in_progress` (frontmatter-only edit; plan content is untouched). Already-`in_progress` (resume) leaves status unchanged.
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

8a. **Phasing decision.** Compute `phasing_required` from these triggers (any one fires → phasing on):
    - Unit count `>= 8`.
    - `depth: deep` in plan frontmatter.
    - Any unit with `risk: destructive`.
    - `>= 2` units with `risk: high`.
    - `>= 2` units with `category: migration | migration-additive`.
    - `data_scale: large` in plan frontmatter.

    User overrides: `--no-phasing` forces off, `--phasing` forces on, `--unit U<N>` and `--from U<N>` bypass phasing entirely (universal safety gates still apply per unit — see below).

    **Phase classification** (when phasing is on): each unit maps to one of P1 (Measurement, `risk: low`), P2 (Additive, `risk: medium` except migration/backfill/schema-evolution categories), P3 (Migration / Backfill, `risk: high` OR `risk: medium` + migration/backfill/schema-evolution category), P4 (Destructive, `risk: destructive`). `risk:` is the single source of truth for phase placement; `category:` only carves out the `medium → P3` case for migrations. **Empty phases are collapsed silently.**

    **Inference fallback** (legacy plans without `risk:`): single ordered classifier, **first match wins**:
    1. **Destructive patterns** (highest priority): approach mentions `DROP TABLE`, `DROP SCHEMA`, `DROP DATABASE`, mass `DELETE` without `WHERE`, `TRUNCATE`, `rm -rf` against data dirs, `aws s3 rm --recursive`, `kubectl delete` against persistent resources, `terraform destroy` → `risk: destructive`.
    2. **Destructive migrations**: `migrations/` or `alembic/` paths AND `ALTER COLUMN` (drop/rename/type-change), `DROP COLUMN`, `DROP INDEX` on populated index, destructive data transforms → `risk: high`, `category: migration`.
    3. **Additive migrations**: `migrations/` paths AND additive only (`CREATE TABLE`, `ADD COLUMN` with default, `CREATE INDEX CONCURRENTLY`) → `risk: medium`, `category: migration-additive`.
    4. **Backfill**: approach mentions iterating existing rows (UPDATE batch loop, ETL backfill) → `risk: high`, `category: backfill`.
    5. **Observability/read-only**: files entirely under `tests/`, `docs/`, or configured observability paths → `risk: low`, `category: observability`.
    6. **Fallback**: → `risk: medium`, `category: feature`.

    When inference fires, surface a confirmation: *"Plan has no `risk:` metadata. Inferred classification: P1 (3), P2 (5), P3 (2), P4 (1). Review before continuing? (y/n)"*.

    **Dependency-vs-phase invariant.** For every dependency edge `U → V`, verify `phase(V) <= phase(U)`. If a low-risk unit depends on a higher-risk unit (so `phase(V) > phase(U)`), **reject the plan as a structural error** with three remediation options (remove the dependency, promote `U.risk:`, or split `U`). Never silently bury the unit in a higher phase — that would violate the "phase contains only its own risk class" invariant and let the unit land after a confirmation typed for destructive work.

8b. **Universal safety gates** (apply on EVERY execution path — phasing on/off, `--unit`, `--from`, `--from-phase`, manual resume; **no flag disables them**):

    For every unit selected for execution, classify it (using `risk:` or the ordered inference fallback) and enforce:

    | Classification | Gate |
    |---|---|
    | `risk: destructive` | Literal-string confirmation `"run unit U<N>"` typed verbatim, with goal/files/approach surfaced first. (When the unit is part of an active P4 phase already group-confirmed via `"run phase 4"`, this per-unit gate is skipped — see step 9.) |
    | `gated: true` | y/skip/abort confirmation, with goal and approach surfaced first. (Always per-unit; never group-confirmed.) |
    | `risk: high` AND `--strict-destructive` | Literal-string confirmation `"run unit U<N>"`. (Skipped when the unit is part of an active P3 phase already group-confirmed via `"run phase 3"`.) |
    | Anything else | No mandatory gate at the unit level. |

    These are the primary safety boundary — and they are deliberately **two narrow categories, nothing more**:
    - **`risk: destructive`** — its own literal-string category, for irreversible data loss.
    - **`gated: true`** — limited **explicitly to production-state-changing actions**: customer-facing feature-flag flips, production data backfills / data mutation, real-side-effect third-party API calls against **production** endpoints, API contract breaks, and production config changes with behavior impact. **Non-production external side effects** (PR/branch automation, issue/comment writes, local workflow or CI-config changes, sandbox/staging API calls, reversible repo operations) are explicitly **NOT** gated — they're covered by the per-unit verification gate (9d) + the post-build review (step 10), not user prompts. (Plan authors and peer review enforce this bar; see `$ENSEMBLE_ROOT/references/templates/plan-template.md`.)

    Everything outside these two categories advances autonomously. Phase-level prompts (P4 `"run phase 4"`, opt-in `--pause`) are conveniences that group multiple units' confirmations when phasing is active. With phasing off (or `--unit` selecting a destructive unit alone), the unit-level gate fires instead.

    **Preflight gate summary.** Before entering the unit loop (step 9), surface a one-line count so gates are never a surprise mid-build: *"Plan has N gated/destructive units that will pause: U<a> (gated), U<b> (destructive). The remaining M units run autonomously."* If N is 0, say so: *"No gated or destructive units — this plan runs fully autonomously."*

## Agent autonomy contract

`/en-build` is autonomous by design. The user authorized the work at plan time (peer-reviewed plan, `status: open`, hash recorded). After a unit commits successfully (step 9k passes), advance to the next unit immediately. **Do not pause** for confirmation, judgment, "natural checkpoint," "the next unit is bigger," "let me verify before continuing," or any reason not in the seven enumerated cases below.

### Scope of the contract

The contract governs **the inter-unit main loop** — specifically, the window from the START of step 9 (per-unit loop, after preflight has cleared) through the END of step 10 (after all units, before /en-learn hand-off). Within this window, pauses are restricted to the seven cases below.

**Steps 1–8 are NOT governed by this contract.** Preflight, sub-state matrix decisions (untracked-but-approved → offer auto-commit; draft + revise with cleared findings → offer finalize-and-build; unresolved draft findings → refuse and ask for `/en-plan --resume`), host detection, branch setup, plan-review concerns, and batch sizing all have their own documented prompts and protocols. Those are *pre-execution* prompts about whether the build can sensibly start; they're orthogonal to the *during-execution* autonomy this contract enforces.

Why scope this way: the field-observed bug ("Working tree is clean. I stopped at a clean checkpoint before U4") is specifically a post-step-9k, inter-unit pause inserted by agent judgment. Scoping the contract to that window catches exactly that bug class. Scoping wider would either invalidate legitimate preflight prompts or require an unmaintainable enumeration of every prompt-emitting code path.

### Legitimate pause cases within the contract window (exhaustive within scope, no others permitted)

1. **Working tree dirty at branch setup** (step 5) — stash / commit / abort prompt. *(Out of contract window; listed for completeness — see Scope above.)*
2. **Plan-review concerns surfaced at start** (step 7) — continue / pause / split prompt. *(Out of contract window; listed for completeness.)*
3. **`risk: destructive` unit at step 9a** — typed `"run unit U<N>"` literal-string gate.
4. **`gated: true` unit at step 9a** — y/skip/abort prompt.
5. **P4 phase-level confirmation** (step 9, phasing-on path) — typed `"run phase 4"` literal-string.
6. **`--pause` flag set** (step 9, opt-in) — between-phase y/pause/n prompt.
7. **Failure protocol fires** (failure-protocol table) — gate failure, peer reject, malformed evidence, hash mismatch, after-phase verification failure, plan-hash drift, worker malformed diff, etc. Each has its own documented handler.

Cases 3–7 are inside the contract window (steps 9 and 10). Cases 1 and 2 are listed for completeness so the reader sees the full pause-emitting universe of /en-build; they're already in their own documented handlers and are not subject to this contract.

### Anti-patterns (explicitly forbidden)

- **Agent-initiated "checkpoint before bigger unit" pauses.** The plan was authored and peer-reviewed; the agent does not re-evaluate unit complexity at execution time.
- **"Working tree is clean, paused for confirmation" between non-gated units.** Working-tree-clean is the *expected* state between units, not a reason to pause.
- **"Should I continue?" preambles outside the seven cases.** Continuing is the default; stopping requires a specific authorized reason.
- **"Let me verify with the user before [implementing/committing/running tests/anything]"** when none of the seven cases apply. The user already authorized the plan; per-unit pauses bypass that authorization.
- **"This next unit has [X characteristic that's not in the seven cases]; pausing here."** No characteristic outside the seven cases is grounds for an inserted pause.

### Right response to LLM uncertainty: advance, not ask

If the agent feels uncertain about advancing, the correct action is to **continue per the contract**. The failure protocols are the safety net:

- Tests fail → step 9d / 9j catches it.
- Lint fails → step 9d catches it.
- Peer review fails → step 9g / 9h / 9i handles it.
- Implementation goes wrong → verification gate 1 or 2 catches it.
- After-phase regression → after-phase verification catches it.

Agent-self-paused checkpoints add no protection on top of these mechanisms — they just add friction that the autonomous-execution design exists to avoid.

If the agent has a real concern that's outside the seven cases AND not caught by failure protocols, the right place to surface it is in the **per-unit progress report after committing** (step 9k's report). The report is informational — it doesn't pause the loop. Example:

```
✓ U3 — feat(api): wrap rotateRefreshToken in singleFlight  [P2 / risk: medium]
  Implementer: codex (worker) | Simplifier: 2 changes | Peer: applied 1, deferred 1
  Tests: 7 added, 7 passing | Commit: a3f1b9c
  Note: U4 touches more files than U3 (12 vs 3). No pause; advancing.
```

`Note:` lines are encouraged when the agent has observations worth surfacing. They don't gate the build.

9. **Phase loop (when phasing is on).** For each phase in `[P1, P2, P3, P4]`:
   - Skip empty phases silently.
   - Surface phase plan to user (units, files, risk summary).
   - **Phase-level mandatory gates** (cannot be bypassed by any flag):
     - If phase == P4: require literal-string `"run phase 4"`. Accepting covers all destructive units in the phase; per-unit destructive gates are NOT re-prompted within P4.
     - If `--strict-destructive` AND phase == P3: require literal-string `"run phase 3"`. Same group-cover semantics.
   - **Opt-in per-phase pause** (`--pause` flag, default off): ask y/pause/n. Default behavior is auto-roll into the next phase.
   - For each unit in the phase (dependency order):
     - **9a. Mandatory safety gate (cannot be bypassed by any flag, on any code path).** Before doing ANY work on this unit:
       1. **Classify the unit.** Read its `risk:` field; if absent, run the ordered classifier from step 8a's inference fallback to assign one. Read its `gated:` field (default `false`).
       2. **If `risk: destructive`** AND the active phase has not already been group-confirmed (no `"run phase 4"` accepted for this phase): surface the unit's goal, files, and approach; require typed `"run unit U<N>"` (literal string, verbatim). Any other input → record the unit as `skipped` and advance to the next unit; if the user types `abort`, stop the build per the abort protocol.
       3. **If `gated: true`** (regardless of risk class): surface the unit's goal and approach; require y/skip/abort. **This gate fires even when a phase-level `"run phase 4"` or `"run phase 3"` has been accepted** — gating is per-unit-only and never group-covered. On `skip`: record as `skipped` and continue. On `abort`: stop per the abort protocol.
       4. **If `--strict-destructive` is set AND `risk: high`** AND the active phase has not been group-confirmed (no `"run phase 3"` accepted): same as step 2 with `"run unit U<N>"`.
       5. Otherwise: proceed to 9b.
       
       This entire sequence runs identically on every code path — phase loop, phasing-off, `--unit U<N>`, `--from U<N>`, `--from-phase`, manual resume. **No flag suppresses it.** The phase-level prompts above (P4 `"run phase 4"`, P3 under `--strict-destructive`) only group-confirm the *destructive* and *high-risk* gates inside their phase; they never cover `gated: true`, and they never apply on phasing-off paths.
     - **9b. Honor execution note** (test-first / characterization-first / pragmatic).
     - **9c. Implement** via the flavor's flow (worker dispatch or native).
     - **9d. Verification gate.** Run unit tests + project lint. Failures → fix before committing (don't commit a broken unit).
     - **9e. Conditional per-unit peer review (destructive / gated units ONLY).** **The branch-level review model (D35) defers code-simplifier and Outside Voice review to the post-build phase (step 10) for ordinary units.** The exception: a unit with `risk: destructive` or `gated: true` MUST get a dedicated per-unit Outside Voice peer pass here — a branch-level pass is not a sufficient substitute for high-consequence work. For those units only:
       - Set `ENSEMBLE_PEER_REVIEW=true`; invoke the peer per the flavor (`build-orchestration.md` / `build-handoff.md`); apply findings per `$ENSEMBLE_ROOT/references/severity.md` into a `resolutions[]` list.
       - **Per-unit finalize loop.** Track `re_review_count` (it **starts at 0**; the initial peer pass does NOT count). If `verdict: revise` AND ≥1 finding was applied AND `re_review_count < --max-per-unit-iterations` (default 1): re-invoke the peer with a "Previous review context" tempfile, then increment. Terminates on `approve`, cap exhaustion, all-deferred/disagreed, or `reject` (pause + surface). **Cap-hit warning:** if the cap is hit AND ≥1 finding was applied on the last re-review pass, surface a P1 warning — those applications were verified by tests+lint but NOT by another peer pass.
       - Re-verify (tests + lint) if code changed.
       - For all other (ordinary) units: skip straight to 9f. No per-unit peer, no per-unit simplifier — they're covered by the post-build branch-level review.
     - **9f. Commit.** Conventional subject + U-ID + `phase: P<N>` trailer (always).
       - **Ordinary unit:** commit with the `phase: P<N>` trailer only. Per-unit peer evidence is NOT required — the post-build branch-level review (step 10) produces the `review-verdict:` covering this unit. (If `--no-peer-per-unit` semantics or a recursion guard apply, a `peer-skipped:` trailer is also acceptable.)
       - **Destructive / gated unit:** also write the `peer-verdict:` trailer (one; required keys `verdict`/`peer_mode`/`iteration`/`findings_count`) and one `peer-resolution:` trailer per finding, then run `$ENSEMBLE_ROOT/bin/ensemble-verify-peer-evidence HEAD --require-peer-resolution`. If it returns anything but `ok`, the commit is invalid — `git reset --soft HEAD^`, fix the trailers (or re-run the peer), and re-commit; or halt and surface. **No flag lets a destructive/gated unit commit without an actual peer pass.**
   - **After-phase verification.** Run project default test suite (e.g. `npm test` / `pytest`), lint, typecheck. On failure: stop; surface failing tests; offer investigate / commit-as-WIP-via-`--commit-wip` / abort. Do **not** advance to next phase.
   - **Plan-hash check.** Re-compute `peer_review_plan_hash` over current immutable plan-input fields (excluding iteration log, per-unit `status`, `peer_review_resolutions`). On mismatch with the build's baseline → refuse to advance; surface that the plan was edited externally during build. (User can re-baseline with `/en-build --re-baseline` after reviewing the diff.)
   - **Working-tree contract.** Verify clean tree, expected feature branch, up to the previous phase's last commit. Any divergence → refuse to advance; surface state.
   - Surface phase summary (units, commits, any destructive/gated per-unit peer findings).
   - If `--pause` AND not last phase: ask y/pause/n for next phase. Default: roll forward.

   **Phasing-off path** (phasing disabled by triggers, `--no-phasing`, `--unit U<N>`, `--from U<N>`): same per-unit loop (9a–9f), no phase grouping, no phase-level prompts. Critically, **step 9a runs verbatim** on every selected unit — `--unit U8` against a destructive unit still requires `"run unit U8"` typed literally; `--from U3` against a plan that contains a gated unit still pauses for y/skip/abort on that unit AND gets the dedicated per-unit peer pass (9e). Commit trailer `phase: P<N>` is still appended based on the unit's classification (so logs stay consistent across phasing-on and phasing-off runs). **Note:** when phasing is off and `--unit`/`--from` builds a subset, the post-build branch-level review (step 10) still runs over the resulting branch diff so ordinary units get their `review-verdict:` coverage.

10. **Post-build phase (branch-level simplify → review → audit → learn).** Runs ONCE after all units commit. This is where ordinary units get their code-simplifier and Outside Voice review — at the branch level, not per-unit (D29).

    1. **Full test suite, lint, typecheck.** On failure: stop; surface; offer investigate / `--commit-wip` / abort.
    2. **Code-simplification pass** — invoke `/en-simplify` on the branch diff (`git diff <merge-base>..HEAD`). Skip on docs-only or trivial (<~10 changed lines) branches, or with `--no-simplify`. It leaves changes in the working tree (does not commit). Skipped for the rare branch composed entirely of destructive/gated units already reviewed per-unit.
    3. **Branch-level Outside Voice review** — invoke `/en-review --mode headless` over the branch diff. Apply eligible findings per `$ENSEMBLE_ROOT/references/severity.md` (auto-apply `safe_auto`; surface P0-disagreements / high-confidence security or architecture findings). Skip with `--no-peer` (records the branch as review-skipped). Set `ENSEMBLE_PEER_REVIEW=true` for any subprocess call.
    4. **Commit the simplify + review changes** (if any) with a `review-verdict:` trailer carrying `{verdict, reviewer, mode, units_covered, findings_count}` where `units_covered` lists **every ordinary U-ID built this run** (destructive/gated units already carry their own per-unit evidence and don't need branch-level coverage). If steps 2–3 produced no working-tree changes, create an empty commit (`--allow-empty`) carrying the `review-verdict:` trailer so the branch records the review pass. Format per `$ENSEMBLE_ROOT/references/build-orchestration.md`.
    5. **End-of-build evidence audit (mandatory, mechanical).** Compute branch-level coverage once: `$ENSEMBLE_ROOT/bin/ensemble-verify-peer-evidence --branch-coverage <merge-base>..HEAD --json` → `covered_units`. Then for each plan U-ID, confirm it is **either** covered by `covered_units` (ordinary units) **or** has a per-unit commit passing `ensemble-verify-peer-evidence <sha>` (destructive/gated units, verified with `--require-peer-resolution`). **Surface a per-unit table in the summary**:

      ```
      Evidence audit — FR07-auth-rotation (5 units)
        ✓ U1 — branch-level review-verdict (approve, covered)
        ✓ U2 — branch-level review-verdict (approve, covered)
        ✓ U3 — branch-level review-verdict (revise→applied, covered)
        ✓ U4 — per-unit peer-resolution: 3 (gated:true — applied 2, disagreed 1)
        ✓ U5 — branch-level review-verdict (approve, covered)

      Audit verdict: ok (5/5 units have valid evidence; 1 per-unit, 4 branch-level)
      ```

      A unit fails verification when it is neither in `covered_units` nor backed by a valid per-unit commit (and, for destructive/gated units, a per-unit commit lacking `peer-resolution`/`peer-verdict`). Then the audit verdict is `failed`:

      ```
      ⚠️  Evidence audit FAILED. The following units lack valid evidence:
        ✗ U10 — not in branch-level coverage and no per-unit evidence commit
        ✗ U13 — gated:true unit with no per-unit peer-resolution (branch-level coverage is not sufficient for gated units)

      The branch-level review didn't cover these units, or a gated unit's
      dedicated peer pass didn't run. Do NOT merge until resolved (run
      /en-cross-review, or re-run /en-build's post-build review / --from <U-ID>).
      ```

      The audit surfaces, but does NOT auto-revert — the user decides. If the audit fails, the suggested next step changes from `/en-review → /en-qa → /en-ship` to `/en-cross-review on the failing units, then re-audit`.

    - Summary: completion status per U-ID, deviations, branch-level simplifier + review verdict, any per-unit (destructive/gated) peer verdicts. Per-phase summary if phasing was on.
    - **Auto-invoke `/en-learn`** (soft prompt — A3): "Build complete. Capture learnings? (yes / skip)". User accepts → invoke; user declines → no-op. **If the peer-evidence audit failed, /en-learn should be deferred** until the failing commits are addressed.
    - Suggest next: `/en-review` → `/en-qa` → `/en-ship` — but only if the audit passed. Otherwise: `/en-cross-review` on the failing commits.

## Flags

| Flag | Effect |
|---|---|
| `--orchestrate` | Force build-by-orchestration regardless of host |
| `--handoff` | Force build-handoff regardless of host |
| `--no-simplify` | Skip the post-build code-simplification pass (step 10.2). |
| `--no-peer` | Skip the post-build branch-level Outside Voice review (step 10.3). The branch records as review-skipped; destructive/gated units still get their mandatory per-unit peer pass. |
| `--no-peer-per-unit` | Skip the per-unit peer pass that destructive/gated units would otherwise get (9e). Ordinary units have no per-unit peer in the branch-level model regardless. |
| `--max-per-unit-iterations <N>` | Cap on the destructive/gated per-unit finalize-loop re-reviews (9e). Default 1. 0 disables looping. |
| `--worktree` | Run in a worktree (`../<repo>-<fr-id>/`) |
| `--unit U<N>` | Build only the named unit; don't auto-advance. Universal safety gates still apply. |
| `--dry-run` | Show what would happen; don't write or commit |
| `--from U<N>` | Resume from a specific unit (skip earlier ones). Universal safety gates still apply per unit. |
| `--no-phasing` | Force phasing off (universal safety gates still fire per unit) |
| `--phasing` | Force phasing on even if no trigger fired |
| `--from-phase P<N>` | Resume at phase N. Verifies prior phases' commits and a clean working tree before starting. |
| `--pause` | Pause and prompt between phases (default is auto-roll). Mandatory destructive / gated-unit confirmations always fire regardless. |
| `--strict-destructive` | Add literal-string confirmation for `risk: high` and Phase 3 in addition to P4 / `risk: destructive` (which always require it). |
| `--no-finalize` | Disable the recovery offer for `draft + revise` plans; refuse on draft as today. |
| `--finalize-only` | Run finalize loop and stop without building. |
| `--commit-wip` | After a stopped run (Ctrl-C, gate-failure, etc.), create a `wip/<plan_id>-phase<N>` branch and commit current state. Explicit user invocation only — never automatic. |
| `--re-baseline` | After reviewing an external plan-file diff, accept the new state as the build's baseline `peer_review_plan_hash`. |

**No flag disables universal safety gates.** Every flag changes phasing, pacing, or selection; none turn off destructive / gated confirmations.

## Cross-review

**On per unit by default.** Disable globally with `--no-peer-per-unit`. Auto-skipped (each case maps 1:1 to a documented `peer-skipped:` enum value — the auto-skipped commit STILL records its reason via the trailer so the verify gate at step 9k passes):

| Auto-skip case | `peer-skipped:` value |
|---|---|
| `PEER_AVAILABLE=false` | `peer-skipped: PEER_AVAILABLE=false` |
| `ENSEMBLE_PEER_REVIEW=true` (recursion guard) | `peer-skipped: recursion-guard-active` |
| `--no-peer-per-unit` flag set | `peer-skipped: --no-peer-per-unit-flag` |
| Diff `< skip_peer_below_lines` (default 50) | `peer-skipped: auto-skip:diff-below-threshold` |
| Lightweight depth AND `skip_peer_on_lightweight: true` | `peer-skipped: auto-skip:lightweight-depth` |

Auto-skip and explicit-skip are operationally identical — the agent still writes the structured `peer-skipped:` trailer so the verify gate has machine-readable evidence either way. **Auto-skip cases are NOT permitted on destructive (`risk: destructive`) or `gated: true` units** — those require an actual peer pass (`--require-peer-resolution` enforces it; the gate halts the build instead of letting the unit ship without peer evidence).

When peer is available:
- Cross-agent → peer is the *other* agent (D23).
- Single-agent fallback → fresh subprocess of host's CLI (D31). Prompt augmented per `$ENSEMBLE_ROOT/references/single-agent-fallback.md`.

## Code simplification

**On per unit by default.** Skipped on:

- Trivial units (renames, single-line config tweaks, pure deletions).
- `--no-simplify` flag.
- Units where the diff exceeds `simplifier.max_lines_to_run` (default 2000).

Two verification gates protect against simplifier breakage. On Gate-2 failure, revert the simplifier's edits and continue with the original implementation (per `$ENSEMBLE_ROOT/references/code-simplifier-dispatch.md`).

## Per-unit progress report

After each unit commits, surface a one-line summary:

```
✓ U3 — feat(auth): wrap rotateRefreshToken in singleFlight  [P2 / risk: medium]
  Implementer: codex (worker) | Simplifier: 2 changes | Peer: 2 iterations, applied 1, deferred 1
  Tests: 7 added, 7 passing | Commit: a3f1b9c (trailers: phase: P2, peer-resolution: x2)
```

(Iteration count >1 means the per-unit finalize loop ran. `2 iterations` = initial peer pass + 1 re-review pass.)

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

- `$ENSEMBLE_ROOT/references/host-detect.md` — host detection
- `$ENSEMBLE_ROOT/references/build-orchestration.md` — Claude-host flow (worker dispatch)
- `$ENSEMBLE_ROOT/references/build-handoff.md` — Codex-host flow (peer-reviewer dispatch)
- `$ENSEMBLE_ROOT/references/code-simplifier-dispatch.md` — when/how to run simplifier; revert protocol
- `$ENSEMBLE_ROOT/references/outside-voice.md` — peer-review prompt and verdict handling
- `$ENSEMBLE_ROOT/references/single-agent-fallback.md` — fallback when only one CLI installed
- `$ENSEMBLE_ROOT/references/finding-schema.md` — peer JSON shape
- `$ENSEMBLE_ROOT/references/severity.md` — apply / defer / disagree routing
- `$ENSEMBLE_ROOT/references/recursion-guard.md` — ENSEMBLE_PEER_REVIEW env var
- `$ENSEMBLE_ROOT/references/stable-ids.md` — U-ID stability rules
- `$ENSEMBLE_ROOT/bin/ensemble-build-peer-prompt` — assembles the Outside Voice prompt for peer dispatch (used by step 9g)
- `$ENSEMBLE_ROOT/bin/ensemble-verify-peer-evidence` — mechanical gate at step 9k and step 10. Inspects git trailers; rejects commits without valid peer evidence. Run with `--require-peer-resolution` for destructive / `gated: true` units (peer-skipped is not sufficient).

## Failure protocol

| Failure | Behavior |
|---|---|
| Plan has unmet dependency (`Depends: U7` but U7 not present) | Stop; surface; suggest plan revision |
| Plan structure violates phase invariant (low-risk depends on higher-risk) | Reject the plan with three remediation options: remove the dependency, promote the unit's `risk:`, or split the unit. Never silently bury units across phases. |
| Plan in `status: draft` with unresolved `peer_review_resolutions:` | Refuse build; list unresolved findings; suggest `/en-plan --resume`. |
| Plan in `status: draft + revise` with all resolutions cleared | Offer finalize-and-build single prompt (recovery flow). On y, run `/en-plan` finalize loop, flip to `open`, commit, then proceed. |
| Plan untracked in git but `status: open` and verdict cleared | Offer auto-commit single prompt; on y, commit and proceed. |
| Plan-hash mismatch at phase boundary | Refuse to advance; surface that immutable plan-input fields changed during build; ask user to re-baseline (`--re-baseline`) or abort. |
| Verification gate 1 fails on a unit | Pause; show test output; ask user: retry, skip, abort |
| Verification gate 2 fails | Revert simplifier edits automatically; proceed with original; surface regression |
| After-phase verification fails (full suite / lint / typecheck) | Stop. Do not advance to next phase. Surface failing tests; offer investigate / `--commit-wip` / abort. |
| Peer review verdict = `reject` | Pause and surface to user before commit |
| Peer subprocess attempts to modify files (D30 violation) | Detect via git status; revert; do not trust this round of findings; log violation |
| Worker dispatch returns malformed diff | Retry once; on second failure, surface and ask user to take over the unit |
| `git restore` fails on a revert | Surface; abort the build; do not leave the working tree corrupted |
| User Ctrl-C mid-phase / mid-unit | **Stop cleanly. No signal-time git operations.** Surface: current branch, current unit (with completion state), dirty files, last successful commit. Provide explicit resume instructions (`/en-build --from U<N>` or `--from-phase P<M>`). User invokes `/en-build --commit-wip` separately if a WIP commit is desired. |
| User asks to abort mid-unit | **Stop cleanly. Surface state and resume instructions.** Do NOT auto-commit, auto-stash, or auto-create a WIP branch — `abort` is a request to stop, not to preserve partial progress. WIP capture is opt-in via a separate `/en-build --commit-wip` invocation; the user must explicitly request it. |

## What this skill never does

- **Never modifies plan content.** Units, approach, scope, and U-IDs are `/en-plan` territory. Lifecycle status flip (`open` → `in_progress`) at step 4 and unit `status` updates after each commit are bookkeeping only — no content changes.
- **Never opens a PR.** PRs are `/en-ship` territory.
- **Never deletes files outside the unit's scope.**
- **Never bypasses verification gates.** A gate failure stops or reverts; never proceeds anyway.
- **Never bypasses universal safety gates.** Destructive units and gated units always require explicit confirmation. No flag disables them.
- **Never inserts agent-initiated checkpoints.** Only the seven enumerated pause cases (see Agent autonomy contract) are legitimate within the inter-unit main loop. The agent never adds "let me checkpoint here" or "I'll pause before the next unit" pauses based on its own judgment. The plan was authored and reviewed; the agent executes.
- **Never silently buries low-risk units in higher-risk phases.** Phase-invariant violations reject the plan structurally.
- **Never auto-commits or auto-stashes on Ctrl-C / abort / signal.** No signal-time git operations. WIP commits are user-initiated only via `--commit-wip`.
- **Never invokes `/en-build` recursively.** Recursion guard ensures this.
- **Never commits a unit without peer evidence.** Step 9k runs `$ENSEMBLE_ROOT/bin/ensemble-verify-peer-evidence` after each commit. A unit commit without `peer-resolution:` or `peer-skipped:` trailers is rejected — the agent must either re-run peer review or record a documented skip reason. Destructive and gated units cannot use `peer-skipped:` at all; they require an actual peer pass.
- **Never declares a build "complete" with missing peer evidence.** The end-of-build audit (step 10) runs the same verification across every unit commit on the branch and refuses the success path (`/en-review` → `/en-qa` → `/en-ship`) if any unit fails. Suggests `/en-cross-review` on the failing commits instead.
