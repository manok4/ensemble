# `/en-fix` — contract for calling skills

Owned by `en-fix`. Callers depend on this page, not on `SKILL.md`.

## Accepted invocations

| Form | Caller |
|---|---|
| `/en-fix <request>` | a person |
| `/en-fix <request> --orchestrated [--no-ship] [--no-watch]` | `en-conductor`, on the fix route |
| `/en-fix <request> --orchestrated [--no-ship] [--no-watch] --decision "<question>: <answer>"` | `en-conductor`, continuing a `needs-decision` return on the same branch, with the earlier edits and commits in place; `--decision` repeats, one per answer so far |

## Non-interactive guarantee

Under `--orchestrated` this skill **never asks**. Every stop returns one of the
outcomes below. A caller's brief is not the user's words, so it never lifts a
risk stop, and neither does a `--decision` answer. `--auto-merge` is refused.

## Return

The last line is exactly one of:

| Last line | Meaning |
|---|---|
| `en-fix: shipped <pr-url> <exit-state>` | a PR exists; the exit state is `en-ship`'s |
| `en-fix: ready <branch>` | reviewed and committed, nothing pushed |
| `en-fix: needs-plan clean <condition>` | a plan is needed and nothing was created |
| `en-fix: needs-plan edited <condition>` | a plan is needed and edits stay on the branch |
| `en-fix: needs-decision <question>` | one answer from the user lets it continue |
| `en-fix: split <concern>; <concern>` | unrelated concerns, each its own run |
| `en-fix: stopped <reason>` | any other stop; report it verbatim |

**Branch on these exact spellings.**

## Authority envelope

Writes code and tests, commits on a feature branch, and through `en-ship` pushes
and opens a PR. Never writes a plan, never merges unless a person passed
`--auto-merge`, and never writes Linear state or comments.

## Cost bounds

At most three failed attempts at the change, and at most two review rounds. A
second blocked round stops the run.

## Recursion

Under `ENSEMBLE_PEER_REVIEW=true` it stops at once: it never runs inside a peer
subprocess. It never invokes itself.
