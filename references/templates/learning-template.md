# Template — `docs/learnings/<category>/<slug>-<date>.md`

Used by `/en-learn capture` (default mode) to file a learning.

## Frontmatter

See `references/learning-frontmatter-schema.md` for the canonical schema and field rules.

## Body structure

The body has a fixed shape so future runs (and `learnings-research` agent) can grep predictably.

```markdown
---
title: <one-line title>
date: YYYY-MM-DD
category: bugs | patterns | decisions | sources
problem_type: <enum>
component: <module-or-area>
applies_when: <one sentence describing when this applies>
tags: [<tag>, ...]
related: [<paths>]
confidence: 1-10
status: active
---

# <Title verbatim>

## TL;DR

<One paragraph. The "if you read nothing else, read this" version.>

## Context

<2-3 paragraphs. What was happening when this came up. The codebase state, the user request, the constraint that mattered.>

## What didn't work

<For bugs: failed hypotheses. For patterns/decisions: alternatives considered.>

- ...
- ...

## Root cause / why this approach

<For bugs: the actual cause, not just symptoms. For patterns: why this design beat alternatives. For decisions: the rationale, including non-obvious factors.>

## Fix / implementation

<For bugs: the diff (or summary), with key snippets quoted. For patterns: code shape with one canonical example. For decisions: the chosen path, with files/commits cited.>

## Why it works

<The mechanistic explanation. What property of the system makes this the right answer.>

## Prevention / when to apply

- **Apply when:** <repeats `applies_when:` from frontmatter and elaborates>
- **Don't apply when:** <opposite condition; common misuses>
- **Watch out for:** <related pitfalls>

## Related

- [<title>](<path>) — <one-line connection>
- ...

## Citations

- Commit: <hash> (or repo path)
- Plan: docs/plans/<active-or-completed>/FRXX-<name>.md
- External source: <URL or file path, if applicable>
```

## Generation notes

- **Slug rules** — lowercase, alphanumeric + hyphens, ≤60 chars. Add `-YYYY-MM-DD` suffix.
- **TL;DR** is required; future grep relies on it.
- **What didn't work** is critical for bugs — failed hypotheses are the highest-signal content for future runs.
- **Citations** must include at least the commit and the plan; external sources optional.
- **Cross-refs** in `related:` must point to existing learning paths; `--lint` will flag broken ones.

## Always-on behaviors after writing

After the write succeeds:

1. Walk `related: [...]` and add reciprocal back-references to each cited page (per `references/learn-cross-ref-maintenance.md`).
2. Append a one-line entry to `docs/learnings/index.md` under the category.
3. Append a single line to `docs/learnings/log.md`: `## [<date>] capture | <title>`.
4. If material structural change → sync `docs/architecture.md` (per `references/architecture-update-rules.md`).
5. If the originating plan exists → flip its status from `active` to `completed`, update `shipped:` field, move file from `docs/plans/active/` to `docs/plans/completed/`.

## Worked example (bug)

```markdown
---
title: "Refresh token race when two requests arrive within rotation window"
date: 2026-04-15
category: bugs
problem_type: concurrency
component: auth-middleware
applies_when: "Multiple concurrent requests from one user during refresh-token rotation"
tags: [auth, refresh-token, race-condition]
related: [docs/learnings/patterns/single-flight-cache-2026-03-20.md]
confidence: 9
status: active
---

# Refresh token race when two requests arrive within rotation window

## TL;DR

Two near-simultaneous requests during token rotation both read the old token, both try to rotate it, the second rotation invalidates the first's new token, and the first caller gets a 401 on the response. Fix: serialize rotation per-user with a single-flight cache.

## Context

The auth middleware rotates the refresh token on every access. Production traffic occasionally fired two API calls within ~50ms (mobile network retries, page-prefetch). When both hit the rotation window, both tried to rotate, and the second rotation invalidated the first.

## What didn't work

- Adding a `refreshing: bool` flag on the user record (lost the in-flight result; second caller still raced)
- Database-level row lock (correct but too coarse for the rest of the request handler)

## Root cause

`rotateRefreshToken()` was a pure function — no de-duplication. Two parallel callers both saw the same old token state.

## Fix

Wrapped in a `singleFlight<K, V>` helper keyed on `user_id`:

```ts
const flight = singleFlight<string, RefreshResult>();

async function rotateRefreshToken(userId: string) {
  return flight(userId, async () => actualRotate(userId));
}
```

Single rotation fires; concurrent callers await the same promise.

## Why it works

The single-flight cache de-duplicates concurrent calls keyed on `user_id`. Only one rotation fires per user; concurrent callers all get the same result. Cache TTL is the rotation grace window (5s default).

## Prevention / when to apply

- **Apply when:** Operation has side effects and must run at most once per key, with concurrent callers awaiting the same result.
- **Don't apply when:** Side effects must fire per-call (e.g., logging, audit).
- **Watch out for:** Memory growth if the keyspace is unbounded; add a max-entries cap.

## Related

- [Single-flight cache for per-user side-effecting operations](../patterns/single-flight-cache-2026-03-20.md) — the underlying pattern.

## Citations

- Commit: a3f1b9c — `fix(auth): serialize refresh-token rotation per-user (U3)`
- Plan: `docs/plans/completed/FR07-auth-rotation.md`
```
