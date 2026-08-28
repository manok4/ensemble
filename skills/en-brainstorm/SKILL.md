---
name: en-brainstorm
description: "Explore an idea via Q&A, prior-art research, and 2-3 trade-off-aware approaches with a recommendation and devil's-advocate pass. Outputs a design doc to docs/designs/. Use before committing to a plan. Trigger phrases: 'brainstorm', 'explore options', 'think through', 'help me decide', 'what would it look like if', 'design doc for'."
argument-hint: "[idea or question to explore]"
# What this skill needs. Every path is skill-relative and must exist here.
# A skill is self-contained: nothing outside this directory is listed.
requires:
  - agents/web-research.md
  - references/agent-dispatch.md
  - references/brainstorm-approaches.md
  - references/brainstorm-blindspot.md
  - references/host-detect.md
  - references/recursion-guard.md
  - references/research-dispatch.md
  - references/script-invocation.md
  - references/socratic-questions.md
  - references/templates/design-doc-template.md
  - scripts/ensemble-detect-host
  - scripts/ensemble-lint

---


# `/en-brainstorm`

> **Running a bundled script.** Anchor every call to this skill's own directory: `SKILL_DIR="<absolute path of the directory containing this SKILL.md>"; bash "$SKILL_DIR/scripts/<name>"`. The trailing `;` is load-bearing. See `references/script-invocation.md`.


> **Dispatching a bundled agent.** This skill carries its agents in `agents/`. Dispatch by name as usual; when the name is not registered (a lone skill directory), resolve it from the bundled definition per `references/agent-dispatch.md`.


Lightweight idea-exploration skill. **No code written; no implementation; no peer review.** The point is to leave with clarity, not artifacts.

> **Priority principle (D39): performance > speed ≥ cost.** Optimize first for the quality of the brainstorm→plan outcome, then for speed, then for token/tool cost. The rigor steps below are self-gating, so simple work stays fast.

> Hard gate: this skill never edits source code, runs tests, opens PRs, or invokes implementation skills. Output is a design doc and a recommendation.

## Process

1. **Detect host.** Source `references/host-detect.md`. Brainstorm needs exactly two things from it: `$QUESTION_TOOL` (the Q&A step) and path conventions. No peer resolution — cross-review is off here.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, exit with note.
3. **Resume or start fresh.** Glob `docs/designs/*.md` for a doc with `status: open` whose topic matches this request (title, slug, or `topic:` frontmatter). If one matches, **confirm before resuming** — never auto-resume silently:
   > "Found an open design doc for [topic] (`<path>`, last touched <date>). Continue from it, or start fresh?"
   On resume: read it, summarize its settled decisions and still-open questions, treat those decisions as **already answered** (they never re-enter the frontier), and **update that file** rather than minting a duplicate. Preserve its `created:` and `topic:`. On start-fresh, leave the old doc untouched — the user may want both.
4. **Right-size depth.** Per the depth table below. Default **Standard**; when the framing is genuinely ambiguous, ask one question rather than guessing.
5. **Existing-context scan (bounded).** Read each source's *shape* first, then only the parts that match the topic. Never read a large artifact whole:
   - `docs/foundation.md` (if present) — read the frontmatter, then `grep -n '^#' docs/foundation.md` for the section index, then `sed -n '<start>,<end>p'` on the 1–2 sections matching the topic. **Never `cat` it whole**; it routinely runs past 2,000 lines.
   - `docs/learnings/index.md` — read the index only, then drill into at most 3 matching pages.
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
   - **Facts are yours to find, never the user's to supply.** A question whose answer sits in the environment — the repo, git history, a config file, a lockfile — is not put to the user. Look it up. When a frontier question needs a fact you don't have, dispatch a sub-agent to find it and **don't block on it**: a running lookup is an unsettled prerequisite, so only the questions *downstream of that fact* wait for it — ask the rest of the frontier now. Decisions stay with the user.
   - **Default to the host's blocking question tool** — `$QUESTION_TOOL` from host-detect (`AskUserQuestion` on Claude Code, `request_user_input` on Codex), with its built-in free-text fallback — for narrowing / single-select questions; well-chosen options scaffold the answer without confining it.
   - **Open-vs-closed discipline:** use an **open-ended** question only when the answer is inherently narrative, OR when you genuinely cannot write 3–4 distinct, plausibly-correct options without padding. The test: *if you'd be straining to fill the option slots, the question is open — ask it open-ended.*
   - **Harness fallback:** when no blocking question tool exists in the harness, fall back to numbered options in chat; never silently skip the question.
   - **Stop when the frontier is empty** — every branch visited, nothing left silently assumed — or when the depth budget is spent, whichever comes first. If the budget runs out with a live frontier, record the unasked decisions as **explicit assumptions** in the design doc rather than dropping them.
7. **Blindspot gate** (fires rarely; territory-scoped). If the user signals they **cannot evaluate** part of the territory — either flagged up front ("I know nothing about X") or shown by two consecutive can't-evaluate answers ("I don't know", "you decide") on questions needing domain judgment — the Q&A is extracting guesses, not requirements. Before the first substantive question *into that territory*, offer to map its decision surface first. **Read `references/brainstorm-blindspot.md` when this fires**; it owns the trigger test, the offer, the map, and re-entry. Guard against over-firing: a user who understands the options but hasn't picked one is *undecided*, not blindsided — keep interviewing. Never fire in a non-interactive run.
8. **Product pressure test** (self-gating). Before generating approaches, pressure-test whether the idea is real and well-framed. This is **internal analysis**: scan the opening and the dialogue so far for the rigor gaps catalogued in `references/socratic-questions.md` → "Product rigor gaps", and raise **only those that actually exist**, as **open-ended probes** folded into the conversation — never a menu, never a pre-flight checklist. A well-framed opening earns **zero** probes; one probe satisfies one gap. The gaps: **evidence**, **specificity**, **counterfactual**, **attachment**, and **durability** (Deep / strategic scope only). If a probe reveals genuine uncertainty, record it as an **explicit assumption** in the design doc rather than skipping it.
9. **Integration check.** Still before approaches: **combine** what the user has said with your own defaults and surface any non-obvious downstream consequence the one-question-at-a-time dialogue hasn't probed (*"if mute lives on the rule AND we don't warn on delete, then rule-delete silently loses pause state"*). Fire **one open-ended probe per genuine combination effect**, not a blanket audit.
10. **Probe budget.** The pressure test, the integration check, and any blindspot walk-through **count toward the depth question budget** — they add no separate quota. On **Lightweight**, fire **at most one** rigor/integration probe (the single highest-signal gap) and skip the rest; a Lightweight brainstorm must not become a rigor interrogation. Standard/Deep have room for one probe per genuine gap within the budget.
11. **Optional research.** Dispatch the `web-research` agent only if the user wants prior art OR external best practice would materially change the recommendation. Per `references/research-dispatch.md` this is `optional` for brainstorm; default skip on Lightweight, ask on Standard/Deep.
12. **Propose 2–3 approaches** with trade-offs. Each: sketch, pros, cons. Keep sketches short (one paragraph each). Approaches name mechanism or product shape, never implementation specifics — those belong to `/en-plan`.
    - **Divergent generation gate.** On **Deep**, or on **Standard with 3+ genuinely live directions**, generate the approaches through parallel constraint-diverged sub-agents rather than serially in this context — serial generation anchors, and B and C come back as variants of A. **Read `references/brainstorm-approaches.md` when this fires**; it owns the constraint table, the acceptance bar, and the no-sub-agent fallback.
    - Otherwise generate inline. When one approach is clearly best, skip the menu and say so.
13. **Recommendation.** Pick one. State the rationale in one paragraph.
14. **Devil's advocate.** Stress-test the recommendation. What would a senior engineer poke at? What changes in 6 months? What's the failure mode at 3am? What if the problem framing is wrong?
15. **Show synthesis to the user.** Confirm or iterate. One round usually suffices.
16. **Verify-before-claiming.** Before writing the doc, any claim that something is **absent** in the codebase — a missing table, an endpoint that doesn't exist, a dependency not installed, a config option with no current support — must be **verified against the repo** first (read the relevant source), or **explicitly labeled an unverified assumption** in the doc. Applies to any checkable infrastructure claim; it is not a full research pass — just don't assert absence you haven't checked.
17. **Write the design doc** to `docs/designs/YYYY-MM-DD-<topic>-design.md` using `references/templates/design-doc-template.md`. Status: `open`. Absence-claims that couldn't be verified go under the doc's assumptions, labeled as such (per the template).
18. **Validate before handing off.** Run `$SKILL_DIR/scripts/ensemble-lint --scope docs/designs` and fix anything it flags on the new file, re-running until clean. `/en-plan` consumes this doc; a malformed one propagates.
19. **Capture-from-synthesis reflex (D21).** If the conversation produced a non-obvious connection, an extracted lesson, or a comparison worth keeping, soft-prompt:
    > "This conversation produced [X]. Capture as a learning?"
    User accepts → invoke `/en-learn capture --from-conversation` with the design doc as input.
20. **Hand off.**
    - New product → `/en-foundation`
    - Feature in existing project → `/en-plan`
    - Just exploration, no immediate next step → wrap

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

## When to skip the design doc

For very small explorations where the user is iterating on a code-level question ("should this be a hook or a util?"), a design doc is overkill. Surface a soft offer:

> "This is a fairly small choice. Want a design doc, or just talk it through and proceed?"

If user picks "talk it through" → answer in chat; no file written, and the write/validate steps don't apply. The capture-from-synthesis reflex still fires if a learning emerges.

## Reference files

- `references/socratic-questions.md` — Q&A pool and the Product rigor gaps catalogue
- `references/research-dispatch.md` — when to use `web-research`
- `references/templates/design-doc-template.md` — output template
- `references/host-detect.md` — `$QUESTION_TOOL` and path conventions

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
| `docs/foundation.md` too large to scan cheaply | Section-index read only (step 4); never fall back to reading it whole. |
| `$SKILL_DIR/scripts/ensemble-lint` reports violations on the new design doc | Fix and re-run (the validate step); hand off only when clean. |
| User asks for code | Decline politely: "Brainstorm doesn't write code. Ready to hand off to `/en-plan`?" |
