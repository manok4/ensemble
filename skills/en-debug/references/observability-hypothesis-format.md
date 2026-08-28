# `/en-debug` — hypothesis output format

How `/en-debug` step 10 renders its conclusion to the user. Format is deterministic so users can scan quickly and so other skills can parse.

## Structure

```
Hypothesis (confidence: <N>/10)

  <one-paragraph hypothesis — what happened, why, where>

Anchor log line:
  <key fields from the log entry that grounds the conclusion,
   one per line, redacted per references/secret-patterns.md>

Span timeline (<count> entries):
  <ts>  <event/span name>     <one-line summary>     <level>   <file:line if mapped>
  <ts>  <event/span name>     <one-line summary>     <level>
  <ts>  <event/span name>     <one-line summary>     <level>   <file:line>  ← source

Suggested next step:
  <one of: /en-build, /en-resolve-pr, /en-plan, /en-learn capture>
  <one-line rationale tied to the hypothesis>
```

## Worked example — high-confidence

```
Hypothesis (confidence: 9/10)

  The error originates in src/auth/refresh.ts:42, where rotateRefreshToken
  fails to handle a null `user.email` returned by getUserById. The trace
  shows two earlier successful rotations on the same user_id; the third
  fired with a stale cache entry where the user's email had been removed.

Anchor log line:
  ts: 2026-05-04T10:13:42Z
  level: error
  event: auth.token_rotated
  error.type: TypeError
  error.message: "Cannot read property 'toLowerCase' of null"
  error.stack: "at Object.normalize (src/auth/refresh.ts:42:18)
                at rotateRefreshToken (src/auth/refresh.ts:88:14)"
  trace_id: 4bf92f3577b34da6a3ce929d0e0e4736
  user_id: u_482

Span timeline (3 entries):
  10:13:41.881  service.boundary    POST /api/auth/refresh         info    src/handlers/auth.ts:14
  10:13:42.012  cache.user_lookup   hit, stale=true                debug   src/cache/users.ts:88
  10:13:42.013  auth.token_rotated  TypeError: ...                 error   src/auth/refresh.ts:42  ← source

Suggested next step:
  /en-build — write a fix for src/auth/refresh.ts:42 that handles
  null user.email + invalidates cache on stale read. Use this trace
  as a test fixture (tests/fixtures/refresh-null-email-trace.json).
```

## Worked example — medium-confidence (no stack)

```
Hypothesis (confidence: 6/10)

  Likely source: src/payments/charge.ts. The event `payments.charge_failed`
  matches a function in this file; the message references a Stripe API
  error code that's referenced only in src/payments/charge.ts:117. No
  stack trace was captured, so the line number is approximate.

Anchor log line:
  ts: 2026-05-04T11:42:08Z
  level: error
  event: payments.charge_failed
  error.message: "Stripe error: card_declined"
  request_id: req_abc123

Span timeline (1 entry — no trace_id, single log line):
  11:42:08.091  payments.charge_failed  Stripe: card_declined   error   src/payments/charge.ts:117  ← suspected source

Suggested next step:
  /en-build — add error-handling branch in src/payments/charge.ts:117
  for the `card_declined` Stripe error code. Verify by replaying
  this request_id. If the line number is wrong, re-run /en-debug
  with the user_id to widen the trace.
```

## Worked example — low-confidence (no structured logs)

```
Hypothesis (confidence: 4/10)

  Could not correlate cleanly. Logs at this timestamp aren't structured per
  references/observability-conventions.md, so no trace_id is available.
  Full-text search on the error message matches three locations:
    - src/auth/refresh.ts:42  (most likely)
    - tests/auth/refresh.test.ts:80  (skipped — test fixture)
    - docs/learnings/auth-null-email-2025-11-08.md:12  (skipped — learning)

Anchor log line:
  ts: 2026-05-04T10:13:42Z
  msg: "TypeError: Cannot read property 'toLowerCase' of null"
  (raw — no trace_id, no event field, no error.stack)

Span timeline:
  (cannot construct — no trace_id)

Suggested next step:
  Confirm src/auth/refresh.ts:42 is the right location.
  Then consider adopting structured logging per
  references/observability-conventions.md so future debug runs
  can correlate via trace_id.
```

## Confidence scale (mirrors SKILL.md)

| Confidence | Meaning |
|---|---|
| 9–10 | Direct match: `error.stack` pinpoints file:line, structured logs corroborate |
| 7–8 | Strong correlation via trace + event-field, no stack but plausible from code-search |
| 5–6 | Reasonable hypothesis from log-text matching; not anchored in code yet |
| 3–4 | Wide net; multiple plausible sources; user should narrow further |
| 1–2 | Couldn't correlate; logs may be insufficient or unstructured |

Below 5, the suggested next step always includes *"narrow your query"* — re-run with a more specific argument (trace ID > error message > timestamp window).

## Redaction rules

The `Anchor log line` section quotes log fields **verbatim**, but with two safety overlays:

1. **Secret patterns** — anything matching `references/secret-patterns.md` (AWS keys, GH PATs, Anthropic/OpenAI keys, JWT-shaped strings, base64-encoded secret-shaped blobs) is replaced with `[REDACTED]`.
2. **PII heuristic** — fields named `email`, `phone`, `ssn`, `credit_card`, etc., or values matching common PII patterns, are replaced with `[REDACTED-PII]`.

These never get suppressed silently — the redacted output keeps the field name and just masks the value, so the user sees that something was redacted.

## Span-timeline rendering rules

- **Sort ascending by `ts`**. The error-level entry that initially matched the query gets a `← source` marker.
- **Truncate `msg` to ~40 chars** in the timeline; full message is in the Anchor section above.
- **Show `<file:line>` only when mapping confidence ≥ 6**. Below that, show blank — better to surface uncertainty than mislead.
- **Cap at 8 entries**. If trace has more, show first 3 + last 4 with `... <N> intermediate spans omitted ...` between.

## Markdown vs plain-text

`/en-debug` emits **plain text by default**. Use `--markdown` to wrap fields in backticks and bold the source-line. Plain text is the default because most consumers (terminal, CI logs, log-aggregator tail) don't render markdown.

## Suggested-next-step routing

| Hypothesis flavor | Suggested next step |
|---|---|
| Confidence ≥ 7, fix is mechanical (null check, error wrap) | `/en-build` with the trace as a test fixture |
| Confidence ≥ 7, fix surfaced from a reviewer comment context | `/en-resolve-pr` (back to the PR thread) |
| Confidence 5–6, fix is structural (cross-cutting) | `/en-plan` to design the change |
| Pattern repeats across multiple traces | `/en-learn capture --from-conversation` to file the anti-pattern |
| Confidence < 5 | "Narrow your query" — re-run with trace_id, or adopt structured logging |

## What this format never includes

- **Raw stack traces with full file paths from outside the project** (e.g., `node_modules/express/lib/router/route.js:131`). Only project-source frames appear in the timeline.
- **Speculative "could it be X?" alternatives without a confidence rating**. Every candidate has a number.
- **More than one error.stack quoted in full**. The anchor is the canonical one; subsequent traces in the timeline get a one-line summary only.
- **Internal API calls visible to the agent's tool use** — the user sees the rendered hypothesis, not the steps the agent took to produce it.
