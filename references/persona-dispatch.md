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

## Parallel dispatch (personas AND the peer, one batch)

All persona agents fire **in parallel** — single message, multiple `Agent` tool calls — **and the cross-agent peer subprocess launches in the same batch**. Aggregation waits for all to return.

In Claude Code:

```
Agent({ subagent_type: "correctness-reviewer", ... })
Agent({ subagent_type: "testing-reviewer", ... })
Agent({ subagent_type: "maintainability-reviewer", ... })
Agent({ subagent_type: "standards-reviewer", ... })
Agent({ subagent_type: "security-reviewer", ... })  // if matched
// Plus learnings-research in the same parallel batch
Agent({ subagent_type: "learnings-research", ... })
// Plus the cross-agent peer, concurrently — NOT serialized after the roster:
bin/ensemble-peer-invoke --peer-cmd "$PEER_CMD" ...
```

In Codex: equivalent `spawn_agent` calls in a batch.

**Why the peer belongs in this batch.** It is **blind** to the persona findings (see the Outside Voice section), so it consumes nothing the roster produces and there is no ordering dependency. Serializing it would add its full latency to every review for no benefit — `peer_timeout_seconds` defaults to 600, so a serial peer is the difference between a review bounded by the slowest persona and one bounded by persona + peer.

The concurrency is therefore **licensed by the blind-peer invariant**, not by convenience. Any change that feeds persona findings to the peer must re-serialize this batch.

**Peer failure inside the batch** does not discard persona results. The peer's own degradation path (one bounded retry, then persona-only fallback) is handled by `bin/ensemble-peer-invoke` and recorded in `peer_decision.reason`; already-returned persona findings are still synthesized and reported. A review whose peer failed is a review with `peer: "off"` and a recorded reason, never a failed review.

## Synthesis

After all personas return:

1. **Validate each response** — must parse as JSON, must follow `references/finding-schema.md`. Drop malformed responses with a stderr log; don't fail the whole review.
2. **Collect findings** — flatten into one list with the persona attribution preserved (`finding.persona = "correctness"`) and the originating side tagged (`finding.source = "host"`).
3. **Dedup within the host set** — findings with the same `location` AND title-similarity ≥ 0.7 are duplicates. Keep the highest-severity, highest-confidence variant; merge `personas` field.
4. **Boost confidence on same-source overlap** — if two personas independently surfaced the same finding, boost confidence by +1 (capped at 10). Note this is *same-stack* agreement; cross-source agreement is weighted higher (see Two-source reconciliation).
5. **Severity reordering** — sort by severity (P0 → P3), then confidence (high → low), then persona priority (`correctness` > `security` > `testing` > `standards` > `maintainability` > `performance` > `migrations`).

## Two-source reconciliation (EN11)

When the peer runs (the default — see `skills/en-review/SKILL.md` step 2a), the host set and the peer set are reconciled into **reconciliation records** rather than flattened into one pool. A single `source` field cannot express a corroborated pair, so the record carries provenance for both sides:

```json
{"bucket": "corroborated | peer-only | host-only | conflicting",
 "sources": ["host", "peer"],
 "canonical": { "<the finding presented to the user>" },
 "contributing": [{"source": "host", "finding_id": "..."},
                  {"source": "peer", "finding_id": "..."}],
 "confidence": 9,
 "conflict": false}
```

### One global algorithm (so the buckets partition)

Conflict and corroboration are two stages of a **single pass over one shared consumption pool**, in a fixed order:

1. **Conflict stage first.** Within each `location`, enumerate cross-source pairs whose claims are **contradictory**, ordered by ascending `(host finding_id, peer finding_id)`. Greedily allocate each pair to a `conflicting` record, **consuming both members**. Conflict runs first because a contradiction is the more consequential classification and must not be masked by a similarity match.
2. **Corroboration stage on the remainder.** Among findings not consumed in stage 1, order cross-source candidate pairs within a `location` by descending title-similarity (`>= 0.7` — the same predicate as host-set dedup, not a second matcher), greedily match **one-to-one**, and consume both members.
3. **Singles.** Every finding still unconsumed becomes a `host-only` or `peer-only` record.

Ties break on ascending `finding_id` at every stage, so identical input yields identical buckets across runs. `canonical` selection is highest-severity, then highest-confidence, then the host-source member.

**Partition invariant (assert it, don't assume it):** every raw finding contributes to **exactly one** reconciliation record. A finding is never both corroborated and conflicting, and none is dropped. The total count of `contributing[]` entries across all records MUST equal the count of raw findings.

**Worked example.** At `src/auth.ts:42` the host surfaced `H1` ("token compared with ==") and `H2` ("missing null guard"); the peer surfaced `P1` ("timing-unsafe token comparison") and `P2` ("null guard here is unreachable, remove it"). `H2`/`P2` contradict each other (add vs remove) and are allocated first as `conflicting`, consuming both. `H1`/`P1` then match on similarity and become `corroborated`. Nothing is left over. Had `P2` been absent, `H2` would have fallen through to `host-only`.

### Bucket semantics

| Bucket | Meaning | Handling |
|---|---|---|
| `corroborated` | Host AND peer independently found it | Rank first; confidence **+2** (capped at 10) |
| `peer-only` | Only the cross-agent peer found it | Surface prominently — empirically where the value has been (EN09's 6 parser bypasses, EN10's 4 findings were all peer-only) |
| `host-only` | Only the host personas found it | Normal ranking; skews to standards/testing/maintainability where project context beats fresh eyes |
| `conflicting` | Same `location`, incompatible claims | Surface **both**, `conflict: true`, **never auto-applied** |

**Why cross-source agreement outranks same-source.** Two host personas agreeing are the same model with correlated blind spots; host and peer agreeing are independent architectures. Hence `+2` across sources versus `+1` within. This repo already encodes the principle that not all agreement is equal: `fast-pass` findings are barred from corroboration promotion entirely, and that carve-out is preserved.

**Conflict detection is independent of the similarity predicate.** Two findings at one `location` whose claims are incompatible are frequently *dissimilar* in title (as in the worked example above), so keying conflict off the `>= 0.7` corroboration predicate would systematically miss them. Conflict is evaluated on contradictory assertions at a shared `location` regardless of similarity.

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

## Outside Voice: on by default, and BLIND (EN11)

The cross-agent peer runs **by default** (see `skills/en-review/SKILL.md` step 2a for the mode and availability scoping). It produces a second finding set, tagged `source: "peer"`, which reconciles with the host set per Two-source reconciliation above.

**Blind-peer invariant.** The peer reads:

- The diff.
- The project context and goal.
- The plan.

It does **NOT** read the host persona findings. This is a deliberate, load-bearing invariant, not an omission:

- **Independence is what makes overlap mean anything.** Anchoring the peer on host findings turns independent discovery into confirmation, and the `corroborated` bucket would then measure suggestibility rather than agreement.
- **It licenses concurrent dispatch.** Because the peer needs nothing from the persona batch, `/en-review` fires it in the *same* parallel batch (step 8) instead of serializing after it.

An earlier version of this file described the peer as receiving the host roster's output for confirmation. That behavior was never implemented: `bin/ensemble-build-peer-prompt` has no flag for it and `/en-review` never passed them. The **implementation was right and the prose was wrong**, so the prose was corrected rather than the feature built.

Any future change that feeds persona findings to the peer must also re-serialize step 8 and re-derive the corroboration weighting, because both depend on this invariant.

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

## Lite roster (`--lite`)

When `/en-review --lite` runs and the diff classifies `is_small_and_safe` per `references/diff-signal-detection.md`, dispatch a reduced roster instead of the full panel:

- **Roster:** `correctness-reviewer` + `standards-reviewer` + a `fast-pass` lens. Skip `testing`, `maintainability`, `learnings`, and every conditional persona.
- **Fail closed:** if `is_small_and_safe` is `false` — unknown line count, any uncounted non-code file, any risk signal, or any conditional persona independently triggered — run the **full roster**. `--lite` is advisory; the gate decides.
- **`fast-pass` confidence anchor:** cap every `fast-pass` finding at anchor 50. At 50 it surfaces on its own only when P0; otherwise it reaches the actionable tier only by deduping onto an independent persona finding. `fast-pass` findings never count toward cross-reviewer corroboration promotion.
- **Outcome line (EN08):** the gate's decision is reported by the mandatory `lite_gate:` line in en-review's summary (`applied` / `overridden (<reasons>)` / `not-requested`) — never a silent override.

## Mutation boundary (EN08)

Whatever the mode, **en-review must not implement findings outside the mode-permitted, announced, and recorded `applied_fixes[]` set** — wholesale implementation of findings is a contract violation. The permitted set is frozen BEFORE any edit (two-phase protocol, see en-review step 12); `applied_fixes[]` derives from the actual before-vs-after tree delta; a P0 finding halts all automatic mutation until severity.md's P0 pause-and-ask occurs. Review reports and applies bounded fixes; implementing belongs to `/en-build` / `/en-resolve-pr`.

## Failure protocol

| Failure | Behavior |
|---|---|
| One persona times out | Drop its findings; note in summary; continue |
| One persona returns malformed JSON | Drop; retry once with "respond with valid JSON only"; if it fails again, drop |
| All personas fail | `verdict: error`; surface to user; do not commit |
| Diff is too large to fit in one persona's context | Split by file; run persona per file; merge findings (rare; bound by per-unit discipline) |
