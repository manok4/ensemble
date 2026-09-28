---
name: en-fix
description: "Take one small bug fix or improvement from request to PR without a plan: /en-debug diagnoses bugs, a test-first change, /en-review --lite, then /en-ship. Manual-invoke only. Trigger phrases: 'en-fix', 'quick fix', 'fix this bug', 'small improvement'."
disable-model-invocation: true
---


# `/en-fix`

> **Running a bundled script.** Anchor every call to this skill's own directory: `SKILL_DIR="<absolute path of the directory containing this SKILL.md>"; bash "$SKILL_DIR/scripts/<name>"`. The trailing `;` is load-bearing. See `references/script-invocation.md`.

One small change, a bug fix or an improvement, from request to a reviewed PR with no plan file. Anything bigger belongs to `/en-plan` and `/en-build`, and this skill hands the work back to `/en-plan` the moment it stops being small.

> **Manual-invoke only.** `disable-model-invocation: true`: it pushes and opens a PR, so it runs only when a person types `/en-fix`. Other skills suggest it to the user and never invoke it, which is why it carries no `CONTRACT.md`.

> **The only writer of small changes (D124).** `/en-debug` diagnoses and never edits; this skill makes the change. A bug restores behaviour everyone agrees is correct, so `/en-debug` diagnoses it first. An improvement changes behaviour that works as designed; there is nothing to diagnose, and the user's request is the decision D62 says `/en-debug` must not make on its own.

> **Invoking other skills.** Resolve each sub-skill name against the host's available-skills list (some platforms namespace them, e.g. `ensemble:en-review`) and match a listed entry verbatim before invoking. Pass words, never a host substitution such as `$ARGUMENTS`, which expands to empty on Codex (D70).

## Invocation

`/en-fix <request>`. The request is one of:

| Input | Intake |
|---|---|
| Free text, or nothing | The words, or the problem the current conversation settled |
| `<file>:<line>` | Read that location and the behaviour around it |
| A Linear identifier (`ABC-123`) | Load the Linear MCP tools; `get_issue` for the title, description and labels, and `list_comments` for the thread |
| `TD<N>` | That entry under `## Open` in `docs/plans/tech-debt-tracker.md` |

| Flag | Effect |
|---|---|
| `--no-watch` | Passed to `/en-ship`, which then opens the PR and stops |
| `--auto-merge` | Passed to `/en-ship` only when given here; off by default |

## Process

1. **Preflight.** If `ENSEMBLE_PEER_REVIEW=true`, stop: this skill never runs inside a peer subprocess. Resolve `$QUESTION_TOOL`: `AskUserQuestion` on Claude Code (a deferred tool; preload it via `ToolSearch`), `request_user_input` on Codex. Read the Test, Lint and Typecheck commands from `AGENTS.md`.
2. **Intake.** Turn the request into a problem statement: the user's words plus whatever an identifier resolved to (the issue's title, description and comments, or the tracker entry). An issue or `TD<N>` that does not exist stops the run and names it.
3. **Triage.** Make three calls and state them to the user in one line before any work.
   - **Bug or improvement.** The user's explicit word ("this is an improvement") beats a Linear `Bug` label, which beats your own call from the description.
   - **Is it small?** One concern that fits in one commit, with no risk surface: authentication, payments, migrations, external contracts, or any risk signal in `references/diff-signal-detection.md`. There is no line or file count; a rename across eight files is still small. If it fails, say which part failed, suggest `/en-plan`, and stop.
   - **Is it ambiguous?** More than one reasonable reading of what should change. Mark it; the Understand step confirms an ambiguous improvement before editing.
4. **Branch.** Refuse to start while tracked files carry uncommitted edits: `/en-ship` stages every tracked modification, so they would ship with this change. Ask the user to commit or stash them. On the default branch, create a branch: `<IDENT>-<slug>` for a Linear issue (the `/en-build` pattern), `TD<N>-<slug>` for a tracker entry, `fix-<slug>` otherwise. Nothing reads a branch name from Linear. Then **record the pre-fix scope** before touching anything: `HEAD` and the untracked files already present. Keep a running list of fix-owned files; it is the only way to tell your new files from the user's afterwards.
5. **Understand the change.**
   - **Bug:** invoke `/en-debug` with the user's words plus the resolved issue or tracker text, per its contract. It asks nothing and returns a `verdict`. Only `convergent` proceeds. On `divergent`, `design-problem` or `unresolved`, show the diagnosis, make no edit, and stop; on `design-problem`, also suggest `/en-brainstorm`.
   - **Improvement:** no `/en-debug`, because nothing is broken to trace. Print a three-line spec: the change, the test that proves it, and the files. Ask for confirmation only when triage marked the request ambiguous. If the work turns up behaviour that is actually broken, invoke `/en-debug` on it then, under the same rules.
6. **Change, test-first.** Write a failing test that captures the bug or the new behaviour, and confirm it fails for the right reason. Make the minimal change, with no drive-by refactors, and confirm the test passes. Run the targeted tests, lint and typecheck, then self-review the diff.
   - **A failing test may be asserting behaviour that is correct.** Before changing an existing assertion, establish that it encodes the bug and not a decision. When that is unclear, stop and ask.
   - **On a failed attempt**, explicitly invalidate the current theory before forming the next. No retry variants.
   - **Three failed attempts is a signal about the design, not a reason for a fourth.** Stop, say so, and suggest `/en-plan`.
7. **Risk re-check.** Run Triage's size check again on the actual diff. If it trips, stop with the change uncommitted, name the surface, and suggest `/en-plan`.
8. **Commit.** One Conventional Commit of the fix-owned files only, never `git add -A`. A Linear request puts `Fixes <IDENT>` in the body so Linear's GitHub integration links and closes the issue; this skill writes no Linear state or comments. A `TD<N>` request moves that entry from `## Open` to `## Resolved` in the same commit.
9. **Review.** Invoke `/en-review --lite --mode headless` with no target: the branch diff against the default branch is the only target its post-review check writes a receipt for. Headless mode applies `safe_auto` findings itself and leaves them uncommitted. **At most two rounds.**
   - **Round 1.** A P0 stops the run here. If P1 findings are open, apply them, and apply any `gated_auto` fix you agree with; never a `conflicting` finding, and a `manual` one that encodes a decision goes to the user instead. If anything was applied, by the review or by you, commit every review edit as `fix(review): <subject>` and run round 2. Otherwise go to the Receipt gate.
   - **Round 2.** Apply nothing yourself. A P0, or a P0 or P1 still open, stops the run here: report the findings and suggest `/en-plan`, since two blocked rounds mean the change was not small. Report any P2 or P3 findings left; `/en-ship` commits the round's `safe_auto` edits.
   - Whenever the review's edits changed the diff, run the Risk re-check again on it.
10. **Receipt gate.** `bash "$SKILL_DIR/scripts/ensemble-verification-receipt" verify --requires lint,typecheck,targeted_tests --json`, dropping `typecheck` when `AGENTS.md` declares no Typecheck command. This skill writes no receipt, so one valid for the current tree was written after the last edit, by `/en-review`'s post-review check. A non-zero exit stops the run: do not invoke `/en-ship`. Nothing may edit or commit between this gate and the ship.
11. **Ship.** Invoke `/en-ship`, adding `--no-watch` or `--auto-merge` only when the user gave them. The Branch step started from a clean tracked tree, so its unscoped staging picks up only this change. `/en-ship` can stop on its own preflight; report where it stopped rather than assuming a PR exists.

## Stops and resuming

Every stop leaves the branch as it is and names the next command. A run that dies after the Commit step resumes with `/en-review --lite` or `/en-ship` on the same branch, never a fresh `/en-fix`, which would re-triage work that is already committed.

## What this skill never does

- **Never plans.** No plan file and no U-IDs. Work that outgrows the size check goes to `/en-plan`.
- **Never edits a risk surface.** Triage, the Risk re-check and the Review each stop the run on one.
- **Never ships unreviewed work.** The Receipt gate is the check, not this sentence.
- **Never auto-merges** unless `--auto-merge` was passed.
- **Never writes Linear state or comments.**
