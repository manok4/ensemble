---
type: design
created: 2026-09-18
topic: Linear as the plan store — per-repo choice between local plans and Linear-resident plans
status: accepted
related_plan: EN18
---

# Linear as the plan store — per-repo choice between local plans and Linear-resident plans

## Problem

Plans live in `docs/plans/active/` and are invisible to anyone not reading the repo. The
operator wants one place to watch work: issues reported from the app land in Linear, get
triaged, and become work an agent picks up, alongside plans authored by `/en-plan`. The
second driver is a reframing: implementation plans were treated as a documentation source,
and they should not be. The durable record belongs in ADRs, `docs/CONTEXT.md` and
architecture docs, derived from code that was actually written. Plans are transient
execution artifacts.

What has to be decided is where a plan lives, what authorizes a build when the plan is not
a file, and how much of the existing pipeline changes.

## Constraints and context

Verified in this repository:

- **No tracker integration exists.** No Linear API call, MCP tool use, or tracker
  abstraction anywhere in `skills/`, `bin/`, `hooks/` or `scripts/`. `/en-debug` mentions
  Linear URLs but implements GitHub only (`skills/en-debug/SKILL.md:126`).
- **No configuration key selects where plans are stored.** `docs/plans/active/` is hardcoded
  (`.ensemble/config.local.example.yaml`, whole file).
- **`/en-build` accepts a filesystem path only** (`skills/en-plan/SKILL.md:146`).
- **No helper in the repo calls an external HTTP API.** Every script invokes a local CLI
  (`git`, `gh`, `claude`, `codex`). Publishing over HTTP is new ground for the codebase.
- **The promotion seam is precise.** On peer-review pass, `/en-plan` computes
  `peer_review_plan_hash`, writes it to frontmatter with `peer_review_verdict`, and flips
  `status: draft → open` (`skills/en-plan/SKILL.md:128-129`). That hash is the existing
  tamper-evidence chain between review and build.
- **Nothing deletes a plan.** `/en-ship` moves it to `docs/plans/completed/` with `git mv`
  (`skills/en-ship/references/plan-completion.md:15`); `/en-sweep` can move a declined draft
  to `docs/plans/archive/` (`skills/en-sweep/references/sweep-checks.md`).
- **`.ensemble/` is not ignorable wholesale.** `.ensemble/config.local.example.yaml` is
  tracked; the existing rule targets one file (`.gitignore:32`).

Verified externally (Linear, as of 2026-09):

- **No custom fields.** Grepping Linear's published `schema.graphql` returns zero
  `CustomField` types. Structured metadata must live in labels, description conventions, or
  Linear Documents.
- **Identifiers split cleanly.** `Issue.id` is an immutable UUID; `Issue.identifier`
  (`ENG-123`) changes on a team move, with the old value kept in `previousIdentifiers`.
- **Sub-issues inherit team, priority and project, but not labels.** This is decisive for the
  approval carrier below.
- **Linear Documents are GraphQL-native markdown** with full CRUD.
- **The MCP server supports bearer-token auth**, so non-interactive use is possible.
- **Rate limits** are 2,500 requests/hour on an API key.
- **Prior art exists.** OpenAI's Symphony and daily.dev's Huginn both drive coding agents
  from Linear issues. Huginn stored agent state in comments and Linear's automatic thread
  archival silently wiped it; they moved state to labels, which survive archival. Linear's
  own MCP documentation recommends a parent issue plus sub-issues as the shape for an
  agent-executable implementation plan.

Carried over from prior art in `agent-skills/`:

- `to-tickets` publishes the same tickets to either a local file set or a real tracker;
  only the shape of the blocking edges changes. It publishes in dependency order so edges
  can reference identifiers that already exist.
- compound-engineering's `ce-work` states the rule this design adopts: do not edit the plan
  body during execution, because progress lives in commits and the tracker, and a `status:`
  field is not state.
- compound-engineering requires file paths in plan units, the opposite of `to-tickets`, and
  resolves the tension by layering: paths live in the execution artifact and are stripped
  from the user-facing synthesis, the glossary, and the handoff objective.

## Assumptions & unverified claims

- **Linear MCP Document write support is unconfirmed.** Linear's own docs describe MCP writes
  as "issues, projects, and comments"; third-party catalogues claim Documents are read-only
  over MCP. GraphQL Document writes are confirmed. Only matters if Approach C is revisited.
- **Sub-issue nesting depth and per-parent count limits are undocumented.** No limit was
  found, which is not proof none exists.
- **Identifier behaviour when an issue is converted to or from a sub-issue, or duplicated,
  is undocumented.** Only the team-move case is described.
- **The Linear workspace's GitHub integration settings are unverified.** Whether it moves an
  issue on PR *open* as well as merge decides whether it fights `/en-build` for the parent
  state. Needs checking in the operator's workspace, not in code.
- **Which state category "Agent Ready" belongs in (Backlog vs Unstarted) is unverified**
  and affects default views and cycle behaviour.
- **Whether Linear preserves the labelled-field markup through a round-trip is unproven.**
  `ensemble-plan-hash` does not hash file bytes; it hashes a canonical projection (per unit, in
  U-ID order: Goal, Files, Approach, Risk, Category, Gated, Dependencies, each whitespace-
  collapsed and length-prefixed). Rebuilding it from Linear needs the `- **Goal:**` bullet
  structure to survive storage and retrieval. Untested.

## Approaches considered

### A. Author directly in Linear

**Sketch:** `/en-brainstorm` and `/en-plan` write into a Linear issue as they work. The
parent issue holds the brainstorm and the plan header; sub-issues hold units. Peer review
reads the issue after it exists. Nothing is written to the repo.

**Pros:**
- One artifact, one place, no duplication at any point.
- Work is visible to the team from the first moment, not only after review.

**Cons:**
- Peer review has to read a tracker instead of a file, which is a rewrite of a gate that
  currently works, for no gain in review quality.
- Linear holds unreviewed drafts, so "everything in Linear is reviewed" stops being true.
- The parent description does two jobs, brainstorm and plan header, with different
  lifecycles and different readers.
- `/en-plan` and `/en-brainstorm` both change substantially; the blast radius is four skills.

### B. Author locally, publish on review-pass, archive locally (recommended)

**Sketch:** `/en-brainstorm` writes its design doc and `/en-plan` writes the plan exactly as
today, including peer review against the local file. On promotion, instead of only flipping
`status`, the plan is published to Linear as a parent issue plus one sub-issue per unit, the
read-back is verified, and the plan and its design doc move to gitignored archives under
`.ensemble/`. `/en-build` takes either a path (local mode) or a Linear identifier
(Linear mode), fetches, and builds.

**Pros:**
- The authoring pipeline does not change at all. Only the last step of `/en-plan` and the
  first step of `/en-build` differ by mode.
- Peer review is untouched: it reviews a file, as now. Linear only ever holds reviewed plans.
- Local mode is genuinely unchanged, not "mostly unchanged".
- Two seams to test instead of a distributed rewrite.
- The brainstorm never reaches Linear, so the parent-description conflict does not arise.

**Cons:**
- The `peer_review_plan_hash` chain needs a Linear front-end that rebuilds the same canonical
  records the file reader produces.
- Publishing is not atomic; a partial publish needs an idempotent re-run.
- Two representations exist briefly, between publish and archive.

### C. Linear as a mirror, repo stays the source of truth

**Sketch:** `/en-plan` writes the plan as today and additionally creates a Linear issue
carrying intent, status and a link. Units stay in `docs/plans/`. `/en-build` reads the file.
Linear is for visibility and triage only.

**Pros:**
- Lowest risk: nothing load-bearing moves, and Linear never gates a build.
- CI keeps full plan access, so requirements-coverage checking is unaffected.
- File paths stay in a short-lived artifact, matching both prior-art systems.

**Cons:**
- Does not deliver the driver. The operator wants to manage the work in Linear, not read a
  mirror of it.
- Two places to keep in step, permanently, rather than briefly.
- Repo churn from plan files and status flips continues.

## Recommendation

**Approach B.** It delivers the driver while leaving the expensive, well-tested parts of the
pipeline alone. The insight that makes it work is that authoring and storage are separable:
a plan can be written and reviewed as a file, then published, without the review machinery
knowing anything about Linear. Approach A pays a four-skill rewrite to move the authoring
step, and buys a worse invariant, because unreviewed drafts become visible as if they were
plans. Approach C is safer but declines the actual request.

The decisions that follow from it:

- **Approval carrier: a Linear workflow state**, not a label, because sub-issues do not
  inherit labels but do carry their own state. `/en-plan` publishes the parent in an
  "Agent Ready" state; nothing builds without it.
- **State ownership: `/en-build` owns both** parent and sub-issue states. No PR exists until
  `/en-ship` runs, so Linear's GitHub integration cannot contend with it. The parent is in
  Review by the time a PR opens, and the integration moves it to Done on merge.
- **Identity: the Linear identifier is the plan id.** `/en-build ENG-412`, branch
  `ENG-412-<slug>`, so Linear's GitHub integration auto-links the PR. U-IDs are unchanged
  inside the plan; `/en-build` resolves to the immutable UUID once and holds that.
- **Unit body: the sub-issue description.** Opening a sub-issue shows the unit. Its U-ID is
  appended to the title (`Add parser coverage (U3)`) so units are scannable in the sub-issue
  list and the U-ID is parseable for ordering. Never lead with the identifier: the reader
  should understand the work before the traceability label.
- **Destination: one per-repo config key names the Linear team.** Plans become issues on that
  team and inherit its workflow states, which is where "Agent Ready" lives. Sub-issues inherit
  the team automatically.
- **An abandoned or failed build returns the parent to "Agent Ready"** and leaves each
  sub-issue in whatever state it reached, so the plan reads as re-runnable and a resumed build
  can see which units are already Done. This mirrors how `/en-build` already resumes from
  `status: in_progress`.
- **In Linear mode `/en-plan` makes no commit.** Step 18 auto-commits the plan file today
  (`skills/en-plan/SKILL.md:18`); in Linear mode the plan is published and archived instead, so
  a repo using Linear has no plan-related commits in its history at all.
- **Progress: commits and tracker state only.** Never written back into the plan body.
- **Archive, do not delete.** Publish, verify, then move both files to
  `.ensemble/archive-plans/` and `.ensemble/archive-designs/`, gitignored per-directory. The
  archived plan is stamped with `linear_issue:` and `archived:` so it reads as superseded and
  serves as the plan-to-issue audit trail.
- **Design docs are scaffolding.** They are archived, not promoted. ADRs are written later
  from the actual diff, never from a design doc, because implementation diverges from what
  was proposed and an ADR sourced from a proposal is confidently wrong.
- **Vocabulary is unchanged: plan and unit, never ticket.** `docs/CONTEXT.md` defines a Plan
  and lists `ticket` under _Avoid_. Storing a plan in Linear does not rename it. Linear's own
  object type is an issue, and that word is fine when describing Linear's API; Ensemble's
  skills, docs and output say plan (the parent) and unit (the sub-issue).
- **CI never reads Linear.** `/en-build`, `/en-plan` and `/en-ship` run locally with the
  operator's credentials. D38's no-secrets-in-CI decision is untouched.

## Devil's advocate

- **The hash chain needs a second front-end, and one unknown.** `ensemble-plan-hash`
  canonicalizes before hashing, so reformatting already does not move it and the mechanism
  transfers in principle: one canonicalizer, a file reader and a Linear reader. The unknown is
  whether Linear returns the `- **Label:**` bullet structure the field parser expects. If it
  rewrites markdown on storage, the Linear front-end has to absorb that. Spike it first; it is
  a short test, not a research project.
- **A Linear-resident plan is editable by anyone with workspace access; a repo file needs a commit.**
  The attack surface on an approved plan grows. The hash catches edits, but only at the next
  check, and only if the hash chain survives.
- **Linear becomes a hard dependency for building.** No Linear, no build. The offline cache is
  a second mechanism that has to be designed, and a stale cache silently builds the wrong plan.
- **Partial publish at 3am.** The script dies after the parent and three of seven sub-issues.
  Without idempotency, re-running creates duplicates and there is no obvious recovery. This is
  the most likely operational failure and it needs tests before it needs features.
- **Identifier drift.** Moving an issue between teams changes `ENG-412`, orphaning branch
  names already created from it. `previousIdentifiers` makes it recoverable but not automatic.
- **The framing may be wrong.** The stated driver is visibility and triage. Approach C
  delivers visibility at a fraction of the cost without making Linear load-bearing for builds.
  If, after using it, the value turns out to be "I can see what's happening" rather than "the
  agent works from Linear", C was the right answer and B is over-built.

## Why we're proceeding anyway

- The per-repo switch bounds the risk: a repo that turns it off is unaffected, and the local
  path stays the tested default.
- Archiving rather than deleting makes every failure mode recoverable by hand.
- A failed publish leaves the plan in `docs/plans/active/`, so the failure is visible rather
  than silent.

**Amended 2026-09-19, during planning.** This section originally argued that the publish step
would be a script, so its invariants could carry negative controls like the rest of the
codebase's mechanical work. Planning chose the Linear MCP server instead: it needs no
credential, and no helper in this repo has ever made an HTTP call. The cost is accepted
knowingly. Publish, verify and archive become model-followed steps rather than a fail-closed
gate, and cannot carry a negative control. EN18 carries this as a named risk.

## Open questions

- Does Linear preserve the `- **Label:**` field markup through publish and read-back, so the
  Linear front-end can rebuild the same canonical records? Spike this first.
- Unit order in the canonical form comes from the U-ID parsed out of the sub-issue title,
  not from Linear's sub-issue ordering, which is not guaranteed stable. Confirm the title
  suffix survives a round-trip alongside the field markup.
- What is the idempotency key for re-publish — U-ID stored in the sub-issue, or a local
  publish receipt written as each unit lands?
- Which state category should "Agent Ready" sit in, and is the workspace's GitHub
  integration configured to move issues on PR open as well as merge?
- What shape is `/en-build`'s offline cache, and what makes a stale cache detectable?
- Does `/en-ship`'s plan-completion step become a no-op in Linear mode, or does it verify the
  Linear state before shipping?

## Next steps

- Run `/en-plan` to turn this into an implementation plan.
- Spike the field round-trip before planning the publish unit: publish one plan, read it back,
  rebuild the canonical form, and compare against `ensemble-plan-hash --canon` on the original.
