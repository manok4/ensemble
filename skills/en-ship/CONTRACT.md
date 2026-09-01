# `/en-ship` — contract for calling skills

Owned by `en-ship`. Callers depend on this page, not on `SKILL.md`.

> Reached this page from EN12's plan? Its U10 file list named a different skill
> here. The call-graph check that unit introduced showed otherwise: nothing
> invoked that skill programmatically, while `en-flow` does invoke this one.
> The derived set is the source of truth, which is the point of deriving it.

## Accepted invocations

| Form | Caller |
|---|---|
| `/en-ship` | `en-flow`, after a green build |
| `--auto-merge` | arms `gh pr merge --auto --squash`; default OFF |
| `--draft` · `--no-pr` · `--base <branch>` · `--reviewers <list>` | PR shape |
| `--no-watch` | open the PR and stop, skipping the watch loop |
| `--allow-secrets` | bypass the secret scan; use sparingly |

## Non-interactive guarantee

**Not guaranteed.** A failed pre-flight (lint, typecheck, targeted tests, secret
scan, merge-conflict check) stops and surfaces rather than shipping. A caller
must handle a stop, not assume a PR exists on return.

## Return

The PR URL plus pre-flight results. On a stop, the failing check and its output.
A caller must not treat a reported URL as a completed hand-off when the watch
loop is still running.

## Authority envelope

**This skill is the widest envelope in the toolkit: it pushes and opens PRs.**
That authority does not extend to its callers and cannot be widened by them. It
never force-pushes, never merges directly (auto-merge is armed, not performed),
and never pushes to the default branch without `--allow-main-push`.
`--allow-secrets` requires an explicit flag precisely because it bypasses a
safety check.

## Cost bounds

The watch loop is bounded; `--no-watch` opts out entirely. The learning
checkpoint does **not** fire here — it belongs to `en-build` alone, so a caller
running both does not get two prompts.

## Recursion

Does not invoke a peer subprocess directly.
