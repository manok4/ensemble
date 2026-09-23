# Publishing a reviewed plan to Linear

> Read at the publish step, after promotion and before auto-commit, and only when
> `plan_store` resolves to `linear`. One section runs earlier: the tracked-source check,
> which `/en-plan` runs at its write-the-plan step, before the plan file, the finalize
> loop or promotion writes anything.
> On `local` none of this runs and the flow is unchanged: the auto-commit step commits the plan as it always has.
>
> `references/linear-plan-format.md` owns the mapping between a plan file and a Linear
> parent plus sub-issues, and `$SKILL_DIR/scripts/ensemble-linear-plan` implements it (D119).
> This file owns the MCP calls around the script and their order. Never transform a plan or a
> read-back by hand: the script is the only implementation `/en-build` also runs.

In `linear` mode the reviewed plan becomes the parent issue and its units become
sub-issues, and **the auto-commit step is skipped entirely**: a repo in Linear mode makes no
plan-related commit. That is the whole point of the mode, and it is also what makes the
tracked-file rule below load-bearing.

## Resolving the configuration, fail-closed

Before anything else, and with these exact invocations. The reader is fail-soft by default,
which is right for a model alias and wrong for a mode switch: without `--strict`,
`plan_store: Linear` (or `[linear]`, or any value the narrow YAML grammar cannot represent)
falls through to `local`, and the operator promotes believing the plan was published when it
never was.

```
plan_store:  ensemble-config-get plan_store --allowed local,linear --default local --strict
linear_team: ensemble-config-get linear_team --required          # linear mode only
```

`--strict` turns a present-but-invalid value into exit 3 instead of a fall-through; an absent
key still falls through, so a repo that never opted in is unaffected. `linear_team` has no
sensible default and is resolved **before any Linear call**: failing here beats failing once a
parent issue exists, and the idempotency protocol's "search the team for an existing parent"
has no team to search without it.

**One more read, a warning rather than a gate, and deliberately without `--strict`.**
`ensemble-config-get linear_github_confirmed --allowed true,false`: when it is not `true`, warn
once before publishing that the team's GitHub integration mapping is unconfirmed (PR open must
map to In Review or nothing, merge to Done; `/en-setup`'s Linear check records it) and continue.
It cannot be checked over MCP, so it is the operator's word, and a publish is not the moment to
block on it.

## Order of operations

The sequence is not arbitrary. Each step exists because doing it later loses something.

1. **Resolve the plan's tracked status** at the
   write-the-plan step: before the plan is written, before the finalize loop writes,
   and so before any Linear mutation. **A tracked plan refuses Linear promotion.** Deciding after the
   publish means deciding with a half-published plan on the other side, and deciding at
   publish means deciding over a file three earlier steps already rewrote.
2. **Confirm the design doc's amendments.** The design is left untouched in `linear` mode
   (below), so an un-amended copy is the version the team keeps reading. `/en-plan` is the only
   skill holding both the design and the plan that consumed it, so this cannot be deferred.
3. **Publish**, in dependency order, so each unit's blocking edges reference identifiers
   that already exist.
4. **Read back and verify.**
5. **Archive the plan**, per the rule below. The design doc is never touched.

## Workflow states

**Only in `linear` mode.** On `local` none of this runs: no state lookup, no MCP call.

`/en-plan` needs the same four states `/en-build` does, and checks them here with
`list_issue_statuses` for the team, because a missing one should surface **before publishing**
rather than once a parent issue already exists:
`Agent Ready`, `In Progress`, `In Review` and `Done`. The third is spelled **In Review**, and
states are matched by name rather than type, since `In Progress` and `In Review` share the type
`started`. A missing or ambiguous state is a blocking error naming which one.

`/en-plan` sets the parent to `Agent Ready` on publish and touches state no further;
`/en-build` owns every transition after that.

## Publishing

Work in `/tmp/ensemble/en-plan/<plan_id>/`. **Render first**:
`bash "$SKILL_DIR/scripts/ensemble-linear-plan" render <plan-path> > payload.json`. It prints the
parent's title and description (the plan with its unit blocks removed, then the Verification
Contract carrying `plan_full_hash` and `repo`) and one entry per unit with its title,
description and `blocked_by`. A non-zero exit stops the publish before any Linear call, with
the reason on stderr (no `origin` remote, a unit without a title).

Then write with `save_issue`, following the idempotency protocol below rather than creating
anything directly: the parent from `payload.parent`, each unit from `payload.units` with
`parentId` set, in dependency order so each `blocked_by` names an issue that already exists.
Send each title and description exactly as rendered. **Each sub-issue's state is set
explicitly at creation.**

U1 measured this against a live workspace: **a sub-issue does not inherit its parent's
state.** One created under an `Agent Ready` parent lands in **Backlog**. Leaving the state
to the default means `/en-build` later starts against units nobody marked ready, so the
state is always written, never assumed.

## Verifying the read-back

**The hash is necessary but not sufficient, so it is not the whole gate.**
`ensemble-plan-hash` covers seven unit fields plus `depth` and `data_scale`. The format
contract maps considerably more: Test scenarios, Verification, Requirements covered,
Reversibility, Ship scope, Execution note and Interfaces. A field Linear mangled outside
the hashed subset would verify clean here and then reach `/en-build`'s pre-flight, which
validates exactly those fields.

So verification is **field-by-field over the full invertible mapping**, with the
`ensemble-plan-hash` comparison against the plan's own `peer_review_plan_hash` as one
clause of it rather than a proxy for it. `ensemble-linear-plan verify` does all of it: both
digests, the recorded `plan_full_hash` and `repo` (both required), a stale
`peer_review_plan_hash`, the frontmatter line for line, and every section and unit. It ignores
`linear_issue:` and `archived:`, which this flow writes into the plan after `render` ran.

**What passing proves.** The digests catch drift between the reviewed plan and what Linear
stored. They do not stop a colleague: they live in the parent they protect, so anyone with write
access to the team can edit a unit and recompute them. Linear write access is authority to
instruct the build (D119).

**Fetch, then verify.** `get_issue` the parent; `list_issues` with its `parentId` for the
sub-issue ids; `get_issue` each sub-issue. Write the results as
`{"parent": <get_issue result>, "sub_issues": [<get_issue result>, …]}` to `readback.json`,
unedited, then run `bash "$SKILL_DIR/scripts/ensemble-linear-plan" verify <plan-path> readback.json`.
**Archive only on exit 0.** Exit 3 prints what differs, a unified diff of the first differing
section or unit; surface it and follow Recovery.

Two measured behaviours shape the fetch, and the script handles both:

- **Linear rewrites `- ` list markers to `* `** (`- **Goal:**` comes back as `* **Goal:**`). A read-back compared as returned
  canonicalizes to seven *empty* fields per unit, and still hashes. The script normalizes
  the markers, the same code `/en-build`'s materialization runs; when verification fails,
  the fix is never to weaken the comparison.
- **`list_issues` truncates descriptions**, returning
  `(truncated, use get_issue for full description)` in place of the tail. That is why each
  unit is fetched with **`get_issue`**, and why the script refuses a description still
  carrying the marker. The N+1 is deliberate: a truncated description that silently
  verified is worse than a slow read-back that verified honestly.

## Archiving, and the tracked-source refusal

**A tracked plan refuses `linear`-mode promotion.** Check it at the write-the-plan
step, before anything is written, name the path, and stop with an actionable message: remove
it from git (`git rm --cached <path>`, commit that), then re-run. Nothing is published, nothing
is moved, and the tree is exactly as it was.

**Why refusal rather than a cleverer rule.** Two weaker attempts failed in review, and both
failed the same way. Moving a tracked file into a gitignored directory leaves a tracked
*deletion*. Leaving it in place but stamping `linear_issue:` and `archived:` into it leaves a
tracked *modification*, which dirties the tree exactly as much. And the stamp is not even the
whole of it: in `linear` mode the finalize loop has already written `peer_review_verdict`,
`peer_review_iterations` and `peer_review_resolutions`, promotion has written
`peer_review_plan_hash` and flipped `status`, and the idempotency protocol writes
`linear_issue:` before any sub-issue exists. A promotion that skips the commit cannot leave a
tracked source clean, whatever the archive rule says.

The two alternatives both hide something. Restoring the committed bytes after publish discards
the review state locally, so an operator reading the file sees no evidence the review happened.
Committing the lifecycle change breaks the headline promise that a `linear`-mode repo makes no
plan-related commit. Refusing hides nothing and the remedy is one command.

**When this actually fires.** A plan authored and promoted in the same `/en-plan` run is
untracked, so the common path is unaffected. It fires on `--resume` of a plan committed earlier,
including an `/en-sweep` draft, which is exactly the case an earlier draft of this rule assumed
away.

| Plan tracked | What happens |
|---|---|
| no | moves to `.ensemble/archive-plans/`, stamped `linear_issue:` and `archived:` |
| yes | **refuse before any write**; name the path and the `git rm --cached` remedy |

An untracked plan is stamped and moved, because nothing git tracks is changed by either.

## Design docs are left alone

**In `linear` mode a design doc is never stamped, moved or status-flipped, tracked or not.**
`/en-plan`'s design close-out is skipped; the parent's Verification Contract carries
`related_design`, which is the link. The run report says the design stays open and names it, so
the operator can close it (`status: accepted`, `related_plan:`) in their next commit.

Designs used to follow the plan's rule, and in a repo that commits its designs, as this one does,
that made the tracked-source refusal fire on nearly every promotion that consumed one. A design is
a durable record rather than an execution artifact, which is the split D118's Problem statement
draws: plans are transient, the record stays in the repo. Leaving it untouched keeps
`git status --porcelain` empty without asking anyone to untrack their design history.

**The contract is auditable, not aspirational:** after a `linear`-mode promotion,
`git status --porcelain` is empty. That is the check, not "no deletion appeared".

## Recovery

On a verification mismatch or a partial publish: **move nothing**, surface what landed,
and leave the plan in `docs/plans/active/`. The failure stays visible.

**Rollback cancels; it does not delete.** The Linear MCP server exposes no delete-issue tool,
so a failed publish cancels what it created and says so. Cleanup is therefore weaker than it
looks, and the idempotency protocol is what actually makes a retry safe.

## Idempotency protocol

In this order, because a retry must never create a second parent.

1. If the plan's frontmatter already carries `linear_issue:`, that parent is authoritative.
   A plan authored from an issue (`references/linear-intake.md`) carries it from the start, so
   publish updates that issue with `save_issue` by id rather than creating a parent.
2. Otherwise **search the team for an existing parent carrying this plan's `plan_id`
   and this repo's `repo` before creating one.** Writing `linear_issue:` immediately after
   the create narrows the crash window but cannot close it: a process killed between the
   API returning and the frontmatter write leaves an orphan parent the next run cannot
   see, and the run after that creates a second. Remote discovery is what closes it, so
   the `plan_id` is carried in the parent's title and `repo` in its Verification
   Contract, and the pair is the durable identity. `plan_id` alone is not: it is
   repo-local, and another repo publishing to the same team can hold the same one.
3. Create the parent if discovery found none, writing `linear_issue:` into the plan's
   frontmatter **before any sub-issue exists**.
4. Fetch the parent's existing sub-issues and reconcile by the `(U<N>)` title suffix,
   creating only the units that are absent and setting each one's state explicitly. An amend
   (`references/linear-intake.md`) also updates surviving units in place and cancels removed ones.
5. Refuse and surface if two sub-issues claim the same U-ID, rather than guessing which is
   current.

**A cancelled parent is not reusable.** Discovery ignores parents in a canceled state and
creates a replacement, because reusing one would resurrect the sub-issues a rollback
cancelled alongside it. Discovery that finds **two live parents** for one `plan_id` and
`repo` refuses and names both; that is a human decision, not a coin flip. A parent with
this `plan_id` and a different `repo` belongs to another repo and is ignored. One with
this `plan_id` and **no** `repo` cannot be attributed, so discovery refuses and names it
rather than adopting or duplicating it.

## The `/en-flow` boundary

`/en-flow` chains planning into building by passing a plan path. In a repo whose
`plan_store` is `linear` there is no path to pass. **Refuse before publishing**, naming
the reason, so the chain cannot reach the state where the plan is in Linear and `/en-flow`
is holding a path that no longer exists. Enforced, not merely documented: a documented
boundary fails after the publish, which is the expensive half.
