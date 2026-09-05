# `/en-debug` — hypothesis output format

How `/en-debug`'s surface-a-hypothesis step renders its conclusion to the user. Format is deterministic so users can scan quickly and so other skills can parse.

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

## Worked example

The `Output format` block in SKILL.md is the worked example; it is not repeated here. The confidence scale is SKILL.md's `Confidence scoring` section.

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
