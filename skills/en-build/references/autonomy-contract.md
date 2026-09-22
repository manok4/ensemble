# `/en-build` agent autonomy contract

> Read at the start of step 9. This is the contract governing the unit loop; the skill's flow
> points here rather than restating it.

`/en-build` is autonomous by design: the user authorized the work at plan time (peer-reviewed plan, `status: open`, hash recorded). After a unit commits, advance to the next immediately. **Do not pause** for confirmation, judgment, "natural checkpoint", "the next unit is bigger", "let me verify before continuing", or any reason not enumerated below.

## Scope of the contract

The contract governs **the inter-unit main loop**: the window from the start of step 9 through the end of step 10, before the `/en-learn` hand-off. **Steps 1-8 are NOT governed by this contract**; their prompts are pre-execution, about whether the build can sensibly start.

## Legitimate pause cases within the contract window (exhaustive within scope, no others permitted)

1. **Working tree dirty at branch setup** (step 5) — stash / commit / abort. *(outside the window)*
2. **Plan-review concerns surfaced at start** (step 7) — continue / pause / split. *(outside the window)*
3. **`risk: destructive` unit at step 9a** — typed `"run unit U<N>"`.
4. **`gated: true` unit at step 9a** — y/skip/abort.
5. **Failure protocol fires** — each row has its own handler.

## Anti-patterns (explicitly forbidden), each with its tell

- **Agent-initiated "checkpoint before bigger unit" pauses.** The plan was authored and peer-reviewed; complexity is not re-litigated at execution time. *The tell: the reason cites the next unit's size, not this unit's state.*
- **"Working tree is clean, paused for confirmation" between non-gated units.** A clean tree is the expected state between units. *The tell: the pause reports success and asks nothing answerable.*
- **"Should I continue?" preambles and "Let me verify with the user before …"** outside the five cases. *The tell: the question offers no option that changes what happens next.*

**Uncertainty is not a pause case: advance, not ask.** The verification gates and the failure protocol are the safety net. A real concern goes in the progress report as an informational `Note:` line, not a prompt.
