---
type: plan
plan_type: feature
plan_id: EN22
title: Correction router, route each correction to the strongest enforcement layer
status: open
location: active
created: 2026-09-26
shipped:
deepened:
covers_requirements: []
requirements_pending: false
related_design: docs/designs/2026-09-26-agent-trust-strategy-design.md
peer_review_verdict: revise
peer_review_iterations: 3
peer_review_last_run: 2026-09-26
peer_review_plan_hash: f92fa260502d07d1889a1d653051533f1afffd0f1e6af99365a666a08c2f7e94
peer_review_resolutions:
  - {finding_id: 1-1, iteration: 1, severity: P1, title: "Recurrence is missed across sweep runs", status: applied, location: U6}
  - {finding_id: 1-2, iteration: 1, severity: P1, title: "The TD gate accepts a check with no assertion", status: applied, location: U2}
  - {finding_id: 1-3, iteration: 1, severity: P1, title: "Audit inventory misses ordinary imperative rules", status: superseded, rationale: "inventory script removed in the slimming pass; audit mode reads the map files whole, so no line can be filtered out", location: U5}
  - {finding_id: 1-4, iteration: 1, severity: P1, title: "An existing prose rule stops capture before stronger routing", status: applied, location: U3}
  - {finding_id: 1-5, iteration: 1, severity: P1, title: "L3 capture writes a rule despite the proposed-only contract", status: applied, location: U3}
  - {finding_id: 1-6, iteration: 1, severity: P1, title: "Review routing has no behavioral scenarios", status: superseded, rationale: "review-routing unit withdrawn in the slimming pass; review and resolve-pr are unchanged", location: withdrawn review-routing unit}
  - {finding_id: 1-7, iteration: 1, severity: P1, title: "Audit mode is tested only through its inventory script", status: superseded, rationale: "inventory script removed; filing and dedupe are tested through ensemble-td-append (U2), classification stays with TD7", location: U5}
  - {finding_id: 1-8, iteration: 1, severity: P2, title: "Line-number matching cannot make audit reruns converge", status: applied, location: U2, U5}
  - {finding_id: 1-3, iteration: 2, severity: P1, title: "Audit inventory still misses imperative prose", status: superseded, rationale: "inventory script removed; see iteration-1 entry", location: U5}
  - {finding_id: 2-1, iteration: 2, severity: P1, title: "Capture routes L4 and L5 outside the stated TD contract", status: applied, location: U1, U3}
  - {finding_id: 2-2, iteration: 2, severity: P1, title: "Fixed PR comments route only L1 and L2 corrections", status: superseded, rationale: "review-routing unit withdrawn: filing per fixed comment added a classification cycle to every PR and duplicated the U6 recurrence scan, which is the agreed trigger", location: withdrawn review-routing unit}
  - {finding_id: 3-1, iteration: 3, severity: P1, title: "The add-now path can lose a correction", status: applied, location: U3}
  - {finding_id: 3-2, iteration: 3, severity: P1, title: "Recurrence tests stop before the core outcome", status: applied, location: U6}
  - {finding_id: 2-3, iteration: 2, severity: P1, title: "Capture and review callers have no rule-key contract", status: applied, location: U2}
depth: standard
data_scale: small
---

# EN22: Correction router

## Context

Foundation §17.1 says every skill failure should become an enforced capability. No skill does this: `/en-learn capture` writes prose or nothing. The design doc (Track A, item A5) adopts the five-layer ordering from the pstack talk: fix a correction in the codebase if possible, else in static analysis, else rules, else skills, and prose last.

This plan builds that router with the smallest footprint that works. There are two entry points:
- capture, which already runs once per build;
- an opt-in recurrence scan in the off-hours sweep.

An audit mode applies the same rubric to a repo's existing prose rules. Emble is the pilot, through a separate Emble plan after this ships.

**Leanness constraint.** Every new check must replace or shrink an existing cycle, or stay off the hot paths. `/en-build`, `/en-review`, `/en-resolve-pr` and `/en-ship` are unchanged by this plan. Capture gains one question, asked only of candidates that already passed its gate.

## Requirements covered

`docs/foundation.md` carries no R-IDs for skill behaviour; this plan implements the §17.1 operating principle and design doc item A5.

## Out of scope for this plan

- Classifying TD entries filed by `/en-review` or `/en-resolve-pr`. Withdrawn with the review-routing unit; repeats reach the router through the U6 recurrence scan instead.
- Writing lint rules or tests in a target repo from the router. It proposes; capture can hand a proposal back for the current branch, and anything else goes through a normal plan.
- The Emble conversions themselves. After EN22 ships, `/en-learn --enforce-audit` runs in Emble and its TD entries seed an Emble `EM` plan.
- A `category` or `layer` field in the peer finding schema.
- A model eval of classification accuracy (TD7 owns the eval harness).
- `docs/golden-principles.md` (design doc item B2).

## Approach (high-level)

One rubric, `references/enforcement-layers.md`, defines the layers and the order they are tried in:

- **L1 structure:** make the mistake unrepresentable (types, module boundaries, one paved path).
- **L2 static analysis:** a lint rule, an invariant test, a compiler or CI check.
- **L3 rules:** `AGENTS.md`, `CLAUDE.md`, `REVIEW.md`.
- **L4 skills.**
- **L5 prose:** a learning or style note.

The strongest layer that can express the correction wins. An L1 or L2 answer must name a concrete check: the file it lives in plus the rule or assertion it adds. Only `/en-learn` and `/en-sweep` carry the rubric, as byte-identical copies.

Outcomes:

- **L1 to L4** produce a TD entry proposing the change. One script, `ensemble-td-append`, writes it with two new fields, `Enforce at:` and `Proposed check:`, and a `Rule key:` for deduplication.
- **L5** stays a prose learning through `/en-learn`'s existing routing.

A new `ensemble-lint` rule fails any L1 or L2 entry without a concrete check. That is the mechanical gate, and it costs the model nothing at run time.

**The lever, now or later.** When capture classifies an L1 or L2 correction whose check lives in the repo being worked on, it asks one question: add the check on this branch now, or file it. Filing is the default for unattended callers. This is the talk's "write the lint when you see the mistake", without making it automatic.

Entry points:

- **`/en-learn capture`:** one classification step between the gate and artifact routing.
- **`/en-learn --enforce-audit`:** reads `AGENTS.md`, `CLAUDE.md` and `REVIEW.md` whole, classifies each rule, and files the ones that belong at L1 or L2 and have no check. It is a reference file with no script.
- **`/en-sweep` step 8b (opt-in):** a script pulls review threads from a trailing window of merged PRs. The model clusters them, and a cluster spanning two or more PRs becomes one routed TD entry.

## Test seams

Three seams, all existing kinds in this repo:

1. **Script I/O on fixtures.** `ensemble-td-append` runs against fixture trackers. `ensemble-review-history` runs with a `gh` stub on `PATH`, following `tests/en-sweep/runner.test.sh`.
2. **`bin/ensemble-lint` on tracker fixtures.** Good and bad fixtures, with negative controls.
3. **One anchored prose assertion per edited file.** Each is scoped to a single file and anchored on wording only that file carries.

The model's choice of layer is not tested (TD7).

## Technical design

Triggers fired: three data-flow stages (source, router, gated output).

```
en-learn capture ─────────┐
en-learn --enforce-audit ─┼─▶ enforcement-layers.md ─▶ L1-L4: ensemble-td-append ─▶ td.enforce-layer lint
en-sweep 8b recurrence ───┘   (strongest layer wins)   L5: existing learning routing
```

Script contracts:

- **`ensemble-td-append --list-keys --tracker <path>`**
  - Prints one line per open entry: `TD<N>\t<rule key or ->\t<title>`.
  - Every caller reads this before filing and reuses the key of an open entry that describes the same correction.
- **`ensemble-td-append --tracker <path> --title <t> --source <s> --severity P0-P3 --confidence 1-10 --location <l> --why <w> --fix <f> --enforce-at L1-L4 [--check "<path>: <rule>"] --rule-key <k>`**
  - The rule key is a kebab-case slug naming the correction, such as `no-orm-return-from-routes`. The appender normalizes it: lowercased, whitespace to hyphens, 12-hex digest past 64 characters.
  - It appends one entry under `## Open`, taking the next TD number after the highest existing one.
  - It refuses L1 or L2 without a check whose path part and rule part are both non-empty, and refuses L5.
  - An open entry with the same key means no write.
  - Exit codes: 0 appended, printing the new TD-ID; 4 duplicate, printing the existing TD-ID; 2 usage or validation error; 1 tracker missing or no `## Open` section.
- **`ensemble-review-history --since <iso-date> [--repo <owner/name>] [--limit <n>]`**
  - Runs `gh api graphql` over PRs merged since the date.
  - Prints JSON lines: `{"pr": 118, "path": "...", "author": "...", "bot": false, "body": "...", "resolved": true}`.
  - Exit codes: 0 on success, 3 when no PRs matched, 1 when `gh` fails, with stderr naming the failure. It never reports an empty result as success.

## Implementation units

### U1. Enforcement-layer rubric and tracker fields

- **Goal:** One definition of L1 to L5, the selection order and the new TD fields, carried by the two skills that route.
- **Requirements covered:** none (foundation §17.1)
- **Dependencies:** none
- **Files:**
  - `skills/en-learn/references/enforcement-layers.md` (new)
  - `skills/en-sweep/references/enforcement-layers.md` (new, byte-identical)
  - `skills/en-review/references/tech-debt-tracker-format.md`
  - `skills/en-sweep/references/tech-debt-tracker-format.md`
  - `tests/parity/enforcement-layers-parity.test.sh` (new)
  - `docs/foundation.md` (§17.1 and a new D123 in §4)
- **Approach:**
  - **The rubric** has four parts:
    - the five layers, each with a one-line test ("could a type or module boundary make this impossible?");
    - the rule that the strongest expressible layer wins;
    - what "concrete check" means;
    - two worked examples. Emble's "never branch on `source_system`" goes to L2, as an AST guard beside `backend/tests/test_architecture_invariants.py`. Ensemble's SKILL.md size budget is already L2 via `tests/lint/skill-size.test.sh`.

    It also states that routing proposes and never edits a map file, lint config, skill or test itself. Target length is 80 lines or fewer, because both carriers load it.
  - **The tracker format** gains three optional fields: `Enforce at:` (`L1 structure | L2 static | L3 rules | L4 skill`), `Proposed check:` (`<path>: <rule or assertion>`, required for L1 and L2), and `Rule key:`. Both carriers get the same edit.
  - **The parity test** pins exactly two carriers by name. A missing or divergent copy fails, modelled on `peer-contract-parity.test.sh`.
  - **Foundation.** §17.1's list points at the rubric instead of the nonexistent `golden-principles.md`. D123 records the router decisions, including the leanness constraint.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Patterns to follow:** `tests/parity/peer-contract-parity.test.sh`; memory rule "guards need negative controls".
- **Test scenarios:**
  - *Happy path:* two identical carriers, so the parity test passes.
  - *Error path:* one carrier edited by one byte, so the test fails and names it.
  - *Error path:* one carrier deleted, so the test fails on the pinned count.
  - *Edge case:* both `tech-debt-tracker-format.md` copies stay identical, which `reference-parity.test.sh` checks.
- **Verification:** The targeted tests pass, both negative controls go red when forced, and `bin/ensemble-lint --scope docs/foundation.md` is clean.

### U2. TD-entry mechanics: `td.enforce-layer` lint rule and `ensemble-td-append`

- **Goal:** One script writes routed TD entries and one lint rule checks them, so filing, numbering, deduplication and the concrete-check rule are code under test.
- **Requirements covered:** none
- **Dependencies:** U1
- **Interfaces:**
  - *Produces:* `ensemble-td-append`, with the flags and exit codes in Technical design. U3, U5 and U6 call it.
- **Files:**
  - `bin/ensemble-lint`
  - `skills/en-setup/references/templates/ensemble-lint`
  - `skills/en-sweep/references/doc-lints.md`
  - `skills/en-learn/scripts/ensemble-td-append` (new)
  - `skills/en-sweep/scripts/ensemble-td-append` (new, byte-identical)
  - `tests/lint/td-enforce-layer.test.sh` (new)
  - `tests/en-learn/td-append.test.sh` (new)
  - `tests/fixtures/td-enforce-layer/` (new)
- **Approach:**
  - **Lint.** For each `### TD<N>.` block under `## Open` in `docs/plans/tech-debt-tracker.md`, emit `td.enforce-layer`:
    - P1 when the layer is L1 or L2 and the check is missing or empty, has no `<path>:` prefix, or has nothing after the colon;
    - P2 for an unknown layer value;
    - nothing when the fields are absent, so TD1 to TD23 stay valid.

    Ignore `## Resolved`. Both linter copies change identically. Catalog the rule in `doc-lints.md`.
  - **Appender.** POSIX sh plus awk. It validates with the same rule the lint applies. Byte parity between its two copies comes from `script-parity.test.sh`.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Patterns to follow:** the `cross-link.broken-td` block in `bin/ensemble-lint` (around line 514).
- **Test scenarios:**
  - *Happy path:* `Enforce at: L2 static` with `Proposed check: backend/tests/test_architecture_invariants.py: forbid source_system == comparisons` produces no finding.
  - *Error path:* L1 with no `Proposed check:` gives P1, naming the TD-ID.
  - *Error path:* `Proposed check: add a lint` (no path) gives P1. `Proposed check: tests/guard.sh:` (nothing after the colon) gives P1.
  - *Error path:* `Enforce at: L9` gives P2.
  - *Edge case:* an entry with neither field gives nothing, and the real tracker lints clean. An L2 entry under `## Resolved` gives nothing.
  - *Appender, happy path:* a fixture whose highest entry is TD23 gets TD24 under `## Open`. The call exits 0, prints `TD24`, and the result lints clean.
  - *Appender, duplicate:* the same key again exits 4, prints `TD24`, and leaves the file byte-unchanged.
  - *Appender, validation:* L2 with `--check "tests/guard.sh:"` exits 2. `--enforce-at L5` exits 2. Neither writes.
  - *Appender, error path:* a tracker with no `## Open` exits 1 and writes nothing.
  - *Appender, list keys:* TD23 with no key and TD24 keyed `no-orm-return-from-routes` both print, with `-` for TD23's key.
- **Verification:** Both tests pass and end with `report`. Deleting the lint's emit line or the appender's duplicate check turns the matching cases red. `bin/ensemble-lint --scope docs/` is clean. The linter copies are byte-identical, and so are the appender copies.

### U3. `/en-learn capture` routes before it writes

- **Goal:** Capture classifies each candidate that passed its gate. An enforceable correction becomes a filed proposal, optionally added on the branch now, instead of a prose learning.
- **Requirements covered:** none
- **Dependencies:** U1, U2
- **Files:**
  - `skills/en-learn/SKILL.md`
  - `skills/en-learn/references/capture-gate.md`
  - `skills/en-learn/references/artifact-types.md`
  - `tests/lint/en-learn-capture-gate.test.sh`
  - `tests/lint/en-learn-enforcement-routing.test.sh` (new)
- **Approach:**
  - **Capture gate.** Split "what does not qualify" into two states:
    - *Already enforced at the strongest feasible layer*: write nothing, as today.
    - *Covered only at a weaker layer, or not at all*: route to the rubric. An `AGENTS.md` rule for something a lint could check counts as not enforced.
  - **Artifact types.** Gains an *enforcement* outcome ahead of term, decision and solution:
    - L1 to L4 go through `ensemble-td-append`, with `Source: en-learn capture` and a key reused from `--list-keys` when one matches. No learning file is written.
    - The TD entry is always filed, so no correction is lost. For L1 or L2 with a check path inside the current repo, capture then asks one question: "add this check on the branch now?" "Yes" hands the proposal back to the caller as the next piece of work, and the entry is resolved by the normal flow when the check lands. Unattended callers (`CI=true`, `/en-loop`) don't ask.
    - Only L5 reaches term, decision or solution routing.
  - **Worked examples,** as input and expected output:
    - "routes never call `useAuthFetch` directly", in `AGENTS.md` and checked by nothing, goes to L2 with a biome `noRestrictedImports` rule scoped to `frontend/src/routes/`.
    - A correction covered by `tests/lint/skill-size.test.sh` produces no write.
    - "`/en-build` forgot the simplify pass" goes to L4, naming `skills/en-build/SKILL.md` and the step.
    - "TD numbers are append-only because `/en-plan` cites them" goes to L5 as a decision learning.
  - **SKILL.md.** One step between gate (step 4) and routing (step 5) that cites the two references. **Budget: 400 bytes or fewer** added to this file by this unit.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Patterns to follow:** `tests/lint/en-learn-capture-gate.test.sh` locks shape, not wording.
- **Test scenarios:**
  - *Happy path:* `capture-gate.md` names both states and says a prose-only rule is not enforcement (anchored).
  - *Happy path:* `artifact-types.md` lists enforcement first, names the appender, says the entry is filed before the add-now question, gives the question's unattended default, and carries the four worked examples (anchored).
  - *Error path:* `artifact-types.md` has no instruction to edit a map file as part of routing (negative assertion).
  - *Edge case:* the SKILL.md step cites `enforcement-layers.md` once. The file grows 400 bytes or fewer against the pre-unit size, measured in the test, and `skill-size.test.sh` passes.
  - *Error path:* the existing write-nothing default assertion still holds.
- **Verification:** The targeted tests pass. A recorded dry run on the four worked examples gives the expected outcomes: one L2 entry that lints clean, one no-write, one L4 entry and one L5 learning. The excerpt goes in the PR body.

### U5. `/en-learn --enforce-audit`

- **Goal:** Given a repo, classify its existing prose rules and file TD entries for those that belong at L1 or L2 and have no check.
- **Requirements covered:** none
- **Dependencies:** U1, U2, U3
- **Files:**
  - `skills/en-learn/references/enforce-audit.md` (new)
  - `skills/en-learn/SKILL.md` (one modes-table row)
  - `tests/lint/en-learn-enforce-audit.test.sh` (new)
  - `README.md` (skill catalog row)
- **Approach:**
  - **The reference:**
    1. Read `AGENTS.md`, `CLAUDE.md` and `REVIEW.md` whole, since map files are short by convention.
    2. List the rules.
    3. For a rule that names a test or lint file, open it and confirm it enforces the rule.
    4. Classify the rest.
    5. File L1 and L2 rules through `ensemble-td-append`, with `Source: en-learn --enforce-audit`, `Location: <file>:<line>`, and a slug key reused via `--list-keys`.
    6. Print a table: rule, layer, check, TD-ID or `exists TD<N>`.
  - Reruns converge through key reuse. No learning files are written.
  - **SKILL.md** gets a modes-table row only. **Budget: 150 bytes or fewer** added.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* the SKILL.md modes table lists `--enforce-audit` and points at `enforce-audit.md` (anchored).
  - *Happy path:* `enforce-audit.md` names the three map files, the confirm-the-cited-check step, the appender call and `--list-keys` reuse (anchored).
  - *Edge case:* the SKILL.md growth stays within budget, and the README catalog drift test passes.
- **Verification:** The targeted tests pass. A recorded dry run against a copy of Emble's `AGENTS.md` files entries for the `source_system` and `useAuthFetch` rules, and a second run files none. The excerpt goes in the PR body.

### U6. `/en-sweep` recurrence scan and `ensemble-review-history`

- **Goal:** A correction repeated across two or more merged PRs becomes one routed TD entry.
- **Requirements covered:** none
- **Dependencies:** U1, U2
- **Files:**
  - `skills/en-sweep/scripts/ensemble-review-history` (new)
  - `skills/en-sweep/SKILL.md` (step 8b)
  - `skills/en-sweep/references/recurrence-scan.md` (new)
  - `tests/en-sweep/review-history.test.sh` (new)
  - `tests/fixtures/review-history/` (new)
- **Approach:**
  - **Window.** Step 8b passes `--since` as today minus `sweep.recurrence_window_days` (default 60). Every run re-reads the whole window, so matching PRs on either side of a sweep boundary land in one scan, and appender deduplication absorbs the overlap.
  - **Step 8b:**
    1. Run the script.
    2. Cluster comments by the correction they make.
    3. Keep clusters spanning two or more PRs.
    4. Reuse an open entry's key via `--list-keys`, or mint a slug.
    5. File through `ensemble-td-append` with `Source: en-sweep recurrence` and the PR numbers in `Location`. Exit 4 means already tracked.
  - Opt-in behind `sweep.recurrence_scan: true`, off by default. It stays doc-only, since the tracker sits under `docs/`.
  - Exit 3 is a clean skip. Exit 1 records `recurrence_scan: failed (<reason>)` in the summary, and the sweep continues.
  - **SKILL.md budget:** 500 bytes or fewer added. The procedure lives in the reference.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Patterns to follow:** `gh` stubbing in `tests/en-sweep/runner.test.sh`; step 8a's partition.
- **Test scenarios:**
  - *Happy path:* the stubbed `gh` returns two PRs with three threads, and the script prints three JSON lines.
  - *Edge case:* no PRs gives exit 3 with empty stdout.
  - *Error path:* the `gh` stub exits 1, so the script exits 1 with `gh` named on stderr. It never exits 0.
  - *Edge case:* a bot comment carries `"bot": true`.
  - *Edge case, sweep boundary:* PR 101, merged 40 days ago, and PR 130, merged 3 days ago, match; the last sweep ran 20 days ago. A 60-day `--since` returns both. `--since` set to the last sweep date returns only PR 130.
  - *Integration:* step 8b is gated on `sweep.recurrence_scan` and passes a trailing-window `--since`. `recurrence-scan.md` states the two-PR threshold and key reuse (anchored per file).
- **Verification:** The script tests pass with negative controls, and the SKILL.md growth stays within budget.
  - A recorded end-to-end dry run of step 8b uses the `gh` stub fixture: two PRs carry the same correction and a third carries an unrelated comment. The result is exactly one TD entry listing both PR numbers. A rerun files nothing, because the appender returns exit 4. The excerpt goes in the PR body.
  - The full suite passes once before commit.

## Decisions, assumptions & risks

- **Decision:** The router stays off the hot paths. `/en-build`, `/en-review`, `/en-resolve-pr` and `/en-ship` are unchanged. The review-routing unit was withdrawn in the slimming pass: filing a TD entry per fixed PR comment added a classification step to every PR and duplicated U6, whose two-PR threshold is the agreed trigger.
- **Decision:** Two carriers, `/en-learn` and `/en-sweep`. A new `/en-enforce` skill or more carriers would add copies and hand-offs for no gain.
- **Decision:** There is no inventory script. After two review rounds it had become "print every prose line of a ~100-line file", which the model does by reading the file.
- **Decision:** One script writes TD entries. Numbering, deduplication and the concrete-check rule are code under test; only the choice of layer is judgment.
- **Decision:** Keys are slugs reused through `--list-keys`, never line numbers.
- **Decision:** No schema change. Recurrence is matched by clustering review history against open TD entries.
- **Decision:** Capture always files, then offers "add now" for L1 and L2 checks in the current repo. That is the talk's "write the lint when you see the mistake", kept to one question and skipped when unattended. The entry keeps the correction on record until the check lands.
- **Assumption:** The sweep machine's `gh` identity can read review threads. A failure is reported, not skipped.
- **Risk:** Classification drifts toward L5. **Mitigation:** the rubric's order, plus a later layer-distribution report from `Source` markers.
- **Risk:** Skill growth. **Mitigation:** per-unit byte budgets (U3 400, U5 150, U6 500), each asserted in that unit's tests.

## Tracked debt

None resolved. TD7 (classification eval) is related and stays open.

## Iteration log

> - 2026-09-26 (initial): plan v0 from `docs/designs/2026-09-26-agent-trust-strategy-design.md` item A5, after two planning rounds.
> - 2026-09-26 (peer iteration 1, codex, verdict revise): applied all 8 findings.
> - 2026-09-26 (peer iteration 2, codex, verdict revise, cap reached): applied all 4 findings; accepted by the user and committed.
> - 2026-09-26 (slimming pass, user-requested): the review loop had answered each finding with machinery, and round 2 sat inside round 1's fixes (the pattern in `docs/learnings/repeated-review-rejects-are-a-design-signal-2026-09-11.md`). Withdrew the review-routing unit. Removed `ensemble-rule-inventory`. Cut the rubric and appender from four carriers to two. Added per-unit SKILL.md byte budgets and the capture "add now or file" question. U-IDs U1, U2, U3, U5 and U6 are unchanged; the fourth ID is retired and not reused. Five resolutions marked superseded.
> - 2026-09-26 (peer iteration 3, codex, leanness brief, verdict revise): applied both findings without new machinery. Capture always files, then offers add-now. U6 gains a recorded end-to-end dry run.
