# Default-branch checkpoint — `en-plan`

Read this only when the checkpoint's gate fires: the current branch **is** the detected default branch, and neither `--commit-branch` nor `--no-commit` was passed. Most `en-plan` runs are already on a feature branch and skip this entirely.

Canonical spec: `docs/en-plan-default-branch-spec.md`. This file is the operational subset the skill executes.

The checkpoint resolves the target branch **before** the plan file is written, so a resume run never hits "untracked working tree file would be overwritten" on `git checkout`.

## Detect the default branch

Three-source resolution, first hit wins:

1. `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null`
2. `git symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's|^origin/||'`
3. Hardcoded fallback: check the current branch against `main`, `master`, `develop`, `trunk`. If on one of these AND there is no remote `origin`, assume it is the default.

Detection failing entirely (fresh repo with no commits, detached HEAD) skips the checkpoint: stay on the current branch and proceed to the plan-file write.

## The prompt

```
Default-branch checkpoint
─────────────────────────
You're on `<default-branch>`. Auto-committing plans to the
default branch bypasses PR review and mixes design-stage
commits with main-line history.

Recommended: create feature branch `<plan_id>-<slug>` and commit
the plan there. /en-build will reuse the same branch.

y           (recommended) — create the branch + commit
no-commit              — leave the plan uncommitted; commit manually
current                — commit on `<default-branch>` anyway (opt-out)
details                — show diagnostic info
```

## Handling the response

All branch operations happen **before** the plan-file write, while the working tree is still clean of plan files and `git checkout` can switch freely.

| Response | Action | Recorded in the report |
|---|---|---|
| `y` (default) | Branch `<plan_id>-<slug>` doesn't exist → `git checkout -b <plan_id>-<slug>` from the current commit. Exists → inspect `git log <default-branch>..<branch>`: only paths under `docs/plans/` → `git checkout <branch>` and surface *"Existing branch `<branch>` has prior plan commits; resuming."*; build commits or commits outside `docs/plans/` → **refuse the auto-resume** and prompt for an alternate name (`<plan_id>-<slug>-2` / custom / abort). | `default_branch_checkpoint: auto_branched` |
| `no-commit` | Stay on the current branch, no switch. The auto-commit step is skipped entirely; surface manual instructions. | `default_branch_checkpoint: no_commit_requested` |
| `current` | Stay on the default branch, no switch. The auto-commit step commits there normally, with an audit note. | `default_branch_checkpoint: committed_to_default_branch` |
| `details` | Print diagnostics (detected default branch + which source resolved it, target branch name, whether that branch exists, the `protected_branches:` future-extension note), then re-display the four options. **Non-terminal — loop until a terminal response.** | — |

## Non-interactive runs

`--branch-on-default <y|current|no-commit>` pre-answers the prompt for CI and automation: bypass the prompt and go straight to the corresponding action. The flag has no effect when the current branch is not the detected default branch.

## Future extension

Not implemented: `protected_branches: [...]` in `.ensemble/config.local.yaml` will extend this same prompt to other long-lived branches (`develop`, release branches). Listed so the extension point is discoverable.
