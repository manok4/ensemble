# Fable 5.1 prompting guide: audit of the Ensemble skills

Date: 2026-09-05
Source: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1
Branch reviewed: `en-brainstorm-efficiency-pass` at `ccdde62`

## What landed

The "apply now" items below shipped in the PR that carries this file, as D95 through D99: the `xhigh` effort tier, en-setup's single opt-in round, en-foundation's frontier rounds and disk ledger, the run ledgers for en-build, en-qa, en-flow and en-resolve-pr, the autonomous framing in the en-loop worker prompt and the en-sweep CI wrapper, and the batching, search, edit, long-output and progress lines in the remaining skills. Still open, by design: the peer ladder rung re-measurement, the agent tier comparison, and en-sweep at medium effort, each of which waits on an eval.

## Scope and method

This is a static audit. Each `skills/en-*/SKILL.md`, its bundled `agents/*.md`, the peer briefs, the peer prompt builder and the peer invoke helper were read against the sixteen sections of the guide. "Current standing" below means how well the prompt text already matches the guide's recommendations. Nothing here was measured at runtime; where the guide says to run an eval before changing a setting, that is repeated rather than pre-empted.

The guide's own framing matters: Fable 5 prompts should perform well on 5.1 without changes. Most of the findings are therefore refinements, and several skills are already ahead of the guide. The material items are concentrated in three places: the effort enum, durable state for long runs, and prompts that ask one question at a time when a round would do.

## Which guide sections touch which skills

| Guide section | Applies to |
|---|---|
| Consider all effort levels | en-review peer ladder, `ensemble-peer-flags`, `agent-dispatch.md` tier binding, en-sweep CI runner |
| Ask for user-facing progress updates | en-build, en-qa, en-ship watch loop, en-flow, en-setup, en-resolve-pr |
| Batch independent tool calls | en-build, en-plan, en-ship, en-setup, en-debug, en-simplify, en-sweep, en-guardrail |
| Keep history append-only | peer helper only; already one-shot and stateless, nothing to do |
| Writing density and mannered prose | skill prose generally; low priority |
| Formatting in chat | output templates already explicit; nothing to do |
| Quoting retrieved sources | en-learn solution template; web-research already marks quotes |
| Finish the whole task | en-loop worker prompt, en-sweep CI prompt, en-setup, en-plan, en-foundation |
| Compaction summaries | en-build, en-qa, en-flow, en-foundation, en-resolve-pr |
| Keep changes and tests to the task | en-build, en-qa, en-resolve-pr, en-simplify |
| Search triggering at low effort | web-research triggers in en-plan and en-brainstorm |
| Reduce safeguard false positives | en-qa screenshots, en-debug log fetch |
| Prefer targeted edits | en-foundation, en-plan finalize loop, en-learn syncs, en-sweep, en-simplify, en-build, en-resolve-pr |
| Leave room for long outputs | en-plan, en-foundation, en-brainstorm |
| Let the lead keep working | en-plan research, en-foundation retrofit, en-sweep, en-brainstorm approaches |
| Vision tools | en-qa bug evidence |

## Cross-cutting work items, ranked

1. **Effort enum.** `ensemble-peer-flags` and `peer-model-policy.md` accept only `low|medium|high`. Fable 5.1 has `xhigh` and `max`, and the guide says effort names do not map across models and the sweep should be re-run. Extend the enum to `xhigh`, then re-evaluate the ladder rungs with an eval rather than assuming `high` still means what it did. Leave `max` out unless measured. The three `ensemble-peer-invoke` copies and the policy file move together under the parity guards.
2. **Agent tier binding.** `agent-dispatch.md` binds `evidence` to `sonnet`, `ceiling` to `opus`, `retrieval` to `haiku`. The guide says Fable at `low` is often competitive with Opus and Sonnet on cost per task and scores higher, and asks that it be included wherever a smaller model at higher effort would run. The Agent tool states both model and reasoning effort come from agent frontmatter. Run a comparison for `dimension-reviewer` and `code-simplifier` first; change the binding on evidence, not on the guide's general claim. Eight byte-identical copies per agent file move together.
3. **One question round instead of a sequence of prompts.** en-setup asks up to seven yes/no questions in one run and en-foundation asks one question per turn across up to twelve groups. en-brainstorm and en-plan already use frontier rounds with recommended answers. Bring en-setup and en-foundation to the same shape.
4. **Durable run state for compaction.** en-build, en-qa, en-flow, en-resolve-pr and en-foundation hold their in-flight ledger only in context. Client-side compaction in Claude Code can drop it, and the guide's compaction instruction is not something a skill can set. Write the ledger to `/tmp/ensemble/<skill>/<run-id>/` and derive the final report from the file. en-review already does this with its envelope; en-loop reconstructs from git by design.
5. **Batching nudge in the resolve-context steps.** Several skills open with a list of independent reads and never say to issue them in one message. The guide's one-sentence nudge fits at those steps.
6. **Targeted edits.** Add the guide's one-liner where a skill edits an existing long document: en-foundation retrofit and finding application, en-plan finalize loop, en-learn foundation and pointer-map syncs, en-sweep batches, en-simplify apply, en-build implement and apply. en-sweep step 11 should name `Edit` for existing files and `Write` only for new ones.
7. **Scope line for incidental findings.** en-build, en-qa and en-resolve-pr have no rule for a pre-existing bug found mid-task. Add the guide's line: report it as a follow-up, do not fix unless the requested behaviour cannot work without it, and size committed tests like the neighbouring files.
8. **Non-blocking research.** en-plan's research reference says the skill awaits both agents before proceeding. en-foundation retrofit and en-sweep are similar. Where the next step does not depend on the result, start the agent, continue, collect later. The Agent tool runs in the background by default on Claude Code, so the harness already supports this.
9. **Search nudge.** The web-research triggers in en-plan and en-brainstorm gate on "library the repo does not use with known footguns", which the model judges from memory. At low effort Fable 5.1 answers from memory more often. Add the guide's sentence: recognising a name from a fast-moving area is a reason to search, not to skip.
10. **Long-output note.** en-plan, en-foundation and en-brainstorm produce documents of several hundred lines. If a host runs at `xhigh` or `max`, add the guide's note that reasoning is for structure and the output space is for the text.
11. **Progress lines in long tool chains.** Fable 5.1 narrates less during long tool-calling turns. en-build already has a per-unit line. en-qa, en-ship's watch loop, en-flow stage transitions and en-setup steps do not specify interim lines.
12. **Autonomous block in the two prompts Ensemble hands to a fresh model.** The en-loop worker prompt and the en-sweep CI invocation are the only places Ensemble composes a whole prompt for a fresh Fable process. Neither carries the guide's opening sentence that the user is not watching and the check-your-last-paragraph rule. A worker that stops to ask stalls the loop; a sweep runner that describes the PR it would open passes the `num_turns` guard.

Low priority, noted for completeness: the guide's mannered-prose section applies to the skill files themselves, which lean on "load-bearing" and similar phrases; base64 in tool output can trip safety classifiers, which touches en-qa screenshots and en-debug log fetches; the solution template in en-learn does not say to mark copied source text as a quotation.

## Per-skill assessment

### en-brainstorm

Standing: the best aligned skill in the set. Frontier rounds with recommended answers, fact lookups that do not block the frontier, verification dispatched while the user reads the synthesis, evidence kept in a dossier and cited by path. It is human-in-the-loop by design, so the finish-the-task guidance is not the target.

Work: add the search nudge to the step 10 web-research trigger. Add the long-output note at step 15 for Deep. In `brainstorm-approaches.md`, say the lead drafts the devil's-advocate framing while the constraint-diverged agents run.

### en-build

Standing: the autonomy contract already matches the guide's autonomous block nearly clause for clause, including the exception that uncertainty is not a pause case. Per-unit progress report, path-limited staging, and the failure protocol that stops on scope widening are all in line. Full suite once, trailers as evidence, receipt written.

Work: add the incidental-bug rule to 9c and the test-sizing rule alongside it. Add the batching nudge at step 6 context reads and at 9d, where lint and tests are independent. Add the targeted-edit line at 9c and at 10.3 finding application. Write a per-unit ledger to `/tmp/ensemble/en-build/<run-id>/` so the final summary and the 10.6 audit table survive compaction; `--from` already covers git state, the ledger covers the report. Add a one-line "starting U<N>: <goal>" before each implement step; Fable 5.1 goes quiet for minutes at high effort in long chains.

### en-debug

Standing: telemetry mode is exactly the guide's exception clause, a described problem whose deliverable is an assessment. The blocking choice is deliberate and documented. The rule to write the findings block in full before the question opens solves a real modal-surface problem. Log lines are quoted verbatim in a labelled block and secrets redacted.

Work: add the batching nudge to code-mode step 2, where reproduce, environment check, `git log` and blame are independent. Cap or strip long base64 runs from fetched logs before they enter context; container logs and JWT payloads carry them, and the guide names base64 in tool output as a false-positive trigger. Split the long code-mode paragraphs.

### en-flow

Standing: thin orchestrator with a terminal done marker and stop-at-gate semantics. Nothing here asks permission for work already requested.

Work: specify a one-line stage-transition message, since the final message of a long run may otherwise cover only the ship stage. Record stage outcomes, in particular en-build's `learning_checkpoint:` value and the plan path, to `/tmp/ensemble/en-flow/<run-id>/` so step 5 and step 6 read a file rather than context after a compaction between stages.

### en-foundation

Standing: the known-facts ledger, ask-only-what-the-ledger-left-open, one-line confirmations and the precision rules on invented metrics are strong. Step 4 already says to read in parallel.

Work: move the discovery loop from one question per turn to frontier rounds per group with recommended answers, keeping one-per-turn only for rigor probes; this is the single largest turn count in Ensemble. On retrofit, ask the groups the code cannot answer while `repo-research` runs instead of waiting for it. Add the targeted-edit line for retrofit edits and peer-finding application; this repo's foundation file is 299KB. Add the long-output note at step 9. Write the ledger to disk so a compaction mid-interview does not lose it.

### en-guardrail

Standing: mostly a hook, not a model prompt. The D93 path fix landed this branch. The skill body is status, patterns and dry-run.

Work: steps 2 through 4 are independent reads; add the batching nudge. Nothing else from the guide applies.

### en-learn

Standing: the capture gate's default of writing nothing is the guide's keep-changes principle applied to knowledge. Architecture sync says surgical edits only. One learning per run.

Work: step 14 foundation sync and step 15 pointer-map sync lack the surgical-edit line step 13 has; add it. Step 17 says "regenerate by appending", which reads as a rewrite instruction; say append. Add to the solution template that text copied from a PR thread, document or log is marked as a quotation. In `--refresh`, present dispositions as one round rather than confirming each entry in turn.

### en-loop

Standing: reconstructing state from git and never from memory makes it compaction-proof by design. Caps, test gate and no-fake-success are in place.

Work: the worker prompt is one of two places Ensemble composes a full prompt for a fresh model, and it lacks the guide's autonomous block. Add its first paragraph and the check-your-last-paragraph rule; a worker that ends its iteration with "next I would" produces a rollback, not a commit. Add the incidental-bug rule next to "make no unrelated refactors". If gnhf's backend config can pin effort, expose it; verify against `gnhf --help` first.

### en-plan

Standing: frontier rounds, bounded foundation read, parallel research, pre-write quality review, severity-gated re-loop and the hash helper are all in line. The plan-file offer and the build hand-off are follow-up offers, which the guide permits.

Work: `research-dispatch.md` says the skill awaits both agents before proceeding; on Standard and Deep, ask the round-1 architecture question while research runs when it does not depend on the result. Add the long-output note at step 15. Add the targeted-edit line to the finalize loop so a rewrite of the plan file cannot reflow the fields the hash canonicalises. Add the search nudge to the web-research trigger. Fold the plan-type confirmation and the step 12 confidence-check offer into the last frontier round rather than asking them as separate turns. Add the batching nudge at step 4, where design doc, foundation index, learnings index and tech-debt tracker are independent reads.

### en-qa

Standing: the autonomy contract, the caller-versus-human resolution, skip-never-fake, and the rule that every in-scope flow has an outcome are exactly right.

Work: the flow list and per-flow outcomes live only in context, and a compaction mid Phase 2 loses precisely what rule 8a protects; write `.test-output/qa/<run-id>/flows.json` at the start of step 7, update it per flow, and derive the report from it. Add the incidental-bug rule to the bug protocol: a bug in a flow the change did not reach is reported, not fixed, unless the in-scope flow cannot pass without it. Say screenshots go to disk and only paths enter the report, for both drivers, so base64 stays out of context. For a visual bug, take an element-scoped or zoomed screenshot as evidence; this is the guide's vision item. Add a per-flow one-liner as each flow completes.

### en-resolve-pr

Standing: orchestrated mode never blocks and runs one pass, replies quote the excerpt, comment text is untrusted, reported bugs owe a regression test, and the convergence check stops divergent rounds early.

Work: default-to-fix is deliberate and stays, but add the boundary the guide draws: fix what the comment names; something adjacent the reviewer did not raise becomes a suggestion or a TD entry, not an edit. Add the batching nudge for per-item reads across items. Add the targeted-edit line at step 7. Write the step 6 task list to a scratch file so a compaction mid-run does not lose the item set.

### en-review

Standing: detached peer, personas in one batch, blind-peer invariant, verification pass, envelope on disk, and the phase 1 rule to ask about every ambiguous finding at once. This skill is where the earlier session's work landed and it shows.

Work: the effort enum, item 1 above; this skill is the sole resolver, so the change is here plus the three helper copies. The `dimension-reviewer` `model: opus` binding is the first candidate for the Fable comparison in item 2. Nothing else from the guide applies; the peer prompt's JSON-only rule is correct under `--json-schema`.

### en-setup

Standing: the mandatory step 18 verification is the right backstop for the guide's turn-ends-early failure on long mechanical sequences. Idempotent, never overwrites, merge-only on existing files.

Work: consolidate the opt-in questions into one round after state detection, each with a recommended answer, then run the install sequence without stopping. Today a run can stop for legacy-plan archival, sweep cadence, local config, guardrail scope, gnhf, the code-review action and `REVIEW.md` in turn. Add the batching nudge for the probes in steps 13 through 16. Specify a one-line progress message per step.

### en-ship

Standing: hands-off default, receipt-based skip with reasons, named exit states, comment text never executed, backoff polling, and a final recap that covers the whole task.

Work: add the batching nudge at step 1, where branch, base, existing PR and fetch are independent. In the watch loop, emit a line on each state change rather than per poll, so a user watching a fifteen-minute CI run sees the loop is alive.

### en-simplify

Standing: three dispatches in one message, read-only reviewers, parent applies, edit narrowly, revert one fix rather than the pass.

Work: the guide's rewrite tendency matters most here; a simplify pass that rewrites a file produces a diff the review then reads as reformatting. Add the targeted-edit line at step 5. `code-simplifier` at `model: sonnet` is the second candidate for the Fable-at-low comparison. Add the batching nudge at step 6, where typecheck, lint and scoped tests are independent.

### en-sweep

Standing: headless in CI, doc-only by contract, silent no-op exit, and the `en-sweep-ci` guard against an inert runner.

Work: steps 4 through 8 are independent scans; dispatch `repo-research` first and run the lints while it works. Step 11 should name `Edit` for existing docs and `Write` only for new files. Add the autonomous block's opening paragraph to the CI invocation prompt; the `num_turns` guard catches a runner that did nothing, not one that described the PR and stopped. Consider running the sweep at `medium` effort behind a config key, since the guide says medium roughly matches Fable 5 at lower cost; measure before defaulting.

## Suggested order

Start with the effort enum and the agent-tier comparison, since they affect every peer run and every dispatch. Then the two consolidation changes, en-setup and en-foundation, which change user experience the most. Then the durable ledgers, in the order en-qa, en-build, en-flow. The batching, targeted-edit, scope and search-nudge lines are one-sentence additions and can go in as one commit per guide section across skills, subject to the size pins.
