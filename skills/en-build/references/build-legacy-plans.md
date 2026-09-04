# Legacy plans — inference for pre-D37 plan files

Read only when the plan being built predates the peer-review frontmatter or the per-unit `risk:` field. New plans carry both (the lint requires them), so a normal build never opens this file.

## Pre-flight: no `peer_review_verdict` field

Map the old iteration-log signals onto the pre-flight sub-state matrix in SKILL.md, or refuse:

| Legacy signal | Inferred state |
|---|---|
| `status: draft` AND a parseable iteration log shows applied/deferred/disagreed entries | Treat as `peer_review_verdict: revise` + reconstructed `peer_review_resolutions` (best-effort, flagged `inferred: true`); offer finalize-and-build with a legacy notice |
| `status: draft` AND no iteration log | Treat as `peer_review_verdict: null`; refuse |
| `status: open` AND no peer-review fields | Treat as `peer_review_verdict: null` AND `/en-plan --no-peer` was the path; accept |
| `status: open` AND iteration log shows final `verdict: approve` | Treat as `peer_review_verdict: approve`; accept |
| Any other ambiguous combination | Refuse with a clear instruction to re-run `/en-plan --resume <plan-path>` |

## Units without `risk:`

Single ordered classifier, **first match wins**:

1. **Destructive patterns** (highest priority): approach mentions `DROP TABLE`, `DROP SCHEMA`, `DROP DATABASE`, mass `DELETE` without `WHERE`, `TRUNCATE`, `rm -rf` against data dirs, `aws s3 rm --recursive`, `kubectl delete` against persistent resources, `terraform destroy` → `risk: destructive`.
2. **Destructive migrations**: `migrations/` or `alembic/` paths AND `ALTER COLUMN` (drop/rename/type-change), `DROP COLUMN`, `DROP INDEX` on populated index, destructive data transforms → `risk: high`, `category: migration`.
3. **Additive migrations**: `migrations/` paths AND additive only (`CREATE TABLE`, `ADD COLUMN` with default, `CREATE INDEX CONCURRENTLY`) → `risk: medium`, `category: migration-additive`.
4. **Backfill**: approach mentions iterating existing rows (UPDATE batch loop, ETL backfill) → `risk: high`, `category: backfill`.
5. **Observability/read-only**: files entirely under `tests/`, `docs/`, or configured observability paths → `risk: low`, `category: observability`.
6. **Fallback**: → `risk: medium`, `category: feature`.

When inference fires, surface a confirmation: *"Plan has no `risk:` metadata. Inferred classification: P1 (3), P2 (5), P3 (2), P4 (1). Review before continuing? (y/n)"*.

The confirmation is mandatory before proceeding on inferred classes: a legacy plan was never peer-reviewed against these categories, and the phase placement and safety gates both key off them.
