---
name: en-ship
description: "Push clean changes to the remote with a meaningful commit and PR. Pre-flight (lint + typecheck + targeted tests + secret scan + merge-conflict check), conventional-commit message, push, gh pr create. Optional --auto-merge enables gh pr merge --auto --squash. Trigger phrases: 'ship it', 'push and PR', 'open a PR', 'commit and push', 'send for review'."
---

> **Helper resolution.** All `references/X` and `bin/Y` paths in this skill resolve relative to `$ENSEMBLE_ROOT` — the install root (skill at `$ENSEMBLE_ROOT/skills/<name>/`, shared helpers at `$ENSEMBLE_ROOT/{references,bin}/`). Compute once at start: `$ENSEMBLE_ROOT` env var if set; otherwise `$(realpath "$(dirname <this-SKILL.md>)/../..")`. Fail loudly if `$ENSEMBLE_ROOT/references/host-detect.md` does not resolve — that indicates a partial install (run `/en-setup` to repair).


# `/en-ship`

Pre-flight + commit + push + PR. Last-mile shipping; assumes `/en-review` and `/en-qa` have already passed.

## Process

1. **Detect host (light).** Source `$ENSEMBLE_ROOT/references/host-detect.md` for path conventions.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, exit (peer subprocesses don't ship).
3. **Pre-flight.**
   - `git status` — show unstaged + staged + untracked.
   - `git rev-parse --abbrev-ref HEAD` — current branch.
   - `git diff --stat origin/<base>...HEAD` — diff scope.
   - **Merge conflict check** — `git status` for `UU` markers. On detection: stop and surface; do not attempt to ship a conflicted tree.
   - **Default-branch protection** — if `HEAD == main`, ask explicitly: "Pushing directly to `main`. Confirm? (y/N)". Default no.

4. **Learning checkpoint** (first preflight step that can write to the working tree; runs BEFORE lint/typecheck/secret-scan so any files `/en-learn capture` writes go through the rest of preflight). The backstop for the soft `/en-learn` auto-invokes in `/en-build` and `/en-qa` — those should have caught most captures already, but this step ensures no learnings ship without an explicit decision, AND any files written here go through later preflight before being committed.

   1. **CI short-circuit.** If `CI=true` in the env, record `learning_checkpoint: ci_environment` in the en-ship report; skip to step 5. No interactive prompt in CI.
   2. **Determine the capture baseline.** Read `docs/learnings/log.md` and find the latest `## [YYYY-MM-DD] capture | <subject> | <head-sha>` entry. If a SHA is present, baseline = that SHA. If the latest capture entry exists but lacks `| <head-sha>` (legacy format), surface a one-line notice (*"Last capture entry lacks `<head-sha>`. Baseline detection is imprecise until next capture refreshes the log format."*) and fall back to `git log --since=<YYYY-MM-DD>` from that date. If no capture entries exist at all, baseline = `git merge-base HEAD <default-branch>` (since-branch-creation).
   3. **Compute scope.** Run `git log <baseline-sha>..HEAD` (precise) or `git log --since=<baseline-date>` (imprecise legacy fallback). Count commits and diff size.
   4. **Idempotency check.** If the scope is zero commits (no new work since last capture), record `learning_checkpoint: up_to_date`; skip silently to step 5. en-ship runs twice on the same branch don't re-prompt.
   5. **Surface the structured prompt** (NOT a soft prompt — the agent must surface a terminal outcome):
      ```
      Learning checkpoint
      ───────────────────
      <N> commits since last /en-learn capture (<baseline date or "branch creation">).
      Diff: <X> files changed, <Y> lines.
      Recent commits touch: <comma-separated areas from changed files>

      Worth filing learnings before shipping? (yes / skip / details)
      ```
   6. **Handle response.**
      - `yes` → invoke `/en-learn capture` interactively. On completion, resume en-ship preflight at step 5. Record `learning_checkpoint: captured (<N> learnings)` in en-ship's report. **Note**: any files `/en-learn capture` writes (log.md update, new learning pages, possibly architecture/foundation cross-ref updates) are now staged — they'll go through lint/typecheck/secret-scan at steps 5–6 before being committed.
      - `skip` → record `learning_checkpoint: intentionally_skipped` (explicit user decision, auditable). Continue to step 5.
      - `details` → print the commit list + per-area summary; re-prompt with the same options. Loop until terminal response.
   7. **Flag override.** `--no-learning-checkpoint` skips the whole step; record `learning_checkpoint: intentionally_skipped (--no-learning-checkpoint flag)`.

5. **Lint + typecheck + targeted tests on changed files.**
   - Project `lint` command (from `AGENTS.md`).
   - Project `typecheck` command if applicable.
   - Test files matching changed source files (heuristic: same path with `.test.` / `.spec.` / `_test.` insertion).
   - On any failure → stop; surface; offer to run `/en-review` or `/en-qa` to triage.
6. **Secret scan on diff.** Per `$ENSEMBLE_ROOT/references/secret-patterns.md`. Match against high-confidence regexes + file-name red flags.
   - Match → stop; print offenders; suggest `git restore <file>` or `--allow-secrets` (rare).
   - Heuristic match only → surface as warning; let user confirm.
7. **Confirm scope of staging.** Show what will be committed (`git diff --cached` summary). User confirms or revises.

8. **Plan completion checkpoint.** AFTER all blocking preflight checks have passed (lint, typecheck, tests, secret scan, scope confirm) and BEFORE committing. The checkpoint is informational on `incomplete_build` (does NOT gate ship); it catches plans orphaned at `status: in_progress` (or `open`) that should have been flipped to `completed` by `/en-learn capture` step 11 but weren't (dropped soft prompt, skipped capture, etc.).

   **Placement rationale.** This step deliberately runs LATE in preflight — after lint/typecheck/secret-scan/scope-confirm and before commit-message generation. Earlier placement would mutate the plan (flip status, set shipped, git mv) before later checks could fail, leaving the plan recording having shipped when the PR never opened. Late placement makes the lifecycle mutation atomic with the ship commit.

   1. **Plan-branch detection.** Read the current git branch name. Extract `<plan_id>` via case-insensitive regex against the foundation's `plan_id_prefix:` (e.g. `EN`, `FR`) — branch name pattern is `<plan_id>-<slug>` per `/en-plan`'s default-branch checkpoint. **Normalize the extracted ID to the canonical (uppercase) form** before any filesystem lookup: `/en-build` may create lowercase branches (e.g. `fr07-auth-rotation`) while plan files are named with the uppercase prefix (`FR07-feature_auth-rotation.md`); on case-sensitive filesystems an unnormalized lookup misses the plan and silently records `not_applicable`, defeating the checkpoint. If no plan_id derivable → record `plan_completion_checkpoint: not_applicable`; skip silently to step 9.

   2. **Plan file lookup.** Using the normalized (uppercase) plan_id from step 1, look for `docs/plans/active/<plan_id>-*.md`. If found, read frontmatter; otherwise check `docs/plans/completed/<plan_id>-*.md` (already shipped; outcome `up_to_date`). If neither exists → outcome `not_applicable`; skip silently to step 9.

   3. **Status inspection.**
      - `completed` → record `plan_completion_checkpoint: up_to_date`; skip silently to step 9.
      - `in_progress` OR `open` → continue to completeness check. **The `open` case is intentional**, NOT a typo: it preserves the recovery path from `/en-learn` step 11, which handles "build started but skipped the `open → in_progress` flip" (interrupted build, manual resume, etc.). If the work IS verifiably complete (per step 4 below), the checkpoint flips `open → completed` directly.
      - `draft` → record `plan_completion_checkpoint: not_applicable`; surface a one-line notice ("plan still in draft state; finalize via /en-plan before shipping"); skip to step 9.
      - `abandoned` → record `plan_completion_checkpoint: not_applicable`; terminal state; skip to step 9.

   4. **Build completeness check** (accepts per-unit OR branch-level evidence). A unit's build is complete when **either**:
      - **(per-unit, legacy)** its U-ID has ≥1 unit commit carrying a peer-evidence trailer (`peer-verdict:`, `peer-resolution:`, or `peer-skipped:`), verified via `$ENSEMBLE_ROOT/bin/ensemble-verify-peer-evidence <sha>`; **or**
      - **(branch-level, lfg model)** its U-ID appears in the `covered_units` from `$ENSEMBLE_ROOT/bin/ensemble-verify-peer-evidence --branch-coverage <merge-base>..HEAD --json` — i.e. the post-build branch-level review (`review-verdict:` trailer) covered it.

      Compute `covered_units` once, then for each plan U-ID check per-unit evidence first, then branch-level coverage. If every U-ID is covered by one path or the other → build complete; continue to step 5. If any U-ID has neither per-unit evidence nor branch-level coverage → outcome `incomplete_build`; list the uncovered U-IDs; surface a one-line notice; skip to step 9 (PR still opens — informational, not blocking).

   4a. **What counts as a "unit commit"** (audit-scope discriminator). A commit on the plan branch is a *unit commit* if AND ONLY IF its subject line contains a U-ID pattern (`U<N>` where `<N>` is a positive integer) matching one in the plan AND it has ≥1 of the three peer-evidence trailer types. Specifically excluded:
       - The initial `docs(plan): <plan_id> <slug>` commit from `/en-plan`'s auto-commit step — has no U-ID and no peer-evidence trailers; not a unit commit.
       - Merge commits.
       - Manual cleanup commits, doc fixes, gitignore updates — no U-ID in the subject.

       The audit walks commits on the branch since `git merge-base HEAD <default-branch>`, extracts U-IDs via regex from each subject, and only counts commits whose subject matches a U-ID in the plan AND that have evidence trailers. Non-unit commits are ignored — they're not part of the build-completeness signal.

   5. **Surface the checkpoint prompt** (structured):
      ```
      Plan completion checkpoint
      ──────────────────────────
      Plan `<plan_id>-<slug>` is still at `status: <in_progress|open>`.
      All <N> units have peer-evidence trailers on unit commits; the
      build is verifiably complete.

      Mark the plan as completed and move to docs/plans/completed/?
        y       (recommended) — flip status, set shipped: <today>, git mv to completed/
        skip                — leave at <in_progress|open>; you flip manually later
        details              — show per-unit completion state
      ```

   6. **Handle response.**
      - `y` (default): perform the lifecycle flip atomically with the commit that's about to fire at step 10 —
        - Set `status: completed` in plan frontmatter.
        - Set `shipped: <today>`.
        - `git mv docs/plans/active/<plan-file>.md docs/plans/completed/<plan-file>.md`.
        - `git add` the renamed file (the rename + frontmatter edit are now staged).
        - Continue to step 9 (commit-message generation); the lifecycle flip becomes part of the same commit as the ship work. **If push or PR-create at step 11 / 12 fails, the lifecycle flip is locally committed but the ship didn't complete remotely.** This is acceptable: the local state correctly records the plan as completed (the work IS done), and the user can rerun `/en-ship` to retry the remote operations. Next run sees `completed` → `up_to_date`.
        - Record `plan_completion_checkpoint: completed_and_moved`.
      - `skip`: record `plan_completion_checkpoint: skipped_by_user` with an audit-friendly note ("user explicit skip; plan stays at <in_progress|open>"). Continue to step 9 with no mutation.
      - (For reference, the other terminal outcomes — `plan_completion_checkpoint: up_to_date`, `plan_completion_checkpoint: not_applicable`, `plan_completion_checkpoint: incomplete_build` — are set automatically from earlier steps; see sub-steps 1–4.)
      - `details`: show per-unit completion state (U-ID, unit-commit SHA, evidence trailer count, U-ID's risk classification). Show plan-branch detection source. Re-prompt; loop until terminal option.

   7. **Idempotency.** Re-running `/en-ship` on the same branch after the checkpoint flipped status to `completed`:
      - Status inspection finds `completed` → outcome `up_to_date`; checkpoint silently passes.
      - No re-prompts. No double-flip. The state machine moves forward only.

   8. **Flag override.** `--no-plan-completion-checkpoint` skips the whole step; record `plan_completion_checkpoint: skipped_by_user (--no-plan-completion-checkpoint flag)`.

9. **Generate conventional-commit message.** Per `$ENSEMBLE_ROOT/references/conventional-commits.md`:
   - Inspect the diff to determine `<type>` (`feat` / `fix` / `docs` / `refactor` / etc.).
   - Pick `<scope>` from existing scopes in recent git log + the file paths touched.
   - Compose `<subject>` ≤ 50 chars, imperative mood, no trailing period.
   - Compose `<body>` explaining WHY at 72-char wrap.
   - Add trailers: `Fixes: #<n>`, `Resolves: TD<n>`, `Co-authored-by:` if applicable.
   - User can revise the proposed message.
10. **Commit.** Use HEREDOC for body to preserve formatting:
   ```bash
   git commit -m "$(cat <<'EOF'
   <type>(<scope>): <subject>
   
   <body>
   EOF
   )"
   ```
11. **Push.**
   - Feature branch → `git push -u origin <branch>`.
   - Default branch (after explicit confirmation) → `git push origin <default>`.
12. **Open PR via `gh pr create`.**
    - Title from commit subject (or summary across commits if multiple).
    - Body auto-generated:
      - **Summary** — 1–3 bullets from the commits.
      - **Test plan** — checkbox list of what was tested (from `/en-qa` report if available, otherwise generated from changed files).
      - Plan reference: `Closes plan: <resolved-plan-path>` if the branch name carries a recognizable plan ID (`<PREFIX><NN>`). The resolved path depends on the step-8 checkpoint outcome:
        - `completed_and_moved` → use `docs/plans/completed/<PREFIX><NN>-<plan_type>_<slug>.md` (the plan was just renamed; the active/ path no longer exists).
        - `up_to_date` → use `docs/plans/completed/<PREFIX><NN>-<plan_type>_<slug>.md` (already in completed/ from a prior ship).
        - `skipped_by_user`, `incomplete_build`, `not_applicable` → use `docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md` (plan stayed in active/).
    - Use HEREDOC for body to preserve formatting.
    - On PR-creation success → return URL.
13. **Watch loop (default ON).** After the PR opens, watch it for issues and resolve them automatically — bounded. **Never auto-merges** (the user merges when the PR is ready).
    1. Poll the PR for new review comments and CI status: `gh pr checks` (CI) and `gh pr view --json reviewDecision,comments` (reviews). Re-poll on a sensible cadence (e.g. `gh pr checks --watch` for CI; re-fetch reviews between rounds).
    2. When issues appear (failing checks OR new review comments), invoke `/en-resolve-pr` to address them. en-resolve-pr applies fixes, replies, and resolves threads per its 6-verdict rubric.
    3. **Bounded to 2 cycles.** After the 2nd resolve cycle, stop and **escalate**: surface remaining unresolved items as needs-human (mirrors `/en-resolve-pr`'s own cap and ce-resolve-pr-feedback). Do not loop indefinitely.
    4. **Exit conditions:** all checks green AND no unresolved review threads → surface *"PR is green and clean — ready for your review/merge."*; PR merged/closed externally → stop; 2-cycle cap hit → escalate and stop.
    5. **No auto-merge.** The watch loop never runs `gh pr merge`. Merging is the user's explicit action.
    - Disable with `--no-watch` (open the PR and stop).
14. **Optional auto-merge.** Only when the user explicitly opts in with `--auto-merge` AND CI is green AND branch protection allows:
    - `gh pr merge --auto --squash` (or `--rebase` per repo convention).
    - Surface: "Auto-merge enabled; PR will merge when CI passes."
    - **Default OFF**, and mutually exclusive with the default watch loop — `--auto-merge` implies you want hands-off merging instead of the watch-and-fix loop.

## Flags

| Flag | Effect |
|---|---|
| `--draft` | Open as draft PR |
| `--no-pr` | Push but don't open a PR (e.g., for branches that aren't user-facing) |
| `--auto-merge` | Enable auto-merge after CI passes (hands-off merge; replaces the default watch loop). |
| `--no-watch` | Open the PR and stop — skip the default post-PR watch-and-resolve loop (step 13). |
| `--allow-secrets` | Bypass the secret scan (use sparingly; surface warning) |
| `--base <branch>` | Override PR target base |
| `--reviewers <list>` | Request reviewers via `gh pr create --reviewer` |
| `--no-test-on-changed` | Skip targeted-test step (rare; usually leave on) |
| `--no-learning-checkpoint` | Skip the learning-checkpoint step (step 4). Records `learning_checkpoint: intentionally_skipped (--no-learning-checkpoint flag)` in the report for audit. |
| `--no-plan-completion-checkpoint` | Skip the plan-completion checkpoint (step 8). Records `plan_completion_checkpoint: skipped_by_user (--no-plan-completion-checkpoint flag)` for audit. |

## Cross-review

**Off.** By this point, `/en-review` and `/en-qa` have already passed. Re-running cross-review costs more than it surfaces.

## Output

```
Branch: fr07-auth-rotation
Diff:   12 files changed, 247 insertions, 38 deletions

Pre-flight:
  ✓ learning_checkpoint: captured (2 learnings)
  ✓ Lint
  ✓ Typecheck
  ✓ Targeted tests (8 changed files; 14 tests passed)
  ✓ Secret scan (clean)
  ✓ plan_completion_checkpoint: completed_and_moved (FR07-auth-rotation → completed/; shipped: 2026-05-20)

Commit:
  feat(auth): rotate refresh token on every access — U1-U5

Pushed to origin/fr07-auth-rotation.

PR opened: https://github.com/manok4/ensemble/pull/42
Title: feat(auth): rotate refresh token on every access
Reviewers requested: <none>
Auto-merge: disabled (pass --auto-merge to enable)

Next: Run /en-resolve-pr when reviewers leave comments,
      or `/loop 30m /en-resolve-pr` to poll periodically.
```

## Reference files

- `$ENSEMBLE_ROOT/references/conventional-commits.md` — message format
- `$ENSEMBLE_ROOT/references/secret-patterns.md` — secret-scan regex catalog
- `$ENSEMBLE_ROOT/references/host-detect.md`

## Failure protocol

| Failure | Behavior |
|---|---|
| Lint or typecheck fails | Stop; surface; suggest `/en-review` |
| Targeted tests fail | Stop; surface failing test names; suggest `/en-qa` |
| Secret scan matches high-confidence pattern | Stop; print offenders; require `--allow-secrets` to override |
| Merge conflict | Stop; do not attempt ship on conflicted tree |
| User pushes to `main` without confirm flag | Refuse; require `--allow-main-push` |
| `gh pr create` fails (auth, repo permissions) | Surface error; commit + push succeed regardless; user can open PR manually |
| Auto-merge requested but branch protection rejects | Surface; PR remains open; user reviews and merges manually |
| Unstaged dirty tree at start | Ask user: stage all, stage nothing (abort), or list-and-pick |
| Branch is detached HEAD | Refuse; ask user to check out or create a branch first |

## What this skill never does

- **Never force-pushes.** Force is a destructive operation; user invokes manually if needed.
- **Never amends published commits.** Always creates a new commit.
- **Never skips hooks** (`--no-verify`). If a pre-commit hook fails, the user investigates.
- **Never deletes branches.** Cleanup is the user's call.
- **Never bypasses branch protection.** If the repo requires N reviews, sweep-style auto-merge isn't appropriate here either.
