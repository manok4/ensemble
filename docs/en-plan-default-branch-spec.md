---
title: en-plan default-branch auto-branch checkpoint
status: spec
owner: mano
related_design:
related:
  - skills/en-plan/SKILL.md
  - docs/foundation.md (§D-N — to be added)
created: 2026-05-12
---

# Spec: `/en-plan` default-branch auto-branch checkpoint

## Context

When `/en-plan` finalizes a plan and reaches step 15 (auto-commit), it commits to **whichever branch the user is currently on**, including the repo's default branch (`main` / `master` / etc.). Field-observed friction: a user invoked `/en-plan` from `main`, the plan got committed straight to `main`, and the design-stage artifact landed in main-line history without going through PR review.

The current behavior was an explicit decision in the original finalize-loop spec (PR #6). The reasoning then: *"Plans on the default branch are discoverable in main-line history."* In practice, the cost outweighs the benefit:

- **Plans bypass PR review.** A plan is a meaningful design artifact and the rest of the team should see it before it lands on the trunk.
- **Plan-only commits on main create weird history.** A commit appears with no corresponding shipped feature — `git log main` shows a planning event with nothing built yet.
- **Design and implementation stages mix on the same branch.** The clean lifecycle is `main → feature branch → plan + build commits → PR → merge`. Putting the plan commit on main short-circuits this.

This spec adds a checkpoint at `/en-plan`'s auto-commit step: when the user is on the default branch, prompt before committing. The default action is to create a feature branch (`<plan_id>-<slug>`) and commit the plan there. Users who genuinely want plans on the default branch get an explicit opt-out (`current`) right in the prompt.

The change is intentionally narrow: it only triggers on the **literal default branch** (per three-source detection). Other long-lived branches (`develop`, `trunk`, `release/*`) are out of scope for v1. A future extension point — `protected_branches` in `.ensemble/config.local.yaml` — is documented but not implemented.

## Outcome enum (canonical)

The prompt's response set and the `/en-plan` report's `default_branch_checkpoint:` field accept exactly these values. Every other section of this spec, the foundation update, the SKILL.md changes, and the drift-guard tests MUST use these exact strings:

| Response | Report value | Action |
|---|---|---|
| `y` (default) | `auto_branched` | Create `<plan_id>-<slug>` from current commit; check out the new branch; commit the plan there. |
| `no-commit` | `no_commit_requested` | Finalize plan to `status: open`; skip the auto-commit step; surface manual commit instructions. |
| `current` | `committed_to_default_branch` | Commit the plan on the default branch (opt-out for users who genuinely want this). |
| `details` | (no terminal value; prompt re-asked) | Show diagnostic info (detected default branch, target branch name, `protected_branches` config hint); re-prompt. |

If any section of this spec uses different wording (e.g. `branched` instead of `auto_branched`, or `kept_on_main`), it's a bug. Drift-guard test asserts exact spelling.

## Resolved decisions

1. **Default response to the prompt is `y` (auto-branch).** Reverses the original PR #6 decision. The whole point of this change is to make the safer behavior the default. Users who genuinely want plans on `main` get the `current` opt-out right in the prompt — it's discoverable, not hidden behind a flag.
2. **Detection scope: literal default branch only.** Three-source resolution: `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name` → `git symbolic-ref refs/remotes/origin/HEAD --short | sed 's|^origin/||'` → hardcoded fallback (`main`, `master`, `develop`, `trunk`). Configurable extension via `.ensemble/config.local.yaml` `protected_branches:` is a documented future enhancement, NOT v1. Predictability beats coverage; false positives compound (every invocation), false negatives don't.
3. **`/en-foundation` gets the same treatment.** Same friction class, same pattern. Out of scope for THIS PR — separate follow-up. Both skills' auto-commit logic should be uniform, but easier to ship them independently.
4. **Branch name = `<plan_id>-<slug>`.** Matches `/en-build`'s feature-branch convention so build picks up the existing branch instead of creating a parallel one. If the branch already exists with only plan-related commits, check it out and resume; if it has build commits or unrelated work, surface and ask.

## Change 1 — `/en-plan` SKILL.md auto-commit step

**File:** `skills/en-plan/SKILL.md`, step 15 (auto-commit).

Insert a default-branch checkpoint **before** the existing "stage and commit" logic. Existing flags (`--commit-branch`, `--no-commit`) and the unrelated-staged-changes refuse-to-commit logic stay unchanged — the checkpoint is additive.

The new sub-step ordering inside step 15:

1. **Resolve target branch.**
   - If `--commit-branch <name>` was passed → honor it; skip the rest of step 15.1; jump to commit.
   - If `--no-commit` was passed → honor it; surface manual instructions; skip commit.
   - Otherwise: continue to default-branch detection.

2. **Detect default branch** (three-source resolution, first hit wins):
   - `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null`
   - `git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's|^origin/||'`
   - Hardcoded fallback: check current branch against `main`, `master`, `develop`, `trunk`. If on one of these AND no remote origin → assume it's the default.

   If detection fails entirely (e.g. fresh repo with no commits, detached HEAD): skip the checkpoint and use the existing commit-on-current-branch behavior.

3. **Checkpoint decision.**
   - If current branch != detected default branch → proceed with existing behavior (commit on current branch).
   - If current branch == default branch → surface the checkpoint prompt (next sub-step).

4. **Surface the checkpoint prompt** (structured, not soft):

   ```
   Default-branch checkpoint
   ─────────────────────────
   You're on `<default-branch>`. Auto-committing plans to the default
   branch bypasses PR review and mixes design-stage commits with
   main-line history.

   Recommended: create feature branch `<plan_id>-<slug>` and commit
   the plan there. /en-build will reuse the same branch.

   y           (recommended) — create the branch + commit
   no-commit              — leave the plan uncommitted; commit manually
   current                — commit on `<default-branch>` anyway (opt-out)
   details                — show diagnostic info
   ```

5. **Handle response.**

   - `y` (default): `git checkout -b <plan_id>-<slug>` from the current commit. If the branch already exists:
     - Inspect via `git log <branch>..HEAD` and `git log HEAD..<branch>` to determine state.
     - If the branch has only plan-related commits (file paths under `docs/plans/`): check it out, surface notice (*"Existing branch <name> has prior plan commits; resuming."*), commit there.
     - If the branch has build commits OR commits touching files outside `docs/plans/`: refuse, surface state, prompt: *"Branch `<name>` already exists with non-plan commits. Pick a different name? (`<plan_id>-<slug>-2` / custom / abort)"*.
     - Record `default_branch_checkpoint: auto_branched` in the `/en-plan` report's structured output.
   - `no-commit`: skip the commit step entirely; finalize the plan to `status: open` but leave it uncommitted; surface manual instructions:
     > *"Plan written. To commit:*
     > `git checkout -b <plan_id>-<slug>`
     > `git add docs/plans/active/<plan-file>.md`
     > `git commit -m 'docs(plan): <plan_id> <slug>'`*"*
     Record `default_branch_checkpoint: no_commit_requested`.
   - `current`: proceed with existing commit-on-default-branch behavior; record `default_branch_checkpoint: committed_to_default_branch` (with an audit-friendly explicit-opt-in note).
   - `details`: print detected default branch, source of detection (`gh` / `git symbolic-ref` / fallback), target branch name (`<plan_id>-<slug>`), existence check result, and one-line config-extension hint:
     > *"To skip this prompt for additional protected branches (e.g. `develop`), add `protected_branches: [develop, trunk]` to `.ensemble/config.local.yaml`. (Planned for a future release; not yet implemented.)"*

6. **Idempotency note.** Running `/en-plan` on the same plan twice from `main`:
   - First run: prompt → user picks `y` → branch `<plan_id>-<slug>` created; plan committed there.
   - Second run (still on `main`, plan_id resolves to the same value via re-detection): prompt fires again; user picks `y`; branch already exists with the prior plan commit; existing-branch handler checks it out and treats this as a resume. The auto-commit step writes the updated plan and commits.

   This matches `/en-plan --resume` semantics — `/en-plan` is already idempotent on the plan file; the checkpoint extends that to the branch.

## Change 2 — `/en-plan` SKILL.md flags table

Add one new flag to the existing flags table (the existing `--commit-branch`, `--no-commit` stay unchanged):

| Flag | Effect |
|---|---|
| `--branch-on-default <y\|current\|no-commit>` | Pre-answer the default-branch checkpoint prompt. Useful for non-interactive runs (CI, automation scripts). Bypasses the prompt entirely; goes straight to the corresponding action. If the user is NOT on the default branch, this flag has no effect. |

Examples:
- `--branch-on-default y` — auto-create branch silently. Equivalent to typing `y` at the prompt.
- `--branch-on-default current` — opt out silently, commit on default branch. For workflows where the user has a real reason to want plans on main.
- `--branch-on-default no-commit` — skip auto-commit silently.

Other valid escape hatches that already exist:
- `--commit-branch <name>` — specify the branch explicitly; bypasses the checkpoint.
- `--no-commit` — skip auto-commit entirely; bypasses the checkpoint.

## Change 3 — `/en-plan` report output

The `/en-plan` skill currently surfaces a summary at the end of the run (line 117+ of SKILL.md):

```
Plan: docs/plans/active/EN07-feature_auth-rotation.md (5 units, 380 lines)

Units:
  ...

Peer review: cross-agent (codex). Verdict: revise. Applied 2 of 3 findings (1 deferred to TD8).

Next: /en-build docs/plans/active/EN07-feature_auth-rotation.md
```

Extend the report to include a `default_branch_checkpoint:` line when the checkpoint fired (omit when it didn't apply, i.e. user wasn't on default branch):

```
Plan: docs/plans/active/EN07-feature_auth-rotation.md (5 units, 380 lines)

...

default_branch_checkpoint: auto_branched (created EN07-feature_auth-rotation from main)
```

For `committed_to_default_branch`, include a brief audit note so the explicit opt-in is visible:

```
default_branch_checkpoint: committed_to_default_branch (user explicit opt-out; plan landed on main)
```

This makes the checkpoint decision auditable in chat transcripts and lets `/en-ship` later read the report (or git log) to know which branch the plan landed on.

## Change 4 — `docs/foundation.md` (§D-N)

Add a new decision entry to `docs/foundation.md`:

> **D-N. `/en-plan` and `/en-foundation` auto-branch off the default branch.** When invoked from the repo's default branch (per three-source detection: `gh defaultBranchRef` → `git symbolic-ref` → hardcoded fallback), the auto-commit step prompts the user before committing. Default action is to create a feature branch (`<plan_id>-<slug>` for `/en-plan`; `foundation-bootstrap` or similar for `/en-foundation`) and commit there. Reverses the original PR #6 decision to commit on the current branch; the friction of plans landing on `main` (bypassing PR review, mixing design/implementation history) outweighed the discoverability benefit. Users who genuinely want plans on the default branch get an explicit `current` opt-out in the prompt — surfaced, not hidden. Scope: literal default branch only; broader "protected branches" coverage is a future extension via `.ensemble/config.local.yaml` `protected_branches:` list.

Number assignment: use the next available decision number in foundation §11+ (probably D-32 or higher; resolve at PR time).

## Change 5 — `.ensemble/config.local.example.yaml` documentation

**File:** `references/templates/config-local-example.yaml`.

Add a commented section documenting the future `protected_branches` config:

```yaml
# Future enhancement (not yet implemented in /en-plan or /en-foundation):
# Extend the default-branch auto-branch checkpoint to additional long-lived
# integration branches (gitflow develop, release branches, etc.). When set,
# any branch in this list triggers the same prompt as the default branch.
#
# protected_branches:
#   - develop
#   - trunk
#   - release/*  # glob patterns will be supported
```

Documenting the extension point in the example file makes it discoverable for users who need it AND signals to future contributors that the detection logic is designed for this extension.

## Drift guards

New assertions in `tests/peer-resolution-trailer/peer-resolution-trailer.test.sh` (or a new file `tests/en-plan/auto-branch-checkpoint.test.sh` — see U6 in implementation outline):

| # | Assertion |
|---|---|
| 1 | `skills/en-plan/SKILL.md` step 15 mentions "default-branch checkpoint" (or equivalent) BEFORE the existing "stage and commit" logic. |
| 2 | The checkpoint has all four response options documented (`y`, `no-commit`, `current`, `details`) with their canonical report values. |
| 3 | The checkpoint records a structured outcome line (`default_branch_checkpoint:` field in the report). |
| 4 | The checkpoint supports **exactly four** outcome values, spelled exactly: `auto_branched`, `no_commit_requested`, `committed_to_default_branch`. (`details` doesn't produce an outcome — it re-prompts.) Bare words `branched`, `skipped`, `main`, or `kept_on_main` must NOT appear as outcome values. |
| 5 | The skill documents three-source default-branch detection: `gh repo view`, `git symbolic-ref refs/remotes/origin/HEAD`, hardcoded fallback. |
| 6 | The hardcoded fallback list is exactly: `main`, `master`, `develop`, `trunk`. (Adding or removing entries here without a deliberate decision is a regression.) |
| 7 | Branch name convention is `<plan_id>-<slug>` (matches `/en-build`). Test asserts the literal `<plan_id>-<slug>` pattern appears in step 15. |
| 8 | `--branch-on-default <y\|current\|no-commit>` flag is documented in the flags table. |
| 9 | The existing-branch handler is documented: branch with only plan commits → check out and resume; branch with non-plan commits → refuse and ask. |
| 10 | `docs/foundation.md` has a decision entry covering the auto-branch behavior. |
| 11 | `references/templates/config-local-example.yaml` documents `protected_branches:` as a future enhancement (commented). |
| 12 | The `current` opt-out is described as "explicit opt-in to commit on default branch" (catches drift back to "hidden" or "discouraged" framing — the opt-out should be discoverable, not penalized). |

## Implementation outline

5 units, Standard depth. **Build order matters**: U1 (SKILL.md changes) is the load-bearing piece; the rest support it.

- **U1** — `skills/en-plan/SKILL.md`: insert the default-branch checkpoint as sub-steps in step 15. Three-source detection, four-response handler, idempotency note, existing-branch logic. Update the flags table with `--branch-on-default`. Update the report output template to include the `default_branch_checkpoint:` line.

  **Risk:** medium (changes the default auto-commit behavior; affects every `/en-plan` run on default branch). **Category:** feature. **Gated:** false (not a production-state change; behavior change happens at design time, not runtime).

- **U2** — `docs/foundation.md`: add decision entry (D-N) documenting the auto-branch behavior. Resolve the actual number at PR time based on what's already in foundation §11+.

  **Risk:** low. **Category:** other (doc update). **Gated:** false.

- **U3** — `references/templates/config-local-example.yaml`: add commented `protected_branches:` section as documented future enhancement. Signal the extension point to users and future contributors.

  **Risk:** low. **Category:** other (doc update). **Gated:** false.

- **U4** — `tests/peer-resolution-trailer/peer-resolution-trailer.test.sh` (or new `tests/en-plan/auto-branch-checkpoint.test.sh`): +12 drift-guard assertions per the table above. Decide test-file home based on whether existing en-plan tests exist or whether the trailer-test file is the right place.

  **Risk:** low. **Category:** feature. **Gated:** false.

- **U5** — Verification: run `tests/run.sh` + `bin/ensemble-lint` + manual spot-check of step 15 prose. Confirm the structured outcome line renders correctly in the example output, and that the four canonical enum values are spelled identically across SKILL.md, foundation §D-N, and the drift-guard tests.

  **Risk:** low. **Category:** diagnostics. **Gated:** false.

## What's deliberately NOT in this PR

- **`/en-foundation` getting the same treatment.** Same friction class, same pattern, but separate skill. Ship independently in a follow-up — easier to review each in isolation, and `/en-plan` is the higher-frequency invocation (so it captures more value first).
- **`.ensemble/config.local.yaml` `protected_branches:` runtime support.** Documented as a future extension; the detection logic in U1 is designed to accommodate it (`default_branch + (future) configured list`), but reading the config and acting on it is a separate change.
- **`/en-plan --batch` or other non-interactive modes.** The `--branch-on-default` flag covers the common case (pre-answer the prompt). A fuller non-interactive story (all prompts pre-answered) is a larger scope.
- **Existing-branch conflict resolution beyond "refuse and ask."** If the branch exists with non-plan commits, we surface the conflict and ask. We don't try to auto-merge or auto-rename. Smart conflict handling is out of scope.

## Open questions (for review before implementation)

1. **Should `--branch-on-default` accept `auto` as a value, mapping to "follow the prompt's default"?** I.e., `--branch-on-default auto` would pick `y` if on default branch, do nothing if not. Probably unnecessary — omitting the flag already gives interactive default. Lean: no `auto` value.

2. **What about a `--commit-branch` interaction?** Currently `--commit-branch <name>` bypasses the checkpoint (user is being explicit about the branch). Should we still warn if `<name>` equals the default branch? E.g., `--commit-branch main` from `main` — should that prompt, or just commit silently?

   Lean: respect the flag. If the user explicitly typed `--commit-branch main`, they meant it. The checkpoint exists to catch the implicit case (user didn't think about which branch). An explicit flag isn't implicit.

3. **Should the report's `default_branch_checkpoint:` line appear in ALL runs (with value `not_applicable` when user wasn't on default), or only when the checkpoint fired?** Showing it always makes the audit trail uniform; showing it only when it fired keeps reports cleaner.

   Lean: only when it fired. The audit value is the *decision*, not the *non-event*. Adding `not_applicable` lines bloats reports without adding signal.

## Verification plan

- All existing tests still pass.
- +12 new drift-guard assertions covering the new contract.
- Manual sanity check: run `/en-plan` from `main` in a test repo; confirm prompt fires with all four options; confirm each option produces the expected outcome; confirm `--branch-on-default y` runs non-interactively.
- Manual sanity check: run `/en-plan` from a feature branch; confirm checkpoint does NOT fire (current behavior preserved).
- Manual sanity check: run `/en-plan --branch-on-default current` from `main`; confirm it commits to `main` silently AND records `committed_to_default_branch (user explicit opt-out)` in the report.

## Review history

Initial spec (this document).
