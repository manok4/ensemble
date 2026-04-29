---
name: en-ship
description: "Get clean changes onto the remote with a meaningful commit message and PR. Pre-flight (git status, branch, diff stat, merge conflict check), lint + typecheck + targeted tests on changed files, secret scan on the diff, conventional-commit message generation, push, gh pr create with auto-generated summary. Optional auto-merge if user confirms and CI is green. Use whenever the user is ready to push their work and open a PR. Trigger phrases: 'ship it', 'push and PR', 'open a PR', 'create the PR', 'commit and push', 'send for review'."
---

# `/en-ship`

Pre-flight + commit + push + PR. Last-mile shipping; assumes `/en-review` and `/en-qa` have already passed.

## Process

1. **Detect host (light).** Source `references/host-detect.md` for path conventions.
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
5. **Secret scan on diff.** Per `references/secret-patterns.md`. Match against high-confidence regexes + file-name red flags.
   - Match → stop; print offenders; suggest `git restore <file>` or `--allow-secrets` (rare).
   - Heuristic match only → surface as warning; let user confirm.
6. **Confirm scope of staging.** Show what will be committed (`git diff --cached` summary). User confirms or revises.
7. **Generate conventional-commit message.** Per `references/conventional-commits.md`:
   - Inspect the diff to determine `<type>` (`feat` / `fix` / `docs` / `refactor` / etc.).
   - Pick `<scope>` from existing scopes in recent git log + the file paths touched.
   - Compose `<subject>` ≤ 50 chars, imperative mood, no trailing period.
   - Compose `<body>` explaining WHY at 72-char wrap.
   - Add trailers: `Fixes: #<n>`, `Resolves: TD<n>`, `Co-authored-by:` if applicable.
   - User can revise the proposed message.
8. **Commit.** Use HEREDOC for body to preserve formatting:
   ```bash
   git commit -m "$(cat <<'EOF'
   <type>(<scope>): <subject>
   
   <body>
   EOF
   )"
   ```
9. **Push.**
   - Feature branch → `git push -u origin <branch>`.
   - Default branch (after explicit confirmation) → `git push origin <default>`.
10. **Open PR via `gh pr create`.**
    - Title from commit subject (or summary across commits if multiple).
    - Body auto-generated:
      - **Summary** — 1–3 bullets from the commits.
      - **Test plan** — checkbox list of what was tested (from `/en-qa` report if available, otherwise generated from changed files).
      - Plan reference: `Closes plan: docs/plans/active/FRXX-*.md` if branch name matches FRXX.
    - Use HEREDOC for body to preserve formatting.
    - On PR-creation success → return URL.
11. **Optional auto-merge.** If user confirms AND CI is green AND branch protection allows:
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

Commit:
  feat(auth): rotate refresh token on every access — U1-U5

Pushed to origin/fr07-auth-rotation.

PR opened: https://github.com/manok4/ensemble/pull/42
Title: feat(auth): rotate refresh token on every access
Reviewers requested: <none>
Auto-merge: disabled (pass --auto-merge to enable)
```

## Reference files

- `references/conventional-commits.md` — message format
- `references/secret-patterns.md` — secret-scan regex catalog
- `references/host-detect.md`

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
- **Never bypasses branch protection.** If the repo requires N reviews, garden-style auto-merge isn't appropriate here either.
