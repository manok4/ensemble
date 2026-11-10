---
type: plan
plan_type: feature
plan_id: EN28
title: Run /en-ship on a configured model per host
status: open
location: active
created: 2026-11-10
shipped:
deepened:
covers_requirements: []
requirements_pending: false
related_design:
peer_review_verdict: revise
peer_review_iterations: 2
peer_review_last_run: 2026-11-10
peer_review_plan_hash: 91cb7283d00789462ff6bd5de954fb2ef5cc93a683ca343b110667e90c824785
peer_review_resolutions:
  - finding_id: 1-1
    iteration: 1
    severity: P1
    title: "Continuation skips refreshing child-modified state"
    status: applied
    location: U2
  - finding_id: 1-2
    iteration: 1
    severity: P1
    title: "Conductor lacks the new question-return handling"
    status: applied
    location: U3
  - finding_id: 1-3
    iteration: 1
    severity: P1
    title: "Codex outcomes can leave the stated goal unmet"
    status: applied
    location: Out of scope
  - finding_id: 2-1
    iteration: 2
    severity: P1
    title: "Conductor model selection lacks a concrete scenario"
    status: applied
    location: U3
depth: standard
data_scale: small
---

# EN28 — Run /en-ship on a configured model per host

## Context

A Claude usage review reported that `/en-ship` accounts for about a third of model usage. Ensemble's metrics record time, not tokens, so the figure is unverified. They do show `/en-ship` taking a median 968s and a p90 5521s over 25 runs, with most of that in the CI watch loop. Shipping is mechanical work: preflight, commit, push, then poll CI and fix review-bot findings. The operator wants it to run on a cheaper model, Sonnet for example, while planning and building stay on the session model. Today `/en-ship` always runs on whatever model the session has, and `/en-conductor`'s Ship stage agent inherits that model too.

## Requirements covered

None from `docs/foundation.md`. This is an operator cost control in the same family as D100, D103 and D104.

## Out of scope for this plan

- A per-call effort setting for ship. The operator asked for the model only. `ship_effort_*` can follow the same pattern later.
- Token accounting in `ensemble-run-metrics`. The "33%" claim stays unverified. See the risk below.
- Configurable models for any other skill. This plan settles the mechanism on one skill.
- Splitting the watch loop's fixes onto the host model. The operator chose one model for the whole ship.
- A guaranteed Codex binding. Honouring `ship_model_codex` depends on U4's live evidence. If a Codex child cannot load the skill, run on the given model and push, this plan delivers Claude-only control, and Codex gets a documented, dated limitation with a one-time message. The operator chose this reproduce-then-decide scope. A Codex path that needs a different mechanism, `codex exec -m` for example, becomes its own plan.
- Changing how `/en-fix` invokes `/en-ship`. Its in-session call keeps working, and `/en-ship` places itself.

## Approach (high-level)

There are two new flat keys: `ship_model_claude` holds a Claude alias (`haiku | sonnet | opus | fable`), and `ship_model_codex` holds an operator's Codex model ID. Unset means inherit the session's model, which is today's behaviour. A small resolver, `ensemble-ship-model`, reads the key for the current host through `ensemble-config-get`, validates the value, and prints what it resolved. Every caller reads that output and makes no choice of its own (D103's rule).

`/en-ship` places itself. A new step right after the recursion guard resolves the model. When a model is set, it re-runs the same invocation in a fresh subagent with that model and returns the child's report. It stays in session when `--in-agent` was passed, under `--interactive`, when the current branch is the base's default branch (the typed confirmation needs the user), or when the host has no verified dispatch. A child that hits a question it cannot ask ends with `en-ship: needs-input <question>`. The parent asks the user, then finishes the ship in session on the host model. The ship is rerunnable, and an existing PR is updated, not duplicated. If the Agent call is refused or returns no report, the parent falls back to the session the same way the conductor does: it reruns in session only when `HEAD` is unchanged, the tracked tree is clean and no PR exists for the branch. Otherwise it stops and names what landed.

`/en-conductor`'s Ship stage resolves the model itself. It dispatches its stage agent with that `model` and adds `--in-agent`, so there is one hop and the stage agent never loads on the host model. The Fix route is unchanged. `/en-fix` runs `/en-ship` inside the conductor's Fix agent, and `/en-ship` then dispatches one more agent. D143's 2026-11-04 check verified that depth: a conductor subagent spawning one agent.

Codex comes last as reproduce-then-decide. D115 and D141 show that `spawn_agent` takes a per-call `model` and `fork_turns: "none"` on current CLIs. Nobody has verified that a Codex child can load a skill and push. Until U4 records the evidence, a Codex session ships in session and says once that `ship_model_codex` is set but not yet honoured.

## Test seams

- **`ensemble-ship-model` CLI** (new): behavioural tests against fixture `--repo-root` and `--home` directories, the same shape as `tests/lint/ensemble-agent-model.test.sh`. This is the only seam with logic.
- **Skill prose** (existing seam): `grep -F` pins on `skills/en-ship/SKILL.md`, `skills/en-ship/CONTRACT.md`, `skills/en-ship/references/model-dispatch.md` and `skills/en-conductor/SKILL.md`, each with a negative control. This is how every other skill clause is pinned.
- **Live dispatch** (manual): only a real session shows the Agent call's `model`. The check is recorded in `tests/evals/ledger.md`, as D141's live check was.

Parity of the copied scripts is covered by `tests/parity/script-parity.test.sh`, which discovers carriers itself.

## Technical design

Components: the resolver (new), `/en-ship`'s placement step and reference (new), `/en-conductor`'s Ship row (changed) and the config surface (changed).

```
caller                               en-ship (session)                      en-ship (child, --in-agent)
──────                               ─────────────────                      ───────────────────────────
/en-ship [args]          ──────────► Resolve context (branch, base, PR)
                                     Recursion guard
                                     Model placement:
                                       detect host → ensemble-ship-model
                                       SHIP_MODEL empty, --in-agent,
                                       --interactive, HEAD == default,
                                       or host has no verified dispatch ─► continue in session (today's path)
                                       else ── Agent(model=SHIP_MODEL) ───► /en-ship --in-agent [args]
                                                                             runs steps 2b.. as today
                                     ◄── report + last line ─────────────── last line unchanged, or
                                                                             `en-ship: needs-input <q>`
                                     needs-input → ask user → run in session
                                     no report / refused → guarded fallback

/en-conductor Ship stage ── Agent(model=SHIP_MODEL) ──────────────────────► /en-ship --in-agent [--no-watch]
/en-conductor Fix stage  ── Agent(host model) → /en-fix → /en-ship ─────► places itself as above (depth 2, D143)
```

## Implementation units

### U1. Add the ship-model keys and their resolver

- **Goal:** Make `ship_model_claude` and `ship_model_codex` readable and validated in one place, and documented where operators look.
- **Requirements covered:** none
- **Dependencies:** none
- **Interfaces:**
  - *Produces:* `ensemble-ship-model --host claude-code|codex [--repo-root <dir>] [--home <dir>]`. Prints two eval-able, shell-escaped lines to stdout, `SHIP_MODEL=<value or empty>` and `SHIP_MODEL_SOURCE=config|inherit`. Exits 0 for any config state and 2 only for a missing or bad `--host`. An invalid configured value prints one stderr line, `ensemble-ship-model: ignoring ship_model_<claude|codex>=<value>: <reason>`, and resolves to `inherit`. `--repo-root` defaults to `git rev-parse --show-toplevel` (or `.` outside a repo), and `--home` defaults to `$HOME`.
  - *Consumes:* the sibling `ensemble-config-get` (unchanged).
- **Files:**
  - `skills/en-ship/scripts/ensemble-ship-model` (create)
  - `skills/en-conductor/scripts/ensemble-ship-model` (create)
  - `skills/en-conductor/scripts/ensemble-config-get` (create)
  - `skills/en-conductor/references/script-invocation.md` (modify)
  - `tests/lint/ensemble-ship-model.test.sh` (create)
  - `.ensemble/config.local.example.yaml` (modify)
  - `skills/en-setup/references/templates/config-local-example.yaml` (modify)
  - `setup` (modify)
- **Approach:** Bash with `set -u`. Resolve the sibling `ensemble-config-get` from the script's own directory with the `${BASH_SOURCE[0]:-$0}` idiom that `ensemble-agent-model` uses, and keep stderr unpiped (D127). Map `--host claude-code` to key `ship_model_claude` and `--host codex` to `ship_model_codex`. Read the key once with no `--allowed`, so a present-but-invalid value can be told apart from an absent one, then validate it in the script. A Claude value must be one of `haiku,sonnet,opus,fable`, held in one `SHIP_CLAUDE_ALIASES` variable with a comment dating the check to 2026-11-10 against the Agent tool's documented alias set. A Codex value must match `^[A-Za-z0-9._-]{1,64}$`, the same rule as `valid_codex_id` in `ensemble-agent-model`. Escape output with `printf '%q'`. The two copies are byte-identical, and `en-conductor` gains a byte-identical copy of `ensemble-config-get` copied from `skills/en-ship/scripts/`. `skills/en-conductor/references/script-invocation.md` already exists, because the conductor carries `scripts/`. Modify it only if it lists the carried scripts. In both config example files, add a commented block after the `peer_*` block: `# ship_model_claude:  # alias (haiku | sonnet | opus | fable); unset = the session's model` and `# ship_model_codex:  # your Codex model ID; unset = the session's model`, with one line saying `/en-ship` and `/en-conductor`'s Ship stage read them at run time, so a change needs no `./setup`. In `setup`'s `config_defaults`, add both keys as `null` beside the `agent_*` keys.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Patterns to follow:** `skills/en-plan/scripts/ensemble-agent-model` (validation, escaping, sibling resolution); `tests/lint/ensemble-agent-model.test.sh` (fixture layout).
- **Test scenarios:**
  - *Happy path:* repo `.ensemble/config.local.yaml` has `ship_model_claude: sonnet`, so `--host claude-code` prints `SHIP_MODEL=sonnet` and `SHIP_MODEL_SOURCE=config`.
  - *Happy path:* only `~/.ensemble/config.json` has `"ship_model_codex": "gpt-x.1-mini"`, so `--host codex` prints that ID with source `config`.
  - *Edge case:* both layers set `ship_model_claude`, and the repo value wins (`ensemble-config-get`'s order).
  - *Edge case:* the key is unset, or JSON `null`, so the script prints `SHIP_MODEL=` and `SHIP_MODEL_SOURCE=inherit` with empty stderr.
  - *Edge case:* `ship_model_claude` is set but `--host codex` is asked, so the Claude key is never read and the result is `inherit`.
  - *Error path:* `ship_model_claude: gpt-5`, an unknown alias, gives `inherit`, exit 0 and the stderr `ignoring` line.
  - *Error path:* `ship_model_codex: "a b;rm"` fails the ID rule, giving `inherit` and the `ignoring` line, and nothing is executed.
  - *Error path:* `--host vim`, or no `--host`, exits 2 with usage on stderr.
  - *Integration:* `eval "$(ensemble-ship-model ...)"` in a subshell sets both variables, and `tests/parity/script-parity.test.sh` stays green with the new carriers.
- **Verification:** `./tests/run.sh -k ensemble-ship-model` and `./tests/run.sh -k script-parity` pass. Negative control: change one copy by a byte and parity goes red. Break the alias list and the happy-path case goes red.

### U2. Make /en-ship place itself on the configured model

- **Goal:** Have `/en-ship` invoked in a Claude Code session run in a subagent on `ship_model_claude` when set, and stay in session whenever it may need the user.
- **Requirements covered:** none
- **Dependencies:** U1
- **Interfaces:**
  - *Produces:* the flag `--in-agent`, meaning "already placed, never dispatch". It is accepted by `/en-ship`, listed in `CONTRACT.md`, and used by U3. The child's question line is `en-ship: needs-input <question>`, written as its last line when it would ask the user.
  - *Consumes:* `ensemble-ship-model` from U1, and a byte-identical copy of `ensemble-detect-host` for `HOST`.
- **Files:**
  - `skills/en-ship/SKILL.md` (modify)
  - `skills/en-ship/CONTRACT.md` (modify)
  - `skills/en-ship/references/model-dispatch.md` (create)
  - `skills/en-ship/scripts/ensemble-detect-host` (create)
  - `tests/lint/en-ship-model-dispatch.test.sh` (create)
  - `docs/foundation.md` (modify)
  - `tests/evals/ledger.md` (modify)
- **Approach:** Add a step titled **Model placement** between **Recursion guard** and **Start the run ledger**. Label it `2a.` and relabel the ledger step `2b.`, after `grep -rn '2a\.' tests/ skills/en-ship/` finds and updates any pin on the old label. Keep the SKILL.md text short, because the file is at 24,420 of `skill-size.test.sh`'s 26,624 bytes. The step evals `ensemble-detect-host` and `ensemble-ship-model --host "$HOST"`, lists the four stay-in-session conditions (`SHIP_MODEL` empty or `--in-agent` passed; `--interactive`; `HEAD` is the default branch from **Resolve context**; `HOST` is not `claude-code` until U4 says otherwise), and points at `references/model-dispatch.md` for the dispatch. That reference owns these points:
  - **The dispatch.** Use the Agent tool, `subagent_type: general-purpose`, with `model: $SHIP_MODEL`, and this brief verbatim followed by `/en-ship --in-agent` and the original arguments: "Invoke the skill named below with these exact arguments. You have no way to ask the user: anything you would ask ends your turn with the last line `en-ship: needs-input <question>`. Return the run report and its last line unchanged."
  - **Before dispatch.** Record `HEAD`.
  - **On return.** Print the child's report and last line verbatim. That is the parent's report.
  - **On `en-ship: needs-input <q>`.** Ask the user with the host's question tool. Then continue this run in session from **Resolve context**, re-reading branch, base and existing PR because the child may have committed, pushed or opened one. Keep the original arguments, treat the run as if `--in-agent` were passed so it never dispatches again, and carry the user's answer as the decision for that question. A run on a branch that already has a PR updates it (step 1's rule).
  - **On a refused Agent call or a reply with no report.** Rerun in session only when `HEAD` matches the recorded value, `git status --porcelain --untracked-files=no` is empty and `gh pr list --head <branch> --state open` finds nothing. Otherwise stop and name the new commits, edits or PR. This mirrors the conductor's fallback rule.
  - **A Codex section.** It says Codex ships in session pending U4. When `ship_model_codex` resolves non-empty, print once: `ship_model_codex is set but Codex dispatch is unverified (EN28 U4); shipping on the session model.`

  Add `--in-agent` to the SKILL.md flag table and to `CONTRACT.md`'s accepted invocations. Add the `needs-input` line to `CONTRACT.md`'s Return section. Copy `ensemble-detect-host` from `skills/en-conductor/scripts/`. Add **D144** to `docs/foundation.md` §4.1, extending D103 and D132: the keys, self-placement, the stay-in-session conditions, the trade that review-finding fixes also run on the cheaper model, and the cost that the parent still loads `SKILL.md` on the host model. Also add one line to `/en-ship`'s §5.2 entry. Record the live check in `tests/evals/ledger.md`.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* `skills/en-ship/SKILL.md` contains the **Model placement** step, names `ensemble-ship-model` and `references/model-dispatch.md`, and lists `--in-agent`, `--interactive` and the default branch as stay-in-session conditions. Each pin goes red when its clause is deleted (negative control in the test).
  - *Happy path:* `references/model-dispatch.md` contains the verbatim brief, `model: $SHIP_MODEL`, the `en-ship: needs-input` line and the three fallback conditions (`HEAD`, `--untracked-files=no`, `gh pr list`).
  - *Edge case:* a child that opened a PR and then returned `needs-input`. The reference says the continuation restarts at **Resolve context** (so the existing PR is found and updated, never duplicated) and runs as if `--in-agent` were passed. Both clauses are pinned.
  - *Edge case:* the **Model placement** step sits after **Recursion guard** and before **Start the run ledger**, so a parent that dispatches opens no run of its own. The test checks the line order.
  - *Error path:* `CONTRACT.md` lists `--in-agent` and the `needs-input` return, and `tests/lint/skill-size.test.sh` stays green for en-ship.
  - *Integration:* `tests/parity/script-parity.test.sh` stays green with en-ship's new `ensemble-detect-host` copy.
  - *Integration (manual, live):* in a scratch branch of this repo with `ship_model_claude: sonnet` in `.ensemble/config.local.yaml`, `/en-ship --preflight` from an Opus session dispatches an Agent call carrying `model: sonnet` and prints the child's preflight report. With the key removed it runs in session. On `main` with the key set it stays in session. Record all three in `tests/evals/ledger.md` with the date and the observed models.
- **Verification:** `./tests/select-for.sh` over the changed paths, then those tests pass, along with `./tests/run.sh -k en-ship` and `bin/ensemble-lint --scope docs/foundation.md`. The live check is recorded.

### U3. Pass the ship model from /en-conductor's Ship stage

- **Goal:** Make the conductor's Ship stage agent run on `ship_model_<host>` directly, without a second hop.
- **Requirements covered:** none
- **Dependencies:** U1, U2
- **Files:**
  - `skills/en-conductor/SKILL.md` (modify)
  - `tests/lint/en-conductor.test.sh` (modify)
- **Approach:**
  - **Ship row.** In the Stages table's Ship row, change the invocation to "invoke `/en-ship --in-agent`, adding `--no-watch` when given". Add one sentence under `## Stage agents`: "Ship's agent is dispatched with `model` from `ensemble-ship-model --host "$HOST"` when it prints one, and the default model otherwise."
  - **Fallback.** The `--in-agent` flag stays on the in-session fallback rerun too, since that rerun is already placed.
  - **A question from the Ship agent.** Under `--in-agent` there is no `/en-ship` parent to ask, so the conductor owns it. When the Ship agent's last line is `en-ship: needs-input <question>`, the conductor logs `stage ship stopped` and stops the run. The report names the question and `/en-ship` as the command to run in session, where the question reaches the user. This follows the existing rule that a stop from Ship "is reported as a stop, never rerun". It is a contract field, not a fallback trigger: the in-session fallback rerun stays reserved for an agent that returned no contract field. The Ship stage's gate gains this line in the Stages table or in `**Ship's exit state.**`.
  - **Fix route.** Add one clause stating that the Fix stage passes no model, because `/en-ship` places itself inside `/en-fix` (D144, the depth D143 verified).
  - **Codex.** Leave the Codex in-session rule (Build placement) untouched. On Codex, Ship runs in session without `--in-agent`, so `/en-ship`'s own placement applies once U4 lands.
  - **Size.** Keep the additions under the skill-size budget. The conductor is at 15,600 bytes, so this is not a concern.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* the Ship row contains `/en-ship --in-agent`, and `## Stage agents` names `ensemble-ship-model`. Both pins go red on removal.
  - *Edge case:* the existing pins (`never \`--auto-merge\``, skipped under `--no-ship` or `local_only`, the fallback clauses) stay green.
  - *Error path:* a Ship agent that pushed and then returned `en-ship: needs-input <q>`. The conductor's text says it stops with the question and names `/en-ship`, and does not take the fallback rerun. Pinned, with a negative control.
  - *Error path:* the Fix row is unchanged, and the new clause says the Fix stage passes no model. The test pins it, so a later edit that adds a model to Fix has to update the decision.
  - *Integration (manual, live):* in an Opus session with `ship_model_claude: sonnet` in `.ensemble/config.local.yaml`, `/en-conductor --resume` on a scratch run whose last finished stage is `learn` (or a fresh plan route with `--no-watch` against a draft PR) reaches Ship and makes exactly one Agent call, carrying `model: sonnet` and the argument `/en-ship --in-agent --no-watch`. No second, nested dispatch appears. With the key removed, the same Ship call carries no `model` and runs on the session model. Record both in `tests/evals/ledger.md` with the date and the observed models.
- **Verification:** `./tests/run.sh -k en-conductor` and `./tests/run.sh -k script-parity` pass, and the live check is recorded.

### U4. Reproduce a Codex ship child on a configured model, then wire or document

- **Goal:** Know, from a live Codex session, whether a `spawn_agent` child given `model` and `fork_turns: "none"` can run `/en-ship` end to end, and make the Codex path match the evidence.
- **Requirements covered:** none
- **Dependencies:** U2
- **Files:**
  - `tests/evals/ledger.md` (modify)
  - `skills/en-ship/references/model-dispatch.md` (modify)
  - `skills/en-ship/SKILL.md` (modify)
  - `tests/lint/en-ship-model-dispatch.test.sh` (modify)
  - `docs/foundation.md` (modify)
- **Approach:** In a Codex session (record the CLI version) in a scratch repo with a push-capable remote and `ship_model_codex` set to an operator ID, spawn a child with `spawn_agent`, `model: <id>`, `fork_turns: "none"`, and a message to run `$en-ship --in-agent --no-watch --draft`. Record three facts from the rollout, never from the child's self-report (D115's lesson): whether the child's rollout shows the configured model, whether it loaded the skill, and whether `git push` and `gh pr create` succeeded under its sandbox. Then take one of three outcomes:
  - **All three hold.** Replace the Codex section of `model-dispatch.md` with the `spawn_agent` dispatch, using the same brief, return handling and fallback as Claude. Drop the `HOST` condition from the SKILL.md step, and update the test pins.
  - **The child runs but cannot push or open the PR.** Keep Codex in session, and reword the one-time message to name the sandbox limit with the ledger entry's date.
  - **No model, or no skill load.** Same as the previous outcome, naming that fact.

  Amend D144 with the outcome in every case. Delete the scratch repo and remote afterwards.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path (outcome 1):* the pins for the Codex dispatch (`spawn_agent`, `fork_turns: "none"`, `model`) are present, and the `HOST` stay-in-session condition is gone. Each pin is negative-controlled.
  - *Error path (outcomes 2 and 3):* the Codex section still says Codex ships in session, and the message names the recorded reason. The pin on the message stays.
  - *Integration (manual):* the ledger entry names the CLI version, the configured and observed models from the rollout, and the push and PR results.
- **Verification:** the ledger entry exists. `./tests/run.sh -k en-ship-model-dispatch` passes. `bin/ensemble-lint --scope docs/foundation.md` is clean.

## Decisions, assumptions & risks

- **Decision:** `/en-ship` dispatches itself at run time rather than using frontmatter `model:` or `context: fork`. Frontmatter is static, so a configurable value would need `./setup` to rewrite an installed, symlinked skill. A fork runs in the background with no way to ask the user. Self-dispatch reads the config on every run and keeps the question path.
- **Decision:** a child that needs the user returns `en-ship: needs-input`, and the parent finishes in session on the host model. Pre-checking every possible question in the parent would mean running preflight on the host model on every ship, which defeats the purpose.
- **Decision:** the watch loop's fixes to review-bot findings run on the configured model too. The operator chose one key and one model, and the watch loop is where most of the time goes.
- **Decision:** the conductor passes the model on its Ship stage and adds `--in-agent`, so there is one hop. The Fix route relies on `/en-ship`'s own placement at depth 2, which D143 verified.
- **Decision:** a dedicated resolver rather than a new path in `ensemble-agent-model`. That resolver needs an agent file and builds `agent_*` keys only, and widening it would touch nine byte-identical copies for one caller.
- **Alternative:** a `ship_effort_<host>` key. It was left out because the operator asked for the model only, and Claude's per-call dispatch takes no effort anyway.
- **Assumption:** the Agent tool's per-call `model` accepts `haiku | sonnet | opus | fable` (code.claude.com/docs/en/sub-agents, read 2026-11-10). If the set changes, `SHIP_CLAUDE_ALIASES` is the one place to edit.
- **Assumption:** a parent that dispatches still loads the whole of `/en-ship`'s SKILL.md, about 6k tokens, on the host model. That is small next to a watch loop, but it is not zero. D144 states it.
- **Risk:** the 33% figure is unverified, so the saving is unmeasured. **Mitigation:** the live check in U2 records the model per run. A token measurement belongs in `ensemble-run-metrics`, which is out of scope here, and is noted as a follow-up in D144.
- **Risk:** a cheaper model fixes a review finding badly during the watch loop. **Mitigation:** the loop stays capped at 2 cycles and ends `escalated` with the findings named. Unsetting the key restores the host model at once.
- **Risk:** a child pushes, then stops on a question, leaving a half-finished ship. **Mitigation:** the parent's in-session continuation reruns from the ledger step, and the existing-PR rule makes that an update, not a second PR.

## Tracked debt

None.

## Iteration log

> - 2026-11-10 (initial): plan v0 from the conversation request plus two rounds of planning questions. All six recommended answers were taken. Repo research covered the resolver, config reader, conductor stages, en-ship's ask points, Codex TOML rendering and the affected tests.
> - 2026-11-10 (peer pass 1, codex, revise): applied three P1s. The needs-input continuation re-reads Resolve context and never redispatches. The conductor stops on a Ship agent's needs-input and names `/en-ship`. The Codex scope is stated as conditional on U4.
> - 2026-11-10 (peer pass 2, codex, revise): applied one P1. U3 gains a live check that the Ship dispatch carries `model: sonnet` and `--in-agent`, with no nested dispatch. The cap is reached.
