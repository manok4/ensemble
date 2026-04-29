# Append-merge rules for `AGENTS.md` and `CLAUDE.md`

Used by `/en-setup` State 2 sub-variants 2b, 2c, 2d when an existing `AGENTS.md` and/or `CLAUDE.md` is found in the repo. **Never overwrite existing user content.**

## Core principle

> If the user already has it, leave it. Add Ensemble's contribution as a new appended section, but only if it isn't already there.

The merge is idempotent — running `/en-setup` twice on the same file produces the same result.

## Detection — does the file already have Ensemble integration?

`AGENTS.md`:

- Look for any of: a heading "Ensemble pointer map", a heading "Where things live", a link to `docs/foundation.md`, or a link to `docs/learnings/index.md`.
- If found → already integrated; skip append.
- Else → append.

`CLAUDE.md`:

- Look for any of: a heading "Ensemble — Claude Code notes", a heading "Slash command preferences" containing `/en-*` references, or a link to `docs/foundation.md`.
- If found → already integrated; skip append.
- Else → append.

## CLAUDE.md cross-reference check (always-applied)

Independent of the integration check, `/en-setup` always ensures the first non-frontmatter line of `CLAUDE.md` is:

```markdown
> See [AGENTS.md](./AGENTS.md) for the project map and shared agent guidance.
```

If absent → prepend it (after frontmatter, before any existing content).
If present → leave it.

This rule fires regardless of whether the rest of the Ensemble section is appended.

## Append placement

When appending, place the Ensemble section at the **end** of the existing file, separated by a single blank line. Don't try to "smartly merge" into existing sections — that risks corrupting the user's content.

Add a leading separator and clear heading:

```markdown

---

## Ensemble pointer map

<contents from template, starting at "## Where things live">
```

The separator (`---` on its own line) makes the boundary obvious to humans and survives any subsequent garden runs.

## Frontmatter handling

If the existing file has frontmatter:

- Keep the user's frontmatter intact.
- Add or update only fields the lint requires:
  - `host: any` (AGENTS.md) — add if missing
  - `host: claude-code` (CLAUDE.md) — add if missing
  - `type: agent-map` — add if missing
  - `target_length_lines: 100` (AGENTS.md) / `60` (CLAUDE.md) — add if missing
  - `updated: YYYY-MM-DD` — bump to today on every `/en-setup` run that modified the file
- Never remove user-added frontmatter fields.

If the existing file has no frontmatter:

- Add the Ensemble frontmatter block at the very top.
- Preserve all existing body content untouched.

## What never gets touched

- Existing prose. Even if it covers the same topics as the template, leave it.
- Existing links. Even if they point to non-Ensemble paths.
- Section ordering of existing content.
- User-added frontmatter fields.

## Worked examples

### Example: 2b (CLAUDE.md only) → AGENTS.md is generated, CLAUDE.md is touched lightly

Before — CLAUDE.md exists with:

```markdown
# My project

Some notes about the project for Claude.

## Build commands

`npm run build`
```

After `/en-setup`:

- `AGENTS.md` — newly generated from template (no existing file).
- `CLAUDE.md` — modified to:

```markdown
---
project: my-project
type: agent-map
host: claude-code
created: <existing or today>
updated: <today>
target_length_lines: 60
references: ./AGENTS.md
---

> See [AGENTS.md](./AGENTS.md) for the project map and shared agent guidance.

# My project

Some notes about the project for Claude.

## Build commands

`npm run build`

---

## Ensemble — Claude Code notes

[appended template content]
```

(Note: the existing `## Build commands` section is technically forbidden in CLAUDE.md per the strict rules, but `/en-setup` does not move user content. The lint will surface a P2 advisory for the user to migrate it.)

### Example: 2c (AGENTS.md only) → CLAUDE.md generated, AGENTS.md touched lightly

Before — AGENTS.md exists with custom team content. After `/en-setup`:

- `AGENTS.md` — kept; Ensemble section appended at the end with `---` separator and `## Ensemble pointer map` heading.
- `CLAUDE.md` — newly generated from template.

### Example: 2d (both) → both touched lightly

Both files kept; Ensemble sections appended only if missing; CLAUDE.md cross-reference line prepended if missing.

## Reporting

`/en-setup` reports the merge action explicitly:

```text
AGENTS.md: ✓ already had Ensemble pointer map (no changes)
CLAUDE.md: ✓ added cross-reference line; appended "Ensemble — Claude Code notes" section
```

The user always knows what was modified.

## Edge cases

| Case | Behavior |
|---|---|
| Existing file has malformed frontmatter | Skip frontmatter mutation; surface a warning; ask user to fix manually |
| Existing file is empty | Treat as 2a (greenfield); generate fully from template |
| Existing file has Ensemble section but it's stale (older template) | Leave it; do not auto-update. User runs `/en-garden` or manual update |
| User-added content matches Ensemble template verbatim | Don't append; treat as already-integrated |
