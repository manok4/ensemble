---
name: en-build
description: "Execute an implementation plan unit-by-unit on a feature branch. Picks build-by-orchestration (Claude host dispatches Codex worker) or build-handoff (Codex host with Claude peer reviewer) per host detection. Each unit: tests + lint → simplifier → re-verify → peer review → host applies → commit. Auto-invokes /en-learn at the end. Trigger phrases: 'build this plan', 'implement <plan_id>', 'start building', 'execute the plan'."
---

# `/en-build`

Execute a plan, unit by unit, with cross-agent peer review at every per-unit gate. Two flavors based on host detection — both guarantee implementer ≠ reviewer.

> **Hard preconditions.** A plan in `docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md` (e.g. `EN03-improvement_dashboard-overview.md`; `<PREFIX>` from foundation's `plan_id_prefix`, default `FR`) with `status: open` (or `in_progress` when resuming), all U-IDs present, no unblocked dependencies. The skill verifies these at start. **Recoverable `status: draft`** (verdict `revise` with all findings resolved in `peer_review_resolutions:`) is offered a single finalize-and-build prompt instead of refused.

> **Universal safety gates** (apply on EVERY code path — phasing on/off, `--unit`, `--from`, `--from-phase`, manual resume): every unit with `risk: destructive` or `gated: true` requires explicit confirmation before running. **No flag disables these gates.** See "Universal safety gates" section below.

## Process

1. **Detect host.** Source `references/host-detect.md`. Resolve `HOST`, `PEER`, `PEER_MODE`, `PEER_CMD`, `PEER_FORMAT`.

   **Plugin-install preflight (fail-fast).** Verify the skill's referenced files are accessible — observed failure mode: a partial plugin install that has only `SKILL.md` leaves the agent without the dispatch recipe, and peer review silently degrades to "skipped without recording why." For each of these reference paths, confirm the file exists:

   - `references/host-detect.md`
   - `references/build-orchestration.md`
   - `references/build-handoff.md`
   - `references/outside-voice.md`
   - `references/severity.md`
   - `references/finding-schema.md`
   - `bin/ensemble-build-peer-prompt`
   - `bin/ensemble-verify-peer-evidence`

   If any are missing, **fail at start with a clear error** — do not proceed with a degraded build. Surface the exact paths missing and tell the user to re-run `/en-setup` or sync the plugin.

2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, skip all peer-review subprocess calls (host implements + reviews inline). Each unit commit will record `peer-skipped: recursion-guard-active` so the gate at step 9k passes.
3. **Choose flavor.**
   - HOST = Claude Code → **build-by-orchestration** (Codex as worker). See `references/build-orchestration.md`.
   - HOST = Codex → **build-handoff** (Claude as peer-reviewer). See `references/build-handoff.md`.
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

    These are the primary safety boundary. Phase-level prompts (P4 `"run phase 4"`, opt-in `--pause`) are conveniences that group multiple units' confirmations when phasing is active. With phasing off (or `--unit` selecting a destructive unit alone), the unit-level gate fires instead.

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
     - **9d. Verification gate 1.** Run unit tests + project lint. Failures → fix before proceeding (don't advance to simplifier or review on broken unit).
     - **9e. Code-simplifier pass.** Per `references/code-simplifier-dispatch.md`. Skip on trivial units, on `--no-simplify`, or with the auto-skip heuristics.
     - **9f. Verification gate 2.** Re-run unit tests after simplifier. On failure: revert simplifier's changes (`git restore` for files in `changes_made[]`); proceed with original implementation; surface regression.
     - **9g. Outside Voice peer review (mandatory invocation).** Per the chosen flavor (`build-orchestration.md` or `build-handoff.md`). Set `ENSEMBLE_PEER_REVIEW=true` for any subprocess call.

       **Fail-closed contract:** every unit MUST end this step with EITHER a parsed peer-response JSON in hand (will become `peer-resolution:` trailers in 9k) OR a recorded skip reason from the documented enum (will become a `peer-skipped:` trailer). **Writing "Peer review approved" as plain prose without invoking the subprocess is a violation of this contract** — the gate at 9k will reject the commit.

       Valid skip reasons (each maps 1:1 to a documented `peer-skipped:` value):
         - `PEER_AVAILABLE=false` — host-detect resolved no peer; build-handoff cannot dispatch.
         - `--no-peer-per-unit-flag` — user passed the flag.
         - `peer-subprocess-failed:<one-line-detail>` — subprocess timed out, returned malformed JSON twice, or D30 violation forced abort. **Surface to the user;** do not silently proceed if the unit is `risk: destructive` or `gated: true` (those require peer-resolution; see 9k).
         - `cap-exhausted-with-applied-findings` — finalize loop hit cap with applied findings on the last pass (already P1-warning-surfaced per 9h.1).
         - `recursion-guard-active` — `ENSEMBLE_PEER_REVIEW=true` was set at start; peer call would recurse.

       For any other situation — including "I forgot," "the conversation was compacted," or "I assumed it would be ok" — there is no valid skip path. Re-invoke the peer; if you can't, fall back to one of the documented skip reasons and surface clearly.
     - **9h. Host applies findings** per `references/severity.md`: agree-and-apply / agree-and-defer-to-tech-debt-tracker / disagree-with-rationale. As each finding is walked, append a structured entry to a per-unit `resolutions[]` list (`finding_id`, `u_id`, `iteration`, `severity`, `status`, `title`, `rationale` when applicable — schema in `references/build-handoff.md`).
     - **9h.1. Per-unit finalize loop.** Track a per-unit `re_review_count` counter that **starts at 0** and increments by 1 after each re-review pass (the initial peer pass at 9g does NOT count toward it). Loop condition: if `verdict: revise` AND ≥1 finding was applied in 9h AND `re_review_count < --max-per-unit-iterations` (default 1): build a "Previous review context" section from the resolutions[] list, write to a tempfile, **re-invoke step 9g** with `--iteration-context-file <path>` (build-handoff via the helper subprocess; build-orchestration inline), then increment `re_review_count`. With the default cap=1, this guarantees **exactly one re-review pass** when the initial pass returned `revise` with applied findings — the post-fix diff is always peer-verified at default settings. `--max-per-unit-iterations 0` disables the loop entirely (single-pass behavior). Loop terminates on `approve`, cap exhaustion, all-deferred-or-disagreed (no fixes to verify), or `reject` (pause + surface to user). **Cap-exhaustion warning:** if the cap is hit AND ≥1 finding was applied on the *last* re-review pass, surface a P1 warning in the unit summary — those last applications were verified by lint+tests in 9j but NOT by another peer pass. The user can raise `--max-per-unit-iterations` if this happens repeatedly.
     - **9i. Surface to user** if peer reports a P0 the host disagrees with, or a security/architecture finding (confidence ≥ 8) the host wants to defer, or peer verdict = `reject`. All other host decisions proceed without confirmation.
     - **9j. Re-verify** if any code changed in 9h — unit tests + lint. On failure: revert; surface.
     - **9k. Verify-and-commit (mechanical gate).** This step is **not** a plain commit — it is a *verifying* commit. The agent does NOT decide whether peer evidence is sufficient; the helper script does, by inspecting trailers on the commit it just produced.

       **Substeps (in order, no skipping):**

       1. **Build the commit message** with conventional subject + U-ID, body listing peer-finding counts (applied / deferred / disagreed) + iteration count, plus trailers:
          - `phase: P<N>` — always.
          - **`peer-verdict: <single-line JSON>`** — exactly one, written WHENEVER the peer actually ran on this unit (regardless of finding count). Required keys: `verdict` (`approve`|`revise`|`reject`), `peer_mode`, `iteration`, `findings_count` (must match the count of `peer-resolution:` trailers below). This is the primary "the peer reviewed this unit" signal — it covers the zero-finding approve case where there are no per-finding trailers to write.
          - **`peer-resolution: <single-line JSON>`** — one per finding from the resolutions[] list. Zero of these is fine if peer returned 0 findings; the `peer-verdict:` trailer above carries the evidence in that case. Schema per `references/build-handoff.md`.
          - **`peer-skipped: <reason>`** — exactly one, written ONLY if 9g recorded a skip reason from the documented enum. Mutually exclusive with `peer-verdict:` (peer either ran or it didn't).
       2. **Commit.**
       3. **Run `bin/ensemble-verify-peer-evidence HEAD` in JSON mode.** This is the gate. The helper inspects trailers and returns:
          - `verdict: ok` (exit 0) → continue to next unit.
          - `verdict: missing-evidence` / `missing-resolution` / `malformed` (exit 1) → **the commit is invalid by build contract**. Either (a) `git reset --soft HEAD^` to keep the staged changes and re-attempt the commit with proper trailers, or (b) surface to the user and stop the build.
       4. **For destructive (`risk: destructive`) or `gated: true` units, run with `--require-peer-resolution`.** This rejects `peer-skipped:` as evidence — destructive and gated units cannot ship without an actual peer pass. If 9g had to skip (e.g. peer subprocess failed), **the build halts** and surfaces the failure to the user. **No flag lets a destructive or gated unit commit without peer-resolution evidence.**

       The verify step is mechanical — the helper reads git trailers, not the agent's procedural memory of "did I do the peer call." This is the load-bearing gate that catches the field-observed failure mode where an agent skipped peer review and wrote "Peer review approved" as text.

       Format per `references/build-orchestration.md` or `build-handoff.md`.
   - **After-phase verification.** Run project default test suite (e.g. `npm test` / `pytest`), lint, typecheck. On failure: stop; surface failing tests; offer investigate / commit-as-WIP-via-`--commit-wip` / abort. Do **not** advance to next phase.
   - **Plan-hash check.** Re-compute `peer_review_plan_hash` over current immutable plan-input fields (excluding iteration log, per-unit `status`, `peer_review_resolutions`). On mismatch with the build's baseline → refuse to advance; surface that the plan was edited externally during build. (User can re-baseline with `/en-build --re-baseline` after reviewing the diff.)
   - **Working-tree contract.** Verify clean tree, expected feature branch, up to the previous phase's last commit. Any divergence → refuse to advance; surface state.
   - Surface phase summary (units, commits, peer findings, simplifier changes).
   - If `--pause` AND not last phase: ask y/pause/n for next phase. Default: roll forward.

   **Phasing-off path** (phasing disabled by triggers, `--no-phasing`, `--unit U<N>`, `--from U<N>`): same per-unit loop (9a–9k), no phase grouping, no phase-level prompts. Critically, **step 9a runs verbatim** on every selected unit — `--unit U8` against a destructive unit still requires `"run unit U8"` typed literally; `--from U3` against a plan that contains a gated unit still pauses for y/skip/abort on that unit. Commit trailer `phase: P<N>` is still appended based on the unit's classification (so logs stay consistent across phasing-on and phasing-off runs).

10. **After all units:**
    - Full test suite, lint, typecheck.
    - **End-of-build peer-evidence invariant (mandatory, mechanical).** Walk every unit commit on this branch (since branch start) and run `bin/ensemble-verify-peer-evidence <sha>` per commit. Aggregate by U-ID. **Surface a per-unit table in the summary**:

      ```
      Peer-evidence audit — FR07-auth-rotation (5 units)
        ✓ U1 — peer-resolution: 2 (applied 1, deferred 1)
        ✓ U2 — peer-resolution: 0 (verdict: approve, no findings)
        ✓ U3 — peer-skipped: PEER_AVAILABLE=false
        ✓ U4 — peer-resolution: 3 (applied 2, disagreed 1)
        ✓ U5 — peer-resolution: 1 (applied 1)

      Audit verdict: ok (5/5 units have valid evidence)
      ```

      If ANY unit's commit fails verification (no trailers, malformed JSON, invalid skip reason, or destructive/gated unit with peer-skipped instead of peer-resolution), the audit verdict is `failed` and the summary surfaces:

      ```
      ⚠️  Peer-evidence audit FAILED. The following commits are missing valid evidence:
        ✗ U10 (sha: a3f1b9c) — verdict: missing-evidence (no peer-resolution: or peer-skipped: trailer)
        ✗ U13 (sha: b8e2cd4) — verdict: missing-resolution (gated:true unit; peer-skipped is not sufficient)

      This means /en-build's per-unit peer review didn't actually run on these
      units. The unit commits are still on the branch but should NOT be merged
      until peer review is performed (run /en-cross-review on each commit, or
      revert and re-run /en-build --from <U-ID>).
      ```

      The audit surfaces, but does NOT auto-revert — the user decides. If the audit fails, the suggested next step changes from `/en-review → /en-qa → /en-ship` to `/en-cross-review on the failing commits, then re-audit`.

    - Summary: completion status per U-ID, deviations, simplifier changes, peer-review verdicts. Per-phase summary if phasing was on.
    - **Auto-invoke `/en-learn`** (soft prompt — A3): "Build complete. Capture learnings? (yes / skip)". User accepts → invoke; user declines → no-op. **If the peer-evidence audit failed, /en-learn should be deferred** until the failing commits are addressed.
    - Suggest next: `/en-review` → `/en-qa` → `/en-ship` — but only if the audit passed. Otherwise: `/en-cross-review` on the failing commits.

## Flags

| Flag | Effect |
|---|---|
| `--orchestrate` | Force build-by-orchestration regardless of host |
| `--handoff` | Force build-handoff regardless of host |
| `--no-simplify` | Skip code-simplifier on every unit |
| `--no-peer-per-unit` | Skip per-unit Outside Voice peer review |
| `--max-per-unit-iterations <N>` | Cap on per-unit finalize-loop re-reviews. Default 1 (one re-review max → 2 peer passes total per unit). 0 disables looping entirely (single-pass behavior). |
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
- `bin/ensemble-build-peer-prompt` — assembles the Outside Voice prompt for peer dispatch (used by step 9g)
- `bin/ensemble-verify-peer-evidence` — mechanical gate at step 9k and step 10. Inspects git trailers; rejects commits without valid peer evidence. Run with `--require-peer-resolution` for destructive / `gated: true` units (peer-skipped is not sufficient).

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
- **Never silently buries low-risk units in higher-risk phases.** Phase-invariant violations reject the plan structurally.
- **Never auto-commits or auto-stashes on Ctrl-C / abort / signal.** No signal-time git operations. WIP commits are user-initiated only via `--commit-wip`.
- **Never invokes `/en-build` recursively.** Recursion guard ensures this.
- **Never commits a unit without peer evidence.** Step 9k runs `bin/ensemble-verify-peer-evidence` after each commit. A unit commit without `peer-resolution:` or `peer-skipped:` trailers is rejected — the agent must either re-run peer review or record a documented skip reason. Destructive and gated units cannot use `peer-skipped:` at all; they require an actual peer pass.
- **Never declares a build "complete" with missing peer evidence.** The end-of-build audit (step 10) runs the same verification across every unit commit on the branch and refuses the success path (`/en-review` → `/en-qa` → `/en-ship`) if any unit fails. Suggests `/en-cross-review` on the failing commits instead.
