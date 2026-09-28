# `/en-debug`: contract for calling skills

Owned by `en-debug`. Callers depend on this page, not on `SKILL.md`.

## Accepted invocations

| Form | Caller |
|---|---|
| `/en-debug <words>` | `en-fix`, on the bug path, before any edit |

The words are the user's request plus any issue or tracker text the caller
already resolved. `/en-debug` does not fetch from Linear itself. Mode is chosen
from the words exactly as for a person: telemetry when they are log-anchored and
`observability:` is configured, code mode otherwise.

## Non-interactive guarantee

Invoked by a skill, this never calls a blocking-question tool: not the
fix-choice gate, not the tail-mode "which event?" question, and not the prompt
for a missing log location. Anything it would have asked becomes an
`unresolved` return carrying the question as its reason.

## Return

A diagnosis the caller branches on. `verdict` is exactly one of:

`convergent` · `divergent` · `design-problem` · `unresolved`

| Field | Content |
|---|---|
| `verdict` | as above; `convergent` restores behaviour everyone agrees is correct, `divergent` would reverse a deliberate decision (D62) |
| `root_cause` | the causal chain from trigger to symptom, with `file:line`; absent on `unresolved` |
| `proposed_fix` | the minimal change and the tests to add; absent unless `convergent` |
| `confidence` | 1 to 10, per the skill's confidence scale |
| `reason` | required on `design-problem` and `unresolved`: the gap, or the question it could not ask |

**Branch on these exact spellings.** A caller proceeds to an edit only on
`convergent`; every other verdict is shown to the user.

## Authority envelope

Read-only. It never edits a file, commits, pushes or opens a PR, whoever calls
it. The fix belongs to the caller.

## Cost bounds

Code mode's investigation is bounded by its own escalation rule: after two or
three exhausted hypotheses it returns `design-problem` or `unresolved` rather
than forming another. Telemetry mode caps fetched lines at
`observability.max_log_lines`.

## Recursion

Under `ENSEMBLE_PEER_REVIEW=true` it exits without a diagnosis. It never spawns
a peer subprocess.
