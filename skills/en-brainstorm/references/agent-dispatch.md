# Dispatching a bundled agent

**Resolve the model first.** `eval "$($SKILL_DIR/scripts/ensemble-agent-model --agent <name> --host "$HOST" --agent-file "$SKILL_DIR/agents/<name>.md")"` answers which model and effort the agent runs on for this operator: a per-agent override for the host, then the operator's value for the agent's tier, then the file's own `model:`, then inherit (D103). It reads the flat keys through the sibling `scripts/ensemble-config-get` and emits `AGENT_TIER`, `AGENT_MODEL`, `AGENT_EFFORT` and `AGENT_MODEL_SOURCE`. Both dispatch paths below pass `model: $AGENT_MODEL` when it is non-empty, so the same value reaches the agent whichever path ran.

**Dispatch by name:** `Agent(subagent_type: "<name>", model: $AGENT_MODEL, …)`. The host resolves the name from the registry `./setup` populates from `skills/*/agents/*.md`. In a normal install this is the only path.

**When the name does not resolve** — a lone skill directory, copied in on its own with nothing to register it — read `agents/<name>.md` from this skill and dispatch a general-purpose agent with that body as its prompt, task appended, and `$AGENT_MODEL` as the Agent tool's `model` parameter. Same contract, same output shape: it is the file the registry would have used, and its tier is part of that contract. A general-purpose dispatch with no `model` argument inherits the session model, the most expensive tier, reached by omission; the resolver returns the file's own alias when the operator set nothing, so this path never dispatches bare.

**Only after the named dispatch fails.** Falling back unconditionally would hide a broken registry publish behind a path that happens to work. The fallback is also why the bundled copies are not decoration — without it, a lone skill directory carries agent definitions nothing can reach.

## Which model a bundled agent runs on

Three layers, the same separation `peer-model-policy.md` uses. **Policy** (this table) owns the stable tier. **Binding** owns the per-host syntax. **Call sites** pass what the resolver returns and choose nothing themselves: with no operator key set the resolver returns the declaration, so the declaration still decides by default, and with one set the operator decides, never the caller. `/en-review` reads `review_host_model_alias` first for its personas and lets the resolver decide when it is unset. Effort has no per-call parameter on Claude Code; an agent that needs one declares `effort:` in its frontmatter, and a repo overrides it with a project-level copy under `.claude/agents/` (D100).

| Tier | For | Ours |
|---|---|---|
| `retrieval` | find it, cite it, do not judge it | `repo-fact-lookup` |
| `evidence` | evidence-driven work and mechanical verification | `repo-research`, `learnings-research`, `web-research`, `code-simplifier` |
| `ceiling` | output is code, or a judgement the orchestrator would otherwise make itself | `dimension-reviewer` |

**Two hosts, two binding times.** The `model:` frontmatter is read by the agent loader of only Claude Code, which also takes a per-call `model`, so on Claude Code the resolver's value binds at every dispatch, on the first rung of the host's own resolution order. Codex binds per agent file: it reads `~/.codex/agents/<name>.toml`, selects nothing per call, and never read the markdown `./setup` used to place there. So `./setup` renders that TOML from the markdown, with `model` and `model_reasoning_effort` from the same resolver run as `--host codex --global-only`, bound from `~/.ensemble/config.json` alone; an operator's Codex choice takes effect on the next `./setup`, and a repo that wants a different Codex model for one agent uses Codex's own project scope, `.codex/agents/<name>.toml` (D103). A Codex session passes no model to `spawn_agent`, and as of Codex 0.153.2 it cannot select a custom agent either: `spawn_agent` takes `task_name`, `fork_turns` and `message` only, the child carries no agent role, and it inherits the parent's model and effort (EN16 U6, reproduced 2026-09-08 with a project-scoped `repo-research.toml` naming another model; the child ran on the parent's). Until the spawn tool gains a selector, a Codex session runs a bundled agent by handing its body to `spawn_agent` or inline, and the rendered TOML's `model` is an operator default for Codex's own agent picker, not a binding Ensemble can rely on (TD11).

Never write a concrete model ID in either place. A model ID is a volatile CLI literal, and D44 cost a whole plan when one was scattered across nine files; Claude values are aliases and Codex values live in the operator's config.

The line that matters is the first row: an agent that **only retrieves** can run
cheaper than one that **decides**. `learnings-research` sits above that line and
arguably belongs below it — but a retrieval agent that starts mis-judging
`applies_when` fit degrades a plan silently, so move one down on measured
evidence, not on the shape of its description.
