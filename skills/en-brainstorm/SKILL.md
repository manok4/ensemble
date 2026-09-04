---
name: en-brainstorm
description: "Explore an idea via Q&A, prior-art research, and 2-3 trade-off-aware approaches with a recommendation and devil's-advocate pass. Outputs a design doc to docs/designs/. Use before committing to a plan. Trigger phrases: 'brainstorm', 'explore options', 'think through', 'help me decide', 'what would it look like if', 'design doc for'."
---


# `/en-brainstorm`

> **Dispatching a bundled agent.** This skill carries its agents in `agents/`. Dispatch by name as usual; when the name is not registered (a lone skill directory), resolve it from the bundled definition per `references/agent-dispatch.md`.


Lightweight idea-exploration skill. **No code written; no implementation; no peer review.** The point is to leave with clarity, not artifacts.

> **Priority principle (D39): performance > speed ≥ cost.** Optimize first for the quality of the brainstorm→plan outcome, then for speed, then for token/tool cost. The rigor steps below are self-gating, so simple work stays fast.

> Hard gate: this skill never edits source code, runs tests, opens PRs, or invokes implementation skills. Output is a design doc and a recommendation.

## Process

1. **Resolve the question tool.** `$QUESTION_TOOL` is `AskUserQuestion` on Claude Code (a deferred tool; preload it via `ToolSearch`) and `request_user_input` on Codex. That is all this skill needs from the host: it has no peer, dispatches no CLI subprocess, and runs no host-detection script.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, this is a peer subprocess; exit with a one-line note.
3. **Resume or start fresh.** Glob `docs/designs/*.md` for a doc with `status: open` whose topic matches this request (title, slug, or `topic:` frontmatter). If one matches, **confirm before resuming** — never auto-resume silently:
   > "Found an open design doc for [topic] (`<path>`, last touched <date>). Continue from it, or start fresh?"
   On resume: read it, summarize its settled decisions and still-open questions, treat those decisions as **already answered** (they never re-enter the frontier), and **update that file** rather than minting a duplicate. Preserve its `created:` and `topic:`. On start-fresh, leave the old doc untouched — the user may want both.

   **The candidate pool is self-pruning; don't work around it.** `/en-plan` closes a design out to `accepted` or `superseded` when a plan built from it opens, so designs already acted on drop out of this glob on their own. What stays `open` is what genuinely is: explorations no plan was ever built from. If this scan starts returning a large ambiguous set, the close-out has stopped running somewhere upstream — say so rather than narrowing the glob here.
4. **Right-size depth.** Per the depth table below. Default **Standard**; when the framing is genuinely ambiguous, ask one question rather than guessing.
5. **Existing-context scan (bounded).** Read each source's *shape* first, then only the parts that match the topic. Never read a large artifact whole:
   - `docs/foundation.md` (if present) — read the frontmatter, then `grep -n '^#' docs/foundation.md` for the section index, then `sed -n '<start>,<end>p'` on the 1–2 sections matching the topic. **Never `cat` it whole**; it routinely runs past 2,000 lines.
   - `docs/learnings/index.md` — read the index only, then drill into at most 3 matching pages.
   - `docs/CONTEXT.md` (if present) — the project glossary. Read the term headings, then the entries that touch the topic. This is what the conflict gate below checks against.
   - `docs/plans/active/` and `docs/plans/completed/` — filenames only, unless one matches the topic.
   - Recent commits — `git log --oneline -30`.
   - Any code paths the user named.
6. **Q&A — frontier rounds.** Pull questions from `references/socratic-questions.md`. Model the open decisions as a **design tree**: every decision branches into the decisions that hang off it. The **frontier** is every decision whose prerequisites are already settled — the questions you can ask *now* without guessing at answers you haven't heard yet.
   - **Standard / Deep — ask the whole frontier in one round.** Number each question and give your **recommended answer** for each, so a round is "confirm these, correct the ones I got wrong" rather than "answer these". Then wait. The user's answers reshape the tree: settled decisions push the frontier outward and unblock what depended on them. Recompute the frontier and ask the next round.
     - **The dependency rule is what makes batching safe:** a question whose answer depends on another question still open **in this round** belongs to a *later* round, never this one. Stacking dependent questions is what produces diluted answers; an independent frontier does not.
     - Round format:
       ```
       ❓ **Q1 — <short title>**: <question, options inline if natural>
       ➡️ **Recommend:** <your answer, with the one-clause why>
       ```
   - **Lightweight — one question per turn.** A 2–4 question budget doesn't need a tree.
   - **Rigor probes stay one per turn** (the pressure test and integration check), on every depth. They are deliberately open-ended; folding them into a numbered round with a recommended answer flattens exactly what they exist to elicit.
   - **Facts are yours to find, never the user's to supply.** A question whose answer sits in the environment, the repo, git history, a config file, a lockfile, is not put to the user. Look it up: a one-file fact directly, anything wider by dispatching the `repo-fact-lookup` agent with the specific questions. It owns the read budget and the `file:line`-or-`absent` return, so the dialogue carries the answer and the evidence stays on disk. Decisions stay with the user.
   - **Don't block on it.** A running lookup is an unsettled prerequisite, so only the questions *downstream of that fact* wait for it. Ask the rest of the frontier now, and read the answer when it lands.
   - **Conflict gate: challenge terms against the glossary.** If the user uses a term that conflicts with an entry in `docs/CONTEXT.md`, or uses one of its terms to mean something else, put the conflict to them before treating their wording as settled: *"CONTEXT.md defines <term> as A; you seem to mean B. Which is it?"* Then use the canonical name in the dialogue, the approaches, and the design doc, so `/en-plan` inherits one vocabulary rather than two.
   - **Never write the glossary here.** `/en-learn` owns `docs/CONTEXT.md`. Capturing a term mid-dialogue captures the wrong name often enough to matter: the canonical term is frequently the thing the recommendation renames. Surface the conflict, settle it in conversation, and let the capture reflex file it after the doc is written.
   - **Stress-test boundaries with an invented scenario.** When the dialogue turns on how two concepts relate, asking about the relationship in the abstract gets an abstract answer back. Invent a specific case sitting on the boundary and ask what happens to it: *"a rule is muted, then deleted, then recreated with the same filter — is it muted?"* A scenario does work a definition request cannot, because the user answers it from how they think about the product rather than from vocabulary they may not have yet. Reach for it where the concepts are new or where a boundary is where the design would leak, not on every relationship.
   - **Default to the host's blocking question tool** — `$QUESTION_TOOL` as resolved at the start (`AskUserQuestion` on Claude Code, `request_user_input` on Codex), with its built-in free-text fallback — for narrowing / single-select questions; well-chosen options scaffold the answer without confining it.
   - **Open-vs-closed discipline:** use an **open-ended** question only when the answer is inherently narrative, OR when you genuinely cannot write 3–4 distinct, plausibly-correct options without padding. The test: *if you'd be straining to fill the option slots, the question is open — ask it open-ended.*
   - **Harness fallback:** when no blocking question tool exists in the harness, fall back to numbered options in chat; never silently skip the question.
   - **Stop when the frontier is empty** — every branch visited, nothing left silently assumed — or when the depth budget is spent, whichever comes first. If the budget runs out with a live frontier, record the unasked decisions as **explicit assumptions** in the design doc rather than dropping them.
7. **Blindspot gate** (fires rarely; territory-scoped). If the user signals they **cannot evaluate** part of the territory — either flagged up front ("I know nothing about X") or shown by two consecutive can't-evaluate answers ("I don't know", "you decide") on questions needing domain judgment — the Q&A is extracting guesses, not requirements. Before the first substantive question *into that territory*, offer to map its decision surface first. **Read `references/brainstorm-blindspot.md` when this fires**; it owns the trigger test, the offer, the map, and re-entry. Guard against over-firing: a user who understands the options but hasn't picked one is *undecided*, not blindsided — keep interviewing. Never fire in a non-interactive run.
8. **Product pressure test** (self-gating). Before generating approaches, pressure-test whether the idea is real and well-framed. This is **internal analysis**: scan the opening and the dialogue so far for the rigor gaps catalogued in `references/socratic-questions.md` → "Product rigor gaps", and raise **only those that actually exist**, as **open-ended probes** folded into the conversation — never a menu, never a pre-flight checklist. A well-framed opening earns **zero** probes; one probe satisfies one gap. The gaps: **evidence**, **specificity**, **counterfactual**, **attachment**, and **durability** (Deep / strategic scope only). If a probe reveals genuine uncertainty, record it as an **explicit assumption** in the design doc rather than skipping it.
9. **Integration check.** Still before approaches: **combine** what the user has said with your own defaults and surface any non-obvious downstream consequence the one-question-at-a-time dialogue hasn't probed (*"if mute lives on the rule AND we don't warn on delete, then rule-delete silently loses pause state"*). Fire **one open-ended probe per genuine combination effect**, not a blanket audit.

   **Probe budget** (governs all three probe steps: the blindspot walk-through, the pressure test, and this one). They **count toward the depth question budget**; they add no separate quota. On **Lightweight**, fire **at most one** rigor/integration probe, the single highest-signal gap, and skip the rest: a Lightweight brainstorm must not become a rigor interrogation. Standard/Deep have room for one probe per genuine gap within the budget.
10. **Optional research.** Dispatch the `web-research` agent only if the user wants prior art OR external best practice would materially change the recommendation. Per `references/research-dispatch.md` this is `optional` for brainstorm; default skip on Lightweight, ask on Standard/Deep.
11. **Propose 2–3 approaches** with trade-offs. Each: sketch, pros, cons. Keep sketches short (one paragraph each). Approaches name mechanism or product shape, never implementation specifics — those belong to `/en-plan`.
    - **Divergent generation gate.** On **Deep**, or on **Standard with 3+ genuinely live directions**, generate the approaches through parallel constraint-diverged sub-agents rather than serially in this context — serial generation anchors, and B and C come back as variants of A. **Read `references/brainstorm-approaches.md` when this fires**; it owns the constraint table, the acceptance bar, and the no-sub-agent fallback.
    - Otherwise generate inline. When one approach is clearly best, skip the menu and say so.
12. **Recommendation.** Pick one. State the rationale in one paragraph.
13. **Devil's advocate.** Stress-test the recommendation. What would a senior engineer poke at? What changes in 6 months? What's the failure mode at 3am? What if the problem framing is wrong?
14. **Show synthesis to the user.** They agreed to many things one at a time and have never seen the whole. This is their last chance to correct scope before the doc lands, so it is a **shape-confirmation checkpoint, not a preview of the document**.

    **Draft internally, present selectively.** First list, for yourself, everything the dialogue settled: what the user stated, what you inferred to fill gaps, and what you deliberately excluded. That draft is for your completeness. Do not paste it. A comprehensive audit is too much for anyone to actually weigh in on, which is the failure this two-stage split exists to prevent.

    **Present up to four sections. Omit any section with nothing to say; never pad one to fill it.**

    1. **What we're building** (always) — 1–3 sentences, forward-looking, plain words. Not a transcript of "you said X".
    2. **Key trade-offs** — only choices the user weighed alternatives on, or structural calls they would expect to see named. A mechanical or inevitable choice fails the test.
    3. **Not in scope** — only deferrals a downstream reader would ask about. "No rate limiting, it wasn't in scope" fails.
    4. **Call-outs** — residual forks the dialogue left open: a scope bet you made silently, or a consequence of combining their answers that they could not have tracked one question at a time. **The affirmability test: if the user would have to read code to judge it, it is doc-body content, not a call-out.**

    **Bullet budget**, sections 2–4 combined:

    | Depth | Typical | Ceiling |
    |---|---|---|
    | Lightweight | 0–1 | 2 |
    | Standard | 2–4 | 5 |
    | Deep | 3–6 | 8 |

    Over the ceiling the synthesis is misshapen: **do not raise the cap, re-cut at a higher level.** Related bullets are usually sub-decisions of one decision the user actually weighs. Read them aloud; two that sound like "and also" extensions of each other are one bullet. A bullet is one line, two at most — meeting the count by writing paragraphs defeats the point of the count.

    **Cut** anything that restates a Q&A turn, re-states the approach they already picked, or names a choice that had no real alternative.

    **Lightweight with no blocking questions announces; everything else confirms.** On that one path, state what we're building and continue in the same turn. Otherwise ask for confirmation explicitly, even when no call-outs survived.

    **A revision is not a confirmation.** When the user changes something, integrate it, re-present the revised synthesis, and wait again. Writing straight after a revision because the change felt small is how an unconfirmed synthesis reaches the file.

    **Soft-cut on circularity, not on round count.** Revising different things across rounds is the mechanism working: keep going. When the **same decision** is revised twice, stop and ask whether to proceed and write or keep discussing. Track it by decision, not by wording or section — the same call often returns rephrased, merged, or moved.

    **Verify-before-claiming — dispatch it here, not at the write.** In the same turn the synthesis goes up, dispatch the `repo-fact-lookup` agent with every claim the doc will make that something is **absent** in the codebase: a missing table, an endpoint that doesn't exist, a dependency not installed, a config option with no current support. It runs while the user reads, which is the only idle time in the flow, and returns a per-claim verdict: **confirmed** with a `file:line`, **refuted** with the contradicting evidence, or **unverifiable**. Do not block the confirmation on it.

    Skip the dispatch when the doc will make no absence-claims, or when no sub-agent is available; then verify inline before the write instead. The rule holds either way; only where it runs changes.
15. **Write the design doc.** Two preconditions run first. The first can end the step; the second constrains what goes in the file.

    **Is a doc warranted?** For a very small exploration where the user is iterating on a code-level question ("should this be a hook or a util?"), a design doc is overkill. Surface a soft offer:

    > "This is a fairly small choice. Want a design doc, or just talk it through and proceed?"

    If they pick "talk it through", answer in chat and stop here: no file, and the validate step below does not apply. The capture reflex still fires if a learning emerges.

    **Consume the verification verdicts.** Every absence-claim in the doc must be **verified against the repo** or **explicitly labeled an unverified assumption**. Correct refuted claims before writing; label unverifiable ones as assumptions. A claim that never reached the verifier is unverified, not true. This applies to any checkable infrastructure claim. It is not a full research pass; just don't assert absence you haven't checked.

    Then write to `docs/designs/YYYY-MM-DD-<topic>-design.md` using `references/templates/design-doc-template.md`. Status: `open`. Absence-claims that couldn't be verified go under the doc's assumptions, labeled as such (per the template).
16. **Validate before handing off.** Run `bin/ensemble-lint --scope docs/designs` and fix anything it flags on the new file, re-running until clean. `/en-plan` consumes this doc; a malformed one propagates.
17. **Capture-from-synthesis reflex (D21).** If the conversation produced a non-obvious connection, an extracted lesson, or a comparison worth keeping, soft-prompt:
    > "This conversation produced [X]. Capture as a learning?"
    User accepts → invoke `/en-learn capture --from-conversation` with the design doc as input.
18. **Hand off.**
    - New product → `/en-foundation`
    - Feature in existing project → `/en-plan`
    - Just exploration, no immediate next step → wrap

## Red flags

Every gate below is one an agent talks itself out of, and the talking-out is
predictable enough to name. If you catch yourself thinking the left column, the
right column is what is actually true.

| Thought | Reality |
|---|---|
| "One approach is clearly best, I'll skip the menu" | Allowed, but only when you would defend having no alternative. Reaching for the shortcut because generating three is work is the tell that you have not found the second one yet. |
| "This is Deep, but I can already see the approaches" | Seeing them in one context is exactly what the divergent gate distrusts. B and C thought up after A come back as variants of A. |
| "I'm fairly sure that table doesn't exist" | Fairly sure *is* the unverified assumption. Read the source, or label it as one in the doc. Absence is the claim that propagates into `/en-plan` as fact. |
| "They said 'you decide', that's the blindspot signal" | Once is undecided. The gate needs two consecutive can't-evaluate answers on questions needing domain judgment. Firing on an undecided user turns the interview into a lecture. |
| "They're busy, I'll ask the whole list this round" | Batching the *frontier* is cheap; batching dependents is what dilutes answers. A question whose answer depends on another still open this round belongs to the next one. |
| "It's a small choice, writing the doc is easier than asking" | The offer costs one line; the file costs a review and joins the resume pool. Make the offer. |
| "The design doc is nearly right, lint can wait" | `/en-plan` consumes this file. A malformed one propagates into the plan, and the person who finds it is downstream of everyone who could have fixed it cheaply. |

## What never happens here

- No implementation.
- No PRD-style requirements (R-IDs are assigned by `/en-foundation`, not here).
- No detailed plan units (U-IDs are assigned by `/en-plan`).
- No code-touching commits.
- No cross-agent peer review (D4 — brainstorm is exploratory).

## Depth scaling

Canonical. The right-size-depth and probe-budget steps both resolve against this table; nothing else restates these numbers.

| Depth | Q budget | Asking cadence | Approaches | Web research | Output |
|---|---|---|---|---|---|
| Lightweight | 2–4 | one per turn | 2 (inline) | skip default | Short design doc (<100 lines) |
| Standard | 5–8 | frontier rounds (~2–3 rounds) | 2–3 (divergent if 3+ live directions) | ask | Standard design doc (100–250 lines) |
| Deep | 9–14 | frontier rounds (~3–4 rounds) | 3 (divergent) | ask | Long design doc (250–500 lines) |

## Output format

After the Q&A and synthesis, the design doc lands at `docs/designs/YYYY-MM-DD-<topic>-design.md`. The skill ends with a short summary in chat:

```
Design doc: docs/designs/2026-04-28-cross-agent-review-architecture-design.md

Recommendation: Approach B (subprocess-based with single-agent fallback).
Devil's advocate flagged: same-model bias in fallback mode; cost on large artifacts.

Next: /en-foundation if this is a new product, /en-plan for a feature in an existing project.
```

## Reference files

- `references/socratic-questions.md` — Q&A pool and the Product rigor gaps catalogue
- `references/research-dispatch.md` — when to use `web-research`
- `references/templates/design-doc-template.md` — output template

Gated — read only when their step's gate fires, never up front:

- `references/brainstorm-blindspot.md` — the blindspot pass (most runs never load it)
- `references/brainstorm-approaches.md` — divergent approach generation (Deep, or Standard with 3+ live directions)

## Failure protocol

| Failure | Behavior |
|---|---|
| User abandons mid-conversation | No file written; chat history is its own record. A doc already written with `status: open` is picked up by the resume step next time. |
| Resume candidate is ambiguous (several open docs match) | List them with dates and ask which; never guess, never merge two. |
| Approach sub-agents fail or are unavailable | Fall back to serial generation against the same constraint table; note in the design doc that approaches were generated serially. |
| Two approach sub-agents converge on the same shape | Report one approach, and say they converged independently — that is evidence, not a wasted slot. |
| Blindspot gate fires in a non-interactive run | Never offer; treat the territory as a declined offer (recommended defaults recorded as explicit assumptions). |
| `web-research` agent fails | Note in design doc: "External research truncated due to fetch failure"; continue with internal context. |
| `docs/foundation.md` too large to scan cheaply | Section-index read only (the bounded existing-context scan); never fall back to reading it whole. |
| `bin/ensemble-lint` reports violations on the new design doc | Fix and re-run (the validate step); hand off only when clean. |
| User's response to the synthesis says they are in the wrong skill ("this is too small, just build it") | Stop. Name the skill they seem to want and offer the hand-off. Do not argue: the synthesis is an honest checkpoint, and discovering the wrong skill by reading it is the mechanism working. |
| Same synthesis item revised a third time after the soft-cut | Treat the soft-cut's "keep discussing" as spent; surface that the scope is not converging and ask what is actually unresolved. |
| User asks for code | Decline politely: "Brainstorm doesn't write code. Ready to hand off to `/en-plan`?" |
