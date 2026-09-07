---
type: plan
plan_type: improvement
plan_id: EN16
title: Per-host agent model control and en-plan cost fixes
status: open
location: active
created: 2026-09-07
shipped:
deepened:
covers_requirements: []
requirements_pending: true
related_design: docs/designs/2026-09-07-agent-model-control-and-en-plan-cost-design.md
peer_review_verdict: revise
peer_review_iterations: 2
peer_review_last_run: 2026-09-07
peer_review_plan_hash: bb32aa5392d37b9809d1c4f0a0280c7f431cb56c33f08bf7c0a60ee1f1efb3bd
peer_review_resolutions:
  - finding_id: "1-1"
    iteration: 1
    severity: P1
    title: Severity must not depend on a finding quota
    status: applied
    rationale: quota removed; calibration by impact and evidence, deduplication, per-unit batching
    location: U8
  - finding_id: "1-2"
    iteration: 1
    severity: P1
    title: Resolver unit consumes undeclared prerequisites
    status: applied
    rationale: U3 now depends on U2
    location: U3
  - finding_id: "1-3"
    iteration: 1
    severity: P1
    title: Research handoff lacks behavioral scenarios
    status: applied
    rationale: three recorded-run scenarios added (skip, truncation sentinel, unreadable path)
    location: U9
  - finding_id: "1-4"
    iteration: 1
    severity: P1
    title: Confirm-only review excludes blocking findings
    status: applied
    rationale: every severity reportable on the final pass; only auto-apply narrowed; scenarios added
    location: U12
  - finding_id: "1-5"
    iteration: 1
    severity: P2
    title: Codex installation leaves repo-config binding unspecified
    status: applied
    rationale: setup binds from the global layer only via a new --global-only resolver flag; two-repo scenario added
    location: U5
  - finding_id: "1-6"
    iteration: 1
    severity: P2
    title: Lint scope and temporary-file repair are independent changes
    status: applied
    rationale: split into U10 (scope) and U14 (mktemp); U-IDs not renumbered
    location: U10
  - finding_id: "2-1"
    iteration: 2
    severity: P1
    title: Invalid Claude overrides reach the dispatch tool
    status: applied
    rationale: Claude values validated against the Agent tool alias set before selection; invalid falls through; scenario added
    location: U3
  - finding_id: "2-2"
    iteration: 2
    severity: P2
    title: Defaults omit the Codex effort tier keys
    status: applied
    rationale: config_defaults enumerates all nine tier keys; merge scenario added
    location: U3
  - finding_id: "2-3"
    iteration: 2
    severity: P2
    title: TOML scalar escaping lacks a defined contract
    status: applied
    rationale: basic-string escaping for scalars defined; round-trip fixture with quote and backslash added
    location: U5
depth: deep
data_scale: small
---

# EN16 — Per-host agent model control and en-plan cost fixes

## Context

One `/en-plan` run on 2026-09-06 cost about $182 and 71 active minutes. The largest single cause, seven unregistered research agents falling through to the session model, is fixed by PR #85 together with the fallback dropping the agent's tier and the silent config-parse failure. What remains is structural: an operator has no way to say which model an agent runs on per host, the Codex install publishes markdown into a directory Codex reads only as TOML, `/en-plan` never resolves the peer model or effort keys that `/en-review` honours, and every P1 finding on a 17-unit plan cost an apply cycle because the plan brief never said what a P1 is. The design doc, including its 2026-09-07 revision, settled the shape; this plan carries it.

## Requirements covered

None — `docs/foundation.md` carries no R-IDs (`requirements_pending: true`). Drivers: G8 (cross-agent peer review with cost controls), G9 (identical behaviour across hosts), G10 (token efficiency), and decisions D39, D44, D49, D86, D100.

## Out of scope for this plan

- A working Codex-host research dispatch beyond the reproduction in U6. If Codex cannot spawn a rendered custom agent by name from a skill, that becomes its own plan.
- Nested config keys. The reader stays flat; the operator chose flat keys over widening the YAML grammar.
- Per-call effort on Claude Code hosts. The Agent tool has no effort parameter; effort stays in agent frontmatter, overridable per repo under `.claude/agents/`.
- Renaming `review_host_model_alias`. It has no non-review consumer.
- Per-repo Codex agent overrides. `setup` binds the user-level TOML from the global config only; a repo-scoped `.codex/agents/<name>.toml` is Codex's own mechanism and is documented, not generated.
- The `fr_id:` alias and `id-stability.fr-*` rule-name rename in the lint.
- Raising the peer loop cap. U12 gathers the evidence and records a decision; it does not pre-commit to a change.

## Approach (high-level)

Two blocks, sequenced so the second can be measured with the first in place.

**Peer keys and resolution (U1, U2).** The three `review_peer_*` keys become `peer_*` with the old names read as fallbacks for one release, and `setup` ships all of them plus `review_host_model_alias` in its defaults, which closes the D100 gap where two keys were never written. `/en-plan` and `/en-foundation` then resolve the peer's model and effort through `ensemble-peer-flags` exactly as `/en-review` does, minus the diff-size ladder, which has no meaning for a document. A new `--effort inherit` tier lets a document-reviewing skill pass a model without inventing an effort.

**Per-host agent model control (U3 to U7).** Every bundled agent already declares a tier through its `model:` alias: `haiku` is retrieval, `sonnet` is evidence, `opus` is ceiling. A new resolver, `ensemble-agent-model`, reads that alias, maps it to a tier, and consults flat operator keys in this order: per-agent override for the host, per-tier value for the host, the agent's own frontmatter, inherit. On Claude Code the resolved alias is passed as the Agent tool's `model` at every dispatch, named or fallback, so the operator's choice sits on rung one of the host's resolution order. On Codex, `setup` renders one `~/.codex/agents/<name>.toml` per agent with the body as `developer_instructions` and model and effort filled from the same resolver, since Codex binds models per agent file and has no per-call override. The resolver and the config reader are copied byte-identical into every dispatching skill per EN12, guarded by a parity test.

**en-plan cost and latency (U8 to U13).** The plan brief gains a P1 definition and a proportional cap, so the confidence gate does work again. `--research <path>` lets a user hand prior findings to the skill instead of paying for the same research twice. The finalize loop lints only the plan file between passes. A small metrics helper records what the skill can observe per run: dispatches with model and duration, peer passes with token counts where the CLI reports them, lint runs, findings per severity per pass. The loop cap and the detached-invoke failure are reproduce-then-decide units at the end, because neither has evidence yet beyond one run.

## Test seams

All four seams exist today; the plan adds no new one.

1. **Prose anchors.** `tests/lint/*.test.sh` grep single-line fragments of SKILL.md and references (the `rule`/`has` pattern). Used for every reference and SKILL.md change.
2. **Script behaviour.** Scripts invoked directly with `--home` / `--repo-root` pointing at temp dirs, asserting stdout, stderr and exit code (the `cg()` block in `tests/lint/en-review-peer-default.test.sh`). Used for the resolver, the config reader, peer-flags and the metrics helper.
3. **Install.** `./setup` run into a temp `HOME` (`tests/install/*.test.sh`). Used for the Codex TOML rendering and the config defaults merge.
4. **Parity.** Byte-identical copies discovered and compared (`tests/parity/peer-contract-parity.test.sh`). Used for the per-skill script copies.

## Technical design

Three components and a two-stage data flow, which fires the complexity trigger.

```
operator config                         resolver (per skill, byte-identical)          binding (per host)
~/.ensemble/config.json  ─┐
<repo>/.ensemble/          ├─ ensemble-config-get ─► ensemble-agent-model ─┬─► Claude Code: Agent(model: $AGENT_MODEL)
  config.local.yaml      ─┘   (flat keys, repo first)   --agent --host       │   at every dispatch, named or fallback
                                                        --agent-file         │
agent frontmatter  model: sonnet ──────────────────────► tier = evidence  ───┴─► Codex: setup renders
                                                                                 ~/.codex/agents/<name>.toml
                                                                                 model = / model_reasoning_effort =
```

Key contracts:

- **Flat keys.** `agent_model_claude_<tier>`, `agent_model_codex_<tier>`, `agent_effort_codex_<tier>`, `agent_model_override_<agent>_claude`, `agent_model_override_<agent>_codex`, `agent_effort_override_<agent>_codex`, with `<tier>` in `retrieval|evidence|ceiling` and `<agent>` the file's `name:`. Claude values are aliases; Codex values are operator IDs. Ensemble's own files never carry an ID.
- **Resolver output.** Eval-able shell, same convention as `ensemble-detect-host`: `AGENT_TIER`, `AGENT_MODEL`, `AGENT_EFFORT`, `AGENT_MODEL_SOURCE` in `override|tier|frontmatter|inherit`. Empty `AGENT_MODEL` means pass nothing and inherit.
- **Peer keys.** `peer_model_alias`, `peer_codex_model`, `peer_effort_override`; legacy `review_peer_*` read through `ensemble-config-get --legacy <old-key>` so layering stays in one implementation.
- **Binding time.** Claude binds at dispatch; Codex binds at `setup`. A config change on a Codex host takes effect on the next `./setup`, and `setup` prints the per-agent result so that is visible.

## Implementation units

Each unit has a stable U-ID. Never renumbered after assignment.

### U1. Rename the peer config keys to `peer_*` with legacy fallback reads

- **Goal:** `peer_model_alias`, `peer_codex_model` and `peer_effort_override` are the documented keys; `review_peer_*` still resolve for one release; `setup` ships all four reviewer keys.
- **Requirements covered:** none (`requirements_pending: true`); D100.
- **Dependencies:** none
- **Interfaces:**
  - *Produces:* `ensemble-config-get <key> [--legacy <old-key>] [--default v] [--allowed a,b] [--repo-root d] [--home d]`. Resolution: `<key>` across both layers first, then `<old-key>` across both layers, then `--default`. Exit 0 always.
  - *Produces:* the key names `peer_model_alias`, `peer_codex_model`, `peer_effort_override` (unchanged semantics from the `review_peer_*` rows in `peer-model-policy.md` (b)).
- **Files:**
  - `skills/en-review/scripts/ensemble-config-get`
  - `setup` (repo root; `config_defaults` and the jq-missing hint at line 274)
  - `skills/en-review/SKILL.md` (step 2b, lines 38–39)
  - `skills/en-review/references/peer-model-policy.md` (section (b) table, section (c))
  - `skills/en-setup/references/templates/config-local-example.yaml` (lines 83–86) and `.ensemble/config.local.example.yaml`
  - `tests/lint/en-review-peer-default.test.sh`
- **Approach:** Add `--legacy` to the reader as a second key tried after the first across the same two layers, so precedence stays in one place. Rename the three keys everywhere they are read or documented; leave `review_host_model_alias` untouched. `config_defaults` writes `peer_model_alias`, `peer_codex_model`, `peer_effort_override` and `review_host_model_alias` as `null`; an operator's existing `review_peer_*` values survive the merge as unknown keys and keep working through `--legacy`. The policy file states the deprecation: legacy names are read until the next minor release and then dropped. Historical decision entries in `docs/foundation.md` (D76, D100) are not rewritten; U7 records the rename.
- **Risk:** medium
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Patterns to follow:** the `cg()` behavioural block in `tests/lint/en-review-peer-default.test.sh` (lines 186–235).
- **Test scenarios:**
  - *Happy path:* `peer_effort_override: high` in repo YAML, nothing global → `cg peer_effort_override --legacy review_peer_effort_override` prints `high`.
  - *Happy path:* only `review_peer_codex_model` set in global JSON → the new key with `--legacy` prints that value; `AGENT`-free call without `--legacy` prints empty.
  - *Edge case:* both new and legacy set at different layers (legacy in repo YAML, new in global JSON) → the new key wins even though the legacy key sits in the higher-precedence layer, because key precedence outranks layer precedence.
  - *Error / failure path:* legacy value outside `--allowed` → falls to `--default`, exit 0.
  - *Integration:* `./setup --host claude --copy` into a temp HOME whose config holds `review_peer_effort_override: "high"` → merged file contains the four new keys as `null` and still contains the legacy key with its value; running setup twice is byte-idempotent.
- **Verification:** `tests/lint/en-review-peer-default.test.sh` green with the renamed spellings and the five scenarios above; `grep -rn review_peer_ skills/ setup` returns only the `--legacy` arguments, the policy's deprecation note and the config example's migration comment.

### U2. `/en-plan` and `/en-foundation` resolve the peer's model and effort through `ensemble-peer-flags`

- **Goal:** The Codex peer of a plan or foundation review runs on the operator's `peer_codex_model` and `peer_effort_override` when set, and inherits the CLI defaults when not, with the outcome visible in `peer_decision`.
- **Requirements covered:** none; D49 (3), D100.
- **Dependencies:** U1
- **Interfaces:**
  - *Produces:* `ensemble-peer-flags --effort inherit ...` emits `PEER_EFFORT=''` and still emits `PEER_MODEL` from `--model-alias` / `--codex-model`. `inherit` is accepted only by the translator; it is never a ladder rung.
  - *Consumes:* `ensemble-config-get <key> --legacy <old>` from U1.
- **Files:**
  - `skills/en-review/scripts/ensemble-peer-flags`
  - `skills/en-plan/scripts/ensemble-peer-flags` (new, byte-identical copy)
  - `skills/en-plan/scripts/ensemble-config-get` (new, byte-identical copy)
  - `skills/en-foundation/scripts/ensemble-peer-flags` (new, byte-identical copy)
  - `skills/en-foundation/scripts/ensemble-config-get` (new, byte-identical copy)
  - `skills/en-plan/SKILL.md` (step 16 invocation bullet)
  - `skills/en-plan/references/peer-brief.md` (the `## Effort` section, lines 66–71)
  - `skills/en-foundation/SKILL.md` (step 11)
  - `skills/en-review/references/peer-model-policy.md` (section (b) opening sentence)
  - `tests/parity/script-parity.test.sh` (new)
  - `tests/lint/en-plan-peer-model.test.sh` (new)
- **Approach:** Add `inherit` to the translator's accepted tiers, emitting an empty effort fragment. In `/en-plan` step 16 and `/en-foundation` step 11, before the invoke: read `peer_effort_override` (allowed `low,medium,high,xhigh`), `peer_model_alias` and `peer_codex_model` through the skill's own `ensemble-config-get` with `--legacy`, then `eval "$($SKILL_DIR/scripts/ensemble-peer-flags --effort "${override:-inherit}" --peer-cmd "$PEER_CMD" --model-alias "$alias" --codex-model "$codex")"` and pass `$PEER_MODEL` / `$PEER_EFFORT` to `ensemble-peer-invoke`, which already accepts them and already degrades a rejected fragment. Rewrite the brief's Effort section: en-plan still runs no ladder; it honours the operator's override and model keys and otherwise inherits. Change the policy sentence to "every skill that invokes a peer resolves through `ensemble-peer-flags`; only `/en-review` runs the ladder". The parity test discovers every `scripts/ensemble-config-get` and `scripts/ensemble-peer-flags` under `skills/*/` and asserts one distinct hash each, and asserts that any skill whose SKILL.md names `ensemble-peer-flags` carries it.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Patterns to follow:** `tests/parity/peer-contract-parity.test.sh` (carriers discovered, not listed).
- **Test scenarios:**
  - *Happy path:* `ensemble-peer-flags --effort inherit --peer-cmd codex --codex-model gpt-x` → `PEER_MODEL='-m gpt-x'`, `PEER_EFFORT=''`.
  - *Happy path:* `--effort high --peer-cmd codex` with no model → `PEER_MODEL=''`, `PEER_EFFORT='-c model_reasoning_effort="high"'` (unchanged behaviour).
  - *Edge case:* `--effort inherit --peer-cmd "claude -p"` with no alias → `PEER_MODEL='--model sonnet'` (the translator's default alias still applies), `PEER_EFFORT=''`.
  - *Error / failure path:* `--effort max` → exit 2, nothing emitted (unchanged).
  - *Integration:* prose anchors: en-plan SKILL.md step 16 names `ensemble-peer-flags`, `peer_effort_override` and `--peer-model`; en-foundation step 11 no longer says "this skill passes no effort flag"; peer-brief no longer says `review_peer_effort_override does not apply here`; the policy no longer says `/en-review` is the only resolver.
  - *Integration:* parity: the four new copies hash-equal their en-review source; deleting one byte from a copy fails the test.
- **Verification:** new tests green; `tests/lint/en-review-peer-default.test.sh` still green; a manual `/en-plan` run in this repo with `peer_codex_model` set shows that model in the Codex rollout header (record in the iteration log).

### U3. `ensemble-agent-model` resolver, tier derived from the agent's alias, copied into every dispatching skill

- **Goal:** One script answers "which model and effort does agent X run on host Y for this operator", from flat config keys, with the agent's frontmatter as the default and inherit as the floor.
- **Requirements covered:** none; D86, D100.
- **Dependencies:** U2 (supplies the en-plan and en-foundation `ensemble-config-get` copies and creates the parity test this unit extends)
- **Interfaces:**
  - *Produces:* `ensemble-agent-model --agent <name> --host <claude-code|codex> --agent-file <path> [--repo-root d] [--home d] [--global-only]` → eval-able lines `AGENT_TIER='retrieval|evidence|ceiling'`, `AGENT_MODEL='<alias|id|>'`, `AGENT_EFFORT='<low|medium|high|xhigh|>'`, `AGENT_MODEL_SOURCE='override|tier|frontmatter|inherit'`. Exit 0 on every config problem; exit 2 only on a missing or unreadable `--agent-file` or an unknown `--host`.
  - *Produces:* the alias-to-tier table: `haiku`→`retrieval`, `sonnet`→`evidence`, `opus`→`ceiling`; any other alias → `AGENT_TIER=''` and tier keys are skipped. The Claude alias allow-list `haiku,sonnet,opus,fable` lives beside it.
  - *Produces:* `scripts/check-health --models`, printing one line per agent per host: name, tier, model, source.
- **Files:**
  - `skills/en-review/scripts/ensemble-agent-model` (new, canonical)
  - byte-identical copies under `skills/{en-brainstorm,en-debug,en-foundation,en-learn,en-plan,en-simplify,en-sweep}/scripts/ensemble-agent-model` (new)
  - `skills/{en-brainstorm,en-debug,en-learn,en-simplify,en-sweep}/scripts/ensemble-config-get` (new, byte-identical copies; en-plan and en-foundation get theirs in U2)
  - `setup` (`config_defaults`: all nine tier keys as `null`: `agent_model_claude_{retrieval,evidence,ceiling}`, `agent_model_codex_{retrieval,evidence,ceiling}`, `agent_effort_codex_{retrieval,evidence,ceiling}`; per-agent override keys are documented in the config example only)
  - `skills/en-setup/references/templates/config-local-example.yaml` and `.ensemble/config.local.example.yaml` (new commented block)
  - `scripts/check-health`
  - `tests/lint/ensemble-agent-model.test.sh` (new)
  - `tests/parity/script-parity.test.sh` (extend with `ensemble-agent-model`)
- **Approach:** Bash, `set -u`, sibling `ensemble-config-get` resolved from the script's own directory with the `${BASH_SOURCE[0]:-$0}` idiom the peer-invoke script uses. Read `model:` from the agent file's frontmatter with the same awk `get_field` shape the lint uses. Host `claude-code` reads `agent_model_override_<agent>_claude` then `agent_model_claude_<tier>` then the frontmatter alias; `AGENT_EFFORT` is always empty on Claude (no per-call effort). Host `codex` reads `agent_model_override_<agent>_codex` then `agent_model_codex_<tier>` then empty (inherit; the frontmatter alias is a Claude alias and is never emitted on Codex), and `agent_effort_override_<agent>_codex` then `agent_effort_codex_<tier>` with `--allowed low,medium,high,xhigh`. Values are validated per host before they are selected, and an invalid value falls through to the next source rather than reaching a dispatch: a Claude value must be one of the aliases the Agent tool accepts (`haiku`, `sonnet`, `opus`, `fable`, listed once in the resolver with the date they were checked, since the host owns that set and Ensemble names aliases, never IDs); a Codex model value must match `^[A-Za-z0-9._-]{1,64}$`; a Codex effort must be one of `low`, `medium`, `high`, `xhigh`. `--global-only` skips the repo layer entirely, for callers that produce a machine-wide artifact and must not pick up whichever repo they happen to run from. The tier is derived from the alias rather than a new `tier:` frontmatter field because the Claude loader's tolerance of unknown frontmatter keys is unverified and an unregistered agent is exactly the failure PR #85 repaired. `check-health --models` walks `skills/*/agents/*.md` once per host and prints the resolution, so an operator can see the binding without a dispatch.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Patterns to follow:** `skills/en-review/scripts/ensemble-peer-flags` (pure translator; validate before emitting; eval-able output).
- **Test scenarios:**
  - *Happy path:* agent file `model: sonnet`, no config → `AGENT_TIER='evidence'`, `AGENT_MODEL='sonnet'`, `AGENT_MODEL_SOURCE='frontmatter'` on Claude; `AGENT_MODEL=''`, `AGENT_MODEL_SOURCE='inherit'` on Codex.
  - *Happy path:* global JSON `agent_model_claude_evidence: "opus"` → Claude resolves `opus`, source `tier`; repo YAML `agent_model_override_web-research_claude: haiku` for agent `web-research` → `haiku`, source `override` (override beats tier; hyphenated agent name works in both layers).
  - *Happy path:* Codex with `agent_model_codex_evidence: "gpt-x"` and `agent_effort_codex_evidence: "medium"` → `AGENT_MODEL='gpt-x'`, `AGENT_EFFORT='medium'`.
  - *Edge case:* agent file `model: fable` (alias outside the table) → `AGENT_TIER=''`, tier keys skipped, override keys still honoured, frontmatter alias returned on Claude.
  - *Edge case:* repo YAML sets `agent_model_claude_evidence: opus`, global JSON sets `haiku` → default resolution returns `opus`; `--global-only` returns `haiku`.
  - *Error / failure path:* `agent_model_override_repo-research_claude: gpt-x` with `agent_model_claude_evidence: opus` → the override is rejected as a non-alias and the result is `opus`, source `tier`; `agent_model_claude_evidence: "opus 4"` (space) → treated as unset, falls to frontmatter; `agent_effort_codex_evidence: turbo` → effort empty; missing `--agent-file` → exit 2 with a one-line message; malformed global JSON → the reader's warning on stderr, resolution continues from the next layer.
  - *Integration:* `scripts/check-health --models` in this repo lists every agent under `skills/*/agents/` twice (once per host) with a non-empty tier for all twelve files.
  - *Integration:* `./setup --host claude --copy` into a temp HOME whose config already holds `agent_model_claude_evidence: "opus"` → the merged file has all nine tier keys, eight of them `null`, and the operator's `opus` preserved; a second run is byte-idempotent.
  - *Integration:* parity: eight `ensemble-agent-model` copies and eight `ensemble-config-get` copies hash-equal; every skill that carries `agents/` also carries both scripts.
- **Verification:** new behavioural test green; parity test green; `./tests/run.sh -k parity` and `-k install` green.

### U4. Claude Code binding: every dispatch passes the resolver's model, named path and fallback alike

- **Goal:** On a Claude Code host, an operator-set model reaches every bundled-agent dispatch as the Agent tool's `model` parameter, and the dispatch reference no longer says "call sites omit the model".
- **Requirements covered:** none; D86, D100.
- **Dependencies:** U3
- **Interfaces:**
  - *Consumes:* `ensemble-agent-model` output (`AGENT_MODEL`, `AGENT_MODEL_SOURCE`) from U3.
- **Files:**
  - `skills/*/references/agent-dispatch.md` (all eight carriers, byte-identical)
  - `skills/en-review/SKILL.md` (steps 2b and the roster dispatch at line 85)
  - `skills/en-simplify/SKILL.md` (line 32)
  - `tests/lint/agent-dispatch-resolves.test.sh` (the `rule` anchors)
- **Approach:** Rewrite the dispatch section of `agent-dispatch.md`: before either dispatch path, `eval "$($SKILL_DIR/scripts/ensemble-agent-model --agent <name> --host "$HOST" --agent-file "$SKILL_DIR/agents/<name>.md")"`; pass `model: $AGENT_MODEL` when non-empty. Because the resolver returns the frontmatter alias when nothing is configured, the named path and the fallback path carry the same value and the declaration still decides by default; the D100 "one exception" paragraph and the PR #85 "two exceptions" paragraph collapse into this one rule. Rewrite the Codex paragraph: Codex binds per agent file, `setup` renders the TOML (U5), and a Codex session selects nothing per call. In `/en-review`, `review_host_model_alias` remains the first choice for `dimension-reviewer` and the resolver is consulted when it is unset; the sentence in `agent-dispatch.md` that names `review_host_model_alias` is rewritten to say so. Update the `rule` anchors in the test to the new single-line fragments and add one that the fallback and named paths cite the same variable.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Patterns to follow:** the "three rules survive compression" anchors in `tests/lint/agent-dispatch-resolves.test.sh` (single-line fragments only; grep is line-based).
- **Test scenarios:**
  - *Happy path:* anchors: `agent-dispatch.md` names `ensemble-agent-model`, the phrase `model: $AGENT_MODEL`, and states the Codex binding is `setup`-time TOML; all eight carriers hash-equal.
  - *Edge case:* the retired sentence "call sites omit any model override" is absent from every carrier; "select nothing" survives only in the per-call sense for Codex sessions.
  - *Error / failure path:* negative control: strip the `ensemble-agent-model` line from one carrier → the parity assertion fails and the anchor assertion fails.
  - *Integration:* manual: a `/en-plan` research dispatch in this repo with `agent_model_claude_evidence: opus` in `.ensemble/config.local.yaml` shows `model: opus` in the Agent call, verified from the session's dispatch record; with the key removed it shows `sonnet`. Record both in the iteration log.
- **Verification:** `tests/lint/agent-dispatch-resolves.test.sh`, `grounding-validation`, `en-setup-scaffold`, `host-only-substitutions` green; the manual check recorded.

### U5. `setup` renders Codex custom agents as TOML with model and effort from the resolver

- **Goal:** A Codex host gets one `~/.codex/agents/<name>.toml` per bundled agent that Codex can load, with `model` and `model_reasoning_effort` present only when the operator configured them.
- **Requirements covered:** none; G9.
- **Dependencies:** U3
- **Interfaces:**
  - *Consumes:* `ensemble-agent-model --host codex` from U3.
  - *Produces:* the TOML shape: `name`, `description`, optional `model`, optional `model_reasoning_effort`, `developer_instructions` as a TOML multi-line literal string (`'''`), rendered from the markdown body after the frontmatter. Scalar fields are TOML basic strings: backslash and double quote are escaped as `\\` and `\"`, control characters other than tab are rejected with a named error; `name` is additionally required to match `^[A-Za-z0-9_-]+$`, which every bundled agent already satisfies.
- **Files:**
  - `setup` (a `render_codex_agent` function and a branch in `install_into` when the target is the Codex root)
  - `tests/install/codex-toml-agents.test.sh` (new)
  - `tests/install/single-skill-install.test.sh` (the Codex expectations, if any assert `.md` under `.codex/agents`)
- **Approach:** When `install_into` runs for `~/.codex`, write `agents/<name>.toml` instead of linking the markdown: `name` and `description` from the frontmatter, `developer_instructions = '''<body>'''`, and `model = "…"` / `model_reasoning_effort = "…"` only when the resolver returns them. The TOML is a machine-wide file, so `setup` calls the resolver with `--global-only`: only `~/.ensemble/config.json` binds it, never the `.ensemble/config.local.yaml` of whichever checkout `setup` was run from, and the per-agent log line names that file as the source. A repo that wants a different Codex model for one agent uses Codex's own project scope, `.codex/agents/<name>.toml`, which outranks the user-level file; rendering that per project is out of scope here. The TOML is always a generated file, so copy versus symlink mode does not apply to it; the manifest records the `.toml` path so a re-run sweeps it, and the sweep of the previous manifest removes the old `.md` symlinks the same way it removes anything else Ensemble installed. A body containing `'''` cannot be represented in a literal string: `setup` refuses that agent with a named error rather than emitting broken TOML. `setup` logs one line per rendered agent with its model or `inherit`. The Claude target is unchanged.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Patterns to follow:** `tests/install/single-skill-install.test.sh` (setup into a temp HOME, then assert the published set) and `tests/install/reinstall-sweep.test.sh` (manifest sweep on re-run).
- **Test scenarios:**
  - *Happy path:* `HOME=$T ./setup --host codex --copy --quiet` → one `.toml` per canonical agent name, zero `.md` under `$T/.codex/agents`, each file has `name`, `description`, `developer_instructions`, and `python3 -c 'import tomllib'` parses each when Python 3.11+ is present (otherwise the parse assertion is skipped and says so).
  - *Happy path:* with `$T/.ensemble/config.json` holding `agent_model_codex_evidence: "gpt-x"` and `agent_effort_codex_evidence: "high"` → the `repo-research.toml` has both keys and `repo-fact-lookup.toml` (retrieval) has neither.
  - *Edge case:* re-running setup after the config changes replaces the TOML with the new model and leaves no stray file; a prior install's `.md` symlink recorded in the manifest is gone after the run.
  - *Error / failure path:* a fixture agent whose body contains `'''` → setup exits non-zero naming the agent and writes no partial TOML for it; every other agent is still rendered.
  - *Edge case:* a fixture agent whose `description` contains a double quote and a backslash → the rendered file parses (tomllib when present) and the decoded `description` and `developer_instructions` equal the source text byte for byte.
  - *Integration:* `--host both` renders TOML under `.codex` and leaves markdown symlinks under `.claude`; the two manifests do not overlap.
  - *Integration:* two checkouts whose `.ensemble/config.local.yaml` set conflicting `agent_model_codex_evidence` values, `setup` run from each with the same `HOME` → byte-identical TOML both times, bound to the global file's value, and the log line names `~/.ensemble/config.json`.
- **Verification:** new install test green; `tests/install/*.test.sh` green; on this machine, `./setup` then `ls ~/.codex/agents` shows `.toml` files only (record in the iteration log).

### U6. Reproduce Codex custom-agent dispatch from a skill and record the result

- **Goal:** Know, from a live Codex session, whether `spawn_agent("repo-research")` resolves the rendered TOML and which model the spawned agent ran on.
- **Requirements covered:** none; G9.
- **Dependencies:** U5
- **Files:**
  - `docs/designs/2026-09-07-agent-model-control-and-en-plan-cost-design.md` (a dated "Codex reproduction" note under the revision section)
  - `skills/*/references/agent-dispatch.md` only if the result contradicts the U4 text (then the eight carriers are corrected together)
- **Approach:** With U5 installed and `agent_model_codex_evidence` set to an operator ID, run `$en-plan` on a small request in a Codex session in a scratch repo and observe the research dispatch: does `spawn_agent` accept the custom agent name, and does the session log or rollout header show the configured model for the child. Three outcomes, each recorded: works as designed; spawns but ignores the model (then the TOML model field is documented as advisory and the design's Codex column is downgraded); cannot spawn by name (then Codex-host research dispatch becomes its own plan and the reference says a Codex session runs research inline). No code is changed in this unit beyond the eight-carrier correction in the third outcome.
- **Risk:** medium
- **Category:** diagnostics
- **Reversibility:** trivial
- **Gated:** false
- **Ship scope:** in
- **Execution note:** pragmatic
- **Test expectation:** none — a manual reproduction whose deliverable is the recorded outcome; the eight-carrier correction, if needed, is covered by U4's anchors and parity.
- **Verification:** the design doc carries the dated outcome with the Codex CLI version and the exact evidence (log line or header), and the plan's iteration log points to it.

### U7. Decision entry D103 and removal of stale model text from the foundation

- **Goal:** `docs/foundation.md` records the per-host binding, the key rename and the peer resolution change as D103, and no longer names concrete model IDs or retired keys.
- **Requirements covered:** none; D44 (no concrete IDs in Ensemble's files).
- **Dependencies:** none
- **Files:**
  - `docs/foundation.md` (§4.1 new D103 after D102; §7.5 line 612; §13.4 lines 1055–1065; §13.5 line 1078)
  - `tests/lint/decision-log-order.test.sh` (only if it pins the last D number)
- **Approach:** Write D103 in the D100 style: what changed, the asymmetry stated (Claude binds per call, Codex per file at install time), the alias-to-tier derivation and why no new frontmatter field, the flat-key grammar, the `peer_*` rename with the one-release fallback, and "every peer-invoking skill resolves; only `/en-review` runs the ladder", amending D86 and D100 and the "select nothing on Codex" rule. Replace §7.5's `peer_model_codex` / `peer_model_claude` sentence and §13.4's example config with the current key set and alias-only values, and drop the two concrete IDs from §13.5, which today contradict the rule the same document states. `bin/ensemble-lint --scope docs/` stays clean.
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Ship scope:** in
- **Execution note:** pragmatic
- **Test expectation:** none — documentation; `tests/lint/decision-log-order.test.sh` and the docs lint are the guards.
- **Verification:** `bash tests/lint/decision-log-order.test.sh` green; `grep -n "gpt-5-codex-mini\|claude-sonnet-4-6\|peer_model_codex\|peer_model_claude" docs/foundation.md` returns nothing; `bin/ensemble-lint --scope docs/` clean.

### U8. Calibrate severity in the plan peer brief

- **Goal:** The peer's P1 means "would make `/en-build` build the wrong thing or fail a phase check", so the confidence gate separates apply-now from defer again.
- **Requirements covered:** none; G5, D49.
- **Dependencies:** none
- **Files:**
  - `skills/en-plan/references/peer-brief.md`
  - `tests/lint/en-plan-finalize-loop.test.sh` (new anchors)
- **Approach:** Add a "Severity on a plan" block to the brief, above the routing table: P0 is a plan `/en-build` must not run (destructive misclassified, phase invariant broken, a unit that cannot be implemented as written); P1 is a defect that changes what gets built or fails a phase check (a goal with no unit, a wrong `risk:`, a signature one unit produces and another consumes under a different name, a feature unit with no scenarios, a bet stated nowhere); P2 is consistency, naming, wording and cross-reference issues that do not change a signature another unit consumes; P3 is advisory. Severity is set by impact and evidence alone: no quota, no per-unit ratio, because a cap would demote real P1s and bias the counts U12 reads. Instead the brief asks the peer to deduplicate overlapping findings into one, to name in each P1 what would be built wrongly or which phase check would fail, and it tells the host to batch the apply edits per unit rather than one cycle per finding, so the cost of a pass is controlled without touching severity. The wire contract in `peer-contract.md` is unchanged; this is en-plan's policy, which is what the brief is for.
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Ship scope:** in
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* anchors: the brief contains "Severity on a plan", a P1 definition line naming `/en-build`, the deduplication sentence, and the per-unit batching instruction to the host; no line contains a numeric P1 quota.
  - *Edge case:* the block sits above the routing table (line order asserted with `grep -n`), so the peer reads the definition before the actions.
  - *Error / failure path:* negative control: delete the P1 definition line → the anchor test fails.
  - *Integration:* `ensemble-build-peer-prompt --brief peer-brief.md --artifact-stdin` output contains the new block verbatim (the builder injects the brief; a fenced example in the brief must not be mistaken for the block).
- **Verification:** `tests/lint/en-plan-finalize-loop.test.sh` green; U12 measures the effect.

### U9. `--research <path>`: hand prior research to `/en-plan`

- **Goal:** A user who already ran research in the session can pass it in, and `/en-plan` skips its own `repo-research` and `web-research` dispatch while recording that it did.
- **Requirements covered:** none; G10.
- **Dependencies:** none
- **Files:**
  - `skills/en-plan/SKILL.md` (step 6, the Flags table, the run report)
  - `skills/*/references/research-dispatch.md` (the en-plan rows and a short "user-supplied research" paragraph; all seven carriers edited together)
  - `tests/lint/en-plan-research-handoff.test.sh` (new)
- **Approach:** Step 6 gains a precondition: when `--research <path>` names a readable file, read it once, bounded to its first 200 lines with a note if longer, treat it as the repo and web research result, and dispatch neither agent; `learnings-research` keeps its own rule because it is cheap and reads a store the user's research did not. The plan's `## Decisions, assumptions & risks` gets an `Assumption:` bullet naming the file and date and stating the findings were not re-verified, and the run report prints `research: user-supplied (<path>)`. A missing or unreadable path is an error before any dispatch, not a silent fall-through to paid research. The dispatch matrix rows for en-plan gain a footnote pointing at the flag.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Ship scope:** in
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* anchors: the Flags table lists `--research <path>`; step 6 says both agents are skipped and `learnings-research` is not; the run report line `research: user-supplied` is named.
  - *Edge case:* the SKILL text bounds the read (the `200` figure is anchored) so a large dossier does not enter context whole.
  - *Error / failure path:* the SKILL text says an unreadable path stops before dispatch; anchored.
  - *Integration:* all seven `research-dispatch.md` carriers hash-equal after the edit (assert in the new test, same discovery pattern as agent-dispatch).
  - *Happy path (recorded run):* `/en-plan --research <file>` on a small request in this repo → the run report says `research: user-supplied (<path>)`, the session's dispatch record shows no `repo-research` and no `web-research` call, `learnings-research` still follows its own rule, and the written plan carries the `Assumption:` bullet naming the file and date. Once U11 has shipped, the same facts are read from the metrics file instead of the session record.
  - *Edge case (recorded run):* a 201-line research file whose line 201 is a sentinel string → the plan and report contain no trace of the sentinel and the report notes the truncation at 200 lines.
  - *Error / failure path (recorded run):* `--research /nonexistent` → the run stops with a message naming the path before any agent dispatch and before any question round.
- **Verification:** new test green; `tests/lint/en-plan-*.test.sh` green; the three recorded runs noted in the iteration log with their report lines.

### U10. Lint only the plan file inside the finalize loop

- **Goal:** Each apply pass lints one file in seconds, the promotion still lints the active directory once, and single-file scope is guarded to keep running the cross-link checks.
- **Requirements covered:** none; G13.
- **Dependencies:** none
- **Files:**
  - `skills/en-plan/SKILL.md` (step 16 apply bullet, step 17 "Validate first")
  - `tests/lint/lint-rules.test.sh` (single-file scope keeps cross-links)
  - `tests/lint/en-plan-test-scenarios.test.sh` (the `scope docs/plans/active` anchor)
- **Approach:** In the finalize loop, after each apply pass run `bin/ensemble-lint --scope <plan-path>`; keep the one `--scope docs/plans/active` run at promotion. The lint already accepts a file path and already runs `check_cross_links` per file, so no rule changes; add a test that a single-file scope still fires `cross-link.broken-r` for a bad R-ID, so nobody later gates that check on `docs/` the way the collision and index checks are. Time a single-file run and a directory run in this repo and record both in the iteration log; the design's 20-second target is recorded as a target, not asserted.
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* fixture plan citing an R-ID the foundation does not declare, linted with `--scope docs/plans/active/<file>.md` → `cross-link.broken-r` fires.
  - *Happy path:* the same fixture linted with the directory scope → the same finding, so both scopes agree.
  - *Edge case:* a single-file scope on a file outside `docs/plans/` (a design doc) still runs its per-file rules and exits with the same findings as the directory run.
  - *Error / failure path:* negative control: gate `check_cross_links` on `docs/` in a scratch copy of the lint → the new single-file assertion fails.
  - *Integration:* anchors: en-plan step 16 names `--scope <plan-path>`; step 17 still names `--scope docs/plans/active`.
- **Verification:** `tests/lint/lint-rules.test.sh` and the en-plan anchor tests green; timings recorded.

### U11. `ensemble-run-metrics`: record what a plan run can observe

- **Goal:** Each `/en-plan` run leaves a JSON file of agent dispatches, peer passes, lint runs and findings per severity per pass, so the next improvement pass has evidence without reconstructing a transcript.
- **Requirements covered:** none; G10.
- **Dependencies:** none
- **Interfaces:**
  - *Produces:* `ensemble-run-metrics start --plan <plan_id> [--run-id <id>]` (prints the file path), `ensemble-run-metrics event <file> --kind <dispatch|peer|lint|findings|note> --json '<object>'`, `ensemble-run-metrics finish <file>`. File: `$(git rev-parse --git-dir)/ensemble/runs/<plan_id>-<YYYYMMDDTHHMMSS>.json` with `{plan_id, started, finished, events:[...]}`. Exit 0 with a stderr note outside a git repo; never blocks the run.
- **Files:**
  - `skills/en-plan/scripts/ensemble-run-metrics` (new)
  - `skills/en-plan/SKILL.md` (steps 6, 16, 17, 20: the four call points and the one-line summary in the report)
  - `tests/lint/ensemble-run-metrics.test.sh` (new)
- **Approach:** Bash plus `jq` for appends, same dependency posture as `setup`. Events carry what the skill can see: for a dispatch, agent name, host, `AGENT_MODEL` and `AGENT_MODEL_SOURCE` from U3 when present, start and end epoch seconds; for a peer pass, the `peer_decision` object plus token counts when the CLI's JSON output includes them (Codex `--json` reports `token_count`; a Claude peer reports `usage`), otherwise `null`; for lint, scope and seconds; for findings, counts per severity per iteration. Compaction count and dollar cost are not observable and are not recorded, which the report line says. The report prints `metrics: <path> (N dispatches, M peer passes, K lint runs)`.
- **Risk:** low
- **Category:** observability
- **Reversibility:** trivial
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* `start` in a temp git repo creates the file under `.git/ensemble/runs/` with `plan_id` and `started`; two `event` calls append two objects in order; `finish` sets `finished`; `jq .` parses the result.
  - *Edge case:* `event` with a `--json` payload that is not an object → exit 0, stderr note, file unchanged.
  - *Error / failure path:* run outside a git repo → `start` prints nothing to stdout, one stderr line, exit 0; a subsequent `event ""` is a no-op.
  - *Integration:* anchors: SKILL.md names the helper at the four call points and the `metrics:` report line; the plan-hash helper does not cover any new frontmatter field (none is added).
- **Verification:** new test green; a `/en-plan` run in this repo leaves a parseable file (record its path in the iteration log).

### U12. Loop cap: gather two calibrated Deep-plan samples and record a decision

- **Goal:** Decide from evidence whether the Deep cap moves from one re-loop to two with a confirm-only third pass, or D49 stands.
- **Requirements covered:** none; D49.
- **Dependencies:** U8, U11
- **Files:**
  - `docs/designs/2026-09-07-agent-model-control-and-en-plan-cost-design.md` (a dated "Loop cap decision" note)
  - `skills/en-plan/SKILL.md` and `tests/lint/en-plan-finalize-loop.test.sh` only if the cap changes
- **Approach:** With U8 and U11 shipped, take the metrics files of the next two Deep `/en-plan` runs (this repo's or a consuming repo's) and read P1 counts per pass. Decision rule, written down before the samples: if the second pass returns three or more P1s on both runs, raise the Deep cap to two re-loops where the last pass is confirm-only, keep Standard at one and Lightweight at zero, and keep `--max-iterations` and `--no-reloop`; otherwise D49 stands and the note says why. Confirm-only restricts what the host does automatically, never what the peer may report: every severity stays reportable on that pass, a P0 still stops the run, an unresolved P1 still surfaces to the user at the cap-hit prompt, and only auto-apply is narrowed to P1 at confidence 9 or higher. A final pass can therefore never produce an approval-shaped result over a blocking defect. If the cap changes, the SKILL.md cap paragraph (lines 166 and 231) and the brief's "One verification pass at every depth" sentence change together, and the finalize-loop test's anchors follow.
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Ship scope:** deferred
- **Execution note:** pragmatic
- **Test scenarios:** (apply only if the cap changes; otherwise **Test expectation:** none — the deliverable is a recorded decision)
  - *Happy path:* anchors: the SKILL.md cap table names the Deep confirm-only pass and the line "every severity stays reportable".
  - *Error / failure path:* anchors: the confirm-only text says a P0 on the final pass stops the run and an unresolved P1 surfaces at the cap-hit prompt; negative control: delete the P0 sentence → the anchor test fails.
  - *Edge case:* anchors: auto-apply on the final pass is limited to `P1` at confidence `9` or higher, and the brief's "One verification pass at every depth" sentence is gone.
- **Verification:** the design doc carries the two samples (run ids, P1 per pass) and the decision; if the cap changed, `tests/lint/en-plan-finalize-loop.test.sh` green with the new text.

### U13. Reproduce the detached peer invoke under zsh and fix it if it fails

- **Goal:** `ensemble_peer_start` is proven to work, or fixed, when the sourcing shell is zsh.
- **Requirements covered:** none; D81.
- **Dependencies:** none
- **Files:**
  - `tests/portability/peer-detached-zsh.test.sh` (new)
  - `skills/en-plan/scripts/ensemble-peer-invoke` (only if the reproduction fails)
- **Approach:** The test skips with a note when `zsh` is absent. Otherwise it runs `zsh -c 'source ensemble-peer-invoke; ensemble_peer_start --job-dir "$D" --peer-cmd "sh -c '\''printf %s {\"verdict\":\"approve\",\"findings\":[]}'\''" --prompt-file "$P"'`, then `ensemble_peer_wait "$D" --max-secs 20` and `ensemble_peer_result "$D"`, and asserts `pid`, `started`, `exit` and a parseable `decision.json` appear. It runs the same sequence under `bash -c` as the control. If zsh fails, the fix is a re-exec of the detached body under `bash` from the sourcing shell (the file already resolves its own path for both shells), and the test then guards it. Either way the outcome, with the zsh version, is recorded in the design doc next to root cause 9.
- **Risk:** low
- **Category:** diagnostics
- **Reversibility:** trivial
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* under bash, `ensemble_peer_start` returns the job dir, `ensemble_peer_wait` prints `done`, `ensemble_peer_result` prints the decision JSON and exits 0.
  - *Happy path:* the same under `zsh -c`.
  - *Edge case:* a peer command that sleeps past `--max-secs` → `ensemble_peer_wait` prints `running` and exits 3 under both shells.
  - *Error / failure path:* `ensemble_peer_start` without `--job-dir` → exit 2 and the usage line under both shells.
- **Verification:** new portability test green on this machine (zsh present) and in CI (skips with a note if zsh is absent).

### U14. Reproduce the lint's `mktemp` failure under the sandbox and make the temp path explicit

- **Goal:** `bin/ensemble-lint` creates its temp files where the environment allows, and fails with a named error rather than an unbound-variable trace when it cannot.
- **Requirements covered:** none; G13.
- **Dependencies:** none
- **Files:**
  - `skills/en-setup/references/templates/ensemble-lint` and `bin/ensemble-lint` (identical; `mktemp` at lines 53, 411, 816)
  - `tests/lint/lint-rules.test.sh`
- **Approach:** Reproduce first: run the lint with `TMPDIR` pointing at a directory that does not exist, then at one that is read-only, then unset, inside and outside the Claude Code sandbox, and record which combination fails and how. Then replace the three bare `mktemp` calls with one `lint_mktemp` helper that tries `${TMPDIR:-/tmp}/ensemble-lint.XXXXXX`, falls back to `/tmp` with one stderr line, and exits non-zero with a message naming both paths when neither works. If the reproduction shows the sandbox failure had another cause, the helper still ships for the clear error, and the cause is recorded in the design doc next to root cause 8.
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* `TMPDIR` unset → lint completes with no stderr output and leaves no file behind in `/tmp` (the RETURN trap still cleans up).
  - *Edge case:* `TMPDIR=$T/nonexistent bash bin/ensemble-lint --scope <file>` → lint completes using `/tmp` and prints one stderr line about the fallback.
  - *Error / failure path:* `TMPDIR` read-only and the fallback root overridden to a read-only path by an env variable the test controls → non-zero exit with a message naming both paths, no bash unbound-variable trace.
  - *Integration:* `bin/ensemble-lint` and the template stay identical (`bin-template-sync`).
- **Verification:** `tests/lint/lint-rules.test.sh` and `bin-template-sync` green; the reproduction result recorded in the design doc.

## Decisions, assumptions & risks

- **Decision:** The tier is derived from the agent's `model:` alias (`haiku`, `sonnet`, `opus`) instead of a new `tier:` frontmatter field. The Claude loader's handling of unknown frontmatter keys is unverified, and an unregistered agent is the failure PR #85 just repaired; a three-row table in the resolver is the cheaper risk.
- **Decision:** Flat config keys with the host and tier in the name, chosen over teaching the reader nested keys. The YAML grammar is deliberately narrow and every existing key is flat.
- **Decision:** Byte-identical script copies per dispatching skill, guarded by a discovered-carrier parity test, over a single `bin/` install. A skill directory copied alone must still resolve everything it names (EN12).
- **Decision:** Metrics live under `.git/ensemble/runs/` beside the verification receipt: never committed, no `.gitignore` change, gone with the clone.
- **Decision:** `peer_*` replaces `review_peer_*` with legacy reads for one release; `review_host_model_alias` keeps its name because only review personas consume it.
- **Alternative:** A single `research_agent_model_alias` key (the design's approach B). Rejected in the revision: it covered one tier on one host and could not express Codex at all.
- **Alternative:** Compound Engineering's shape, where prompt assets have no frontmatter and the caller picks the tier. Rejected because Ensemble registers its agents with the host and wants the operator's setting on rung one of the host's own resolution order, not in prose.
- **Assumption:** Codex loads `~/.codex/agents/*.toml` with `name`, `description`, `developer_instructions`, `model`, `model_reasoning_effort` and inherits the parent model when `model` is unset, per the official subagents documentation read 2026-09-07. Not verified against a live spawn; U6 exists to verify it.
- **Assumption:** Codex `spawn_agent` has no per-call model parameter, so install time is the only binding point. If U6 finds one, U5's TOML model field becomes a default rather than the binding.
- **Assumption:** The `mktemp` failure under the Claude Code sandbox is `TMPDIR`-related. U14 reproduces before changing anything.
- **Assumption:** The detached-invoke failure under zsh is reproducible with a stub peer. U13 may find it was environmental, in which case the test still ships as the guard.
- **Risk:** Eight-way duplication drifts — **Mitigation:** the parity test discovers carriers by the presence of `agents/` and fails on any hash mismatch; the same test refuses a skill that dispatches agents without carrying the resolver.
- **Risk:** The rename strands operators who set `review_peer_*` by hand — **Mitigation:** legacy reads for one release, `setup` merge preserves unknown keys, the config example carries a migration comment, and the reader warns on unparseable JSON (PR #85).
- **Risk:** Passing `model` on every dispatch masks a frontmatter regression like EN14's — **Mitigation:** `AGENT_MODEL_SOURCE` is recorded in the metrics file, and the agent test now requires both loader fields.
- **Risk:** This plan touches more than 30 files, mostly byte-identical copies and reference carriers — **Mitigation:** the file set was surfaced at planning time and the user chose one plan; `/en-build` phases by risk, and U3 and U4 land as separate commits so a copy-set mistake reverts alone.

## Tracked debt

None resolved. If U6 finds Codex cannot spawn a custom agent by name from a skill, file a TD entry for Codex-host research dispatch with a back-reference to this plan.

## Iteration log

> - 2026-09-07 (peer pass 2, cross-agent codex, revise, cap hit): 1 P1 and 2 P2, all applied. Claude values validated against the alias set (U3); all nine tier keys in setup defaults (U3); TOML scalar escaping contract and round-trip fixture (U5). Iteration cap reached with `revise`; user asked whether to accept as-is.
> - 2026-09-07 (peer pass 1, cross-agent codex, revise): 4 P1 and 2 P2, all applied. Quota dropped from the brief (U8); U3 depends on U2; recorded-run scenarios on U9; confirm-only pass keeps every severity reportable (U12); setup binds Codex TOML from the global config only (U5, resolver gains `--global-only`); U10 split into U10 and new U14.
> - 2026-09-07 (initial): plan v0 from `docs/designs/2026-09-07-agent-model-control-and-en-plan-cost-design.md` (revision section) and repo research; round 1 settled one Deep plan, flat keys, `peer_*` rename keeping the host key; round 2 settled byte-identical copies per skill and `.git/ensemble/runs/` for metrics.

<!--
Resolution log lives in frontmatter (`peer_review_resolutions`). Each entry:

  - finding_id: <id from peer or auto-minted as `<iteration>-<index>`>
    iteration: <N>
    severity: P0 | P1 | P2 | P3
    title: <short title from peer>
    status: applied | deferred | disagreed | superseded
    rationale: <one-line reason; required for deferred/disagreed/superseded>
    location: <file:line or section name>
-->
