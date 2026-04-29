# Garden security model

Garden auto-merges its own PRs. That requires a careful security posture — it's the riskiest piece of automation in Ensemble. This file documents the safe defaults.

## Default-safe configuration

### Use `GITHUB_TOKEN`, not a PAT

The workflow uses the auto-provided `GITHUB_TOKEN`, **not** a personal access token (PAT). PATs grant broader access; `GITHUB_TOKEN` is scoped to the workflow run and expires when the workflow ends.

```yaml
permissions:
  contents: write       # to commit doc-only fixes
  pull-requests: write  # to open and auto-merge PRs
  issues: write         # to post comments on the source PR
```

**No `actions: write`** (would let garden modify workflows — out of scope).
**No `admin`** (would let garden change repo settings).

### No fork-triggered runs

The workflow uses:

```yaml
on:
  push:
    branches: [main]
```

**Never** `pull_request_target` from forks — that pattern exposes credentials to attacker-controlled code (a fork's PR can modify the workflow file before it runs). Garden runs only on pushes to `main`, which means the code has already been merged by a trusted reviewer.

### Branch protection respected

If the repo's branch protection requires N reviews on PRs to `main`, garden's PRs queue for review rather than auto-merging. Garden detects this via:

```bash
PROTECTION=$(gh api "/repos/${{ github.repository }}/branches/main/protection" 2>/dev/null || echo "{}")
REQUIRED_REVIEWS=$(echo "$PROTECTION" | jq -r '.required_pull_request_reviews.required_approving_review_count // 0')

if [ "$REQUIRED_REVIEWS" -gt 0 ]; then
  echo "Branch protection requires $REQUIRED_REVIEWS review(s); garden PRs will queue for review."
  AUTO_MERGE_ENABLED=false
fi
```

Garden surfaces this in the source-PR comment and exits gracefully with PRs open but not merging.

### Doc-only enforcement at runtime

`bin/ensemble-doc-only-check` runs as a workflow step before `gh pr create`. Verifies every staged path is in the allowlist:

- `docs/`
- `AGENTS.md`
- `CLAUDE.md`
- `.github/workflows/en-garden.yml`
- `.ensemble/garden-summary.md`

Any path outside → abort PR creation; fail loudly with the offending path; post to source PR comment.

This catches the case where garden's batching logic somehow produced a code-file edit despite the doc-only contract. **Garden never modifies code, even by mistake.**

### Auto-merge disabled on detection failure

If any guard check errors out (rate-limited GitHub API; auth failure; allowlist check throws), garden leaves all PRs open for human review and does not auto-merge. Fail-closed.

```bash
set -e  # any error → exit non-zero → workflow fails → no auto-merge
```

## What auto-merge requires

For a garden PR to auto-merge:

1. PR is doc-only (verified by `bin/ensemble-doc-only-check`).
2. `/en-review` in `mode:report-only` returns no P0/P1 findings.
3. CI checks (project tests, lint) pass.
4. Branch protection's review requirement is met (e.g., approval count ≥ required).

If any of these fail, the PR stays open for human resolution.

## Trust model

| Actor | Trust |
|---|---|
| `ensemble-garden[bot]` (the workflow's auth principal) | Trusted to modify docs/, AGENTS.md, CLAUDE.md, and the en-garden workflow itself. Nothing else. |
| Anyone with `contents: write` on the repo | Trusted as much as garden — they could disable garden if they wanted. Defense is repo access control. |
| External fork PRs | **Untrusted.** Workflow doesn't run on `pull_request_target` from forks. Their PRs go through the normal review flow. |

## Required setup secrets

The repo needs (in Settings → Secrets):

- `ANTHROPIC_API_KEY` (or `OPENAI_API_KEY`) for the LLM provider that runs garden's checks. The workflow expects whichever the host CLI uses.
- `GITHUB_TOKEN` is auto-provided; no manual setup.

If the secret is missing, garden fails at the LLM step with a clear error — doesn't auto-merge anything.

## What garden never does

- **Never modifies source code, configuration, tests, or any non-doc artifact.** Doc-only contract enforced at runtime via the allowlist.
- **Never bypasses branch protection.** If the repo requires reviews, garden waits.
- **Never force-pushes.** All commits are normal commits; PRs are normal PRs.
- **Never deletes branches** other than its own merged feature branches (post-merge cleanup is optional and disabled by default).
- **Never escalates permissions.** The workflow's `permissions:` block is the entire scope.
- **Never spawns another garden.** Loop guards (`references/garden-loop-guards.md`) prevent recursion.

## Disabling garden

If a project wants to opt out of auto-merging garden PRs:

```yaml
# in .github/workflows/en-garden.yml
env:
  GARDEN_AUTO_MERGE: "false"
```

Garden runs normally and opens PRs but does not auto-merge — they wait for human approval.

To disable garden entirely, delete `.github/workflows/en-garden.yml`. The skill remains available for manual invocation (`/en-garden`) but never runs unattended.

## Audit trail

Every garden PR includes:

- The triggering merge commit SHA in the PR body.
- The list of checks that fired and their findings.
- The `mode:report-only` review verdict from `/en-review`.
- The garden batch name (e.g., `lint-fixes`, `architecture-update`).

The user can always reconstruct *why* garden made a change.

## Incident response

If garden does something unexpected (the rare case of a doc-only-check bypass or a logic bug):

1. **Revert the offending PR** — `gh pr revert <pr-number>` opens a revert PR.
2. **Disable garden** — delete or rename the workflow file in a fast-follow PR (commit message: `chore(ci): temporarily disable en-garden — see <issue>`).
3. **File an issue** documenting the failure mode.
4. **Add a regression test** under `tests/en-garden/` for the failure mode.
5. **Re-enable garden** only after the test catches the failure on a fixture.

This is the standard response — garden is software; it can have bugs; the response is to add a test, not to abandon the automation.
