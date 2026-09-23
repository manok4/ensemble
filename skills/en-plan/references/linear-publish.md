# Publishing a reviewed plan to Linear

> Read at the publish step, after promotion and before auto-commit, and only when
> `plan_store` resolves to `linear`. One section runs earlier: the tracked-source check,
> which `/en-plan` runs at its write-the-plan step, before the plan file, the finalize
> loop or promotion writes anything.
> On `local` none of this runs and the flow is unchanged: the auto-commit step commits the plan as it always has.
>
> `references/linear-plan-format.md` owns the mapping between a plan file and a Linear
> parent plus sub-issues, including the marker normalization both this step and
> `/en-build` apply. Read it alongside this one; do not restate its rules from memory.

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

## Order of operations

The sequence is not arbitrary. Each step exists because doing it later loses something.

1. **Resolve tracked status for both sources**, the plan and its design doc, at the
   write-the-plan step: before the plan is written, before the finalize loop writes,
   and so before any Linear mutation. **A tracked source refuses Linear promotion.** Deciding after the
   publish means deciding with a half-published plan on the other side, and deciding at
   publish means deciding over a file three earlier steps already rewrote.
2. **Confirm the design doc's amendments.** Once the design is archived or closed out, an
   un-amended copy is the version that survives. `/en-plan` is the only skill holding both
   the design and the plan that consumed it, so this cannot be deferred to a later unit.
3. **Publish**, in dependency order, so each unit's blocking edges reference identifiers
   that already exist.
4. **Read back and verify.**
5. **Archive, or leave in place**, per the tracked-file rule.

## Workflow states

**Only in `linear` mode.** On `local` none of this runs: no state lookup, no MCP call.

`/en-plan` needs the same four states `/en-build` does, and checks them here because a missing
one should surface **before publishing** rather than once a parent issue already exists:
`Agent Ready`, `In Progress`, `In Review` and `Done`. The third is spelled **In Review**, and
states are matched by name rather than type, since `In Progress` and `In Review` share the type
`started`. A missing or ambiguous state is a blocking error naming which one.

`/en-plan` sets the parent to `Agent Ready` on publish and touches state no further;
`/en-build` owns every transition after that.

## Publishing

Follow the idempotency protocol below rather than creating anything directly. Units are
created in dependency order. **Each sub-issue's state is set explicitly at creation.**

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
clause of it rather than a proxy for it. Archive only when both hold.

Before publishing, compute `ensemble-plan-hash --full <plan>` and `repo` and write both
into the parent's Verification Contract, per the format doc. `/en-build` has no local
source to compare against, so `plan_full_hash` is what lets it refuse a plan someone
edited in Linear outside the seven hashed fields. The read-back verifies both keys like
any other field.

Two measured behaviours shape how the read-back is fetched and compared:

- **Linear rewrites `- ` list markers to `* `.** Sent `- **Goal:** …`, stored and
  returned `* **Goal:** …`. `ensemble-plan-hash` anchors on
  `^- \*\*(Goal|Files|Approach|Risk|Category|Gated|Dependencies):\*\*`, so a read-back
  compared as returned canonicalizes to seven *empty* fields per unit. It still hashes.
  **Normalize `* **` back to `- **` before canonicalizing**, per the format doc, which is
  the same rule `/en-build` applies on the materialization side. Without it verification
  fails on every plan, and the tempting repair is to weaken the comparison instead.
- **`list_issues` truncates descriptions**, returning
  `(truncated, use get_issue for full description)` in place of the tail. Read-back is
  therefore one list call plus a **`get_issue` per unit**. The N+1 is deliberate: a
  truncated description that silently verified is worse than a slow read-back that
  verified honestly.

## Archiving, and the tracked-source refusal

**A tracked plan or design refuses `linear`-mode promotion.** Check both at the write-the-plan
step, before anything is written, name which source is tracked, and stop with an actionable message: remove
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

| Source | Tracked | What happens |
|---|---|---|
| plan | no | moves to `.ensemble/archive-plans/`, stamped `linear_issue:` and `archived:` |
| plan | yes | **refuse before any write**; name the path and the `git rm --cached` remedy |
| design | no | moves to `.ensemble/archive-designs/`, stamped the same way |
| design | yes | **refuse before any write**, same message |

An untracked source is stamped and moved, because nothing git tracks is changed by either.

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
   creating only the units that are absent and setting each one's state explicitly.
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
