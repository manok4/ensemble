# Peer review brief — reviewing code

What the peer is asked when a code diff goes out for review, and what this skill
does with what comes back. The wire format both ends share is
`references/peer-contract.md`; everything here is this skill's own.

**This replaces nothing, because there was nothing.** The dimensions used to be
built by `ensemble-build-peer-prompt`, which set them only when
`ARTIFACT_TYPE = "plan"`. Code review hit the `else` and sent its peer an empty
dimensions block. The personas below existed as separate agent definitions that
were 81% shared boilerplate — output format, severity, confidence — all of which
`references/peer-contract.md` now owns once. What was actually unique to each was
its scope, and that is what follows.

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
| **Tests that read source instead of running it** | A test whose only evidence is that it opens, greps, parses or snapshots implementation source and finds particular strings, tokens, function names or regex matches. It proves nothing: matched text can be dead or commented out, and a behaviour-preserving refactor breaks it while the behaviour holds. Flag it and say what to execute instead — a public interface, asserting observable output, state, side effects or failure modes. **Two carve-outs:** a file that is itself generated output, a serialized protocol, persisted state or a deliberate snapshot is a real contract and may be read — name the contract. And a declarative artifact consumed by a machine (workflow YAML, JSON policy, generated config) may be parsed into a typed model and asserted on meaning; a raw substring match over it is still the anti-pattern. |
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

**Floor when the repo documents nothing.** The categories above are this skill's own list. Where a project has no written conventions, fall back to these named smells so the finding is reproducible rather than taste: *mysterious name* (rename it; if no honest name comes, the design is murky), *duplicated code* (extract the shape, call it from both), *feature envy* (move the method onto the data it envies), *data clumps* (the fields that travel together want a type), *primitive obsession* (a string standing in for a domain concept), *repeated switches* (the same cascade on the same type, twice), *shotgun surgery* (one logical change, scattered edits), *divergent change* (one file edited for unrelated reasons), *speculative generality* (abstraction for a need the plan does not have), *message chains*, *middle man*, *refused bequest*.

Two rules bind the floor. **A documented repo standard always wins** — where the project endorses something a smell would flag, the smell is suppressed, not reported. And **every smell is a judgement call**, named as one ("possible feature envy"), never a hard violation. Skip anything the project's tooling already enforces.

### standards

| Category | Examples |
|---|---|
| **`AGENTS.md` / `CLAUDE.md` conventions** | Build/test/lint command alignment; coding conventions stated in the maps |
| **File naming** | New file follows the project's casing convention (kebab-case, snake_case, camelCase, etc.); placement matches existing structure |
| **Commit messages** | Conventional commits (`<type>(<scope>): <subject>`); subject ≤ 50 chars; imperative mood |
| **Frontmatter validity** | Markdown artifacts in `docs/` have valid frontmatter per `references/learning-frontmatter-schema.md` and per Appendix C of foundation |
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

Use `<file>:<line>` for code, the section name for prose, or `global` when it is
about the change as a whole.

## What this skill does with the findings

Contract first: severity, confidence, the autofix classes and the resolution
statuses are defined in `references/peer-contract.md`. What follows is policy.

| Severity | Confidence | Class | Action |
|---|---|---|---|
| P0 | any | any | **Pause and ask.** Even `safe_auto` does not apply silently at P0. |
| P1 | ≥ 7 | `safe_auto` | Apply, re-verify, note in the commit body. |
| P1 | ≥ 7 | `gated_auto` | Apply with a one-line announcement; the user can revert. |
| P1 | ≥ 7 | `manual` | Surface; the user decides. |
| P1 | < 7 | any | Surface; the user decides. |
| P2 | ≥ 8 | `safe_auto` | Apply silently. |
| P2 | ≥ 8 | `gated_auto` | Apply with a one-line announcement. |
| P2 | < 8 | any | File to the tech-debt tracker; mention in the summary. |
| P2 | any | `manual` | Surface; the user decides. |
| P3 | any | `advisory` | Note in the summary. No action. |
| P3 | any | other | File to the tech-debt tracker. |

**Re-verify after applying.** Any code change made in response to a finding
re-runs unit tests and lint before the commit. On failure, `git restore` the
change and surface it. Never commit broken code in pursuit of a finding.

`conflicting` findings are never auto-applied. Prefer `corroborated` ones when
triaging: host and peer agreeing independently is the strongest signal available.

## Confidence surfacing

| Confidence | Behaviour |
|---|---|
| 8–10 | Surface in the main report. |
| 6–7 | Surface with a caveat tag. |
| 5 | Surface only when severity ≥ P1. |
| 1–4 | Suppress unless severity is P0. |

Sub-threshold findings are filed to the tech-debt tracker rather than discarded,
so there is a paper trail without review noise.

## Effort

An ordered first-match cascade — `high` is tested first, so a change satisfying
more than one condition resolves to the strongest tier.

| Order | Tier | Condition |
|---|---|---|
| 1 | `high` | the security or migrations dimension fired, an architectural trigger is present, or the unit is `risk: destructive` or `gated: true` |
| 2 | `low` | the diff is small and carries no risk signals |
| 3 | `medium` | otherwise — the floor |

The floor is `medium`, not `low`: review is a recall problem and the findings
that justify running a peer at all are the subtle ones. `low` is an explicit cost
opt-in for diffs that have earned it.

Resolution order, first hit wins: an `--effort` flag, then
`<repo>/.ensemble/config.local.yaml`, then `~/.ensemble/config.json`
(`review_peer_effort_override`, `review_peer_model_alias`), then the ladder.
`/en-review` is the only resolver; it produces one final tier and one final alias
and passes them on. Model IDs are never hardcoded — see the contract.
