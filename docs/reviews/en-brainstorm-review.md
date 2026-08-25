# Skill review: `/en-brainstorm`

- **Reviewed:** 2026-08-25
- **Target:** `skills/en-brainstorm/SKILL.md` (107 lines) at `a56a869`
- **Evaluation axes (user-set):** skill effectiveness, latency, build-process streamlining
- **Benchmarks:** internal `en-plan`, `en-foundation`; external `compound-engineering-plugin/skills/ce-brainstorm`, `agent-skills/skills/skills/engineering/codebase-design`

---

## 1. Current performance summary

**There is no runtime telemetry for this skill.** No `docs/designs/` directory exists in this repo, there are no run logs, and there is no eval suite. Every number below is a static measurement or a structural count, not an observed run. Anything about real-world outcome quality is untested.

### Drift-guard health (measured)

| Test file | Assertions | Result |
|---|---|---|
| `en-brainstorm-elicitation.test.sh` | 6 | pass |
| `en-brainstorm-integration-verify.test.sh` | 6 | pass |
| `en-brainstorm-pressure-test.test.sh` | 10 | pass |
| `en-brainstorm-priority-principle.test.sh` | 6 | pass |
| **Total** | **28** | **28/28 pass** |

All four call `report` at the end, so they are genuine gates, not silent always-pass shells.

### Context cost of one Standard run (measured, this repo)

| Loaded item | Bytes | ~tokens (÷4) |
|---|---:|---:|
| `SKILL.md` | 11,592 | 2,900 |
| `references/socratic-questions.md` | 6,054 | 1,510 |
| `references/research-dispatch.md` | 6,571 | 1,640 |
| `references/templates/design-doc-template.md` | 3,811 | 950 |
| `references/host-detect.md` | 9,162 | 2,290 |
| **Skill scaffolding subtotal** | **37,190** | **9,300** |
| `docs/foundation.md` — step 4, unbounded read | 205,161 | **51,300** |
| **Total before the first question** | **242,351** | **~60,600** |

**85% of the pre-dialogue context is a single unbounded file read.** That is the headline efficiency finding.

### Latency profile

Latency here is dominated by **blocking-question round trips**, not tokens. Each question is a full model turn plus human think-time.

| Depth | Question budget | Sub-agent dispatches | Parallelism |
|---|---|---|---|
| Lightweight | 2–4 | 0 (research skipped) | none |
| Standard | 5–8 | 0–1 (`web-research`, on request) | none |
| Deep | 9–14 | 0–1 (`web-research`, on request) | none |

Step 4 says "Read in parallel" but those are host-context file reads, not concurrent agents; there is no wall-clock saving. The skill has **no parallel work anywhere** — `web-research` is the only sub-agent it can dispatch, and it is optional.

Credit where due: folding the 5a rigor probes and 5b integration probes **into** the depth budget rather than adding a separate quota is the right call, and the Lightweight cap of one probe keeps small work cheap.

### Effectiveness (structural read, not measured)

Strong: the three EN05/D39 rigor lenses (pressure test, integration check, verify-before-claiming) are well-specified, self-gating, and each has a clear "fires only when the gap exists" trigger. The open-vs-closed elicitation discipline is sharper than either benchmark's equivalent.

Weak: approach generation, resume, unknown-territory handling, and write-time validation — detailed below.

---

## 2. Inefficiencies and improvement suggestions

### B1. Unbounded `docs/foundation.md` read — ~51K tokens on this repo
Step 4 (`SKILL.md:23`) says *"Read `docs/foundation.md` (if present) — orient on product context"* with no bound. `docs/foundation.md` here is 205,161 bytes / 2,047 lines. No bounded-read guidance exists in this skill or `en-plan`.

**Fix:** replace with a two-stage bounded read — frontmatter plus `grep -n '^#'` for the section index, then targeted `sed -n` on the 1–2 sections that match the topic. Estimated ~1–2K tokens instead of ~51K. (Do *not* reach for a scout-dossier agent here without a deliberate decision: D39 explicitly rejected the async grounding-scout dossier.)

### B2. `host-detect.md` is conditionally instructed but unconditionally required
Step 1 (`SKILL.md:19`) says source it *"only if path conventions matter."* Step 5 (`SKILL.md:29`) then requires `$QUESTION_TOOL`, which is defined only in `references/host-detect.md:18`. An agent that follows step 1 literally and decides paths don't matter arrives at step 5 with no question tool.

**Fix:** either state plainly that brainstorm always needs it, or better — brainstorm uses exactly one row of a 179-line file built for peer-review host resolution. Extract a small question-tool stanza (`$QUESTION_TOOL` + fallback rule) that brainstorm and the other `$QUESTION_TOOL` consumers can load instead of the full 2,290-token file.

### B3. Three-way drift on `learnings-research` — the skill never dispatches it
- `references/research-dispatch.md:18-19` — matrix says **always** for `en-brainstorm` Standard and Deep.
- `references/socratic-questions.md:70` — *"`learnings-research` runs unconditionally for Standard/Deep."*
- `SKILL.md:106` — failure protocol has a `learnings-research` row.
- The agent's own registry description names `en-brainstorm` as a dispatcher.
- **But `SKILL.md`'s Process never dispatches it.** Step 4 reads `docs/learnings/index.md` inline instead; step 6 dispatches only `web-research`.

No drift test guards this. **Fix:** pick one and make the other three match. Recommendation: actually dispatch it (fast, 2–8K budget, returns a gist rather than the raw index) and drop the inline `index.md` read from step 4; then add a drift test, since three documents already disagree.

### B4. Duplicated content in the always-load path
The five rigor gaps are stated in full in `SKILL.md:32-39` (2,527 B) *and* `socratic-questions.md:23-35` (1,497 B). The open-vs-closed discipline appears at `SKILL.md:30` and `socratic-questions.md:94`. The depth table appears in both files. Roughly 1,000 tokens of pure restatement on every run, and two places to drift apart.

**Fix, with a caveat:** `en-brainstorm-pressure-test.test.sh:50-59` deliberately requires all five **gap names** in *both* files; only the full probe **phrasings** (lines 71–75) are required in `socratic-questions.md` alone. So `SKILL.md` can safely drop the probe phrasings and keep the names + the trigger + the budget rule. Trimming further needs the test updated first, not bypassed.

### B5. The two depth defaults contradict each other
`SKILL.md:21` — *"default Standard."* `socratic-questions.md:107` — *"When in doubt, lean Lightweight."* These are opposed instructions on the same decision, in two files loaded in the same run. (`ce-brainstorm` resolves it a third way: *"when it stays uncertain, take the heavier tier."*)

**Fix:** keep "default Standard" and rewrite the `socratic-questions.md` line to match. The rigor lenses are self-gating, so Standard does not over-tax a small idea — the Lightweight lean was written before the lenses existed.

### B6. No write-time validation of the design doc
`bin/ensemble-lint` already validates `docs/designs/*.md` (`bin/ensemble-lint:146` and `:347` — frontmatter schema and the `open|accepted|superseded` status enum), and `design-doc-template.md:104-111` documents those rules as if they run. But `en-brainstorm` never invokes the linter; `en-plan`, `en-review`, `en-setup`, and `en-sweep` all do. A malformed design doc is only caught much later, if ever — and `/en-plan` consumes it in between.

**Fix:** one line at step 11 — run `bin/ensemble-lint` on the written file, fix and re-check. Near-zero cost, closes a real gap on the brainstorm → plan handoff.

### B7. Stale reference paths in `docs/foundation.md`
`docs/foundation.md:213-215` lists `en-brainstorm`'s references as `references/research-guide.md` (does not exist — it is `research-dispatch.md`) and `references/design-doc-template.md` (actually `references/templates/design-doc-template.md`). The broken-link lint evidently does not cover foundation's per-skill reference lists.

### B8. Cosmetic: the Process list is not a valid ordered list
Steps run `5, 5a, 5b, 6 … 10, 10a`, with two items numbered 10. Renders oddly and makes the steps hard to cite. Renumber, or convert to headed sub-steps.

---

## 3. Benchmark comparison

### Structural comparison

| Dimension | `en-brainstorm` | `en-plan` (internal) | `en-foundation` (internal) | `ce-brainstorm` (external) | `codebase-design` (external) |
|---|---|---|---|---|---|
| SKILL.md lines | 107 | 284 | 150 | 67 (pure router) | 114 |
| Reference files | 4 shared | 22 refs | 25 refs | 19 dedicated (2,641 lines) | 2 dedicated |
| Progressive disclosure | partial — refs named but not phase-gated | partial | partial | **full** — phase → "read first" table | full |
| Resume support | **none** | yes (`--resume`, `--from-legacy`, auto-resume) | n/a | yes (Phase 0.1 scan) | n/a |
| Approach generation | serial, single context | n/a | n/a | serial + anti-genericness test | **parallel sub-agents, divergent constraints** |
| Unknown-territory handling | none | none | none | **blindspot pass** | none |
| Write-time validation | **none** | `ensemble-lint` + peer review | peer review | Ready-for-Planning Check | n/a |
| Failure protocol table | **yes** | partial | partial | no | no |
| Machine drift guards | **28 assertions** | yes | partial | none per-instruction | none |
| `argument-hint` frontmatter | no | no | no | yes | no |

### Adoptable, in leverage order

**A1. "Design It Twice" — parallel divergent approach generation.**
Source: `agent-skills/skills/skills/engineering/codebase-design/DESIGN-IT-TWICE.md`. Spawn 3+ sub-agents in parallel, each given a *different* design constraint ("minimize the interface", "maximise flexibility", "optimise for the most common caller"), then compare on named axes and give an opinionated recommendation.

Why it matters most: step 7's *"Propose 2–3 approaches"* is serial generation in one anchored context, and approaches B and C reliably become variants of A. Independent contexts with opposed constraints is the direct structural fix. It is also **latency-positive** — three parallel agents beat three serial in-context generations. Gate it to Deep, or to Standard when 3+ plausible directions genuinely remain. Not on D39's not-adopted list.

**A2. Resume scan.**
Source: `ce-brainstorm/references/phase-0.md` §0.1; `en-plan/SKILL.md:21-31` already implements the pattern internally. `en-brainstorm`'s failure protocol currently accepts total loss: *"User abandons mid-conversation → No file written; chat history is its own record."* Before Q&A, glob `docs/designs/*.md` for `status: open` matching the topic and offer to resume. This is a consistency win inside Ensemble, not a new mechanism — reuse `en-plan`'s auto-resume shape and wording.

**A3. "Ask only decisions the environment can settle."**
Source: `ce-brainstorm/references/interaction-rules.md` Rule 8 — *"A question whose answer is in the environment ... is not put to the user. Look it up."* Since round trips dominate latency, this is the single highest-leverage latency lever in the whole skill, and it costs one line of prose. It also pairs naturally with B1's bounded foundation read: the read exists precisely to close questions.

**A4. Anti-genericness test on approaches.**
Source: `ce-brainstorm/references/approaches.md:9` — require at least one non-obvious angle (inversion, constraint removal, cross-domain analogy) and drop any approach that would appear in a generic listicle for the problem category. One sentence. Worth adopting *even if* A1 is deferred, and worth keeping *alongside* A1 as the quality bar the sub-agents are held to.

**A5. Blindspot pass.**
Source: `ce-brainstorm/references/blindspot-pass.md`. When the user signals they cannot evaluate the territory ("I don't know what I should be asking", or two consecutive "you decide" answers), the interview extracts guesses rather than requirements. The pass maps the decision surface first — 3–7 items, each a decision or a hazard, with realistic options and a recommended default — then asks one multi-select about which to walk through; unselected items become recorded assumptions.

This addresses a failure mode `en-brainstorm` has no answer for, and it is **not** on D39's not-adopted list. Recommend a trimmed version (trigger, offer, 3–7 item map, re-entry rule) at roughly 25 lines, not `ce`'s 70 — consistent with D39's "kept deliberately lean" stance.

**A6. `argument-hint` frontmatter.** `en-flow` and `en-loop` already carry it; `en-brainstorm` does not. Trivial discoverability win.

### Explicitly not re-proposed

D39 records these as deliberately rejected from `ce-brainstorm`, and nothing found in this review overturns them: **visual probes, HTML output mode, the universal/non-software route, model tiers, the async grounding-scout dossier, and the unified single-artifact model.** One flag: B1's fix deliberately stays a *bounded read* rather than a scout, to respect the dossier rejection. If delegating that read later looks attractive, it should be reopened as a decision, not slipped in.

### Where `en-brainstorm` is ahead of both benchmarks

- **Budgeted rigor.** The pressure test counts probes against the depth question budget and caps Lightweight at one. `ce`'s equivalent is unbudgeted and can balloon.
- **Verify-before-claiming as a rule, not an agent.** `ce` dispatches a fresh-context claim verifier (`approaches.md:49-55`). Ensemble's inline rule is cheaper and adds no round trip. `ce`'s anchoring argument is real, but the cost/benefit favors the rule at brainstorm's stakes.
- **A real failure-protocol table.** Neither benchmark has a per-skill one.
- **Machine-enforced drift guards.** 28 greps against the prose. Neither benchmark enforces its own instructions this way.

---

## 4. Final recommendations

**Now — low risk, no behavior change, do as one atomic commit each:**

| # | Change | Why |
|---|---|---|
| B1 | Bound the `foundation.md` read | ~51K → ~1–2K tokens per run |
| B2 | Fix the `host-detect` conditional/required contradiction | Skill is currently self-contradictory at step 5 |
| B3 | Resolve the `learnings-research` three-way drift + add a drift test | Three docs disagree with the code path |
| B5 | Resolve the Standard-vs-Lightweight default contradiction | Opposed instructions in one run |
| B6 | Run `ensemble-lint` at step 11 | Closes the brainstorm → plan handoff gap |
| B7 | Fix stale reference paths in `foundation.md:213-215` | Broken links |
| B8 | Renumber the Process list | Legibility |
| A3 | Add the ask-only-decisions rule | Highest-leverage latency fix, one line |
| A6 | Add `argument-hint` | Consistency with `en-flow` / `en-loop` |

**Next — real behavior change; each needs a plan unit and its own drift test:**

| # | Change | Note |
|---|---|---|
| A1 | Parallel divergent approach generation | Biggest effectiveness gain; gate to Deep first, measure, then consider Standard |
| A2 | Resume scan | Mirror `en-plan`'s existing shape rather than inventing one |
| A4 | Anti-genericness test on approaches | Ship with or before A1 |

**Consider — worth a decision, not obviously right:**

| # | Change | Tension |
|---|---|---|
| A5 | Trimmed blindspot pass | Genuine gap, but it is added machinery in a skill D39 wants lean |
| B4 | De-duplicate the always-load path | Requires touching a passing drift test; do it deliberately |

**Suggested route:** the Now tier is mechanical and safe to apply directly. The Next and Consider tiers change documented behavior and will break existing drift assertions, so they belong in an `/en-plan` improvement plan (`plan_type: improvement`) with a unit per item — the same discipline EN05 used to land the rigor lenses in the first place.

**Not measured:** every effectiveness claim here is structural. There is no eval harness for Ensemble skills and no brainstorm run logs. If approach quality matters enough to justify A1's cost, the honest next step is a small eval fixture (a few seed prompts, human-scored approach diversity) rather than more static reading.

---

## 5. Deep comparison: `ce-brainstorm` and `grill-with-docs`

### `grill-with-docs` is a 7-line composition skill

The entire body is one line:

> `Call the Skill tool twice, for "grilling" and "domain-modeling".`

It composes `grilling` (28 lines) and `domain-modeling` (74 lines). Its sibling `grill-me` (7 lines) is the same pattern wrapping `grilling` alone. Four skills ship, two carry substance; the thin two are named entry points with `disable-model-invocation: true`.

Ensemble already knows this pattern — `en-flow` sequences plan → build → learn → ship. But `en-flow` is 79 lines to `grill-with-docs`'s 7, because it adds gates, artifact threading, and a failure protocol between stages. That weight is justified for a pipeline that commits and pushes. It would not be justified around brainstorm, which writes one file. **No composition change recommended here** — the point is the calibration: composition weight should track what the composed stages can break.

### The frontier/rounds model — the highest-value adoptable idea in either repo

`grilling` models the interview as a **design tree**. The **frontier** is every decision whose prerequisites are already settled. Ask the *whole frontier in one round* — numbered, each with your recommended answer — then wait. The user's answers reshape the tree and push the frontier outward. Done when the frontier is empty.

This attacks en-brainstorm's dominant latency term head-on:

| | `en-brainstorm` | `grilling` |
|---|---|---|
| Batching | one question per turn, always | whole frontier per round |
| Deep run | 9–14 sequential round trips | ~3–4 rounds |
| Exit condition | question-count budget (arbitrary) | frontier empty (semantic) |
| Default answer | "recommend a default" — a *style guideline* (`socratic-questions.md:95`) | mandatory `➡️ <recommended answer>` per question |

**The nuance that makes this safe.** This is not "batch the questions." The reason for one-per-turn is real — `ce`'s Interaction Rule 1: *"stacking several questions in a single message produces diluted answers."* But that applies to **dependent** questions, where a later one presupposes an earlier answer. The frontier is defined precisely to exclude those (`grilling:24` — *"A question whose answer depends on another question still open in this round belongs to a later round, not this one"*). The frontier model keeps the property one-per-turn protects and drops its cost.

The mandatory recommended answer matters as much as the batching. It turns a round from "answer 4 questions" into "confirm 4 defaults, correct the ones I got wrong" — which is why a 4-question round is *cheaper* for the user than 4 single questions, not more expensive. en-brainstorm already has this instinct but files it as style advice rather than format.

**Recommendation:** adopt frontier-rounds for **Standard and Deep** only. Keep strict one-per-turn on Lightweight (2–4 questions needs no tree), and keep it for the 5a rigor probes specifically — those are deliberately open-ended, and a numbered menu with a recommended answer would flatten exactly what they exist to elicit. Keep the depth question budget as a **cost cap**; add "frontier empty" as the **exit condition**.

### `grilling:26` supersedes recommendation A3

Section 3 proposed `ce`'s Rule 8 ("ask only decisions"). `grilling` states it better and adds the part that matters:

> *"Finding facts is your job, never the user's. When a frontier question needs a fact from the environment, dispatch a sub-agent to find it... **Don't block on it**: a running exploration is an unsettled prerequisite, so only the questions downstream of it wait for the sub-agent to report; ask the rest of the frontier now."*

This gives en-brainstorm the parallelism it currently has none of — and does it **without** the scout-dossier machinery D39 rejected. The sub-agent returns a fact, not a dossier. **Adopt this phrasing over A3.**

### `domain-modeling`'s three-test — a sharper artifact gate

`domain-modeling:66-73` gates ADR creation on three conditions, **all** required: hard to reverse, surprising without context, the result of a real trade-off. en-brainstorm's equivalent ("When to skip the design doc", `SKILL.md:85-91`) is a vibe: *"For very small explorations where the user is iterating on a code-level question."*

The three-test is testable and maps cleanly onto what a design doc is for. `ce` has the same instinct in another form: *"a file is earned only by a decision a downstream consumer needs in IDed form."* Also worth taking: `domain-modeling:40` — *"Create files lazily: only when you have something to write."*

### `ce-brainstorm`, re-read with the overkill lens

Section 3 framed `ce` as the richer skill worth borrowing from. The more useful second reading is about **shape**: `ce` is a 67-line router over 2,641 lines of references, strictly phase-gated so only the current phase's file loads. en-brainstorm is 107 lines carrying its content inline, naming 4 references that load anyway.

`ce`'s total is 10× larger, but its *per-phase* load is comparable or smaller. The lesson is not "add references" — it is that `ce` pays for its size with strict phase gating, while en-brainstorm pays for its inline content on every run regardless of depth. Ensemble is small enough that this doesn't bite yet. It will if the skill grows.

---

## 6. What's overkill

### O1. The drift tests are the densest in the repo, on the least load-bearing skill

| Skill | Skill lines | Assertions | Assertions/line |
|---|---:|---:|---:|
| **`en-brainstorm`** | 107 | 28 | **0.26** |
| `en-ship` | 225 | 48 | 0.21 |
| `en-review` | 240 | 47 | 0.20 |
| `en-build` | 432 | 73 | 0.17 |
| `en-plan` | 284 | 46 | 0.16 |

Meanwhile `design-doc-template.md:92` states the output is *"informational, not load-bearing."* The tightest prose lock in the repo guards the skill with the smallest blast radius.

The locks also actively block improvement. `en-brainstorm-pressure-test.test.sh:50-59` **requires** all five gap names in *both* `SKILL.md` and `socratic-questions.md` — the test mandates the duplication B4 wants to remove. `en-brainstorm-priority-principle.test.sh` spends 6 assertions confirming a paragraph of philosophy exists, including that `foundation.md` records what was *not* adopted.

This is not an argument against the gates. EN07's lesson holds, and gates gating real invariants (the mutation boundary, the guardrail matchers) earn their keep — that is a different risk class. It is a calibration point: **assertion density should track blast radius, and here it is inverted.** Trim to the assertions that guard *behavior* (probes are open-ended; probes count toward the budget; Lightweight caps at one; verify-before-claiming exists) and drop the ones guarding *wording* and *provenance*.

### O2. The depth numbers are stated four times

`SKILL.md:21` (prose), `SKILL.md:39` (inline in the budget rule), `SKILL.md:64-70` (the "at a glance" table), `socratic-questions.md:103-105` (a second table). Four copies of three numbers — and two of them already contradict each other on the default (B5). Keep one canonical table; everything else cites it.

### O3. Three provenance tags inside the running instructions

*"(adapted from `ce-brainstorm`)"* appears 3× in `SKILL.md`. That is changelog material, and `foundation.md`'s D39 entry already records it in full. An agent does not need an instruction's origin to follow it.

### O4. Justification prose inside instructions

Step 5a spends ~490 B on *"Why open-ended, not a menu: a menu signals which evidence 'counts'..."*; step 5b explains at length how it differs from step 9; step 10a explains what it prevents. Each is a good argument that **already won** — and is recorded in D39. The instruction needs the rule, not the case for it.

### O5. The priority principle, 459 B on every run

`performance > speed ≥ cost` is a real decision, but it is stated identically in en-brainstorm and en-plan, guarded by a test, and it branches nothing: every self-gating rule it justifies is already stated explicitly at its own step. One clause would carry it.

### O6. Four caveat sections in the output template

The design doc carries "Assumptions & unverified claims", "Devil's advocate", "Why we're proceeding anyway (if applicable)", and "Open questions". For a doc capped at <100 lines on Lightweight, that is more scaffolding than content. Merge the middle two.

### O7. A failure-protocol row for a dispatch that never happens

The `learnings-research` row (`SKILL.md:106`) handles a failure mode the skill cannot reach (B3). Dead protocol.

### Not overkill — keep as-is

The pressure test and integration check themselves (self-gating, budgeted, and the strongest thing in the skill); verify-before-claiming as a rule rather than `ce`'s dispatched verifier; the failure-protocol table as a *form*; the hard gate against writing code.

### The net

en-brainstorm's **mechanisms** are well-chosen and genuinely lean — D39's restraint was the right call. The weight sits in *prose about* the mechanisms — justification, provenance, philosophy, restated numbers — and in tests that freeze that prose in place. Roughly **2.5K of `SKILL.md`'s 11.6K is non-instructional**. Removing it changes no behavior, but requires touching the drift tests first, which is the actual work.

---

## 7. Revised recommendations

Supersedes §4 where they conflict.

**Now — mechanical, no behavior change:**
B1, B2, B3, B5, B6, B7, B8, A6 (as in §4), plus **O2, O3, O4, O7** (redundancy and non-instructional prose).

**Next — behavior change, one plan unit + drift test each:**

| # | Change | Note |
|---|---|---|
| **N1** | **Frontier-rounds for Standard/Deep** (`grilling`) | Largest latency win available: 9–14 round trips → ~3–4 rounds. Keep one-per-turn on Lightweight and for 5a probes. |
| **N2** | **Non-blocking fact sub-agents** (`grilling:26`) | Supersedes A3. Gives the skill its only parallelism, without the rejected dossier. |
| A1 | Design It Twice — parallel divergent approaches | Complements N1; both are parallelism, different axis |
| A2 | Resume scan | Mirror `en-plan`'s existing shape |
| A4 | Anti-genericness test on approaches | Ship with or before A1 |
| **N3** | **Three-test gate on writing the design doc** (`domain-modeling:66-73`) | Replaces the current vibe-based skip rule |

**Consider:**

| # | Change | Tension |
|---|---|---|
| **O1** | Recalibrate drift-test density to blast radius | Touches passing tests; needs an explicit decision, not a quiet trim |
| B4 | De-duplicate the rigor gaps | Blocked by O1 — the test mandates the duplication |
| A5 | Trimmed blindspot pass | Genuine gap, but added machinery in a skill D39 wants lean |
| O5 | Trim the priority principle to one clause | It is a real decision; only the *restatement* is the cost |
| O6 | Merge the template's caveat sections | Cosmetic |

**Sequencing note:** O1 gates B4 and makes N1/N3 cheaper to land, since both edit prose the current tests pin. Decide O1 first.

---

## 8. Applied — cost pass + latency pass (2026-08-25)

Uncommitted. `./tests/run.sh` 54/54 green; `ensemble-lint --scope docs` exit 0.

### Measured result

| | Before | After |
|---|---:|---:|
| Skill scaffolding (always-loaded) | ~9,297 tok | ~9,039 tok |
| `foundation.md` runtime read | ~51,290 tok | ~1,374 tok + matched section |
| **Standard run, pre-dialogue** | **~60,600 tok** | **~11,500 tok** |
| Deep-run question round trips | 9–14 | ~3–4 rounds |
| Drift assertions | 28 (wording + provenance) | 17 (behavior, all negative-controlled) |

**Honest note on the prose trims.** O2/O3/O4 saved ~260 tokens — essentially nothing. Their value is drift-resistance (one canonical depth table instead of four copies, two of which contradicted each other), not cost. **The entire cost win is B1.**

### Cost pass
- **B1** — step 4 is now a bounded scan: frontmatter → `grep -n '^#'` section index → `sed -n` on matching sections. Never whole-file.
- **B2** — step 1 states plainly that host-detect is always sourced, and names the two things brainstorm takes from it.
- **B3** — resolved toward reality rather than new behavior: the dispatch matrix now reads `never/never` for brainstorm's scouts, with a paragraph explaining why, and the false "dispatched by en-brainstorm" claim is gone from `agents/learnings-research.md`.
- **B5** — "default Standard" is canonical; the contradicting "lean Lightweight" line is gone.
- **B6** — new step 16 lints the design doc before handoff.
- **B7** — `foundation.md` reference paths corrected.
- **B8** — Process renumbered 1–18; no more 5a/5b/10a or duplicate 10.
- **O2/O3/O4/O7** — one canonical depth table, provenance tags removed, justification prose trimmed, dead failure-protocol row removed.
- **B4** (was gated on O1) — the five rigor gaps are now named once in SKILL.md and catalogued once in `socratic-questions.md`; the probe phrasings live in exactly one place.
- **A6** — `argument-hint` added.

### Latency pass
- **N1 — frontier rounds.** Standard/Deep ask each round's independent frontier in one numbered batch, every question carrying a recommended answer. The dependency rule (a question depending on one still open this round waits for the next) is what keeps batching from producing diluted answers. One-per-turn retained on Lightweight and for all rigor probes.
- **N2 — non-blocking fact lookup.** Facts in the environment are never asked; a needed fact is dispatched and only *downstream* questions wait. This is the skill's first parallelism.
- Exit condition is now frontier-empty **or** budget-spent; a live frontier at budget exhaustion records explicit assumptions instead of dropping decisions.

### Guard recalibration (your call: behavior over wording)

| File | Before | After |
|---|---:|---:|
| elicitation | 6 | 4 |
| integration-verify | 6 | 3 |
| pressure-test | 10 | 4 |
| priority-principle | 6 | 1 |
| cost-contract *(new)* | — | 2 |
| frontier *(new)* | — | 3 |
| **Total** | **28** | **17** |

12 recalibrated + 5 new for behavior that didn't exist before. Every new guard was **negative-controlled**: the target was broken and the guard confirmed red (unbounded read restored → red; lint step removed → red; probe text re-duplicated → red; host tool hardcoded → red; step order scrambled → red; dependency rule deleted → red; rigor carve-out dropped → red; fact lookup made blocking → red; budget-exit assumptions dropped → red).

One existing guard caught a real mistake mid-pass: `skill-helper-anchor` rejected an unanchored `bin/ensemble-lint` path. Fixed to `$ENSEMBLE_ROOT/bin/...`.

### Not done (unchanged from §7)
A1 Design It Twice, A2 resume scan, A4 anti-genericness, N3 three-test doc gate, A5 blindspot pass, O5 priority-principle trim, O6 template caveat merge.

---

## 9. Applied — three adopted mechanisms (D47)

Uncommitted. `./tests/run.sh` 55/55 green; `ensemble-lint --scope docs` exit 0.

### What landed

**A2 — Resume** (inline, step 3). Globs `docs/designs/*.md` for a `status: open` doc matching the topic, **confirms before resuming** (never silent), treats its settled decisions as already-answered so they never re-enter the frontier, and **updates that file** rather than minting a duplicate. Mirrors `/en-plan` step 3.

**A5 — Blindspot pass** (`references/brainstorm-blindspot.md`, gated). Fires only when the user **cannot evaluate** a territory — flagged up front, or two consecutive can't-evaluate answers. Maps 3–7 decisions/hazards with options and recommended defaults, then re-enters via one multi-select; unselected items become explicit assumptions. Trimmed from `ce`'s 70 lines to 67 by dropping the `ce-explain` handoff and the universal route (D39 rejected the non-software path).

**A1 — Divergent approach generation** (`references/brainstorm-approaches.md`, gated). On Deep, or Standard with 3+ live directions, approaches come from parallel sub-agents each held to a *different* constraint — smallest-thing / invert-the-default / optimize-common-case / remove-the-binding-constraint. Serial fallback for hosts without sub-agents.

### The honest cost

| | After §8 | After §9 |
|---|---:|---:|
| `SKILL.md` | 117 lines / 12,295 B | 132 lines / 15,601 B |
| Always-loaded scaffolding | ~9,039 tok | **~10,561 tok** |
| Gated, paid only on trigger | — | blindspot ~1,600 tok · approaches ~1,039 tok |
| Standard run, pre-dialogue | ~11,500 tok | **~13,000 tok** |

**The additions cost ~1,500 tokens on every run, including runs that trigger neither mechanism.** Gating moved the *bodies* out (2,639 tokens deferred), but the triggers, the resume step, and the reference wiring all live in the always-loaded skill.

Net against where this started: **~60,600 → ~13,000 tok**, still a 4.7× cut. But §8's number was ~11,500, and these three mechanisms gave back about a fifth of the cost-pass win. That is the real trade — worth it if the blindspot pass and divergent generation earn their keep, and there is still no telemetry to say whether they do.

### Guards: 23 total (was 28, bottomed at 17)

Six new, each negative-controlled: resume made silent → red; gated reference deleted → red; over-firing discriminator removed → red; blindspot walk-throughs unbudgeted → red; four constraints collapsed to one → red; sub-agent fallback removed → red; anti-genericness bar dropped → red.

**One guard was decorative on first write.** The over-firing check matched the phrase "undecided, not blindsided" while the meaningful discriminator ("understands the options but hasn't picked one") could be deleted without tripping it. Caught by the negative control, tightened to require the discriminator in both files, re-verified red. This is the whole argument for negative controls — the guard looked correct and passed.

### Scope note

`references/brainstorm-approaches.md` folds in **A4 (anti-genericness)**, which you did not ask for. It is one bullet, and it is the acceptance bar the parallel agents' output is held to — without it three agents can each return a generic answer and the mechanism buys nothing. Say the word and I'll drop it.

### Still not done
N3 (three-test gate on writing the doc), O5 (trim the priority principle), O6 (merge template caveat sections).
