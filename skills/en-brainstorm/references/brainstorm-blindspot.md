# Blindspot pass — `en-brainstorm`, the blindspot gate

Read this only when the blindspot gate in `en-brainstorm` fires. Most brainstorms never reach it.

The Q&A assumes the user can evaluate what it asks. On territory the user doesn't know, that assumption fails and the interview extracts **guesses instead of requirements** — which then harden into a design doc and propagate into `/en-plan`. This pass converts unknown unknowns into known unknowns: it maps the decision surface of the flagged territory so the user chooses among options they can now evaluate.

A blindspot pass is a **decision map, not a tutorial.** Test every item: it must end in something the user will decide, delegate, or explicitly defer during this brainstorm. An item that feeds no decision is domain trivia — cut it.

## Trigger

Two signals arm the pass:

- **Opening signal** — the user flags missing working knowledge: "I know nothing about X", "never touched the auth modules", "I don't know what I should be asking".
- **Mid-dialogue signal** — two consecutive answers show the user **cannot evaluate** the question's substance: "I don't know", "whatever you think", "you decide" on questions that need domain judgment.

**Can't-evaluate vs hasn't-decided — the guard against over-firing.** A user who understands the options but hasn't picked one needs the normal Q&A, not a teaching pass. Fire only when the signal shows they cannot weigh the options at all. Offering this to someone who is merely undecided is the failure mode; when the signal is ambiguous, keep interviewing.

## The gate

**Territory-scoped, not conversation-wide.** Questions about the user's own problem, users, evidence, and priorities proceed normally — they are the authority on those. The gate fires only before the first substantive question *into the flagged territory*.

Never silently switch into teaching. The offer is a blocking question via `$QUESTION_TOOL`, asked **once per flagged territory**. If declined, do not re-offer for that territory — fill gaps with recommended defaults recorded as **explicit assumptions**, the same way rigor-probe uncertainty is recorded.

**Non-interactive degradation:** in a headless run where no user can answer, never fire the offer. Treat flagged territory exactly like a declined offer and continue.

## Offer

> Part of this sits in territory you've flagged as unfamiliar (<territory>). I can map the decision surface first — the decisions you'll face there, the realistic options for each, and what I'd default to — so you're choosing rather than guessing. Or we keep going with questions and I fill gaps with defaults recorded as assumptions.

Two options: **Map the territory first** / **Proceed with questions**.

## Building the map

Ground it before writing it:

- **In-repo territory** (a module, subsystem, or pattern in this codebase) — read the relevant source. Never map in-repo territory from model knowledge alone.
- **External domain** (a technology or practice outside the repo) — research it if `web-research` is reachable. When it isn't, model knowledge is allowed but each such item is labeled **"Unverified — from model knowledge, not checked against current sources."**

**The territory closes questions the user should never be asked.** Before an item goes on the map, check whether the codebase already answers it. If so it is not a decision — show the question and the found answer with its citation as **settled ground**, not as an option menu. A question closed off-screen isn't closed: territory-answered items are shown, never silently resolved.

While grounding, hunt hazards specifically: things that bite silently (wrong-by-default data, filters that pass bad rows), unwritten conventions the code enforces that no doc states, and half-built or reverted prior attempts at the same job — the reason a prior attempt died is usually the landmine.

The map is **3–7 items**, delivered in chat. Each is a **decision** the user will face or a **hazard** that constrains one, in at most 4 lines — an item running longer has started teaching; cut it back:

- what the decision or hazard is, **in the user's vocabulary**; when a term of art is unavoidable, define it and name what knowing it lets them decide
- why it matters **for this topic** — tie it to something the user said, not to the domain in general
- *decisions only:* the realistic options (2–4), one clause each on the trade-off that matters here. List only options you would defend. An option you ruled out belongs in why-it-matters as one clause, never in the menu
- *decisions only:* the recommended default, stated plainly

A **hazard is not a vote** — no option menu, no default. When a hazard forces a choice among genuinely viable mitigations, that choice becomes its own decision item and the hazard is its why-it-matters.

Order by how much the user's answer would change the product shape: shape-changing decisions first, hazards and reversible choices last. The highest-stakes item earns first placement, not extra length. Do not pad to 7 — a territory with three real decisions gets three items.

## Re-entering the Q&A

After the map, ask **one** multi-select blocking question: *"Which of these do you want to walk through now? Anything unselected takes the recommended default, recorded as an explicit assumption."*

Then:

- **Selected decisions** — walk through one per turn as informed single-select menus. Post-pass, menus over mapped options are the right form **even where the frontier rounds' open-vs-closed discipline would normally prefer open-ended**: the options no longer steer, they recall what was just mapped.
- **Unselected decisions and hazards** — record the recommended default (or the hazard's constraint) as an explicit assumption in the design doc.

## Budget

The map itself is not questions and costs no budget. The re-entry multi-select and each selected walk-through **count toward the depth question budget**, exactly like rigor probes — they add no separate quota. If the budget is spent before the selected items are walked, the remainder take their recommended defaults as explicit assumptions.

The pass never resolves decisions by itself and never replaces the Q&A. It runs **once**, converts blindspots into questions the user can answer, and the normal flow — frontier rounds, rigor probes, approaches — continues on informed ground.
