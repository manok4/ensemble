# Persona dispatch (en-review)

How `/en-review` decides which reviewer agents fire and how their findings are synthesized.

## Always-on (4)

Fire on every `en-review` invocation regardless of diff content:

| Agent | Focus |
|---|---|
| `correctness-reviewer` | Logic errors, edge cases, state bugs, error propagation, off-by-one |
| `testing-reviewer` | Coverage gaps, weak assertions, brittle tests, missing categories |
| `maintainability-reviewer` | Coupling, complexity, naming, dead code, abstraction debt |
| `standards-reviewer` | CLAUDE.md / AGENTS.md compliance, file naming, frontmatter, IDs, paths |

## Conditional (3) — fire when diff matches

Decide via diff content scan before dispatching:

| Agent | Fires when diff touches |
|---|---|
| `security-reviewer` | Auth code, public endpoints, user-input handling, secret/token handling, permissions, CORS, CSP, cookie config |
| `performance-reviewer` | DB queries (raw SQL, ORM call patterns), hot paths (request handlers, render loops), async/concurrency, caching, large data transforms |
| `migrations-reviewer` | Schema migration files, backfill scripts, data-isolation changes, multi-tenancy boundary changes |

## Detection heuristics

`security-reviewer`:
- File path matches `**/auth/**`, `**/permissions/**`, `**/oauth/**`, `**/session/**`
- Diff content matches: `cookie`, `token`, `password`, `secret`, `bcrypt`, `jwt`, `csrf`, `cors`, `Authorization:`, `req.user`, `req.headers`, `process.env.[A-Z_]+_SECRET`
- File path matches `**/api/**`, `**/routes/**`, `**/handlers/**` AND function signature suggests public endpoint
- Migration touches a `roles`, `permissions`, `users.password*`, `sessions`, `api_keys` table

`performance-reviewer`:
- File path matches `**/queries/**`, `**/db/**`, `**/repository/**`
- Diff content matches: ORM patterns (`.findMany`, `.findFirst`, `.where`, `JOIN`, `eager`, `include`, raw `SELECT`)
- Diff content suggests N+1 (loop with `await` calling a query)
- File path matches `**/handlers/**` for known hot-path routes
- Diff adds caching layer (Redis, in-memory, CDN config)

`migrations-reviewer`:
- File path matches `**/migrations/**`, `**/db/migrations/**`, `**/migration_*.sql`
- Diff adds/removes columns, tables, indexes, constraints
- File contains `ALTER TABLE`, `DROP COLUMN`, `ADD COLUMN`, `CREATE TABLE`, `CREATE INDEX`
- File path matches `**/seeds/**`, `**/backfills/**`

## Conservative dispatch

When in doubt, **fire** the conditional agent. Cost is low (mid-tier model, focused remit); missing a security finding is high.

The exception: don't fire a conditional agent on a doc-only diff. If `git diff --name-only` shows only `docs/` paths or `*.md` files, skip all three conditional reviewers.

## Parallel dispatch

All persona agents fire **in parallel** — single message, multiple `Agent` tool calls. Aggregation waits for all to return.

In Claude Code:

```
Agent({ subagent_type: "correctness-reviewer", ... })
Agent({ subagent_type: "testing-reviewer", ... })
Agent({ subagent_type: "maintainability-reviewer", ... })
Agent({ subagent_type: "standards-reviewer", ... })
Agent({ subagent_type: "security-reviewer", ... })  // if matched
// Plus learnings-research in the same parallel batch
Agent({ subagent_type: "learnings-research", ... })
```

In Codex: equivalent `spawn_agent` calls in a batch.

## Synthesis

After all personas return:

1. **Validate each response** — must parse as JSON, must follow `references/finding-schema.md`. Drop malformed responses with a stderr log; don't fail the whole review.
2. **Collect findings** — flatten into one list with the persona attribution preserved (`finding.persona = "correctness"`).
3. **Dedup** — findings with the same `location` AND title-similarity ≥ 0.7 are duplicates. Keep the highest-severity, highest-confidence variant; merge `personas` field.
4. **Boost confidence on overlap** — if two personas independently surfaced the same finding, boost confidence by +1 (capped at 10). Strong signal.
5. **Conflict detection** — same `location` flagged for incompatible reasons → leave both; mark `conflict: true` for user judgment.
6. **Severity reordering** — sort by severity (P0 → P3), then confidence (high → low), then persona priority (`correctness` > `security` > `testing` > `standards` > `maintainability` > `performance` > `migrations`).

## Output envelope

The synthesis layer emits a single envelope (per `references/finding-schema.md`) with the same shape plus a `personas` array listing which personas contributed:

```json
{
  "verdict": "approve | revise | reject",
  "summary": "<2-3 sentence overall>",
  "personas": ["correctness", "testing", "maintainability", "standards", "security"],
  "findings": [
    {
      "severity": "P1",
      "confidence": 9,
      "title": "...",
      "location": "src/auth/refresh.ts:42",
      "personas": ["correctness", "security"],
      "why_it_matters": "...",
      "suggested_fix": "...",
      "autofix_class": "manual"
    }
  ]
}
```

Aggregate `verdict` is the most-severe of the personas:
- Any persona returns `reject` → aggregate is `reject`.
- Any persona returns `revise` and none returns `reject` → aggregate is `revise`.
- All return `approve` → aggregate is `approve`.

## Optional Outside Voice on top

`/en-review --peer` adds a cross-agent peer pass on top of the personas. The peer reads:

- The diff.
- The persona findings (so it can confirm or counter them).
- The plan.

The peer pass produces an **additional** finding set merged into the envelope with `persona: "peer"`. Useful for genuinely ambiguous reviews; off by default to keep the standard `en-review` cost low.

## Cost characteristics

| Agent | Approximate token cost |
|---|---|
| `correctness-reviewer` | 3K–10K |
| `testing-reviewer` | 2K–8K |
| `maintainability-reviewer` | 3K–10K |
| `standards-reviewer` | 2K–6K |
| `security-reviewer` | 3K–10K (only when fires) |
| `performance-reviewer` | 3K–10K (only when fires) |
| `migrations-reviewer` | 3K–8K (only when fires) |
| `learnings-research` | 2K–8K |

Total for an average diff: ~15K–40K. Keep diffs reviewable per-unit (per-unit is preferred to per-PR-of-15-units) so each round stays small.

## Failure protocol

| Failure | Behavior |
|---|---|
| One persona times out | Drop its findings; note in summary; continue |
| One persona returns malformed JSON | Drop; retry once with "respond with valid JSON only"; if it fails again, drop |
| All personas fail | `verdict: error`; surface to user; do not commit |
| Diff is too large to fit in one persona's context | Split by file; run persona per file; merge findings (rare; bound by per-unit discipline) |
