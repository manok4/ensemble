# Two situations that change how a thread is read

Neither is a step. Read the first when a thread comes back `isOutdated=true`, and
the second when the branch was rebased during the review. Both cost nothing on a
run where they do not fire, which is most runs.

## Outdated threads

When `isOutdated=true`, the diff hunk has shifted — the reported line may not be where the concern lives. Strategy:

1. Walk location fields in order: `line` → `startLine` → `originalLine` → `originalStartLine`.
2. If none resolve to current content matching the reviewer's description, extract an anchor (symbol, identifier, distinctive phrase) from the comment and search the **same file** once.
3. Three outcomes:
   - Anchor found in the file → re-evaluate at that location with the rubric.
   - Anchor not found and the comment describes concrete in-place code → `not-addressing` with evidence (`searched <file> for <anchor>, not present`).
   - Anchor not found and the comment suggests the code was extracted elsewhere → `needs-human`. Don't grep the whole repo; picking the right new location is a judgment call.

## After a rebase, prior evidence does not carry

Rebasing moves the branch onto a new base, so a review that approved the old head has not seen what is there now, and any verification receipt `/en-ship` was relying on is invalidated by the base moving (`base-moved`). Two consequences worth stating rather than rediscovering:

- **Re-review, do not assume continuity.** A thread resolved against the pre-rebase head may no longer point at the code it was about. Re-fetch before replying to anything, and treat an outdated thread by the rules below.
- **Do not treat a green check from before the rebase as green now.** It described a commit that no longer exists.

This is why rebasing is excluded from what this skill may do: it is not a mechanical fix, it invalidates the evidence around it, and deciding to spend that is the caller's call.
