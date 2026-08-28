# Grounding validation

The doc just written becomes permanent, trusted knowledge. Future agents will act
on its claims **without re-verifying them**. This step checks the checkable
claims before they compound — while the cost is one correction, not a chain of
decisions built on a dead reference.

Run `scripts/ensemble-validate-claims <file>` after the artifact is written and
before the index and log are updated.

## Never a hard gate

Every finding is **advisory** and is adjudicated, not auto-applied.

A solution doc legitimately cites a path that the fix deleted, or describes a
pre-fix state that no longer exists. Those are correct claims about a moment, and
a hard gate would fail the common case and train you to bypass the check. The
script's job is to notice; yours is to decide.

## Three exit codes, and the third is the point

| Exit | Meaning | What to do |
|---|---|---|
| `0` | Clean | Proceed. |
| `1` | Findings to adjudicate | Walk them. Keep, correct, or qualify each claim. |
| `2` | Operational failure — the validator could not run | The artifact is **unverified**. Record degraded verification. |

**1 and 2 must never collapse.** "This doc has a dead link" and "nothing checked
this doc" are different facts, and only the second means the artifact went
unchecked. A run whose grounding exited 2 may **not** be reported as grounded —
that case is the one that would otherwise look identical to clean.

## Which tree is the ground truth

Two claim categories verify against different trees.

**Code-behaviour claims** — what a function does, what an enum holds, what a
default is — verify against the **local working tree**. They describe what this
session produced and verified here.

**Merge-state claims** — "fixed in #44", "landed", "shipped" — verify against
**remote truth**. The checkout may predate the merge, so `gh pr view` is primary
and local reachability is only a fallback. Before checking, `git fetch --quiet`
is worth trying, but best-effort only: skip silently when it fails or you are
offline. **The network is never a correctness dependency.**

When remote state cannot be checked at all, keep the claim, add an as-of
qualifier ("as of this writing"), and record degraded verification in the report.

## What the script checks

- **Paths** in backticks — repo-relative, since a backticked path in prose reads
  as a location in the tree.
- **Markdown links** — resolved from the **document's own directory**, per
  markdown semantics. Resolving these from the repo root would accept broken
  links and reject valid ones.
- **SHAs** — hex tokens of 7–40 characters, checked with `git cat-file`.
- **Unrendered placeholders** — a doubled-brace token left by a template.

**Fenced blocks are masked.** A doc showing what a path looks like is not
claiming that path exists.

**External URLs are never fetched**, and an anchor checks only that the file
exists — a missing heading is not a finding worth blocking a write over.

## Adjudicating

For each finding, one of:

- **Correct it** — the claim was a typo or the file moved.
- **Keep it and qualify** — the claim is about a past state. Say so in the text:
  "before the fix, that helper held …".
- **Keep it as-is** — the reference is to something outside this tree.

An `unresolved-sha` finding needs care. There is no syntactic way to tell a dead
commit from a colour literal — a dead commit and a colour literal are the same shape — so
the script reports what it could not resolve and does not guess. Most such
findings are false positives, and that is expected: the check is cheap and the
cost of a genuinely dead commit reference is high.
