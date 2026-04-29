# Socratic questions — `en-brainstorm` Q&A library

A pool of well-formed questions for the brainstorm skill to draw from. **One question per turn; multiple-choice preferred where natural.**

## Scope and ambition

| Q | Use when |
|---|---|
| Is this a new product or a feature in an existing project? | First exchange, when the skill could go to either `/en-foundation` or `/en-plan` |
| What's the smallest version that's still valuable? | Risk: scope creep |
| Who's the user — primary, secondary, anyone? | Risk: solving the wrong problem |
| What's the deadline (real, not aspirational)? | Risk: over-engineering |

## Problem framing

| Q | Use when |
|---|---|
| What's the user trying to do that they can't do today? | Always early — grounds the conversation |
| What's the cost of doing nothing? | Risk: solution looking for a problem |
| What pain are existing solutions causing? | Helps surface differentiation |
| Have you seen this solved well anywhere? | Activates prior-art research |

## Constraints

| Q | Use when |
|---|---|
| What stack are we constrained to? | Tech choices on the table |
| Are there compliance or data-residency constraints? | Auth / data work |
| What's the production load profile? | Performance-relevant work |
| Any sacred cows — things we explicitly can't change? | Refactors and migrations |

## Approach exploration

| Q | Use when |
|---|---|
| If we did the simplest possible thing, what would it look like? | Baseline anchor |
| If we had unlimited time, what would the ambitious version be? | Upper bound on scope |
| What's the riskiest assumption? | Surfaces what to validate first |
| What's the part you're most uncertain about? | Surfaces hidden complexity |

## Trade-offs

| Q | Use when |
|---|---|
| Performance vs simplicity — which way do you lean here? | When the design has both fast-but-complex and slow-but-simple options |
| Batch or streaming? | Data-pipeline work |
| Synchronous or async? | Service-call work |
| Generic or specific? | API / library design |

## Research and prior art

| Q | Use when |
|---|---|
| Should I research how others solved this? (yes/no) | Before invoking `web-research` |
| Any specific tools or libraries to check? | When research would benefit from a starting point |
| Is there a learning in our store relevant to this? | Always — `learnings-research` runs unconditionally for Standard/Deep |

## Devil's advocate (devil's-advocate pass after recommendation)

| Q | Use when |
|---|---|
| What would a senior engineer poke at first? | Stress-test the recommendation |
| What changes in 6 months that breaks this design? | Risk: optimization for current state only |
| What if the user's actual workflow is different from what we assumed? | Risk: misread |
| What if this fails in production at 3am — what's the failure mode? | Operational angle |
| If we're wrong about the problem framing, what's the cost of throwing this away? | Risk: sunk cost |

## Decision-time

| Q | Use when |
|---|---|
| Which of these approaches do you want me to write up as the design? | After 2–3 approaches with trade-offs |
| Any modifications before I write the design doc? | Before final write |
| Should I capture a learning from this conversation? | At the end — D21 capture-from-synthesis |

## Question style guidelines

- **One per turn.** Don't bundle.
- **Multiple-choice when natural.** Open-ended when the answer is genuinely free-form.
- **Recommend a default.** Phrase as "Lean A or B?" with a brief why for each, not "What do you think?"
- **No "what should we do?" questions.** Decide a recommendation; ask the user to push back.
- **Skip rituals.** No "Are you ready to begin?" or "Let me know if you have questions" filler.

## Depth scaling

| Depth | Question count target |
|---|---|
| Lightweight | 2–4 |
| Standard | 5–8 |
| Deep | 9–14 |

When in doubt, lean Lightweight. Brainstorm output is exploratory, not load-bearing — over-questioning is more costly than the missed nuance.
