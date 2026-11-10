# Running a ship on its configured model

Read at step 2a when it dispatches: `SHIP_MODEL` is set and none of the
stay-in-session conditions holds. The decision is
D144: a cheaper model runs the mechanical part of shipping, including the watch
loop's fixes, while the session that called `/en-ship` keeps its own model.

## Before dispatch

Record `HEAD` (`git rev-parse HEAD`). The fallback below compares against it.

## The dispatch

One subagent, given this brief verbatim, followed by `/en-ship --in-agent`
(`$en-ship --in-agent` on Codex) and this run's original arguments:

> Invoke the skill named below with these exact arguments. You have no way to ask the user: anything you would ask ends your turn with the last line `en-ship: needs-input <question>`. Return the run report and its last line unchanged.

- **Claude Code:** one Agent call, `subagent_type: general-purpose`, with
  `model: $SHIP_MODEL`.
- **Codex:** one `spawn_agent` call with `model: $SHIP_MODEL` and
  `fork_turns: "none"`, then wait for it. A CLI whose `spawn_agent` takes no
  `model` cannot place the ship: stay in session and print once
  `this Codex CLI's spawn_agent takes no model; shipping on the session model.`

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
- **A refused dispatch, or a reply with no report.** Rerun in session, as if
  `--in-agent` were passed, only when all three hold:
  - `HEAD` matches the recorded value;
  - `git status --porcelain --untracked-files=no` is empty;
  - `gh pr list --head <branch> --state open` finds nothing.

  Otherwise stop and name the new commits, edits or PR, so a rerun never repeats
  work that already landed. This is `/en-conductor`'s fallback rule.

## Evidence

Claude Code: a headless Opus session's Agent call carried `model: sonnet` and
the child's turns ran on Sonnet. Codex CLI 0.167.0: a `spawn_agent` child given
`model` and `fork_turns: "none"` recorded that model in its rollout's
`turn_context`, loaded `$en-ship`, pushed and reached `gh`. Both are in
`tests/evals/ledger.md` (2026-11-10). A child inherits the session's sandbox,
so a Codex sandbox with network off blocks the push in session and child alike.
