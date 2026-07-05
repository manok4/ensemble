---
name: en-brainstorm
description: "Explore an idea via Q&A, prior-art research, and 2-3 trade-off-aware approaches with a recommendation and devil's-advocate pass. Outputs a design doc to docs/designs/. Use before committing to a plan. Trigger phrases: 'brainstorm', 'explore options', 'think through', 'help me decide', 'what would it look like if', 'design doc for'."
---

> **Helper resolution.** All `references/X` and `bin/Y` paths in this skill resolve relative to `$ENSEMBLE_ROOT` — the install root (skill at `$ENSEMBLE_ROOT/skills/<name>/`, shared helpers at `$ENSEMBLE_ROOT/{references,bin}/`). Compute once at start: `$ENSEMBLE_ROOT` env var if set; otherwise `$(realpath "$(dirname <this-SKILL.md>)/../..")`. Fail loudly if `$ENSEMBLE_ROOT/references/host-detect.md` does not resolve — that indicates a partial install (run `/en-setup` to repair).


# `/en-brainstorm`

Lightweight idea-exploration skill. **No code written; no implementation; no peer review.** The point is to leave with clarity, not artifacts.

> **Priority principle (D39): performance > speed ≥ cost.** Optimize first for the quality of the brainstorm→plan outcome (does the resulting plan build the right thing well), then for speed, then for token/tool cost. The rigor upgrades below (pressure test, integration check, verify-before-claiming) spend a little time up front because a sharper design doc pays for itself many times over downstream — but each is self-gating so simple work stays fast.

> Hard gate: this skill never edits source code, runs tests, opens PRs, or invokes implementation skills. Output is a design doc and a recommendation.

## Process

1. **Detect host (light).** Source `$ENSEMBLE_ROOT/references/host-detect.md` only if path conventions matter. No peer-review setup needed (cross-review is off by default).
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, exit with note.
3. **Right-size depth.** Lightweight (2–4 questions, 2 approaches), Standard (5–8 questions, 2–3 approaches), Deep (9–14 questions, 3 approaches with thorough trade-offs). Pick based on the user's framing; default Standard.
4. **Existing-context scan.** Read in parallel:
   - `docs/foundation.md` (if present) — orient on product context.
   - `docs/plans/active/` and `docs/plans/completed/` index — what's recent.
   - `docs/learnings/index.md` — what we've already learned about this area.
   - Recent commits (last ~30) — what's been on the user's mind.
   - Any related code paths the user mentioned.
5. **Q&A loop.** Pull questions from `$ENSEMBLE_ROOT/references/socratic-questions.md`. **One question per turn.** Stop when scope, constraints, and the riskiest assumption are clear.
   - **Default to `AskUserQuestion`** (the platform's blocking question tool, with its built-in free-text fallback) for narrowing / single-select questions — well-chosen options scaffold the answer without confining it. (Ensemble already uses `AskUserQuestion` in en-resolve-pr / en-simplify / en-debug.)
   - **Open-vs-closed discipline:** use an **open-ended** question only when the answer is inherently narrative, OR when you genuinely cannot write 3–4 distinct, plausibly-correct options without padding. The test: *if you'd be straining to fill the option slots, the question is open — ask it open-ended.* (The Product pressure test's rigor probes are always open-ended by design.)
   - **Harness fallback:** when no blocking question tool exists in the harness, fall back to numbered options in chat — never silently skip the question.
5a. **Product pressure test** (self-gating; adapted from `ce-brainstorm`). Before generating approaches, don't just interview — pressure-test whether the idea is real and well-framed. This is **internal analysis**: scan the opening and the dialogue so far for the product-rigor gaps below, and raise **only those that actually exist** as **open-ended probes folded into the conversation** — never a pre-flight checklist. A well-framed opening earns **zero** probes; one probe satisfies one gap. The gaps (full phrasing in `$ENSEMBLE_ROOT/references/socratic-questions.md` → "Product rigor gaps"):
   - **Evidence gap** — the opening asserts a want but points to nothing anyone has already *done* about it. Probe: what's the most concrete thing someone's already done — paid for it, built a workaround, quit a tool over it?
   - **Specificity gap** — the beneficiary is described too abstractly to design for. Probe: name a specific person or narrow segment, and what changes for them when this ships.
   - **Counterfactual gap** — it's not visible what users do today, or what happens if nothing ships. Probe: what's the current workaround, even if messy — and what does it cost them?
   - **Attachment gap** — a particular solution *shape* is treated as the thing, not the value it delivers. Probe: what's the smallest version that still delivers real value?
   - **Durability gap** (**Deep / strategic scope only**) — the value rests on a current state of the world that may shift. Probe: how does it fare under the most plausible near-term shifts? (Push past rising-tide answers every competitor could give.)
   Why open-ended, not a menu: a menu signals which evidence "counts" and lets the user pick rather than produce; an open probe forces real observation or surfaces real uncertainty. If a probe reveals genuine uncertainty, record it as an **explicit assumption** in the design doc rather than skipping it. Reflects the priority principle (performance first): a few sharp probes here materially lift plan quality downstream, at trivial cost.
5b. **Integration check** (adapted from `ce-brainstorm`). Before approaches, mentally **combine** what the user has said with your own defaults and surface any non-obvious downstream consequence the one-question-at-a-time dialogue hasn't probed. When user-stated X + user-stated Y + your-default-Z produces an effect the user is unlikely to have tracked (*"if mute lives on the rule AND we don't warn on delete, then rule-delete silently loses pause state"*), probe it now — **one open-ended probe per genuine combination effect**, not a blanket audit. This runs **before approaches**, which is what distinguishes it from the devil's-advocate pass (step 9, **after** the recommendation): the integration check catches cross-cutting effects while they can still shape which approaches you generate.
6. **Optional research.** Dispatch `web-research` agent only if the user wants prior art OR external best practice would materially change the recommendation. Per `$ENSEMBLE_ROOT/references/research-dispatch.md`, this is `optional` for brainstorm; default skip on Lightweight, ask on Standard/Deep.
7. **Propose 2–3 approaches** with trade-offs. Each: sketch, pros, cons. Keep sketches short (one paragraph each).
8. **Recommendation.** Pick one. State the rationale in one paragraph.
9. **Devil's advocate.** Stress-test the recommendation. What would a senior engineer poke at? What changes in 6 months? What's the failure mode at 3am? What if the problem framing is wrong?
10. **Show synthesis to the user.** Confirm or iterate. One round usually suffices.
10a. **Verify-before-claiming** (adapted from `ce-brainstorm`; lightweight rule, not a verifier sub-agent). Before writing the doc, any claim that something is **absent** in the codebase — a missing table, an endpoint that doesn't exist, a dependency not installed, a config option with no current support — must be **verified against the repo first** (read the relevant source), or **explicitly labeled an unverified assumption** in the doc. This prevents the design doc from baking in a wrong premise that `/en-plan` then inherits. Applies to any checkable infrastructure claim; it is not a full research pass, just don't assert absence you haven't checked.
11. **Write the design doc** to `docs/designs/YYYY-MM-DD-<topic>-design.md` using `$ENSEMBLE_ROOT/references/templates/design-doc-template.md`. Status: `open`. Absence-claims that couldn't be verified go under the doc's assumptions, labeled as such (per the template).
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

- `$ENSEMBLE_ROOT/references/socratic-questions.md` — Q&A pool
- `$ENSEMBLE_ROOT/references/research-dispatch.md` — when to use `web-research`
- `$ENSEMBLE_ROOT/references/templates/design-doc-template.md` — output template
- `$ENSEMBLE_ROOT/references/host-detect.md` — light usage (path conventions only)

## Failure protocol

| Failure | Behavior |
|---|---|
| User abandons mid-conversation | No file written; chat history is its own record. |
| `web-research` agent fails | Note in design doc: "External research truncated due to fetch failure"; continue with internal context. |
| `learnings-research` finds many overlapping pages | Surface the top 3 with citations; offer to drop into the design doc instead of restating. |
| User asks for code | Decline politely: "Brainstorm doesn't write code. Ready to hand off to `/en-plan`?" |
