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

**Resolve the configuration fail-closed, with these exact invocations.** The reader is
fail-soft by default, which is right for a model alias and wrong for a mode switch: without
`--strict`, `plan_store: Linear` (or any typo) falls through to `local` and the operator ships
believing a plan was published that never was.

```
plan_store:  ensemble-config-get plan_store --allowed local,linear --default local --strict
linear_team: ensemble-config-get linear_team --required          # linear mode only
```

`--strict` makes a present-but-invalid value exit non-zero instead of falling through; an absent
key still falls through, so a repo that never opted in is unaffected. `linear_team` has no
sensible default and is resolved **before any Linear call**, because failing here beats failing
once a parent issue already exists, and because the idempotency protocol's "search the team for
an existing parent" step has no team to search without it.

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

**Provenance is written on both paths, and it is TWO fields, not one.** Collapsing them makes
the `linear` + path row above unshippable: it resolves a source of `local` under a configured
store of `linear`, so a single field forces ship to read one of the two as drift and stop on
every mid-migration build. So record both, and never re-resolve either:

| field | value | what reads it |
|---|---|---|
| `plan_source:` | `linear` or `local` | picks the lifecycle: `git mv` to `completed/`, or the Linear hand-off |
| `configured_store:` | `plan_store` as it read at intake | the only thing compared against the repo's current `plan_store` |

`plan_source` answers "where did this plan come from", `configured_store` answers "what was the
repo set to at the time". Drift is `configured_store` against the live config, in **either**
direction; the mid-migration row is then simply `configured_store: linear` with
`plan_source: local`, which is internally consistent and ships cleanly. A single field written
only on the Linear path would have caught a Linear build shipped under a config since flipped to
`local` and missed the inverse, the one that skips the `git mv` and leaves the plan out of
`docs/plans/completed/` entirely.

## Materializing a plan from Linear

Write the fetched plan to `.ensemble/materialized-plans/<identifier>.md`, then let the normal
"Read `<plan-path>`" proceed against it. A materialized file is always **overwritten, never
merged**, and its path cannot collide with an authoring plan because the directories are
disjoint. Everything downstream, the state matrix above, the plan-hash baseline, the status
flip and the checkpoint, is untouched: that is the point of materializing rather than teaching
the pre-flight about Linear.

`references/linear-plan-format.md` owns the mapping and `$SKILL_DIR/scripts/ensemble-linear-plan`
implements it (D119). **Fetch, then materialize; never rebuild the plan by hand:**

1. `get_issue` the parent; `list_issues` with its `parentId` for the sub-issue ids; `get_issue`
   each sub-issue. `list_issues` truncates descriptions, so its bodies are never used.
2. Write the results unedited as `{"parent": …, "sub_issues": […]}` to a read-back file.
3. `$SKILL_DIR/scripts/ensemble-linear-plan materialize <read-back> --out
   .ensemble/materialized-plans/<identifier>.md`. **Refuse on a non-zero exit, before any
   build work**, surfacing its stderr; the script writes no file when it refuses.

The script applies the rules that decide whether the result is usable at all: it normalizes
Linear's `* ` markers back to `- ` (a plan materialized as returned hashes **seven empty fields
per unit**), refuses a description still carrying Linear's truncation marker (a build that read
it would implement a unit with its Approach cut off), orders units by the `(U<N>)` suffix rather
than Linear's `updatedAt`-descending order, and skips canceled sub-issues.
- **Compare both digests the parent records.** `ensemble-plan-hash` against
  `peer_review_plan_hash`, and `ensemble-plan-hash --full` against `plan_full_hash`. The first
  covers seven fields per unit; an edit made in Linear to Test scenarios, Verification or
  Interfaces passes it and changes what gets built. `--full` covers every labelled field, and
  there is no local source to fall back on, so this is the only check that sees such an edit.
- **Refuse before any build work, naming what is wrong** when: the identifier does not resolve
  to an issue; `materialize` exits non-zero (a missing `(U<N>)` suffix, a duplicate U-ID, a
  truncated description, no Verification Contract); the parent's `repo` is not this repo; or
  `plan_full_hash` is absent or does not match. Name the offending unit in
  each case. A
  parent edited by hand in Linear is the ordinary way to reach all three, and guessing which
  sub-issue was meant is worse than stopping.

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

## Linear state, through the build

**Only in `linear` mode.** A `local` build makes no state lookup and no MCP call: this whole
section fires after the mode is resolved, on the Linear branch only. Worth saying plainly,
because the resolution below is described as happening before the first mutation and a
workspace-wide state preflight on every local build would be both a latency cost and a hard
failure for a repo with no Linear workspace at all.

**Resolve all four states before the first mutation of this run, local or remote**, which means
before the branch is created. The four are `Agent Ready`, `In Progress`, `In Review` and `Done`.
Only `Agent Ready` is one the operator is told to create, so the other three are assumptions
until checked. A missing or ambiguous state is a **blocking error** naming which one, raised
**before any commit exists**, not discovered halfway through a build.

**Match states by name, never by type.** `In Progress` and `In Review` share the type `started`,
so resolving "the started one" picks arbitrarily between them and passes on whichever team
happens to list them in the convenient order. The third state is spelled **In Review**; a bare
"Review" does not exist on a correctly configured team.

| When | Transition |
|---|---|
| build start, beside the status flip | the parent moves to **In Progress** |
| a unit starts | its sub-issue moves to **In Progress** |
| a unit commits | its sub-issue moves to **Done** |
| after the post-build gates pass | the parent moves to **In Review** |

**In Review comes after the post-build gates, not after the last unit commits.** The
simplification pass, the branch review, the evidence audit and any fix loop all run after the
last commit, and any of them can fail gracefully. Setting In Review at the last commit and then
forbidding further writes leaves those failures with no way to honour the promise below of
returning the parent to `Agent Ready`. So the transition is the **last thing before the ship
hand-off**, ordered after the evidence audit.

**`/en-build` stops touching the parent once it sets In Review.** From the moment `/en-ship`
pushes a branch, Linear's own GitHub integration owns it, and the PR is the hand-off point.
**Progress is never written back into the plan body**, in either mode: Linear holds the state,
the plan holds the work.

### Abort, and the gap it cannot cover

On a **graceful** failure or abort, return the parent to `Agent Ready` and leave every
sub-issue at whatever state it reached, so a resumed build can see which units are already
Done. A killed process cannot run that transition, so the guarantee is narrowed to graceful
exits rather than promised outright.

The gap closes at the other end. **At build start, reconcile a parent already In Progress** by
comparing its sub-issue states against the branch's commits, and **surface the discrepancy for
an operator decision** rather than silently resuming or silently restarting. A resumed build
does not reset sub-issues already at Done. Without this, an interrupted build sits In Progress
forever and nothing ever notices.

## The plan-hash baseline

**4a. Plan-hash baseline.** If `peer_review_plan_hash` is present, record it as the build's baseline; the phase-boundary check will compare against it. If absent (legacy plan), compute one with `$SKILL_DIR/scripts/ensemble-plan-hash <plan-path>` and record it (but skip the boundary check this run; surface a notice). **Always use that helper — never canonicalize the fields yourself**, or the baseline and the boundary check will disagree and refuse a plan nobody edited.
