# `/en-brainstorm` — contract for calling skills

Owned by `en-brainstorm`. Callers depend on this page, not on `SKILL.md`.

## Accepted invocations

| Form | Caller |
|---|---|
| `/en-brainstorm <request>` | `en-conductor`, on the brainstorm route; a person |
| `/en-brainstorm <IDENT>` | `en-conductor`, on the brainstorm route for a Linear issue, under `plan_store: linear` (D147) |

## Non-interactive guarantee

**None.** This skill is a conversation with the user. A caller runs it in the
user's own session, never in an agent with no question tool.

## Return

A design doc at `docs/designs/YYYY-MM-DD-<topic>-design.md` with `status: open`,
and a short summary in chat. A conversation abandoned before synthesis writes no
file.

## Authority envelope

Writes one design doc and may capture learnings from it. Never writes code,
never writes a plan and never opens a PR.

## Cost bounds

Bounded by the conversation: it asks until the user settles the approach, and its
research dispatches run once per round.

## Recursion

Under `ENSEMBLE_PEER_REVIEW=true` it exits with a one-line note. It never invokes
itself.
