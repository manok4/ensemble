---
type: plan
plan_type: feature
plan_id: EN32
title: Strategy section in the foundation, consumed across skills
status: open
location: active
created: 2026-11-24
shipped:
deepened:
covers_requirements: []
requirements_pending: true
related_design:
peer_review_verdict: revise
peer_review_iterations: 2
peer_review_last_run: 2026-11-24
peer_review_plan_hash: 0b39fb7e683f6cc073ed72fb5dbc3c4ee907c292c76dc1095b44f215fd371457
peer_review_resolutions:
  - finding_id: 1-1
    iteration: 1
    severity: P1
    title: Literal test examples become broken citations
    status: applied
    rationale: citations are plain text; backticked and fenced IDs are examples; U3 strips them and adds a mixed fixture
    location: U3, Technical design
  - finding_id: 1-2
    iteration: 1
    severity: P1
    title: Standalone consumers disagree with the section contract
    status: applied
    rationale: check-health calls the reader as a sibling (en-setup carries it); the lint embeds the same recognition and consumers-agree.test.sh runs both over shared fixtures
    location: Technical design, U2, U3, U7
  - finding_id: 1-3
    iteration: 1
    severity: P1
    title: Plan intake lacks concrete behavior scenarios
    status: applied
    rationale: four kind-plan behavioral cases with stated expected lines
    location: U5
  - finding_id: 1-4
    iteration: 1
    severity: P1
    title: Authoring workflow tests do not exercise its gates
    status: applied
    rationale: six-case manual procedure with expected writes, recorded in tests/evals/ledger.md
    location: U6
  - finding_id: 1-5
    iteration: 1
    severity: P1
    title: Sweep scenarios omit debt and ownership outcomes
    status: applied
    rationale: doc-only-check now refuses Strategy edits (scripted tests); td-append dedupe tests; manual drift procedure
    location: U8
  - finding_id: 1-6
    iteration: 1
    severity: P2
    title: Scope violations have no defined finding identifier
    status: applied
    rationale: "Strategy: Scope" title form plus a prompt scenario
    location: U4
  - finding_id: 2-1
    iteration: 2
    severity: P1
    title: Delta writes can replace the wrong section
    status: applied
    rationale: delta mode replaces only the reader-located section; the retitle of §1 applies only when no section exists; added the delta-elsewhere case
    location: U6
  - finding_id: 2-2
    iteration: 2
    severity: P2
    title: Sweep ownership guard lacks parser-error handling
    status: applied
    rationale: a non-zero reader exit on either revision fails the guard before comparing; added the duplicate-heading fixture
    location: U8
depth: standard
data_scale: small
---

# EN32 — Strategy section in the foundation, consumed across skills

## Context

Ensemble's principles and non-goals live in `docs/foundation.md` §1, §2.2, §3.3 and §17, and they have drifted without anyone noticing: §1 says "11-skill, 11-agent" while `skills/` holds 18, and "No telemetry. No analytics events on skill invocation." stands beside D106 and D129's per-run analytics ledger.
No review checks a change against the product's principles; `en-review` checks plan coverage only, and `/en-fix` changes have no plan.
`docs/reviews/strategy-section-review.md` studied the external `/vision` skill and recommended taking its document shape (identity, principles, non-goals, an aligns/resisted test) and its hypothetical stress-test, naming the result a **strategy**, giving its principles stable IDs, and wiring it into the review that already runs. Its §5 sets how repos already on Ensemble adopt it.

## Requirements covered

Ensemble's foundation declares no R-IDs, so `requirements_pending: true`. Source: `docs/reviews/strategy-section-review.md` §4 and §5.

## Out of scope for this plan

- `/en-fix` triage reading the strategy. It runs `en-review`, which carries the check on the real diff.
- Giving the strategy to host dimension-reviewers. The peer is the only checker; with `peer_mode: off` there is no strategy check.
- The external `/vision` skill, a root `STRATEGY.md` or `VISION.md`, and the `lavish-axi` review board.
- Running `/en-foundation --strategy` in adopting repos. That happens per repo, by its author, after this ships.
- Implementing the cataloged-but-missing `id-stability.*-renumbered` and `requirements-traceability.*` lint rules.

## Approach (high-level)

A repo's strategy is §1 of `docs/foundation.md`, titled `## 1. Strategy`, whose first line is `<!-- strategy: author-approved YYYY-MM-DD -->`.
It holds an identity opener, 3 to 6 principles declared as `### ST<N>. <heading>`, a Scope with concrete non-goals, and the closing pair "A change aligns when ..." and "A change should be resisted when ...".
The marker is what makes a section count; skills find it by heading text and marker, never by section number, because older foundations differ in layout.
`ST` is the prefix because a bare `S<N>` collides with "S3" in adopting repos' docs.

One script, `ensemble-strategy-section`, owns finding the section, so every consumer agrees on its boundary.
`/en-foundation` authors and revises it (`--strategy`, and as part of fresh and retrofit runs) through `references/strategy-mode.md`.
`en-review`'s peer prompt builder injects it automatically when the brief has a `### strategy` dimension, so the agent cannot forget it and `en-review`'s SKILL.md, 27 bytes under its cap, does not change.
`en-plan` names the ST-IDs a plan touches. The lint resolves ST citations: P1 when the section exists, P3 when it does not.
`/en-setup` State 3 and `/en-sweep` notice a missing section and point at `/en-foundation --strategy`; neither writes strategy text, because the author owns it.
Every consumer treats a missing section as a no-op, so a repo nobody migrates behaves exactly as today.

## Test seams

Five seams, all but one existing, because the consumers sit in separate harnesses and no single seam observes them all:

1. **`ensemble-strategy-section` stdout and exit code** (new): `tests/strategy/strategy-section.test.sh`.
2. **`ensemble-build-peer-prompt` output** (existing): `tests/build-peer-prompt/build-peer-prompt.test.sh`.
3. **`ensemble-lint` findings** (existing): `tests/lint/lint-rules.test.sh` fixtures.
4. **`check-health` output** (existing): a `tests/en-setup/` test in the shape of `analytics-store-advisory.test.sh`.
5. **Wording pins** for behaviour that is prose only (strategy-mode, plan intake, sweep): `tests/lint/*.test.sh`, each scoped to one file, anchored on wording only that file carries, with a negative control that edits the file and sees the test go red.

## Technical design

Components: the foundation section (data), `ensemble-strategy-section` (reader), and five consumers.

```
docs/foundation.md  ## 1. Strategy + marker + ### ST<N>.
        │
        ├─ ensemble-strategy-section ──► en-review build-peer-prompt ──► peer prompt "## Strategy"
        │        (carried by en-foundation,         (only when brief has ### strategy)
        │         en-plan, en-review,
        │         en-test-audit, en-sweep)  ──► en-plan intake: "Strategy: ST2, ST4"
        │                                   ──► en-sweep: drift / missing → TD via ensemble-td-append
        ├─ ensemble-lint (inline grep): cross-link.broken-st, P1 with marker, P3 without
        ├─ check-health (inline grep of marker): 🟢 / 🟡 "run /en-foundation --strategy"
        └─ en-foundation strategy-mode: the only writer
```

The script is the single definition of the section's boundary. `check-health` lives in `skills/en-setup/scripts/`, so `en-setup` carries the reader and calls it as a sibling. `ensemble-lint` is copied into adopting repos' `bin/` and cannot call a skill script, so it embeds the reader's recognition (heading regex, fence skipping, boundary, exact marker, declarations only inside the section) as one awk function, and `tests/strategy/consumers-agree.test.sh` runs both over the same fixtures so they cannot drift apart.

**Citation versus example.** A citation is an `ST<N>` in plain text. One inside an inline code span or a fenced block is an example and is never checked, so docs that explain the format, and plans whose test scenarios name IDs like `ST9`, do not trip the lint.

## Implementation units

### U1. Define the Strategy section format

- **Goal:** The foundation template, the stable-ID catalog and the AGENTS.md template describe the Strategy section and ST-IDs.
- **Requirements covered:** none (pending)
- **Dependencies:** none
- **Files:**
  - `skills/en-foundation/references/templates/foundation-template.md` (modify)
  - `skills/en-foundation/references/stable-ids.md` (modify)
  - `skills/en-plan/references/stable-ids.md` (modify)
  - `skills/en-setup/references/stable-ids.md` (modify)
  - `skills/en-foundation/references/templates/agents-md-template.md` (modify)
  - `skills/en-setup/references/templates/agents-md-template.md` (modify)
- **Approach:** In the foundation template, retitle `## 1. Executive Summary` to `## 1. Strategy` and replace its body with the anatomy: the marker line `<!-- strategy: author-approved {{TODAY}} -->`, the identity opener ("`{{PROJECT_NAME}}` exists so that ... It serves ... It owns exactly one thing: ..."), 3 to 6 `### ST<N>. <heading>` principle blocks of declarative present-tense lines, a `### Scope` block holding the concrete non-goals, and the two closing lines "A change aligns when ..." and "A change should be resisted when ...". State the 40 to 70 line target and "no roadmap, no feature list, no marketing voice". Keep `### 2.2 Non-Goals` as a heading whose body is the one line "Non-goals live in §1 Strategy, Scope.", so existing §2.2 references resolve. Update the template's depth-scaling note if it names §1. In all three `stable-ids.md` copies (byte-identical; `tests/parity/reference-parity.test.sh` discovers them by basename), add the row `| ST<N> | foundation.md §1 Strategy | ST1, ST2, … | Append-only. A retired principle stays numbered and is marked "(retired YYYY-MM-DD)", never deleted or reused. |`, and add `broken-st` to the cross-link list at the line naming `broken-r`. In both AGENTS.md template copies, add a "Where things live" row `| Strategy: what the project owns, refuses, and how a change is judged | docs/foundation.md §1 (ST-IDs) |` and add `ST<N>` to the Stable IDs convention line.
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Test expectation:** none — template and catalog text; the parity tests and `tests/lint/pointer-map-coverage.test.sh` cover the copies, and U6's wording pin covers the template anatomy.
- **Verification:** `./tests/select-for.sh <the six files>` passes, including reference parity and pointer-map coverage.

### U2. Add the `ensemble-strategy-section` reader script

- **Goal:** One script prints a repo's Strategy section or its ST-IDs, and prints nothing when the section is absent.
- **Requirements covered:** none (pending)
- **Dependencies:** U1
- **Interfaces:**
  - *Produces:* `ensemble-strategy-section [--ids] [<foundation-path>]`. Default path `docs/foundation.md`, resolved against the current directory. Finds the first line, outside fenced code blocks, matching `^##[[:space:]]+([0-9]+\.[[:space:]]+)?Strategy[[:space:]]*$` case-insensitively. The section runs from that line to the line before the next `^#{1,2}[[:space:]]` heading or end of file. It counts only when a line matching `^<!-- strategy: author-approved [0-9]{4}-[0-9]{2}-[0-9]{2} -->$` sits inside it. Without `--ids`, prints the section verbatim. With `--ids`, prints each `ST<N>` declared by a `^### ST[0-9]+\.` line in the section, one per line, in file order. Exit 0 in every found-or-absent case (missing file, no heading, no marker: empty stdout). Exit 3 with `ensemble-strategy-section: more than one Strategy section in <path>` on stderr when two headings match. Exit 2 on bad usage.
- **Files:**
  - `skills/en-foundation/scripts/ensemble-strategy-section` (create)
  - `skills/en-plan/scripts/ensemble-strategy-section` (create)
  - `skills/en-review/scripts/ensemble-strategy-section` (create)
  - `skills/en-test-audit/scripts/ensemble-strategy-section` (create)
  - `skills/en-sweep/scripts/ensemble-strategy-section` (create)
  - `skills/en-setup/scripts/ensemble-strategy-section` (create)
  - `tests/strategy/strategy-section.test.sh` (create)
  - `tests/strategy/fixtures/` (create)
- **Approach:** POSIX `sh` plus `awk`, in the style of the other `ensemble-*` scripts (header usage block printed by `-h`). Six byte-identical copies; `tests/parity/script-parity.test.sh` pins them by basename with no declaration. The test fixtures live in `tests/strategy/fixtures/` (one foundation file per case below) so U3's agreement test reuses them. `en-test-audit` carries it only because its `ensemble-build-peer-prompt` is byte-identical to `en-review`'s and calls it as a sibling (U4).
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* a fixture with `## 1. Strategy`, the marker, `### ST1.` and `### ST2.`, followed by `## 2. Goals` → stdout is the section through the line before `## 2. Goals`; `--ids` prints `ST1` then `ST2`.
  - *Happy path:* an unnumbered `## Strategy` heading is found the same way.
  - *Edge case:* the heading exists without the marker → empty stdout, exit 0.
  - *Edge case:* no `docs/foundation.md` → empty stdout, exit 0.
  - *Edge case:* a `## Strategy` line inside a fenced code block is ignored.
  - *Edge case:* the section is the last in the file → it runs to end of file.
  - *Edge case:* `### ST3.` declared outside the section is not printed by `--ids`.
  - *Error path:* two matching headings → exit 3 with the stderr message, nothing on stdout.
  - *Error path:* an unknown flag → exit 2.
- **Verification:** `./tests/run.sh -k strategy-section` and `-k script-parity` pass.

### U3. Lint unresolved ST citations

- **Goal:** `ensemble-lint` reports an `ST<N>` citation that the foundation does not declare.
- **Requirements covered:** none (pending)
- **Dependencies:** U1, U2 (its fixtures)
- **Files:**
  - `skills/en-setup/references/templates/ensemble-lint` (modify)
  - `bin/ensemble-lint` (modify)
  - `skills/en-sweep/references/doc-lints.md` (modify)
  - `tests/lint/lint-rules.test.sh` (modify)
  - `tests/strategy/consumers-agree.test.sh` (create)
- **Approach:** Add an awk function `strategy_scan` to the lint that applies the U2 recognition exactly (heading regex outside fences, boundary at the next `#` or `##` heading, the exact marker line inside the section, `^### ST[0-9]+\.` declarations inside the section only) and yields the section-present flag, the declared IDs, and a duplicate-heading flag. Two matching headings emit `strategy.duplicate-section` at P1 on `docs/foundation.md`, and ST citations are then checked as if no section exists. In `check_cross_links`, beside the R block, add an ST block guarded on `docs/foundation.md` existing and skipping `docs/foundation.md` itself, as the R block does. Before matching, drop fenced blocks and inline code spans from the file's text, so only plain-text citations count. For each remaining `\bST[0-9]+\b` not declared, `emit "cross-link.broken-st" "$file" "" "<sev>" "Citation of $sid not found in the foundation's Strategy section" "<remediation>"`, with `P1` and "Either declare $sid in foundation.md §1 Strategy or remove the citation" when the section exists, and `P3` and "This repo has no Strategy section; run /en-foundation --strategy, or remove the citation" when it does not. Edit the template, then copy it to `bin/` (`tests/lint/bin-template-sync.test.sh`). Add the row to `doc-lints.md`'s cross-link family.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* foundation with the marker and `### ST1.`; a plan citing `ST1` → no `cross-link.broken-st`.
  - *Error path:* same foundation; a plan citing `ST9` → `cross-link.broken-st` at P1.
  - *Edge case:* foundation without the marker; a plan citing `ST1` → `cross-link.broken-st` at P3.
  - *Edge case:* no `docs/foundation.md` → the rule does not run.
  - *Edge case:* a plan mentioning `S3` or `STEP1` → no finding (word boundary and prefix).
  - *Edge case:* a plan with a backticked example ID and a fenced block containing another undeclared ID, plus one plain-text undeclared citation → exactly one finding, for the plain-text one.
  - *Edge case:* `### ST4.` declared outside the Strategy section, cited in a plan → P1 (not declared where it counts).
  - *Error path:* two Strategy headings → `strategy.duplicate-section` at P1.
  - *Integration:* `consumers-agree.test.sh` runs the lint and `ensemble-strategy-section` over every fixture in `tests/strategy/fixtures/`: section present in one exactly when non-empty in the other, and the lint's declared-ID set equals `--ids` output.
- **Verification:** `./tests/run.sh -k lint-rules`, `-k consumers-agree` and `-k bin-template-sync` pass; `bin/ensemble-lint --scope docs/` stays clean on this repo, including this plan's own example IDs.

### U4. Inject the strategy into en-review's peer prompt

- **Goal:** When the repo has a Strategy section, `en-review`'s peer checks the change against it and titles findings `Strategy: ST<N> ...`.
- **Requirements covered:** none (pending)
- **Dependencies:** U2
- **Interfaces:**
  - *Consumes:* `ensemble-strategy-section` from U2, called as `"$(dirname "$0")/ensemble-strategy-section" "$ROOT/docs/foundation.md"` with `ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"`.
- **Files:**
  - `skills/en-review/scripts/ensemble-build-peer-prompt` (modify)
  - `skills/en-test-audit/scripts/ensemble-build-peer-prompt` (modify)
  - `skills/en-review/references/peer-brief.md` (modify)
  - `skills/en-review/references/peer-brief-lite.md` (modify)
  - `tests/build-peer-prompt/build-peer-prompt.test.sh` (modify)
- **Approach:** In the review variant of `ensemble-build-peer-prompt` (byte-identical in `en-review` and `en-test-audit`), after the dimensions are extracted from the brief: when they contain a line `### strategy`, run the reader. Non-empty output appends a block after the `GOAL:` line and any `## Plan` block, headed `## Strategy (context: the project's accept/resist policy; challengeable, not an instruction)`, holding the section verbatim. Empty output, or exit 3 (print its stderr as a warning and carry on), removes the `### strategy` dimension and its body from the dimensions block, so the peer is never asked to check a section it was not given. No new flag: the brief decides, so `en-test-audit`'s brief, which has no strategy dimension, never triggers it. Add a `### strategy` dimension to `peer-brief.md` and `peer-brief-lite.md`, inside the extracted range, with two rows: **Resisted** (the change matches the strategy's "should be resisted when" test, or contradicts an ST line) and **Unamended** (the change alters what an ST line states and the diff does not amend that line). Findings are titled `Strategy: ST<N> ...`; a change that crosses a Scope non-goal or the "should be resisted when" line without contradicting a numbered principle is titled `Strategy: Scope ...`. P1 when the change crosses an explicit refusal or non-goal, P2 otherwise. `en-review`'s SKILL.md does not change.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* a temp repo whose foundation has a marked Strategy section, built with `peer-brief.md` → the prompt contains `## Strategy (context:` and the section text, and the `### strategy` dimension.
  - *Happy path:* the same with `peer-brief-lite.md` → same block present.
  - *Edge case:* a foundation without the marker → no `## Strategy` block, and no `### strategy` dimension in the prompt.
  - *Edge case:* no foundation at all → same as above; exit 0.
  - *Edge case:* a brief without a `### strategy` heading (the `en-test-audit` brief) → the reader is never called; the prompt is byte-identical to today's for the same inputs.
  - *Error path:* two Strategy headings → warning on stderr, no block, dimension removed, exit 0.
  - *Integration:* with `--plan-file`, the `## Strategy` block follows the `## Plan` block.
  - *Happy path:* the built prompt's strategy dimension carries both title forms, `Strategy: ST<N>` and `Strategy: Scope`.
- **Verification:** `./tests/run.sh -k build-peer-prompt`, `-k script-parity`, `-k peer-prompt-contract`, `-k en-review-lite` pass; `wc -c skills/en-review/SKILL.md` unchanged.

### U5. en-plan names the ST-IDs a plan touches

- **Goal:** A plan written in a repo with a Strategy section names the ST-IDs it touches; a repo without one is unaffected.
- **Requirements covered:** none (pending)
- **Dependencies:** U2
- **Interfaces:**
  - *Consumes:* `ensemble-strategy-section` from U2.
- **Files:**
  - `skills/en-plan/references/plan-intake.md` (modify)
  - `skills/en-plan/references/templates/plan-template.md` (modify)
  - `skills/en-foundation/references/templates/plan-template.md` (modify)
  - `tests/lint/en-plan-strategy-intake.test.sh` (create)
  - `tests/evals/behavioral/plan-strategy-touch/` (create)
  - `tests/evals/behavioral/plan-strategy-none/` (create)
  - `tests/evals/behavioral/plan-strategy-absent/` (create)
  - `tests/evals/behavioral/plan-strategy-resisted/` (create)
- **Approach:** In `plan-intake.md`'s bounded foundation read, add: run `$SKILL_DIR/scripts/ensemble-strategy-section` (it prints nothing when the repo has no Strategy section, and then this step is skipped); otherwise read the section and name, in the plan's `## Requirements covered`, a line `Strategy: ST<N>, ...` for the principles the plan's work bears on, or `Strategy: none touched`. A plan that would cross a "should be resisted when" line says so under `## Decisions, assumptions & risks`, naming the ST-ID. In both plan-template copies (byte-identical), add the `Strategy:` line to the `## Requirements covered` guidance and to the requirements-traceability generation note, stating it is omitted when the foundation has no Strategy section. `en-plan`'s SKILL.md does not change.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:** The wording pin runs in CI; the four behavioral cases are `kind: plan` cases for `tests/evals/run-behavioral`, on demand, whose `base/` is a small CLI repo (built from `plan-cli-additive`'s base) plus a `docs/foundation.md` whose Strategy section declares `ST1. Output stays plain text` and `ST2. No network calls`, with "A change should be resisted when it adds a network dependency".
  - *Happy path (`plan-strategy-touch`):* request "add a `--format plain|table` flag to the report" → `plan_checks` `must_contain` `Strategy: ST1` in the plan.
  - *Edge case (`plan-strategy-none`):* request "rename the internal helper `fmt` to `formatRow`" → the plan contains `Strategy: none touched`.
  - *Edge case (`plan-strategy-absent`):* the same base without the Strategy section → a judge confirms the plan has no `Strategy:` line; `bin/ensemble-lint` reports no P1.
  - *Error path (`plan-strategy-resisted`):* request "fetch exchange rates from an API in the report" → the plan contains `Strategy: ST2`, and a judge confirms `## Decisions, assumptions & risks` names ST2 as crossed.
  - *Pin:* the test finds the `ensemble-strategy-section` call, the `Strategy: ST<N>` and `Strategy: none touched` forms, and the skip-when-empty clause in `plan-intake.md`; negative control: deleting the skip clause from a temp copy makes it fail.
- **Verification:** `./tests/run.sh -k en-plan-strategy-intake`, `-k en-plan-context-sufficiency`, `-k reference-parity` and `-k grade` pass; `tests/evals/run-behavioral plan-strategy-touch --dry-run` resolves each case; one `--runs 1` pass of the four cases, recorded in `tests/evals/ledger.md`.

### U6. `/en-foundation` authors and revises the Strategy section

- **Goal:** `/en-foundation --strategy` writes or revises a repo's Strategy section with the author, from evidence and a hypothetical stress-test; fresh and retrofit runs draft §1 the same way.
- **Requirements covered:** none (pending)
- **Dependencies:** U1, U2
- **Interfaces:**
  - *Produces:* the flag `--strategy` on `/en-foundation`, and the file `skills/en-foundation/references/strategy-mode.md`.
  - *Consumes:* `ensemble-strategy-section` from U2.
- **Files:**
  - `skills/en-foundation/references/strategy-mode.md` (create)
  - `skills/en-foundation/SKILL.md` (modify)
  - `skills/en-foundation/CONTRACT.md` (modify)
  - `skills/en-foundation/references/foundation-questions.md` (modify)
  - `skills/en-foundation/references/peer-brief.md` (modify)
  - `tests/evals/cases/en-foundation.json` (modify)
  - `tests/lint/en-foundation-strategy.test.sh` (create)
- **Approach:** `strategy-mode.md` owns the flow, in order:
  1. **Locate.** Run `ensemble-strategy-section`. A marked section means delta mode: it is the baseline, and the run proposes only line-level changes backed by evidence newer than the marker's date, each accepted or declined on its own. Exit 3 stops and asks the author which heading is the strategy. `--strategy` with no `docs/foundation.md` stops and names `/en-foundation`.
  2. **History gate** (`--strategy` and `--retrofit` only). `git rev-list --count <default-branch>` under 20 stops with "This repo has <N> commits; a strategy drawn from that little history would be guesswork." The run continues only on the author's own words saying to proceed without history; then each line cites the author's answers instead of history. A fresh (greenfield) run skips the gate and mining, and drafts from the author's answers.
  3. **Mine.** Merged PRs via `gh pr list --state merged --limit 100` (titles), 8 to 15 full bodies spread across the range; fallback `git log` on the default branch. Also read the README, §2, any principles section and the D-ID log. Write an evidence sheet (value → PRs, commits, files, D-IDs) to `/tmp/ensemble/en-foundation/<run-id>/strategy-evidence.md`; never into the repo. Generic virtues with no specific evidence are dropped.
  4. **Draft** to the U1 anatomy, every line traceable to the evidence sheet or an author answer.
  5. **Stress-test.** 8 to 12 fault-line hypotheticals: tempting off-mission features, principle collisions, slippery slopes, scope expansions, open identity questions. Each names the proposal in 2 to 4 sentences, quotes the ST line it tests, and steelmans both sides. Replace any whose answer you can predict. Ask them one at a time with `QUESTION_TOOL`; after each answer, fold the reasoning into the draft and show a one-line changelog (`H3 no → ST2 now says ...`). Never copy hypotheticals or answers into the repo.
  6. **Approve.** The author approves the full text explicitly. Silence, or approving one card, is not approval.
  7. **Write.** In delta mode, replace only the lines of the section the reader located, wherever it sits and whatever its number; nothing else moves. Only when no section exists: retitle §1 in place to `## 1. Strategy` and replace its body, or, with no §1, insert the section after the title block and before the first `##`. Refresh the marker date. ST-IDs are append-only; a removed principle is marked `(retired YYYY-MM-DD)`.
  8. **Consolidate.** List numbered proposals for lines elsewhere that repeat the strategy (judged by meaning): §2.2 becomes the one-line pointer; others are deleted or pointed. Apply only those the author says yes to. Offer the AGENTS.md "Where things live" row and the Stable IDs entry when absent, since `/en-setup` never rewrites an existing AGENTS.md.
  9. **Close debt.** If `docs/plans/tech-debt-tracker.md` has an open entry with rule key `strategy-missing`, move it to Resolved with `Resolved: YYYY-MM-DD by /en-foundation --strategy`.
  10. **Peer.** Under `--strategy`, run the existing Outside Voice with the extracted section as `--artifact-file` and `--goal "Strategy review"`; fresh and retrofit runs keep their whole-foundation pass.

  In `SKILL.md`: step 3 detects `--strategy` (strategy-only mode: steps 4 to 10 of the normal flow do not run); step 9 drafts §1 by `references/strategy-mode.md`; add the flag to the Flags table; add "strategy" to the description's trigger phrases. Mirror the flag in `CONTRACT.md`. In `foundation-questions.md`, the §1 group asks what the project exists to do, who it serves, the one thing it owns, and what it refuses. In `peer-brief.md`, add a dimension: a Strategy line a reviewer could not apply to a concrete PR, and a non-goal with no named example. Add the trigger-rank positive "Write down this repo's strategy: what it owns, what it refuses, and how to judge a change". Keep `SKILL.md` under the 26,624-byte cap (currently 17,721).
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* the pin finds, in `strategy-mode.md`, the 20-commit gate, "Replace any whose answer you can predict", one-at-a-time `QUESTION_TOOL`, the evidence sheet path under `/tmp/ensemble/`, the append-only retire rule, and the `strategy-missing` resolve step.
  - *Happy path:* the pin finds `--strategy` in `SKILL.md`'s Flags table and in `CONTRACT.md`.
  - *Edge case:* the pin finds that delta mode keeps the baseline and proposes line-level changes.
  - *Error path:* negative controls: removing the history gate sentence, or the "silence is not approval" sentence, from a temp copy makes the test fail.
  - *Integration:* `tests/evals/trigger.test.sh` keeps rank-1 at or above its floor with the new positive.

  The behavioral harness has no foundation kind, and adding one is out of scope, so the gates are also checked by a **manual procedure** run once during the build in scratch repos, each outcome recorded in `tests/evals/ledger.md`:
  - *History gate, no override:* a repo with 5 commits and a foundation with no Strategy section, `/en-foundation --strategy` → stops naming the commit count; `git diff --exit-code docs/foundation.md` passes.
  - *History gate, override:* same repo, the author answers "proceed without history" → after approval §1 is `## 1. Strategy` with the marker dated today and `### ST1.` onward.
  - *No foundation:* `/en-foundation --strategy` in a repo without `docs/foundation.md` → stops naming `/en-foundation`; nothing written.
  - *Duplicate headings:* a foundation with two `## Strategy` headings → stops and asks which; nothing written.
  - *Approval withheld:* the author answers every hypothetical and then declines the full text → no write; `git diff --exit-code` passes.
  - *Delta elsewhere:* a foundation whose §1 is an unrelated Executive Summary followed by a marked, unnumbered `## Strategy` section; an approved delta → the Executive Summary is byte-identical and there is exactly one, updated Strategy section.
  - *Delta retire:* a 30-commit repo whose section declares ST1 to ST3, the author approves retiring ST2 → ST2's heading carries `(retired <today>)`, ST1 and ST3 keep their numbers, no ID is reused, and the marker date is today.
- **Verification:** `./tests/run.sh -k en-foundation`, `-k trigger`, `-k skill-size` pass; the seven manual outcomes are in the ledger.

### U7. `/en-setup` State 3 reports a missing Strategy section

- **Goal:** `/en-setup`'s diagnostic shows 🟢 with a Strategy section and 🟡 "run /en-foundation --strategy" without one.
- **Requirements covered:** none (pending)
- **Dependencies:** U6
- **Files:**
  - `skills/en-setup/scripts/check-health` (modify)
  - `skills/en-setup/SKILL.md` (modify)
  - `tests/en-setup/strategy-advisory.test.sh` (create)
- **Approach:** In `check-health`, after the `docs/foundation.md` row: when the foundation exists and the sibling `"$(dirname "$0")/ensemble-strategy-section" docs/foundation.md` (carried by `en-setup` since U2) prints anything → `check "Strategy section" green`; exit 3 → `check "Strategy section" yellow "Two Strategy headings in docs/foundation.md"`; else `check "Strategy section" yellow "No Strategy section; run /en-foundation --strategy"`. No repair offer, because nothing mechanical repairs it. Add one State 3 bullet to `SKILL.md` naming the row and the hand-off. Write the test in the shape of `tests/en-setup/analytics-store-advisory.test.sh`.
- **Risk:** low
- **Category:** diagnostics
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* a temp repo whose foundation has the marker → the output has the Strategy row in green.
  - *Edge case:* a foundation without the marker → yellow row naming `/en-foundation --strategy`.
  - *Edge case:* no foundation → no Strategy row (the existing foundation row already reports it).
  - *Edge case:* a marker sitting outside the Strategy section, or a `## Strategy` heading only inside a fenced block → yellow, matching the reader.
  - *Error path:* two Strategy headings → yellow "Two Strategy headings".
- **Verification:** `./tests/run.sh -k strategy-advisory`, `-k state-detection`, `-k skill-size` pass.

### U8. `/en-sweep` files strategy debt and never edits the section

- **Goal:** Each sweep files one tracked entry when a repo has no Strategy section, and one per ST line whose factual claim no longer matches the repo.
- **Requirements covered:** none (pending)
- **Dependencies:** U2, U6
- **Interfaces:**
  - *Consumes:* `ensemble-strategy-section` from U2 and `ensemble-td-append` (existing).
- **Files:**
  - `skills/en-sweep/SKILL.md` (modify)
  - `skills/en-sweep/references/sweep-checks.md` (modify)
  - `skills/en-sweep/scripts/ensemble-doc-only-check` (modify)
  - `tests/en-sweep/doc-only-enforcement/doc-only.test.sh` (modify)
  - `tests/en-sweep/strategy-debt.test.sh` (create)
  - `tests/lint/en-sweep-strategy.test.sh` (create)
- **Approach:** Add a step to the sweep Process, with a new category "G. Strategy" in `sweep-checks.md`. When `docs/foundation.md` exists and `ensemble-strategy-section` prints nothing, file with `ensemble-td-append --rule-key strategy-missing --source /en-sweep --severity P3 --confidence 10 --enforce-at "L4 skill" --location docs/foundation.md --title "No Strategy section" --why "No review can check a change against the project's principles" --fix "Run /en-foundation --strategy"`; the rule key's dedupe means a weekly run never re-files it. When the section exists, compare each ST line's checkable claims (counts, named files, flags, "never"/"no" statements) against the repo, and file a drift entry per ST-ID with `--rule-key strategy-drift-st<N>` naming the line and the contradicting fact. Sweep never edits the Strategy section, in its fix-up PRs or anywhere else: the author owns it, and the fix is `/en-foundation --strategy`. That rule is enforced, not only stated: `ensemble-doc-only-check`, which sweep already runs on its staged diff, gains a second check. When `docs/foundation.md` is staged, it runs `ensemble-strategy-section` over `git show HEAD:docs/foundation.md` and over the staged blob (`git show :docs/foundation.md`), each written to a temp file, and exits 1 with "en-sweep never edits the Strategy section; file a strategy-drift TD instead" when the two outputs differ. A non-zero reader exit on either revision (two Strategy headings) also exits 1, with "cannot read the Strategy section in <HEAD|staged> docs/foundation.md; resolve the duplicate heading outside sweep", before any comparison.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* a staged edit to `docs/foundation.md` §4 only → `ensemble-doc-only-check` exits 0.
  - *Error path:* a staged edit to a line inside the Strategy section → exit 1 with the message; a staged edit that only moves the marker date → exit 1.
  - *Edge case:* a foundation with no Strategy section in HEAD or the index → the second check passes.
  - *Error path:* HEAD has two Strategy headings and the staged blob changes one Strategy body → exit 1 with the cannot-read message.
  - *Edge case (`strategy-debt.test.sh`):* run the exact `ensemble-td-append` command for `strategy-missing` twice against a temp tracker → one open entry, the second call refused by the rule key.
  - *Edge case (`strategy-debt.test.sh`):* the `strategy-drift-st2` command after `strategy-drift-st1` → two entries, keyed per ST-ID.
  - *Pin:* the test finds both rule keys and the never-edits clause in `SKILL.md` or `sweep-checks.md`; negative control: deleting the clause from a temp copy makes it fail.

  Model judgment on drift is checked by a **manual procedure** run once during the build, recorded in `tests/evals/ledger.md`: a scratch repo whose ST1 says "the CLI has 3 commands" while it has 4, swept twice → one `strategy-drift-st1` entry naming the line and the fourth command; `docs/foundation.md` unchanged; and a repo whose strategy matches its code → no strategy entry.
- **Verification:** `./tests/run.sh -k en-sweep`, `-k doc-only`, `-k strategy-debt`, `-k skill-size` pass; the manual outcome is in the ledger.

### U9. Record the decision and update Ensemble's maps

- **Goal:** The foundation, AGENTS.md and CONTEXT.md describe the Strategy section, ST-IDs and the new flag.
- **Requirements covered:** none (pending)
- **Dependencies:** U1 to U8
- **Files:**
  - `docs/foundation.md` (modify)
  - `AGENTS.md` (modify)
  - `docs/CONTEXT.md` (modify)
  - `docs/reviews/strategy-section-review.md` (create)
- **Approach:** Add D150 to §4.1 in the established shape: what changed, why (the drift and the missing alignment check), **Not changed** (`/en-fix` triage, host personas, the external skill), **Cost** (about 70 lines per peer prompt in a repo with a strategy; no check with the peer off), and the enforcement tier (the tests from U2 to U8). Update §5.2.2 for `--strategy`, §10.2's stable-ID table with ST, and §18.1 with `cross-link.broken-st`. Add the Strategy row to AGENTS.md's "Where things live" and `ST<N>` to its Stable IDs convention. Add "Strategy" to `docs/CONTEXT.md`. Commit the review doc that motivated the plan (it exists untracked; the "create" marker reflects that it enters git here).
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Test expectation:** none — documentation; `bin/ensemble-lint` and the decision-log tests check it.
- **Verification:** `bin/ensemble-lint --scope docs/` clean; `./tests/run.sh -k decision-log-order` and `-k foundation-catalog-drift` pass.

### U10. Write Ensemble's own Strategy section

- **Goal:** `docs/foundation.md` §1 is an author-approved Strategy section with ST-IDs, written by following `strategy-mode.md`.
- **Requirements covered:** none (pending)
- **Dependencies:** U6, U9
- **Files:**
  - `docs/foundation.md` (modify)
  - `AGENTS.md` (modify)
- **Approach:** Follow `skills/en-foundation/references/strategy-mode.md` by hand on this repo, in `--strategy` mode: mine its merged PRs and the D-ID log, draft from §1's pillars, §2, §3.3 and §17, and run the hypotheticals with the author. The drafts must put the two known contradictions to the author as hypotheticals: the "11-skill" count, and "no telemetry" against the local analytics ledger. The author's answers decide the lines; any line that reverses a D-ID gets a new D-ID. Retitle §1 to `## 1. Strategy`, make §2.2 the pointer, and apply only the consolidation edits the author approves. **The build stops for the author's explicit approval of the full text before writing.**
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Test expectation:** none — content; checked by the tools this plan ships.
- **Verification:** `skills/en-review/scripts/ensemble-strategy-section --ids` lists the ST-IDs; `bin/ensemble-lint --scope docs/` clean; `skills/en-setup/scripts/check-health` shows the Strategy row green; `./tests/run.sh` passes in full.

## Decisions, assumptions & risks

- **Decision:** The strategy is §1 of `docs/foundation.md`, not a separate file, to keep G2's one foundation document and one home for non-goals. Skills find it by heading and marker, never by number.
- **Decision:** `ST<N>` IDs, because a bare `S<N>` collides with "S3" in adopting repos.
- **Decision:** The marker is required. A Strategy heading without it counts as absent, so a hand-written section is not silently trusted as author-approved.
- **Decision:** `en-review` gets the strategy from its prompt builder, keyed on the brief's `### strategy` dimension, with no flag. Its SKILL.md is 27 bytes under the cap, and a script cannot forget the step.
- **Decision:** Only the peer checks the strategy. With `peer_mode: off` no check runs; the user chose this over adding a host persona.
- **Decision:** `/en-sweep` and `/en-setup` detect and point; only `/en-foundation` writes, with the author.
- **Decision:** `--strategy` and `--retrofit` stop below 20 commits unless the author says to proceed in their own words; a fresh run skips the gate.
- **Alternative:** Installing the external `/vision` skill. Rejected: unpinned `npx -y lavish-axi`, a root file outside `docs/`, no stable IDs and no consumption path.
- **Alternative:** An explicit `--strategy-file` flag on the prompt builder, like `--plan-file`. Rejected: it needs `en-review` SKILL.md bytes and relies on the agent remembering it.
- **Assumption:** The peer applies the "resisted when" test with useful precision. Checked after U10 by running `/en-review` on a branch that crosses an ST line on purpose.
- **Risk:** Peer prompts grow by about 70 lines in repos with a strategy. **Mitigation:** the 40 to 70 line cap in the anatomy.
- **Risk:** A vague principle produces vague findings. **Mitigation:** the stress-test, and the en-foundation peer dimension for untestable lines.
- **Risk:** The trigger-rank floor moves when en-foundation's description changes. **Mitigation:** U6 runs the trigger eval and adjusts wording, never the floor.
- **Risk:** Sweep drift entries are model judgment and may be noisy. **Mitigation:** they are P3 tracked entries, deduped per ST-ID, and `ensemble-doc-only-check` blocks any sweep edit to the section.
- **Decision:** A citation is plain-text `ST<N>`; backticked and fenced IDs are examples. **Risk:** a real citation written in backticks goes unchecked. Accepted: it fails open on a doc-reference check, and the convention matches how D-entries cite TD- and R-IDs in plain text.
- **Decision:** en-foundation's gates and sweep's drift judgment are verified by recorded manual procedures, not a new behavioral-eval kind; adding a foundation or sweep kind to `run-behavioral` and `grade` is machinery this plan does not need.

## Tracked debt

None resolved.

## Iteration log

> - 2026-11-24 (initial): plan v0 from `docs/reviews/strategy-section-review.md` §4 and §5, and two question rounds.
> - 2026-11-24 (peer pass 1, codex): revise. Applied all six findings (5 P1, 1 P2): plain-text citation rule, one recognition shared by reader, lint and check-health, behavioral cases for en-plan, manual procedures for en-foundation and sweep drift, doc-only-check guard on the Strategy section, Strategy: Scope titles.
> - 2026-11-24 (peer pass 2, codex): revise, cap reached. Applied both findings: delta mode replaces only the located section (P1); the sweep guard fails closed on a reader error (P2).
> - 2026-11-24: the user accepted the plan as-is at the cap; status open.
