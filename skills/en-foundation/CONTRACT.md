# `/en-foundation` — contract for calling skills

Owned by `en-foundation`. Callers depend on this page, not on `SKILL.md`.

## Accepted invocations

| Form | Caller |
|---|---|
| `/en-foundation <request>` | `en-conductor`, on the foundation route; a person |
| `--retrofit` | back-fill the foundation for an existing project from its code |
| `--no-peer` | skip the Outside Voice review of the draft |

## Non-interactive guarantee

**None.** This skill interviews the user and needs their acceptance before it
finishes. A caller runs it in the user's own session, never in an agent with no
question tool.

## Return

`docs/foundation.md` at `status: active` once the user accepts it, plus
`docs/architecture.md`, `AGENTS.md` and `CLAUDE.md`. For a new project, also a
bootstrap plan under `docs/plans/active/`.

## Authority envelope

Writes documents only. Never writes code and never opens a PR.

## Cost bounds

The Outside Voice review runs under its own peer loop, and `--no-peer` skips it.

## Recursion

Under `ENSEMBLE_PEER_REVIEW=true` the Outside Voice pass is skipped. It never
invokes itself.
