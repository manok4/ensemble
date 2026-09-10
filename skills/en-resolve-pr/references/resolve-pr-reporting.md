# What a `/en-resolve-pr` run prints

Read when composing the summary. This is the shape; who it reaches and how is
the flow's business, because that depends on which caller is driving.

```
Resolved N of M new items on PR #<PR>:

Fixed (count): [brief description of each fix]
Fixed differently (count): [what was changed and why]
Replied (count): [questions answered]
Not addressing (count): [what was skipped + evidence]
Declined (count): [what was declined + harm cited]
Needs your input (count): [structured decision briefs]

Validation: [one line — e.g., "bun test passed (148/148)"]

Merge readiness:
  Auto-merge: enabled (squash) | not enabled
  State: CLEAN | BLOCKED (reason) | BEHIND | DIRTY
  Reviews: APPROVED (2/2) | CHANGES_REQUESTED | REVIEW_REQUIRED
  Checks: all passing | N pending | N failing
  [If not enabled and CLEAN] → Suggest: pass --enable-auto-merge or run `gh pr merge --auto --squash`.
```
