---
type: plan
plan_type: improvement
plan_id: EN14
title: Three artifact types for captured knowledge, replacing the flat learnings taxonomy
status: open
location: active
created: 2026-08-28
shipped:
deepened:
covers_requirements: []
requirements_pending: false
related_design:
depth: deep
data_scale: small
peer_review_verdict: revise
peer_review_overridden: cap-hit-accepted-by-user
peer_review_iterations: 2
peer_review_last_run: 2026-08-28
peer_review_plan_hash: f9128989946297f83cafb6285eea9532fedc0858704773a2fdcc26391eef7dc3
peer_review_resolutions:
  - finding_id: "1-1"
    iteration: 1
    severity: P1
    title: Existing learning stores have no safe upgrade path
    status: applied
    rationale: Correct and the most valuable finding. The zero-entry assumption held only for this repo; these skills install into others that may hold hundreds of entries. Added U13 (migration, test-first, 11 scenarios) as a dependency of U10, so validation of the retired paths does not stop until migration has run.
    location: U13
  - finding_id: "1-2"
    iteration: 1
    severity: P1
    title: Solution frontmatter has conflicting field counts
    status: applied
    rationale: Real internal inconsistency - the artifact table said seven while U8 removed category to reach six. Table corrected to six and the fields enumerated in the design so U10's fixtures have one authoritative contract.
    location: design table, U8
  - finding_id: "1-3"
    iteration: 1
    severity: P1
    title: Grounding tests omit links and SHAs
    status: applied
    rationale: Two of the three promised capabilities were untested, so an absent implementation would have passed. Added eight scenarios covering valid/dead/anchor/external links and valid/dead/ambiguous SHAs, plus relative-link resolution semantics.
    location: U4
  - finding_id: "1-4"
    iteration: 1
    severity: P1
    title: Router tests do not exercise routing decisions
    status: applied
    rationale: The sharpest finding. The scenarios asserted that routing prose existed, not that routing worked - the same decorative-guard class the capture gate's own generalization step was written about. Replaced with fixture candidates carrying expected artifact type and path, including both ambiguity directions and a gate-rejected candidate.
    location: U5
  - finding_id: "1-5"
    iteration: 1
    severity: P1
    title: Flat learning matcher may classify the index as a solution
    status: applied
    rationale: Correct - index.md, log.md, and README.md sit at that level and would have been required to carry solution frontmatter. Matcher now excludes them explicitly, with fixtures proving they keep their own rules.
    location: U10
  - finding_id: "1-6"
    iteration: 1
    severity: P2
    title: Grounding findings and validator failure share unclear semantics
    status: applied
    rationale: Conflated found-problems with could-not-run. Split into three exit codes (0 clean, 1 findings, 2 operational failure) stated in the design, with U7 asserting that an exit-2 run cannot be reported as grounded.
    location: U4, U7
  - finding_id: "2-1"
    iteration: 2
    severity: P0
    title: Existing stores can still lose or hide entries
    status: applied
    rationale: Both sub-claims correct. Flattening three directories collides on identical basenames, which is silent data loss; U13 now runs a preflight collision inventory, never overwrites, and is restartable. The U10/U13 contradiction was real - U10 said legacy paths stop matching while U13 promised they stay validated until migration; resolved in U13's favour, since the alternative makes un-migrated entries invisible. Declined only the risk reclassification - see 2-1b.
    location: U13, U10
  - finding_id: "2-1b"
    iteration: 2
    severity: P0
    title: Reclassify U13 as high risk
    status: disagreed
    rationale: Building a migration procedure changes no user data; the risky act happens later, in a user's repo, at a time this plan does not control. Ensemble's risk field drives build-time gates, so rating U13 high would gate the wrong moment and cascade high onto U10, U11, and U12, none of which touch user data either. The runtime hazard is instead addressed directly - the procedure refuses to start on a dirty working tree, so rollback is always git checkout, and collisions are resolved in preflight before anything moves.
    location: U13
  - finding_id: "2-2"
    iteration: 2
    severity: P1
    title: Grounding semantics still misvalidate links and SHAs
    status: applied
    rationale: Correct on both counts and the link half was my error - markdown resolves relative links from the containing document, and I had specified repo-root resolution, which would accept broken links and reject valid ones. Added nested-document fixtures. On SHAs the peer caught a contradiction I could not have satisfied - deadbee and ffffff0 are syntactically identical, so no rule distinguishes them. Made the treatment uniform - unresolvable hex tokens are advisory findings the agent adjudicates, same as paths.
    location: U4
  - finding_id: "2-3"
    iteration: 2
    severity: P1
    title: Router fixtures still do not execute routing
    status: applied
    rationale: Correct, and it names a limit of Ensemble's whole test approach rather than a defect in this unit. Routing is a model judgment; no shell assertion can prove a candidate yields the right type. Rather than invent a deterministic classifier - which would be the wrong design, since the point is judgment - U5 now states plainly what its tests do and do not prove, keeps the fixtures for their real value as few-shot worked examples, and defers behavioural coverage to TD7 without claiming it.
    location: U5
  - finding_id: "2-4"
    iteration: 2
    severity: P1
    title: Legacy decisions are migrated as solutions
    status: applied
    rationale: A genuine miss. The migration flattened decisions/ entries into solutions, which preserves the files while destroying their artifact semantics - the exact distinction this plan exists to draw. Legacy decisions now convert to numbered ADRs, and a conversion that cannot be made confidently is surfaced rather than guessed.
    location: U13
  - finding_id: "2-5"
    iteration: 2
    severity: P1
    title: Glossary behavior lacks executable scenarios
    status: applied
    rationale: Same class as 2-3 and equally correct. U6 now scopes its claims to specification and parity, and TD7 carries the behavioural gap.
    location: U6
  - finding_id: "2-6"
    iteration: 2
    severity: P1
    title: TD5 can close before core features complete
    status: applied
    rationale: Correct and trivially checkable - U12 depended only on U11, whose chain runs U1 to U9 to U13 to U10 to U11 and never reaches U4 through U7. TD5 could have been marked resolved with grounding and routing unbuilt. U12 now depends on U6, U7, and U11.
    location: U12
resolves: [TD5]
---

# EN14 — Three artifact types for captured knowledge

## Problem

`en-learn` writes one kind of thing: a learning entry, filed under
`docs/learnings/{bugs,patterns,decisions,sources}/`. Two problems compound.

**The taxonomy does not survive contact with the capture gate.** The gate rejects
what a reader can recover from the code, which is most of what a fixed bug
teaches, so `bugs/` starves. What survives is a decision or a pattern, and that
boundary is not one a writer can apply consistently — drafting a real entry, the
same content was defensible under either. This is TD5.

**The store has no place for the two highest-value things.** Domain vocabulary
(which of three synonyms is canonical, what was rejected, which ambiguity got
settled) is not recoverable from code and is exactly what helps when reading an
unfamiliar codebase — and nothing in Ensemble captures it. Decisions are captured
as prose with no statement of the rules they create, so a future agent reads what
was decided but not what it must now uphold.

Nothing checks that a written claim is *true*. The gate decides whether to write;
after that, a doc becomes trusted knowledge future agents act on without
re-verifying.

## What changes

Three artifact types replace one, chosen because they differ in **shape,
lifecycle, and write path** — the distinction `bugs` vs `patterns` never had:

| Type | Path | Shape | Lifecycle |
|---|---|---|---|
| Glossary | `docs/CONTEXT.md` | Terms, canonical + retired synonyms | Amended in place; entries accrete |
| Decision | `docs/decisions/NNNN-<slug>.md` | Title-as-claim, no frontmatter, invariants | Append-only; dated in-place updates |
| Solution | `docs/learnings/<slug>-<date>.md` | 6-field frontmatter, one paragraph | Goes stale against code; refreshed |
| Source | `docs/learnings/sources/<slug>-<date>.md` | Adds `source_type`/`source_uri`/`fetched` | Ingested, not authored |

The solution frontmatter is exactly six required fields: `title`, `applies_when`,
`date`, `tags`, `related`, `status`. `category` leaves the schema in U8 because
the directory it selected no longer exists. A `sources/` entry adds
`source_type`, `source_uri`, and `fetched`.

`bugs/`, `patterns/`, and `decisions/` as directories disappear. `sources/`
survives because it is genuinely different in kind: external material on a
separate write path.

Prior art, reviewed 2026-08-28:
`/Users/mano.kulasingam/CodeRepo/agent-skills/skills` (`CONTEXT.md` glossary,
`.agents/adr/NNNN-*.md`) and
`/Users/mano.kulasingam/CodeRepo/agent-skills/compound-engineering-plugin/skills/ce-compound`
(`references/concepts-vocabulary.md`, `references/grounding-validation.md`,
`scripts/validate-doc-claims.py`).

## Technical design

Three components, one shared router.

**The router** (U5) sits inside `en-learn capture`, after the capture gate. The
gate answers *whether* to write; the router answers *which artifact*. It is a
classification with a defined tie-break, not a free judgment: a candidate that
defines what a word means in this codebase is a term; one that records a choice
between alternatives and the rules that follow is a decision; one that records a
solved problem is a solution. A candidate matching two types is written as the
**more durable** one — term over decision, decision over solution — because the
durable form outlives the occasion and can cite the other.

**Glossary population has two paths** and they cover different gaps. *Accretion*
(U6) fires during capture when a candidate surfaces a term whose meaning was not
obvious; it reliably catches peripheral terms because friction is what surfaces
them. *Seeding* (U6) fires during `en-setup` and defines the core domain nouns of
the area in scope; it catches the stable-central terms accretion never reaches,
because the nouns a system is built around rarely break and so rarely appear in a
learning. Without seeding the file fills with peripheral mechanics and never names
what the project is about.

**Grounding** (U4, U7) runs after the doc is written and before it is trusted. A
mechanical pass (`bin/ensemble-validate-claims`) checks that every path, link, and
SHA the doc cites resolves in the tree, and flags unrendered `{{template}}`
leftovers. Neither pass is a hard gate: a solution doc legitimately cites a
deleted path or a pre-fix state, so every flag is adjudicated, not auto-applied.
Claim categories verify against different trees — code-behavior claims against the
working tree, merge-state claims ("landed in #44") against remote, since the
checkout may predate a merge.

`ensemble-validate-claims` distinguishes three outcomes, because "found
problems" and "could not run" are different facts: **0** clean, **1** findings to
adjudicate, **2** operational failure (bad arguments, unreadable file). Exit 2 is
the only one that means the artifact went unchecked, and it forces the run to
report degraded verification rather than success.

**Data flow:** capture gate → router → artifact writer → grounding → index/log →
cross-ref maintenance.

## Units

U-IDs are assignment-ordered and never renumbered. U13 was added after the first
peer review and is placed here in **build** order, immediately before the unit
that depends on it.

### U1. Define the artifact types

- **Goal:** One reference that says what the three types are and how a candidate is routed to one.
- **Requirements covered:** none (infrastructure).
- **Dependencies:** none.
- **Files:** `skills/en-learn/references/artifact-types.md` (new), `skills/en-learn/SKILL.md` (requires:), `tests/lint/en-learn-artifact-types.test.sh` (new).
- **Approach:** Write the routing rule with the more-durable tie-break stated explicitly, and a worked example per type drawn from this repo. Declare it in `requires:`.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - Happy path: reference exists, is declared in `en-learn`'s `requires:` block, and `skill-payload.test.sh` still passes.
  - Content: the three type names, their paths, and the tie-break rule are each present.
  - Edge case: the tie-break is stated as an ordering (term > decision > solution), not as prose that a reader could invert.
  - Negative control: delete the tie-break line, confirm the test goes red, restore.
- **Verification:** `tests/lint/en-learn-artifact-types.test.sh` and `tests/lint/skill-payload.test.sh` pass.

### U2. Glossary rules and the seed file

- **Goal:** `docs/CONTEXT.md` has a specification and an empty-state template.
- **Requirements covered:** none.
- **Dependencies:** U1.
- **Files:** `skills/en-learn/references/glossary-rules.md` (new), `skills/en-learn/references/templates/context-template.md` (new), `skills/en-learn/SKILL.md`, `tests/lint/en-learn-glossary.test.sh` (new).
- **Approach:** Port the rules that make the artifact work: be opinionated (one canonical term, retired synonyms as an `_Avoid:_` line), the file stands on its own (no file paths, class names, dates, owners, version-specific claims, or current-config numbers — state the behavior, not the number), what earns a slot (a new engineer would need it defined; general programming vocabulary does not), optional `## Relationships`, and a `## Flagged ambiguities` tail as the audit trail for settled distinctions.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - Happy path: both files exist and are declared; the template renders a valid empty `CONTEXT.md` with the ambiguities tail present.
  - Content: each of the five exclusions is stated; the `_Avoid:_` alias convention is shown in the illustrative entry.
  - Edge case: the template contains no `{{placeholder}}` that survives rendering.
  - Error path: a rules doc that omits the "stands on its own" exclusions fails the test.
  - Negative control: remove the exclusion list, confirm red, restore.
- **Verification:** `tests/lint/en-learn-glossary.test.sh` passes.

### U3. ADR format and template

- **Goal:** Decisions are written as numbered ADRs with no frontmatter, a title that states the claim, and the invariants they create.
- **Requirements covered:** none.
- **Dependencies:** U1.
- **Files:** `skills/en-learn/references/adr-format.md` (new), `skills/en-learn/references/templates/adr-template.md` (new), `skills/en-learn/SKILL.md`, `tests/lint/en-learn-adr.test.sh` (new).
- **Approach:** `docs/decisions/NNNN-<slug>.md`, zero-padded to 4, never renumbered. Title is an H1 stating the decision as a claim ("Ship X; defer Y"), not a topic. Required sections: the constraint or context, the decision, and `## Invariants this creates` — the rules that now hold because of this decision, which is what a future agent can actually check against. Rejected alternatives are recorded with the reason and any evidence of testing. Amendments append `## Update, YYYY-MM-DD` in place rather than superseding the file.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - Happy path: format doc and template exist, declared, and the template has no frontmatter block.
  - Content: `## Invariants this creates` and the `## Update, YYYY-MM-DD` amendment convention are both specified.
  - Edge case: numbering rule states zero-padding and no-renumber, matching `references/stable-ids.md`.
  - Error path: a template carrying YAML frontmatter fails the test, since zero-frontmatter is the point.
  - Negative control: add a frontmatter block to the template, confirm red, restore.
- **Verification:** `tests/lint/en-learn-adr.test.sh` passes.

### U4. Claim grounding script

- **Goal:** A doc's cited paths, links, and SHAs are checked against the tree before the doc is trusted.
- **Requirements covered:** none.
- **Dependencies:** U1.
- **Files:** `skills/en-learn/scripts/ensemble-validate-claims` (new), `skills/en-learn/references/grounding-validation.md` (new), `skills/en-learn/SKILL.md`, `tests/lint/grounding-validation.test.sh` (new).
- **Approach:** The script extracts path-shaped backtick tokens, markdown link targets, and 7-40 char hex SHAs from the body (code fences masked so examples are not treated as claims), and reports each that does not resolve. Output is advisory findings on stdout, exit 0 when clean and 1 when flags exist — never a hard gate, because a solution doc legitimately cites a deleted path. The reference tells the agent how to adjudicate: code-behavior claims verify against the working tree, merge-state claims against remote via `gh pr view` with local reachability as fallback, and an unverifiable remote claim keeps the claim, adds an as-of qualifier, and records degraded verification in the report.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - Happy path: a doc citing only existing paths exits 0 with no findings.
  - Edge case: a path inside a fenced code block is NOT flagged (fence masking works).
  - Edge case: an inline `` `docs/nonexistent.md` `` IS flagged.
  - Edge case: a bare word in backticks that is not path-shaped (`` `true` ``, `` `P0` ``) is not flagged.
  - Link, valid: a relative link resolves **from the containing document's directory**, per markdown semantics — `[x](../foundation.md)` inside `docs/learnings/a.md` resolves to `docs/foundation.md`.
  - Link, nested: the same target written from two documents at different depths both resolve, which a repo-root-relative implementation would get wrong.
  - Link, invalid: `[x](docs/gone.md)` is flagged as a dead link, reported under a distinct claim category from paths.
  - Link, anchor: `[x](docs/foundation.md#section-11)` checks the file only; a missing anchor is not a finding.
  - Link, external: `https://example.com` is never fetched and never flagged; the network is not a correctness dependency.
  - SHA, valid: a full or abbreviated SHA that `git cat-file -e` resolves is not flagged.
  - SHA, unresolvable: a hex-shaped token git cannot resolve is reported as an **advisory** finding, uniformly. There is no syntactic way to tell a dead SHA from a colour literal — both are seven hex characters — so the checker does not pretend to: it reports what it could not resolve and the agent adjudicates, exactly as it does for paths.
  - Error path: an unrendered `{{slug}}` is flagged as a template leftover.
  - Error path: the script is invoked on a missing file and exits **2** with a usage message, not a traceback.
  - Integration: exit is **0** clean, **1** findings present, **2** operational failure — three distinct codes, asserted separately.
  - Negative control: point the script at a doc with a known-dead path, a dead link, and a dead SHA; confirm three findings; fix each in turn and confirm each stops flagging independently.
- **Verification:** `tests/lint/grounding-validation.test.sh` passes; script runs clean against this plan file.

### U5. Route capture to an artifact type

- **Goal:** `en-learn capture` picks an artifact type after the gate, instead of picking a category.
- **Requirements covered:** none.
- **Dependencies:** U1, U2, U3.
- **Files:** `skills/en-learn/SKILL.md`, `tests/lint/en-learn-capture-gate.test.sh`.
- **Approach:** Replace step 5 ("Identify category") with the router from U1. Step 7's compose step branches on type. The gate (`capture-gate.md`) and its generalization step are unchanged and run first — the router only sees candidates that already passed.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  **What these tests can and cannot prove.** Routing is a judgment executed by a model, not a deterministic function, so a shell test can verify that the *specification* is present and self-consistent — it cannot verify that a model given a candidate emits the right type. Claiming otherwise would be the decorative-guard failure this plan's own gate warns about. The fixtures below therefore serve two real purposes: they are the worked examples embedded in `artifact-types.md`, where they do measurable work as few-shot guidance, and they are the corpus a behavioural eval suite would run. Executable behavioural coverage is tracked as TD7 and is **not** claimed by this unit.
  - Routes to glossary: "the word *carrier* means a skill that holds a byte-identical copy of a shared reference" → `docs/CONTEXT.md`, appended as a term.
  - Routes to ADR: "we chose explicit `requires:` declarations over a reachability walk; walkers produced five classes of false edge" → `docs/decisions/NNNN-*.md`.
  - Routes to solution: "peer review returned a well-formed failure because `BASH_SOURCE` is unset under zsh" → `docs/learnings/<slug>-<date>.md`.
  - Ambiguity, term vs decision: a candidate that both names a term and records a choice resolves to the term, per U1's ordering.
  - Ambiguity, decision vs solution: resolves to the decision.
  - Gate interaction: a candidate the capture gate rejects never reaches the router, and the run reports which gate condition failed.
  - Integration: the gate still runs before the router; the capture-gate test's ordering assertions still pass.
  - Error path: SKILL.md still under the Codex 8000-byte injection limit after the edit, or TD2 is explicitly cited if not.
  - Negative control: invert the tie-break ordering in `artifact-types.md`; confirm the ordering assertion goes red. Delete a worked example; confirm the fixture-presence assertion goes red. Restore.
- **Verification:** `tests/lint/en-learn-capture-gate.test.sh` and `tests/lint/en-learn-artifact-types.test.sh` pass.

### U6. Glossary accretion and seeding

- **Goal:** Terms enter `docs/CONTEXT.md` during capture (accretion) and during setup (seeding).
- **Requirements covered:** none.
- **Dependencies:** U2, U5.
- **Files:** `skills/en-learn/SKILL.md`, `skills/en-setup/SKILL.md`, `skills/en-setup/references/glossary-rules.md` (new copy), `skills/en-setup/SKILL.md` (requires:), `tests/lint/en-learn-glossary.test.sh`, `tests/parity/glossary-rules-parity.test.sh` (new).
- **Approach:** Accretion is a capture side effect: a term surfaced by the work gets defined, and the run records vocabulary capture even when nothing qualified, so silence is a reported outcome rather than an omission. Seeding is an `en-setup` step bounded by the area's declared domain model (schema, core types, top-level domain docs) and by the qualifying bar — never by a target count. `glossary-rules.md` is carried by both skills and must stay byte-identical; the parity guard derives carriers from behaviour, not from the file's presence, so deleting a copy cannot make it vacuous.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  **Scope.** As with U5, writing a glossary entry is model behaviour; these tests verify the specification and the parity of the carried copies, not that a model writes a correct entry. Behavioural coverage is TD7.
  - Happy path: both accretion and seeding are specified, each naming its trigger.
  - Content: seeding states its bound is the declared domain model and the qualifying bar, explicitly not a count.
  - Edge case: a capture that surfaces no qualifying term still reports vocabulary capture as attempted-and-empty.
  - Integration: both carriers of `glossary-rules.md` are byte-identical.
  - Negative control: drift one copy by a byte, confirm the parity guard goes red; delete a copy entirely and confirm the carrier-count assertion goes red; restore.
- **Verification:** `tests/lint/en-learn-glossary.test.sh` and `tests/parity/glossary-rules-parity.test.sh` pass.

### U7. Wire grounding into capture

- **Goal:** Every written artifact is claim-checked before the run reports success.
- **Requirements covered:** none.
- **Dependencies:** U4, U5.
- **Files:** `skills/en-learn/SKILL.md`, `tests/lint/grounding-validation.test.sh`.
- **Approach:** A grounding step runs after the artifact is written and before index/log updates. Findings are adjudicated and the adjudication is reported; a doc is never silently rewritten by the script.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - Happy path: the step is named in SKILL.md, positioned after write and before index update.
  - Integration: the script path in SKILL.md matches the file U4 created and is declared in `requires:`.
  - Error path: exit 1 (findings) routes to adjudication; exit 2 (operational failure) records degraded verification and the run may NOT report the artifact as grounded.
  - Error path: a run whose grounding exited 2 cannot end on a success report — asserted, since this is the case that would otherwise look identical to clean.
  - Negative control: rename the script without updating SKILL.md, confirm `skill-payload.test.sh` goes red, restore.
- **Verification:** `tests/lint/grounding-validation.test.sh` and `tests/lint/skill-payload.test.sh` pass.

### U8. Retire the taxonomy in en-learn's own references

- **Goal:** `en-learn`'s references describe the new layout.
- **Requirements covered:** none.
- **Dependencies:** U1.
- **Files:** `skills/en-learn/references/{learn-index-format,learn-lint,learn-cross-ref-maintenance,learning-frontmatter-schema,learn-ingest,learn-bootstrap-patterns,pack-reference-template}.md`, `skills/en-learn/agents/learnings-research.md`, `skills/en-learn/references/templates/learning-template.md`.
- **Approach:** Index groups by artifact type rather than by category. `related:` paths lose the category segment. `category` leaves the frontmatter schema, taking the required-field count from 7 to 6. `learnings-research` reads the index first and now knows three artifact types.
- **Risk:** medium
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** characterization-first
- **Test scenarios:**
  - Happy path: no file under `skills/en-learn/` references `learnings/bugs`, `learnings/patterns`, or `learnings/decisions`.
  - Content: the index format's headings match the three artifact types plus sources.
  - Edge case: `learning-frontmatter-schema.md` no longer lists `category`, and `applies_when` remains second.
  - Integration: `tests/golden/frontmatter/learning/valid.md` still lints clean under the 6-field requirement.
  - Negative control: reintroduce a `learnings/bugs/` path in one reference, confirm the sweep assertion goes red, restore.
- **Verification:** `tests/lint/en-learn-capture-gate.test.sh` and the frontmatter goldens pass.

### U9. Retire the taxonomy in the other carrier skills

- **Goal:** The copies carried by `en-review`, `en-sweep`, `en-setup`, `en-plan`, and `en-foundation` match `en-learn`'s.
- **Requirements covered:** none.
- **Dependencies:** U8.
- **Files:** `skills/{en-review,en-sweep}/references/learn-lint.md`, `skills/en-review/references/learning-frontmatter-schema.md`, `skills/en-setup/references/learn-index-format.md`, `skills/{en-foundation,en-plan,en-review}/agents/learnings-research.md`, `skills/{en-cross-review,en-build,en-foundation,en-learn,en-review}/references/templates/plan-template.md`, `skills/*/references/templates/architecture-template.md`, `tests/parity/learn-reference-parity.test.sh` (new).
- **Approach:** Propagate U8's edits byte-for-byte to every carrier, then add one parity guard covering all four duplicated learn references at once. Carriership is derived from behaviour — a skill that declares the file in `requires:` — so deleting both file and declaration is still caught.
- **Risk:** medium
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** characterization-first
- **Test scenarios:**
  - Happy path: every carried copy of each of the four references is byte-identical to `en-learn`'s.
  - Edge case: carrier counts match the `requires:` declarations (2 index-format, 3 learn-lint, 2 frontmatter-schema, 4 learnings-research).
  - Error path: no file anywhere under `skills/` still references a retired category directory.
  - Negative control: drift one copy, confirm red; delete a copy and its declaration together, confirm the count assertion goes red; restore.
- **Verification:** `tests/parity/learn-reference-parity.test.sh` and `tests/lint/skill-payload.test.sh` pass.

### U13. Migrate an existing learning store

- **Goal:** A repo that already has entries under the retired directories reaches the new layout without losing any.
- **Requirements covered:** none.
- **Dependencies:** U1, U9.
- **Files:** `skills/en-learn/references/layout-migration.md` (new), `skills/en-learn/SKILL.md`, `tests/lint/layout-migration.test.sh` (new), `tests/fixtures/legacy-store/` (new).
- **Approach:** This repo has zero entries, but these skills install into repos that may have hundreds. Write a migration procedure `en-learn` runs when it detects a retired directory. **Preflight first:** inventory every entry and compute its target path; `bugs/x-2026-01-01.md` and `patterns/x-2026-01-01.md` both target `learnings/x-2026-01-01.md`, so basename collisions are found and resolved *before* anything moves, and an overwrite is never permitted — a colliding entry is renamed with a disambiguating suffix and the choice is reported. **Legacy `decisions/` entries become ADRs**, not flat solutions: the artifact types differ, so a decision that keeps its semantics needs a numbered `docs/decisions/NNNN-*.md` with a claim title and an invariants section; a conversion that cannot be done confidently is surfaced rather than guessed. `bugs/` and `patterns/` entries become solutions under the flat path with `category` stripped. Every `related:` path that carried a category segment is rewritten. `sources/` is untouched. The move is restartable: each entry is moved and recorded before the next begins, so an interrupt leaves every entry readable at exactly one path. The procedure refuses to start on a dirty working tree, which makes `git checkout` a complete rollback. Entries whose target type is ambiguous are **never** auto-classified — the procedure surfaces them and asks, because a wrong silent classification is the failure mode that loses knowledge. The migration is interactive by default and refuses to run non-interactively without an explicit flag. Detection persists: until migration completes, the retired paths keep their old validation so entries do not become invisible to lint and research in the window between upgrade and migration.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Category note:** `feature`, not `migration`. `category: migration` classifies a unit as P3, and U10 (P2) depends on this unit, which violates the dependency-vs-phase invariant. The classification is also wrong on its own terms: this unit *builds* a migration procedure and migrates nothing at build time. Same reasoning as the recorded disagreement on finding 2-1b.
- **Test scenarios:**
  Building the procedure changes no user data; the fixtures stand in for a populated store.
  - Populated store: a fixture with entries in all three retired directories migrates every one, and the post-migration count equals the pre-migration count.
  - Collision: `bugs/x-2026-01-01.md` and `patterns/x-2026-01-01.md` both present — preflight reports the collision, neither file is overwritten, and both survive at distinct paths.
  - Decisions become ADRs: a legacy `decisions/` entry lands in `docs/decisions/` with a number, a claim title, and an invariants section — not in flat `learnings/`.
  - Unconvertible decision: an entry that cannot be confidently rendered as an ADR is surfaced for classification and left in place.
  - Dirty tree: the procedure refuses to start when the working tree is dirty, so rollback is always `git checkout`.
  - Cross-refs: a `related:` path of `docs/learnings/patterns/x-2026-01-01.md` is rewritten to the flat path, and `learn-lint`'s `broken-links` reports zero afterwards.
  - Frontmatter: `category` is stripped and the remaining six fields survive unmodified.
  - Sources untouched: entries under `sources/` keep their path and their three extra fields.
  - Mixed layout: a store with both retired directories and flat entries migrates only the retired ones and does not touch the flat ones.
  - Ambiguous entry: an entry whose type cannot be determined is surfaced for classification, never auto-assigned.
  - Idempotence: running the migration twice produces the same tree and the second run reports nothing to do.
  - Interrupted run: a migration stopped partway leaves every entry readable at either its old or new path, never lost, and the next run completes it.
  - Non-interactive refusal: without the explicit flag, a non-interactive invocation refuses rather than guessing at ambiguous entries.
  - Pre-migration validation: with a retired directory still present, entries under it are still validated — asserted, since silent invisibility is the failure this unit exists to prevent.
  - Negative control: delete the `related:` rewrite step and confirm the cross-ref scenario goes red; delete the ambiguity prompt and confirm the ambiguous-entry scenario goes red. Restore both.
- **Verification:** `tests/lint/layout-migration.test.sh` passes; a fixture store round-trips with zero entry loss and zero broken links.

### U10. Update the validator

- **Goal:** `ensemble-lint` validates the new layout and stops validating the old one.
- **Requirements covered:** none.
- **Dependencies:** U1, U9, U13.
- **Files:** `skills/en-setup/references/templates/ensemble-lint`, `tests/golden/frontmatter/learning/*`, `tests/golden/frontmatter/frontmatter.test.sh`, `tests/lint/lint-rules.test.sh`.
- **Approach:** Drop the `bugs|patterns|decisions|sources` enum and the `category` required field. Match solutions at `docs/learnings/*.md` **excluding the control files** `index.md`, `log.md`, and `README.md`, which live at that level and are not solutions; they keep their own rules. Match ingested sources at `docs/learnings/sources/*.md`. Add a rule that an ADR under `docs/decisions/` carries no frontmatter and has an `## Invariants this creates` section, and that `docs/CONTEXT.md` has the ambiguities tail.
- **Risk:** medium
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - Happy path: a 6-field learning at the flat path lints clean.
  - Required fields: each of the six is individually removed and each removal emits `frontmatter.required-field-missing`; all six present lints clean.
  - Control files: `docs/learnings/index.md` and `log.md` are NOT subjected to solution frontmatter checks, and are still validated by their own rules.
  - Legacy coexistence: while a retired directory still exists, entries under it are **still validated by the legacy rules** — the switch-off is conditional on that repo's migration having completed, not on this plan having shipped. A rule that dropped legacy paths unconditionally would make un-migrated entries invisible, which is the failure U13 exists to prevent.
  - Error path: an ADR carrying frontmatter emits a finding; an ADR missing `## Invariants this creates` emits a finding.
  - Error path: a learning missing `applies_when` still emits `frontmatter.required-field-missing`.
  - Integration: full golden suite passes with new fixtures for ADR-valid, ADR-with-frontmatter, and CONTEXT-valid.
  - Negative control: remove the ADR frontmatter rule, confirm the ADR fixture goes red, restore.
- **Verification:** `tests/golden/frontmatter/frontmatter.test.sh` and `tests/lint/lint-rules.test.sh` pass.

### U11. Scaffold the new layout in en-setup

- **Goal:** A fresh `/en-setup` creates the new tree, not the old four directories.
- **Requirements covered:** none.
- **Dependencies:** U1, U10.
- **Files:** `skills/en-setup/SKILL.md`, `skills/en-setup/references/learn-bootstrap-patterns.md`, `skills/en-setup/references/templates/context-template.md` (new copy), `tests/install/*`.
- **Approach:** Create `docs/learnings/sources/`, `docs/decisions/`, and seed `docs/CONTEXT.md` from the template. Drop `{bugs,patterns,decisions}`. Update the State-3 detection and the verification checklist that currently asserts all four directories exist.
- **Risk:** medium
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - Happy path: a scaffold run in a temp `HOME` creates `docs/CONTEXT.md`, `docs/decisions/`, `docs/learnings/`, `docs/learnings/sources/`.
  - Edge case: the four retired directories are not created.
  - Error path: the State-3 "Ensemble already present" probe still fires on a repo with the new layout.
  - Integration: the setup verification checklist matches what is actually created.
  - Negative control: remove the `docs/decisions/` creation, confirm the scaffold test goes red, restore.
- **Verification:** install tests pass. Every run uses an explicit temp `HOME` on the same command line; the live install is never touched.

### U12. Close out

- **Goal:** TD5 is resolved and the foundation describes the store that now exists.
- **Requirements covered:** none.
- **Dependencies:** U6, U7, U11.
- **Files:** `docs/plans/tech-debt-tracker.md`, `docs/foundation.md` (§11), `docs/README.md`.
- **Approach:** Mark TD5 resolved citing EN14. Rewrite foundation §11 to describe three artifact types. Correct the tracker's TD5 cost analysis, which asserted the migration was cheap only before the wiki fills — the reference cost is time-invariant and only the entry cost varies.
- **Risk:** medium
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Test expectation:** none — documentation only; `ensemble-lint` covers the frontmatter of the files touched.
- **Verification:** `ensemble-lint` clean on the three files; TD5 shows resolved.

## Decisions, assumptions & risks

**Decision: three types, not two.** Collapsing to captured-vs-ingested was the
obvious cheap fix for TD5. Rejected: it keeps one artifact shape and so leaves
the two highest-value gaps (vocabulary, invariants) unaddressed. The types chosen
differ in lifecycle, which is the property that makes a split load-bearing.

**Decision: the more-durable tie-break.** A candidate matching two types is
written as the more durable one. The alternative — write both and cross-link —
was rejected because it reintroduces the duplication the generalization step in
`capture-gate.md` exists to prevent.

**Decision: grounding is advisory, never a gate.** A solution doc legitimately
cites a deleted path or a pre-fix state. A hard gate would make the common case
fail and train the user to bypass it.

**Assumption corrected after peer review: zero entries is true only here.**
`docs/learnings/` does not exist in *this* repo, so U8–U11 are reference-only
edits locally. But these skills install into other repos, which may hold hundreds
of entries under the retired directories. U13 carries the migration, and U10 does
not stop validating the old paths until it has run.

**Risk: SKILL.md size.** `en-learn`'s SKILL.md gains a router (U5), a glossary
step (U6), and a grounding step (U7). It is already among the 15 skills over the
Codex 8000-byte injection limit (TD2). U5's tests assert the size and require TD2
be cited if it grows. Mitigation is to push detail into references, which the
self-contained layout already favours.

**Known limit: no behavioural coverage (TD7).** The router (U5) and the glossary
writer (U6) are model judgments. Their tests verify the specification, not the
behaviour. The peer raised this twice and was right twice; the response is to
state the limit rather than claim coverage that does not exist. TD7 tracks an
eval suite, and this plan leaves the fixture corpus it would need.

**Risk: the parity surface grows.** Two new duplicated references
(`glossary-rules.md`, and the four learn references in U9) add carriers that can
drift. Both units add guards whose carriership is derived from `requires:`
declarations rather than file presence, so the EN13 hole — deleting file and
declaration together going unnoticed — cannot reopen.

**Noted, out of scope:** `EN12` and `EN13` are still in `docs/plans/active/` with
non-terminal status despite having shipped. That is an `en-learn` plan-lifecycle
gap, not this plan's concern.
