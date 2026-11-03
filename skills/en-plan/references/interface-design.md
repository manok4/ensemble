# Interface design

Read at the per-unit metadata step when a unit changes a **public contract**: an exported API, an HTTP or RPC endpoint, CLI flags, a file or wire format, or a schema another system reads. Internal code is out of scope; a refactor behind an unchanged contract does not need this.

A unit that changes a public contract carries an `Interfaces:` block with the exact names, signatures and shapes, plus a **compatibility line**: additive (old callers keep working), or breaking, with the migration the plan sequences for it.

## Rules

- **Hyrum's law.** With enough callers, every observable behaviour becomes a dependency: an error message's wording, the order of a list, a field that happened to be present. Change what is observable as carefully as what is documented.
- **Add, don't modify.** A new field, a new optional parameter, a new endpoint beside the old one. Version only when a break cannot be avoided, and then plan it as expand, migrate, contract (`references/wide-refactors.md`).
- **One error convention per surface.** If some calls throw, others return `null` and others return `{ error }`, no caller can handle failure correctly. Pick the convention the surface already uses.
- **Validate at the boundary.** Untrusted input is checked where it enters; inner code trusts what the boundary admitted.
- **Predictable names.** The same concept has the same name across the surface, in the casing the surface already uses.

## Idempotency keys

An endpoint a client retries (payments, orders, anything that creates or charges) needs an idempotency key. The plan settles each of these, never the implementer:

- **Derive the key from the intent, not the attempt.** It must stay the same across retries of one intent, and differ between two intents.
- **Claim it atomically.** A check followed by a write is a race: two retries both see "unused" and both act. Use an insert that fails on conflict, or a compare-and-set.
- **Same key, different body, fails loudly.** It is a client bug. Serving the first response to a second, different request hides it.
- **Decide what an in-flight duplicate gets.** The first request is still running when the retry arrives: wait for it, return a "processing" response, or reject with a retry-after. Name which.
- **A timeout means "unknown", not failure.** The effect may have applied. Record the intent before the side effect, so a retry can find out.
- **Keep keys for the longest retry chain,** including any dead-letter replay, not for as long as storage is cheap.

Adapted from addyosmani/agent-skills' `api-and-interface-design` skill (MIT).
