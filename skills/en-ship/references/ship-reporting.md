# What a `/en-ship` run prints

Read when composing the run report. The watch step's exit states are here too,
because the state and the line it prints are one decision, and splitting them is
how a state acquires two different closing sentences.

## The watch loop's exit states

Exit in **exactly one** of these, with its evidence. Never improvise a closing
sentence, and never say "safe to merge": that is the reader's call, not this
skill's.

| State | When | Line |
|---|---|---|
| `clean` | green checks, no unresolved threads | `PR is green and clean — <n> checks passed, 0 open threads. Ready for your review.` |
| `escalated` | cycle cap or watch timeout hit with findings open | `Cap reached after <n> repair cycles. <k> findings left as needs-human: <ids>.` |
| `blocked` | doctor failed, a fork/permission wall, or the watch could not poll | `Blocked: <SHIP_WATCH_REASON>. No repair attempted.` |
| `settled-externally` | merged or closed while watching | `PR was <merged\|closed> externally. Stopped watching. <k> unresolved trusted findings: <ids>` (or `none open`) |
| `not-watched` | `--no-watch` | `PR opened; watch loop skipped by --no-watch.` |

## The run report

```
Branch: fr07-auth-rotation
Diff:   12 files changed, 247 insertions, 38 deletions

Pre-flight (hands-off):
  ✓ Lint · Typecheck (skipped: receipt by en-build covers full_suite, 6m old)
  ✓ Targeted tests (8 changed files; 14 tests passed; selection: graph)
  ✓ Secret scan (clean)
  ✓ Base: origin/main fetched; 0 behind, 5 ahead; no predicted conflicts
  ✓ Staging: 12 tracked files in scope; 2 unrelated files preserved and excluded
  ✓ plan_completion_checkpoint: completed_and_moved (FR07-auth-rotation → completed/)

Commit: feat(auth): rotate refresh token on every access - U1-U5
Pushed to origin/fr07-auth-rotation.

PR opened: https://github.com/manok4/ensemble/pull/42
Auto-merge: disabled (pass --auto-merge to enable)

Watch:
  doctor: ok · repair cycles used: 1 of 2
  CI: green (7 checks) · Review threads: 0 open

State: clean
PR is green and clean - 7 checks passed, 0 open threads. Ready for your review.
```
