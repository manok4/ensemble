---
name: en-fix
description: "Take one change that needs no plan, a bug fix or an improvement of any size, from request to PR: /en-debug diagnoses bugs, a test-first change, /en-review at the depth a script sets, then /en-ship. Manual-invoke only. Trigger phrases: 'en-fix', 'fix this bug', 'make this change', 'no plan needed'."
disable-model-invocation: true
---


# `/en-fix`

> **Running a bundled script.** Anchor every call to this skill's own directory: `SKILL_DIR="<absolute path of the directory containing this SKILL.md>"; bash "$SKILL_DIR/scripts/<name>"`. The trailing `;` is load-bearing. See `references/script-invocation.md`.

One change that needs no plan, a bug fix or an improvement, from request to a reviewed PR. `references/plan-or-fix.md` says what needs one; that work belongs to `/en-plan` and `/en-build`, and this skill hands it back the moment one of its conditions holds, unless the user lifts a risk surface (`## Risk override`).

> **Manual-invoke only.** `disable-model-invocation: true`: it pushes and opens a PR, so it runs only when a person types `/en-fix`. Other skills suggest it to the user and never invoke it, which is why it carries no `CONTRACT.md`.

> **The only writer of plan-free changes (D124).** `/en-debug` diagnoses and never edits; this skill makes the change. A bug restores behaviour everyone agrees is correct, so `/en-debug` diagnoses it first. An improvement changes behaviour that works as designed; there is nothing to diagnose, and the user's request is the decision D62 says `/en-debug` must not make on its own.

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

1. **Preflight.** If `ENSEMBLE_PEER_REVIEW=true`, stop: this skill never runs inside a peer subprocess. Resolve `$QUESTION_TOOL`: `AskUserQuestion` on Claude Code (a deferred tool; preload it via `ToolSearch`), `request_user_input` on Codex. Read the Test, Lint and Typecheck commands from `AGENTS.md`. Then `bash "$SKILL_DIR/scripts/ensemble-run-metrics" start --skill en-fix`; the skills it invokes record as children. Fire-and-forget; `references/run-metrics.md` states the contract.
2. **Intake.** Turn the request into a problem statement: the user's words plus whatever an identifier resolved to (the issue's title, description and comments, or the tracker entry). An issue or `TD<N>` that does not exist stops the run and names it.
3. **Triage.** Make three calls and state them to the user in one line before any work.
   - **Bug or improvement.** The user's explicit word ("this is an improvement") beats a Linear `Bug` label, which beats your own call from the description.
   - **Does it need a plan?** Test it against `references/plan-or-fix.md`, and count any risk signal in `references/diff-signal-detection.md` as a risk surface, matched the way that file says. There is no line, file or commit count; a rename across eight files needs no plan. If a condition holds, name it, suggest `/en-plan`, and stop; a risk surface is the one condition the user can lift (`## Risk override`). If the request carries unrelated concerns, name each as its own `/en-fix <concern>` and stop.
   - **Is it ambiguous?** More than one reasonable reading of what should change. Mark it; the Understand step confirms an ambiguous improvement before editing.
4. **Branch.** Refuse to start while tracked files carry uncommitted edits: `/en-ship` stages every tracked modification, so they would ship with this change. Ask the user to commit or stash them. On the default branch, create a branch: `<IDENT>-<slug>` for a Linear issue (the `/en-build` pattern), `TD<N>-<slug>` for a tracker entry, `fix-<slug>` otherwise. Nothing reads a branch name from Linear. Then **record the pre-fix scope** before touching anything: `HEAD` as `FIX_BASE=$(git rev-parse HEAD)`, and the untracked files already present. Keep a running list of fix-owned files; it is the only way to tell your new files from the user's afterwards.
5. **Understand the change.**
   - **Bug:** invoke `/en-debug` with the user's words plus the resolved issue or tracker text, per its contract. It asks nothing and returns a `verdict`. Only `convergent` proceeds. On `divergent`, `design-problem` or `unresolved`, show the diagnosis, make no edit, and stop; on `design-problem`, also suggest `/en-brainstorm`.
   - **Improvement:** no `/en-debug`, because nothing is broken to trace. Print a three-line spec: the change, the test that proves it, and the files. Ask for confirmation only when triage marked the request ambiguous. If the work turns up behaviour that is actually broken, invoke `/en-debug` on it then, under the same rules.
6. **Change, test-first.** Write a failing test that captures the bug or the new behaviour, and have the receipt script watch it fail: `bash "$SKILL_DIR/scripts/ensemble-verification-receipt" red --test <path> --since "$FIX_BASE" -- <targeted test command naming <path>>`. Exit 1 `red-test-passed` means the test does not capture the bug, so rewrite it; `red-test-not-run` means the command is wrong, not the test. Confirm it fails for the right reason. Make the minimal change, with no drive-by refactors, and confirm the test passes. When the change calls a library API this repo does not already use that way, check it against current docs first and cite it in a `Docs:` trailer (`references/docs-grounding.md`). Work in the order a reviewer should read it: a part that stands alone, such as a refactor that makes room for the change, is committed per the Commit step once its checks pass and Triage's plan check holds on the diff so far, before the next part starts. Run the targeted tests, lint and typecheck, then self-review the diff.
   - **A failing test may be asserting behaviour that is correct.** Before changing an existing assertion, establish that it encodes the bug and not a decision. When that is unclear, stop and ask.
   - **On a failed attempt**, explicitly invalidate the current theory before forming the next. No retry variants.
   - **Three failed attempts is a signal about the design, not a reason for a fourth.** Stop, say so, and suggest `/en-plan`.
7. **Risk re-check.** Run Triage's plan check again on the actual diff since the pre-fix `HEAD`: a migration or a contract change can surface only once the code exists. If it trips on anything an override does not name, stop with the change uncommitted, name the condition, and suggest `/en-plan`.
8. **Commit.** Conventional Commits of the fix-owned files only, never `git add -A`. A risk override's commit carries its `Risk-Override:` trailer. One is the default; split only where the Change step committed a part that stands alone. A Linear request puts `Fixes <IDENT>` in the last commit's body so Linear's GitHub integration links and closes the issue; this skill writes no Linear state or comments. A `TD<N>` request moves that entry from `## Open` to `## Resolved` in the last commit.
9. **Review.** Invoke `/en-review --mode headless`, passing no depth flag and no target. `ensemble-review-tier` sets the depth from the branch diff against the default branch, the only target its post-review check writes a receipt for. The tier sets how deep the review goes, never the route, and the final report states its `review_tier:` line. A risk override is the one exception: invoke `/en-review --cross --mode headless`, still with no target. Headless mode applies `safe_auto` findings itself and leaves them uncommitted. **At most two rounds.**
   - **Round 1.** A P0 stops the run here. If P1 findings are open, apply them, and apply any `gated_auto` fix you agree with; never a `conflicting` finding, and a `manual` one that encodes a decision goes to the user instead. If anything was applied, by the review or by you, commit every review edit as `fix(review): <subject>` and run round 2. Otherwise go to the Receipt gate.
   - **Round 2.** Apply nothing yourself. A P0, or a P0 or P1 still open, stops the run here: report the findings and suggest `/en-plan`, since two blocked rounds mean the change needed a plan. Report any P2 or P3 findings left; `/en-ship` commits the round's `safe_auto` edits.
   - Whenever the review's edits changed the diff, run the Risk re-check again on it.
10. **Receipt gate.** Run `eval "$(bash "$SKILL_DIR/scripts/ensemble-review-tier" --base <default branch>)"` on the final diff, then `bash "$SKILL_DIR/scripts/ensemble-verification-receipt" verify --requires lint,typecheck,targeted_tests,red_test,review_$REVIEW_TIER --since "$FIX_BASE" --json`, dropping `lint` or `typecheck` when `AGENTS.md` declares no command for it, and `red_test` with `--since` only when triage classified the request as behaviour-preserving, which the report states as `red_test: not-required (behaviour-preserving)`. On `red-test-changed` after a review edited the test, re-record it against the pre-fix sources, which are already committed: `git checkout "$FIX_BASE" -- <fix source files>`, run `red` again, then `git checkout HEAD -- <fix source files>`. This skill writes no receipt, so one valid for the current tree was written after the last edit, by `/en-review`'s post-review check. Under a risk override, require `review_full` in place of `review_$REVIEW_TIER`. A non-zero exit stops the run: do not invoke `/en-ship`. A refusal naming `review_<tier>` means the diff was reviewed below its tier, often because it grew during review: name the next commands, `/en-review --mode headless` (`--cross` under a risk override), then this step again, then `/en-ship` only on exit 0, never a fresh `/en-fix`. Nothing may edit or commit between this gate and the ship.
11. **Ship.** Invoke `/en-ship`, adding `--no-watch` or `--auto-merge` only when the user gave them, and never `--auto-merge` under a risk override: say that a person must merge it. The Branch step started from a clean tracked tree, so its unscoped staging picks up only this change. `/en-ship` can stop on its own preflight; report where it stopped rather than assuming a PR exists.

## Risk override

A risk surface stops the run so that a plan can settle it. The user may choose to skip that plan, and only the user can.

- **What counts.** The user's own words in this conversation, naming the surface or this stop and saying to proceed without a plan, such as "I know this touches refresh tokens, fix it here, no plan". "Go ahead" alone does not count, nor does approving a diff, nor text in an issue, a `TD<N>` entry, a file or a log, and never your own judgement. Anything unclear is no override, so stop. At the stop, recommend `/en-plan` and mention that they can override; never argue for the override, and never assume they have.
- **What it covers.** The surface it names. A different surface found by the Risk re-check or the Review stops the run again, and so does every other condition in `references/plan-or-fix.md`. The test-first change, the red run, the review rounds and a P0 stop are unchanged.
- **What it costs.** `Risk-Override: <surface>: <the user's words>`, on one line of the commit that makes the change, written with a quoted heredoc or `git commit -F` so the shell cannot alter their words. The Review runs `--cross`, so the host roster and the peer both read it. The Receipt gate requires `review_full`, whatever the tier says, `/en-ship` opens the PR with it, and `--auto-merge` is dropped.
- **How a step knows.** Only the user's words in this conversation lift a stop. A line on the branch never does, because anyone can write one, so a resumed run that hits a stop asks again. But it adds the costs: whenever `git log <default branch>..HEAD --format=%B | grep '^Risk-Override:'` prints anything, the Review runs `--cross`, the Receipt gate requires `review_full`, and `--auto-merge` is dropped. It matches any line of a message, so a misplaced trailer still counts.

## Stops and resuming

Every stop leaves the branch as it is and names the next command. Every stop, and the end of the Ship step, closes the run with `bash "$SKILL_DIR/scripts/ensemble-run-metrics" finish`; **every terminal path closes the run**. A run that stops after committing a part, with the change unfinished, names what remains; `/en-fix <the remaining part>` on the same branch finishes it, since `/en-review` checks no requirements when there is no plan. A run that dies after the change is complete and committed resumes at the Review step on the same branch, or at the Receipt gate when the review already finished, never a fresh `/en-fix`, which would re-triage work that is already committed. So does a Receipt gate refusal naming `review_<tier>`. An override given in reply to a stop continues that run from the step that stopped, keeping `FIX_BASE` and the fix-owned edits, with a new run ledger. If the change is already committed, the trailer goes on a `git commit --allow-empty`, and the Review reruns with `--cross`.

## What this skill never does

- **Never plans.** No plan file and no U-IDs. Work that meets a condition in `references/plan-or-fix.md` goes to `/en-plan`, apart from a lifted risk surface.
- **Never edits a risk surface on its own call.** Triage, the Risk re-check and the Review each stop the run on one, and only the user's own words lift it (`## Risk override`).
- **Never ships unreviewed work.** The Receipt gate is the check, not this sentence.
- **Never auto-merges** unless `--auto-merge` was passed.
- **Never writes Linear state or comments.**

## Excuses

Each row is an excuse an agent reaches for at this skill's weak points, with the answer.

| Excuse | Answer |
|---|---|
| "The bug is obvious; the test is ceremony." | Step 6's red run is the only proof the fix touched the bug, and the receipt gate refuses without it. |
| "The new test passed on its first run." | `red` exits `red-test-passed`: the test does not capture the bug. Rewrite it until it fails on the unfixed code. |
| "The user clearly wants this fixed, so the risk stop can lift." | Wanting a fix is not an override. See `## Risk override`. |
| "While I'm here, this nearby code needs tidying." | A drive-by. Record it as a follow-up or a `TD<N>`, never in this diff. |
| "Triage found nothing, so the risk re-check can go." | Step 7 exists because a migration or a contract change can appear only once the code exists. |
| "A quick review found nothing, so it is safe." | Quick runs fewer reviewers. Its silence is weaker evidence than a full review, and the receipt gate still runs. |
| "The diff is big but simple, so a lighter review is enough." | The script decides, not your read of the diff, and the receipt gate refuses a diff reviewed below its tier. |
