# Template — `CLAUDE.md`

Used by `/en-foundation` and `/en-setup` to seed the project-level `CLAUDE.md`.

> **Strict rules** (D15, lint `claude-md.no-shared-content`):
> - **First line** must be the cross-reference to `AGENTS.md`.
> - Body contains **Claude-Code-specific content only**. No content duplicated from `AGENTS.md`.
> - Forbidden: project structure, coding conventions, build/test/lint commands, architecture descriptions — all belong in `AGENTS.md`.
> - Body target ≤ 60 lines (~80 hard ceiling — soft P2 lint at >80).

## Substitution variables

| Variable | Source |
|---|---|
| `{{PROJECT_NAME}}` | `foundation.md` `project:` |
| `{{TODAY}}` | `YYYY-MM-DD` at generation time |

## Template body

```markdown
---
project: {{PROJECT_NAME}}
type: agent-map
host: claude-code
created: {{TODAY}}
updated: {{TODAY}}
target_length_lines: 60
references: ./AGENTS.md
---

> See [AGENTS.md](./AGENTS.md) for the project map and shared agent guidance.

# {{PROJECT_NAME}} — Claude Code notes

This file is **Claude-Code-specific only**. Anything readable by Codex (project structure, build/test commands, conventions, architecture) lives in `AGENTS.md`. Do not duplicate.

## Slash command preferences

- Prefer `/en-plan` before `/en-build` for any feature touching > 3 files.
- Use `/en-cross-review <path>` for ad-hoc peer review without going through the full review skill.
- For routine refactors that fall under garden's purview, let `/en-garden` run on the next merge — don't open a bespoke PR.

## Skill invocation priority

When multiple skills could apply to the user's request:

1. If the user names a skill explicitly → use that one.
2. Else, route to the most specific skill (`en-build` over a generic implementation skill, `en-foundation` over `en-plan` for a new product).
3. If still ambiguous, ask once with two options.

## Auto-memory

Memory files live at `~/.claude/projects/-Users-...-{{PROJECT_NAME}}/memory/`. Save user-preference and feedback memories there per `~/.claude/CLAUDE.md` global instructions; project-specific facts go in `docs/learnings/` instead.

## Tool-name notes

- `AskUserQuestion`, `CronCreate`, `TaskCreate`, etc. are deferred tools — preload via `ToolSearch` before first use in a session.
- Prefer dedicated tools (`Read`, `Edit`, `Write`) over `Bash` for file operations.

## Plugin / marketplace

This project is configured for the Ensemble plugin (`/plugin install ensemble@ensemble`). If the plugin isn't present, run `/en-setup` to verify install state.
```

## Notes on generation

- The template above is the **starting** state. As the project evolves, the user (or `en-garden`) may extend Slash command preferences and Skill invocation priority sections.
- The first-line cross-reference is mandatory; the lint will P1-fail if it's missing or modified.
- The `host: claude-code` frontmatter is critical — it's how `bin/ensemble-lint` knows this is the Claude-specific map.

## Append-merge mode (State 2b/2c/2d)

When an existing `CLAUDE.md` is present, `/en-setup` does **not** overwrite it. Instead:

1. Parse existing content.
2. **Cross-reference check.** If the first non-frontmatter line is not the AGENTS.md cross-reference, **prepend** the cross-reference line (above any other content; below frontmatter).
3. **Ensemble section check.** Look for a section heading like "Ensemble Claude Code notes" or "Slash command preferences" pointing to `/en-*` commands.
4. If absent → append the **Slash command preferences + Skill invocation priority + Tool-name notes + Plugin / marketplace** sections as a new block (heading: `## Ensemble — Claude Code notes`).
5. If present → no-op.
6. Never modify existing user content.

See `references/templates/agents-md-merge-rules.md` for the full append-merge logic (applies symmetrically to `CLAUDE.md`).
