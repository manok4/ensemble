# Pre-flight (`/en-build` steps 1 to 4)

What the build checks before it touches a branch: that the skill's own payload
arrived intact, which plan states are buildable, and how the plan-hash baseline
is set. `SKILL.md` keeps the four outcomes and the refusals; this file is read
when the build starts.

## The payload check

**Plugin-install preflight (fail-fast).** Confirm each of these exists. A partial install carrying only `SKILL.md` leaves peer review to degrade silently:

- `references/severity.md`
- `references/finding-schema.md`
- `$SKILL_DIR/scripts/ensemble-verify-peer-evidence`

If any are missing, **fail at start with a clear error** — do not proceed with a degraded build. Surface the exact paths missing and tell the user to re-run `/en-setup` or sync the plugin.

## Which plan states are buildable

**Pre-flight sub-state matrix** — read `peer_review_verdict` and the count of unresolved entries in `peer_review_resolutions:` (an entry is "unresolved" when its `status` is absent or anything other than `applied | deferred | disagreed | superseded`):

| status | verdict | unresolved findings | git tracked | Pre-flight action |
|---|---|---|---|---|
| `open` | `approve` | 0 | yes | Proceed to step 4a |
| `open` | `approve` | 0 | **no** | Offer auto-commit (one prompt), then proceed |
| `draft` | `revise` | 0 | yes or no | **Offer finalize-and-build:** one prompt to re-run the peer pass via `/en-plan`'s finalize loop, on `approve` flip to `open`, auto-commit, then proceed |
| `draft` | `revise` | > 0 | any | Refuse; list the unresolved findings; ask the user to apply/defer/disagree first via `/en-plan --resume` |
| `open` | `null` | n/a | yes | Proceed (the plan was made with `/en-plan --no-peer`; no peer verdict expected) |
| `open` | `null` | n/a | **no** | Offer auto-commit, then proceed |
| `draft` | `null` | n/a | any | Refuse; peer review never ran. Suggest `/en-plan --resume <plan-path>`. |
| `draft` | `reject` | any | any | Refuse; user must take over. Surface `peer_review_resolutions:` for context. |
| `completed` / `abandoned` | any | any | any | Refuse |

**Legacy inference** (a plan with no `peer_review_verdict` field at all): read `references/build-legacy-plans.md`, which owns the inference table; it maps the old iteration-log signals onto the matrix above or refuses.

Recovery prompt (when offering finalize-and-build):

> Plan is in draft. Findings from the last peer review (verdict: revise) appear to be applied (resolutions: 8 applied, 0 deferred, 0 disagreed). I can finalize now: re-run the peer pass, flip to `open` on approve, and commit the plan. Then proceed with `/en-build`. (y / n / details)

Declining the offer at the prompt is how you skip it; `--finalize-only` runs finalize and stops without building.

## Resolving the argument: path or Linear identifier

**The mode comes from `plan_store`, not from the argument's shape.** Selecting on shape alone
would let `/en-build ENG-412` reach Linear in a repo configured `local`, which is the one thing
the per-repo switch exists to prevent. Resolve all four combinations **before any fetch and
before the branch is created**:

| `plan_store` | argument | outcome |
|---|---|---|
| `local` | a path | unchanged, today's behaviour |
| `local` | an `ABC-123` identifier | refuse, naming `plan_store: local`; no fetch, no branch |
| `linear` | an `ABC-123` identifier | fetch and materialize |
| `linear` | a path | build it, and record provenance as `local` |

The last row is deliberate rather than a refusal: a repo mid-migration still has plans on disk,
and refusing them would strand work the switch was never meant to touch. What matters is that
the **resolved mode is recorded as immutable build provenance**, so `/en-ship` and `/en-learn`
act on what this build did rather than on what the config says later.

## Materializing a plan from Linear

Write the fetched plan to `.ensemble/materialized-plans/<identifier>.md`, then let the normal
"Read `<plan-path>`" proceed against it. A materialized file is always **overwritten, never
merged**, and its path cannot collide with an authoring plan because the directories are
disjoint. Everything downstream, the state matrix above, the plan-hash baseline, the status
flip and the checkpoint, is untouched: that is the point of materializing rather than teaching
the pre-flight about Linear.

`references/linear-plan-format.md` owns the mapping. Three of its rules decide whether the
result is usable at all, and each was measured rather than assumed:

- **Normalize `* **` back to `- **` at the start of every unit body**, before anything reads
  the result. Linear rewrites `- ` list markers to `* `, and `ensemble-plan-hash` anchors on
  `^- \*\*(Goal|Files|Approach|Risk|Category|Gated|Dependencies):\*\*`. A plan materialized
  as returned still hashes; it hashes **seven empty fields per unit**, so every unit's digest is
  identical and the checkpoint compares two meaningless values. Field values themselves survive
  byte-for-byte, so the normalization is the whole of the repair, not the first of several.
- **Fetch one `list_issues` for the children plus a `get_issue` per unit.** `list_issues`
  truncates descriptions, returning `(truncated, use get_issue for full description)`; a build
  that read the truncated form would silently implement a plan with its Approach cut off. Refuse
  on a description still carrying that marker rather than treating it as the unit's content.
- **Order units by the `(U<N>)` title suffix**, never by Linear's own ordering. The default is
  `updatedAt` descending, so it is not merely unspecified, it is actively wrong for a build.
  Two sub-issues claiming the same U-ID refuse, naming the duplicate, and write no file.

| status | verdict | unresolved findings | git tracked | Pre-flight action |
|---|---|---|---|---|
| materialized from Linear | as published | 0 | **no** (not git-tracked, by design) | Proceed; do **not** offer auto-commit |

A materialized plan is a generated artifact in a gitignored directory, so its untracked state
is expected and is not the "plan file was never committed" case the auto-commit offer exists
for. The directory is also how `/en-learn` and `/en-ship` tell a generated file from an
authoring plan whose archive failed: same shape, different directory.

**Name the branch from the Linear identifier**, `ENG-412-<slug>`. This is what lets Linear's
GitHub integration associate the PR with the plan and move it to Done on merge; the state
hand-off in `/en-build` assumes that link exists and nothing else establishes it. In `local`
mode the branch name is unchanged.

## The plan-hash baseline

**4a. Plan-hash baseline.** If `peer_review_plan_hash` is present, record it as the build's baseline; the phase-boundary check will compare against it. If absent (legacy plan), compute one with `$SKILL_DIR/scripts/ensemble-plan-hash <plan-path>` and record it (but skip the boundary check this run; surface a notice). **Always use that helper — never canonicalize the fields yourself**, or the baseline and the boundary check will disagree and refuse a plan nobody edited.
