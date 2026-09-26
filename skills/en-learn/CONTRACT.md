# `/en-learn` — contract for calling skills

Owned by `en-learn`. Callers depend on this page, not on `SKILL.md`.

## Accepted invocations

| Form | Caller |
|---|---|
| `/en-learn capture` | `en-build`'s learning checkpoint |
| `/en-learn capture --from-conversation` | `en-brainstorm`, with a design doc as input |
| `/en-learn capture` | `en-loop`, at loop end |
| `/en-learn --lint` | `en-sweep`, wiki-graph health |
| `--fix` | with `--lint`, auto-applies mechanical repairs |
| `/en-learn --migrate` | a person, once, on a store still on the retired layout |
| `/en-learn --enforce-audit` | a person, when adopting the correction router or after a map file grows |

## Non-interactive guarantee

`--lint` is fully unattended and is the mode CI uses. When a caller drives
`capture`, the capture gate decides and nothing is asked; a failed gate is a
reported skip, not a question. The one question capture can ask, whether to add
a layer 1 or 2 check on the branch now, is asked only when a person invoked
capture directly; the entry is filed before it either way. `--refresh` confirms each disposition with a
person unless `--auto` is passed.

## Return

| Mode | Return |
|---|---|
| `capture` | learning entries written and TD-IDs filed (layers 1 to 4), each with a count the caller reports |
| `--enforce-audit` | a table of rules with layer, proposed check and TD-ID, or the proposals alone when the tracker cannot be written |
| `--lint` | JSON report: orphans, broken links, missing back-references, contradictions |
| `--refresh` | per entry, one of `keep` · `update` · `replace` · `archive` |

**Branch on these exact spellings.**

## Authority envelope

Writes under `docs/learnings/`, appends routed entries to
`docs/plans/tech-debt-tracker.md`, and syncs
`docs/architecture.md`, foundation and plan lifecycle state. **Never writes application code and never opens a PR.**
`--fix` mutates only files this skill owns. Moving a plan to `completed/` is
lifecycle bookkeeping, not a content edit.

## Cost bounds

`--lint` reads the index before drilling in, so graph health does not cost a
full corpus read.

## Recursion

Does not invoke a peer subprocess; `ENSEMBLE_PEER_REVIEW` does not change its
behavior.
