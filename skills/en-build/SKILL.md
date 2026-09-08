---
name: en-build
description: "Execute an implementation plan unit by unit on a feature branch: implement, test, lint, commit per unit, then one simplify pass and one cross-agent review over the branch diff. Trigger phrases: 'build this plan', 'implement <plan_id>', 'start building', 'execute the plan'."
---


# `/en-build`

> **Running a bundled script.** Anchor every call to this skill's own directory: `SKILL_DIR="<absolute path of the directory containing this SKILL.md>"; bash "$SKILL_DIR/scripts/<name>"`. The trailing `;` is load-bearing. See `references/script-invocation.md`.

Execute a plan, unit by unit. **The host implements every unit**: the agent `/en-build` runs in writes the code, runs the tests, makes the commits. The peer is never a worker here; it enters once, at the branch-level review in step 10, after `/en-simplify` has run. That is what keeps implementer ≠ reviewer (D52).

> **Hard preconditions.** A plan in `docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md` (e.g. `EN03-improvement_dashboard-overview.md`; `<PREFIX>` from foundation's `plan_id_prefix`, default `FR`) with `status: open` (or `in_progress` when resuming), all U-IDs present, no unblocked dependencies. A recoverable `status: draft` is offered one finalize-and-build prompt instead of being refused.
>
> **Universal safety gates** (EVERY code path: phasing on/off, `--unit`, `--from`, `--from-phase`, manual resume): every unit with `risk: destructive` or `gated: true` requires explicit confirmation before running. **No flag disables these gates.** See step 8b.
>
> **Peer contract.** Severity, confidence, autofix class and the `peer_decision` object are defined once in `references/peer-contract.md`, byte-identical across every skill that exchanges findings. What this skill does with a finding is its own policy.

## Process

1. **Resolve the question tool.** `$QUESTION_TOOL` is `AskUserQuestion` on Claude Code (a deferred tool; preload it via `ToolSearch`) and `request_user_input` on Codex, for the confirmation prompts at 9a. That is all en-build needs from the host: it resolves no peer variables and runs no host-detection script.

   **Payload check, fail-fast.** Confirm the files `references/build-preflight.md` lists are present. Any missing → **fail at start with a clear error**, naming the paths, and tell the user to re-run `/en-setup` or sync the plugin. A degraded build is never started.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, skip step 10.3's review and record `review-verdict: {"verdict":"skipped","reviewer":"recursion-guard-active",...}`, so the step 10.6 audit reads a reason rather than an absence. Every unit is still implemented and committed.
3. **Confirm the implementer.** The host, on any host: `/en-build` never hands authoring to another agent. `/en-review` decides at step 10.3 whether the branch-level review is cross-agent, single-agent fallback, or skipped; that never changes who writes the code.
4. **Load plan and run pre-flight.** Read `<plan-path>`. Verify all U-IDs present and unblocked, and each unit carrying Goal, Files, Approach, Test scenarios, **Risk, Gated**. **Then resolve the plan's state against the pre-flight sub-state matrix in `references/build-preflight.md`**, which owns every buildable and refused combination and the recovery prompt. It returns one of four:

   **Proceed** on `status: open` with verdict `approve` or `null` and no unresolved findings. **Offer auto-commit, then proceed** when that plan file is untracked. **Offer finalize-and-build**, one prompt, on `status: draft` + `revise` with every finding resolved. **Refuse** on unresolved draft findings, a missing verdict, `reject`, `completed` or `abandoned`.

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

    **Phase classification, the inference fallback for legacy plans, and the dependency-vs-phase invariant are `references/unit-loop.md`'s.** Read it here. Two of its rules bind this step: `risk:` is the single source of truth for phase placement, and a plan whose dependency edge would put a unit in a *higher* phase than the unit it depends on is **rejected as a structural error**, never silently buried.

8b. **Universal safety gates** (apply on EVERY execution path — phasing on/off, `--unit`, `--from`, `--from-phase`, manual resume; **no flag disables them**):

    For every unit selected for execution, classify it (using `risk:` or the ordered inference fallback) and enforce:

    | Classification | Gate |
    |---|---|
    | `risk: destructive` | Literal-string confirmation `"run unit U<N>"` typed verbatim, with goal/files/approach surfaced first. (When the unit is part of an active P4 phase already group-confirmed via `"run phase 4"`, this per-unit gate is skipped — see step 9.) |
    | `gated: true` | y/skip/abort confirmation, with goal and approach surfaced first. (Always per-unit; never group-confirmed.) |
    | `risk: high` AND `build.strict_destructive` | Literal-string confirmation `"run unit U<N>"`. (Skipped when the unit is part of an active P3 phase already group-confirmed via `"run phase 3"`.) |
    | Anything else | No mandatory gate at the unit level. |

    **Two narrow categories, nothing more**: `risk: destructive`, its own literal-string category for irreversible data loss, and `gated: true` for production-state-changing actions. `references/unit-loop.md` lists what qualifies as each and what explicitly does not. Everything outside them advances autonomously; the phase-level prompts group a phase's confirmations when phasing is on, and the unit-level gate fires instead when it is off.

    **Preflight gate summary.** Before entering the unit loop (step 9), surface a one-line count so gates are never a surprise mid-build: *"Plan has N gated/destructive units that will pause: U<a> (gated), U<b> (destructive). The remaining M units run autonomously."* If N is 0, say so: *"No gated or destructive units — this plan runs fully autonomously."*

## Agent autonomy contract

`/en-build` is autonomous by design: the user authorized the work at plan time (peer-reviewed plan, `status: open`, hash recorded). After a unit commits, advance to the next immediately. **Do not pause** for confirmation, judgment, "natural checkpoint", "the next unit is bigger", "let me verify before continuing", or any reason not enumerated below.

### Scope of the contract

The contract governs **the inter-unit main loop**: the window from the start of step 9 through the end of step 10, before the `/en-learn` hand-off. **Steps 1-8 are NOT governed by this contract**; their prompts are pre-execution, about whether the build can sensibly start.

### Legitimate pause cases within the contract window (exhaustive within scope, no others permitted)

1. **Working tree dirty at branch setup** (step 5) — stash / commit / abort. *(outside the window)*
2. **Plan-review concerns surfaced at start** (step 7) — continue / pause / split. *(outside the window)*
3. **`risk: destructive` unit at step 9a** — typed `"run unit U<N>"`.
4. **`gated: true` unit at step 9a** — y/skip/abort.
5. **P4 phase-level confirmation** (step 9, phasing on) — typed `"run phase 4"`.
6. **`build.pause_between_phases` set** (step 9, opt-in) — y/pause/n between phases.
7. **Failure protocol fires** — each row has its own handler.

### Anti-patterns (explicitly forbidden), each with its tell

- **Agent-initiated "checkpoint before bigger unit" pauses.** The plan was authored and peer-reviewed; complexity is not re-litigated at execution time. *The tell: the reason cites the next unit's size, not this unit's state.*
- **"Working tree is clean, paused for confirmation" between non-gated units.** A clean tree is the expected state between units. *The tell: the pause reports success and asks nothing answerable.*
- **"Should I continue?" preambles and "Let me verify with the user before …"** outside the seven cases. *The tell: the question offers no option that changes what happens next.*

**The right response to uncertainty is advance, not ask.** Uncertainty is not a pause case: continue per the contract. The verification gates and the failure protocol are the safety net; a self-inserted checkpoint adds friction, not protection. A real concern goes in the per-unit progress report as a `Note:` line, which is informational and does not gate the build.

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
     - **9c. Implement.** The host writes the code, in this session. No dispatch, no worker, no other agent. Say in one line which unit is starting and its goal before the first edit. **The unit's scope is the deliverable**: a pre-existing bug or behaviour the unit does not mention is a `Note:` in the progress report and a follow-up, not a fix here, unless the unit's own behaviour cannot work without it. **Check first whether the unit is already done** and record it as already-satisfied rather than reimplementing. `references/unit-loop.md` owns the rest, including the five-question system-wide check that runs before a feature-bearing unit is called done.
     - **9d. Verification gate.** One call, not a sequence: `bash "$SKILL_DIR/scripts/ensemble-unit-verify" --unit U<N> --working --prefer-full-when-cheap --cheap-seconds 120`. It resolves the unit's tests through `$SKILL_DIR/scripts/ensemble-test-select`, runs lint, typecheck and that selection, writes every byte to a log under `.git/ensemble/runs/`, and prints one line per check plus the tail of whatever failed. A test file the unit just wrote selects itself, so a unit that ships tests is covered without the project declaring anything. **Read the exit code, it is the gate:** `0` green; `1` a check failed, fix it before committing; `3` the selection was empty, so name the unit's tests yourself and run them (zero tests found is a finding about the project, never a pass); `4` AGENTS.md declares no commands, so verify by hand and say so in the progress report.
     - **9e. Commit.** **Only after 9d exited 0**, with nothing edited since. If anything changed after that call, re-run it joined to the commit (`ensemble-unit-verify --unit U<N> --working && git commit …`) so a red assertion cannot reach a commit through inattention. Conventional subject + U-ID + `phase: P<N>` trailer. **Stage only the unit's own files**, never `git add .`, which absorbs whatever was already in the index. If the unit needed a file that was already dirty, ask once whether to include or exclude it, and record the answer in the progress report.

       No peer trailers here: step 10's branch-level `review-verdict:` covers every unit, gated and destructive alike.
   - **After-phase verification.** `bash "$SKILL_DIR/scripts/ensemble-unit-verify" --unit P<N> --range <phase-base>..HEAD --prefer-full-when-cheap`: lint, typecheck, and **the tests covering the files this phase touched** — not the full suite. On failure: stop; surface failing tests; offer investigate / commit-as-WIP-via-`--commit-wip` / abort. Do **not** advance to next phase.

     **The selection is resolved, never guessed (D105).** `ensemble-test-select` reports the tier that chose it (`graph`, `impact-map`, `sibling`, or `full-suite` when `test_full_seconds` says the suite is cheap). **Surface the tier**: a selection nobody can audit is one nobody will notice is wrong. `references/unit-loop.md` owns the tiers and the D53 trade this makes.

   - **Plan-hash check.** Re-compute via `$SKILL_DIR/scripts/ensemble-plan-hash <plan-path>` (it covers the immutable plan inputs and excludes the iteration log, per-unit `status` and `peer_review_resolutions`). On mismatch with the build's baseline → refuse to advance; surface that the plan was edited externally during build. (User can re-baseline with `/en-build --re-baseline` after reviewing the diff.)
   - **Working-tree contract.** Verify clean tree, expected feature branch, up to the previous phase's last commit. Any divergence → refuse to advance; surface state.
   - Surface phase summary (units, commits, any gate confirmations the phase required).
   - If `build.pause_between_phases` AND not last phase: ask y/pause/n for next phase. Default: roll forward.

   **Phasing-off path** (no trigger fired, `--no-phasing`, `--unit U<N>`, `--from U<N>`): the same per-unit loop 9a–9e with no phase grouping or phase-level prompts. **Step 9a runs verbatim** on every selected unit, the `phase: P<N>` trailer is still written from the unit's classification, and the post-build phase still runs over the resulting branch diff.

10. **Post-build phase (branch-level simplify → review → audit → learn).** Runs ONCE after all units commit, over the branch diff rather than per unit (D52). **`references/post-build-protocol.md` owns the mechanics**: the receipt, both trailer schemas, what `/en-review` returns, the audit's report shape and the learning checkpoint's steps. Read it here. Six gates, in order:

    1. **Cheap gate: lint + typecheck only.** Seconds, not minutes. **The full suite does not run here** — it runs once, at 10.4, after review findings have been applied.
    2. **Code-simplification pass**, at the branch level, not per-unit. Invoke `/en-simplify` on the branch diff (`git diff <merge-base>..HEAD`). Skip on docs-only or trivial (<~10 changed lines) branches, or with `--no-simplify`; it leaves changes in the working tree and does not commit.
    3. **Branch-level Outside Voice review (cross-agent required; host personas additive).** **Invoke `/en-review --cross --mode headless --base <merge-base>`**, or `--peer` in place of `--cross` when `--review peer` was passed. The cross-agent peer is **mandatory** here: the host implemented every unit, so the other architecture reviews it (D23). Host personas run alongside as fresh-context sub-agents (D46). The envelope's `reviewer` records whether the cross-agent property held (`cross-agent`, or `single-agent-fallback` / `en-review-host-fallback` when no peer was available), and that is what the 10.6 audit reads. **Apply every finding in one batch, then verify once**; fix-verify-fix-verify pays a full suite per partial fix. When the batch addressed a P0 or P1, run `/en-review --verify <envelope-path> --mode headless` before 10.4, so the trailer records the verdict on the code that ships (D80). **`--review none` skips this step entirely**, personas included, and the audit then fails with `branch_review_pass: missing`.
    4. **The full suite, once.** With simplify and review landed and their findings applied, run the project's full test suite, lint and typecheck. **This is the only full-suite run in the post-build phase.** On failure: stop; surface; offer investigate / `--commit-wip` / abort. **Do not interrupt a running suite**; one that looks stalled is reported, not killed and retried.

       **On success, write a verification receipt** and report the elapsed time, per the reference: `bash "$SKILL_DIR/scripts/ensemble-verification-receipt" write --check full_suite=passed …`. Only on a passing suite, and never fatal if the write itself fails.
    5. **Commit the simplify + review changes** (if any) with **both** a `review-verdict:` trailer AND a `simplify-verdict:` trailer (EN07). No working-tree changes → an empty commit (`--allow-empty`) carrying both, so the branch records both passes. Schemas are in the reference; `simplify-verdict.outcome` is one of `completed` / `not_applicable` / `failed`, with a reason required for the last two. Two rules bind here: a **missing** `simplify-verdict:` is not a legitimate skip, and `--no-simplify` / `--review none` are recorded as explicit, visible opt-outs, never silence.
    6. **End-of-build evidence audit (mandatory, mechanical).** `$SKILL_DIR/scripts/ensemble-verify-peer-evidence --branch-coverage <merge-base>..HEAD --require-simplify --json` → `covered_units`, `simplify_pass` and `branch_review_pass`. `--require-simplify` makes it **exit non-zero** when either gate is `missing`/`failed`. Confirm every plan U-ID appears in `covered_units`; one branch-level review covers every unit, so a U-ID missing from it is a genuine gap. **Surface the per-unit table and the two gate lines** (shape in the reference). **The two gate lines are mandatory in every build summary**, each carrying its reason when it is anything but `completed`. A missing unit or a `missing`/`failed` gate makes the verdict `failed`; the audit surfaces but never auto-reverts, and while it fails the success path is **blocked**: the next step is `/en-review --peer <sha>` on the failing units, then re-audit.

    - Summary: completion status per U-ID, deviations, branch-level simplifier + review verdict. Per-phase summary if phasing was on.
    - **Learning checkpoint** (structured, non-droppable - A3, D26). **The SOLE learning-capture point in the lifecycle**: it fires here, after the branch-level simplify, review and evidence audit, so capture reflects the fully reviewed build. No other skill prompts for learnings. **Deferral guard: deferred whenever the evidence audit failed**, which includes a `missing`/`failed` `simplify_pass` or `branch_review_pass`, with a one-line note naming the gate; the seven steps are in the reference. It emits one `learning_checkpoint:` outcome line in the build summary, one of `captured (N learnings)` / `intentionally_skipped` / `up_to_date` (zero commits since the last capture: idempotency, no prompt) / `ci_environment` (`CI=true`: no prompt), never the bare word `skipped`.
    - Suggest next: `/en-review` → `/en-qa` → `/en-ship` — but only if the audit passed. Otherwise: `/en-review --peer <sha>` on the failing commits.

## Flags

| Flag | Effect |
|---|---|
| `--no-simplify` | Skip step 10.2. Records `simplify-verdict: {"outcome":"not_applicable","reason":"--no-simplify",...}`: a visible, recorded opt-out that passes the audit, never a silent skip. |
| `--review cross\|peer\|none` | What runs at 10.3. **Default `cross`** — peer plus host personas (D46). **`peer`** runs the peer alone, cheaper, and the peer is mandatory either way. **`none`** skips 10.3 **entirely**, peer and personas both; the audit then reports `branch_review_pass: missing` and **fails**. Since D52 this is the build's only review, so `none` leaves every unit unreviewed. |
| `--unit U<N>` | Build only the named unit; don't auto-advance. |
| `--no-phasing` | Force phasing off for this run. No `--phasing` counterpart: phasing turns on from six triggers, and when none fired the plan is small enough not to need it. |
| `--dry-run` | Show what would happen; don't write or commit. |
| `--from U<N>` | Resume from a specific unit (skip earlier ones). |
| `--from-phase P<N>` | Resume at phase N. Verifies prior phases' commits and a clean tree before starting. |
| `--finalize-only` | Run the finalize loop and stop without building. |
| `--commit-wip` | After a stopped run, create a `wip/<plan_id>-phase<N>` branch and commit current state. Explicit user invocation only, never automatic. |
| `--re-baseline` | After reviewing an external plan-file diff, accept the new state as the build's baseline `peer_review_plan_hash`. |

**Standing policy lives in `.ensemble/config.local.yaml`, not here**: `build.worktree`, `build.strict_destructive`, `build.pause_between_phases`, `build.learning_checkpoint`. Config-set skips are surfaced in the 10.6 audit exactly like flag-set ones.

**No flag disables universal safety gates.** Every flag changes phasing, pacing or selection; none turn off destructive or gated confirmations.

## Reporting

**`references/build-reporting.md` owns both formats**: the per-unit line and the build summary. Two rules live here.

**Per unit, after it commits**, surface one line and append the same record to `/tmp/ensemble/en-build/<run-id>/ledger.json` (unit, outcome, commit, tests, notes). The final summary and the 10.6 audit table are derived from that file: a build runs long enough to be compacted, and `--from U<N>` recovers git state but not what was reported. Simplify and review results appear once, in the final summary; they run over the branch, not per unit.

**The build summary carries five mandatory lines**, and each is a gate someone can read:

| Line | Rule |
|---|---|
| `Review:` | **The `Review:` line is mandatory** and carries both halves: `Found 11 — P0:1 P1:3 P2:5 P3:2` and `Addressed 6 (1 P0, 3 P1, 2 P2)`. Addressed-only cannot tell 6-of-11 from 6-of-6. Deferred findings name their TD IDs; disagreed ones are counted, so a silent drop shows as a number. A skipped or fallen-back review says which and why, in place of the counts. |
| `simplify_pass:` | EN07. Echoes the `simplify-verdict:` trailer, with its reason when it is anything but `completed`. |
| `branch_review_pass:` | EN07. Echoes the `review-verdict:` trailer, same rule. A `missing`/`failed` value on either blocks the learning checkpoint and the ship hand-off. |
| `learning_checkpoint:` | One of the four canonical outcomes. |
| `metrics: <path> (<summary>)` | The run ledger's path and summary, or `metrics: disabled (<reason>)`, so a missing file is never read as a run that recorded nothing. |

## Reference files

- `references/build-preflight.md` — the payload check, the plan sub-state matrix, the plan-hash baseline (step 4)
- `references/unit-loop.md` — phase classification, the phase invariant, the gated categories, implementing a unit, the system-wide check, the phase boundary (steps 8 and 9)
- `references/post-build-protocol.md` — the receipt, both trailer schemas, what `/en-review` returns, the audit's report, the checkpoint's steps (step 10)
- `references/build-reporting.md` — the per-unit line and the build summary's shape
- `references/build-failures.md` — the full failure table
- `references/run-metrics.md` — the run ledger's call points, shared with `/en-plan`
- `references/build-legacy-plans.md` — **gated**: read only for a pre-D37 plan with no `peer_review_verdict` or no `risk:`
- `references/severity.md`, `references/finding-schema.md`, `references/peer-contract.md` — how `/en-review`'s findings are graded, shaped and routed
- `$SKILL_DIR/scripts/ensemble-unit-verify` (9d's call, 9e's gate; it calls `ensemble-test-select`), `$SKILL_DIR/scripts/ensemble-plan-hash` (4a and the boundary), `$SKILL_DIR/scripts/ensemble-verify-peer-evidence` (10.6's audit, `--branch-coverage <range> --require-simplify`), `$SKILL_DIR/scripts/ensemble-run-metrics` (the ledger)

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

- **Never modifies plan content.** Units, approach, scope and U-IDs are `/en-plan` territory. The status flip at step 4 and per-unit `status` updates are bookkeeping, not content.
- **Never opens a PR** (that is `/en-ship`), **never deletes files outside the unit's scope**, and **never invokes itself recursively** (step 2's guard).
- **Never inserts agent-initiated checkpoints.** Only the enumerated pause cases are legitimate inside the contract window.
- **Never bypasses a gate.** Verification gates stop or revert; universal safety gates always confirm, and no flag disables them.
- **Never auto-commits, auto-stashes or runs any git operation at signal time** on Ctrl-C or abort. WIP capture is user-initiated via `--commit-wip`.
- **Never lets another agent write the code.** The host implements every unit; the peer enters once, at 10.3, through `/en-review`.
- **Never declares a build complete with missing review evidence.** The 10.6 audit blocks the success path until every U-ID is covered and both gate lines are recorded.
