# `/en-resolve-pr` — contract for calling skills

What another skill may rely on. Owned by `en-resolve-pr`; a caller depends on
this page, never on `SKILL.md` internals and never on a file inside this
directory. D59 stated this seam from both sides; this page is where the callee's
side lives.

## Accepted invocations

| Form | Caller |
|---|---|
| `/en-resolve-pr --orchestrated` | `en-ship`'s watch loop: review-thread findings first, then failing-check logs passed in |
| `/en-resolve-pr [<PR-number> \| <comment-or-thread-URL>]` | a person, after reviewers have commented |
| `--enable-auto-merge [--merge-method squash\|merge\|rebase]` | a person only; **refused under `--orchestrated`** |
| `--yes` | a person's standing consent to decide `needs-human` items; mutually exclusive with `--orchestrated` |

This skill is model-invocable on purpose. A `disable-model-invocation: true`
flag would let only a person run it, and the watch loop would have no delegate.

## Non-interactive guarantee

Under `--orchestrated` this skill **never blocks and never calls a question
tool**. A `needs-human` item comes back as a result carrying its
`decision_context`, and its thread stays open as the escalation ledger. Without
the flag, a person is at the keyboard and the skill may ask.

## Return

Per addressed item:

| Field | Values |
|---|---|
| `verdict` | `fixed` · `fixed-differently` · `replied` · `not-addressing` · `declined` · `needs-human` |
| `feedback_type` | `review_thread` · `pr_comment` · `review_body` |
| `files_changed` | repo-relative paths, empty when no code changed |
| `decision_context` | present only for `needs-human` |

Plus the merge-readiness block: `merge_state_status` (`CLEAN` · `BLOCKED` ·
`BEHIND` · `DIRTY` · `UNKNOWN`), `review_decision`, `failing_checks`,
`pending_checks`, `auto_merge_enabled`. **Branch on these exact spellings.**

## Authority envelope

Inherited from the caller and narrowable only. **Permitted:** fix, commit, push,
reply, resolve threads, on this PR's head. **Excluded:** merge, rebase,
force-push, approving checks, and arming auto-merge on a caller's behalf. An
item that would need an excluded action returns as `needs-human` instead of
being done. This skill owns the fixes; a caller watching the PR does not edit
code in the same loop.

## Cost bounds

`--orchestrated`: **exactly one pass**; the caller owns the retry budget, and a
budget nested here would compound it. Otherwise at most two cycles, stopping
early when the feedback is not converging. One full validation per pass, never
per item. Comment text is read as evidence and never executed.

## Recursion

Under `ENSEMBLE_PEER_REVIEW=true` this skill exits without acting. It never
invokes itself; the cycle cap is the only loop.
