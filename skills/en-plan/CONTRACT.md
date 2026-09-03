# `/en-plan` — contract for calling skills

Owned by `en-plan`. Callers depend on this page, not on `SKILL.md`.

## Accepted invocations

| Form | Caller |
|---|---|
| `/en-plan <description>` | `en-flow`, when no `--plan` was supplied |
| `/en-plan --resume <plan-path>` | promoting a draft plan |
| `/en-plan --from-legacy <path>` | migrating a legacy plan |
| `--no-peer` · `--no-reloop` · `--max-iterations <N>` | peer-loop control |
| `--branch-on-default <y\|current\|no-commit>` | pre-answers the default-branch checkpoint for unattended runs |

An unattended caller must pass `--branch-on-default`, or the default-branch
checkpoint will block.

## Non-interactive guarantee

**Partial, and callers must plan for it.** This skill is interactive by design:
it asks planning questions one per turn. `--branch-on-default` removes the only
checkpoint that blocks unattended, but the planning dialogue itself remains. A
caller wanting a fully unattended run must supply enough context up front that
no question is needed.

## Return

A plan file at `docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md`, plus
frontmatter the caller reads:

| Field | Values |
|---|---|
| `status` | `draft` · `open` (never `active`; that is the directory) |
| `peer_review_verdict` | `approve` · `revise` · `reject` · null |
| `peer_review_plan_hash` | canonical, machine-computed by en-plan; never hand-written or re-derived by a caller |
| `peer_review_resolutions[]` | each `status` is `applied` · `deferred` · `disagreed` · `superseded` |

**Branch on these exact spellings.** A plan left at `draft` is not buildable;
`en-build`'s pre-flight owns the recovery path.

## Authority envelope

Writes one plan file and may commit it. **Never writes code, never opens a PR.**
It may create a feature branch when the default-branch checkpoint says to, and
never force-pushes or rebases.

## Cost bounds

The peer loop is capped by depth: lightweight 1, standard 2, deep 2. The re-loop
is gated on severity — a pass returning only P2/P3 findings exits instead of
spending another round trip.

## Recursion

Under `ENSEMBLE_PEER_REVIEW=true` the Outside Voice pass is skipped and the plan
is produced without it.
