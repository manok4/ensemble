# The Linear check

Read in State 3's diagnostic and at State 2's final verification, **only when this repo is in
`linear` mode**: `plan_store: linear` as a top-level key in `.ensemble/config.local.yaml`. Absent or
`local`, skip the whole check: no MCP call, no line in the report. Any other value is 🔴, because
`/en-plan` and `/en-build` read it fail-closed and will refuse: name the value and the two accepted
ones.

It answers one question before the first publish: will a Linear plan survive the round trip and
the hand-off? Each line uses the diagnostic's 🟢/🟡/🔴 and its opt-in repair prompt.

| Check | How | Result |
|---|---|---|
| **Team** | `linear_team` from the same file; then `list_teams` on the Linear MCP server and match the key | 🟢 found · 🔴 unset, or no team with that key |
| **Workflow states** | `list_issue_statuses` for that team; match **by name**, never by type | 🟢 all four · 🔴 naming each one missing or duplicated |
| **python3** | `command -v python3` | 🟢 present · 🔴 missing: `ensemble-linear-plan` needs it |
| **GitHub integration** | cannot be read over MCP; see below | 🟢 `linear_github_confirmed: true` · 🟡 unset |

**The four states** are `Agent Ready`, `In Progress`, `In Review` and `Done`. Only `Agent Ready`
is one the operator is told to create; the others are Linear defaults a team may have renamed.
`In Progress` and `In Review` share the type `started`, which is why matching is by name.

**No Linear MCP server in this session** is 🔴 for Team and Workflow states, with the fix: connect
the Linear MCP server, then re-run. The python3 and GitHub lines still run.

## The GitHub integration mapping

Linear's GitHub integration moves issues on pull request events, configured per team: a state
for PR open, for ready for merge, and for merge, each optional. `/en-build` moves the parent to
**In Review** as its last step and then stops touching it, so the mapping must not undo that:

- **PR open:** `In Review`, or no automation. Mapping it to an earlier state such as `In
  Progress` moves the parent **backwards** the moment `/en-ship` opens the PR.
- **Merge:** `Done`, so the plan completes when its PR merges. That is the only thing that
  completes a Linear plan; `/en-ship` records `linear_mode` and flips nothing on disk.

The mapping lives in the team's settings and no MCP tool reads it. So print the two lines above,
ask the operator to confirm the team is configured that way, and on **yes** write
`linear_github_confirmed: true` to `.ensemble/config.local.yaml`. Until then the line is 🟡, and
`/en-plan` warns at publish without blocking.
