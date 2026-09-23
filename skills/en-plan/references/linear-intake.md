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

**Keep what you fetched.** Record the issue's title, description, team and state as fetched; the
pre-publish check compares against them.

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

**Publish onto the issue, not beside it.** The idempotency protocol's first rule applies:
`linear_issue:` is already set, so that issue is the parent. Update it with `save_issue` by id
(title and description from `render`, state Agent Ready) instead of creating a parent, then
create the sub-issues under it. Read-back, `verify` and archiving are exactly as for any publish.
