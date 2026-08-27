# `/en-learn` — contract for calling skills

Owned by `en-learn`. Callers depend on this page, not on `SKILL.md`.

## Accepted invocations

| Form | Caller |
|---|---|
| `/en-learn capture` | `en-build`'s learning checkpoint |
| `/en-learn capture --from-conversation` | `en-brainstorm`, with a design doc as input |
| `/en-learn --lint` | `en-sweep`, wiki-graph health |
| `/en-learn --refresh` · `--pack <library>` · `--bootstrap-patterns` | user-invoked modes |
| `--fix` | with `--lint`, auto-applies mechanical repairs |

## Non-interactive guarantee

`--lint` is fully unattended and is the mode CI uses. `capture` is
conversational by default; a skill invoking it should expect interaction unless
it supplies the subject itself.

## Return

| Mode | Return |
|---|---|
| `capture` | learning entries written, plus a count the caller reports |
| `--lint` | JSON report: orphans, broken links, missing back-references, contradictions |
| `--refresh` | per entry, one of `keep` · `update` · `replace` · `archive` |

**Branch on these exact spellings.**

## Authority envelope

Writes under `docs/learnings/`, and syncs `docs/architecture.md`, foundation and
plan lifecycle state. **Never writes application code and never opens a PR.**
`--fix` mutates only files this skill owns. Moving a plan to `completed/` is
lifecycle bookkeeping, not a content edit.

## Cost bounds

`--lint` reads the index before drilling in, so graph health does not cost a
full corpus read.

## Recursion

Does not invoke a peer subprocess; `ENSEMBLE_PEER_REVIEW` does not change its
behavior.
