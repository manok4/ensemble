# Sweep security model

Sweep opens PRs unattended and the runner merges them without a person in the
loop. That makes it the riskiest automation in Ensemble, and since D101 it runs
on a dedicated machine under an operator's own credentials rather than in a
scoped CI job. This file is the posture that keeps that safe.

## The identity is the machine's, and its permissions are the whole scope

The runner uses whatever `gh auth login` established on the sweep machine and
whatever Codex login is present there. There is no `GITHUB_TOKEN` scoped to a
job and no `permissions:` block; the boundary is the repo access that account
holds. Two consequences:

- **Use a dedicated account, or a fine-grained token scoped to the swept
  repos,** with `contents: write` and `pull-requests: write` and nothing more.
  An operator's personal admin login works, and is also how a sweep bug would
  get to do the most damage.
- **Branch protection decides what that identity may merge.** A required
  human review blocks `gh pr merge`; the runner logs `BLOCKED` and leaves the
  PR open. Nothing in Ensemble approves, bypasses or force-pushes. If the goal
  is hands-off merging, the repo setting has to permit this identity to merge
  green PRs without a review; that is a repository decision, made once, in the
  open.

## Codex runs sandboxed

The runner launches `codex exec -s workspace-write` with network access on
(it needs `gh` and `git push`) and `approval_policy="never"`, so a command the
sandbox refuses is refused, not escalated to a prompt nobody will answer. The
skill's doc-only contract is enforced below that, in git: a batch with a
non-doc path never becomes a PR.

## Doc-only enforcement at runtime

`scripts/ensemble-doc-only-check` runs before every `gh pr create`. It verifies
every staged path is in the allowlist:

- `docs/`
- `AGENTS.md`
- `CLAUDE.md`
- `.ensemble/sweep-summary.md`

Any path outside aborts that batch and names the path in the summary. This
catches the case where the batching logic somehow produced a code-file edit
despite the doc-only contract. **Sweep never modifies code, even by mistake.**

## Merging is the runner's, gated three times

The skill records `merge_eligible` per PR in `.ensemble/sweep-result.json` and
never merges. The runner merges a PR only when the file marks it eligible (the
report-only `/en-review` found no P0/P1), every check on the PR has finished
green, and `gh pr merge --squash --delete-branch` succeeds. A failed check, a
pending check past the timeout, a `BLOCKED` merge state or a missing result
file all leave the PR open with the reason logged. **Fail-closed:** no file, no
merge.

## Trust model

| Actor | Trust |
|---|---|
| The sweep machine's `gh` identity | Trusted to open and merge doc-only PRs on the listed repos. Scope it to that. |
| Anyone with write access to the repo | Trusted as much as sweep; they could disable it. Defence is repo access control. |
| The repo list `~/.ensemble/sweep-repos` | Whoever can edit it decides what gets swept. It is a file on the operator's machine. |
| External PRs | Never swept; the runner only reads the default branch. |

## Disabling sweep

- **One repo:** `sweep.enabled: false` in that repo's `.ensemble/config.local.yaml`
  on the sweep machine, or remove its line from `~/.ensemble/sweep-repos`.
- **Merging only:** `sweep.auto_merge_enabled: false`; PRs open, none merge.
- **The machine:** `install-sweep-schedule uninstall`. The skill stays
  available for manual `/en-sweep`.

## Audit trail

Every sweep PR body carries the source merge SHA, the checks that fired and
their findings, the report-only review verdict and the batch name.
`~/.ensemble/logs/sweep.log` holds every run: gate decision, model and effort,
Codex exit, the summary, and each merge or the reason it did not happen. The
operator can always reconstruct *why* sweep made a change and why it merged.

## Incident response

1. **Revert the offending PR:** `gh pr revert <n>` opens a revert PR.
2. **Stop the schedule:** `install-sweep-schedule uninstall`, or drop the repo
   from the list.
3. **File an issue** documenting the failure mode.
4. **Add a regression test** under `tests/en-sweep/`.
5. **Re-enable** only after the test catches the failure on a fixture.

Sweep is software; it can have bugs; the response is a test, not abandoning
the automation.
