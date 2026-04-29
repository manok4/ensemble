# Stable IDs

The IDs Ensemble assigns and the rules that keep them stable.

## Catalog

| ID | Where assigned | Format | Stability rule |
|---|---|---|---|
| `R<N>` | `foundation.md` Section 5 (Functional Requirements) | `R1`, `R2`, … | Append-only. Removed requirements get marked `deprecated`, not deleted. |
| `A<N>` | `foundation.md` Section 3 (Users & Actors) | `A1`, `A2`, … | Append-only. |
| `F<N>` | `foundation.md` Section 6 (User Experience) | `F1`, `F2`, … | Append-only. |
| `AE<N>` | `foundation.md` Section 5 (Acceptance Examples) | `AE1`, `AE2`, … | Append-only. |
| `U<N>` | `docs/plans/FRXX-*.md` Implementation Units | `U1`, `U2`, … per plan | Never renumbered after assignment. Splitting a unit keeps the original ID on the original concept and assigns a new ID to the new piece. |
| `FR<NN>` | `docs/plans/FRXX-*.md` filename prefix | `FR01`, `FR02`, … | Auto-incremented from highest existing across `active/` and `completed/`. Zero-padded to 2 digits up to FR99. |
| `TD<N>` | `docs/plans/tech-debt-tracker.md` | `TD1`, `TD2`, … | Append-only. |
| `D<N>` | `foundation.md` Section 4 (Product Decisions) | `D1`, `D2`, … | Append-only. Decisions can be marked `superseded` but not renumbered. |
| `Q<N>` | `foundation.md` Section 16 (Open Questions) | `Q1`, `Q2`, … | Append-only. Resolved questions stay numbered. |

## Why append-only

Stable IDs are the cross-reference glue. A test that says `Covers AE2` must always mean the same acceptance example. A commit that says `feat(auth): rotate token — U3` must always be readable in light of the original U3 spec.

Renumbering breaks this glue silently. Even if every existing reference is updated, future references to "what U3 used to mean" become impossible to recover.

## Splitting and merging

When a plan unit is too coarse and gets split:

- **Wrong:** Renumber. U3 becomes U3a and U3b; existing references break.
- **Right:** Keep U3 on the original concept. Assign U(highest+1), U(highest+2) etc. to the new pieces. Note in U3's metadata: `Split: see also U7, U8`.

When two plan units get merged:

- **Wrong:** Delete one; reuse the other's ID.
- **Right:** Mark one as `merged_into: U<N>`; both keep their IDs. The plan body shows only the surviving unit's spec.

## Renumbering exception

The **only** exception: pre-publication of a plan. Before the plan is committed (still in `draft` state), the user can renumber freely. Once `status: active` and the plan is committed, IDs are frozen.

`bin/ensemble-lint`'s `id-stability.*` rules check the most recent commit's ID set against earlier commits. Renumbering in `active`/`completed` plans triggers `id-stability.u-renumbered` (P1).

## FRXX numbering

`FR<NN>` is the plan **filename** prefix. Zero-padded:

- FR01, FR02, …, FR09, FR10, FR11, …, FR99.
- FR100+ uses three digits (FR100). Unlikely in practice; if reached, the project has a different problem than naming.

When `en-plan` creates a new plan, it scans both `docs/plans/active/` and `docs/plans/completed/` for the highest existing FRXX, then increments. Gaps are tolerated (FR07 might be missing if a plan was abandoned and deleted) but not introduced.

## TD numbering

`TD<N>` for tracked technical debt. Assigned by:

- `en-plan` when filing items deferred from the plan.
- `en-build` when a peer-review finding is "agree but defer".
- `en-review` when a finding is `gated_auto`/`manual` but the user defers.
- `en-garden` when it surfaces a code-level pattern (always defers — garden is doc-only).

Format: `TD1`, `TD2`, … in `docs/plans/tech-debt-tracker.md`. Append-only.

`en-plan` cites them via `Resolves: TD<N>` in unit metadata when a new plan addresses tracked debt:

```yaml
- name: U4
  resolves: [TD7]
  approach: ...
```

## Lint enforcement

`bin/ensemble-lint` enforces stability:

- `id-stability.r-renumbered` (P1)
- `id-stability.a-renumbered` (P1)
- `id-stability.f-renumbered` (P1)
- `id-stability.ae-renumbered` (P1)
- `id-stability.u-renumbered` (P1)
- `id-stability.fr-collision` (P1)
- `id-stability.fr-format` (P2)
- `id-stability.td-renumbered` (P1)

Cross-link integrity (`cross-link.broken-r`, `broken-u`, `broken-fr`, `broken-td`) is enforced separately — see `references/doc-lints.md`.

## Practical tips

- When in doubt, **append**. Cheap.
- Never touch existing IDs in a "cleanup" pass. The ID is the contract.
- When a requirement is no longer relevant, mark `status: deprecated`, don't delete.
- `learn capture` writes a learning when a stable ID gets `superseded` so future runs understand the history.
