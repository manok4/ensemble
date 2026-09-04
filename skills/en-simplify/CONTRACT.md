# `/en-simplify` — contract for calling skills

Owned by `en-simplify`. Callers depend on this page, not on `SKILL.md`.

## Accepted invocations

| Form | Caller |
|---|---|
| `/en-simplify` | `en-build` step 10.2, over the branch diff |
| `/en-simplify --scope <path>` | any caller narrowing to one path |
| `/en-simplify --no-verify` | rare; behavior preservation goes unverified |

Default scope is the current branch diff against its base, so `en-build` passes
no scope.

## Non-interactive guarantee

Invoked by a skill, this runs unattended and never calls a blocking-question
tool.

## Return

A summary plus the changed-file list. The caller records the outcome in a
`simplify-verdict:` trailer whose `outcome` is exactly one of:

`completed` · `not_applicable` · `failed`

`not_applicable` and `failed` both require a `reason`. **A missing trailer is
not a legitimate skip** — an evidence audit treats it as `missing` and fails.

## Authority envelope

This skill edits the working tree and **does not commit**. The caller owns the
commit, which is what lets the caller attach the verdict trailer and revert as
one operation. It never pushes, never opens a PR, and never changes behavior:
every edit must preserve semantics, and the caller's verification gate is what
proves it. On a gate failure the caller reverts these edits and proceeds with
the original implementation.

## Cost bounds

The caller skips it on a docs-only branch, on a trivial diff (under roughly 10
changed lines), or with `--no-simplify`; each skip is recorded as
`not_applicable` with the reason, never as silence. There is no size cap here:
the preflight is a kind gate, and size belongs to the caller.

## Recursion

Does not invoke a peer subprocess, so `ENSEMBLE_PEER_REVIEW` does not change its
behavior.
