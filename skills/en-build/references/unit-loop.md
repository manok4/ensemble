# The unit loop (`/en-build` steps 8 and 9)

How a plan becomes commits: which phase a unit lands in, what implementing one
unit involves, and what the phase boundary proves. `SKILL.md` keeps the gates,
the loop's shape and the exit codes it acts on; this file is read when the build
enters step 8, and again by anyone who needs the detail behind a step.

## Which phase a unit lands in

**Phase classification** (when phasing is on): each unit maps to one of P1 (Measurement, `risk: low`), P2 (Additive, `risk: medium` except migration/backfill/schema-evolution categories), P3 (Migration / Backfill, `risk: high` OR `risk: medium` + migration/backfill/schema-evolution category), P4 (Destructive, `risk: destructive`). `risk:` is the single source of truth for phase placement; `category:` only carves out the `medium → P3` case for migrations. **Empty phases are collapsed silently.**

**Inference fallback** (a legacy plan whose units lack `risk:`): read `references/build-legacy-plans.md`, which owns the ordered classifier (destructive patterns first, then migrations, backfills, read-only paths, then `medium`) and the confirmation it surfaces before the build proceeds on inferred classes.

**Dependency-vs-phase invariant.** For every dependency edge `U → V`, verify `phase(V) <= phase(U)`. If a low-risk unit depends on a higher-risk unit (so `phase(V) > phase(U)`), **reject the plan as a structural error** with three remediation options (remove the dependency, promote `U.risk:`, or split `U`). Never silently bury the unit in a higher phase: it would land after a confirmation typed for destructive work.

## Implementing one unit

- **9c. Implement.** The host writes the code, in this session. No dispatch, no worker, no other agent. Say in one line which unit is starting and its goal before the first edit. Edit files surgically; rewrite one only when it is short or most of it changes. **The unit's scope is the deliverable.** A pre-existing bug, a performance concern or behaviour the unit does not mention is a `Note:` in the progress report and a follow-up, not a fix in this unit, unless the unit's own behaviour cannot work without it. Commit tests the unit's `Test scenarios` call for, sized like the neighbouring test files; scratch checks are not kept.

  **First, check whether the unit is already done.** If its `Files` exist with the expected capability, or its `Verification` criteria already pass against the current code, the work landed on a prior branch or an earlier run of this build. Confirm it matches the unit's intent, record it as already-satisfied in the progress report, and move on. **Do not silently reimplement.** `--from U<N>` and `--from-phase P<N>` both resume into work that may already exist.

**System-wide check, before calling a feature-bearing unit done.** Unit tests prove the unit's logic; these five questions are about what the unit sits inside. **Skip it entirely for a leaf change** — no callbacks, no persisted state, no parallel interfaces — where the honest answer to all five is "nothing".

| Ask | What to actually do |
|---|---|
| **What fires when this runs?** | Trace two levels out. Read the code, not the docs, for callbacks, middleware, observers, hooks on anything the unit touches. |
| **Do the tests exercise the real chain?** | If every dependency is mocked, the test proves the logic in isolation and says nothing about the interaction. At least one test should run real objects through the chain. |
| **Can failure leave orphaned state?** | If state is persisted before a risky call, trace the failure path: does it clean up, and is retry idempotent? |
| **What other interfaces expose this?** | Grep for the behaviour in sibling classes and alternate entry points. If parity is needed, it belongs in this unit, not a follow-up. |
| **Do error strategies agree across layers?** | List the error classes each layer raises and rescues. Retry middleware plus an application fallback can double-execute. |

A "yes" that the unit's tests do not cover is a gap to close here, not a finding to leave for step 10.

## The phase boundary

- **After-phase verification.** `bash "$SKILL_DIR/scripts/ensemble-unit-verify" --unit P<N> --range <phase-base>..HEAD --prefer-full-when-cheap`: lint, typecheck, and **the tests covering the files this phase touched** — not the full suite. On failure: stop; surface failing tests; offer investigate / commit-as-WIP-via-`--commit-wip` / abort. Do **not** advance to next phase.

  **The selection is resolved, never guessed (D105).** `ensemble-test-select` reports the tier that chose it: `graph` from the project's own `test_changed_command`, `impact-map` from its `test_impact:` prefixes, `sibling` from the filename heuristic, or `full-suite` when `test_full_seconds` says the whole suite is under five minutes. **Surface the tier**: a selection nobody can audit is one nobody will notice is wrong. The cheap-suite tier covers what no heuristic can: a test anchored on file *content* is unreachable from the path that changed.

  **Why targeted rather than full (D53).** The full suite runs once, at 10.4, after remediation. The trade, named rather than hidden: a phase-3 change that breaks a phase-1 test outside the targeted set surfaces at 10.4 rather than at the boundary.
- **Plan-hash check.** Re-compute via `$SKILL_DIR/scripts/ensemble-plan-hash <plan-path>` (it covers the immutable plan inputs and excludes the iteration log, per-unit `status` and `peer_review_resolutions`). On mismatch with the build's baseline → refuse to advance; surface that the plan was edited externally during build. (User can re-baseline with `/en-build --re-baseline` after reviewing the diff.)
- **Working-tree contract.** Verify clean tree, expected feature branch, up to the previous phase's last commit. Any divergence → refuse to advance; surface state.
- Surface phase summary (units, commits, any gate confirmations the phase required).
- If `build.pause_between_phases` AND not last phase: ask y/pause/n for next phase. Default: roll forward.

## What the two gated categories cover

The universal-safety-gate table and its typed confirmations live in `SKILL.md`.
This is the bar each category is drawn at, which plan authors and peer review enforce at plan
time and `/en-plan`'s template carries.

The primary safety boundary, deliberately **two narrow categories, nothing more**:
- **`risk: destructive`** — its own literal-string category, for irreversible data loss.
- **`gated: true`** — limited **explicitly to production-state-changing actions**: customer-facing feature-flag flips, production data backfills / data mutation, real-side-effect third-party API calls against **production** endpoints, API contract breaks, and production config changes with behavior impact. **Non-production external side effects** (PR/branch automation, issue/comment writes, local workflow or CI-config changes, sandbox/staging API calls, reversible repo operations) are explicitly **NOT** gated: 9d's verification gate and step 10's review cover them, not user prompts.

Everything outside these two categories advances autonomously. Phase-level prompts (P4 `"run phase 4"`, opt-in `build.pause_between_phases`) are conveniences that group multiple units' confirmations when phasing is active. With phasing off (or `--unit` selecting a destructive unit alone), the unit-level gate fires instead.
