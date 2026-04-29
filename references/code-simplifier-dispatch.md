# Code-simplifier dispatch (D29)

How `en-build` invokes the `code-simplifier` agent per unit, and what to do when verification fails.

## When to dispatch

After verification gate 1 (unit tests + lint pass) and **before** per-unit Outside Voice peer review, dispatch the simplifier against the unit's diff.

```
implement → verify gate 1 → SIMPLIFY → verify gate 2 → peer review → host applies findings → commit
                              ▲
                          this step
```

## When to skip

- **Trivial units** — renames, single-line config tweaks, pure deletions, version bumps. The simplifier has nothing to add.
- **`--no-simplify` flag** on the `/en-build` invocation.
- **Recovery from a previous simplifier failure** in the same unit (don't run twice).
- **Generated files** in the diff (the simplifier shouldn't touch them).

Heuristic for "trivial":

- Diff <10 lines added/modified across <3 files.
- Pure deletions (only `-` lines, no `+` lines).
- Diff matches `^[\s-]*[a-zA-Z_]+: ` (config-only changes).

When in doubt, **run** — the cost is low and the second verification gate catches breakage.

## What to pass to the simplifier

The simplifier agent (sourced from Anthropic claude-plugins-official) operates on **recently modified code**. Pass:

- The list of files touched by the unit.
- The unit's `Approach` from the plan (gives the simplifier intent context).
- The project's `CLAUDE.md` and `AGENTS.md` content (so the simplifier knows the conventions).
- A reminder to **preserve exact functionality**.

Concrete dispatch (Claude Code; Codex equivalent uses `spawn_agent`):

```
Agent({
  subagent_type: "code-simplifier",
  description: "Simplify U<N> diff",
  prompt: "Simplify the changes for U<N> in <plan-path>.

Files touched:
  - src/auth/refresh.ts
  - src/auth/refresh.test.ts

Unit approach: <copy of plan's Approach for U<N>>

Project conventions: see AGENTS.md. Project-specific Claude guidance: see CLAUDE.md.

CRITICAL CONSTRAINTS:
  - Preserve exact functionality.
  - Don't introduce new dependencies.
  - Don't refactor outside the unit's scope.
  - Don't add features.
  - Avoid over-simplification (no nested ternaries, no clever-at-cost-of-readable).

Return summary + changes_made[]."
})
```

## Verification gate 2 — re-run unit tests after the simplifier

The simplifier modifies files directly. **Immediately** after it returns:

1. Run the unit-level tests + project lint.
2. **If everything passes** → continue to peer review with the simplified diff.
3. **If anything fails** → revert the simplifier's changes (`git restore` for each file in `changes_made[]`), surface the regression in the unit's progress report, and continue to peer review with the **original** implementation.

```bash
# Re-run unit tests (project-specific; this is illustrative)
bun test src/auth/refresh.test.ts || {
  echo "Simplifier broke tests for U$U_ID — reverting." >&2
  for file in $simplifier_changed_files; do
    git restore --staged "$file" 2>/dev/null
    git restore "$file"
  done
  echo "REGRESSION: code-simplifier introduced test failures on U$U_ID; original implementation retained."
}
```

## What the simplifier returns

Per `agents/code-simplifier.md`:

```json
{
  "summary": "<1-3 sentences on what changed and why>",
  "changes_made": [
    {
      "file": "src/auth/refresh.ts",
      "change": "Replaced nested ternary with early return for clarity"
    },
    {
      "file": "src/auth/refresh.test.ts",
      "change": "Renamed test cases to follow project convention (it() → describe → it pattern)"
    }
  ]
}
```

The host posts `summary` + `changes_made[]` in the unit's progress report so the user sees what the simplifier did before peer review runs.

## Configuration

`~/.ensemble/config.json` keys:

```json
{
  "simplifier": {
    "enabled_default": true,
    "skip_on_trivial": true,
    "max_lines_to_run": 2000
  }
}
```

`max_lines_to_run` — if the unit's diff exceeds this, skip the simplifier (defensive; large diffs are rare per-unit and the cost of a botched simplification grows quickly).

## Why two gates around the simplifier

The simplifier is the only agent that **modifies code** (refiner, not reviewer). The two verification gates are the safety contract:

- **Gate 1** (before): the unit must already be correct. The simplifier is for refinement, not for fixing broken code.
- **Gate 2** (after): the simplifier didn't break anything. If it did, revert and proceed with the original.

Without gate 1, the simplifier can hide bugs behind "cleaner" rewrites. Without gate 2, broken-but-prettier code reaches the peer reviewer and wastes a peer round.

## Failure protocol

| Failure | Behavior |
|---|---|
| Simplifier subprocess errors out | Log; surface in progress; proceed with original (no revert needed — nothing was applied) |
| Simplifier returns empty `changes_made` | Treat as "no improvements found"; continue with original |
| Simplifier returns malformed JSON | Log; surface; proceed with original |
| Gate 2 test failure | Revert; surface regression with the failing test name; proceed with original |
| Gate 2 lint failure | Revert; surface; proceed with original |
| Multiple consecutive units fail Gate 2 | After 3 in a row, **disable the simplifier for the rest of the run** with a one-line note. Suggests something systemic (project conventions clash with simplifier rules) for a `learn capture` after the build |
