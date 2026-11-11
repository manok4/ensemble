# Running a ship on its configured model

Read at step 2a when it dispatches: `SHIP_MODEL` or `SHIP_EFFORT` is set and
none of the stay-in-session conditions holds. The decisions are D144 and D145:
a cheaper model, at an effort the operator picks, runs the mechanical part of
shipping, including the watch loop's fixes, while the session that called
`/en-ship` keeps its own model and effort.

## Before dispatch

Record three things the fallback below compares against, because tracked edits
and an open PR are ordinary inputs to a ship, not signs that the child ran:
`HEAD` (`git rev-parse HEAD`), a fingerprint of the tracked tree,
`{ git status --porcelain --untracked-files=no; git diff HEAD; git diff --cached; } | git hash-object --stdin`,
which changes when a child edits a file that was already modified, and step 1's
existing-PR result.

## The dispatch

One subagent, given this brief verbatim, followed by the skill name this run
was invoked by with `--in-agent` (`/en-ship --in-agent`, `/ensemble:en-ship
--in-agent` under the plugin, `$en-ship --in-agent` on Codex) and this run's
original arguments. A bare name could reach a differently installed copy:

> Invoke the skill named below with these exact arguments. You have no way to ask the user: anything you would ask ends your turn with the last line `en-ship: needs-input <question>`. Return the run report and its last line unchanged.

Pass each value only when it is set: an effort-only ship omits `model`, so the
child runs on the session's model, and a model-only ship omits the effort. The
configured effort is this skill's explicit instruction to set the parameter.

- **Claude Code:** one Agent call, `subagent_type: general-purpose`, with
  `model: $SHIP_MODEL` and `effort: $SHIP_EFFORT`. Without an effort, a child
  on another model runs at that model's default, not the session's. Claude
  Code before 2.1.292 refuses `effort`, which is a refused dispatch below.
  `CLAUDE_CODE_EFFORT_LEVEL`, when set in the environment, overrides the call.
- **Codex:** one `spawn_agent` call with `model: $SHIP_MODEL`,
  `reasoning_effort: $SHIP_EFFORT` and `fork_turns: "none"`, then wait for it.
  A CLI whose `spawn_agent` takes no `model` cannot place the ship: stay in
  session and print once
  `this Codex CLI's spawn_agent takes no model; shipping on the session model.`
  A CLI whose `spawn_agent` takes no `reasoning_effort` dispatches with the
  model alone and prints once
  `this Codex CLI's spawn_agent takes no reasoning_effort; the ship runs at the session's effort.`
  With only an effort set there is nothing left to place: stay in session and
  print `this Codex CLI's spawn_agent takes no reasoning_effort; shipping in session.`

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
- **The user rejected the dispatch** at a permission prompt. Stop: say the ship
  did not run and name `/en-ship` to run again. A rejection is the user's own
  answer, never a reason to ship in session.
- **The host refused the dispatch, or the reply has no report.** Rerun in
  session, as if `--in-agent` were passed, only when all three still match what
  was recorded:
  - `HEAD`;
  - the tracked-tree fingerprint;
  - the open PR for the branch, from `gh pr list --head <branch> --state open`.

  Otherwise stop and name the new commits, edits or PR, so a rerun never repeats
  work that already landed. This is `/en-conductor`'s fallback rule, compared
  against a snapshot because a ship starts from edits and PRs a stage does not.

## Evidence

Claude Code: a headless Opus session's Agent call carried `model: sonnet` and
the child's turns ran on Sonnet. Codex CLI 0.167.0: a `spawn_agent` child given
`model` and `fork_turns: "none"` recorded that model in its rollout's
`turn_context`, ran `$en-ship --in-agent --no-watch --draft`, pushed to GitHub
and opened a draft PR. Both are in `tests/evals/ledger.md` (2026-11-10). The
Codex check ran under `danger-full-access`. Whether a child under a narrower
sandbox keeps the session's network access is unverified; a sandbox with
network off blocks a push in session too.

Effort (2026-11-11, D145): on Claude Code 2.1.322 an Agent call with
`model: haiku, effort: low` from a Sonnet session ran its turns on
`claude-haiku-5-5`, and the subagent's transcript and meta recorded
`"effort":"low"`. On Codex CLI 0.167.0 the `spawn_agent` schema reads
"Reasoning effort override for the new agent. Omit to inherit the parent
effort", and a child given `gpt-6-luna` and `low` from a `medium` session
recorded `low` in its rollout's `turn_context`. Read a child's effort from
those records, never from its own account.
