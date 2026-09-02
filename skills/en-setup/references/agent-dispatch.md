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

Each agent declares a **tier alias** in its own frontmatter — never a concrete
model ID, which is a volatile CLI literal for the reason `peer-model-policy.md`
gives. The dispatching skill inherits that declaration and does not restate it.

| Tier | For | Ours |
|---|---|---|
| cheapest capable | retrieval and quoting — find it, cite it, do not judge it | (none today) |
| mid | evidence-driven work and mechanical verification | `repo-research`, `learnings-research`, `web-research`, `dimension-reviewer` |
| ceiling | work whose output is code, or a judgement the orchestrator would otherwise make itself | `code-simplifier` |

The line that matters is the first one: an agent that **only retrieves** can run
cheaper than one that **decides**. `learnings-research` sits above that line today
and arguably belongs below it — but a retrieval agent that starts mis-judging
`applies_when` fit degrades a plan silently, so move one down on measured
evidence, not on the shape of its description.
