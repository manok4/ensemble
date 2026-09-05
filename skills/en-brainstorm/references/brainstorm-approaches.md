# Divergent approach generation — `en-brainstorm`, the approaches step

Read this only when the divergent-generation gate in `en-brainstorm`'s approaches step fires. On the default path (one clearly-best direction, or a Lightweight run) generate approaches inline and skip this file.

Adapted from the "Design It Twice" pattern (Ousterhout, via `agent-skills/skills/engineering/codebase-design`): your first idea is unlikely to be the best, and approaches generated **serially in one context** converge — B and C become variations of A because the same context anchored all three.

## When this fires

- **Deep** depth, or
- **Standard** depth with **3+ genuinely live directions** still on the table after the Q&A.

Skip when one approach is clearly best. A menu padded with options you would not defend is a strawman, not a choice — say so and state the recommendation directly.

## The mechanism

Dispatch one read-only sub-agent **per constraint, in parallel**, and do not idle while they run: draft the devil's-advocate questions and the recommendation's rationale skeleton meanwhile, then collect. Each gets the same brief and a **different** constraint, so the divergence is structural rather than a matter of asking nicely for variety.

**The brief** (identical for every agent): what the user is trying to do, the constraints and context gathered in the Q&A, the facts established by the frontier rounds' fact lookups (with `file:line` where they exist), and what has already been ruled out and why.

**The constraints** (one per agent):

| Agent | Constraint |
|---|---|
| 1 | **Smallest thing that works.** Minimize new surface. Reuse what already exists, even if the fit is imperfect. |
| 2 | **Invert the default.** Take the assumption the framing treats as settled and do the opposite. |
| 3 | **Optimize the common case.** Make the frequent path trivial; accept real cost on the rare one. |
| 4 *(Deep only)* | **Remove the binding constraint.** Assume the thing being treated as fixed is not. Say what it would take. |

**Each agent returns, and nothing else:** the approach in one paragraph (mechanism or product shape, not architecture); pros; cons; the key risk or unknown; and when it is best suited.

**Budget.** Roughly 8 reads, spent against the dossier and the files the brief names rather than re-scanning the repo, and about 200 words back. These agents are generating from a brief you already assembled; an agent that goes looking for its own grounding is doing the frontier rounds' job again, more expensively and with less context.

## Granularity bar

Approaches name **mechanism / product-shape** distinctions ("pause as a rule property" vs "pause as an event filter" vs "pause as a separate entity") and the trade-offs that matter at that level. They do **not** name implementation specifics — table names, column names, file paths, service classes, method names. Those belong to `/en-plan`. Bringing architecture forward here forces the user to decide it on brainstorm's deliberately-shallow research.

## Acceptance bar

Every returned approach must clear this before it reaches the user:

- **Anti-genericness.** If the approach would appear in a generic listicle for this problem category, it is not an approach — sharpen it against what the Q&A actually established, or drop it.
- **Defensible.** You would stand behind it if the user picked it.
- **Distinct.** Two agents that converged on the same shape yield **one** approach, not two. Say that they converged — independent convergence is evidence, and worth telling the user.

Fewer, sharper approaches beat filling the slots. Three agents returning two real approaches is a good outcome.

## Presenting

Present all approaches **before** the recommendation — leading with the recommendation anchors the choice before the user has seen the alternatives. Then recommend one, in one paragraph, and say plainly where each rejected approach lost. If elements combine well, propose the hybrid and name which agent's idea each part came from.

## Fallback — no sub-agent capability

When the host cannot dispatch sub-agents, generate the approaches **serially against the same constraint table**, writing each one out fully before reading the next constraint. This recovers some of the divergence but not the independence; note in the design doc that approaches were generated serially.

## Bounds

- Sub-agents here are **read-only idea generators**. They never write files, never edit code, and never invoke other skills — `en-brainstorm`'s hard gate binds them.
- They do not re-enter `/en-brainstorm`; the recursion guard applies.
- Dispatch is capped at 4. This is idea generation, not a search.
