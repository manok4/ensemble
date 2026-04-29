---
name: en-brainstorm
description: "Explore an idea, problem, or design choice through Q&A, research, and 2-3 trade-off-aware approaches with a recommendation and devil's-advocate stress test. Outputs a design doc to docs/designs/. Use whenever the user wants to think through something before committing to a plan: a new feature shape, an architectural choice, a refactor strategy, an exploratory technical decision, or a 'should we even build this?' question. Trigger phrases: 'brainstorm', 'explore', 'think through', 'help me decide', 'what would it look like if we', 'I'm trying to figure out', 'design doc for'."
---

# `/en-brainstorm`

Lightweight idea-exploration skill. **No code written; no implementation; no peer review.** The point is to leave with clarity, not artifacts.

> Hard gate: this skill never edits source code, runs tests, opens PRs, or invokes implementation skills. Output is a design doc and a recommendation.

## Process

1. **Detect host (light).** Source `references/host-detect.md` only if path conventions matter. No peer-review setup needed (cross-review is off by default).
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, exit with note.
3. **Right-size depth.** Lightweight (2–4 questions, 2 approaches), Standard (5–8 questions, 2–3 approaches), Deep (9–14 questions, 3 approaches with thorough trade-offs). Pick based on the user's framing; default Standard.
4. **Existing-context scan.** Read in parallel:
   - `docs/foundation.md` (if present) — orient on product context.
   - `docs/plans/active/` and `docs/plans/completed/` index — what's recent.
   - `docs/learnings/index.md` — what we've already learned about this area.
   - Recent commits (last ~30) — what's been on the user's mind.
   - Any related code paths the user mentioned.
5. **Q&A loop.** Pull questions from `references/socratic-questions.md`. **One per turn**, multiple-choice when natural. Stop when scope, constraints, and the riskiest assumption are clear.
6. **Optional research.** Dispatch `web-research` agent only if the user wants prior art OR external best practice would materially change the recommendation. Per `references/research-dispatch.md`, this is `optional` for brainstorm; default skip on Lightweight, ask on Standard/Deep.
7. **Propose 2–3 approaches** with trade-offs. Each: sketch, pros, cons. Keep sketches short (one paragraph each).
8. **Recommendation.** Pick one. State the rationale in one paragraph.
9. **Devil's advocate.** Stress-test the recommendation. What would a senior engineer poke at? What changes in 6 months? What's the failure mode at 3am? What if the problem framing is wrong?
10. **Show synthesis to the user.** Confirm or iterate. One round usually suffices.
11. **Write the design doc** to `docs/designs/YYYY-MM-DD-<topic>-design.md` using `references/templates/design-doc-template.md`. Status: `open`.
12. **Capture-from-synthesis reflex (D21).** If the conversation produced a non-obvious connection, an extracted lesson, or a comparison worth keeping, soft-prompt:
    > "This conversation produced [X]. Capture as a learning?"
    User accepts → invoke `/en-learn capture --from-conversation` with the design doc as input.
13. **Hand off.**
    - New product → `/en-foundation`
    - Feature in existing project → `/en-plan`
    - Just exploration, no immediate next step → wrap

## What never happens here

- No implementation.
- No PRD-style requirements (R-IDs are assigned by `/en-foundation`, not here).
- No detailed plan units (U-IDs are assigned by `/en-plan`).
- No code-touching commits.
- No cross-agent peer review (D4 — brainstorm is exploratory).

## Depth scaling — at a glance

| Depth | Q count | Approaches | Web research | Output |
|---|---|---|---|---|
| Lightweight | 2–4 | 2 | skip default | Short design doc (<100 lines) |
| Standard | 5–8 | 2–3 | ask | Standard design doc (100–250 lines) |
| Deep | 9–14 | 3 | ask | Long design doc (250–500 lines) |

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

If user picks "talk it through" → answer in chat; no file written. The capture-from-synthesis reflex still fires if a learning emerges.

## Reference files

- `references/socratic-questions.md` — Q&A pool
- `references/research-dispatch.md` — when to use `web-research`
- `references/templates/design-doc-template.md` — output template
- `references/host-detect.md` — light usage (path conventions only)

## Failure protocol

| Failure | Behavior |
|---|---|
| User abandons mid-conversation | No file written; chat history is its own record. |
| `web-research` agent fails | Note in design doc: "External research truncated due to fetch failure"; continue with internal context. |
| `learnings-research` finds many overlapping pages | Surface the top 3 with citations; offer to drop into the design doc instead of restating. |
| User asks for code | Decline politely: "Brainstorm doesn't write code. Ready to hand off to `/en-plan`?" |
