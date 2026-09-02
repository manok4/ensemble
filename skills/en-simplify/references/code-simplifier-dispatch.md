# Code-simplifier dispatch

How the three reviewers are dispatched, what they receive, and what happens when
one of them cannot run.

> **This file described a per-unit pass until 2026-09-02.** D29 dispatched the
> simplifier inside `/en-build`'s unit loop, between two verification gates, once
> per `U<N>`. **D52 removed that**: the host implements every unit and one
> branch-level pass runs once in `/en-build`'s post-build phase, over the whole
> branch diff.
> The per-unit shape, the `U<N>` prompts and the two-gate diagram are gone
> because the thing they described is.

## The shape now

```
all units commit → cheap gate (lint + typecheck) → SIMPLIFY → branch review → full suite → commit
                                                      ▲
                                                  this pass
```

One pass, one scope: `git diff <merge-base>..HEAD`. `/en-build` skips it entirely
on a docs-only or trivial branch, so this file no longer carries a triviality
heuristic — the caller owns that decision, and duplicating it here would let the
two drift.

## The reviewers are read-only

Three dimensions run **concurrently against one working tree**. They return
findings; the parent applies them at step 5.

`code-simplifier`'s own description says it may modify files. That is true of it
in other contexts and must not be true here: three agents editing the same files
at once is a race whose result depends on scheduling, and the losing edits vanish
without an error. **State the read-only constraint in each dispatch prompt** —
do not rely on the agent inferring it from how it was called.

## What each reviewer receives

- The resolved scope: the full diff, or the file set.
- Its dimension's rubric, **passed verbatim**. Read it and pass the text; a rubric
  re-rendered from memory loses the gating rules that keep the pass
  behavior-preserving, and those rules are the reason the dimension is safe to run.
- The project's `CLAUDE.md` and `AGENTS.md` content, so conventions are known.
- The read-only constraint, and the requirement to preserve exact functionality:
  same output for every input, same errors, same side effects, same ordering.

## When a dispatch cannot run

- **Concurrency or active-agent limits are backpressure, not failure.** Leave the
  reviewer queued and retry once a slot frees. Treating a limit as a failed
  reviewer silently drops a whole dimension from the pass.
- **A dispatch that fails for a reason correcting the call will not fix** — no
  subagent primitive on this host, a persistent error — runs **inline in the
  parent** using the same rubric, and the substitution is disclosed in one line
  of the summary. A dimension reviewed inline is weaker than one reviewed in a
  fresh context; a reader who is not told cannot know which they got.
- **Proceed only when all three dimensions have an outcome**, whether dispatched
  or inline. Applying a partial set and reporting it as a pass overstates what
  was checked.

## When verification fails afterwards

The parent applies findings, then verifies. On a break:

1. Identify which applied fix caused it.
2. **Revert that specific change**, not the whole pass.
3. Continue with the rest, and surface the reverted finding in the summary.

Never relax an assertion, weaken a type, or skip a test to make the check pass.
A simplification that cannot survive the project's own checks is not a
simplification.

## Configuration

`simplifier.enabled_default`, `simplifier.skip_on_trivial` and
`simplifier.max_lines_to_run` live in `.ensemble/config.local.yaml`. They gate
whether `/en-build` invokes this pass at all; they do not change what the pass
does once invoked.
