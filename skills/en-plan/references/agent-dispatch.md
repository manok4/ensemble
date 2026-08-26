# Dispatching a bundled agent

How a skill dispatches one of the agents in its own `agents/` directory.

## The normal path

Dispatch by name, the way you always have:

```
Agent(subagent_type: "repo-research", prompt: "…")
```

The host resolves that name from its flat agent registry, which `./setup`
populates from `skills/*/agents/*.md`. In a normal install every agent a skill
carries is registered, and this is the only path you need.

## When the name is not registered

A skill directory can arrive on its own: someone copies one skill into a host's
skills folder, or a converter ships a single skill as an isolated unit. There is
no host hook that registers an agent in that case, so `subagent_type:
"repo-research"` resolves to nothing.

The skill carries the definition, so resolve it yourself:

1. Read `agents/<name>.md` from this skill's directory.
2. Dispatch a general-purpose agent whose prompt is that file's body, with the
   task appended.
3. Treat the result exactly as you would the named agent's — same contract, same
   output shape. The definition is the same file the registry would have used.

Do this **only** after the named dispatch fails to resolve. When the agent is
registered, use the registry: falling back unconditionally would hide a broken
registry publish behind a path that happens to work.

## Why the copies exist at all

Without the fallback the bundled copies would be decoration — present in the
folder, read by nothing, since dispatch never consults a skill directory. The
fallback is what makes a lone skill directory actually able to do its work, and
it needs nothing outside that directory.
