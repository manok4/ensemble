---
type: design
created: 2026-09-07
topic: Per-agent model control and en-plan cost/latency fixes
status: accepted
related_plan: EN16
---

# Per-agent model control and en-plan cost/latency fixes

This is a hand-off document. It collects everything learned from one full
`/en-plan` run (PolicyAsync FR85, a 17-unit Deep plan, 2026-09-06 to
2026-09-07) so a separate session can turn it into an Ensemble plan and fix
the causes. The single biggest finding is that research agents ran on the
most expensive model available, and the operator had no working way to stop
that. Everything else is secondary.

## Problem

An `/en-plan` run that should have cost tens of dollars cost about $182 and
71 minutes of active time. Two research agents alone cost $67 because they
ran on the host model (Claude Fable 5.1) instead of the Sonnet the agent
definitions ask for. The operator's config file that was supposed to pin
cheaper models is invalid JSON and silently ignored. The peer model choice
the operator made in that file also never reached the Codex peer, because
only `/en-review` resolves those keys and `/en-plan` does not.

The question to settle here: how do we guarantee that, for a named agent
(repo-research, web-research, repo-fact-lookup, learnings-research), the
operator can set the model it runs on, and that the setting cannot be
silently bypassed?

## Evidence from the session

### Timeline (active time, wall clock excluded user waits of 16h34m and 14m)

| Phase | Minutes | Notes |
|---|---|---|
| Pre-skill research (user-driven, before `/en-plan`) | 11 | Three agents in parallel, 4 / 5.5 / 9 min |
| en-plan setup and planning questions | 5 | Two question rounds, batched. Worked well. |
| Plan write | 10 | 17 units, 873 lines |
| Verify and lint | 8 | 5 min lost to `mktemp` failing under the sandbox |
| Peer pass 1 | 4 | Codex 2m03s; 2 min lost to detached invoke failing under zsh |
| Apply pass 1 | 17 | 12 P1 findings applied |
| Peer pass 2 | 3 | Codex 2m18s |
| Apply pass 2 | 8 | 8 P1 findings applied |
| Finalize (hash, status flip, commit) | 0.5 | |

Other counts: 5 context compactions in one plan run. 7 lint runs at roughly
2 minutes each, about 14 minutes total. Codex tokens: pass 1 46,174 in /
3,231 out; pass 2 54,047 in / 2,696 out; one failed detached attempt 25,916
in / 5 out. All Codex calls used `gpt-6-astra` at effort `high`, inherited
from `~/.codex/config.toml`, not the `gpt-5.6-sol` the operator configured.

### Cost (Anthropic list prices fetched 2026-09-07, 1h cache TTL in effect)

| Item | Model actually used | Cost | Cost if Sonnet |
|---|---|---|---|
| Main session (host) | Fable 5.1 | $56.25 | n/a, host is the user's choice |
| Pre-skill MCP web research agent | Fable 5.1 (fallback) | $47.00 | roughly $10 |
| en-plan `repo-research` | Fable 5.1 (fallback) | $34.38 | $7.25 |
| en-plan `web-research` (36 web fetches) | Fable 5.1 (fallback) | $32.31 | $7.48 |
| Data-model map agent | Opus 5 | $6.66 | |
| Auth map agent | Opus 5 | $5.14 | |
| en-plan `learnings-research` | Sonnet 5 | $0.73 | as-is |
| Codex peer (two passes plus one failed) | gpt-6-astra | Unknown (pricing page returned 403) | |

Main session breakdown: cache writes $30.81, output $20.39, cache reads
$4.99, input $0.05. The two en-plan research agents overspent by about $52
against the Sonnet they were defined to use. Sonnet is cheaper than the Opus
tier the user named as acceptable, and it is what the agent files already
declare, so the fix is to make the declaration take effect, not to pick a
new model.

## Root causes, in priority order

1. **Six of nine bundled agent definitions have no `description:` field, so
   Claude Code never registers them.** Claude Code's subagent docs
   (`https://code.claude.com/docs/en/sub-agents`, read 2026-09-07) say only
   `name` and `description` are required, and a file with a `name` but no
   `description` is skipped with the reason written only to the debug log.
   The affected files are:
   - `skills/en-brainstorm/agents/repo-fact-lookup.md`
   - `skills/en-brainstorm/agents/web-research.md`
   - `skills/en-debug/agents/repo-research.md`
   - `skills/en-foundation/agents/repo-research.md`
   - `skills/en-plan/agents/repo-research.md`
   - `skills/en-plan/agents/web-research.md`
   - `skills/en-sweep/agents/repo-research.md`

   The three that do have a description (`learnings-research`,
   `dimension-reviewer`, `code-simplifier`) were the only Ensemble agents the
   session's host offered. `setup` symlinks every one of them into
   `~/.claude/agents/` and the symlinks resolve, so installation is not the
   problem. The `model: sonnet` line in the skipped files is dead text.

2. **The dispatch fallback drops the model.** When a name is not registered,
   `skills/en-plan/references/agent-dispatch.md` says to dispatch
   `general-purpose` with the agent body as the prompt. It also says call
   sites omit the `model` override unless an operator alias is configured.
   Combined with cause 1, every research dispatch this session ran on the
   host model. Under Claude Code's resolution order (per-call `model`
   parameter, then frontmatter `model`, then `CLAUDE_CODE_SUBAGENT_MODEL`,
   then the main conversation model), a general-purpose dispatch with no
   `model` argument lands on the fourth rung, which is the most expensive
   one when the host is Fable.

3. **`~/.ensemble/config.json` is invalid JSON and fails soft.** Line 9 reads
   `"review_peer_model_alias": opus,` with an unquoted value.
   `skills/en-review/scripts/ensemble-config-get` is designed to fall through
   to defaults on malformed JSON, so every key in that file, including
   `review_peer_codex_model: "gpt-5.6-sol"` and
   `review_host_model_alias: "opus"`, was ignored for the whole session with
   no warning. `setup` writes `"review_peer_model_alias": null` as the
   default (around line 263), so the bad value came from a hand edit, but
   nothing validates the file afterwards.

4. **Only `/en-review` resolves peer model and effort.** The policy doc
   `skills/en-review/references/peer-model-policy.md` says "/en-review is
   the only resolver". `skills/en-plan/scripts/ensemble-peer-invoke`
   accepts `--peer-model`, `--peer-effort`, `--effort` and `--model-alias`,
   but en-plan's peer step never passes any of them, so the Codex peer
   inherits whatever `~/.codex/config.toml` says. That is why the peer ran
   on `gpt-6-astra` at `high` even with the config key set (and it would
   have been ignored anyway because of cause 3).

5. **The peer loop cap does not scale with depth.** `skills/en-plan/SKILL.md`
   line 166 fixes the iteration cap at 1 at every depth. On a 17-unit plan
   pass 1 produced 12 P1 findings and pass 2 produced 8 more, and the run
   ended at the cap with `peer_review_verdict: revise`. The user then had
   to decide manually whether to accept. Two passes is right for Standard
   plans and too few for Deep ones.

6. **P1 severity inflation.** Twenty findings across two passes were all P1
   with confidence at or above 7, which is the auto-apply band in
   `skills/en-plan/references/peer-brief.md` lines 44-46. Several were
   wording or consistency fixes that a P2 label would have deferred. When
   everything is P1, the confidence gate does no work and every finding
   costs an apply cycle (25 of the 71 minutes went to applying findings).

7. **Whole-plan reads cause compaction.** Applying findings meant re-reading
   the 873-line plan several times. Five compactions in one run is a cost
   in cache writes (the largest line item in the host cost) and a
   correctness risk, since each compaction can lose finding detail.

8. **Lint is slow and not sandbox-safe.** `bin/ensemble-lint` takes about
   2 minutes per run and lints the whole docs tree. Its three bare
   `mktemp` calls (lines 53, 411, 816) failed under the Claude Code
   sandbox until a shim forced a writable path. Root cause of the
   `mktemp` failure is Unknown; the working theory is that the sandbox's
   `TMPDIR` was not honoured somewhere in the call chain.

9. **Detached peer invoke fails under zsh.** The detached form (D81) at
   `skills/en-plan/scripts/ensemble-peer-invoke` line 404 failed on first
   use because Claude Code's Bash tool on macOS is zsh. The file's own
   comment at lines 34-40 describes the BASH_SOURCE problem for sourcing;
   the detached path has a similar gap. One failed Codex call (25,916
   input tokens) and 2 minutes were lost before the foreground form worked.

10. **Duplicate research.** The user ran three research agents before
    invoking `/en-plan`, and `/en-plan` then dispatched its own
    `repo-research` and `web-research` over overlapping ground. There is no
    way to hand prior same-session research to the skill.

## Constraints and context

- Ensemble policy (`skills/en-review/references/peer-model-policy.md`):
  no concrete model ID may appear anywhere in Ensemble. Operators supply
  IDs through config. Aliases (`sonnet`, `opus`, `haiku`, `fable`,
  `inherit`) are allowed because Claude Code owns them.
- Three-layer model policy already exists for the peer: policy doc, binding
  via `ensemble-peer-flags`, call sites. The research-agent fix should reuse
  that shape rather than invent a fourth mechanism.
- Config precedence already defined: `--effort` flag, then
  `<repo>/.ensemble/config.local.yaml`, then `~/.ensemble/config.json`,
  then the ladder. Keep it.
- D39 priority: performance > speed >= cost. Cheaper research models are
  acceptable only where they do not lower plan quality. Research agents
  read and cite; they do not decide. That is exactly the work Sonnet is
  defined for in the agent files today.
- Claude Code project-level `.claude/agents/<name>.md` overrides
  user-level `~/.claude/agents/<name>.md` by name. This is the per-repo
  escape hatch and needs no Ensemble code.
- `CLAUDE_CODE_SUBAGENT_MODEL` exists as a global fallback but sits below
  both the per-call parameter and frontmatter since Claude Code v2.1.251.
  It is a blunt tool and should not be the primary mechanism.
- The Agent tool's per-call `model` parameter in this host accepts
  `sonnet`, `opus`, `haiku`, `fable`.

## Assumptions & unverified claims

- Assumes the missing `description:` is the only reason the six agents did
  not register. Not verified against Claude Code's debug log. The plan's
  first unit should confirm this by adding the field and checking the
  agent list before touching anything else.
- Assumes the Codex host path dispatches research agents through the
  Codex CLI in a way that can accept a model argument. Not verified. If
  Codex-host dispatch has no model hook, the Codex half of the research
  key becomes documentation only.
- Assumes `ensemble-config-get` has no strict mode today. Not verified
  beyond its usage header.
- Assumes the `mktemp` failure is `TMPDIR`-related. Not verified.

## Approaches considered for per-agent model control

### A. Frontmatter only

**Sketch:** Add `description:` to the six broken agent files so Claude Code
registers them and honours `model: sonnet`. Change nothing else.

**Pros:** smallest change, fixes the $52 overspend outright, no new config.

**Cons:** the operator still cannot change the model without editing
skill-owned files (which `setup` symlinks, so edits land in the source
repo). No Codex-host equivalent. Fallback dispatch still drops the model.

### B. Operator config key resolved at every dispatch site

**Sketch:** Add `research_agent_model_alias` (Claude hosts, alias only,
default `sonnet`) and `research_agent_codex_model` (Codex host, operator-
supplied ID, default null) to `~/.ensemble/config.json` and `setup`'s
default block. Every skill that dispatches a research agent (en-plan,
en-brainstorm, en-debug, en-foundation, en-learn, en-review, en-sweep)
reads the key through `ensemble-config-get` and passes it as the Agent
tool's `model` parameter. The per-call parameter is rung one in Claude
Code's order, so it beats frontmatter and cannot be lost by a fallback
dispatch.

**Pros:** one setting controls every research agent across all skills;
mirrors `review_host_model_alias`, which already exists for personas;
survives the general-purpose fallback because the call site supplies the
model.

**Cons:** seven skills to touch; needs a strict config read so a bad
config file fails loudly instead of silently reverting to the host model.

### C. Project-level agent overrides

**Sketch:** Document that a repo can drop `.claude/agents/repo-research.md`
with a different `model:` and Claude Code will prefer it.

**Pros:** zero Ensemble code. **Cons:** per-repo, per-agent, Claude-only,
and invisible to Ensemble's own dispatch logic.

## Recommendation

Do A and B together, and document C as the per-repo escape hatch. A is
mandatory regardless (unregistered agents are a bug). B is what answers
the user's question, because it gives one operator knob per agent class
that the dispatch path cannot drop. Default the alias to `sonnet`, which
is what the agents already declare and is cheaper than the Opus tier the
user named as acceptable; the operator sets `opus` if a specific repo
needs it.

Make the config read strict for these keys: invalid JSON in
`~/.ensemble/config.json` must print one warning naming the file and line
and then apply defaults. Fail-soft is fine for optional keys; it is not
fine when the silent default is "run everything on the most expensive
model you have".

## Proposed units

Unit boundaries follow the en-plan rule (a reviewer could reject one while
approving its neighbour). Paths are relative to the Ensemble source repo.

1. **Register the research agents.** Add a one-line `description:` to the
   seven agent files listed under root cause 1. Verify in a fresh Claude
   Code session that `repo-research`, `web-research` and `repo-fact-lookup`
   appear in the Agent tool's list and that a dispatch bills at Sonnet
   rates. Add a lint rule (or a `setup` check) that fails when any
   `skills/*/agents/*.md` lacks `name:` or `description:`.

2. **Add the research model keys.** In `setup`'s config default block add
   `"research_agent_model_alias": "sonnet"` and
   `"research_agent_codex_model": null`. Document both in
   `skills/en-review/references/peer-model-policy.md` beside the existing
   `review_*` keys, with the same "aliases only for Claude, operator ID for
   Codex" rule.

3. **Pass the model at every research dispatch.** Update
   `skills/en-plan/references/agent-dispatch.md` and
   `skills/en-plan/references/research-dispatch.md` so the dispatch step
   reads `research_agent_model_alias` via `ensemble-config-get` and passes
   it as the Agent `model` parameter, both for the named dispatch and for
   the general-purpose fallback. Repeat for the equivalent references in
   en-brainstorm, en-debug, en-foundation, en-learn, en-review and
   en-sweep. The fallback must never dispatch without a `model` argument.

4. **Strict config read.** Give `ensemble-config-get` a `--strict` (or
   `--warn`) flag that prints a single line to stderr when the JSON does
   not parse, naming the file and the parse error, before returning the
   default. Use it at the research and peer resolution sites. Add a
   `setup --check` or `en-setup` diagnostic that validates
   `~/.ensemble/config.json` and `<repo>/.ensemble/config.local.yaml` and
   reports every key with its resolved value and source.

5. **Resolve peer model and effort in every peer-invoking skill.** Change
   the policy sentence "/en-review is the only resolver" to "every skill
   that invokes a peer resolves through `ensemble-peer-flags`". en-plan's
   peer step should call `ensemble-peer-flags --effort <tier>
   [--codex-model <id>]` with `review_peer_effort_override` and
   `review_peer_codex_model` read from config, and pass the resulting
   `PEER_MODEL`/`PEER_EFFORT` to `ensemble-peer-invoke`. Same for en-build
   and en-foundation if they invoke a peer. Consider renaming the keys to
   `peer_*` with `review_peer_*` kept as read-only aliases, since they are
   no longer review-specific.

6. **Fix the operator's config file.** Quote the value on line 9 of
   `~/.ensemble/config.json`. This is a one-line local fix outside the
   repo; the plan should list it as a manual step so the next session does
   not forget it.

7. **Scale the peer loop cap with depth.** Lightweight 0 extra iterations,
   Standard 1, Deep 2, with the last Deep pass confirm-only (the peer may
   only return "accept" or a P1 with confidence 9 or higher). Keep
   `--max-iterations` and `--no-reloop` as overrides. Update SKILL.md line
   166 and the peer-brief.

8. **Calibrate severity in the peer brief.** Add a P1 definition to
   `skills/en-plan/references/peer-brief.md`: P1 means the plan would lead
   `/en-build` to build the wrong thing or fail a phase check. Naming,
   wording, and cross-reference consistency are P2 unless they change a
   signature another unit consumes. Ask the peer to cap P1 findings at a
   number proportional to unit count (for example one per three units)
   and push the rest to P2 with a reason.

9. **Apply findings without re-reading the whole plan.** Write findings to
   a file in the plan's review directory keyed by U-ID, and have the apply
   step read only the affected unit blocks with `sed -n` ranges. Record
   compaction count as a run metric so regressions are visible.

10. **Make lint cheaper and sandbox-safe.** Add a `--file <path>` scope to
    `bin/ensemble-lint` so a plan run lints only its plan, and replace the
    three bare `mktemp` calls with
    `mktemp "${TMPDIR:-/tmp}/ensemble-lint.XXXXXX"` after confirming the
    real cause. Target under 20 seconds for a single-file run.

11. **Fix detached peer invoke under zsh.** Make the detached form at line
    404 of `ensemble-peer-invoke` re-exec itself under bash explicitly and
    add a smoke test that runs it from a zsh parent. Record the failed
    attempt's token cost as the reason.

12. **Accept prior research.** Add `--research <path>` (or read a
    `docs/research/<topic>.md` convention) so `/en-plan` skips its own
    `repo-research` and `web-research` dispatch when the user supplies
    same-session findings. Keep `learnings-research` since it is cheap.

13. **Cost and duration metrics per run.** Have en-plan write a small
    `run-metrics` block (agent dispatches with model and duration, peer
    passes with token counts, compaction count, lint runs) into the review
    directory so the next improvement pass has evidence without a manual
    transcript reconstruction like this one.

Keep as-is: question batching in two frontier rounds (5 minutes for a
Deep plan is good), the Codex peer itself (roughly 2 minutes per pass with
high-quality findings), and the confidence-gated auto-apply once
severities are calibrated.

## Acceptance checks for the follow-up plan

- A fresh Claude Code session lists all nine Ensemble agents by name.
- A `repo-research` dispatch from `/en-plan` with default config runs on
  Sonnet; with `research_agent_model_alias: "opus"` it runs on Opus. Verify
  from the session's cost breakdown, not from the prompt text.
- Deleting `description:` from one agent file makes lint or `setup` fail.
- With invalid JSON in `~/.ensemble/config.json`, the run prints one
  warning naming the file and continues on defaults.
- With `review_peer_codex_model` set, the Codex rollout for an en-plan
  peer pass shows that model in its header instead of the config.toml
  default.
- A Deep plan run can reach a third, confirm-only peer pass without a
  manual override.
- A single-file lint run finishes in under 20 seconds inside the Claude
  Code sandbox with no shim.

## Open questions for the user

- Should the research-agent default be `sonnet` (current agent files,
  cheapest) or `opus` (what you named as acceptable)? The recommendation
  above defaults to `sonnet` and lets the operator raise it.
- Do you want the `review_peer_*` keys renamed to `peer_*` in this pass, or
  left alone with en-plan simply reading them?
- Is there a Codex-host research dispatch path today? If not, the Codex
  research key can be deferred.

## Revision 2026-09-07: what the hot-fix covered and what the plan should do instead

Written after reviewing this document against the code and after PR #85.

### Verified against the code

- Root cause 1 is confirmed. The seven files lacked `description:`; the field
  was dropped in EN14 (#46), so the agents have been unregistered since then.
  The session that reviewed this document listed only the three Ensemble
  agents that still had a description.
- Root cause 3 was live: the operator's `config.json` failed to parse at line
  9 and `ensemble-config-get` returned empty with exit 0.
- Root cause 4 is a stated policy, not an oversight: `peer-brief.md` says
  en-plan carries no effort resolver. That holds for the diff-size ladder,
  which has no meaning for a plan. It never held for `review_peer_codex_model`,
  which D100 added after that sentence was written.
- Root cause 5 reverses D49, which capped the loop because a single-shot peer
  mostly resamples its first pass. This run's second pass produced eight new
  P1s, but cause 6 says the severities were inflated, so the two cannot be
  separated from one run.
- Root cause 8: `bin/ensemble-lint` already accepts a file path as `--scope`.
  A full docs run on the Ensemble repo took 54 s on 25 files with two thirds
  of it in system time, so it is process-spawn bound.
- Root cause 9: the detached form uses nothing bash-only on inspection. The
  failure is unreproduced.

### Covered by PR #85 (merged separately, no plan unit needed)

- Unit 1: `description:` restored on all seven files; the agent test now
  requires both loader fields and fails on a stripped one.
- Unit 3, the mandatory half: the name-does-not-resolve fallback passes the
  agent file's `model:` as the Agent tool's `model`.
- Unit 4, the warning half: malformed global JSON prints one stderr line
  naming the file and the parse error, unconditionally. No `--strict` flag.
- Unit 6: the operator's file was quoted by hand.

### Per-host model control: the recommendation supersedes approach B

Codex custom agents are TOML files in `~/.codex/agents/` (user scope) or
`.codex/agents/` (trusted project scope) with required `name`, `description`
and `developer_instructions`, and optional `model` and
`model_reasoning_effort`; an unset model inherits the parent's. `setup`
symlinks Ensemble's markdown agent files into that directory, and Codex does
not read markdown there. So there is no working Codex research dispatch
today, and `agent-dispatch.md`'s rule "On Codex, take the default model and
select nothing" was written on the belief that Codex could not select per
agent. It can.

Compound Engineering was checked for comparison. It registers no agents at
runtime: specialist prompts are frontmatter-less files the skill seeds into a
generic subagent, model tiering lives in the caller, one config key selects a
model for its single heaviest step, and its Codex converter emits TOML agents
with the model field dropped, deferring to Codex config. Its alias table maps
`sonnet` to a concrete ID and must be edited each model generation, which is
the D44 failure Ensemble's no-IDs rule exists to avoid.

Recommendation, replacing the single `research_agent_model_alias` key:

- **Map by tier, override by agent.** The agent files already declare three
  tiers (`retrieval`, `evidence`, `ceiling`). One operator block per host maps
  tier to model; a per-agent override sits on top:

  ```yaml
  agent_models:
    claude:  { retrieval: haiku, evidence: sonnet, ceiling: opus }
    codex:   { evidence: { model: <operator id>, effort: medium } }   # unset tier = inherit
    overrides:
      web-research: { codex: { model: <operator id>, effort: high } }
  ```

  Claude values are aliases; Codex values are operator IDs, so the no-IDs rule
  holds. Merge order: per-agent override, then tier, then the agent's own
  frontmatter, then inherit.
- **Claude binding.** Resolve at dispatch and pass the alias as the Agent
  tool's `model`, on the named path and the fallback path alike. That is rung
  one in Claude Code's resolution order and cannot be lost.
- **Codex binding.** `setup` renders `~/.codex/agents/<name>.toml` from each
  markdown file (body as `developer_instructions`, model and effort from the
  operator block). `spawn_agent` shows no per-call model in the docs, so
  install time is where the binding happens; a config change means re-running
  `setup`. `en-setup` prints the resolved model per agent per host.
- **Per-repo escape hatch, both hosts, no code.** `.claude/agents/<name>.md`
  and `.codex/agents/<name>.toml` in a trusted project outrank the user copy.
- **Decision entry.** Amend the "select nothing on Codex" rule in
  `agent-dispatch.md` and record the change in `docs/foundation.md`.
- **Reproduce first.** The first Codex unit spawns a rendered custom agent by
  name from a Codex session and confirms the model in the rollout header.
  None of the above is verified against a live Codex spawn.

### Ordering for the plan

Peer model and effort resolution in en-plan (with the `peer_*` rename and
`review_peer_*` read as fallbacks, its own unit), then the per-host model
block above, then severity calibration, prior-research hand-off,
single-file lint scope in en-plan's verify step, run metrics limited to what
the skill can observe. The cap change and the zsh fix are reproduce-then-decide
units at the end. Research default is `sonnet` on Claude; the Codex research
model stays unset (inherit) until the reproduction unit passes.

### Reproductions recorded during the EN16 build

- **Root cause 9, detached peer invoke under zsh (U13, 2026-09-07).** Not reproduced. `tests/portability/peer-detached-zsh.test.sh` runs the whole detached lifecycle (`ensemble_peer_start`, `ensemble_peer_wait`, `ensemble_peer_result`) under `zsh 5.9 (arm64-apple-darwin25.0)` with a stub peer and under bash as the control: 22 assertions pass on both, including the slow-peer `running` path and the missing `--job-dir` usage error. The 2026-09-06 failure therefore came from something the stub does not model (the real `codex exec` under the Claude Code sandbox, or the shell state of that particular tool call), not from zsh sourcing or the detached form itself. No code change; the test stays as the guard so a zsh-specific regression is a red test rather than a lost run.
- **Root cause 8, lint `mktemp` under the sandbox (U14, 2026-09-07).** Not reproduced outside the sandbox on macOS 25.5: with `TMPDIR` unset, pointing at a missing directory, or pointing at a read-only one, the old bare `mktemp` still succeeded, because macOS `mktemp` silently falls back to the per-user temp directory (`/var/folders/.../T`) when `TMPDIR` is unusable. That fallback is the likely sandbox failure: a sandbox that grants `TMPDIR` but not the per-user directory makes the silent fallback the one unwritable path, `TMP_FINDINGS` ends up empty, and the run dies with an unbound-variable trace. The lint now places temp files explicitly (`lint_mktemp`: `TMPDIR`, then `/tmp` with one stderr line, then exit 3 naming both paths). Verified by three new `lint-rules` assertions; the in-sandbox case is still unverified and is the reason the message names the paths.

### Loop cap decision (U12): rule first, samples pending

Written 2026-09-07, before any calibrated sample exists, so the rule cannot be fitted to the data.

**Inputs.** The metrics files of the next two Deep `/en-plan` runs made after U8 (severity definitions in the brief) and U11 (`ensemble-run-metrics`) shipped, read for P1 count per peer pass. A run made before both shipped does not count; this plan's own two passes were pre-calibration (6 and 3 findings, 4 and 1 of them P1) and are excluded.

**Rule.** If the second pass returns three or more P1s on both runs, raise the Deep cap to two re-loops where the last pass is confirm-only, keep Standard at one and Lightweight at zero, and keep `--max-iterations` and `--no-reloop`. Confirm-only narrows only what the host does automatically (auto-apply limited to P1 at confidence 9 or higher); every severity stays reportable, a P0 still stops the run, and an unresolved P1 still surfaces at the cap-hit prompt. Otherwise D49 stands and this note says why.

**Samples.**

| Run | Date | Plan | Pass 1 P1 | Pass 2 P1 | Metrics file |
|---|---|---|---|---|---|
| 1 | pending | | | | |
| 2 | pending | | | | |

**Decision.** Pending both samples. Ship scope for U12 is `deferred`; the rule is the deliverable that lands with EN16.
- **Codex custom-agent dispatch (U6, 2026-09-08, Codex CLI 0.153.2).** Outcome 3: a skill cannot spawn a rendered custom agent by name. Setup: a scratch git project with `.codex/agents/repo-research.toml` rendered by `./setup` (temp HOME, `agent_model_codex_evidence: gpt-5.6-sol`, effort `low`), `codex exec --json -s read-only -c 'projects."<path>".trust_level="trusted"'`, asked to spawn `repo-research` by name; repeated with `--enable multi_agent_v2`. Evidence from the rollouts under `~/.codex/sessions/2026/09/08/`: the parent's `spawn_agent` call carried `{"task_name":"repo_research","fork_turns":"all","message":…}` and no agent, role or model field; the child's `session_meta` shows `agent_role: null`, `agent_path: /root/repo_research`; both threads' `turn_context` show `model: gpt-6-astra, effort: high`, the parent's config.toml values, not the TOML's. Codex itself reported "the available spawn tool cannot select custom agents from .codex/agents/" in both runs. Consequences: the U5 TOML stays (it is what Codex's own agent picker reads, and the format is the documented one), the eight `agent-dispatch.md` carriers now say the per-call half plainly, and Codex-host research dispatch through a named custom agent is filed as TD13 rather than planned here. Not verified: whether the interactive Codex TUI's agent picker honours the TOML model; only `exec` was exercised.
