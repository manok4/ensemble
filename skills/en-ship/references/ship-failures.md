# `/en-ship` failure protocol

Read when a run hits one of these. Each row is the behaviour, not a suggestion,
and they share one rule: a failure stops the ship and surfaces. Nothing here
auto-reverts, auto-stashes, or works around the problem on the user's behalf.

| Failure | Behavior |
|---|---|
| Lint or typecheck fails | Stop; surface; suggest `/en-review` |
| Targeted tests fail | Stop; surface failing test names; suggest `/en-qa` |
| Secret scan matches high-confidence pattern | Stop; print offenders; require `--allow-secrets` to override |
| Merge conflict | Stop; do not attempt ship on conflicted tree |
| Push target is the default branch | Refuse until the step-3 confirmation is given verbatim. There is no flag for this: a typed confirmation is the whole mechanism, and a flag would let a caller pre-authorise it in a config file. |
| `gh pr create` fails (auth, repo permissions) | Surface error; commit + push succeed regardless; user can open PR manually |
| Auto-merge requested but branch protection rejects | Surface; PR remains open; user reviews and merges manually |
| Unstaged dirty tree at start | Resolve it with step 7's state machine: scope-matching changes are staged path by path, everything else is preserved and excluded. "Stage all" is not offered — it was, and on a tree holding unrelated work it commits what the user never offered. |
| Branch is detached HEAD | Refuse (`ensemble-ship-preflight` exits 1, `blocked: detached-head`); ask user to check out or create a branch first |
