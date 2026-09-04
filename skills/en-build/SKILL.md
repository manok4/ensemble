---
name: en-build
description: "Execute an implementation plan unit by unit on a feature branch: implement, test, lint, commit per unit, then one simplify pass and one cross-agent review over the branch diff. Trigger phrases: 'build this plan', 'implement <plan_id>', 'start building', 'execute the plan'."
---


# `/en-build`

> **Running a bundled script.** Anchor every call to this skill's own directory: `SKILL_DIR="<absolute path of the directory containing this SKILL.md>"; bash "$SKILL_DIR/scripts/<name>"`. The trailing `;` is load-bearing. See `references/script-invocation.md`.



Execute a plan, unit by unit. **The host implements every unit** — whichever agent `/en-build` was invoked in writes the code, runs the tests, and makes the commits. The peer agent is never a worker here; it enters once, at the branch-level review in step 10, after `/en-simplify` has run. That is what keeps implementer ≠ reviewer: the review is cross-agent even though the implementation never leaves the host (D52, superseding D35's two flavors and amending D46).

> **Hard preconditions.** A plan in `docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md` (e.g. `EN03-improvement_dashboard-overview.md`; `<PREFIX>` from foundation's `plan_id_prefix`, default `FR`) with `status: open` (or `in_progress` when resuming), all U-IDs present, no unblocked dependencies. The skill verifies these at start. **Recoverable `status: draft`** (verdict `revise` with all findings resolved in `peer_review_resolutions:`) is offered a single finalize-and-build prompt instead of refused.

> **Universal safety gates** (apply on EVERY code path — phasing on/off, `--unit`, `--from`, `--from-phase`, manual resume): every unit with `risk: destructive` or `gated: true` requires explicit confirmation before running. **No flag disables these gates.** See "Universal safety gates" section below.

> **Peer contract.** Severity, confidence, autofix class and the `peer_decision` object are defined once in `references/peer-contract.md`, byte-identical across every skill that exchanges findings. What this skill does with a finding is its own policy.

## Process

1. **Resolve the question tool.** `$QUESTION_TOOL` is `AskUserQuestion` on Claude Code (a deferred tool; preload it via `ToolSearch`) and `request_user_input` on Codex; it is used for the confirmation prompts at 9a. That is all en-build needs from the host: it resolves no peer variables and runs no host-detection script, since D52 it dispatches no peer, and `/en-review` resolves its own at step 10.3.

   **Plugin-install preflight (fail-fast).** Verify the skill's referenced files are accessible — observed failure mode: a partial plugin install that has only `SKILL.md` leaves the agent without the dispatch recipe, and peer review silently degrades to "skipped without recording why." For each of these reference paths, confirm the file exists:

   - `references/severity.md`
   - `references/finding-schema.md`
   - `$SKILL_DIR/scripts/ensemble-verify-peer-evidence`

   If any are missing, **fail at start with a clear error** — do not proceed with a degraded build. Surface the exact paths missing and tell the user to re-run `/en-setup` or sync the plugin.

2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, skip step 10.3's review. The host still implements and commits every unit; only step 10.3's branch-level review is skipped, and the branch records `review-verdict: {"verdict":"skipped","reviewer":"recursion-guard-active",...}` so the step 10.6 audit reads a reason rather than an absence.
3. **Confirm the implementer.** The host implements. There is no flavor choice and no worker dispatch: `/en-build` never hands authoring to another agent, on any host. `/en-review` decides at step 10.3 whether the branch-level review is cross-agent, single-agent fallback, or skipped; nothing about that changes who writes the code.
4. **Load plan and run pre-flight.** Read `<plan-path>`. Verify all U-IDs present and unblocked. Verify each unit has Goal, Files, Approach, Test scenarios, **Risk, Gated** (or fall back to inference for legacy plans without `risk:`).

    **Pre-flight sub-state matrix** — read `peer_review_verdict` and the count of unresolved entries in `peer_review_resolutions:` (an entry is "unresolved" when its `status` is absent or anything other than `applied | deferred | disagreed | superseded`):

    | status | verdict | unresolved findings | git tracked | Pre-flight action |
    |---|---|---|---|---|
    | `open` | `approve` | 0 | yes | Proceed to step 4a |
    | `open` | `approve` | 0 | **no** | Offer auto-commit (one prompt), then proceed |
    | `draft` | `revise` | 0 | yes or no | **Offer finalize-and-build:** one prompt to re-run the peer pass via `/en-plan`'s finalize loop, on `approve` flip to `open`, auto-commit, then proceed |
    | `draft` | `revise` | > 0 | any | Refuse; list the unresolved findings; ask the user to apply/defer/disagree first via `/en-plan --resume` |
    | `open` | `null` | n/a | yes | Proceed (the plan was made with `/en-plan --no-peer`; no peer verdict expected) |
    | `open` | `null` | n/a | **no** | Offer auto-commit, then proceed |
    | `draft` | `null` | n/a | any | Refuse; peer review never ran. Suggest `/en-plan --resume <plan-path>`. |
    | `draft` | `reject` | any | any | Refuse; user must take over. Surface `peer_review_resolutions:` for context. |
    | `completed` / `abandoned` | any | any | any | Refuse |

    **Legacy inference** (plans drafted before the new frontmatter exists, i.e. no `peer_review_verdict` field):

    | Legacy signal | Inferred state |
    |---|---|
    | `status: draft` AND a parseable iteration log shows applied/deferred/disagreed entries | Treat as `peer_review_verdict: revise` + reconstructed `peer_review_resolutions` (best-effort, flagged `inferred: true`); offer finalize-and-build with a legacy notice |
    | `status: draft` AND no iteration log | Treat as `peer_review_verdict: null`; refuse |
    | `status: open` AND no peer-review fields | Treat as `peer_review_verdict: null` AND `/en-plan --no-peer` was the path; accept |
    | `status: open` AND iteration log shows final `verdict: approve` | Treat as `peer_review_verdict: approve`; accept |
    | Any other ambiguous combination | Refuse with a clear instruction to re-run `/en-plan --resume <plan-path>` |

    Recovery prompt (when offering finalize-and-build):

    > Plan is in draft. Findings from the last peer review (verdict: revise) appear to be applied (resolutions: 8 applied, 0 deferred, 0 disagreed). I can finalize now: re-run the peer pass, flip to `open` on approve, and commit the plan. Then proceed with `/en-build`. (y / n / details)

    Declining the offer at the prompt is how you skip it; `--finalize-only` runs finalize and stops without building.

   **4a. Plan-hash baseline.** If `peer_review_plan_hash` is present, record it as the build's baseline; the phase-boundary check will compare against it. If absent (legacy plan), compute one with `$SKILL_DIR/scripts/ensemble-plan-hash <plan-path>` and record it (but skip the boundary check this run; surface a notice). **Always use that helper — never canonicalize the fields yourself**, or the baseline and the boundary check will disagree and refuse a plan nobody edited.

   **4b. Status flip.** If `status: open`, flip to `in_progress` (frontmatter-only edit; plan content is untouched). Already-`in_progress` (resume) leaves status unchanged.
5. **Set up branch.**
   - If on default branch → create `<plan_id>-<slug>` feature branch.
   - If on a feature branch → use it.
   - If working tree is dirty → ask user: stash, commit, or abort.
   - **Worktree** (D28): if user passed `--worktree`, create one at `../<repo>-<plan_id>/` and build in there.
6. **Read context.** Foundation, related plan files (deps from this plan's `related:`), `CLAUDE.md`, `AGENTS.md`, project conventions.
7. **Plan review with user.** Surface concerns: "Plan touches 12 files; some intersect with EN05 (in-flight). Continue, pause, or split?" Address before starting.
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

    User overrides: `--no-phasing` forces off, `--unit U<N>` and `--from U<N>` bypass phasing entirely (universal safety gates still apply per unit — see below).

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
    | `risk: high` AND `build.strict_destructive` | Literal-string confirmation `"run unit U<N>"`. (Skipped when the unit is part of an active P3 phase already group-confirmed via `"run phase 3"`.) |
    | Anything else | No mandatory gate at the unit level. |

    These are the primary safety boundary — and they are deliberately **two narrow categories, nothing more**:
    - **`risk: destructive`** — its own literal-string category, for irreversible data loss.
    - **`gated: true`** — limited **explicitly to production-state-changing actions**: customer-facing feature-flag flips, production data backfills / data mutation, real-side-effect third-party API calls against **production** endpoints, API contract breaks, and production config changes with behavior impact. **Non-production external side effects** (PR/branch automation, issue/comment writes, local workflow or CI-config changes, sandbox/staging API calls, reversible repo operations) are explicitly **NOT** gated — they're covered by the per-unit verification gate (9d) + the post-build review (step 10), not user prompts. (Plan authors and peer review enforce this bar at plan time; `/en-plan`'s template carries the same criteria.)

    Everything outside these two categories advances autonomously. Phase-level prompts (P4 `"run phase 4"`, opt-in `build.pause_between_phases`) are conveniences that group multiple units' confirmations when phasing is active. With phasing off (or `--unit` selecting a destructive unit alone), the unit-level gate fires instead.

    **Preflight gate summary.** Before entering the unit loop (step 9), surface a one-line count so gates are never a surprise mid-build: *"Plan has N gated/destructive units that will pause: U<a> (gated), U<b> (destructive). The remaining M units run autonomously."* If N is 0, say so: *"No gated or destructive units — this plan runs fully autonomously."*

## Agent autonomy contract

`/en-build` is autonomous by design. The user authorized the work at plan time (peer-reviewed plan, `status: open`, hash recorded). After a unit commits successfully (the commit step passes), advance to the next unit immediately. **Do not pause** for confirmation, judgment, "natural checkpoint," "the next unit is bigger," "let me verify before continuing," or any reason not in the seven enumerated cases below.

### Scope of the contract

The contract governs **the inter-unit main loop** — specifically, the window from the START of step 9 (per-unit loop, after preflight has cleared) through the END of step 10 (after all units, before /en-learn hand-off). Within this window, pauses are restricted to the seven cases below.

**Steps 1–8 are NOT governed by this contract.** Preflight, sub-state matrix decisions (untracked-but-approved → offer auto-commit; draft + revise with cleared findings → offer finalize-and-build; unresolved draft findings → refuse and ask for `/en-plan --resume`), host detection, branch setup, plan-review concerns, and batch sizing all have their own documented prompts and protocols. Those are *pre-execution* prompts about whether the build can sensibly start; they're orthogonal to the *during-execution* autonomy this contract enforces.

Why scope this way: the field-observed bug ("Working tree is clean. I stopped at a clean checkpoint before U4") is specifically a post-commit, inter-unit pause inserted by agent judgment. Scoping the contract to that window catches exactly that bug class. Scoping wider would either invalidate legitimate preflight prompts or require an unmaintainable enumeration of every prompt-emitting code path.

### Legitimate pause cases within the contract window (exhaustive within scope, no others permitted)

1. **Working tree dirty at branch setup** (step 5) — stash / commit / abort prompt. *(Out of contract window; listed for completeness — see Scope above.)*
2. **Plan-review concerns surfaced at start** (step 7) — continue / pause / split prompt. *(Out of contract window; listed for completeness.)*
3. **`risk: destructive` unit at step 9a** — typed `"run unit U<N>"` literal-string gate.
4. **`gated: true` unit at step 9a** — y/skip/abort prompt.
5. **P4 phase-level confirmation** (step 9, phasing-on path) — typed `"run phase 4"` literal-string.
6. **`build.pause_between_phases` set** (step 9, opt-in) — between-phase y/pause/n prompt.
7. **Failure protocol fires** (failure-protocol table) — gate failure, peer reject, malformed evidence, hash mismatch, after-phase verification failure, plan-hash drift, etc. Each has its own documented handler.

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
- The branch-level review fails → step 10's review and audit handle it.
- Implementation goes wrong → 9d's verification gate catches it.
- After-phase regression → after-phase verification catches it.

Agent-self-paused checkpoints add no protection on top of these mechanisms — they just add friction that the autonomous-execution design exists to avoid.

If the agent has a real concern that's outside the seven cases AND not caught by failure protocols, the right place to surface it is in the **per-unit progress report after committing** (the commit step's report). The report is informational — it doesn't pause the loop. Example:

```
✓ U3 — feat(api): wrap rotateRefreshToken in singleFlight  [P2 / risk: medium]
  Tests: 7 added, 7 passing | Commit: a3f1b9c (phase: P2)
  Note: U4 touches more files than U3 (12 vs 3). No pause; advancing.
```

`Note:` lines are encouraged when the agent has observations worth surfacing. They don't gate the build.

9. **Phase loop (when phasing is on).** For each phase in `[P1, P2, P3, P4]`:
   - Skip empty phases silently.
   - Surface phase plan to user (units, files, risk summary).
   - **Phase-level mandatory gates** (cannot be bypassed by any flag):
     - If phase == P4: require literal-string `"run phase 4"`. Accepting covers all destructive units in the phase; per-unit destructive gates are NOT re-prompted within P4.
     - If `build.strict_destructive` AND phase == P3: require literal-string `"run phase 3"`. Same group-cover semantics.
   - **Opt-in per-phase pause** (`build.pause_between_phases`, default off): ask y/pause/n. Default behavior is auto-roll into the next phase.
   - For each unit in the phase (dependency order):
     - **9a. Mandatory safety gate (cannot be bypassed by any flag, on any code path).** Before doing ANY work on this unit:
       1. **Classify the unit.** Read its `risk:` field; if absent, run the ordered classifier from step 8a's inference fallback to assign one. Read its `gated:` field (default `false`).
       2. **If `risk: destructive`** AND the active phase has not already been group-confirmed (no `"run phase 4"` accepted for this phase): surface the unit's goal, files, and approach; require typed `"run unit U<N>"` (literal string, verbatim). Any other input → record the unit as `skipped` and advance to the next unit; if the user types `abort`, stop the build per the abort protocol.
       3. **If `gated: true`** (regardless of risk class): surface the unit's goal and approach; require y/skip/abort. **This gate fires even when a phase-level `"run phase 4"` or `"run phase 3"` has been accepted** — gating is per-unit-only and never group-covered. On `skip`: record as `skipped` and continue. On `abort`: stop per the abort protocol.
       4. **If `build.strict_destructive` is set AND `risk: high`** AND the active phase has not been group-confirmed (no `"run phase 3"` accepted): same as step 2 with `"run unit U<N>"`.
       5. Otherwise: proceed to 9b.
       
       This entire sequence runs identically on every code path — phase loop, phasing-off, `--unit U<N>`, `--from U<N>`, `--from-phase`, manual resume. **No flag suppresses it.** The phase-level prompts above (P4 `"run phase 4"`, P3 under `build.strict_destructive`) only group-confirm the *destructive* and *high-risk* gates inside their phase; they never cover `gated: true`, and they never apply on phasing-off paths.
     - **9b. Honor execution note** (test-first / characterization-first / pragmatic).
     - **9c. Implement.** The host writes the code, in this session. No dispatch, no worker, no other agent.

       **First, check whether the unit is already done.** If its `Files` exist with the expected capability, or its `Verification` criteria already pass against the current code, the work landed on a prior branch or an earlier run of this build. Confirm it matches the unit's intent, record it as already-satisfied in the progress report, and move on. **Do not silently reimplement.** `--from U<N>` and `--from-phase P<N>` both resume into work that may already exist, and reimplementing churns a diff the branch-level review then has to read.
     - **9d. Verification gate.** Run unit tests + project lint. Failures → fix before committing (don't commit a broken unit).

       **System-wide check, before calling a feature-bearing unit done.** Unit tests prove the unit's logic; these five questions are about what the unit sits inside. **Skip it entirely for a leaf change** — no callbacks, no persisted state, no parallel interfaces — where the honest answer to all five is "nothing".

       | Ask | What to actually do |
       |---|---|
       | **What fires when this runs?** | Trace two levels out. Read the code, not the docs, for callbacks, middleware, observers, hooks on anything the unit touches. |
       | **Do the tests exercise the real chain?** | If every dependency is mocked, the test proves the logic in isolation and says nothing about the interaction. At least one test should run real objects through the chain. |
       | **Can failure leave orphaned state?** | If state is persisted before a risky call, trace the failure path: does it clean up, and is retry idempotent? |
       | **What other interfaces expose this?** | Grep for the behaviour in sibling classes and alternate entry points. If parity is needed, it belongs in this unit, not a follow-up. |
       | **Do error strategies agree across layers?** | List the error classes each layer raises and rescues. Retry middleware plus an application fallback can double-execute. |

       A "yes" that the unit's tests do not cover is a gap to close here, not a finding to leave for step 10.
     - **9e. Commit.** Conventional subject + U-ID + `phase: P<N>` trailer. **Stage only the unit's own files**, never `git add .`: a bare stage absorbs whatever was already in the index, which on a build that started from a dirty tree silently commits work the user never offered. If the unit needed a file that was already dirty, ask once whether to include or exclude it, and record the answer in the progress report.

       No peer trailers here. Every unit — ordinary, destructive or gated alike — is covered by the branch-level `review-verdict:` written at step 10, so there is no per-unit peer evidence to record and none is required.
   - **After-phase verification.** Run lint, typecheck, and **the tests covering the files this phase touched** — not the full suite. On failure: stop; surface failing tests; offer investigate / commit-as-WIP-via-`--commit-wip` / abort. Do **not** advance to next phase.

     **Why targeted rather than full (D53).** A four-phase build was paying for the full suite at every boundary and again at 10.1, five runs before review had said anything, on an implementation that review was about to change. The full suite runs once, at 10.4, after remediation. The trade is real and worth naming: a phase-3 change that breaks a phase-1 test outside the targeted set now surfaces at 10.4 rather than at the boundary, so the debug window is longer when it happens. Against that, the FR78 build spent 2h48m in full suites and threw away eight of twelve runs.
   - **Plan-hash check.** Re-compute via `$SKILL_DIR/scripts/ensemble-plan-hash <plan-path>` (it covers the immutable plan inputs and excludes the iteration log, per-unit `status` and `peer_review_resolutions`). On mismatch with the build's baseline → refuse to advance; surface that the plan was edited externally during build. (User can re-baseline with `/en-build --re-baseline` after reviewing the diff.)
   - **Working-tree contract.** Verify clean tree, expected feature branch, up to the previous phase's last commit. Any divergence → refuse to advance; surface state.
   - Surface phase summary (units, commits, any gate confirmations the phase required).
   - If `build.pause_between_phases` AND not last phase: ask y/pause/n for next phase. Default: roll forward.

   **Phasing-off path** (phasing disabled by triggers, `--no-phasing`, `--unit U<N>`, `--from U<N>`): same per-unit loop (9a–9e), no phase grouping, no phase-level prompts. Critically, **step 9a runs verbatim** on every selected unit — `--unit U8` against a destructive unit still requires `"run unit U8"` typed literally; `--from U3` against a plan that contains a gated unit still pauses for y/skip/abort on that unit. Commit trailer `phase: P<N>` is still appended based on the unit's classification (so logs stay consistent across phasing-on and phasing-off runs). **Note:** when phasing is off and `--unit`/`--from` builds a subset, the post-build branch-level review (step 10) still runs over the resulting branch diff so ordinary units get their `review-verdict:` coverage.

10. **Post-build phase (branch-level simplify → review → audit → learn).** Runs ONCE after all units commit. This is where every unit gets its code-simplifier and Outside Voice review — at the branch level, not per-unit (D52).

    1. **Cheap gate: lint + typecheck only.** Seconds, not minutes. It catches syntax and type breakage before simplify and review spend time on code that cannot compile. **The full suite does not run here** — it runs once, at 10.4, after review findings have been applied. Running it first is how a build pays for the full suite three times: once now, once after simplify, once after remediation, on an implementation that was still changing (D53).
    2. **Code-simplification pass** — invoke `/en-simplify` on the branch diff (`git diff <merge-base>..HEAD`). Skip on docs-only or trivial (<~10 changed lines) branches, or with `--no-simplify`. It leaves changes in the working tree (does not commit).
    3. **Branch-level Outside Voice review (cross-agent required; host personas additive).** **Invoke `/en-review --cross --mode headless --base <merge-base>`** over the branch diff — or `--peer` in place of `--cross` when `--review peer` was passed. `--cross` is the default and the reason is D46: the personas are where project context and plan alignment show up, and a review whose subject is "did this branch implement this plan" is a strange place to drop them.

       The cross-agent peer is **mandatory** here and carries the implementer ≠ reviewer property: the host just implemented every ordinary unit, so an independent architecture must review it (Claude host → Codex reviews; Codex host → Claude reviews — D23). The **host personas run alongside it** (D46, superseding this step's former `--peer-only`): they are *fresh-context* sub-agents that never saw the implementing reasoning, so they do not weaken the cross-agent property, and `--peer-only` was discarding every **host-only** finding — precisely the standards / testing / maintainability categories where project context and plan alignment matter most in a build.

       en-review returns the findings envelope with a `reviewer` field (`cross-agent` normally; `single-agent-fallback` / `en-review-host-fallback` when no peer) plus `reconciliation[]` buckets. **`reviewer` still records whether the CROSS-AGENT property held**, not how many personas contributed — that is what the step 10.6 audit gates on, so its meaning is unchanged. **Host applies** eligible findings per `references/severity.md` (the P0-P3 grades and the wire shape they arrive in are the shared contract in `references/peer-contract.md`) (auto-apply `safe_auto`; surface P0-disagreements / high-confidence security or architecture findings); **`conflicting` findings are never auto-applied**. Prefer `corroborated` findings when triaging: host and peer agreeing independently is the strongest signal available. **Apply every finding in one batch, then verify once.** Fix-verify-fix-verify is what turns a 30-minute review into a two-hour one: each cycle pays a full suite for a partial fix. Collect the applications, make them together, and let 10.4's single suite prove them. Skip entirely with `--review none` (records the branch as review-skipped). The flag is named for what it does: it skips this step, personas included. It is **not** "run the review without the peer" — that case needs no flag, because when `PEER_AVAILABLE=false` en-review runs its host personas anyway and records `reviewer: single-agent-fallback` or `en-review-host-fallback`, which the audit accepts as `branch_review_pass: fallback_completed`. The peer machinery lives in en-review (one implementation), not duplicated here.
    4. **The full suite, once.** Now that simplify and review have both landed and their findings are applied, run the project's full test suite, lint and typecheck. **This is the only full-suite run in the post-build phase**, and on a build with phasing it is the only one after the last phase boundary. On failure: stop; surface; offer investigate / `--commit-wip` / abort.

       **On success, write a verification receipt.** `bash "$SKILL_DIR/scripts/ensemble-verification-receipt" write --check full_suite=passed --check lint=passed --check typecheck=passed --base origin/<default-branch> --by en-build`, plus a `--dep <path>` for each lockfile the project has. This is the layer that just paid for the expensive run, so it is the layer that records it: `/en-ship` and a project's pre-push hook can then skip what this proved, instead of re-running it minutes later on the identical tree.

       **Only on a passing suite, and never fatal.** A receipt is evidence something succeeded, not a log that it ran, so a failed suite leaves none behind. If the write itself fails, warn and carry on — the receipt is an optimisation, and a build that fails because it could not record an optimisation has turned a saving into a liability.

       **Do not interrupt a running suite.** Bound it with the project's own timeout if it has one, and otherwise let it finish. A suite that looks stalled is reported, not killed and retried: in the FR78 build eight of twelve launches were interrupted before producing a result, which is where most of its 2h48m of suite time went. If a run genuinely exceeds what the project expects, say so with the elapsed time and let the user decide — a suite slow enough to look hung is a finding about the project, not a reason to guess again.

       **Report the elapsed time in the summary.** A full suite over ~10 minutes is worth the user knowing about; sharding it is their call, and they cannot make it if the number is never surfaced.

    5. **Commit the simplify + review changes** (if any) with **both** a `review-verdict:` trailer AND a `simplify-verdict:` trailer (EN07 - the simplify pass is now auditable evidence, not prose). If steps 2–3 produced no working-tree changes, create an empty commit (`--allow-empty`) carrying **both** trailers so the branch records both passes.

       **Trailer schemas.** These two are the branch's whole evidence record, so they live here rather than in a reference:

       - **`review-verdict:`** — one per post-build review commit. Required keys: `verdict` (`approve`/`revise`/`reject`), `reviewer` (`cross-agent` normally; `single-agent-fallback` / `en-review-host-fallback` when the cross-agent peer was unavailable — the value IS the recorded reason a fallback was used, and it records which fallback), `mode`, `units_covered` (JSON array of **every U-ID built this run**), `findings_count`. A unit counts as reviewed when its U-ID appears in some `review-verdict.units_covered` on the branch. A fallback `reviewer` maps to `branch_review_pass: fallback_completed` — valid, because the field records why the cross-agent peer was not used.
       - **`simplify-verdict:`** (EN07) — emitted on the **same** commit, so the `/en-simplify` pass is auditable rather than prose. Required keys: `outcome` (`completed` / `not_applicable` / `failed`), `reason` (non-empty and REQUIRED when `not_applicable` or `failed`: `docs-only`, `trivial:<10-lines`, `--no-simplify`, or the gate regression that reverted it), `findings_count`, `units_covered`. **`--no-simplify` records `{"outcome":"not_applicable","reason":"--no-simplify",...}` explicitly — a visible, recorded opt-out, never silence.** A **missing** `simplify-verdict:` trailer is NOT a legitimate skip; the audit treats it as `missing` and fails. **`--review none`** likewise records the branch review as a loud, recorded skip (`branch_review_pass: missing`, and the audit fails) — never a silent pass.

       ```
       review-verdict: {"verdict":"approve","reviewer":"cross-agent","mode":"headless","units_covered":["U1","U2","U3"],"findings_count":1}
       simplify-verdict: {"outcome":"completed","reason":"","findings_count":2,"units_covered":["U1","U2","U3"]}
       ```

       `ensemble-verify-peer-evidence --branch-coverage <range> --require-simplify` derives `simplify_pass` and `branch_review_pass` from these and fails when either is `missing`/`failed`. Trailers rather than sidecar files because `git interpret-trailers --parse` and `git log --grep` are stable and scriptable.
    6. **End-of-build evidence audit (mandatory, mechanical).** Compute branch-level coverage once, **with the simplify+review gate**: `$SKILL_DIR/scripts/ensemble-verify-peer-evidence --branch-coverage <merge-base>..HEAD --require-simplify --json` → `covered_units`, plus the two derived outcome fields **`simplify_pass`** (`completed | not_applicable | failed | missing`) and **`branch_review_pass`** (`completed | fallback_completed | failed | missing`). The `--require-simplify` flag makes the command **exit non-zero** when `simplify_pass` is `missing`/`failed` or `branch_review_pass` is `missing`/`failed` - so a skipped `/en-simplify` (with no recorded `not_applicable`) or an unrun/unrecorded branch review fails the audit here, not silently. Then confirm every plan U-ID appears in `covered_units`. There is no per-unit evidence path any more: the host implements every unit and one branch-level review covers all of them, so a U-ID missing from `covered_units` is a genuine gap rather than a unit that took the other route. **Surface a per-unit table plus the two gate lines in the summary**:

      ```
      Evidence audit — FR07-auth-rotation (5 units)
        ✓ U1 — branch-level review-verdict (approve, covered)
        ✓ U2 — branch-level review-verdict (approve, covered)
        ✓ U3 — branch-level review-verdict (revise→applied, covered)
        ✓ U4 — branch-level review-verdict (revise→applied, covered)  [gated:true]
        ✓ U5 — branch-level review-verdict (approve, covered)

      simplify_pass: completed
      branch_review_pass: completed
      Audit verdict: ok (5/5 units covered by the branch-level review; simplify + review gated)
      ```

      **Each gate line carries its reason when it is anything but `completed`** — `simplify_pass: not_applicable (build config: simplifier off)` reads as loudly as `(--no-simplify)`. A policy set once in `.ensemble/config.local.yaml` and forgotten must be as visible here as a flag typed this morning; that is the whole reason it is safe to move standing policy out of the flag surface.

      **The two gate lines are mandatory in every build summary** (the human-visible echo of the durable `simplify-verdict:` / `review-verdict:` trailers). A `simplify_pass`/`branch_review_pass` of `missing` or `failed` makes the audit verdict `failed` even when every U-ID is covered - a skipped simplify or an unrecorded review is a build defect, not a clean finish.

      A unit fails verification when it is not in `covered_units`. Then the audit verdict is `failed`:

      ```
      ⚠️  Evidence audit FAILED. The following units lack valid evidence:
        ✗ U10 — not in branch-level coverage
        ✗ U13 — not in branch-level coverage

      simplify_pass: missing        ← no simplify-verdict trailer on the branch
      branch_review_pass: completed

      The branch-level review did not cover these units, or the simplify/review
      gate failed (simplify_pass / branch_review_pass is missing or failed).
      Do NOT merge until resolved: re-run the post-build simplify + review
      (`/en-build --from <U-ID>`), or `/en-review --peer <sha>` on them.
      ```

      The audit surfaces, but does NOT auto-revert — the user decides. If the audit fails **for any reason** (uncovered unit, or a `missing`/`failed` `simplify_pass` / `branch_review_pass`), the suggested next step changes from `/en-review → /en-qa → /en-ship` to `/en-review --peer <sha>` on the failing units, then re-audit - the success path is **blocked** until the audit passes.

    - Summary: completion status per U-ID, deviations, branch-level simplifier + review verdict. Per-phase summary if phasing was on.
    - **Learning checkpoint** (structured, non-droppable - A3, D26). **The SOLE learning-capture point in the lifecycle** — it fires here, at the very end of the post-build phase (after the branch-level simplify + Outside Voice review + evidence audit above), so capture reflects the *fully reviewed* build. `/en-qa` and `/en-ship` no longer prompt for learnings (removed by the EN04 follow-up); if you don't run `/en-build`, there is no learning checkpoint. It emits a visible `learning_checkpoint:` outcome line in the build summary, so the capture decision can never be silently dropped under context pressure.
      1. **Deferral guard.** **Defer** the checkpoint whenever the peer-evidence audit failed (the end-of-build audit at step 10.6) - do not fire it on a build with missing evidence. This covers an uncovered unit **and (EN07) a `simplify_pass` or `branch_review_pass` of `missing`/`failed`** - a skipped `/en-simplify` or an unrun/unrecorded branch review blocks the learning checkpoint exactly as a missing review-verdict does. Surface a one-line note that the learning checkpoint is deferred (name which gate failed) and skip the rest. This emits **no** `learning_checkpoint:` outcome value - the checkpoint did not run, so none of the four canonical outcomes applies.
      2. **CI short-circuit.** If `CI=true`, record `learning_checkpoint: ci_environment` in the build summary; skip the prompt (no interactive prompt in CI).
      3. **Determine the capture baseline.** Read `docs/learnings/log.md`; find the latest `## [YYYY-MM-DD] capture | <subject> | <head-sha>` entry. If a `<head-sha>` is present, baseline = that SHA (`git log <sha>..HEAD`). Legacy entry without a SHA → one-line imprecise-baseline notice + `git log --since=<date>` fallback. No capture entries at all → baseline = `git merge-base HEAD <default-branch>` (since branch creation).
      4. **Idempotency check.** If the scope is zero commits since the last capture, record `learning_checkpoint: up_to_date` and skip the prompt silently.
      5. **Surface the checkpoint prompt** (structured, not a soft prompt):
         ```
         Learning checkpoint
         ───────────────────
         <N> commits since last /en-learn capture (<baseline date or "branch creation">).
         Diff: <X> files changed, <Y> lines.
         Recent commits touch: <comma-separated areas from changed files>

         Worth filing learnings from this build? (yes / skip / details)
         ```
      6. **Handle response.** `yes` → invoke `/en-learn capture`; record `learning_checkpoint: captured (<N> learnings)`. `skip` → record `learning_checkpoint: intentionally_skipped` (auditable). `details` → print the commit list + per-area summary; re-prompt.
      7. **Policy override.** `build.learning_checkpoint: false` skips the whole step (records `learning_checkpoint: intentionally_skipped (--no-learning-checkpoint flag)`).

      The four canonical outcome values are `captured (N learnings)` / `intentionally_skipped` / `up_to_date` / `ci_environment` (never the bare word `skipped`). This step fires at the `/en-learn` hand-off - after step 10's audit, **outside** the inter-unit autonomy-contract window - so it is a legitimate terminal checkpoint, not an inserted inter-unit pause.
    - Suggest next: `/en-review` → `/en-qa` → `/en-ship` — but only if the audit passed. Otherwise: `/en-review --peer <sha>` on the failing commits.

## Flags

| Flag | Effect |
|---|---|
| `--no-simplify` | Skip the post-build code-simplification pass (step 10.2). Records `simplify-verdict: {"outcome":"not_applicable","reason":"--no-simplify",...}` - a visible, recorded opt-out that passes the audit, never a silent skip. |
| `--review cross\|peer\|none` | What runs at 10.3. **Default `cross`** — peer plus host personas, per D46, because the standards / testing / maintainability findings depend on project context this build has. **`peer`** runs the peer alone: cheaper and faster, and the right call when you want an independent read without the roster; the peer is mandatory either way and `review-verdict.reviewer` still records whether the cross-agent property held, so the audit is unaffected. **`none`** skips 10.3 **entirely**, peer and personas both — the branch records as review-skipped, the audit reports `branch_review_pass: missing` and FAILS. Since D52 this is the build's only review, so `none` leaves every unit unreviewed, destructive ones included. |
| `--unit U<N>` | Build only the named unit; don't auto-advance. Universal safety gates still apply. |
| `--no-phasing` | Force phasing off for this run (universal safety gates still fire per unit). No `--phasing` counterpart: phasing turns on from six triggers, and when none fired the plan is small enough not to need it. |
| `--dry-run` | Show what would happen; don't write or commit |
| `--from U<N>` | Resume from a specific unit (skip earlier ones). Universal safety gates still apply per unit. |
| `--from-phase P<N>` | Resume at phase N. Verifies prior phases' commits and a clean working tree before starting. |
| `--finalize-only` | Run finalize loop and stop without building. |
| `--commit-wip` | After a stopped run (Ctrl-C, gate-failure, etc.), create a `wip/<plan_id>-phase<N>` branch and commit current state. Explicit user invocation only — never automatic. |
| `--re-baseline` | After reviewing an external plan-file diff, accept the new state as the build's baseline `peer_review_plan_hash`. |

**One decision, one flag.** The review decision has three answers, so it is one flag with three values rather than `--review` plus a separate `--no-review` — two flags for one question leave `--review peer --no-review` with no defined meaning. `--no-simplify` is not the same shape: simplify and review are separate passes, and a `--simplify none` would imply a `--simplify` variant that does not exist.

**Standing policy lives in `.ensemble/config.local.yaml`, not here** — `build.worktree`, `build.strict_destructive`, `build.pause_between_phases`, `build.learning_checkpoint`. A flag is for what changes run to run; a project either works in worktrees or it doesn't. Config-set skips are surfaced in the step 10.6 audit exactly like flag-set ones, so a policy set once and forgotten is as visible in the build summary as a flag typed today.

**No flag disables universal safety gates.** Every flag changes phasing, pacing, or selection; none turn off destructive / gated confirmations.

## Cross-review

**Once per build, at step 10.3, after `/en-simplify`.** The peer never reviews a unit in flight and never implements one. `/en-build` invokes `/en-review --cross --mode headless` over the branch diff; the resulting `review-verdict:` trailer is the evidence for every unit on the branch.

Skipped only by `--review none`, which records the branch as review-skipped and makes the step 10.6 audit report `branch_review_pass: missing`. There is no per-unit skip enum any more, because there is no per-unit pass to skip.

Which reviewer ran is `/en-review`'s resolution, not en-build's; it comes back in the envelope's `reviewer` field and lands in the `review-verdict:` trailer.

## Code simplification

**Once per build, at step 10.2, over the branch diff** — not per unit. `/en-build` invokes `/en-simplify`; it owns the dimensions, the revert protocol, and its own agent. en-build owns only the outcome: a `simplify-verdict:` trailer on the post-build commit.

Skipped on a docs-only or trivial branch, or by `--no-simplify`. Either way the skip is recorded as `outcome: not_applicable` with a reason, so the audit reads a decision rather than an absence.

## Per-unit progress report

After each unit commits, surface a one-line summary:

```
✓ U3 — feat(auth): wrap rotateRefreshToken in singleFlight  [P2 / risk: medium]
  Tests: 7 added, 7 passing | Commit: a3f1b9c (trailer: phase: P2)
```

Simplify and review results appear once, in the final summary: they run over the branch, not per unit.

## Final summary

After all units complete:

```
Build summary — FR07-auth-rotation (5 units)

✓ U1: Add singleFlight helper (feat: 12 files, 4 tests)
✓ U2: Wire Redis connection (feat: 3 files)
✓ U3: Wrap rotateRefreshToken (feat: 2 files, 3 tests)
✓ U4: Migration for refresh_token_rotated_at (feat: 1 file) [gated]
✓ U5: Update test coverage (test: 6 files, 12 tests)

Full suite: 247 passing, 0 failing.
Lint: clean.
Typecheck: clean.

Code-simplifier: branch diff; 7 file changes.
Review: --cross, cross-agent (codex). Found 11 — P0:1 P1:3 P2:5 P3:2. Addressed 6 (1 P0, 3 P1, 2 P2), deferred 4 to tech-debt-tracker (TD11-TD14), disagreed 1.
simplify_pass: completed
branch_review_pass: completed
learning_checkpoint: captured (2 learnings)
```

**The `Review:` line is mandatory and carries both halves.** *Found*, broken down by severity, and *addressed*, broken down the same way — a review that found eleven things and addressed six is a different outcome from one that found six and addressed six, and a line reporting only the second is unreadable as either. Deferred findings name their TD IDs so the paper trail is followable from the summary; disagreed ones are counted so a silent drop is visible as a number. Where the review was skipped or fell back, this line says which and why, in place of the counts.

The `simplify_pass:` and `branch_review_pass:` lines are **mandatory** (EN07) - they echo the durable `simplify-verdict:` / `review-verdict:` trailers so a skipped simplify or an unrecorded review can never read as a clean finish. A `missing`/`failed` value on either blocks the learning checkpoint and the ship hand-off.

## Reference files

- `references/finding-schema.md` — shape of the findings envelope `/en-review` returns
- `references/severity.md` — apply / defer / disagree routing
- `references/recursion-guard.md` — ENSEMBLE_PEER_REVIEW env var
- `references/stable-ids.md` — U-ID stability rules
- `$SKILL_DIR/scripts/ensemble-verify-peer-evidence` — mechanical gate at step 10.6's audit. Run with `--branch-coverage <range> --require-simplify`: it enumerates the U-IDs covered by the branch's `review-verdict:` trailers and derives `simplify_pass` / `branch_review_pass`. Its `--require-peer-resolution` mode reads the per-unit trailers of branches built before D52 and is not used here.

## Failure protocol

| Failure | Behavior |
|---|---|
| Plan has unmet dependency (`Depends: U7` but U7 not present) | Stop; surface; suggest plan revision |
| Unit needs files outside its `Files` list | **Stop before making the change.** Name what the unit needs and why the listed scope cannot deliver it, then ask: widen this unit, split the work into a new one, or abort. Do not quietly widen — the `Files` list is what the plan was reviewed against, and silent sprawl is invisible until step 10 reads a diff nobody scoped. |
| Unit's `Approach` is too thin to implement | Stop and ask. Pre-flight checks the field is present, not that it is sufficient, and a guessed interpretation of a thin unit is the expensive kind of wrong: it passes tests written to match the guess. |
| Plan structure violates phase invariant (low-risk depends on higher-risk) | Reject the plan with three remediation options: remove the dependency, promote the unit's `risk:`, or split the unit. Never silently bury units across phases. |
| Plan in `status: draft` with unresolved `peer_review_resolutions:` | Refuse build; list unresolved findings; suggest `/en-plan --resume`. |
| Plan in `status: draft + revise` with all resolutions cleared | Offer finalize-and-build single prompt (recovery flow). On y, run `/en-plan` finalize loop, flip to `open`, commit, then proceed. |
| Plan untracked in git but `status: open` and verdict cleared | Offer auto-commit single prompt; on y, commit and proceed. |
| Plan-hash mismatch at phase boundary | Refuse to advance; surface that immutable plan-input fields changed during build; ask user to re-baseline (`--re-baseline`) or abort. |
| Unit verification fails (9d) | Fix and re-run. **After two failed attempts on the same unit, stop** — show the test output and ask: retry, skip the unit, or abort. Guessing a third time is how a unit gets "fixed" by weakening its test. |
| After-phase verification fails (targeted tests / lint / typecheck) | Stop. Do not advance to next phase. Surface failing tests; offer investigate / `--commit-wip` / abort. |
| Branch-level review verdict = `reject` | Pause and surface to the user before the post-build commit; never proceed to the audit as if approved |
| Peer subprocess attempts to modify files (D30 violation) | Detect via git status; revert; do not trust this round of findings; log violation |
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
- **Never lets another agent write the code.** The host implements every unit, on every host. There is no worker dispatch and no flavor that hands authoring away. The peer enters once, at step 10.3, after `/en-simplify`, through `/en-review --cross`.
- **Never commits outside the unit's files.** Staging is path-limited to the unit's own paths; `git add .` is forbidden, because a bare stage absorbs whatever the user already had in the index.
- **Never declares a build "complete" with missing review evidence.** The end-of-build audit (step 10.6) confirms every plan U-ID is covered by the branch-level `review-verdict:`, and that `simplify_pass` and `branch_review_pass` both recorded. It refuses the success path (`/en-review` → `/en-qa` → `/en-ship`) if any is missing, and suggests `/en-review --peer <sha>` on the failing commits instead.
