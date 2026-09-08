# The unit loop (`/en-build` steps 8 and 9)

What implementing one unit involves, what the checkpoint proves, and the bar each
gated category is drawn at. `SKILL.md` keeps the gates, the loop's shape and the
exit codes it acts on; this file is read when the build enters step 8.

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

## The checkpoint (9f)

- **Before the first `risk: destructive` or `gated: true` unit, and once after the last unit commits**, run `bash "$SKILL_DIR/scripts/ensemble-unit-verify" --unit checkpoint --range <first-unit-commit>^..HEAD --prefer-full-when-cheap`: lint, typecheck, and the tests covering everything built so far. On failure: stop; surface failing tests; offer investigate / commit-as-WIP-via-`--commit-wip` / abort. Do **not** enter the unit the checkpoint was guarding.

  **Why here and not everywhere (D108).** The checkpoint used to fire at each phase boundary, which meant it fired on a schedule the risk did not follow. Attaching it to the risk event is the same protection with none of the grouping: everything reversible is proven immediately before anything irreversible runs. Every unit is already verified at 9d, so the checkpoint's job is cross-unit breakage, not the unit's own logic.

  **Why targeted rather than full (D53).** The full suite runs once, at 10.4, after remediation. The trade, named rather than hidden: a change that breaks an earlier unit's test outside the targeted set surfaces at 10.4 instead of at the checkpoint.

- **Plan-hash check** and the **working-tree contract** run with it: a plan edited externally during a build, or a dirty tree or unexpected branch, refuses to advance.

## What the two gated categories cover

The universal-safety-gate table and its typed confirmations live in `SKILL.md`.
This is the bar each category is drawn at, which plan authors and peer review enforce at plan
time and `/en-plan`'s template carries.

The primary safety boundary, deliberately **two narrow categories, nothing more**:
- **`risk: destructive`** — its own literal-string category, for irreversible data loss.
- **`gated: true`** — limited **explicitly to production-state-changing actions**: customer-facing feature-flag flips, production data backfills / data mutation, real-side-effect third-party API calls against **production** endpoints, API contract breaks, and production config changes with behavior impact. **Non-production external side effects** (PR/branch automation, issue/comment writes, local workflow or CI-config changes, sandbox/staging API calls, reversible repo operations) are explicitly **NOT** gated: 9d's verification gate and step 10's review cover them, not user prompts.

Everything outside these two categories advances autonomously, and every gate inside them is per unit: nothing group-confirms them (D108).
