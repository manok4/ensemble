# Before writing the plan

Read at the pre-write plan-quality review, and again by the write step for the warranted-file gate.

## The five checks

- **Test-scenario completeness.** Every **feature-bearing** unit enumerates real scenarios with concrete inputs and outcomes. Blank, or fewer than two, is **incomplete**: strengthen it, or switch to `**Test expectation:** none — <reason>` when the unit is genuinely non-feature. Mirrors the `unit.test-scenarios` lint (P2 advisory) so plans reach peer review already clean.
- **Decisions / assumptions / risks capture.** A non-obvious decision, a rejected alternative, an inferred assumption the plan bets on, or a genuine risk goes in `## Decisions, assumptions & risks` rather than burying it in unit `Approach:` fields. **Omit the section entirely** when nothing substantive surfaced.
- **Technical-design load-bearing audit (self-gating).** Count the architecture-complexity triggers: **≥3 new/changed components**, a **≥3-step protocol/handshake**, a **state machine**, **≥3 data-flow stages**, **DSL / public-API design**. Any trigger fired means the plan MUST carry a plan-level `## Technical design` section, directional and not a spec. Verify the section is present when a trigger fired; a missing section with a fired trigger is **incomplete**. No trigger, no section: it must not be added as boilerplate.
- **Name and signature consistency.** Walk the `Interfaces:` blocks and every name one unit's `Approach:` gives another. A function called `clearLayers()` in U3 and `clearFullLayers()` in U7 is a defect the plan hands straight to the worker, which implements what the plan says and produces a call to something that does not exist. Same for parameter order, return shapes and field names. Fix in place; one read of the plan catches the whole class.
- **No placeholders.** Plan failures, not shorthand, because a worker cannot resolve them: "TBD", "handle edge cases", "add appropriate error handling", "similar to U3" (the implementer holds one unit block, not the plan), "write tests for the above" with no scenarios, or a reference to a type or function no unit defines.

## Is a plan file warranted?

The design-doc condition is not about size: the no-file path never reaches the promotion that closes a consumed design out, so it would leave that design `status: open` forever and back in `/en-brainstorm`'s resume pool.

> "This is one low-risk change. I can write it up as a plan, or just tell you the change and you make it. A plan file buys peer review and a `/en-build` run; for a change this size that may cost more than it returns."

If they take the no-file path, state the change concretely and stop: **no file, no U-IDs, no peer review, and `/en-build` is not available** for it, since `/en-build` consumes a plan file and there will not be one. Say that plainly rather than implying a handoff that cannot happen.

**Never offer the skip** when the work touches a risk surface — authentication, payments, migrations, external contracts — however small it looks. Those are exactly the one-unit changes that earn a written plan and a peer pass.
