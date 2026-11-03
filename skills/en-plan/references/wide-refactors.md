# Wide refactors: expand, migrate, contract

Read at the break-into-units step, when the work is one mechanical change with a blast radius across the codebase, or a breaking schema change, and not otherwise.

**Wide refactors are the exception to all of the above.** A wide refactor is one mechanical change — rename a column, retype a shared symbol — whose blast radius fans across the codebase, so a single edit breaks hundreds of call sites at once and no self-contained unit can land green. Do not force it into one. Sequence it **expand → migrate → contract**:

- **Expand:** add the new form beside the old so nothing breaks. Its own unit.
- **Migrate:** move call sites over in batches sized by blast radius (per package, per directory), each batch its own unit depending on the expand. The old form still exists, so every batch lands green.
- **Contract:** delete the old form once no caller remains, in a unit depending on every migrate batch.

Only the contract unit is destructive: give it `category: removal` and the `risk:` its blast radius earns, while the batches stay additive at their own lower risk. `unit.destructive-order` then holds for free, since the one destructive unit is also the last one. When even a single batch cannot stay green alone, keep the sequence and say so in the plan: the batches share a branch and only the final unit promises green.

## Breaking schema changes

A rename, a type change or a dropped column, on a table that live code reads and writes, cannot land as one unit. Deploys roll out one instance at a time, and jobs and other services write the table on their own schedules. The order matters as much as the steps: dual writes start **before** the backfill, so no write lands only in the old form after its row was copied.

1. **Expand.** Add the new column or table, nullable or defaulted. `risk: medium`, `category: migration-additive`.
2. **Dual-write.** Deploy code that writes both forms and still reads the old.
3. **Drain old writers.** Confirm that no writer is left writing only the old form: app instances, background workers, scheduled jobs, other services. The unit names each writer and how its retirement is confirmed, such as a deploy version check, a job disabled, or a consumer upgraded. Until this holds, an old writer can update a row after reconciliation and leave the new form stale.
4. **Backfill.** Copy rows written before step 2, in batches, idempotent and resumable after an interruption. It writes the new form only where that is still empty, or under a compare-and-set on a version or `updated_at` column, so it never overwrites a newer dual-written value. `category: backfill`, `risk` from the row count.
5. **Reconcile.** Count the rows where the two forms differ. It runs after the drain and the backfill and must report zero. A nonzero count reruns the backfill for those rows and blocks the switch.
6. **Switch reads.** Read the new form. Rollback is pointing reads back at the old form, which dual writes kept current.
7. **Stop old-form writes.** Deploy code that writes only the new form.
8. **Contract.** Drop the old form. **Always `risk: destructive`**, `category: drop`, and last in the plan, which `unit.destructive-order` enforces. Never `high`: a DROP cannot be reverted.

**Gated** follows the usual rule. Authoring a migration or backfill script is `gated: false`. A unit that runs one against production at build time is `gated: true`.

**Several releases.** When the steps must ship in separate releases, the later units carry `Ship scope: deferred`.

**Worked example: a job that still writes the old column.** Renaming `users.fullname` to `display_name`. The API dual-writes from step 2, but a nightly job, `jobs/sync-crm.js`, still runs `UPDATE users SET fullname = ...`. Without step 3 the backfill copies every row, reconciliation reads zero, and the next night the job rewrites `fullname` on thousands of rows that `display_name` never sees. The drain unit names the job and the change that makes it dual-write, and the backfill waits for it.

The schema-change steps adapt agent-skills' `deprecation-and-migration` skill (MIT), reordered so dual writes precede the backfill and old writers are drained first.

