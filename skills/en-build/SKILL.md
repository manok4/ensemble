---
name: en-build
description: "Execute an implementation plan unit by unit on a feature branch: implement, test, lint, commit per unit, then one simplify pass and one cross-agent review over the branch diff. Trigger phrases: 'build this plan', 'implement <plan_id>', 'start building', 'execute the plan'."
---


# `/en-build`

> **Running a bundled script.** Anchor every call to this skill's own directory: `SKILL_DIR="<absolute path of the directory containing this SKILL.md>"; bash "$SKILL_DIR/scripts/<name>"`. The trailing `;` is load-bearing. See `references/script-invocation.md`.



Execute a plan, unit by unit. **The host implements every unit**: the agent `/en-build` runs in writes the code, runs the tests, makes the commits. The peer is never a worker here; it enters once, at the branch-level review in step 10, after `/en-simplify` has run. That is what keeps implementer ≠ reviewer (D52).

> **Hard preconditions.** A plan in `docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md` (e.g. `EN03-improvement_dashboard-overview.md`; `<PREFIX>` from foundation's `plan_id_prefix`, default `FR`) with `status: open` (or `in_progress` when resuming), all U-IDs present, no unblocked dependencies. The skill verifies these at start. **Recoverable `status: draft`** (verdict `revise` with all findings resolved in `peer_review_resolutions:`) is offered a single finalize-and-build prompt instead of refused.

> **Universal safety gates** (apply on EVERY code path — phasing on/off, `--unit`, `--from`, `--from-phase`, manual resume): every unit with `risk: destructive` or `gated: true` requires explicit confirmation before running. **No flag disables these gates.** See "Universal safety gates" section below.

> **Peer contract.** Severity, confidence, autofix class and the `peer_decision` object are defined once in `references/peer-contract.md`, byte-identical across every skill that exchanges findings. What this skill does with a finding is its own policy.

## Process

1. **Resolve the question tool.** `$QUESTION_TOOL` is `AskUserQuestion` on Claude Code (a deferred tool; preload it via `ToolSearch`) and `request_user_input` on Codex, for the confirmation prompts at 9a. That is all en-build needs from the host: it resolves no peer variables and runs no host-detection script.

   **Payload check, fail-fast.** Confirm the files `references/build-preflight.md` lists are present. Any missing → **fail at start with a clear error**, naming the paths, and tell the user to re-run `/en-setup` or sync the plugin. A degraded build is never started.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, skip step 10.3's review and record `review-verdict: {"verdict":"skipped","reviewer":"recursion-guard-active",...}`, so the step 10.6 audit reads a reason rather than an absence. Every unit is still implemented and committed.
3. **Confirm the implementer.** The host, on any host: `/en-build` never hands authoring to another agent. `/en-review` decides at step 10.3 whether the branch-level review is cross-agent, single-agent fallback, or skipped; that never changes who writes the code.
4. **Load plan and run pre-flight.** Read `<plan-path>`. Verify all U-IDs present and unblocked, and each unit carrying Goal, Files, Approach, Test scenarios, **Risk, Gated**. **Then resolve the plan's state against the pre-flight sub-state matrix in `references/build-preflight.md`**, which owns every buildable and refused combination and the recovery prompt. It returns one of four:

   | Outcome | When |
   |---|---|
   | Proceed | `status: open`, verdict `approve` or `null`, no unresolved findings, plan tracked |
   | Offer auto-commit, then proceed | the same, but the plan file is untracked |
   | Offer finalize-and-build (one prompt) | `status: draft` + verdict `revise` with every finding resolved |
   | **Refuse** | unresolved draft findings, no verdict, `reject`, `completed`, `abandoned` |

   Declining at a prompt is how you skip it; `--finalize-only` runs the finalize and stops without building. A plan with no `peer_review_verdict` field at all is a legacy plan: `references/build-legacy-plans.md` owns its inference and may refuse.

   **4a. Plan-hash baseline.** Record `peer_review_plan_hash` as the build's baseline for the phase-boundary check. Absent (legacy plan) → compute one with `$SKILL_DIR/scripts/ensemble-plan-hash <plan-path>`, record it, skip the boundary check this run, surface a notice. **Always that helper, never your own canonicalization**, or the baseline and the check will disagree and refuse a plan nobody edited.

   **4b. Status flip.** If `status: open`, flip to `in_progress` (frontmatter-only edit; plan content is untouched). Already-`in_progress` (resume) leaves status unchanged.

   **4c. Start the run ledger.** `METRICS=$(bash "$SKILL_DIR/scripts/ensemble-run-metrics" start --plan <plan_id>)`, then record at the call points in `references/run-metrics.md`: unit and phase start/end, every full-suite run, and the review pass. Fire-and-forget: it never blocks a build (D106).
5. **Set up branch.**
   - If on default branch → create `<plan_id>-<slug>` feature branch.
   - If on a feature branch → use it.
   - If working tree is dirty → ask user: stash, commit, or abort.
   - **Worktree** (D28): if user passed `--worktree`, create one at `../<repo>-<plan_id>/` and build in there.
6. **Read context, bounded.** In one message, `AGENTS.md`, `CLAUDE.md`, project conventions, and the plans this plan names in `related:`; none depends on another's result. From `docs/foundation.md` read the frontmatter, then `grep -n '^#' docs/foundation.md` for the section index, then only the Functional Requirements entries for the R-IDs in the plan's `covers_requirements`. **Never read it whole**; the plan already carries the approach and file list the build needs.
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

    **Inference fallback** (a legacy plan whose units lack `risk:`): read `references/build-legacy-plans.md`, which owns the ordered classifier (destructive patterns first, then migrations, backfills, read-only paths, then `medium`) and the confirmation it surfaces before the build proceeds on inferred classes.

    **Dependency-vs-phase invariant.** For every dependency edge `U → V`, verify `phase(V) <= phase(U)`. If a low-risk unit depends on a higher-risk unit (so `phase(V) > phase(U)`), **reject the plan as a structural error** with three remediation options (remove the dependency, promote `U.risk:`, or split `U`). Never silently bury the unit in a higher phase: it would land after a confirmation typed for destructive work.

8b. **Universal safety gates** (apply on EVERY execution path — phasing on/off, `--unit`, `--from`, `--from-phase`, manual resume; **no flag disables them**):

    For every unit selected for execution, classify it (using `risk:` or the ordered inference fallback) and enforce:

    | Classification | Gate |
    |---|---|
    | `risk: destructive` | Literal-string confirmation `"run unit U<N>"` typed verbatim, with goal/files/approach surfaced first. (When the unit is part of an active P4 phase already group-confirmed via `"run phase 4"`, this per-unit gate is skipped — see step 9.) |
    | `gated: true` | y/skip/abort confirmation, with goal and approach surfaced first. (Always per-unit; never group-confirmed.) |
    | `risk: high` AND `build.strict_destructive` | Literal-string confirmation `"run unit U<N>"`. (Skipped when the unit is part of an active P3 phase already group-confirmed via `"run phase 3"`.) |
    | Anything else | No mandatory gate at the unit level. |

    The primary safety boundary, deliberately **two narrow categories, nothing more**:
    - **`risk: destructive`** — its own literal-string category, for irreversible data loss.
    - **`gated: true`** — limited **explicitly to production-state-changing actions**: customer-facing feature-flag flips, production data backfills / data mutation, real-side-effect third-party API calls against **production** endpoints, API contract breaks, and production config changes with behavior impact. **Non-production external side effects** (PR/branch automation, issue/comment writes, local workflow or CI-config changes, sandbox/staging API calls, reversible repo operations) are explicitly **NOT** gated: 9d's verification gate and step 10's review cover them, not user prompts.

    Everything outside these two categories advances autonomously. Phase-level prompts (P4 `"run phase 4"`, opt-in `build.pause_between_phases`) are conveniences that group multiple units' confirmations when phasing is active. With phasing off (or `--unit` selecting a destructive unit alone), the unit-level gate fires instead.

    **Preflight gate summary.** Before entering the unit loop (step 9), surface a one-line count so gates are never a surprise mid-build: *"Plan has N gated/destructive units that will pause: U<a> (gated), U<b> (destructive). The remaining M units run autonomously."* If N is 0, say so: *"No gated or destructive units — this plan runs fully autonomously."*

## Agent autonomy contract

`/en-build` is autonomous by design. The user authorized the work at plan time (peer-reviewed plan, `status: open`, hash recorded). After a unit commits successfully (the commit step passes), advance to the next unit immediately. **Do not pause** for confirmation, judgment, "natural checkpoint," "the next unit is bigger," "let me verify before continuing," or any reason not in the seven enumerated cases below.

### Scope of the contract

The contract governs **the inter-unit main loop** — specifically, the window from the START of step 9 (per-unit loop, after preflight has cleared) through the END of step 10 (after all units, before /en-learn hand-off). Within this window, pauses are restricted to the seven cases below.

**Steps 1–8 are NOT governed by this contract.** Preflight, the sub-state matrix, branch setup, plan-review concerns and batch sizing have their own prompts. Those are *pre-execution*, about whether the build can sensibly start, and orthogonal to the *during-execution* autonomy enforced here.

### Legitimate pause cases within the contract window (exhaustive within scope, no others permitted)

1. **Working tree dirty at branch setup** (step 5) — stash / commit / abort prompt. *(outside the window)*
2. **Plan-review concerns surfaced at start** (step 7) — continue / pause / split prompt. *(outside the window)*
3. **`risk: destructive` unit at step 9a** — typed `"run unit U<N>"` literal-string gate.
4. **`gated: true` unit at step 9a** — y/skip/abort prompt.
5. **P4 phase-level confirmation** (step 9, phasing-on path) — typed `"run phase 4"` literal-string.
6. **`build.pause_between_phases` set** (step 9, opt-in) — between-phase y/pause/n prompt.
7. **Failure protocol fires** (failure-protocol table) — gate failure, peer reject, malformed evidence, hash mismatch, after-phase verification failure, plan-hash drift, etc. Each has its own documented handler.

### Anti-patterns (explicitly forbidden)

- **Agent-initiated "checkpoint before bigger unit" pauses.** The plan was authored and peer-reviewed; unit complexity is not re-evaluated at execution time.
- **"Working tree is clean, paused for confirmation" between non-gated units.** A clean tree is the *expected* state between units.
- **"Should I continue?" preambles and "Let me verify with the user before …"** outside the seven cases. The user authorized the plan; a per-unit pause bypasses that authorization.

### Right response to LLM uncertainty: advance, not ask

Uncertainty is not a pause case: **continue per the contract**; the verification gates and failure protocols are the safety net, and a self-inserted checkpoint adds friction, not protection. A real concern outside the seven cases goes in the **per-unit progress report after committing**, as a `Note:` line. The report is informational and does not gate the build.

9. **Phase loop (when phasing is on).** For each phase in `[P1, P2, P3, P4]`:
   - Skip empty phases silently.
   - Surface phase plan to user (units, files, risk summary).
   - **Phase-level mandatory gates** (cannot be bypassed by any flag):
     - If phase == P4: require literal-string `"run phase 4"`. Accepting covers all destructive units in the phase; per-unit destructive gates are NOT re-prompted within P4.
     - If `build.strict_destructive` AND phase == P3: require literal-string `"run phase 3"`. Same group-cover semantics.
   - **Opt-in per-phase pause** (`build.pause_between_phases`, default off): ask y/pause/n. Default behavior is auto-roll into the next phase.
   - For each unit in the phase (dependency order):
     - **9a. Mandatory safety gate (cannot be bypassed by any flag, on any code path).** Classify the unit (`risk:`, or the ordered classifier when absent; `gated:` defaults to `false`) and apply the 8b table before doing any work, surfacing goal, files and approach first. A phase already group-confirmed by `"run phase 3"` / `"run phase 4"` covers its units' typed gates; `gated: true` is never group-covered. Any other input at a typed gate records the unit `skipped` and advances; `abort` stops the build per the abort protocol. Identical on the phase loop, phasing-off, `--unit U<N>`, `--from U<N>`, `--from-phase` and manual resume; **no flag suppresses it**.
     - **9b. Honor execution note** (test-first / characterization-first / pragmatic).
     - **9c. Implement.** The host writes the code, in this session. No dispatch, no worker, no other agent. Say in one line which unit is starting and its goal before the first edit. Edit files surgically; rewrite one only when it is short or most of it changes. **The unit's scope is the deliverable.** A pre-existing bug, a performance concern or behaviour the unit does not mention is a `Note:` in the progress report and a follow-up, not a fix in this unit, unless the unit's own behaviour cannot work without it. Commit tests the unit's `Test scenarios` call for, sized like the neighbouring test files; scratch checks are not kept.

       **First, check whether the unit is already done.** If its `Files` exist with the expected capability, or its `Verification` criteria already pass against the current code, the work landed on a prior branch or an earlier run of this build. Confirm it matches the unit's intent, record it as already-satisfied in the progress report, and move on. **Do not silently reimplement.** `--from U<N>` and `--from-phase P<N>` both resume into work that may already exist.
     - **9d. Verification gate.** One call, not a sequence: `bash "$SKILL_DIR/scripts/ensemble-unit-verify" --unit U<N> --working --prefer-full-when-cheap --cheap-seconds 120`. It resolves the unit's tests through `$SKILL_DIR/scripts/ensemble-test-select`, runs lint, typecheck and that selection, writes every byte to a log under `.git/ensemble/runs/`, and prints one line per check plus the tail of whatever failed. A test file the unit just wrote selects itself, so a unit that ships tests is covered without the project declaring anything. **Read the exit code, it is the gate:** `0` green; `1` a check failed, fix it before committing; `3` the selection was empty, so name the unit's tests yourself and run them (zero tests found is a finding about the project, never a pass); `4` AGENTS.md declares no commands, so verify by hand and say so in the progress report.

       **System-wide check, before calling a feature-bearing unit done.** Unit tests prove the unit's logic; these five questions are about what the unit sits inside. **Skip it entirely for a leaf change** — no callbacks, no persisted state, no parallel interfaces — where the honest answer to all five is "nothing".

       | Ask | What to actually do |
       |---|---|
       | **What fires when this runs?** | Trace two levels out. Read the code, not the docs, for callbacks, middleware, observers, hooks on anything the unit touches. |
       | **Do the tests exercise the real chain?** | If every dependency is mocked, the test proves the logic in isolation and says nothing about the interaction. At least one test should run real objects through the chain. |
       | **Can failure leave orphaned state?** | If state is persisted before a risky call, trace the failure path: does it clean up, and is retry idempotent? |
       | **What other interfaces expose this?** | Grep for the behaviour in sibling classes and alternate entry points. If parity is needed, it belongs in this unit, not a follow-up. |
       | **Do error strategies agree across layers?** | List the error classes each layer raises and rescues. Retry middleware plus an application fallback can double-execute. |

       A "yes" that the unit's tests do not cover is a gap to close here, not a finding to leave for step 10.
     - **9e. Commit.** **Only after 9d exited 0**, with nothing edited since. If anything changed after that call, re-run it joined to the commit (`ensemble-unit-verify --unit U<N> --working && git commit …`) so a red assertion cannot reach a commit through inattention. Conventional subject + U-ID + `phase: P<N>` trailer. **Stage only the unit's own files**, never `git add .`, which absorbs whatever was already in the index. If the unit needed a file that was already dirty, ask once whether to include or exclude it, and record the answer in the progress report.

       No peer trailers here: step 10's branch-level `review-verdict:` covers every unit, gated and destructive alike.
   - **After-phase verification.** `bash "$SKILL_DIR/scripts/ensemble-unit-verify" --unit P<N> --range <phase-base>..HEAD --prefer-full-when-cheap`: lint, typecheck, and **the tests covering the files this phase touched** — not the full suite. On failure: stop; surface failing tests; offer investigate / commit-as-WIP-via-`--commit-wip` / abort. Do **not** advance to next phase.

     **The selection is resolved, never guessed (D105).** `ensemble-test-select` reports the tier that chose it: `graph` from the project's own `test_changed_command`, `impact-map` from its `test_impact:` prefixes, `sibling` from the filename heuristic, or `full-suite` when `test_full_seconds` says the whole suite is under five minutes. **Surface the tier**: a selection nobody can audit is one nobody will notice is wrong. The cheap-suite tier covers what no heuristic can: a test anchored on file *content* is unreachable from the path that changed.

     **Why targeted rather than full (D53).** The full suite runs once, at 10.4, after remediation. The trade, named rather than hidden: a phase-3 change that breaks a phase-1 test outside the targeted set surfaces at 10.4 rather than at the boundary.
   - **Plan-hash check.** Re-compute via `$SKILL_DIR/scripts/ensemble-plan-hash <plan-path>` (it covers the immutable plan inputs and excludes the iteration log, per-unit `status` and `peer_review_resolutions`). On mismatch with the build's baseline → refuse to advance; surface that the plan was edited externally during build. (User can re-baseline with `/en-build --re-baseline` after reviewing the diff.)
   - **Working-tree contract.** Verify clean tree, expected feature branch, up to the previous phase's last commit. Any divergence → refuse to advance; surface state.
   - Surface phase summary (units, commits, any gate confirmations the phase required).
   - If `build.pause_between_phases` AND not last phase: ask y/pause/n for next phase. Default: roll forward.

   **Phasing-off path** (no trigger fired, `--no-phasing`, `--unit U<N>`, `--from U<N>`): the same per-unit loop 9a–9e with no phase grouping or phase-level prompts. **Step 9a runs verbatim** on every selected unit, the `phase: P<N>` trailer is still written from the unit's classification, and the post-build phase still runs over the resulting branch diff.

10. **Post-build phase (branch-level simplify → review → audit → learn).** Runs ONCE after all units commit. This is where every unit gets its code-simplifier and Outside Voice review — at the branch level, not per-unit (D52).

    1. **Cheap gate: lint + typecheck only.** Seconds, not minutes: it catches breakage before simplify and review spend time on code that cannot compile. **The full suite does not run here** — it runs once, at 10.4, after review findings have been applied.
    2. **Code-simplification pass.** Invoke `/en-simplify` on the branch diff (`git diff <merge-base>..HEAD`). Skip on docs-only or trivial (<~10 changed lines) branches, or with `--no-simplify`. It leaves changes in the working tree and does not commit.
    3. **Branch-level Outside Voice review (cross-agent required; host personas additive).** **Invoke `/en-review --cross --mode headless --base <merge-base>`** over the branch diff, or `--peer` in place of `--cross` when `--review peer` was passed. The cross-agent peer is **mandatory** here: the host implemented every unit, so the other architecture reviews it (D23). The host personas run alongside as fresh-context sub-agents (D46), and are where the standards, testing and maintainability findings come from.

       en-review returns the findings envelope with a `reviewer` field (`cross-agent` normally; `single-agent-fallback` / `en-review-host-fallback` when no peer) plus `reconciliation[]` buckets. `reviewer` records whether the cross-agent property held, which is what the step 10.6 audit gates on. **Host applies** eligible findings per `references/severity.md` (grades and wire shape per `references/peer-contract.md`), as surgical edits: auto-apply `safe_auto`; surface P0 disagreements and high-confidence security or architecture findings; **`conflicting` findings are never auto-applied**; triage `corroborated` first. **Apply every finding in one batch, then verify once**; fix-verify-fix-verify pays a full suite per partial fix. When the batch addressed a P0 or P1, run `/en-review --verify <envelope-path> --mode headless` before 10.4, so the `review-verdict:` trailer records the verdict on the code that ships rather than the code before the fixes (D80). `--review none` skips this step entirely, personas included, and records the branch as review-skipped. It is not "run the review without the peer": when `PEER_AVAILABLE=false` en-review runs its host personas anyway and records `reviewer: single-agent-fallback` or `en-review-host-fallback`, which the audit accepts as `branch_review_pass: fallback_completed`.
    4. **The full suite, once.** With simplify and review landed and their findings applied, run the project's full test suite, lint and typecheck. **This is the only full-suite run in the post-build phase**, and on a build with phasing it is the only one after the last phase boundary. On failure: stop; surface; offer investigate / `--commit-wip` / abort.
       **On success, write a verification receipt**, and report the elapsed time, per `references/post-build-protocol.md`: `bash "$SKILL_DIR/scripts/ensemble-verification-receipt" write --check full_suite=passed …`, only on a pass, never fatal if the write itself fails. **Do not interrupt a running suite**; a suite that looks stalled is reported, not killed and retried.

    5. **Commit the simplify + review changes** (if any) with **both** a `review-verdict:` trailer AND a `simplify-verdict:` trailer (EN07). If steps 2–3 produced no working-tree changes, create an empty commit (`--allow-empty`) carrying **both** trailers so the branch records both passes.

       **Both trailer schemas are in `references/post-build-protocol.md`**, with their required keys and an example commit. Two rules bind here: a **missing** `simplify-verdict:` is not a legitimate skip, and `--no-simplify` / `--review none` are recorded as explicit, visible opt-outs, never as silence. `ensemble-verify-peer-evidence --branch-coverage <range> --require-simplify` derives `simplify_pass` and `branch_review_pass` from these trailers and fails when either is `missing`/`failed`.

    6. **End-of-build evidence audit (mandatory, mechanical).** Compute branch-level coverage once, **with the simplify+review gate**: `$SKILL_DIR/scripts/ensemble-verify-peer-evidence --branch-coverage <merge-base>..HEAD --require-simplify --json` → `covered_units`, plus the two derived outcome fields **`simplify_pass`** (`completed | not_applicable | failed | missing`) and **`branch_review_pass`** (`completed | fallback_completed | failed | missing`). `--require-simplify` makes it **exit non-zero** when either is `missing`/`failed`, so a skipped `/en-simplify` or an unrecorded branch review fails the audit here rather than silently. Then confirm every plan U-ID appears in `covered_units`. One branch-level review covers every unit, so a U-ID missing from it is a genuine gap. **Surface a per-unit table plus the two gate lines in the summary** (its shape, and the reason each gate line carries, are in `references/post-build-protocol.md`). **The two gate lines are mandatory in every build summary**, and a `missing`/`failed` value on either makes the verdict `failed` even when every U-ID is covered.

      A unit not in `covered_units`, or a `missing`/`failed` gate line, makes the audit verdict `failed`; the audit surfaces but does NOT auto-revert, and the user decides. While it fails **for any reason**, the success path is **blocked**: the suggested next step is `/en-review --peer <sha>` on the failing units, then re-audit, not `/en-review → /en-qa → /en-ship`.

    - Summary: completion status per U-ID, deviations, branch-level simplifier + review verdict. Per-phase summary if phasing was on.
    - **Learning checkpoint** (structured, non-droppable - A3, D26). **The SOLE learning-capture point in the lifecycle**: it fires at the very end of the post-build phase, after the branch-level simplify, review and evidence audit, so capture reflects the fully reviewed build. No other skill prompts for learnings. It emits a visible `learning_checkpoint:` outcome line in the build summary, so the decision is never silently dropped.
      **The seven steps are in `references/post-build-protocol.md`**: the deferral guard (a failed evidence audit defers the checkpoint and emits no outcome value), the `CI=true` short-circuit, the capture baseline, the idempotency check, the prompt itself, the four canonical outcomes, and the `build.learning_checkpoint: false` override.

      The four canonical outcome values are `captured (N learnings)` / `intentionally_skipped` / `up_to_date` / `ci_environment`, never the bare word `skipped`. Firing at the `/en-learn` hand-off puts it outside the autonomy contract's window, so it is a terminal checkpoint rather than an inserted pause.
    - Suggest next: `/en-review` → `/en-qa` → `/en-ship` — but only if the audit passed. Otherwise: `/en-review --peer <sha>` on the failing commits.

## Flags

| Flag | Effect |
|---|---|
| `--no-simplify` | Skip the post-build code-simplification pass (step 10.2). Records `simplify-verdict: {"outcome":"not_applicable","reason":"--no-simplify",...}` - a visible, recorded opt-out that passes the audit, never a silent skip. |
| `--review cross\|peer\|none` | What runs at 10.3. **Default `cross`** — peer plus host personas, per D46, because the standards / testing / maintainability findings depend on project context this build has. **`peer`** runs the peer alone: cheaper and faster, and the right call when you want an independent read without the roster; the peer is mandatory either way and `review-verdict.reviewer` still records whether the cross-agent property held, so the audit is unaffected. **`none`** skips 10.3 **entirely**, peer and personas both — the branch records as review-skipped, the audit reports `branch_review_pass: missing` and FAILS. Since D52 this is the build's only review, so `none` leaves every unit unreviewed, destructive ones included. |
| `--unit U<N>` | Build only the named unit; don't auto-advance. |
| `--no-phasing` | Force phasing off for this run. No `--phasing` counterpart: phasing turns on from six triggers, and when none fired the plan is small enough not to need it. |
| `--dry-run` | Show what would happen; don't write or commit |
| `--from U<N>` | Resume from a specific unit (skip earlier ones). |
| `--from-phase P<N>` | Resume at phase N. Verifies prior phases' commits and a clean working tree before starting. |
| `--finalize-only` | Run finalize loop and stop without building. |
| `--commit-wip` | After a stopped run (Ctrl-C, gate-failure, etc.), create a `wip/<plan_id>-phase<N>` branch and commit current state. Explicit user invocation only — never automatic. |
| `--re-baseline` | After reviewing an external plan-file diff, accept the new state as the build's baseline `peer_review_plan_hash`. |

**One decision, one flag.** The review decision has three answers, so it is one flag with three values; there is no `--no-review`.

**Standing policy lives in `.ensemble/config.local.yaml`, not here** — `build.worktree`, `build.strict_destructive`, `build.pause_between_phases`, `build.learning_checkpoint`. A flag is for what changes run to run; a project either works in worktrees or it doesn't. Config-set skips are surfaced in the step 10.6 audit exactly like flag-set ones, so a policy set once and forgotten is as visible in the build summary as a flag typed today.

**No flag disables universal safety gates.** Every flag changes phasing, pacing, or selection; none turn off destructive / gated confirmations.

## Per-unit progress report

After each unit commits, surface a one-line summary, and append the same record to `/tmp/ensemble/en-build/<run-id>/ledger.json` (unit, outcome, commit, tests, notes). The final summary and the step 10.6 audit table are derived from that file: a build runs long enough for the context to be compacted, and `--from U<N>` recovers git state but not what was reported.

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
metrics: <path> (<summary>)
```

**The `Review:` line is mandatory and carries both halves.** *Found*, broken down by severity, and *addressed*, broken down the same way — a review that found eleven things and addressed six is a different outcome from one that found six and addressed six, and a line reporting only the second is unreadable as either. Deferred findings name their TD IDs so the paper trail is followable from the summary; disagreed ones are counted so a silent drop is visible as a number. Where the review was skipped or fell back, this line says which and why, in place of the counts.

The `metrics:` line is the run ledger `references/run-metrics.md` describes, with the helper's own summary in the parentheses (`6 units, 3 phases, 1 suite runs`). When metrics were disabled it reads `metrics: disabled (<reason>)`, so a missing file is never mistaken for a run that recorded nothing.

The `simplify_pass:` and `branch_review_pass:` lines are **mandatory** (EN07) - they echo the durable `simplify-verdict:` / `review-verdict:` trailers so a skipped simplify or an unrecorded review can never read as a clean finish. A `missing`/`failed` value on either blocks the learning checkpoint and the ship hand-off.

## Reference files

- `references/finding-schema.md` — shape of the findings envelope `/en-review` returns
- `references/severity.md` — apply / defer / disagree routing
- `references/post-build-protocol.md` — step 10's mechanics: the receipt, the two trailer schemas, the audit's report shape, the learning checkpoint's steps
- `references/build-preflight.md` — the payload check, the sub-state matrix and the plan-hash baseline; read at step 4
- `references/build-failures.md` — the full failure table; read when something fails
- `references/build-legacy-plans.md` — **gated**: read only for a plan with no `peer_review_verdict` field or a unit with no `risk:` (pre-D37 plans); owns the legacy inference table and the ordered risk classifier
- `references/run-metrics.md` — the run ledger's call points, shared with `/en-plan`; the helper is `$SKILL_DIR/scripts/ensemble-run-metrics`
- `$SKILL_DIR/scripts/ensemble-unit-verify` — step 9d's single call, and the gate 9e's commit hangs on. It calls `$SKILL_DIR/scripts/ensemble-test-select`, which is also what the phase boundary asks for its tier.
- `$SKILL_DIR/scripts/ensemble-verify-peer-evidence` — mechanical gate at step 10.6's audit. Run with `--branch-coverage <range> --require-simplify`: it enumerates the U-IDs covered by the branch's `review-verdict:` trailers and derives `simplify_pass` / `branch_review_pass`. Branch coverage is its only mode (D83).

## Failure protocol

**`references/build-failures.md` owns the table**: one row per failure, what to do, and the rule they share — a failure surfaces, never auto-reverts, auto-commits or auto-stashes, and the user decides. Five of them stop the build where it stands:

| Failure | Behavior |
|---|---|
| Unit needs files outside its `Files` list | **Stop before making the change.** Name what the unit needs and why its scope cannot deliver it, then ask: widen, split, or abort. Do not quietly widen: the `Files` list is what the plan was reviewed against. |
| Unit's `Approach` is too thin to implement | Stop and ask. Pre-flight checks the field is present, not that it is sufficient, and a guessed interpretation passes tests written to match the guess. |
| Unit verification fails (9d) | Fix and re-run. **After two failed attempts on the same unit, stop** — show the output and ask: retry, skip the unit, or abort. Guessing a third time is how a unit gets "fixed" by weakening its test. |
| After-phase verification fails | Stop. Do **not** advance to the next phase. Surface failing tests; offer investigate / `--commit-wip` / abort. |
| Ctrl-C or abort mid-unit | **Stop cleanly. No signal-time git operations.** Surface branch, current unit, dirty files, last successful commit and the resume command (`--from U<N>` / `--from-phase P<M>`). WIP capture is opt-in via `--commit-wip`, never automatic. |

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
