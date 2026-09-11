---
title: A second round of findings inside the first round's fixes is a design signal
applies_when: A review pass rejects an artifact again and the new findings are in the fixes the previous round applied, not beside them
date: 2026-09-11
tags: [peer-review, refactoring, concurrency, shell]
related: []
status: active
---

# A second round of findings inside the first round's fixes is a design signal

When round N's findings are *inside* round N-1's fixes rather than beside them,
stop fixing findings and ask what single decision is generating them. EN17's
`skills/*/scripts/ensemble-run-metrics` took four cross-agent passes, verdicts
reject, reject, reject, revise, and rounds two and three each found their
defects in the previous round's repairs. Every one traced to one structural
choice: `runs/active` was a mutable stack, so it needed a lock; the lock needed
ownership, staleness and a spin budget; and each of those grew its own defect.
A rewrite clobbered a concurrent append and lost 5 registrations of 12. The lock
leaked from an argument check that exited the critical section, after which every
later pop skipped silently. Its ownership test `[ -d "$af.lock" ]` succeeded
precisely when *another* process held it. The prune deleted exactly the runs
awaiting a publish retry. Replacing the stack with an append-only log, where
`start` appends `+` and `finish` appends `-` and resolution replays the tail
backwards, removed the lock, the spin, the staleness sweep, the prune and the
pop together, came out 43 lines smaller, and produced the first non-reject. The
tell is specific and worth trusting: a second reject whose findings sit beside
the first round's is ordinary review, while one whose findings sit inside them
means the design is generating them faster than they can be patched.
