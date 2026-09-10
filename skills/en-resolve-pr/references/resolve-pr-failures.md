# `/en-resolve-pr` failure protocol

Read when a run hits one of these. Each row is the behaviour, not a suggestion,
and they share one rule: the failure surfaces and the run hands back. Nothing
here rebases, force-pushes, or resolves a conflict on the user's behalf, because
those are excluded actions and a failure is not authority to take one.

| Failure | Behavior |
|---|---|
| `gh` not authenticated | Surface; suggest `gh auth login`; exit |
| `get-pr-comments` script fails (rate limit, network) | Retry once with exponential backoff; if still failing, surface and exit (do not partially process) |
| Combined validation red on changed files, can't fix in one pass | Stage changes, do **not** commit; surface as `needs-human` with the test output |
| `git push` fails (e.g., upstream needs rebase) | Stop; surface the divergence with ahead/behind counts; hand back. **Never rebase or force-push from here** — that is an excluded action, and this skill may narrow its scope but not widen it. |
| `merge_state_status` is `DIRTY` (conflicts) | Report it and hand back with the conflicting paths named. Resolution is the caller's or the user's call, not a side effect of addressing comments. When it is resolved: preserve both intents where they are compatible; where they are not, take the one matching the change's stated goal and note the trade-off. **Do not invent new behaviour to make a conflict go away**, and never `--abort` in place of resolving. |
| Reply API failure on a single thread | Continue with the rest; surface failed-reply list at the end |
| Resolve API failure | Same — continue, surface |
| Reviewer left a thread with no comment body | Skip the thread; surface a one-line warning |
| Two cycles already done and threads remain | Do **not** start a third cycle — escalate as recurring pattern (see step 11) |
| `--enable-auto-merge` requested but repo doesn't allow it | Surface "Repo does not allow auto-merge. Enable in Settings → General → 'Allow auto-merge'". Do not retry. |
| `gh pr merge --auto` fails (branch protection rejects merge method, or PR has merge conflicts) | Surface the gh error verbatim; leave the rest of the run intact (replies/resolutions/commits already landed). User resolves manually. |
| `check-merge-status` fails (rate limit, gh auth) | Surface a one-line warning in the summary; skip the merge-readiness section; rest of the run unaffected. |
