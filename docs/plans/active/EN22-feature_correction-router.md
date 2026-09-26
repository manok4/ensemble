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
peer_review_iterations: 2
peer_review_last_run: 2026-09-26
peer_review_plan_hash: e55d2d51f79ddde6f893e9b0d9bf333f5c0bb8a20a74f8710c8cc6f6092f737e
peer_review_resolutions:
  - {finding_id: 1-1, iteration: 1, severity: P1, title: "Recurrence is missed across sweep runs", status: applied, location: U6}
  - {finding_id: 1-2, iteration: 1, severity: P1, title: "The TD gate accepts a check with no assertion", status: applied, location: U2}
  - {finding_id: 1-3, iteration: 1, severity: P1, title: "Audit inventory misses ordinary imperative rules", status: applied, location: U5}
  - {finding_id: 1-4, iteration: 1, severity: P1, title: "An existing prose rule stops capture before stronger routing", status: applied, location: U3}
  - {finding_id: 1-5, iteration: 1, severity: P1, title: "L3 capture writes a rule despite the proposed-only contract", status: applied, location: U3}
  - {finding_id: 1-6, iteration: 1, severity: P1, title: "Review routing has no behavioral scenarios", status: applied, rationale: "worked input/output examples plus a deterministic appender under test; automated classification eval stays with TD7", location: U4}
  - {finding_id: 1-7, iteration: 1, severity: P1, title: "Audit mode is tested only through its inventory script", status: applied, rationale: "filing, dedupe and cited-check existence are now script-tested; classification choice stays with TD7", location: U5}
  - {finding_id: 1-3, iteration: 2, severity: P1, title: "Audit inventory still misses imperative prose", status: applied, location: U5}
  - {finding_id: 2-1, iteration: 2, severity: P1, title: "Capture routes L4 and L5 outside the stated TD contract", status: applied, location: U1, U3}
  - {finding_id: 2-2, iteration: 2, severity: P1, title: "Fixed PR comments route only L1 and L2 corrections", status: applied, location: U4}
  - {finding_id: 2-3, iteration: 2, severity: P1, title: "Capture and review callers have no rule-key contract", status: applied, location: U2}
  - {finding_id: 1-8, iteration: 1, severity: P2, title: "Line-number matching cannot make audit reruns converge", status: applied, location: U5}
depth: standard
data_scale: small
---

# EN22: Correction router

## Context

Foundation §17.1 says every skill failure should become an enforced capability, and names lints and golden principles as destinations. No skill does this. `/en-learn capture` writes prose or nothing; `/en-review` and `/en-resolve-pr` file TD entries with no view on how the problem could be prevented. The design doc (Track A, item A5) adopts the five-layer ordering from the pstack talk: fix a correction in the codebase if possible, else in static analysis, else rules, else skills, and prose last. This plan builds that router, the recurrence scan that feeds it, and an audit mode that turns a repo's existing prose rules into proposed checks. Emble is the pilot, through a separate Emble plan after this ships.

## Requirements covered

`docs/foundation.md` carries no R-IDs for skill behaviour; this plan implements the §17.1 operating principle and design doc item A5.

## Out of scope for this plan

- Writing lint rules or tests in any target repo. The router proposes; a normal plan in that repo builds.
- The Emble conversions themselves. After EN22 ships, `/en-learn --enforce-audit` runs in Emble and its TD entries seed an Emble `EM` plan.
- A `category` or `layer` field in the peer finding schema (rejected in planning, see Decisions).
- A model eval of classification accuracy (TD7 owns the eval harness).
- `docs/golden-principles.md` (design doc item B2).
- `docs/decisions/` migration; decisions stay inline in foundation §4.

## Approach (high-level)

One shared rubric, `references/enforcement-layers.md`, defines the layers and the order they are tried in:

- **L1 structure:** make the mistake unrepresentable (types, module boundaries, one paved path).
- **L2 static analysis:** a lint rule, an invariant test, a compiler or CI check.
- **L3 rules:** `AGENTS.md`, `CLAUDE.md`, `REVIEW.md`.
- **L4 skills.**
- **L5 prose:** a learning or style note.

The strongest layer that can express the correction wins. An L1 or L2 answer must name a concrete check: the file it lives in and the rule or assertion it adds. The rubric is carried byte-identically by `/en-learn`, `/en-review`, `/en-resolve-pr` and `/en-sweep` under a pinned-carrier parity test.

The TD entry is the router's output and its audit point. The tracker format gains two optional fields, `Enforce at:` and `Proposed check:`. A new `ensemble-lint` rule fails any entry marked L1 or L2 whose proposed check is missing or names no file. This is the mechanical gate that keeps the router from being prose-only.

The router runs in four places:

- **`/en-learn capture`** classifies before writing. Its capture gate distinguishes "already enforced" (write nothing, as today) from "enforceable but not yet" (file a TD entry with the proposed check instead of a prose learning).
- **`/en-review` and `/en-resolve-pr`** add the two fields to the TD entries they already file.
- **`/en-sweep`** gains a recurrence scan. A script pulls review threads from PRs merged since the last sweep. The model clusters them, and a cluster spanning two or more PRs becomes one classified TD entry.
- **`/en-learn --enforce-audit`**, a new mode. A script lists every imperative rule line in a repo's `AGENTS.md`, `CLAUDE.md` and `REVIEW.md`, and the model classifies each and files TD entries for the ones that should move up a layer.

## Test seams

Three seams, all existing kinds in this repo:

1. **Script I/O on fixtures.** Covers `ensemble-rule-inventory` and `ensemble-review-history`, run hermetically with fixture files and a `gh` stub on `PATH`. This follows the pattern in `tests/en-sweep/runner.test.sh`.
2. **`bin/ensemble-lint` on tracker fixtures.** Good and bad `tech-debt-tracker.md` fixtures, each with a negative control that proves the rule can fail.
3. **One anchored prose assertion per edited file.** One assertion per SKILL.md or reference edit, each scoped to a single file and anchored on wording only that file carries, per the `en-resolve-pr-seam.test.sh` convention. No whole-directory greps.

The model's classification choice is not tested (TD7).

## Technical design

Triggers fired: four changed components and three data-flow stages.

```
correction sources                router                     output + gate
------------------                ------                     -------------
en-learn capture   ─┐
en-review TD file  ─┤  enforcement-layers.md (L1..L5)   TD entry with
en-resolve-pr TD   ─┼─▶ strongest layer that works   ─▶  Enforce at: L<n>
en-sweep recurrence ┤  + concrete check for L1/L2       Proposed check: <file> <rule>
en-learn --enforce-audit ┘                                     │
                                                               ▼
                                          bin/ensemble-lint td.enforce-layer
                                          (L1/L2 without a check = P1)
```

Script contracts:

- **`ensemble-rule-inventory [--root <dir>]`**
  - Reads `AGENTS.md`, `CLAUDE.md` and `REVIEW.md` under the root. Missing files are skipped.
  - Prints JSON lines: `{"file": "AGENTS.md", "line": 52, "kind": "list", "text": "...", "key": "<12-hex>", "cited_checks": ["backend/tests/test_x.py"]}`.
  - Emits every prose line: every bullet or numbered list item as `kind: list`, and every other paragraph line as `kind: prose`. Map files are short by convention (AGENTS.md targets 100 lines), so emitting all of them costs little and means no imperative phrasing is missed, "Run the full suite before committing" included. Each line also carries `"modal": true` when it contains a rule word, matched case-insensitively as a whole word: `never`, `always`, `must`, `should`, `do not`, `don't`, `avoid`, `prefer`, `only`, `use`, `keep`. That flag is a hint for ordering, never a filter. Deciding which lines are rules is left to the model.
  - `key` is a digest of the file path plus the lowercased, whitespace-collapsed text. The line number is excluded, so the key survives unrelated edits that move the line.
  - `cited_checks` lists paths the line names that exist under the root and sit under `tests/`, `backend/tests/` or `bin/`, or are lint config files. A named path that doesn't exist is not listed.
  - Skips fenced code blocks, headings, tables, blank lines and frontmatter.
  - Exit codes: 0 when anything was found, 3 when no rule files exist, 2 on usage error.
- **`ensemble-td-append --list-keys --tracker <path>`**
  - Prints one line per open entry: `TD<N>\t<rule key or ->\t<title>`.
  - Callers read this before filing, so a correction that matches an open entry reuses that entry's key.
- **`ensemble-td-append --tracker <path> --title <t> --source <s> --severity P0-P3 --confidence 1-10 --location <l> --why <w> --fix <f> --enforce-at L1-L4 [--check "<path>: <rule>"] --rule-key <k>`**
  - Rule-key source, by caller:
    - `--enforce-audit` uses the inventory `key`.
    - Capture, review, resolve-pr and sweep pass a kebab-case slug naming the correction, such as `no-orm-return-from-routes`. They reuse the key from `--list-keys` when an open entry already describes the same correction.
  - Appends one entry under `## Open` in the tracker format, taking the next TD number after the highest existing one.
  - Writes `Enforce at:`, `Proposed check:` and `Rule key:` fields. The key is normalized: lowercased, whitespace-collapsed, 12-hex digest when longer than 64 characters.
  - Refuses L1 or L2 without a check whose path part and rule part are both non-empty.
  - Deduplicates: an open entry with the same rule key means no write.
  - Exit codes: 0 appended, printing the new TD-ID; 4 duplicate, printing the existing TD-ID; 2 usage or validation error; 1 tracker missing or has no `## Open` section.
- **`ensemble-review-history --since <iso-date> [--repo <owner/name>] [--limit <n>]`**
  - Uses `gh api graphql` over PRs merged since the date.
  - Prints JSON lines: `{"pr": 118, "path": "skills/x/SKILL.md", "author": "...", "body": "...", "resolved": true}`.
  - Bot authors are kept, and marked with `"bot": true`.
  - Exit codes: 0 on success, 3 when no PRs matched, 1 when `gh` fails. Stderr names the failure. It never prints an empty result as success.

## Implementation units

### U1. Shared enforcement-layer rubric and tracker fields

- **Goal:** One byte-identical definition of L1 to L5, the selection order and the two new TD fields, carried by the four skills that will route.
- **Requirements covered:** none (foundation §17.1)
- **Dependencies:** none
- **Files:**
  - `skills/en-learn/references/enforcement-layers.md` (new)
  - `skills/en-review/references/enforcement-layers.md` (new)
  - `skills/en-resolve-pr/references/enforcement-layers.md` (new)
  - `skills/en-sweep/references/enforcement-layers.md` (new)
  - `skills/en-review/references/tech-debt-tracker-format.md`
  - `skills/en-sweep/references/tech-debt-tracker-format.md`
  - `tests/parity/enforcement-layers-parity.test.sh` (new)
  - `docs/foundation.md` (§17.1 and a new D123 in §4)
- **Approach:**
  - **The rubric** holds:
    - the five layers, each with a one-line test ("could a type or module boundary make this impossible?");
    - the rule that the strongest expressible layer wins;
    - what "concrete check" means: a file path plus the rule, assertion or boundary it adds;
    - two worked examples. One is Emble-shaped: "never branch on `source_system`" goes to L2, as an AST guard test beside `backend/tests/test_architecture_invariants.py`. The other is Ensemble's own: a SKILL.md size budget goes to L2 via `tests/lint/skill-size.test.sh`.
  - **The tracker format** gains three optional fields:
    - `Enforce at:` takes `L1 structure | L2 static | L3 rules | L4 skill | L5 prose`.
    - `Proposed check:` takes `<path>: <rule or assertion>`, and is required when `Enforce at` is L1 or L2.
    - `Rule key:` is the stable identity used for deduplication.

    Both carriers of `tech-debt-tracker-format.md` get the same edit.
  - **The router proposes; it never applies.** Each routed correction has exactly one outcome:
    - L1 to L4 produce a TD entry describing the change: a check for L1 and L2, a map-file rule for L3, a skill change for L4.
    - L5 goes to a prose learning through `/en-learn`'s existing routing, or to nothing when the capture gate says so.

    No skill edits a map file, a lint config, a skill or a test as part of routing.
  - **The parity test** pins the four carriers by name and asserts byte identity. A missing carrier fails the test, modelled on `peer-contract-parity.test.sh`.
  - **Foundation:** §17.1's list points at the rubric instead of the nonexistent `golden-principles.md` path. D123 records the router decisions.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Patterns to follow:** `tests/parity/peer-contract-parity.test.sh`; memory rule "guards need negative controls".
- **Test scenarios:**
  - *Happy path:* four identical carriers, so the parity test passes.
  - *Error path:* one carrier edited by one byte, so the test fails and names the carrier.
  - *Error path:* one carrier deleted, so the test fails on carrier count rather than passing on the three that remain.
  - *Edge case:* the two `tech-debt-tracker-format.md` copies stay identical after the field edit, which the existing `reference-parity.test.sh` checks.
- **Verification:** `./tests/select-for.sh` on the changed paths passes. Both negative controls go red when forced. `bin/ensemble-lint --scope docs/foundation.md` is clean.

### U2. TD-entry mechanics: `td.enforce-layer` lint rule and `ensemble-td-append`

- **Goal:** One script writes routed TD entries and one lint rule checks them, so filing, deduplication and the concrete-check requirement are deterministic and tested rather than model-followed prose.
- **Requirements covered:** none
- **Dependencies:** U1
- **Interfaces:**
  - *Produces:* `ensemble-td-append`, with the flags and exit codes in Technical design. U3, U4, U5 and U6 call it.
- **Files:**
  - `bin/ensemble-lint`
  - `skills/en-setup/references/templates/ensemble-lint`
  - `skills/en-sweep/references/doc-lints.md`
  - `skills/en-learn/scripts/ensemble-td-append` (new)
  - `skills/en-review/scripts/ensemble-td-append` (new, byte-identical)
  - `skills/en-resolve-pr/scripts/ensemble-td-append` (new, byte-identical)
  - `skills/en-sweep/scripts/ensemble-td-append` (new, byte-identical)
  - `tests/lint/td-enforce-layer.test.sh` (new)
  - `tests/en-learn/td-append.test.sh` (new)
  - `tests/fixtures/td-enforce-layer/` (new)
- **Approach:**
  - **Lint.** For each `### TD<N>.` block under `## Open` in `docs/plans/tech-debt-tracker.md`, read `Enforce at:` and `Proposed check:`.
  - **Appender.** POSIX sh plus awk. Byte parity across its four carriers comes from the existing `script-parity.test.sh`. It validates with the same rule the lint applies, so nothing it writes can fail the lint.
  - Emit rule `td.enforce-layer` in three cases:
    - P1 when the layer is L1 or L2 and the check is missing or empty, has no `<path>:` prefix, or has nothing after the colon.
    - P2 when `Enforce at` holds an unknown value.
    - Nothing when the fields are absent. They stay optional, so the existing entries TD1 to TD23 remain valid.
  - Ignore `## Resolved`.
  - Both linter copies get the identical change. The existing byte-parity between them must hold.
  - Catalog the rule in `doc-lints.md`.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Patterns to follow:** the `cross-link.broken-td` block in `bin/ensemble-lint` (around line 514), and its tracker parsing.
- **Test scenarios:**
  - *Happy path:* `Enforce at: L2 static` with `Proposed check: backend/tests/test_architecture_invariants.py: forbid source_system == comparisons` produces no finding.
  - *Error path:* `Enforce at: L1 structure` with no `Proposed check:` line produces P1 `td.enforce-layer`, naming the TD-ID.
  - *Error path:* `Proposed check: add a lint` with no path prefix produces P1.
  - *Error path:* `Proposed check: tests/guard.sh:` with nothing after the colon produces P1.
  - *Edge case:* an entry with neither field produces no finding, and the repo's real tracker lints clean.
  - *Edge case:* an L2 entry under `## Resolved` with no check produces no finding.
  - *Error path:* `Enforce at: L9` produces P2.
  - *Appender, happy path:* a fixture tracker whose highest entry is TD23 gets TD24 appended under `## Open`. The call exits 0 and prints `TD24`, and the result lints clean.
  - *Appender, duplicate:* a second call with the same rule key exits 4, prints `TD24`, and leaves the file byte-unchanged.
  - *Appender, validation:* `--enforce-at L2` with `--check "tests/guard.sh:"` exits 2 and writes nothing.
  - *Appender, error path:* a tracker with no `## Open` section exits 1 and writes nothing.
  - *Appender, error path:* `--enforce-at L5` exits 2, because L5 is routed to a learning and never to the tracker.
  - *Appender, list keys:* `--list-keys` on a fixture with TD23 (no key) and TD24 (key `no-orm-return-from-routes`) prints both. TD23 shows `-` for its key.
  - *Appender, repeat filing:* capture files `no-orm-return-from-routes`. A later review call with the same slug exits 4 and prints the existing TD-ID.
- **Verification:** Both tests pass and end with `report`. Deleting the rule's emit line or the appender's duplicate check turns the matching cases red. `bin/ensemble-lint --scope docs/` is clean on the real repo. The linter and its template copy are byte-identical, and so are the four appender copies.

### U3. `/en-learn capture` routes before it writes

- **Goal:** Capture classifies every surviving candidate against the rubric. An enforceable correction becomes a TD entry with a proposed check instead of a prose learning.
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
    - *Already enforced at the strongest feasible layer* (a type, boundary, lint or test covers it): write nothing, as today.
    - *Covered only at a weaker layer, or not at all*: route to the rubric instead of discarding. An `AGENTS.md` rule for something a lint could check falls in this state; the prose rule alone does not count as enforcement.
  - **Artifact types.** Gains a fourth outcome before term, decision and solution: *enforcement*. When the rubric picks L1 to L4, file a TD entry through `ensemble-td-append` with `Source: en-learn capture`, and write no learning file. For L3 the proposed change is the rule text and the map file it belongs in; for L4 it is the skill and the step to change. Routing never edits either. Only L5 falls through to the existing term, decision and solution routing. The rule key is a kebab slug for the correction, reused from `--list-keys` when an open entry matches.
  - **Worked examples.** Each input correction is paired with its expected output:
    - "routes never call `useAuthFetch` directly", already in `AGENTS.md` and checked by nothing, becomes L2. The check proposed is a biome `noRestrictedImports` rule scoped to `frontend/src/routes/`.
    - A correction already covered by `tests/lint/skill-size.test.sh` produces no write.
    - "a sweep PR is doc-only" produces no write, because `ensemble-doc-only-check` enforces it.
    - "`/en-build` forgot to run the simplify pass" becomes L4. The TD entry names `skills/en-build/SKILL.md` and the step to change.
    - "the tracker's TD numbers are append-only because `/en-plan` cites them" becomes L5, written as a decision learning. No TD entry is filed.
  - **SKILL.md.** Adds one step between the capture gate (step 4) and routing (step 5) that cites the two references. It must stay within the 24,576-byte skill-size budget; headroom is about 4.4 KB today. Detail lives in the references.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Patterns to follow:** `tests/lint/en-learn-capture-gate.test.sh` locks the gate's shape, not its wording; extend it the same way.
- **Test scenarios:**
  - *Happy path:* `capture-gate.md` names both states, and states that a prose-only rule does not count as enforcement (anchored assertion).
  - *Happy path:* `artifact-types.md` lists enforcement ahead of term, decision and solution, states that L1 to L4 file through `ensemble-td-append` and write no learning file, and that only L5 reaches term, decision or solution routing, and carries the three worked examples with their expected outputs.
  - *Error path:* `artifact-types.md` contains no instruction to edit `AGENTS.md`, `CLAUDE.md` or `REVIEW.md` as part of routing (negative assertion).
  - *Edge case:* the SKILL.md step cites `enforcement-layers.md` exactly once, and `skill-size.test.sh` still passes.
  - *Error path:* the existing write-nothing default assertion in `en-learn-capture-gate.test.sh` still holds.
- **Verification:** The targeted tests pass, and `skill-size.test.sh` passes. A recorded dry run of `/en-learn capture` on each of the three worked examples produces the expected output: one L2 entry that `bin/ensemble-lint` accepts, and two no-writes. The transcript excerpt goes in the PR body. An automated check of the model's classification is TD7's eval harness.

### U4. `/en-review` and `/en-resolve-pr` classify the TD entries they file

- **Goal:** The two skills that already file TD entries attach a layer and, for L1 and L2, a concrete check.
- **Requirements covered:** none
- **Dependencies:** U1, U2
- **Files:**
  - `skills/en-review/references/review-confidence-gating.md`
  - `skills/en-resolve-pr/SKILL.md`
  - `skills/en-resolve-pr/references/resolve-pr-rubric.md`
  - `tests/lint/en-review-enforcement-layer.test.sh` (new)
  - `tests/lint/en-resolve-pr-seam.test.sh`
- **Approach:**
  - **`/en-review`.** Its SKILL.md is 293 bytes under budget, so the change goes only in `review-confidence-gating.md`, where sub-threshold findings are filed. Filing switches from hand-edited prose to `ensemble-td-append`, with the layer from the rubric and, for L1 and L2, a proposed check. `report-only` mode still files nothing.
  - **`/en-resolve-pr`.**
    - Step 13's tech-debt routing adds the same two fields.
    - A `fixed` verdict whose correction classifies L1 to L4 also files a TD entry for the proposed prevention. The fix removes this instance, and the prevention stops the next one. An L5 correction files nothing; the fix and the reply are the whole outcome.
    - The rule key follows the caller rule in Technical design: a kebab slug, reused from `--list-keys` when an open entry matches.
    - That entry gets `Source: en-resolve-pr` and a PR back-reference in `Location`.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* `review-confidence-gating.md` requires filing through `ensemble-td-append` with `--enforce-at`, and cites `enforcement-layers.md` (anchored on that file only).
  - *Happy path:* `en-resolve-pr` step 13 and the rubric name the fixed-plus-L1/L2 filing rule and the appender call (anchored per file).
  - *Edge case:* `en-review/SKILL.md` is byte-unchanged, and `skill-size.test.sh` passes.
  - *Error path:* `report-only` still states that nothing is filed.
  - *Worked examples,* carried in the two references as input and expected output, and asserted present:
    - A sub-threshold finding, "handler returns ORM row", files L2 with a check in `backend/tests/test_architecture_invariants.py`.
    - A `fixed` PR comment, "don't branch on `source_system`", files L2 with the PR number in `Location`.
    - A `fixed` comment, "use `migrate.py`, not bare alembic head", files L3 when it isn't already in `AGENTS.md`. The TD entry proposes the rule text and the map file.
    - A `fixed` comment on wording taste ("tighten this sentence") classifies L5 and files nothing.
    - A comment about something `tests/lint/skill-size.test.sh` already enforces files nothing.
    - `report-only` mode files nothing.
- **Verification:** The targeted tests pass, and `skill-size.test.sh` passes. A recorded dry run of the two worked examples that should file, driven through `ensemble-td-append`, produces entries that lint clean. The excerpt goes in the PR body.

### U5. `/en-learn --enforce-audit` and `ensemble-rule-inventory`

- **Goal:** Given a repo, list its imperative prose rules, classify each, and file TD entries for rules that belong at L1 or L2 and have no check yet.
- **Requirements covered:** none
- **Dependencies:** U1, U2, U3
- **Files:**
  - `skills/en-learn/scripts/ensemble-rule-inventory` (new)
  - `skills/en-learn/references/enforce-audit.md` (new)
  - `skills/en-learn/SKILL.md` (modes table, one-line mode section)
  - `tests/en-learn/rule-inventory.test.sh` (new)
  - `tests/fixtures/rule-inventory/` (new, including an Emble-shaped `AGENTS.md`)
  - `README.md` (skill catalog row)
- **Approach:**
  - **The script** follows the contract in Technical design. POSIX sh plus awk, no python dependency. It skips fenced code and sets `cites_check` by path pattern.
  - **The mode:**
    1. Runs the script.
    2. Discards lines that are not rules. For a rule with non-empty `cited_checks`, the model reads the cited file to confirm it enforces the rule; unconfirmed rules stay in.
    3. Classifies the rest with the rubric.
    4. Files one TD entry per L1 or L2 rule through `ensemble-td-append`. `Source` is `en-learn --enforce-audit`, `Location` is `<file>:<line>` of the prose rule, and `--rule-key` is the inventory `key`.
    5. Prints a table: rule, layer, proposed check, TD-ID or `exists TD<N>`.
  - Reruns converge through the appender's rule-key deduplication. The key excludes the line number, so a rule moved by an unrelated edit is not filed twice.
  - No learning files are written. The mode edits only the tracker.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Patterns to follow:** exit-code conventions of `skills/en-sweep/scripts/ensemble-sweep-activity-check`; memory rule "a gate over a git file listing passes silently when the listing fails".
- **Test scenarios:**
  - *Happy path:* the fixture, a copy of Emble's `AGENTS.md` at `64bdbd0f`, includes lines 38, 39, 52 and 63 among its results, with the rule text intact and `cited_checks: []`.
  - *Happy path:* list items beginning "Use", "Avoid", "Prefer" and "Only", with no modal word, are each reported with `kind: list`.
  - *Happy path:* the paragraph line "Run the full suite before committing" is reported with `kind: prose` and `modal: false`. A paragraph line containing "should" is reported with `modal: true`. A heading, a table row and a blank line are not reported.
  - *Happy path:* a line naming `backend/tests/test_architecture_invariants.py`, present in the fixture tree, lists it in `cited_checks`. A line naming a missing `tests/nope.py` lists nothing.
  - *Edge case:* the same rule text at line 52 in one fixture and line 60 in another gets the same `key`.
  - *Edge case:* "never" inside a fenced code block, a heading or frontmatter is not reported.
  - *Edge case:* "Nevertheless" and "alwaysOn" in paragraph lines are not matched (whole words only).
  - *Integration:* the inventory's JSON for two fixture rules is fed to `ensemble-td-append` twice. The first run files two entries; the second exits 4 for both and leaves the tracker byte-unchanged.
  - *Error path:* a root with none of the three files exits 3 with an empty stdout, and never exits 0 with nothing printed.
  - *Error path:* an unknown flag exits 2 with usage on stderr.
  - *Integration:* the SKILL.md modes table lists `--enforce-audit`, and `enforce-audit.md` names the appender call with `--rule-key` from the inventory `key` (anchored).
- **Verification:** The script tests pass and end with `report`. Each error case turns red when its guard is removed. `skill-size.test.sh` passes. The README catalog drift test passes. A recorded dry run of `/en-learn --enforce-audit` against the Emble fixture files entries for the `source_system` and `useAuthFetch` rules. A second run files none. The excerpt goes in the PR body.

### U6. `/en-sweep` recurrence scan and `ensemble-review-history`

- **Goal:** Corrections repeated across two or more merged PRs become one classified TD entry per recurring cluster.
- **Requirements covered:** none
- **Dependencies:** U1, U2
- **Files:**
  - `skills/en-sweep/scripts/ensemble-review-history` (new)
  - `skills/en-sweep/SKILL.md` (new step 8b)
  - `skills/en-sweep/references/recurrence-scan.md` (new)
  - `tests/en-sweep/review-history.test.sh` (new)
  - `tests/fixtures/review-history/` (new)
- **Approach:**
  - **The script** follows the contract in Technical design.
  - **The window is trailing, not since the last sweep.** Step 8b passes `--since` as today minus `sweep.recurrence_window_days`, default 60. Each run re-reads the whole window, so two matching PRs on either side of a sweep boundary still land in one scan. No state is carried between runs; deduplication makes the overlap harmless.
  - **Step 8b:**
    1. Runs the script over the window.
    2. Clusters review comments by the correction they make, not by wording.
    3. Keeps clusters that span two or more distinct PRs.
    4. Names each cluster with a short slug. The slug is the rule key.
    5. Files each cluster through `ensemble-td-append`, with the layer, `Source: en-sweep recurrence`, and the PR numbers in `Location`. Exit 4 means the cluster is already tracked.

    The model is asked to reuse an existing open entry's rule key when its cluster matches one. That keeps clustering stable across runs, rather than depending on the model producing the same slug twice.
  - The step is opt-in behind `sweep.recurrence_scan: true`, off by default, so existing sweep installs are unchanged.
  - Everything stays doc-only: the tracker is under `docs/`, so `ensemble-doc-only-check` holds.
  - Exit 3 (no PRs) is a clean skip. Exit 1 records `recurrence_scan: failed (<reason>)` in the sweep summary and continues the rest of the sweep.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Patterns to follow:** `gh` stubbing in `tests/en-sweep/runner.test.sh`; step 8a's `triage-findings` partition.
- **Test scenarios:**
  - *Happy path:* the stubbed `gh` returns two PRs with three threads, and the script prints three JSON lines with `pr`, `path` and `body`.
  - *Edge case:* no PRs since the date, so exit 3 with an empty stdout.
  - *Error path:* the `gh` stub exits 1, so the script exits 1 and stderr names `gh`. It never exits 0.
  - *Edge case:* a bot-authored comment carries `"bot": true`.
  - *Edge case, sweep boundary:* the stubbed `gh` holds PR 101 merged 40 days ago and PR 130 merged 3 days ago, with matching comments; the last sweep was 20 days ago. A 60-day window returns both PRs. The same call with `--since` set to the last sweep date returns only PR 130, which proves the window, not the sweep date, drives recall.
  - *Integration:* `en-sweep/SKILL.md` step 8b is gated on `sweep.recurrence_scan` and passes a trailing-window `--since`. `recurrence-scan.md` states the two-PR threshold and the rule-key reuse instruction (anchored per file).
  - *Integration:* `ensemble-doc-only-check` accepts a staged `docs/plans/tech-debt-tracker.md` change.
- **Verification:** The script tests pass with negative controls. `skill-size.test.sh` passes. The full suite passes once before commit.

## Decisions, assumptions & risks

- **Decision:** `/en-learn` owns routing, and one shared rubric is byte-identical across four carriers. A new `/en-enforce` skill would add a hand-off seam and another copy set for no gain.
- **Decision:** No schema change. Recurrence is matched by model clustering over review history plus open TD entries. A `layer` field in `peer-findings.schema.json` would touch the Codex structured-output contract and every carrier for a key the model would still assign.
- **Decision:** TD entries are the router's only output for L1 to L4; L5 stays a prose learning, since there is nothing stronger to propose. One script (`ensemble-td-append`) writes them. Filing, numbering, deduplication and the concrete-check rule are code under test; only the choice of layer is model judgment.
- **Decision:** Deduplication keys on a rule key, never on a line number. For audit mode the key is a digest of file plus normalized text; for recurrence clusters it is a slug the model reuses from the matching open entry.
- **Alternative:** Emitting draft plan units as a second output. Deferred: TD entries already feed `/en-plan` via `Resolves:`, and the gate (U2) needs one format to check.
- **Decision:** Recurrence scanning runs at sweep time and is opt-in. Live detection in `/en-resolve-pr` would add `gh` queries and latency to every PR cycle.
- **Alternative:** A model eval of classification accuracy. Rejected here as TD7's harness; the lint gate checks the output's shape, not the choice of layer.
- **Assumption:** The sweep machine's `gh` identity can read review threads on the swept repos. It already opens PRs there. A failure is reported as `recurrence_scan: failed`, not silently skipped.
- **Assumption:** `REVIEW.md` exists in target repos that ran `/en-setup` (Emble has one) and is absent in Ensemble. The inventory skips missing files.
- **Risk:** Classification drifts toward L5 because prose is easiest to write. **Mitigation:** the rubric's order makes L5 the last answer, and `ensemble-metrics` can later report the layer distribution from TD `Source` markers.
- **Risk:** Tracker growth from audit mode on a rule-heavy AGENTS.md. **Mitigation:** only L1 and L2 rules file entries, and reruns converge on `Location`.
- **Risk:** `en-learn/SKILL.md` budget. U3 and U5 both add to it, with about 4.4 KB of headroom. **Mitigation:** each adds one step or row and cites a reference; `skill-size.test.sh` runs in both units.

## Tracked debt

None resolved. TD7 (classification eval) is related and stays open.

## Iteration log

> - 2026-09-26 (initial): plan v0 from `docs/designs/2026-09-26-agent-trust-strategy-design.md` item A5, after two planning rounds (architecture: shared rubric owned by en-learn; recurrence: sweep-time scan with no schema change; gate: TD-entry doc lint; seams: scripts, lint, anchored prose; rule scan: script lists, model classifies; pilot: audit mode plus a separate Emble plan).
> - 2026-09-26 (peer iteration 1, codex, verdict revise): applied all 8 findings. Added `ensemble-td-append` to U2 so filing and dedupe are deterministic; rule keys replace line matching; L3 now proposes only; capture gate counts a prose-only rule as unenforced; inventory emits every list item plus modal lines; U6 scans a trailing window; U3 to U5 gained worked examples and recorded dry runs.
> - 2026-09-26 (peer iteration 2, codex, verdict revise, cap reached): applied all 4 findings. Inventory emits every prose line with a `modal` hint; L1 to L4 file TD entries and only L5 becomes a learning; fixed comments route at every layer; `--list-keys` and a slug rule give capture and review a stable rule key.
