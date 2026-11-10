# Running a ship on its configured model

Read at step 2a when it dispatches. `SHIP_MODEL` is set, none of the
stay-in-session conditions holds, and `HOST` is `claude-code`. The decision is
D144: a cheaper model runs the mechanical part of shipping, including the watch
loop's fixes, while the session that called `/en-ship` keeps its own model.

## Before dispatch

Record `HEAD` (`git rev-parse HEAD`). The fallback below compares against it.

## The dispatch

One Agent call, `subagent_type: general-purpose`, with `model: $SHIP_MODEL`.
The prompt is this brief, verbatim, followed by `/en-ship --in-agent` and this
run's original arguments:

> Invoke the skill named below with these exact arguments. You have no way to ask the user: anything you would ask ends your turn with the last line `en-ship: needs-input <question>`. Return the run report and its last line unchanged.

`--in-agent` is what stops the child from dispatching again. Never drop it.

## On return

- **A run report.** Print it and its last line verbatim. That is this run's
  report, and the run ends here.
- **`en-ship: needs-input <question>`.** Ask the user with the host's question
  tool. Then continue this run in session from **Resolve context**, re-reading
  branch, base and existing PR, because the child may have committed, pushed or
  opened one. Keep the original arguments, run as if `--in-agent` were passed
  so it never dispatches again, and carry the user's answer as the decision for
  that question. A run on a branch that already has a PR updates it.
- **A refused Agent call, or a reply with no report.** Rerun in session, as if
  `--in-agent` were passed, only when all three hold:
  - `HEAD` matches the recorded value;
  - `git status --porcelain --untracked-files=no` is empty;
  - `gh pr list --head <branch> --state open` finds nothing.

  Otherwise stop and name the new commits, edits or PR, so a rerun never repeats
  work that already landed. This is `/en-conductor`'s fallback rule.

## Codex

Codex ships in session for now: whether a `spawn_agent` child can load the
skill, run on a given model and push is unverified (EN28 U4). When
`ship_model_codex` resolves non-empty, print once:

`ship_model_codex is set but Codex dispatch is unverified (EN28 U4); shipping on the session model.`
