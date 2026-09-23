# Planning from Linear

Read when `/en-plan` is given a Linear issue identifier (`ENG-123`) instead of a description or a
path. Two entry points share this file: an identifier as the **request**, which plans from a
triaged issue and publishes onto it, and `--resume <IDENT>`, which amends a published plan.

**The mode comes from `plan_store`, never from the argument's shape**, the rule `/en-build`
follows. Read it with `$SKILL_DIR/scripts/ensemble-config-get plan_store --allowed local,linear
--default local --strict`. Under `local` an identifier refuses: "`plan_store` is `local`; set it to
`linear` in `.ensemble/config.local.yaml`, or describe the request instead." An identifier is
`^[A-Z][A-Z0-9]*-[0-9]+$`.

## An issue as the request: `/en-plan ENG-123`

The workflow this serves: issues reported from the app land in Linear, get triaged, and become
agent work. Without it the triaged issue and the plan for it are two unrelated issues.

**Admit the issue, or refuse before anything is written.** `get_issue <IDENT>`, then
`list_issues` with `parentId: <IDENT>`. Refuse, naming the reason, when:

- the issue's team is not `linear_team`;
- it already has sub-issues: they are not ours to reconcile, and publishing would mix them with
  the plan's units;
- its state is started, completed or canceled: someone is already working on it, or it is done.

**Keep what you fetched.** Save the issue's title, description, team and state as fetched to
`/tmp/ensemble/en-plan/<plan_id>/issue-snapshot.json`; the pre-publish check compares against it,
and a file survives a session where a remembered value does not.

**Quote the request into Context.** Under `### Original request (<IDENT>)` in the plan's
`## Context`, the issue's title and description as a markdown blockquote, **every line prefixed
`> `**. A report carrying its own `## ` headings, even `## Implementation units`, then cannot open
a plan section, and `ensemble-linear-plan render` republishes it inside the parent description, so
nothing is lost. Linear keeps the original in the issue's history too.

**Author and review as normal.** Set `linear_issue: <IDENT>` in the plan's frontmatter from the
start. The rest of the flow is unchanged: research, questions, units, the finalize loop,
promotion.

**Re-check immediately before publish.** `get_issue <IDENT>` and `list_issues` with its
`parentId` again, and refuse, naming what changed and writing nothing, if the title,
description, team or state differ from what was fetched, or it now has sub-issues: the report was
edited, the issue moved team, someone started it, or someone split it while the plan was under
review. The remedy is to re-run `/en-plan <IDENT>` against the issue as it now stands.

**The re-check guards the first write only.** Once the issue's description carries this plan's
Verification Contract (its `plan_id` and `repo`), this plan has already written to it, and a
retry after a partial publish or a failed `verify` follows the idempotency protocol and Recovery
in `references/linear-publish.md` instead: the changed description and new sub-issues are this
plan's own, not someone else's edit.

**Publish onto the issue, not beside it.** The idempotency protocol's first rule applies:
`linear_issue:` is already set, so that issue is the parent. Update it with `save_issue` by id
(title and description from `render`, state Agent Ready) instead of creating a parent, then
create the sub-issues under it. Read-back, `verify` and archiving are exactly as for any publish.

## Amend in place: `/en-plan --resume ENG-412`

A published plan can be revised, re-reviewed and updated in Linear from any machine, **before a
build starts**. Work in `/tmp/ensemble/en-plan/<IDENT>/`.

**Admit the parent, or refuse before anything is written.** `get_issue <IDENT>`. Refuse, naming
the state, unless it is Agent Ready or earlier (an unstarted, backlog or triage state): In
Progress, In Review and Done mean a build is running on, or shipped, the reviewed version, and
amending under it would make the two diverge.

**Materialize the published plan.** `list_issues` with `parentId: <IDENT>`, `get_issue` each
sub-issue, and save the results unedited as `intake-readback.json`. Refuse **before any write**
if any file for that `plan_id` already exists under `docs/plans/active/` or
`docs/plans/completed/`, tracked or not: an unfinished earlier revision is never overwritten.
Then `bash "$SKILL_DIR/scripts/ensemble-linear-plan" intake intake-readback.json --out
docs/plans/active/<plan_id>-<plan_type>_<slug>.md`, which refuses a contract for another repo or
one whose digests do not match, and validates `plan_id` and `plan_type` before they name a file.
Keep a copy as `intake.md` beside the read-back; the pre-update check compares against it.

**Revise and review as normal**, from the resume-or-create step onward: the finalize loop and
promotion run over the materialized file and write fresh hashes. Set `linear_issue: <IDENT>` in
its frontmatter: a plan first published fresh wrote that key after `render`, so its contract never
carried it. **U-IDs are never renumbered or reused**: a unit the revision adds takes one
above the highest U-ID among **all** sub-issues in `intake-readback.json`, canceled ones included.

**Re-check immediately before updating Linear.** Fetch a fresh read-back the same way and refuse,
writing nothing, if the parent's state has left the amendable set, or if
`ensemble-linear-plan verify intake.md fresh-readback.json` exits non-zero: a build started, or
someone edited the plan in Linear, while it was under review.

**Update in place.** `render` the revised plan. Update the parent with `save_issue` by id, and
each surviving unit's sub-issue by id (the U-ID to identifier map comes from the fresh read-back).
Create the units the revision added, with `parentId` and state Agent Ready. **Cancel** the
sub-issue of each unit the revision removed; the MCP server has no delete tool, and a canceled
sub-issue is not a unit, so `materialize` and `verify` skip it. Then read back, `verify` and
archive exactly as for a first publish.

