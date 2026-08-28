# Peer review brief — reviewing a build

What the peer is asked when `/en-build` sends it the branch it just built, and
what this skill does with the answer. The wire format is
`references/peer-contract.md`; everything here is en-build's own.

**Not the same job as `/en-review`, despite the same dimensions.** en-review is
asked to review a diff. en-build is asked to review *its own work*, which changes
two things: the implementer-is-not-the-reviewer property is the whole point, and
the authority to act is narrower because a build runs unattended.

## What the peer is asked

Review the diff along these dimensions. The first four always apply. The last
three apply only when the diff matches their trigger; say so explicitly when you
skip one, so a silent omission is never mistaken for a clean pass.

### correctness

| Category | Examples |
|---|---|
| **Logic errors** | Wrong condition, swapped operands, inverted boolean, missing case |
| **Edge cases** | Empty input, single-element input, boundary values, max/min, overflow |
| **State bugs** | Stale reads, missing initialization, ordering-dependent code, race conditions |
| **Error propagation** | Swallowed exceptions, ignored return values, missing cleanup, partial failure modes |
| **Off-by-one** | Loop bounds, slice indices, range inclusivity |
| **Broken invariants** | Class invariants, function pre/post-conditions, type contracts |
| **Concurrency** | Shared mutable state without synchronization, async ordering, deadlocks |
| **Security-relevant correctness** | Authentication paths returning wrong principal, authorization checks short-circuiting incorrectly |

### testing

| Category | Examples |
|---|---|
| **Coverage gaps** | New behavior without a corresponding test; new branches without test arms |
| **Weak assertions** | `expect(x).toBeTruthy()` when `expect(x).toEqual(specific)` is meaningful; tests that pass without exercising the change |
| **Brittle tests** | Snapshot of an entire object when only one field matters; tests coupled to internal implementation |
| **Missing categories** | Happy path covered, error path missed; happy path covered, edge cases missed |
| **Regression test missing** | Bug fix without a test that fails on the old code |
| **Test scoping** | Unit test calling out to a real network or DB; integration test with too-narrow scope |
| **Test isolation** | Shared mutable state across tests; ordering-dependent suite |
| **Mock realism** | Mocks that don't match the real interface; mocks that pass the test but mask production failure |

### maintainability

| Category | Examples |
|---|---|
| **Excessive coupling** | Module reaches into another module's internals; concrete dependency where abstraction would isolate |
| **Hidden complexity** | Function that does five things; class that knows about everything |
| **Naming** | Names that mislead (`getUser` that returns null on miss with no signal); ambiguous abbreviations; inconsistent naming within the file |
| **Dead code** | Unreachable branches, unused exports, commented-out code blocks left behind |
| **Premature abstraction** | Generic helper introduced for one caller; configuration for behavior that has one observed value |
| **Missed abstraction** | Three near-identical blocks copy-pasted; magic numbers with no name |
| **Layer violations** | UI code reading directly from DB; service layer importing route helpers |
| **Long functions / long files** | Functions > 50 lines or with > 4 levels of indentation; files > 500 lines |
| **Comment debt** | Comments that describe WHAT the code does (delete); stale comments that contradict the code (fix or delete) |

### standards

| Category | Examples |
|---|---|
| **`AGENTS.md` / `CLAUDE.md` conventions** | Build/test/lint command alignment; coding conventions stated in the maps |
| **File naming** | New file follows the project's casing convention (kebab-case, snake_case, camelCase, etc.); placement matches existing structure |
| **Commit messages** | Conventional commits (`<type>(<scope>): <subject>`); subject ≤ 50 chars; imperative mood |
| **Frontmatter validity** | Markdown artifacts in `docs/` have valid frontmatter per the project's documented frontmatter schema and per Appendix C of foundation |
| **Stable IDs** | R-IDs / U-IDs / FRXX / TD-IDs cited correctly; never renumbered |
| **Path conventions** | Repo-relative paths in artifacts (no `/Users/...`, no `C:\...`) |
| **Status correctness** | `docs/plans/active/*.md` has `status: draft \| open \| in_progress \| abandoned`; `docs/plans/completed/*.md` has `status: completed`. `plan_type` is one of `feature`, `improvement`, `bug`. |
| **Test placement** | Tests live where the project's existing tests live (`tests/`, `__tests__/`, alongside source) — match the existing convention |

### security — fires when: The dispatching skill (`en-review` per `references/persona-dispatch.md`) detects security-relevant changes and dispatches you. Detection heuristics: - Path: `**/auth/**`, `**/permissions/**`, `**/oaut

| Category | Examples |
|---|---|
| **Authentication** | Token issuance, validation, expiry; session handling; cookie attributes (`HttpOnly`, `Secure`, `SameSite`); OAuth flow correctness; multi-factor handling |
| **Authorization** | Permission checks short-circuiting; admin-only paths exposed; role escalation paths; tenant isolation breaches |
| **Input validation** | SQL injection (raw SQL, ORM `.raw()`), XSS (unescaped HTML), SSRF (user-controlled URLs in fetch), path traversal, command injection |
| **Secret handling** | Hardcoded keys; secrets in logs; secrets passed through to client; insecure storage; missing rotation hooks |
| **Network policy** | CORS misconfiguration; CSP gaps; allowing `*` where origin should be specific |
| **Crypto** | Weak algorithms (MD5, SHA1 for security purposes); custom crypto; insecure random; constant-time comparison missing where needed |
| **Trust boundaries** | Client-side validation only (no server check); trust of `req.headers` without verification; trust of `req.user` after only one auth step |
| **Rate limiting** | Public endpoints without rate limit; missing exponential backoff on retries that hit external APIs |

### performance — fires when: Per `references/persona-dispatch.md`. Detection heuristics: - Path: `**/queries/**`, `**/db/**`, `**/repository/**` - Diff content: ORM patterns (`.findMany`, `.findFirst`, `.where`, `JOIN`, `eager`, 

| Category | Examples |
|---|---|
| **N+1 queries** | Loop with `await db.X` per iteration; ORM relation accessed in a loop |
| **Unbounded queries** | `findMany()` without `limit`; pagination missing |
| **Missing indexes** | Query on a column the migration didn't index |
| **Hot-path overhead** | Synchronous JSON parse on a 10MB blob in a request handler |
| **Cache misses** | Cacheable data fetched per-request; cache TTL too short or too long |
| **Async pitfalls** | Sequential awaits where Promise.all would parallelize; uncoordinated parallelism (1000 concurrent calls to a rate-limited API) |
| **Memory** | Loading entire dataset into memory when a stream/iterator would suffice; closure retaining large objects |
| **Render performance** | (Frontend) re-render storms; missing memoization where the component re-renders on every parent update; large lists without virtualization |
| **Cold-path doing hot-path work** | Initialization that happens lazily but should be eager (pre-warm); or vice versa |

### migrations — fires when: Per `references/persona-dispatch.md`. Detection heuristics: - Path: `**/migrations/**`, `**/db/migrations/**`, `**/migration_*.sql` - Diff adds/removes columns, tables, indexes, constraints - File con

| Category | Examples |
|---|---|
| **Locking and downtime** | `ALTER TABLE ADD COLUMN` with default value on a large table (long lock); `CREATE INDEX` without `CONCURRENTLY` |
| **Backwards compatibility** | Drop column while old code still reads it; rename without view bridge |
| **Backfill safety** | Backfill in a single transaction on millions of rows; backfill without batching; missing idempotency on retry |
| **Constraint additions** | `NOT NULL` on existing nullable column without backfill; foreign key to a table with existing rows that violate |
| **Data loss** | `DROP TABLE`, `DROP COLUMN`, `TRUNCATE` — reversible only via backup |
| **Forward / reverse migrations** | Migration is irreversible (no `down()` method); reverse migration loses data |
| **Multi-tenancy** | Schema change that breaks tenant isolation; index missing tenant column in WHERE clause |
| **Index hygiene** | New WHERE clause on a column without an index; redundant index that increases write cost |
| **Migration ordering** | Migration depends on a column added in a later migration; chronologically out-of-order numbering |
| **Data integrity** | New constraint that existing data would violate (need backfill first) |


## Where a finding points

`<file>:<line>` for code, or the U-ID when the finding is about a specific unit —
the host dispatches per-unit off that field, so set it whenever the finding
belongs to one.

## What en-build does with the findings

Contract first: severity, confidence, autofix classes and resolution statuses
come from `references/peer-contract.md`. What follows is policy, and it is
deliberately more conservative than en-review's because nobody is watching.

| Severity | Action in an unattended build |
|---|---|
| P0 | **Stop the build.** Do not apply, do not commit past it. Surface and wait. |
| P1 `safe_auto` | Apply, re-verify with tests and lint, record in the commit body. |
| P1 anything else | Record as a residual and surface in the build summary. Do not apply unattended. |
| P2 `safe_auto` | Apply, re-verify. |
| P2 anything else | File to the tech-debt tracker with the unit's U-ID. |
| P3 | File to the tech-debt tracker. No action. |

**The narrower authority is the point.** en-review runs with a human present and
can ask; en-build cannot, so anything needing judgement becomes a residual rather
than an autonomous edit. A build that quietly applied a `manual` finding would be
making a decision the user never saw.

`conflicting` findings are never applied, in any mode.

**Re-verify after applying.** Tests and lint re-run before the commit. On
failure, `git restore` and surface. The build never commits broken code chasing a
finding.

## The implementer-is-not-the-reviewer property

The host implemented every ordinary unit, so the branch-level pass must go to a
different architecture: Claude host to a Codex peer, Codex host to a Claude peer.
Host personas run alongside it as fresh-context sub-agents that never saw the
implementing reasoning, so they do not weaken the property.

Record which held in the `review-verdict:` trailer's `reviewer` field —
`cross-agent`, `single-agent-fallback` or a host fallback. That value is what the
end-of-build evidence audit gates on, so it records whether the property held,
not how many personas contributed.

## Effort

Destructive or `gated: true` units get `high` regardless of diff size: those are
the units where a missed finding is expensive and the per-unit peer pass is the
only review they get.
