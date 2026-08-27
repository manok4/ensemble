# The capture gate

Read this before writing any learning. It decides whether to write one at all.

**The default is to write nothing.** A wiki earns its keep by being worth reading
end to end. Every entry that restates what the code already says makes the next
agent read more to learn less, so a near-empty wiki of five real constraints
beats fifty entries describing fixes that are visible in the diff.

## The question this gate exists to ask

Not "was this hard?" — hard work often leaves no durable lesson. Not "did we
learn something?" — every session does. The question is:

> **Would a capable agent, reading this codebase with no other context, arrive
> at this on its own?**

If yes, writing it down subtracts value. Coding agents read code well. They read
diffs, tests, types and call graphs, and they reconstruct *what* and *how*
without help. What they cannot reconstruct is anything that left no trace in the
tree: a constraint that lives in a contract, an alternative that was tried and
abandoned, a reason the obvious approach is wrong here.

Capture the parts reading cannot recover.

## The three conditions

All three must hold. Each has a test that produces a **named answer**. If you
cannot name the answer, the condition fails — an unnamed answer means you are
rationalizing, not judging.

**1. Not recoverable from the code.**
*Test:* name the file an agent would read to learn this. If that file now
contains it, do not write. A fix that is legible in its own diff fails here.

**2. Changes a future action.**
*Test:* name the decision this would change, and who is about to make it. "Useful
background" is not a decision. If nothing downstream moves, do not write.

**3. Outlives the occasion.**
*Test:* would this still be true after the module that prompted it is rewritten?
Anything describing current state ("X is broken", "Y is not implemented yet")
fails: that belongs in the tech-debt tracker or an issue, which are built to be
closed.

## What qualifies

Each of these is un-recoverable by reading, which is exactly why it qualifies.

- **Constraints that live outside the code.** A partner API's rate limit, a
  compliance rule forbidding a region, a contractual response-time budget. The
  code obeys them silently and never says why.
- **Paths not taken.** The approach that looked right, was tried, and failed —
  with the reason. This is the single most valuable category for an agent,
  because a tree records what exists and can never record what was rejected.
  Without it the next agent re-runs the same dead end at full cost.
- **Deliberate deviations from the obvious.** Hand-rolled SQL where an ORM was
  available; a lock held longer than it looks like it needs to be. Without a
  note, someone "fixes" it back.
- **Failure modes that do not announce themselves.** A guard that passes because
  its input is missing. A helper that returns a well-formed "failed" result when
  it is itself broken. These cost hours precisely because nothing points at them.
- **Boundary and ownership decisions.** Which module owns a piece of state, and
  what other modules may assume about it. Code shows the current arrangement, not
  which parts are load-bearing.
- **Invariants a reader would not infer.** "This list must stay sorted or the
  binary search upstream breaks." Obvious once stated, invisible until then.

## What does not qualify

These are the entries that make a wiki not worth reading. Most rejected captures
land here.

- **How the code works.** Reading is cheaper than your summary, and your summary
  goes stale while the code does not.
- **What a fix changed.** The diff says it, permanently and precisely.
- **Restating a convention already written down.** If `AGENTS.md`, `CLAUDE.md` or
  a linter enforces it, a second copy only creates a chance to disagree.
- **Point-in-time state.** "The peer path is currently slow." True today, noise
  next month. Tech-debt tracker or an issue.
- **The narrative of the session.** What you tried in what order is interesting
  to you and useless to a reader who wants the conclusion.
- **A lesson with no specific referent.** "Be careful with concurrency." Nobody
  ever acted differently because of a sentence like that.

## Failing the gate

Write nothing. Report which condition failed and what could not be named:

```
No learning filed — condition 2 (changes a future action).
The BASH_SOURCE fix is legible in its own diff, and no future decision turns
on it. The durable part — a helper that returns a well-formed failure when it
is itself broken is indistinguishable from a real failure — is already filed
as silent-failure-modes-2026-08-26.
```

A silent skip is indistinguishable from a skill that did not run, so the report
is not optional. Reporting a skip is a normal successful outcome, not a failure
of the run.

## Judging the borderline

One learning per run. A session producing two distinct durable lessons gets two
runs, because batching pushes the weaker one through on the stronger one's
merit.

When genuinely torn, do not write. The cost is asymmetric: a missed learning
costs one rediscovery, while a bad one is read by every future agent and taxes
all of them. You can always capture it the second time it comes up, and the
second occurrence is itself evidence it was worth capturing.
