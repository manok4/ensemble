# Sourcing the request

Read at the source-the-request step, after the input candidates are read and before `plan_type` is inferred.

**Bounded foundation read.** Never read `docs/foundation.md` whole — it routinely runs past 2,000 lines. Read the **frontmatter** (for `plan_id_prefix`), then `grep -n '^#' docs/foundation.md` for the section index, then `sed -n '<start>,<end>p'` on the sections you actually need: **Functional Requirements** for R-IDs and acceptance examples, **Technical Direction** when the plan makes stack or dependency choices. Nothing else.

**Consume the design doc; don't re-interview across it.** When a `docs/designs/*.md` matches this topic with `status: open` or `accepted`, its settled decisions are **already answered** — architecture, scope boundaries, rejected alternatives, and the recommendation. Read it, carry those decisions into the plan (record the path in `related_design:`), and put **only what the doc left open** to the user in the planning questions. Re-asking a question the design doc settled is the most common way this seam wastes the user's time. The doc's `## Assumptions & unverified claims` section is the exception: those are explicitly *not* settled — verify them against the repo or carry them forward as plan-level assumptions.

**Context-sufficiency check.** Before planning, judge whether you have enough to plan *from* — not whether a design doc happens to exist. Skip this entirely for a bug/TD fix or a `--resume`/`--from-legacy` run, and skip it when a matching design doc was consumed above (that doc already did this work).

The request is **insufficient** when one or more of these is genuinely unresolved, and nothing in the foundation, research, or the request itself settles it:

- **The problem is unstated.** You know what to build but not what it's for or who for — so no unit can claim a requirement and "done" has no definition.
- **The approach is genuinely open.** Two or more materially different designs are viable and there is no basis in context to choose. Planning here picks an architecture by accident.
- **Scope has no edges.** You cannot tell what's in and what's out, so units can't be sized and the plan will either sprawl or miss half the work.

**Insufficient → offer the brainstorm, and mean it:**
> *"I don't have enough to plan from yet — <the specific gap, in one clause>. `/en-brainstorm` would settle that in a few questions and hand back a design doc. Brainstorm first, or plan anyway on my assumptions? (brainstorm / plan anyway)"*

Recommend `brainstorm` — but **proceeding is always allowed** and remains the default on any non-answer; this is never a hard gate (gating-shrink philosophy — encourage, don't block). If the user proceeds anyway, record each unresolved gap in the plan's `## Decisions, assumptions & risks` section as an explicit assumption, so the guess is visible rather than buried in a unit's `Approach:`.

**Sufficient but no design doc → one-line soft nudge only:** *"No design doc for this — want to `/en-brainstorm` first, or go straight to planning? (brainstorm / proceed)."* Default proceed. A well-specified request does not need to be talked out of being well-specified.
