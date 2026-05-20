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
4. **Lint + typecheck + targeted tests on changed files.**
   - Project `lint` command (from `AGENTS.md`).
   - Project `typecheck` command if applicable.
   - Test files matching changed source files (heuristic: same path with `.test.` / `.spec.` / `_test.` insertion).
   - On any failure → stop; surface; offer to run `/en-review` or `/en-qa` to triage.
5. **Secret scan on diff.** Per `$ENSEMBLE_ROOT/references/secret-patterns.md`. Match against high-confidence regexes + file-name red flags.
   - Match → stop; print offenders; suggest `git restore <file>` or `--allow-secrets` (rare).
   - Heuristic match only → surface as warning; let user confirm.
6. **Confirm scope of staging.** Show what will be committed (`git diff --cached` summary). User confirms or revises.

7. **Plan completion checkpoint.** AFTER all blocking preflight checks have passed (lint, typecheck, tests, secret scan, scope confirm) and BEFORE committing. The checkpoint is informational on `incomplete_build` (does NOT gate ship); it catches plans orphaned at `status: in_progress` (or `open`) that should have been flipped to `completed` by `/en-learn capture` step 11 but weren't (dropped soft prompt, skipped capture, etc.).

   **Placement rationale.** This step deliberately runs LATE in preflight — after lint/typecheck/secret-scan/scope-confirm and before commit-message generation. Earlier placement would mutate the plan (flip status, set shipped, git mv) before later checks could fail, leaving the plan recording having shipped when the PR never opened. Late placement makes the lifecycle mutation atomic with the ship commit.

   1. **Plan-branch detection.** Read the current git branch name. Extract `<plan_id>` via regex against the foundation's `plan_id_prefix:` (e.g. `EN`, `FR`) — branch name pattern is `<plan_id>-<slug>` per `/en-plan`'s default-branch checkpoint. If no plan_id derivable → record `plan_completion_checkpoint: not_applicable`; skip silently to step 8.

   2. **Plan file lookup.** Look for `docs/plans/active/<plan_id>-*.md`. If found, read frontmatter; otherwise check `docs/plans/completed/<plan_id>-*.md` (already shipped; outcome `up_to_date`). If neither exists → outcome `not_applicable`; skip silently to step 8.

   3. **Status inspection.**
      - `completed` → record `plan_completion_checkpoint: up_to_date`; skip silently to step 8.
      - `in_progress` OR `open` → continue to completeness check. **The `open` case is intentional**, NOT a typo: it preserves the recovery path from `/en-learn` step 11, which handles "build started but skipped the `open → in_progress` flip" (interrupted build, manual resume, etc.). If the work IS verifiably complete (per step 4 below), the checkpoint flips `open → completed` directly.
      - `draft` → record `plan_completion_checkpoint: not_applicable`; surface a one-line notice ("plan still in draft state; finalize via /en-plan before shipping"); skip to step 8.
      - `abandoned` → record `plan_completion_checkpoint: not_applicable`; terminal state; skip to step 8.

   4. **Build completeness check** (scope-corrected: unit commits only). For each unit U-ID in the plan, scan commits since the plan branch's creation, identify the unit commit(s) for that U-ID, and verify each unit commit has ≥1 peer-evidence trailer (`peer-verdict:`, `peer-resolution:`, or `peer-skipped:`) via `$ENSEMBLE_ROOT/bin/ensemble-verify-peer-evidence`. If every U-ID has ≥1 unit commit with evidence → build complete; continue to step 5. If any U-ID has no unit commit OR has a unit commit lacking evidence → outcome `incomplete_build`; list the missing U-IDs (and whether they're missing entirely vs. lacking evidence); surface a one-line notice; skip to step 8 (PR still opens — informational, not blocking).

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
      - `y` (default): perform the lifecycle flip atomically with the commit that's about to fire at step 9 —
        - Set `status: completed` in plan frontmatter.
        - Set `shipped: <today>`.
        - `git mv docs/plans/active/<plan-file>.md docs/plans/completed/<plan-file>.md`.
        - `git add` the renamed file (the rename + frontmatter edit are now staged).
        - Continue to step 8 (commit-message generation); the lifecycle flip becomes part of the same commit as the ship work. **If push or PR-create at step 10 / 11 fails, the lifecycle flip is locally committed but the ship didn't complete remotely.** This is acceptable: the local state correctly records the plan as completed (the work IS done), and the user can rerun `/en-ship` to retry the remote operations. Next run sees `completed` → `up_to_date`.
        - Record `plan_completion_checkpoint: completed_and_moved`.
      - `skip`: record `plan_completion_checkpoint: skipped_by_user` with an audit-friendly note ("user explicit skip; plan stays at <in_progress|open>"). Continue to step 8 with no mutation.
      - (For reference, the other terminal outcomes — `plan_completion_checkpoint: up_to_date`, `plan_completion_checkpoint: not_applicable`, `plan_completion_checkpoint: incomplete_build` — are set automatically from earlier steps; see sub-steps 1–4.)
      - `details`: show per-unit completion state (U-ID, unit-commit SHA, evidence trailer count, U-ID's risk classification). Show plan-branch detection source. Re-prompt; loop until terminal option.

   7. **Idempotency.** Re-running `/en-ship` on the same branch after the checkpoint flipped status to `completed`:
      - Status inspection finds `completed` → outcome `up_to_date`; checkpoint silently passes.
      - No re-prompts. No double-flip. The state machine moves forward only.

   8. **Flag override.** `--no-plan-completion-checkpoint` skips the whole step; record `plan_completion_checkpoint: skipped_by_user (--no-plan-completion-checkpoint flag)`.

8. **Generate conventional-commit message.** Per `$ENSEMBLE_ROOT/references/conventional-commits.md`:
   - Inspect the diff to determine `<type>` (`feat` / `fix` / `docs` / `refactor` / etc.).
   - Pick `<scope>` from existing scopes in recent git log + the file paths touched.
   - Compose `<subject>` ≤ 50 chars, imperative mood, no trailing period.
   - Compose `<body>` explaining WHY at 72-char wrap.
   - Add trailers: `Fixes: #<n>`, `Resolves: TD<n>`, `Co-authored-by:` if applicable.
   - User can revise the proposed message.
9. **Commit.** Use HEREDOC for body to preserve formatting:
   ```bash
   git commit -m "$(cat <<'EOF'
   <type>(<scope>): <subject>
   
   <body>
   EOF
   )"
   ```
10. **Push.**
   - Feature branch → `git push -u origin <branch>`.
   - Default branch (after explicit confirmation) → `git push origin <default>`.
11. **Open PR via `gh pr create`.**
    - Title from commit subject (or summary across commits if multiple).
    - Body auto-generated:
      - **Summary** — 1–3 bullets from the commits.
      - **Test plan** — checkbox list of what was tested (from `/en-qa` report if available, otherwise generated from changed files).
      - Plan reference: `Closes plan: docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md` if the branch name carries a recognizable plan ID (`<PREFIX><NN>`).
    - Use HEREDOC for body to preserve formatting.
    - On PR-creation success → return URL.
12. **Optional auto-merge.** If user confirms AND CI is green AND branch protection allows:
    - `gh pr merge --auto --squash` (or `--rebase` per repo convention).
    - Surface: "Auto-merge enabled; PR will merge when CI passes."
    - **Default OFF.** User must explicitly opt in (`--auto-merge` flag).

## Flags

| Flag | Effect |
|---|---|
| `--draft` | Open as draft PR |
| `--no-pr` | Push but don't open a PR (e.g., for branches that aren't user-facing) |
| `--auto-merge` | Enable auto-merge after CI passes |
| `--allow-secrets` | Bypass the secret scan (use sparingly; surface warning) |
| `--base <branch>` | Override PR target base |
| `--reviewers <list>` | Request reviewers via `gh pr create --reviewer` |
| `--no-test-on-changed` | Skip targeted-test step (rare; usually leave on) |
| `--no-plan-completion-checkpoint` | Skip the plan-completion checkpoint (step 7). Records `plan_completion_checkpoint: skipped_by_user (--no-plan-completion-checkpoint flag)` for audit. |

## Cross-review

**Off.** By this point, `/en-review` and `/en-qa` have already passed. Re-running cross-review costs more than it surfaces.

## Output

```
Branch: fr07-auth-rotation
Diff:   12 files changed, 247 insertions, 38 deletions

Pre-flight:
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
