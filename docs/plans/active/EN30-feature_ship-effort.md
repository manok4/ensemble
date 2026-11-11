---
type: plan
plan_type: feature
plan_id: EN30
title: Run /en-ship at a configured effort per host
status: in_progress
location: active
created: 2026-11-11
shipped:
deepened:
covers_requirements: []
requirements_pending: false
related_design:
peer_review_verdict: revise
peer_review_iterations: 2
peer_review_last_run: 2026-11-11
peer_review_plan_hash: 2c7a0e527cad7c4a308c89f4d010bea22120d828b1ad6ba56ffc84685b141b9b
peer_review_resolutions:
  - finding_id: 1-1
    iteration: 1
    severity: P1
    title: "Conductor argument rules contradict effort-only dispatch"
    status: applied
    location: U3
  - finding_id: 1-2
    iteration: 1
    severity: P2
    title: "Default-branch effort scenario lacks a fixture change"
    status: applied
    location: U2
  - finding_id: 2-1
    iteration: 2
    severity: P1
    title: "Combined-dispatch fixture uses the wrong config key"
    status: applied
    location: U2
depth: standard
data_scale: small
---

# EN30 — Run /en-ship at a configured effort per host

## Context

EN28 (D144) lets the operator pick the model `/en-ship` runs on, but not its effort. On Claude Code that gap is worse than it looks. A subagent with no `effort` takes the session's level only when it runs on the session's own model. On any other model the session level "doesn't apply", and the child runs at that model's default (code.claude.com/docs/en/model-config, "Effort level of subagents and teammates", read 2026-11-11). Sonnet 5.5 defaults to `medium`, so a `ship_model_claude: sonnet` ship runs at `medium` whatever the session uses. On Codex an omitted `reasoning_effort` inherits the parent's effort, so the ship's effort follows the session. In both cases the operator can't say "Sonnet at `high`". They want an Opus session at `medium` to still ship on Sonnet at `high`.

## Requirements covered

None from `docs/foundation.md`. This is an operator cost and quality control in the D100, D104 and D144 family.

## Out of scope for this plan

- Moving the persona agents (`dimension-reviewer`, research agents) from install-time effort rendering (D104) to a per-call `effort`. Per-call effort makes that possible now, but it touches `setup`, D104 and the install tests. Tracked as TD45.
- `max` effort. D95 and D104 keep effort to `low | medium | high | xhigh`, and a ship has no use for `max`.
- Effort for any other skill, or for the `/en-fix` path's own stages.
- Proving the Claude child's effort through the CI grader's stream. The stream has the Agent call's `effort` argument, not the child's effective level. U2 records the effective level by hand from the subagent's transcript.

## Approach (high-level)

There are two new flat keys, `ship_effort_claude` and `ship_effort_codex`, valued `low | medium | high | xhigh`. They follow `ship_model_<host>`'s rules: repo layer before global, unset or the literal `inherit` means no override, and an invalid value is named once on stderr and treated as unset. `ensemble-ship-model` resolves the effort beside the model and prints a third line, `SHIP_EFFORT`. Callers keep deciding nothing for themselves (D103).

**Either key starts the dispatch.** Step 2a's stay-in-session test changes from "`SHIP_MODEL` is empty" to "`SHIP_MODEL` and `SHIP_EFFORT` are both empty". With effort alone, the child runs on the session's model at the configured effort (operator's decision, 2026-11-11). The dispatch passes each value only when it is set:

- **Claude Code:** the Agent call takes `model: $SHIP_MODEL` and `effort: $SHIP_EFFORT`. The per-call `effort` parameter exists in Claude Code 2.1.292 and later. It overrides the agent file's `effort:` and is overridden by `CLAUDE_CODE_EFFORT_LEVEL`. Checked live on 2.1.322 on 2026-11-11: an Agent call with `model: haiku, effort: low` from a Sonnet session ran its turns on `claude-haiku-5-5`. Its transcript records `"effort":"low"`, and the subagent meta records `"effort":"low"`.
- **Codex:** the `spawn_agent` call takes `model: $SHIP_MODEL` and `reasoning_effort: $SHIP_EFFORT`. Checked live on CLI 0.167.0 on 2026-11-11. The tool's schema reads "Reasoning effort override for the new agent. Omit to inherit the parent effort". A child spawned with `gpt-6-luna` / `low` from a `gpt-6.1-sol` / `medium` session recorded `gpt-6-luna` / `low` in its rollout's `turn_context`.

On a host that cannot take the effort, there are two cases:
- **Claude Code before 2.1.292** rejects the parameter. That is a refused dispatch, so the existing fallback reruns in session after its snapshot check.
- **A Codex CLI whose `spawn_agent` has no `reasoning_effort`** behaves like EN28's missing-`model` rule. With a model set, it dispatches with the model only and prints once that the effort is not honoured. With effort alone, it stays in session and says so.

`/en-conductor`'s Ship stage passes the same `effort` beside `model`. The repo's 19 statements that Claude Code has no per-call effort are now false, so U4 corrects them without changing how personas bind.

## Test seams

All three already exist, and the build adds no new seam.

- **The resolver's output:** `tests/lint/ensemble-ship-model.test.sh` runs both carriers against scratch config layers. This is the highest seam that sees validation and layering.
- **Pinned skill text:** `tests/lint/en-ship-model-dispatch.test.sh` and `tests/lint/en-conductor.test.sh` grep the clauses that are the only statement of each rule.
- **Behavioural ship cases:** `tests/evals/run-behavioral` drives a real headless ship, and `tests/evals/grade` checks the Agent call's arguments. It is on-demand and never in CI. Its unit tests in `tests/evals/grade.test.sh` run in CI.

## Implementation units

### U1. Resolve ship_effort_<host> beside the ship model

- **Goal:** `ensemble-ship-model` prints `SHIP_EFFORT` from `ship_effort_claude` or `ship_effort_codex`, and the keys are listed wherever ship keys are.
- **Requirements covered:** none
- **Dependencies:** none
- **Interfaces:**
  - *Produces:* `ensemble-ship-model --host <claude-code|codex> [--repo-root <dir>] [--home <dir>]` now prints three eval-able lines, in this order: `SHIP_MODEL='<alias|id|>'`, `SHIP_MODEL_SOURCE='config|inherit'`, `SHIP_EFFORT='<low|medium|high|xhigh|>'`. The first two keep their EN28 meaning. `SHIP_EFFORT` is empty when the key is unset, `inherit` or invalid. The exit codes are unchanged.
  - *Compatibility:* additive. Existing callers `eval` the output and ignore the new variable.
- **Files:**
  - `skills/en-ship/scripts/ensemble-ship-model` (modify)
  - `skills/en-conductor/scripts/ensemble-ship-model` (modify, byte-identical copy)
  - `tests/lint/ensemble-ship-model.test.sh` (modify)
  - `setup` (modify)
  - `.ensemble/config.local.example.yaml` (modify)
  - `skills/en-setup/references/templates/config-local-example.yaml` (modify)
  - `tests/evals/run-behavioral` (modify)
- **Approach:**
  - **Reading the key.** Pick the effort key by host next to the model key: `ship_effort_claude` on `claude-code`, `ship_effort_codex` on `codex`. Read it through the sibling `ensemble-config-get` without `--allowed`, the same way the model is read. That way a present but invalid value can be named rather than silently falling through to the global layer. An invalid repo value inherits and never falls through, matching EN28's rule.
  - **Validation.** `inherit` is treated as empty. A value is valid when it is exactly one of `SHIP_EFFORTS="low,medium,high,xhigh"`. Reject anything holding a character outside `a-z` first, so a list or a glob can't match. Otherwise print `ensemble-ship-model: ignoring <key>=<value>: not one of low,medium,high,xhigh; shipping at the default effort` and emit empty.
  - **Output.** Emit the line through the existing `shellesc`.
  - **The missing-reader branch.** Its stderr message names both keys, and it emits all three lines.
  - **Header comment.** Update it to say the script resolves the model and the effort, and to document the new line.
  - **Setup and examples.**
    - `setup` `config_defaults()` adds `"ship_effort_claude": null, "ship_effort_codex": null` after the ship model keys. The no-jq key list is derived from that heredoc; check it.
    - Both example yaml files add two commented lines under the ship model lines: `# ship_effort_claude:  # low | medium | high | xhigh; unset = the model's default (Claude) or the session's (Codex)`, and the Codex twin. They also extend the existing `inherit` note to cover the effort keys.
  - **Eval runner.** `run-behavioral` writes `inherit` for `ship_effort_claude` and `ship_effort_codex` as well, whenever a case leaves them unset. This keeps the operator's global effort out of every case.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first. Extend `ensemble-ship-model.test.sh` before the script.
- **Patterns to follow:** EN28 U1's model checks in the same script and test. `tests/lint/en-setup-linear-check.test.sh:23-24` shows how to check a key appears in both example yamls.
- **Test scenarios:** (per carrier, in the existing loop)
  - Happy:
    - repo YAML `ship_effort_claude: high` on `claude-code` gives `SHIP_EFFORT=high`, with empty stderr;
    - global JSON `ship_effort_codex: low` on `codex` gives `low`;
    - model and effort both set resolve independently.
  - Edge:
    - the repo layer outranks the global one;
    - unset gives empty with empty stderr;
    - JSON `null` gives empty;
    - `ship_effort_claude` is never read on `codex`;
    - a repo `inherit` overrides a global `high`, with empty stderr;
    - effort set with the model unset gives `SHIP_MODEL=''`, `SHIP_MODEL_SOURCE=inherit` and `SHIP_EFFORT=high`.
  - Error:
    - `max`, `HIGH`, `high,low`, `*` and `turbo` each give empty, with `ignoring ship_effort_claude=` on stderr;
    - an invalid repo value with a valid global one gives empty and does not fall through;
    - a value carrying shell metacharacters is never executed.
  - Integration:
    - `eval` in a subshell sets all three variables;
    - the lone-carrier case (no reader) prints `SHIP_EFFORT=''`;
    - both example yamls name both keys.
- **Verification:** `./tests/run.sh -k ensemble-ship-model` passes, as do `./tests/run.sh -k script-parity` and `./tests/run.sh -k en-setup`. `bash -n setup` passes.

### U2. Dispatch /en-ship's child at the configured effort

- **Goal:** step 2a dispatches when either key is set, and the dispatch carries `effort` (Claude) or `reasoning_effort` (Codex) when `SHIP_EFFORT` is set.
- **Requirements covered:** none
- **Dependencies:** U1
- **Files:**
  - `skills/en-ship/SKILL.md` (modify)
  - `skills/en-ship/references/model-dispatch.md` (modify)
  - `skills/en-ship/CONTRACT.md` (modify)
  - `tests/lint/en-ship-model-dispatch.test.sh` (modify)
  - `tests/evals/grade` (modify)
  - `tests/evals/grade.test.sh` (modify)
  - `tests/evals/behavioral/ship-model-dispatch/expect.json` (modify)
  - `tests/evals/behavioral/ship-model-default-branch/expect.json` (modify: add `ship_effort_claude: high` to `config`, keep `"dispatch": null`)
  - `tests/evals/behavioral/ship-effort-dispatch/expect.json` (create)
  - `tests/evals/behavioral/ship-effort-dispatch/prompt.md` (create)
  - `tests/evals/behavioral/ship-effort-dispatch/base/` (create, copied from `ship-model-dispatch`)
  - `tests/evals/behavioral/ship-effort-dispatch/change/` (create, copied from `ship-model-dispatch`)
  - `tests/evals/ledger.md` (modify)
  - `docs/foundation.md` (modify: new D145, and the §5 en-ship step line)
- **Approach:**
  - **SKILL.md step 2a.**
    - The first stay-in-session condition becomes "`SHIP_MODEL` and `SHIP_EFFORT` are both empty, or `--in-agent` was passed".
    - "rerun this invocation in a subagent on `SHIP_MODEL`" becomes "on `SHIP_MODEL` and `SHIP_EFFORT`".
    - The step names the keys only through the resolver and points at the reference, as now.
  - **`model-dispatch.md`.**
    - **Read-at line.** Change it to "`SHIP_MODEL` or `SHIP_EFFORT` is set".
    - **Claude Code bullet.** It reads: "one Agent call, `subagent_type: general-purpose`, with `model: $SHIP_MODEL` only when `SHIP_MODEL` is non-empty and `effort: $SHIP_EFFORT` only when `SHIP_EFFORT` is non-empty, so an effort-only ship omits `model` and a model-only ship omits `effort`. The configured effort is this skill's explicit instruction to set the parameter. Claude Code before 2.1.292 refuses `effort`, which is a refused dispatch below. `CLAUDE_CODE_EFFORT_LEVEL`, when set in the environment, overrides the call."
    - **Codex bullet.** It adds `reasoning_effort: $SHIP_EFFORT` when it is set. It also adds the rule for a CLI whose `spawn_agent` has no `reasoning_effort`: with a model set, dispatch with the model and print once `this Codex CLI's spawn_agent takes no reasoning_effort; the ship runs at the session's effort.`; with only the effort set, stay in session and print `this Codex CLI's spawn_agent takes no reasoning_effort; shipping in session.`
    - **Evidence.** It gains the two 2026-11-11 live checks from the Approach above.
  - **`CONTRACT.md`.** Where it names `ship_model_<host>`, name `ship_effort_<host>` beside it.
  - **Grader.**
    - **Accepted shape.** `dispatch` accepts `{"model": <alias>?, "effort": <level>?}`, with at least one present. Keep `null` meaning no dispatch.
    - **`ship_dispatches`.** It records each Agent call's `effort` input.
    - **The check.** A wanted `effort` must equal the call's `effort`. A wanted `model` keeps today's two checks. With no `model` wanted, the call must carry no `model`, and the child turns must run on the session's model.
    - **Unit tests.** `grade.test.sh` gets a passing fixture, a fixture where the effort is wrong, and one where the effort is missing.
  - **New case `ship-effort-dispatch`.**
    - Config `ship_effort_claude: high`, with the model unset.
    - Expect `"dispatch": {"effort": "high"}` and `"pushed": true`.
    - This covers the effort-only path the operator chose.
    - In the existing `ship-model-dispatch` case, add `ship_effort_claude: high` to `config` and `"effort": "high"` to `dispatch`, so the model-plus-effort pair is covered without a third case.
  - **Live check before commit.** Run the two cases, then read each child's `subagents/*.meta.json` and transcript for its effective effort. The headless parent should run on a model other than the child's for the model case. Record both rows in `ledger.md`.
  - **D145** (extends D144, amends D104's Claude Code clause). It covers:
    - the two keys and their values;
    - either key dispatches;
    - per-call effort on both hosts, with the version floor and `CLAUDE_CODE_EFFORT_LEVEL`;
    - why it is needed: a Claude child on another model ignores the session level and takes the model's default;
    - the rejected alternative, a rendered `en-ship-runner` agent file, which is static and needs `./setup`.

    The §5 en-ship line becomes "Model placement: with `ship_model_<host>` or `ship_effort_<host>` set, rerun in a subagent on that model and effort unless the run may need the user (D144, D145)."
  - **Pins.** Update the ones in `en-ship-model-dispatch.test.sh` whose text changes: the empty-model condition, the read-at line and the Claude and Codex dispatch lines. Add pins for the effort parameter on each host, the missing-`reasoning_effort` rule, the version floor and `CLAUDE_CODE_EFFORT_LEVEL`. Each new pin should turn red when its clause is deleted; check by hand.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic. Pins and grader tests first, then the prose, then the live cases.
- **Patterns to follow:** EN28 U2 and the evidence section in `model-dispatch.md`. `docs/learnings/codex-child-mistyped-workdir-reads-as-a-sandbox-limit-2026-11-10.md` says to read a child's effort from its rollout or transcript, never its self-report.
- **Test scenarios:**
  - Happy:
    - (eval) effort only: one Agent call with `effort: high` and no `model`, child turns on the session model, branch pushed;
    - (eval) model and effort: one call carrying both, child turns on Sonnet.
  - Edge:
    - (pin) both empty stays in session;
    - (eval, existing `ship-model-unset`) neither key set, so no dispatch;
    - (eval, existing `ship-model-default-branch`) the default branch stays in session with an effort set as well.
  - Error:
    - (grade unit) a call missing the wanted effort fails with a reason naming it;
    - (grade unit) a wrong effort fails;
    - (pin) the old-CLI and missing-`reasoning_effort` rules are present.
  - Integration:
    - the existing five ship cases still pass with the runner's new `inherit` lines.
- **Verification:**
  - `./tests/run.sh -k en-ship-model-dispatch` and `./tests/run.sh -k grade` pass.
  - `tests/evals/run-behavioral ship-effort-dispatch ship-model-dispatch ship-model-default-branch` passes, and `ledger.md` has the rows.
  - `bin/ensemble-lint --scope docs/foundation.md` is clean.

### U3. Pass the ship effort from /en-conductor's Ship stage

- **Goal:** the conductor's Ship agent is dispatched with `effort` (or `reasoning_effort`) set to `SHIP_EFFORT` when it is set, beside the model.
- **Requirements covered:** none
- **Dependencies:** U1, U2
- **Files:**
  - `skills/en-conductor/SKILL.md` (modify)
  - `tests/lint/en-conductor.test.sh` (modify)
  - `tests/evals/ledger.md` (modify)
- **Approach:** extend the **Ship's model.** paragraph. Keep the pinned sentence "Ship's agent is dispatched with `model` set to `SHIP_MODEL`" intact, and add "and with `effort` set to `SHIP_EFFORT` when it is non-empty (`reasoning_effort` on Codex) (D145)". Replace the paragraph's unconditional "and with no `model` otherwise" with the per-argument rule: `model` is passed only when `SHIP_MODEL` is non-empty, `effort` only when `SHIP_EFFORT` is non-empty, and the Ship agent always gets `--in-agent`, so an effort-only config reaches the child with no `model`. The Fix stage still passes neither, because `/en-ship` places itself inside `/en-fix`. Add pins in `en-conductor.test.sh` for the effort clause and for the per-argument rule, and drop any pin on the old "no `model` otherwise" wording. Live check: a headless conductor run on a scratch branch with `--preflight`, `ship_model_claude: sonnet` and `ship_effort_claude: high`. Record the Agent call's arguments and the child meta's effort in `ledger.md`.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Patterns to follow:** EN28 U3.
- **Test scenarios:**
  - Happy:
    - (pin) the effort clause is present;
    - (live) the Ship agent call carries `model: sonnet, effort: high`.
  - Edge:
    - (live, recorded) effort set with the model unset gives a call with `effort` and no `model`.
  - Error:
    - (pin) the existing `model` pin still passes, so the sentence was extended, not rewritten;
    - (pin) the per-argument rule is present and the unconditional "no `model` otherwise" is gone.
- **Verification:** `./tests/run.sh -k en-conductor` passes, and `ledger.md` has the row.

### U4. Correct the stale "no per-call effort" statements

- **Goal:** no file in the repo says Claude Code's Agent tool has no effort parameter. Persona binding stays at install time, and the persona switch is tracked.
- **Requirements covered:** none
- **Dependencies:** U2 (D145 exists to cite)
- **Files:**
  - `skills/en-brainstorm/scripts/ensemble-agent-model` (modify)
  - `skills/en-debug/scripts/ensemble-agent-model` (modify)
  - `skills/en-foundation/scripts/ensemble-agent-model` (modify)
  - `skills/en-learn/scripts/ensemble-agent-model` (modify)
  - `skills/en-plan/scripts/ensemble-agent-model` (modify)
  - `skills/en-review/scripts/ensemble-agent-model` (modify)
  - `skills/en-simplify/scripts/ensemble-agent-model` (modify)
  - `skills/en-sweep/scripts/ensemble-agent-model` (modify)
  - `skills/en-test-audit/scripts/ensemble-agent-model` (modify)
  - `skills/en-brainstorm/references/agent-dispatch.md` (modify)
  - `skills/en-debug/references/agent-dispatch.md` (modify)
  - `skills/en-foundation/references/agent-dispatch.md` (modify)
  - `skills/en-learn/references/agent-dispatch.md` (modify)
  - `skills/en-plan/references/agent-dispatch.md` (modify)
  - `skills/en-review/references/agent-dispatch.md` (modify)
  - `skills/en-simplify/references/agent-dispatch.md` (modify)
  - `skills/en-sweep/references/agent-dispatch.md` (modify)
  - `skills/en-test-audit/references/agent-dispatch.md` (modify)
  - `docs/foundation.md` (modify: D104's Claude effort clause and the review-host sentence near D100)
  - `setup` (modify: the comment above the Claude effort renderer)
  - `tests/install/claude-effort-agents.test.sh` (modify: header comment only)
  - `docs/plans/tech-debt-tracker.md` (modify: add TD45)
- **Approach:**
  - **The new statement.** Replace each "no per-call effort" statement with the accurate one: "the Agent tool takes a per-call `effort` from Claude Code 2.1.292 (D145). Persona agents still bind effort through the installed file's `effort:` rendered by `setup` (D104), and moving them is TD45." Use the same sentence in every copy of a file so parity holds.
  - **D104.** Amend only its "Claude effort binds at install time" sentence, with a parenthetical "(amended by D145: per-call effort exists since 2.1.292; personas still bind here)". Keep the decision itself.
  - **Code.** No code changes. The installed `effort:` rendering stays.
  - **TD45.** "Persona agents could take effort per call instead of install-time rendering." It records:
    - what it would remove: the COPY-not-symlink publishing for agents with an effort key, and the need to rerun `./setup` after a change;
    - the risk: the precedence against the agent file and `CLAUDE_CODE_EFFORT_LEVEL`;
    - the trigger: the next change to D104's keys.
  - **Search.** Before editing, grep the whole repo for `no per-call effort`, `no effort parameter`, `nothing for effort` and `has no effort`. Correct every hit outside `docs/plans/completed/` and `docs/designs/`, which are history.
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - Integration:
    - `tests/parity/` stays green across all 18 copies;
    - `tests/install/claude-effort-agents.test.sh` still passes, since only its comment changed;
    - the repo-wide grep finds no stale statement outside history.
- **Verification:**
  - `./tests/run.sh -k parity`, `./tests/run.sh -k ensemble-agent-model` and `./tests/run.sh -k claude-effort-agents` pass.
  - The grep is empty outside history.
  - The full `./tests/run.sh` passes before the final commit.

## Decisions, assumptions & risks

- **Decision (operator, 2026-11-11): either key dispatches.** With effort alone, the ship runs in a subagent on the session's model. The cost is one subagent context load even when the model is unchanged. That is accepted, because effort is the point.
- **Decision (operator): `low | medium | high | xhigh`.** The same set as D104, and `max` stays out (D95).
- **Decision (operator): correct the stale docs here, and track the persona switch as TD45.**
- **Decision (planner): extend `ensemble-ship-model` rather than adding a script.** One resolver call keeps step 2a and the conductor to one line each, and parity already pins the two copies. The script name now undersells it, and its header says so. A rename would touch every pin for no gain.
- **Decision (planner): pass effort per call, not through a rendered agent file.** The per-call parameter is verified on both hosts. A rendered `en-ship-runner` file would be static and need `./setup`, which is what D144 rejected for the model.
- **Assumption:** the subagent meta's `"effort"` field and the transcript's per-turn `"effort"` reflect the effective level. The docs don't say this outright. The ledger rows record what was observed, not a guarantee.
- **Risk:** `CLAUDE_CODE_EFFORT_LEVEL` silently overrides the key. The reference says so, and nothing else is done about it, because the environment variable is the operator's own choice.
- **Risk:** an Agent call with an unknown `effort` on an old Claude Code takes the refused-dispatch fallback and loses the model too. That is acceptable: the snapshot rule keeps it safe, and the floor (2.1.292) is old.
- **Risk:** the Agent tool's description says to set `effort` only when instructions explicitly ask. The reference states that the configured key is that instruction, so a child-placing parent doesn't skip it. The U2 eval checks it.

## Tracked debt

- TD45 (added by U4): persona agents could take effort per call.

## Iteration log

- **Iteration 1 (2026-11-11, codex, revise).** 1-1 (P1): U3 and U2 now pass `model` and `effort` each only when set, so an effort-only ship omits `model`; the conductor's unconditional "no `model` otherwise" is replaced and pinned. 1-2 (P2): U2 adds `ship_effort_claude: high` to the default-branch case and runs it.
- **Iteration 2 (2026-11-11, codex, revise).** 2-1 (P1): the `ship-model-dispatch` fixture now names the config key `ship_effort_claude: high` and the expectation `dispatch.effort: high`. Cap reached; a wording fix, no re-review.
