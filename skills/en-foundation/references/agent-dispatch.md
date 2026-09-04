# Dispatching a bundled agent

**Dispatch by name:** `Agent(subagent_type: "<name>", …)`. The host resolves it
from the registry `./setup` populates from `skills/*/agents/*.md`. In a normal
install this is the only path.

**When the name does not resolve** — a lone skill directory, copied in on its own
with nothing to register it — read `agents/<name>.md` from this skill and dispatch
a general-purpose agent with that body as its prompt, task appended. Same
contract, same output shape: it is the file the registry would have used.

**Only after the named dispatch fails.** Falling back unconditionally would hide
a broken registry publish behind a path that happens to work. The fallback is
also why the bundled copies are not decoration — without it, a lone skill
directory carries agent definitions nothing can reach.

## Which model a bundled agent runs on

Three layers, the same separation `peer-model-policy.md` uses. **Policy** (this
table) owns the stable tier. **Binding** owns the per-host syntax. **Call sites**
omit any model override so the declaration, not the caller, decides.

| Tier | For | Ours |
|---|---|---|
| `retrieval` | find it, cite it, do not judge it | `repo-fact-lookup` |
| `evidence` | evidence-driven work and mechanical verification | `repo-research`, `learnings-research`, `web-research`, `code-simplifier` |
| `ceiling` | output is code, or a judgement the orchestrator would otherwise make itself | `dimension-reviewer` |

**The binding is Claude Code's, and only Claude Code's.** An agent's `model:`
frontmatter is read by Claude Code's agent loader, which maps the tier to a
model. `./setup` installs the same agent files into a Codex host too, where that
field names a model Codex cannot select.

**On Codex, take the default model and select nothing.** Not because the field
happens to be ignored there, but as the policy: Codex's model lineup is its own,
it moves on its own schedule, and a second mapping to maintain would be a second
thing to get wrong — D44's lesson about per-CLI literals, arriving by a different
road. The tier is still worth declaring, because it records which work is cheap
and which is expensive, and that is true of the agent whichever host runs it.

Never write a concrete model ID in either place. A model ID is a volatile CLI
literal, and D44 cost a whole plan when one was scattered across nine files.

The line that matters is the first row: an agent that **only retrieves** can run
cheaper than one that **decides**. `learnings-research` sits above that line and
arguably belongs below it — but a retrieval agent that starts mis-judging
`applies_when` fit degrades a plan silently, so move one down on measured
evidence, not on the shape of its description.
