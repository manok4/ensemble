# Failure protocol (`/en-build`)

One row per failure the build can hit, and what it does about each. `SKILL.md`
keeps the five met mid-build; this file is the whole table and is
read when something fails.

Every row that stops shares one rule: a failure surfaces, it never auto-reverts, auto-commits
or auto-stashes, and the user decides what happens next.

| Failure | Behavior |
|---|---|
| Plan has unmet dependency (`Depends: U7` but U7 not present) | Stop; surface; suggest plan revision |
| Unit needs files outside its `Files` list | **Widen without asking when the unit's own Goal cannot be met without them.** Make the change, stage the added files with the unit, and record each one as a `Scope widened: <path>, <why>` line in the unit's commit body, repeated as a `Note:` in the progress report. The record is the point: the `Files` list is what the plan was reviewed against, and an unrecorded widening stays invisible until step 10 reads a diff nobody scoped. The plan file is not edited, so its hash stays the baseline. **Stop and ask (split into a new unit, or abort) only when** the extra work is a deliverable of its own that the Goal does not need, or it is work 8b would gate (a migration, a destructive data change, production state). Widening never carries gated or destructive work past 9a. |
| Unit's `Approach` is too thin to implement | Stop and ask. Pre-flight checks the field is present, not that it is sufficient, and a guessed interpretation of a thin unit is the expensive kind of wrong: it passes tests written to match the guess. |
| A `risk: destructive` unit precedes a non-destructive one | Refuse and name the units. `/en-plan`'s `unit.destructive-order` lint catches this at plan time; reaching the build means the plan was written or edited past it. |
| Plan in `status: draft` with unresolved `peer_review_resolutions:` | Refuse build; list unresolved findings; suggest `/en-plan --resume`. |
| Plan in `status: draft + revise` with all resolutions cleared | Offer finalize-and-build single prompt (recovery flow). On y, run `/en-plan` finalize loop, flip to `open`, commit, then proceed. |
| Plan untracked in git but `status: open` and verdict cleared | Offer auto-commit single prompt; on y, commit and proceed. |
| Plan-hash mismatch at a checkpoint | Refuse to advance; surface that immutable plan-input fields changed during build; ask user to re-baseline (`--re-baseline`) or abort. |
| Unit verification fails (9d) | Fix and re-run. **After two failed attempts on the same unit, stop** — show the test output and ask: retry, skip the unit, or abort. Guessing a third time is how a unit gets "fixed" by weakening its test. |
| A 9f checkpoint fails (targeted tests / lint / typecheck) | Stop. Do not enter the unit it was guarding. Surface failing tests; offer investigate / `--commit-wip` / abort. |
| Branch-level review verdict = `reject` | Pause and surface to the user before the post-build commit; never proceed to the audit as if approved |
| Peer subprocess attempts to modify files (D30 violation) | Detect via git status; revert; do not trust this round of findings; log violation |
| `git restore` fails on a revert | Surface; abort the build; do not leave the working tree corrupted |
| User Ctrl-C mid-unit | **Stop cleanly. No signal-time git operations.** Surface: current branch, current unit (with completion state), dirty files, last successful commit. Provide explicit resume instructions (`/en-build --from U<N>`). User invokes `/en-build --commit-wip` separately if a WIP commit is desired. |
| User asks to abort mid-unit | **Stop cleanly. Surface state and resume instructions.** Do NOT auto-commit, auto-stash, or auto-create a WIP branch — `abort` is a request to stop, not to preserve partial progress. WIP capture is opt-in via a separate `/en-build --commit-wip` invocation; the user must explicitly request it. |
