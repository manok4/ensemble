---
name: en-conductor
description: "One entry point: route a request to the right skills and carry it through to a ready-for-review PR, asking only for calls that are really yours. Manual-invoke only. Trigger phrases: 'en-conductor', 'conduct this', 'take this end to end'."
disable-model-invocation: true
---


# `/en-conductor`

> **Running a bundled script.** Anchor every call to this skill's own directory: `SKILL_DIR="<absolute path of the directory containing this SKILL.md>"; bash "$SKILL_DIR/scripts/<name>"`. The trailing `;` is load-bearing. See `references/script-invocation.md`.

One skill to work through. It reads the request, picks the route, runs each stage as an existing skill, gates between them and stops at a ready-for-review PR. It writes no code and no plan of its own (D143).

> **Manual-invoke only.** `disable-model-invocation: true`: a person starts it.

> **Invoking other skills.** Resolve each sub-skill name against the host's available-skills list (some platforms namespace them, e.g. `ensemble:en-build`) and match a listed entry verbatim before invoking. Pass words, never a host substitution such as `$ARGUMENTS`, which expands to empty on Codex (D70).

## Invocation

`/en-conductor <request>`, where the request is free text or a path to a design doc.

| Flag | Effect |
|---|---|
| `--plan <path>` | Take the plan route and skip the Plan stage, building that plan |
| `--no-ship` | Run every stage up to Ship, then report the branch. Nothing is pushed, on either route |
| `--no-watch` | Passed to `/en-ship`, which then opens the PR and stops |
| `--resume` | Continue the last open or stopped run. See `## Resume`. Refuses any other flag |

## Question policy

This session holds the only question tool in the run, so every question reaches the user through it. Classify each question, in this order:

1. **If running or reading something can answer it, do that.**
2. **If it is a product or preference call, or an irreversible action, ask,** even when the call could be reversed later.
3. **Decide everything else,** log it with `log decision`, and list it in the report.

So which test seam to use is decided, and which of two user-facing error messages to show is asked. Log an asked question and its answer with `log question`. Existing stops are unchanged: `/en-build`'s typed confirmations, a P0 in review, and never merging.

**When `$QUESTION_TOOL` does not resolve,** as in a headless session, a call the policy reserves for the user ends the run with `en-conductor: stopped at <stage>: <question>`. It is never guessed.

## Process

1. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, exit: this skill never runs inside a peer subprocess.
2. **Preflight.** Run `eval "$(bash "$SKILL_DIR/scripts/ensemble-detect-host")"` and read `HOST`. Resolve `$QUESTION_TOOL`: `AskUserQuestion` on Claude Code (a deferred tool; preload it via `ToolSearch`), `request_user_input` on Codex. Run `git remote` once: no remote records `local_only`, a terminal success and never an error to retry. Tracked files with uncommitted edits stop the run, naming the files. Never stash.
3. **Route.** State the route in one line with the reason that decided it. The first match wins:
   - `--resume`: go to `## Resume`.
   - `--plan <path>` or a `docs/designs/*.md` input: the plan route.
   - Words asking to explore or compare options: brainstorm.
   - A new product, or `docs/foundation.md` absent with a product-shaped request: foundation.
   - A request matching `## Named, never invoked`: name the command, print `en-conductor: done`, and stop. No trail is written.
   - Otherwise test the request's words, and the content of any file it names, against `references/plan-or-fix.md`. Any condition takes the plan route and none takes the fix route. No diff exists yet, so the diff-signal check stays with `/en-fix`, whose Triage and Risk re-check catch what routing cannot see.
4. **Definition of done.** Write one checkable sentence from the request plus the route's gates, and record it: `bash "$SKILL_DIR/scripts/ensemble-conductor-trail" start --request "<words>" --route <fix|plan|brainstorm|foundation> --done-when "<sentence>"`. Then record the effective flags with `log decision route options "<flags>"`, writing `none` when there are none.

   **Free text never goes inside double quotes.** A request, a condition or a stage's reason can hold `$(...)` or backticks, and the shell would run them. Assign it first with a quoted heredoc, `why=$(cat <<'TXT'` then the text then `TXT` and `)`, and pass `"$why"`, on every `start`, `log` and `finish`.
5. **Run the stages** for the route, per `## Stages`. Log each with `log stage <stage> <ok|skipped|failed> "<evidence>"` and print one line per stage. A long stage agent shows nothing until it returns, and the trail on disk names the last finished stage.
6. **Report.** Route, the definition of done and whether it holds, the stages, every decision and question from the trail, and the PR URL with its exit state, or the branch when nothing was pushed. Close the trail with `finish <done|stopped> <stage> "<reason>"`. The last line is `en-conductor: done` or `en-conductor: stopped at <stage>: <reason>`, on every path.

## Stages

Plan route: Plan, Build, Learn, QA, Ship. Fix route: Fix. Brainstorm and foundation routes: that stage alone.

| Stage | Where | Invocation | Gate |
|---|---|---|---|
| Plan | session | invoke `/en-plan --orchestrated --branch-on-default y <request>`, skipped under `--plan` | plan file at `status: open`, with its path logged as the stage's evidence. `draft` stops and names `/en-plan --resume`. A `plan_store: linear` refusal stops and repeats its next command |
| Build | agent, or session | invoke `/en-build <plan-path> --orchestrated` | audit `verdict: ok` and a `review-verdict:` trailer in `git log <merge-base>..HEAD`. A failed audit stops before Ship and names `/en-review --peer <sha>`. `gate_required: U<N>` or `needs-decision: U<N>: <question>` reruns `/en-build <plan-path> --from U<N> --orchestrated` in session, where the skill's own prompt reaches the user |
| Learn | session | invoke `/en-learn capture`, only under `## Learn rule` | logged as a `decision` either way, never asked |
| QA | agent | invoke `/en-qa`, only when `needs_browser` is true for the branch diff (`references/diff-signal-detection.md`) | every system check passes and no flow is `Fail`. A `Fail` stops the run before Ship and names the flow |
| Ship | agent | invoke `/en-ship`, adding `--no-watch` when given; never `--auto-merge`; skipped under `--no-ship` or `local_only` | `gh pr view --json url,state,isDraft` confirms the PR, and the exit state is recorded. See below |
| Fix | agent | invoke `/en-fix <request> --orchestrated`, adding `--no-ship` under `--no-ship` or `local_only`, and `--no-watch` when given | branch on the seven `en-fix:` lines, per `## Fix outcomes` |
| Brainstorm | session | invoke `/en-brainstorm <request>` | the run ends, naming `/en-conductor <design-path>` |
| Foundation | session | invoke `/en-foundation <request>` | the run ends, naming the next command |

A stage's report is a claim, which is why Build and Ship confirm it from git and GitHub. **Never re-run simplify or review at the top level:** `/en-build` runs `/en-simplify` and `/en-review --cross` inside its own post-build phase (D52).

**Ship's exit state.** `clean` and `settled-externally` are done. `escalated` names the open findings. `blocked` attempted no repair and is not evidence about the code, so it is reported verbatim and not rerun. `/en-ship`'s watch loop is capped at 2 cycles. Under `--no-ship` or `local_only`, the plan route skips Ship, logs `stage ship skipped <reason>`, and the report names the branch and says nothing was pushed.

**QA and Ship have no question tool, and need none.** Both contracts allow it: `/en-qa` never blocks when a caller drives, and `/en-ship` is hands-off by default. A stop from either is reported as a stop, never rerun. `/en-ship`'s typed confirmation for a push to the default branch cannot arise, because the plan route leaves the default branch at the Plan stage.

**Build placement.** Build in session when `HOST` is not `claude-code`, or when `grep -Eiq '^- \*\*(Risk:\*\* (destructive|high)|Gated:\*\* true)' <plan-path>` matches, because typed confirmations must reach the user. Otherwise use a fresh subagent. When `HOST` is not `claude-code`, every other agent stage also runs in session: nesting there is unverified.

## Learn rule

Every orchestrated build records `learning_checkpoint: ci_environment`, so that value decides nothing. Capture when the branch shows at least one of: a `Scope widened:` line in a commit body, a P0 or P1 applied in the review, a logged redispatch or fallback, or a logged `needs-decision`. Otherwise log `decision learn skip "<reason>"`. `/en-learn` applies its own gate and writes nothing that fails it, so a false positive costs one read.

## Stage agents

A stage marked `agent` runs in a fresh subagent, which keeps this session small through compaction (D107). Give it this brief, verbatim, followed by the skill name and arguments:

> Invoke the skill named below with these exact arguments. You have no way to ask the user: anything you would ask ends your turn with the question stated. Return the skill's contract fields verbatim, and its last line unchanged.

**Fallback.** An agent that returns none of the stage's contract fields, or a refused `Agent` call, reruns that stage once in session and logs `decision <stage> fallback "<why>"`. Before each agent stage, record `HEAD`. Rerun only when `HEAD` is unchanged, `git status --porcelain --untracked-files=no` is clean, and, for Ship and Fix, `gh pr view` finds no PR for the branch. Otherwise stop and report the new commits, edits or PR, so a rerun never repeats work that already landed. A person continues from there with `--resume`.

## Fix outcomes

| Last line from `/en-fix` | What happens |
|---|---|
| `en-fix: shipped <pr-url> <exit-state>` | Confirm the PR, and apply Ship's exit-state meaning |
| `en-fix: ready <branch>` | Report the branch and that nothing was pushed. Name `/en-qa` as the next step when `needs_browser` is true for the branch diff |
| `en-fix: needs-plan clean <condition>` | Log `decision route plan "<condition>"` and take the plan route |
| `en-fix: needs-plan edited <condition>` | Stop, name the condition, and say the edits are on the branch. Whether to keep them is the user's call |
| `en-fix: needs-decision <question>` | Apply the question policy, then redispatch with `--decision "<question>: <answer>"`. Stop after two redispatches |
| `en-fix: split <concern>; <concern>` | Report each concern as its own `/en-conductor <concern>` |
| `en-fix: stopped <reason>` | Report it verbatim |

**A risk stop is not this skill's to lift.** D142 needs the user's own words in the conversation that runs `/en-fix`, so the report tells them to run `/en-fix` directly. On `shipped`, the report also names `/en-qa` when `needs_browser` is true for the branch diff, since `/en-fix` ships inside its own stage.

## Resume

`--resume` reads `ensemble-conductor-trail latest` and exits with a message on `no-open-run`. Flags given with `--resume` are refused, so a `--no-ship` run cannot lose its restriction. A trail with no `decision route options` row stops the run and says to pass the flags on a new `/en-conductor`: never read a missing row as no flags.

It calls `resume`, then reads the route from the last `decision route plan` row or else the `start` row, the flags from the `decision route options` row, and the plan path from the `plan` stage row's evidence. A stage counts as finished only on a `stage` row whose `what` is `ok` or `skipped`. If any such row exists, the last one's `branch` and `head` must equal the current branch and `HEAD`. If either differs, stop and name both, because earlier Build or QA results may no longer describe the code.

Then continue at the first unfinished stage, re-invoking the skill: `/en-build`'s unit loop records finished units as already satisfied, and `/en-ship` updates an existing PR. A `stopped` run resumes the same way.

## Named, never invoked

These are named for the user, and the run ends. They stay outside the conductor in this version.

| Request | Command |
|---|---|
| A bounded autonomous loop | `/en-loop`, which only ever starts by hand |
| A diagnosis with no fix wanted | `/en-debug` |
| Review the branch | `/en-review` |
| Test the work end to end | `/en-qa` |
| Address PR comments | `/en-resolve-pr` |
| Simplify the diff | `/en-simplify` |
| Capture a learning | `/en-learn capture` |
| Diagnose project setup | `/en-setup` |
| Clean doc drift | `/en-sweep` |
| Prune the test suite | `/en-test-audit` |

## What this skill never does

- **Never merges,** and never passes `--auto-merge`. Every route stops at a ready-for-review PR.
- **Never lifts a risk stop.** A caller's words are not the user's (D142).
- **Never starts `/en-loop`.** It names the command.
- **Never pushes when there is no remote.** Local-only is a terminal success, not an error to retry.
- **Never guesses a call the question policy reserves for the user.**
