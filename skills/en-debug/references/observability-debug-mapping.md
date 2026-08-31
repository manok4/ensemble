# Observability — debug mapping (span / event → source)

How `/en-debug`'s map-span-to-source step maps a log line to a specific source-code location. Heuristics in priority order.

## The signals

A structured log line per `references/observability-conventions.md` carries fields like:

```json
{
  "ts": "2026-05-04T10:13:42Z",
  "level": "error",
  "msg": "Cannot read property 'toLowerCase' of null",
  "event": "auth.token_rotated",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "00f067aa0ba902b7",
  "user_id": "u_482",
  "error.type": "TypeError",
  "error.message": "Cannot read property 'toLowerCase' of null",
  "error.stack": "TypeError: Cannot read property 'toLowerCase' of null\n    at Object.normalize (src/auth/refresh.ts:42:18)\n    at rotateRefreshToken (src/auth/refresh.ts:88:14)\n    ..."
}
```

Each field provides a different mapping route, with different reliability.

## Priority 1 — `error.stack` (most reliable)

A stack trace gives an exact `file:line`. Parse the topmost frame in the project's source tree (skip `node_modules/`, `vendor/`, `lib/python*/`, etc.) — that's where the error originated.

Implementation:
1. Split `error.stack` on newlines.
2. For each frame, extract `<file>:<line>` using language-appropriate regexes:
   - Node/JS/TS: `at .* \((.+?):(\d+):(\d+)\)` — group 1 is path, group 2 is line.
   - Python: `File "(.+?)", line (\d+)` — group 1 is path, group 2 is line.
   - Go: `\t(.+?\.go):(\d+)` — group 1 is path, group 2 is line.
   - Rust: ` at (.+?\.rs):(\d+)` — group 1 is path, group 2 is line.
3. The first frame whose path is inside the project's source tree is the answer.

**Confidence:** 9/10 when present.

## Priority 2 — Structured `event` field → source heuristic

The `event` field (per conventions) is dotted: `<area>.<verb>` or `<area>.<noun>_<verb>`. Map to source via:

| Event shape | Likely source location |
|---|---|
| `auth.token_rotated` | Function `tokenRotated` / `rotateToken` in `src/auth/` (or `auth/`, `services/auth/`) |
| `db.query_failed` | Wherever the query is issued; check `src/repo/` or `src/db/` |
| `payments.charge_succeeded` | `src/payments/` or `services/payments/` |
| `<area>.<verb>` (general) | Function whose name matches `<verb>` in `src/<area>/` |

Heuristic algorithm:

1. Split `event` on `.` → `[area, ...]`.
2. Search for source files whose path contains `/<area>/` or matches `<area>.<ext>`.
3. Within those files, search for function names matching the remaining segments (`tokenRotated`, `token_rotated`, `TokenRotated`, etc. — language-appropriate casing).
4. If multiple matches, prefer the one closest to the file containing `error.stack`'s top frame (if available).
5. Fallback: dispatch the `repo-research` agent with the event name + project root and ask it to identify the most likely emitter.

**Confidence:** 6–7/10 — depends on consistent naming. Lowers if the event field is generic (`request.processed` → too broad).

## Priority 3 — Span-name correlation

If `span_id` is present and the project uses OpenTelemetry-style spans, span names often match function or module names directly:

| Span name | Likely source |
|---|---|
| `POST /api/auth/refresh` | HTTP handler — search for the route registration: grep for `"/api/auth/refresh"` |
| `db.users.findById` | Database operation — `src/repo/users.*` `findById` method |
| `auth.refresh_token` | Function or method named `refreshToken` / `refresh_token` |

Same algorithm as Priority 2, applied to span name instead of event field.

**Confidence:** 6/10.

## Priority 4 — Full-text msg search

Last resort. Take the `msg` field (or `error.message`) and grep the source tree for a matching string literal. Often error messages are constructed via formatting (`f"Cannot find user {id}"`) so we look for the static prefix:

1. Extract the longest static substring from `msg` (drop placeholders like `{name}`, `${id}`, `%s`).
2. Grep source for that substring in string literals.
3. Each match is a candidate emitter.

**Confidence:** 4–5/10 — message text changes often, false positives from documentation/tests.

## Priority 5 — Repo-research dispatch

When all four priorities miss or produce ambiguous results, dispatch the `repo-research` agent with:

```
A runtime error fired with these signals:
  event: <event>
  msg: <msg>
  error.type: <type>
  trace_id: <trace_id>
  (full structured log line attached)

Identify the most likely source location. Look for:
  - Functions whose names match the event field
  - Error-emit sites that match the message format
  - Recent commits touching paths under <event-area>
Return a single best-guess <file>:<line> with confidence 1-10.
```

Agent returns a candidate; `/en-debug` cites it with the agent's confidence.

## Cross-checking against the trace

When `trace_id` is present and produces multiple log lines:

1. Sort the matched lines by `ts`.
2. Walk parent spans by examining `span_id` chains (if present).
3. The **first** error-level entry with this trace_id is the source. Walk back via parent spans to find the entry point (typically a request handler).
4. Each step's source location is mapped via priorities 1–5.

This produces a span timeline like:

```
10:13:41.881  service.boundary  POST /api/auth/refresh         info   src/handlers/auth.ts:14
10:13:42.012  cache.user_lookup hit, stale=true                debug  src/cache/users.ts:88
10:13:42.013  auth.token_rotated TypeError: ...                error  src/auth/refresh.ts:42  ← source
```

The `→ source` arrow points at the first `error`-level entry; preceding entries are causal context.

## When the codebase has no obvious source for a signal

`/en-debug` reports the hypothesis at confidence 4–5/10 and suggests:

- *"No clear source-code mapping for `event: <name>`. Consider adding a structured emit at the suspected site (per `references/observability-conventions.md`) so future debug runs can correlate. Re-run after the next deploy."*

This is the "your observability is the harness" feedback loop — the skill surfaces where the conventions aren't being followed.

## Edge cases

| Edge case | Handling |
|---|---|
| Multi-frame stack with several project files | Take the topmost project frame. Surface the next 2–3 as call-site context in the hypothesis. |
| Minified/transpiled source map mismatch | If `error.stack` points at a generated file (`dist/`, `.next/`, `build/`), check for a `*.map` sourcemap and resolve. If absent, emit a warning and degrade to Priority 2. |
| Async stack lost (Node, Python pre-3.11) | Walk to the last frame inside project code. If no project frame, fall through to Priority 2. |
| Logs aren't structured | Skip priorities 1–3 (no fields). Drop to Priority 4 (full-text). Cap confidence at 5/10. |
| Multiple plausible sources at equal confidence | Surface all as candidates; ask user to disambiguate. |
| `error.stack` truncated in the log | Use what's present. Surface "stack truncated" as a caveat in the hypothesis. |

## Reference files

- `references/observability-conventions.md` — the log shape this mapping assumes.
- `references/observability-hypothesis-format.md` — how the mapping result is rendered to the user.
