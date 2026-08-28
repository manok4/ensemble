# ADR format — `docs/decisions/`

A decision lands at `docs/decisions/NNNN-<slug>.md`.

## Why no frontmatter

A solution entry carries frontmatter because something has to **find** it:
`applies_when` is what surfaces the entry when an agent is in a matching
situation. An ADR is reached differently — a reader follows a link, an index
entry, or a citation from a solution. Nothing queries it by field.

So every field would be bookkeeping nobody reads, and bookkeeping nobody reads
goes stale without anyone noticing. **ADRs carry zero frontmatter.** The title
and the body do all the work.

## The title states the claim

The H1 is the decision, written as a claim a reader can act on:

> `# Ship the skill set as a native Claude Code plugin; defer a native Codex plugin`

Not `# Plugin distribution`, which names the topic and leaves the reader to open
the file to learn what was decided. A title that states the claim means an index
of ADRs is already a summary of every decision the project has made.

Semicolons are useful here: most real decisions are a choice *plus* a deferral.

## Numbering

`NNNN` is a zero-padded four-digit sequence: `0001`, `0002`. Take the next
unused number.

**Never renumber and never reuse.** Numbers are cited from solutions, commits,
and other ADRs; a renumber silently redirects every one of those citations. This
is the same rule as `stable-ids.md` applies to U-IDs, for the same reason.

## Required sections

An ADR is prose, not a form. Only one section is mandatory.

**The context or constraint.** What forced the decision. A constraint a reader
cannot reconstruct is the reason the decision looks arbitrary later.

**The decision.** What was chosen. State it plainly.

**`## Invariants this creates`** — **required.** The rules that now hold because
of this decision.

This is what separates an ADR from a diary entry. A decision tells a future agent
what happened; an invariant tells them what they must uphold, and can be checked
against. Write each as something falsifiable:

> - Every promoted skill has an entry in `plugin.json`'s `skills` array.
> - `plugin.json`'s `version` tracks `package.json`'s: bump both together.

If a decision creates no invariant, it is probably a solution, not a decision —
re-read `artifact-types.md`.

## Rejected alternatives

Record what was considered and **why it lost**, with any evidence.

This is the most valuable thing an ADR holds. A tree records what exists; it can
never record what was rejected, so the next person to have the same idea repeats
the work to reach the same dead end. "Symlinks were tested; the installer drops
them" saves that entirely.

## Amendment: `## Update, YYYY-MM-DD`

When reality moves, **amend in place**. Append a dated section:

```
## Update, 2026-08-05

The listing now points at the repo's git URL directly, so the marketplace.json
path above is superseded. That file is retained only as a fallback.
```

Do **not** write a new ADR that supersedes this one unless the *decision itself*
is reversed. Amending in place keeps one decision's whole history where the
reader already is; superseding scatters it across files a reader must find and
order for themselves.

An ADR with three dated updates is a healthy ADR. It means the decision stayed
live and someone kept it honest.

## Shape

```
# <the decision, stated as a claim>

<the constraint or context that forced it>

## Decision

<what was chosen>

## Rejected alternatives

<what lost, and why — with evidence where it exists>

## Invariants this creates

- <a rule that now holds, written so it could be checked>

## Update, YYYY-MM-DD

<appended when reality moves>
```
