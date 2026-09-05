# Observability conventions (telemetry harness)

Defines the minimum *shape* Ensemble expects of application logs and traces. **Generic — not tied to any specific library.** Projects pick their stack (OpenTelemetry, Pino, slog, Python `logging`, etc.) and configure Ensemble to read from that source.

Used by:

- The `/en-debug` skill (reads logs to reproduce bugs).
- `/en-resolve-pr` (when reviewer comments reference observability gaps).

## The shape contract

A log line is a single JSON object with:

| Field | Required? | Purpose |
|---|---|---|
| `ts` | yes | ISO-8601 timestamp with timezone |
| `level` | yes | `debug \| info \| warn \| error \| fatal` |
| `msg` | yes | Human-readable description (one short line) |
| `event` | yes | Dotted machine identifier — e.g. `auth.token_rotated`, `db.query_failed` |
| `trace_id` | recommended | Distributed-tracing correlation ID (64- or 128-bit hex) |
| `span_id` | recommended | Span-level correlation ID |
| `request_id` | when applicable | Per-request correlation ID at the API boundary |
| `user_id` | when applicable | Stable user identifier (never email/PII directly) |
| `error.type` | when `level=error\|fatal` | Error class/type name |
| `error.message` | when `level=error\|fatal` | Error message |
| `error.stack` | when `level=error\|fatal` | Stack trace, multi-line single-string |

Custom fields are allowed and encouraged — namespace them under a domain prefix (`db.duration_ms`, `cache.hit`, `payments.amount_cents`) so they don't collide.

## What this contract enables

- **Bug reproduction.** `/en-debug` can take a `trace_id` and walk the spans to identify the failing code path.
- **Enforcement.** A project's own linter flags `console.log()`, `print()`, and bare formatted strings outside explicit dev paths; Ensemble ships no rule for this.
- **Cross-cutting observability.** Aggregators (Datadog, Honeycomb, Loki) parse the same JSON regardless of language.
- **AI-assisted debugging.** Agents reading logs don't need to learn project-specific text patterns — the shape is uniform.

## What this contract does NOT mandate

- Specific library (Pino, slog, Python `logging`, OpenTelemetry SDK, etc.).
- Output destination (file, stdout, syslog, OTLP collector).
- Sampling strategy.
- Retention.

These are project decisions. Ensemble doesn't care *how* the logs are emitted, only *what shape* they have on the way out.

## Enforcing the shape

Ensemble ships no lint rule for unstructured logging; `bin/ensemble-lint` checks documents, not source. A project that wants the contract enforced adds a rule to its own linter (a `no-console` rule in ESLint, a `print` ban in Ruff) with its dev, script and test paths excluded. `/en-debug` degrades gracefully either way: unstructured logs cap the hypothesis at 6/10 and the run says so.

## Configuring the `/en-debug` log source

`/en-debug` needs to know where to read logs from. Three modes:

```yaml
observability:
  # Mode 1: read from a file (rolling app log)
  log_source: file
  log_path: ./logs/app.jsonl

  # Mode 2: read from a shell command (e.g., docker logs)
  log_source: command
  log_command: 'docker logs --tail 1000 app-service'

  # Mode 3: read from stdin (default; user pipes in)
  log_source: stdin
```

For production logs, point at your aggregator's CLI:

```yaml
log_source: command
log_command: 'datadog-cli logs --query "service:auth" --last 1h'
```

`/en-debug` doesn't shell out blindly — it reads the configured command name from a small allowlist (`docker`, `kubectl`, `journalctl`, `datadog-cli`, `gh run view`, plus anything explicitly added via `observability.allowed_log_commands`). This prevents a malformed config from running arbitrary code.

## Trace/span correlation

When a log line carries `trace_id`, `/en-debug` can:

1. Pull all log lines with the same `trace_id` to reconstruct the request lifecycle.
2. Identify the span where `level=error` first appears (the source).
3. Walk parent spans to find the entry point.
4. Map span names to source code locations (heuristic: span name often matches a function name or module path).
5. Surface a hypothesis: *"Error in `auth.token_rotated` span, originating from `src/auth/refresh.ts:42`. Caused by missing null check on `user.email`."*

The same flow works on plain logs without trace IDs — less precise, but `/en-debug` falls back to `request_id` correlation, then timestamp clustering, then full-text search.

## Required emit points

A handful of code locations *must* emit a structured log line. The lint rule `logging.required-emit` (advisory, P2) checks these:

- API request entry/exit (boundaries of HTTP/gRPC handlers).
- Error catch blocks (every `catch` / `except` / `Result<_, E>` discard must log unless explicitly marked `// noemit: <reason>`).
- Background-job lifecycle (start, success, failure).
- Database-migration apply/rollback.
- Scheduled-task fire/finish.

These are the points where missing observability hurts most. Other emits are at the project's discretion.

## Anti-patterns

- **Logging the same object across multiple lines instead of one structured line.** Prefer one log per event.
- **Including PII in `msg` or top-level fields.** Use `user_id` (a stable hash or numeric ID), not email/name.
- **Logging at the wrong level.** Errors that are recovered cleanly are `warn`, not `error`. Reserve `error` for unrecovered failures.
- **Stringifying and re-parsing JSON.** Emit once, structured. Don't `JSON.stringify` then log as `msg`.
- **Adding `console.log` and forgetting it.** A rule in the project's own linter catches it; make it blocking once the codebase is clean.

## Where this fits in the harness

| Feedforward (guides) | Feedback (sensors) |
|---|---|
| This document | the project's own logging lint |
| `.ensemble/config.local.yaml` schema | `logging.required-emit` lint rule (P2 advisory) |
| Project's logger setup (logger.ts, etc.) | `/en-debug` reads logs to reproduce bugs |
| | `/en-review` checks observability adherence on changed files |

Per Martin Fowler's harness-engineering framing: structured logging is a *guide* (the convention) plus a *sensor* (the lint that enforces it) plus a *behavior verification surface* (`/en-debug` uses it to reproduce). All three layers reinforce each other.
