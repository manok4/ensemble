# Wide refactors: expand, migrate, contract

Read at the break-into-units step, when the work is one mechanical change with a blast radius across the codebase, and not otherwise.

**Wide refactors are the exception to all of the above.** A wide refactor is one mechanical change — rename a column, retype a shared symbol — whose blast radius fans across the codebase, so a single edit breaks hundreds of call sites at once and no self-contained unit can land green. Do not force it into one. Sequence it **expand → migrate → contract**:

- **Expand:** add the new form beside the old so nothing breaks. Its own unit.
- **Migrate:** move call sites over in batches sized by blast radius (per package, per directory), each batch its own unit depending on the expand. The old form still exists, so every batch lands green.
- **Contract:** delete the old form once no caller remains, in a unit depending on every migrate batch.

Only the contract unit is destructive: give it `category: removal` and the `risk:` its blast radius earns, while the batches stay additive at their own lower risk. `unit.destructive-order` then holds for free, since the one destructive unit is also the last one. When even a single batch cannot stay green alone, keep the sequence and say so in the plan: the batches share a branch and only the final unit promises green.
