# When to update `docs/architecture.md`

`docs/architecture.md` is the **living architectural reality** of the project. `en-learn` updates it after every material structural change ships; `en-garden` checks it for drift on every PR-merge run.

This file defines what counts as "material" and how the update happens.

## Material changes (trigger an update)

| Trigger | Example |
|---|---|
| New top-level component / service / module / package | Added `src/services/billing/` |
| Removed component, retired service, dropped dependency | Removed `next-auth`, replaced with `clerk` |
| Changed component boundary or layer | Moved `notifications/` from `lib/` to `services/` |
| New external integration | Added Stripe webhook handler |
| Removed external integration | Dropped Mailgun in favor of native SES |
| New infrastructure | Added Redis cache, Inngest worker, Postgres replica |
| Database schema additions/removals at the entity level | New `Subscription` table |
| Auth, permission, or trust-boundary changes | Added admin role; changed token TTL |

## Non-material changes (do NOT trigger an update)

- Cosmetic refactors (rename a function, reorder imports)
- Internal renames where the boundary doesn't change
- Bug fixes that don't change structure
- Pure test additions
- Field-level schema tweaks (added a `created_at` column)
- Style/formatting changes

If in doubt: ask "would a new engineer joining the project benefit from seeing this in the architecture doc?" If no, skip.

## Update protocol

`en-learn capture` performs the architecture sync as part of its post-ship sweep:

1. **Identify what changed.** Read the merged commits + the unit progress reports + the plan.
2. **Classify.** Material vs non-material per the rules above.
3. **Locate the affected section** in `docs/architecture.md`. Surgical edits to drifted sections only — never regenerate the whole doc.
4. **Apply the edit.** Add the new component, remove the deleted one, update the dependency arrow, etc.
5. **Bump `updated: YYYY-MM-DD`** in the frontmatter.
6. **Note in `log.md`:** `## [<date>] arch-update | <one-line summary>`.

## What `docs/architecture.md` contains

Per `references/architecture-template.md`:

| Section | Maintained by | Contents |
|---|---|---|
| Frontmatter | `en-foundation` (seed), `en-learn` (`updated:`), `en-garden` (`last_drift_check:`) | `status`, `created`, `updated`, `last_drift_check`, `freshness_target_days` |
| **Components and responsibilities** | `en-learn` after every material change | One entry per top-level component: name, responsibility, key files, owner team if applicable |
| **Component boundaries and layer rules** | `en-foundation` (seed), `en-learn` (refinements) | Allowed/disallowed import direction, layer hierarchy |
| **Data flows** | `en-foundation` (seed), `en-learn` after material flow changes | Primary flows: request lifecycle, write paths, async pipelines |
| **External integrations** | `en-learn` per change | Per integration: name, purpose, auth model, failure mode |
| **Infrastructure** | `en-learn` per change | Datastores, queues, caches, workers; production topology summary |
| **Database entity overview** | `en-learn` per material schema change | Entity-level (not field-level) overview with relationships |
| **Auth and trust boundaries** | `en-learn` per auth change | Roles, tokens, permission boundaries |
| **Open architectural questions** | `en-foundation` (seed), `en-learn` per resolution | Things still being decided; resolved questions move to `decisions/` learnings |

## Status field

| Status | Meaning |
|---|---|
| `seed` | Initial draft from `en-foundation`. Not yet validated against shipped reality. |
| `active` | Reflects shipped reality. Updated continuously. |

`en-learn` flips `seed` → `active` after the first successful update following the first feature ship.

## Drift checks (`en-garden`)

On every PR-merge run, `en-garden` invokes `repo-research` to compare `docs/architecture.md` against the codebase:

- **Documented components still present?** If a component was removed but the doc still lists it → P1.
- **Dependency rules honored?** If layer rules say A → B is forbidden but a recent commit added it → P0 (file as tech debt; don't auto-fix).
- **Layer boundaries clean?** Cross-layer imports flagged.
- **Freshness window.** `updated:` field within `freshness_target_days` (default 30) → green; up to 90 → P2 advisory; >90 → P1.

Doc-only fixes (component renames, dependency-direction documentation) go into garden's batch PRs. Code-level findings (a layer rule violation in source) go to `tech-debt-tracker.md`.

## When in doubt

If `en-learn` is unsure whether a change is material:

1. Default to **update**. Better to over-document than to leave stale.
2. Note it in the commit body: `Architecture update: <one-line summary>`.
3. Surface the call in the post-ship summary: "Updated `docs/architecture.md` for the new `BillingService` component."
4. User can revert if it was unnecessary.

The cost of an unnecessary update is small (one PR comment). The cost of missed material changes compounds — the doc drifts and people stop trusting it.
