# Brainstorming from a Linear issue

Read when `/en-brainstorm` is given a Linear issue identifier (`EMB-123`) instead of a
description. It turns an issue someone opened with a half-formed idea, a problem to investigate
or a feature to explore into a design, and leaves a trail on the issue so `/en-plan <IDENT>`
picks the design up without re-asking what this session settled (D120).

**The mode comes from `plan_store`, never from the argument's shape**, the rule `/en-plan` and
`/en-build` follow. Read it with
`bash "$SKILL_DIR/scripts/ensemble-config-get" plan_store --allowed local,linear --default local --strict`.
Under `local` an identifier refuses: "`plan_store` is `local`; set it to `linear` in
`.ensemble/config.local.yaml`, or describe the idea instead." An identifier is
`^[A-Z][A-Z0-9]*-[0-9]+$`.

## Admit the issue, or refuse before any Q&A

`get_issue <IDENT>`, then `list_issues` with `parentId: <IDENT>`. Refuse, naming the reason and
asking nothing, when:

- the issue's team is not `linear_team`
  (`bash "$SKILL_DIR/scripts/ensemble-config-get" linear_team --required`);
- it already has sub-issues: a plan has been published onto it, so it is past brainstorming;
- its state is started, completed or canceled.

These are the rules `/en-plan <IDENT>` admits by, on purpose: every issue brainstorming accepts
is one planning will accept, so the chain cannot dead-end on a started or already-planned issue.

## The issue is the request

The issue's title and description are what the frontier rounds start from, quoted as a markdown
blockquote with **every line prefixed `> `**, so a report's own headings and bullets stay
content, never structure. Everything else runs as for any request: the existing-context scan,
the frontier rounds, approaches, recommendation, devil's advocate.

## Resume by the link first

Before the usual topic match, look for an open design whose frontmatter carries
`linear_issue: <IDENT>`; it is the first resume candidate. The topic match then runs as today
with one exclusion: **a design already linked to a different issue is never a candidate.**
Resuming it would overwrite its `linear_issue:` and strand the issue it came from, which would
then point at a design planning can no longer find. A topic match with no `linear_issue:` may be
adopted, and gains the key. Confirmation before resuming is unchanged.

## Link the design, and say so on the issue

The write step adds `linear_issue: <IDENT>` to the design's frontmatter, the identifier exactly
as given.

After each write, first write or a resumed revision, post one `save_comment` on the issue:

```
Design: <repo-relative path of the design doc>
<the recommendation, in two or three lines>
Next: /en-plan <IDENT>
```

One comment per write, so the issue's history shows how the thinking moved. A failed comment
warns and does not fail the run: the design is written, and `/en-plan <IDENT>` finds it by its
frontmatter, not by the comment.

**Never edit the issue's description or state.** Both belong to someone else. `/en-plan <IDENT>`
quotes the description as the original request and its pre-publish re-check refuses a changed
one; plan intake refuses a started issue. A comment disturbs neither.

The design is not committed here, as always. Until it is, only this checkout can find it;
`/en-plan <IDENT>` elsewhere reads the comment and warns that the design lives on another machine.

## Worked example

`EMB-7`, team Emble (`linear_team: EMB`), state Backlog, no sub-issues, description "Exports time
out on large workspaces". Admitted. The frontier starts from:

```
> Export timeouts on large workspaces
> Exports time out on large workspaces
```

The design is written to `docs/designs/2026-09-24-export-timeouts-design.md` with
`linear_issue: EMB-7` in its frontmatter, and EMB-7 gets one comment whose first line is
`Design: docs/designs/2026-09-24-export-timeouts-design.md` and whose last is
`Next: /en-plan EMB-7`.

A second issue, `EMB-9`, on the same topic: `/en-brainstorm EMB-9` is not offered EMB-7's design
for resume, so EMB-7's design keeps `linear_issue: EMB-7` and EMB-9 gets its own.
