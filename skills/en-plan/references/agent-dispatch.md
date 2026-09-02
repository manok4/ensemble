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
