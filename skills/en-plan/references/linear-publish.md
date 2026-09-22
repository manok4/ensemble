# Publishing a reviewed plan to Linear

> Read at the publish step, after promotion and before auto-commit, and only when
> `plan_store` resolves to `linear`. On `local` the whole step is a no-op and the flow is unchanged:
> nothing here runs and the auto-commit step commits the plan as it always has.
>
> `references/linear-plan-format.md` owns the mapping between a plan file and a Linear
> parent plus sub-issues, including the marker normalization both this step and
> `/en-build` apply. Read it alongside this one; do not restate its rules from memory.

In `linear` mode the reviewed plan becomes the parent issue and its units become
sub-issues, and **the auto-commit step is skipped entirely**: a repo in Linear mode makes no
plan-related commit. That is the whole point of the mode, and it is also what makes the
tracked-file rule below load-bearing.

## Order of operations

The sequence is not arbitrary. Each step exists because doing it later loses something.

1. **Resolve tracked status for both sources**, the plan and its design doc, *before any Linear mutation*.
   Deciding after the publish means deciding with a half-published plan on the other side.
2. **Confirm the design doc's amendments.** Once the design is archived or closed out, an
   un-amended copy is the version that survives. `/en-plan` is the only skill holding both
   the design and the plan that consumed it, so this cannot be deferred to a later unit.
3. **Publish**, in dependency order, so each unit's blocking edges reference identifiers
   that already exist.
4. **Read back and verify.**
5. **Archive, or leave in place**, per the tracked-file rule.

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

## Archiving, and the tracked-file rule

**Moving a tracked file into a gitignored directory leaves a tracked deletion in the
working tree**, which would dirty the tree the no-commit promotion promises not to touch.
So the rule keys on tracked status, and it applies to **both sources, plan and design**.

An earlier draft assumed the plan is always untracked because `/en-plan` wrote it that
run. That is false on `--resume`: an `/en-sweep` draft, or any plan committed before
promotion, arrives tracked.

| Source | Tracked | What happens |
|---|---|---|
| plan | no | moves to `.ensemble/archive-plans/`, stamped `linear_issue:` and `archived:` |
| plan | yes | stays in `docs/plans/active/`, stamped `linear_issue:` and `archived:` |
| design | no | moves to `.ensemble/archive-designs/`, stamped the same way |
| design | yes | stays where it is, closed out to `accepted` in the normal way |

A tracked source is already durable and in history, which is what archiving was for. The
stamps make it read as superseded either way, and they double as the plan-to-issue audit
trail. Removing a tracked source afterwards is a normal committed change someone makes
deliberately, never a side effect of promotion.

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
   before creating one.** Writing `linear_issue:` immediately after the create narrows the
   crash window but cannot close it: a process killed between the API returning and the
   frontmatter write leaves an orphan parent the next run cannot see, and the run after
   that creates a second. Remote discovery is what closes it, so the `plan_id` is carried
   in the parent's title as the durable identity and searched for first.
3. Create the parent if discovery found none, writing `linear_issue:` into the plan's
   frontmatter **before any sub-issue exists**.
4. Fetch the parent's existing sub-issues and reconcile by the `(U<N>)` title suffix,
   creating only the units that are absent and setting each one's state explicitly.
5. Refuse and surface if two sub-issues claim the same U-ID, rather than guessing which is
   current.

**A cancelled parent is not reusable.** Discovery ignores parents in a canceled state and
creates a replacement, because reusing one would resurrect the sub-issues a rollback
cancelled alongside it. Discovery that finds **two live parents** for one `plan_id`
refuses and names both; that is a human decision, not a coin flip.

## The `/en-flow` boundary

`/en-flow` chains planning into building by passing a plan path. In a repo whose
`plan_store` is `linear` there is no path to pass. **Refuse before publishing**, naming
the reason, so the chain cannot reach the state where the plan is in Linear and `/en-flow`
is holding a path that no longer exists. Enforced, not merely documented: a documented
boundary fails after the publish, which is the expensive half.
