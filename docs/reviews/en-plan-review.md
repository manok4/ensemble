# Skill review: `/en-plan`

- **Reviewed:** 2026-08-25
- **Target:** `skills/en-plan/SKILL.md` (284 lines) at `533d36e`
- **Axes:** effectiveness, latency, build-process streamlining
- **Benchmarks:** internal `en-brainstorm` (just revised), `en-build`; external `ce-plan`, `agent-skills/skills/engineering/to-spec`

---

## 1. Current performance summary

Same caveat as the `en-brainstorm` review: **no runtime telemetry exists.** Static measurement and structural analysis only.

### Context cost

| Loaded item | Bytes | ~tokens |
|---|---:|---:|
| `SKILL.md` | 30,110 | 7,527 |
| `templates/plan-template.md` | 17,754 | 4,438 |
| `outside-voice.md` | 16,614 | 4,153 |
| `host-detect.md` | 9,162 | 2,290 |
| `finding-schema.md` | 7,591 | 1,897 |
| `research-dispatch.md` | 6,985 | 1,746 |
| `stable-ids.md` | 4,632 | 1,158 |
| `severity.md` | 4,701 | 1,175 |
| `single-agent-fallback.md` | 4,037 | 1,009 |
| **Scaffolding subtotal** | **101,586** | **~25,400** |
| `docs/foundation.md` — R-IDs, unbounded | 205,161 | **~51,300** |
| `repo-research` + `learnings-research` | — | ~7,000–23,000 |
| **Standard run, pre-drafting** | | **~84,000–100,000** |

`en-plan` is the second-largest skill in the repo after `en-build` (432 lines), and carries the largest reference set.

### Latency profile

Two independent latency terms, and the bigger one is not tokens:

| Term | Cost |
|---|---|
| Planning questions (step 7) | 5 categories, **one per turn** → 5+ human round trips |
| Default-branch checkpoint (step 12) | 1 blocking prompt, can loop on `details` |
| Cap-hit prompt | 1 more when the peer loop caps out |
| **Peer finalize loop (step 14)** | **up to 3 full CLI subprocess passes** over a ~380-line plan (Standard/Deep cap = 2 re-loops) |

Research dispatch (step 6) is already **correctly parallel** — `repo-research` and `learnings-research` fire together. `en-plan` got this right where `en-brainstorm` had no parallelism at all.

### Drift-guard health

42 assertions, 0.15/skill-line — in line with `en-build` (0.16) and the recalibrated `en-brainstorm` (0.17). **No over-guarding problem here.**

---

## 2. Inefficiencies and improvement suggestions

### P1. Off-by-one step references send the peer-reject override into the wrong step

`SKILL.md:279`, failure protocol, peer-`reject`-override row:

> *"treat as approved: run **step 14** (compute hash, flip `status: draft → open`…) and continue to **step 15** (auto-commit)."*

But **step 14 is the Outside Voice review loop**; compute-hash-and-flip is **step 15**, and auto-commit is **step 16**. An agent following this instruction after a user overrides a peer rejection **re-enters peer review** instead of promoting the plan — on the exact path where the user has already said "proceed anyway."

`SKILL.md:201` has the same shift: *"auto-commits the plan file (per step 15)"* — auto-commit is step 16.

**Fix:** correct both, and **switch step cross-references to names** (`the status-flip step`, `the auto-commit step`). There are 10 numeric `step N` references across a 19-step process with a `11a` inserted mid-list; this class of bug bit twice during the `en-brainstorm` pass and it has now bitten here for real.

### P2. `foundation §17.4` does not exist in any project `/en-foundation` generates

`SKILL.md:53` tells the agent *"Bias toward boring tech — see foundation §17.4."* Section 17 is **Operating Philosophy** in *Ensemble's own* `docs/foundation.md`. The template that generates every user project's foundation (`references/templates/foundation-template.md`) has **14 sections**, ending at *14. Risks and Open Questions*. No §17 exists there.

The skill leaks its own repo's structure into guidance meant for all projects. **Fix:** state the principle inline (it is one clause) or cite the template's actual section.

### P3. The `foundation.md` read is unbounded — the same defect just fixed in `en-brainstorm`

Step 4 reads foundation *"pulling a requirement (R-ID)"*; step 9 needs *"R-IDs and AE-IDs from foundation"* per unit. Neither is bounded. On this repo that is ~51K tokens.

This is **easier to fix here than it was in brainstorm**, because the foundation template guarantees a stable heading: `## 5. Functional Requirements (R-IDs and Acceptance Examples)`. A bounded read is: frontmatter (for `plan_id_prefix`, which step 10 already does correctly) + section 5 + section 7 when tech direction matters.

### P4. Step 7 is a serial interview — the frontier-round fix already exists in this repo

Five planning questions asked **one per turn**. Architecture, file boundaries, test strategy, dependencies, and migrations are largely **independent** — they are a textbook frontier. `en-brainstorm` now has this mechanism, shipped and guarded (D47).

Note one genuine dependency to respect: file boundaries and test strategy both partly depend on the architecture answer, so architecture is round 1 and the rest is round 2. That is still **2 rounds instead of 5**.

### P5. Step 12 inlines 58 lines duplicating a 298-line spec

The default-branch checkpoint occupies `SKILL.md:86–143` (4,592 B, ~1,148 tok) — prompt text, three-source detection, four response handlers, a future-extension note — while `docs/en-plan-default-branch-spec.md` (298 lines) is the canonical source it points at. Every `en-plan` run pays for it, including the majority that are not on the default branch and skip the checkpoint entirely.

**Fix:** keep the trigger and the decision table inline (~8 lines); move the prompt, handlers, and diagnostics to a gated reference read only when the checkpoint actually fires.

### P6. `11a` repeats the numbering-fragility pattern

Step `11a` (pre-write plan-quality review) is a real, valuable step wedged into the numbering rather than given a number. Same shape as `en-brainstorm`'s old `5a/5b/10a`, which is what produced P1's class of bug. Renumber to a flat 1–20.

---

## 3. Benchmark comparison

| Dimension | `en-plan` | `en-brainstorm` (revised) | `en-build` | `ce-plan` | `to-spec` |
|---|---|---|---|---|---|
| SKILL lines | 284 | 132 | 432 | **60 (router)** | 75 |
| Reference lines | 8 shared, ~17.9K tok | 4 shared + 2 gated | 26 refs | **3,383, phase-gated** | 0 |
| Progressive disclosure | none — all refs load | partial (2 gated) | none | **full** | n/a |
| Research | **parallel ✓** | inline bounded | n/a | phase-gated | inline |
| Interview cadence | one per turn (5 Qs) | **frontier rounds** | n/a | one per turn | **none — "do NOT interview"** |
| Bounded large reads | **no** | **yes** | no | yes | n/a |
| Step cross-refs | **numeric (10, one wrong)** | by name | numeric | phase names | n/a |
| Assertion density | 0.15/line | 0.17/line | 0.16/line | none | none |

### Adoptable

**A1 — Frontier rounds for step 7** (from `en-brainstorm` D47, already in this repo). 5 round trips → 2. The mechanism, its dependency rule, and its guards are already written and tested; this is a port, not a design.

**A2 — Bounded foundation read** (from D47). Easier here than in brainstorm thanks to the template's stable section 5 heading.

**A3 — Name-based step cross-references** (from D47). P1 is the concrete cost of not having this.

**A4 — Gate step 12 behind a reference** (from `ce-plan`'s phase→"read first" table). ~1,150 tokens off every run; the checkpoint only fires when the user is actually on the default branch.

**A5 — `to-spec`'s no-interview posture, as a conditional.** `to-spec` opens with *"Do NOT interview the user; just synthesize what you already know."* `en-plan` always interviews, even when a `/en-brainstorm` design doc already answered architecture, scope, and trade-offs — which is precisely the handoff Ensemble is built around. **Suggestion:** when a matching design doc exists with `status: open|accepted`, treat its settled decisions as answered and ask only what the doc left open. This is the single biggest *streamlining* win across the brainstorm→plan seam, and it is exactly what `en-brainstorm`'s new resume step does within its own skill.

### A tension worth naming, not resolving

`to-spec` states: *"Do NOT include specific file paths or code snippets. They may end up being outdated very quickly."* `en-plan` step 9 **mandates** `**Files:** repo-relative paths` per unit.

These are genuinely opposed bets. `to-spec` writes specs into an issue tracker where they may sit for weeks; `en-plan` hands directly to `/en-build`, usually within the hour, and `en-build` needs the file list to scope units. **`en-plan` is right for its context** — but the risk is real for plans that sit in `active/` and go stale. Worth a staleness note rather than a change.

### Where `en-plan` leads

- **Parallel research dispatch** — the only Ensemble planning skill that does this.
- **The phase invariant check** (`SKILL.md:76`, `risk(V) <= risk(U)` across dependency edges) is a genuine structural check with a real consumer in `en-build`'s phase loop. Neither benchmark has anything comparable.
- **The finalize loop with same-finding-twice suppression** is more rigorous than `ce-plan`'s final review.
- **Gating discipline** (`SKILL.md:69`) — the "do NOT gate refactors/renames/tests" list, with the stated rationale that over-gating trains autopilot, is unusually well-reasoned.

---

## 4. What's overkill

Much less than in `en-brainstorm`. The guards are proportionate (0.15/line) and the per-unit metadata, while heavy at 15 fields, has a real consumer in `en-build`.

Two candidates:

- **Step 12's inline expansion** (P5) — the only clear one. A 58-line prompt flow duplicating a 298-line spec, paid on every run.
- **`SKILL.md:69`'s gating criteria** run ~330 words inline with the full qualify/don't-qualify lists, then point at `plan-template.md` for "the full criteria." Either the inline list is complete (drop the pointer) or it isn't (trim to the rule and keep the pointer). Currently it is both.

Explicitly **not** overkill: the phase invariant, the finalize loop, the per-unit metadata, the pre-write quality review.

---

## 5. Final recommendations

**Now — correctness, do first:**

| # | Change | Why |
|---|---|---|
| **P1** | Fix the two off-by-one step references; switch cross-refs to names | A real behavioral bug on the peer-reject-override path |
| **P2** | Remove the `foundation §17.4` citation | Points at a section no generated project has |
| **P6** | Renumber `11a` into a flat list | Removes the condition that produced P1 |

**Next — cost and latency (all three are ports of mechanisms already shipped in this repo):**

| # | Change | Effect |
|---|---|---|
| **P3 / A2** | Bounded foundation read | ~51K → ~3K tokens |
| **P4 / A1** | Frontier rounds for step 7 | 5 round trips → 2 |
| **A4 / P5** | Gate step 12 behind a reference | ~1,150 tokens off every run |

**Then — the streamlining win:**

| # | Change | Effect |
|---|---|---|
| **A5** | Consume an existing design doc instead of re-interviewing | Closes the brainstorm→plan seam; potentially removes round 1 entirely |

**Not recommended:** changing step 9's file-path requirement. The `to-spec` critique is valid in general and wrong for `en-plan`'s handoff distance.

**Not measured:** the peer finalize loop is the dominant wall-clock cost (up to 3 CLI subprocesses per plan) and nothing here reduces it. Whether the 2nd and 3rd passes earn their latency is an empirical question no data currently answers — the same eval-fixture gap flagged in the `en-brainstorm` review.

---

## 6. Applied (D48)

`./tests/run.sh` 57/57 green; `ensemble-lint --scope docs` exit 0.

### Correctness — four wrong references, not two

The review found two. A full audit of every `step N` in the file found **four**:

| Location | Said | Actually is |
|---|---|---|
| Failure protocol, peer-reject override | "run **step 14** (compute hash, flip status)" | step 14 = Outside Voice **review loop**; the flip is step 15 |
| same row | "continue to **step 15** (auto-commit)" | auto-commit is step 16 |
| `--resume` description | "`draft` until **step 11**" | step 11 = auto-increment plan number |
| `--from-legacy` | back-reference "handled in **step 12**" | step 12 = default-branch checkpoint; nothing there touches the legacy README |

Only the first was behaviour-changing, and it was the worst kind: overriding a peer rejection re-entered peer review instead of promoting the plan.

**All 13 step cross-references are now by name.** `11a` folded into a flat 1–20. A new guard fails the build on *any* numeric `step N` or non-sequential numbering — this is the third time numbering drift produced a defect in this repo, so it is now mechanically impossible.

Also fixed: the `foundation §17.4` citation (§17 exists only in Ensemble's own foundation; the template that generates user projects stops at 14 sections).

### Cost, latency, streamlining

| | Before | After |
|---|---:|---:|
| `foundation.md` read | ~51,300 tok (unbounded) | ~3,000 tok (frontmatter + section index + needed sections) |
| Planning-question round trips | 5 (one per turn) | **2 rounds** |
| Default-branch checkpoint | 58 lines inline, every run | gated reference (~919 tok), read only when it fires |
| `SKILL.md` | 30,110 B | 29,354 B |

**The prose reorganisation was near cost-neutral again** — 756 bytes, same as the `en-brainstorm` pass. The wins are the runtime read and the round trips, not the file size.

**Design-doc reuse:** a matching design doc with `status: open|accepted` now has its settled decisions carried into the plan rather than re-asked, with `## Assumptions & unverified claims` explicitly carved out as *not* settled, and `superseded` docs not carried at all. This closes the brainstorm→plan seam that `to-spec`'s no-interview posture pointed at.

### Guards

7 new (3 step-reference + 4 cost-contract), each negative-controlled. **NC1 reproduced the exact shipped bug** — rerouting the override back into the review loop — and the guard went red.

One existing guard (`en-plan-default-branch.test.sh`) failed when the checkpoint body moved. It was protecting real content, so it was **repointed at the combined contract (SKILL trigger + gated reference), not weakened** — all 28 assertions retained. It also caught a detail the extraction dropped: the report field name `default_branch_checkpoint:`, which was restored rather than removed from the guard.

### Not changed
Per-unit `Files:` paths stay required. `to-spec` argues specs should omit file paths as staleness bait; that is right for a spec sitting in a backlog and wrong here, where `/en-build` consumes the plan within the hour and its phase loop needs the file list.

**Still unaddressed:** the peer finalize loop remains the dominant wall-clock cost (up to 3 CLI subprocesses per plan). Nothing here reduces it, and no data says whether passes 2 and 3 earn their latency.
