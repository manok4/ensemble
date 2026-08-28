---
type: plan
plan_type: improvement
plan_id: EN13
title: Remove the shared tree; each skill owns its files outright
status: completed
location: completed
created: 2026-08-27
shipped: 2026-08-28
deepened:
covers_requirements: []
requirements_pending: false
related_design: docs/reviews/self-contained-skills-refactor.md
depth: deep
data_scale: small
peer_review_verdict: revise
peer_review_overridden: cap-hit-accepted-by-user
peer_review_iterations: 3
peer_review_last_run: 2026-08-27
peer_review_plan_hash: 8da08527c408bce9304f9cae62a81eb372cabdf186d6c3498cfeb7a8866c2d46
peer_review_resolutions:
  - finding_id: "1-1"
    iteration: 1
    severity: P1
    title: U2 misclassifies a mass deletion as medium-risk non-destructive work
    status: applied
    rationale: Promoted to high and recategorised as deletion. Not destructive - everything is git-tracked and recoverable by revert, which is the line destructive draws - but 252 files is not medium. Cascaded U3 to high, since it depends on U2.
    location: U2
  - finding_id: "1-2"
    iteration: 1
    severity: P1
    title: U10 can delete reviewer-agent sources before U11 verifies and migrates them
    status: applied
    rationale: Real ordering bug. U10 deletes shared/, which still holds the shared/agents/*-reviewer.md files U11 reads to verify U6 absorbed every scope. U11 added to U10's dependencies and the reason stated in U10's approach.
    location: U10, U11
  - finding_id: "1-3"
    iteration: 1
    severity: P1
    title: U6 and U7 create briefs without wiring prompt builders to consume them
    status: applied
    rationale: Correct - a brief no builder reads is decoration, and today's empty-string default means nothing would fail to reveal it. Builder scripts added to both units' file lists with the wiring stated.
    location: U6, U7
  - finding_id: "1-4"
    iteration: 1
    severity: P1
    title: U8 introduces an external dependency that conflicts with skill self-containment
    status: applied
    rationale: The tension is real and was left implicit. A project-relative bin/ensemble-lint is not the dependency EN12 removed - that was a path into the plugin install - but the plan asserts no path climbs above a skill, so the distinction now appears in Decisions and U8 carries a per-call-site degradation assertion.
    location: Goal, U8
  - finding_id: "1-5"
    iteration: 1
    severity: P2
    title: U1's intentionally red test makes U2's per-batch green-suite requirement impossible
    status: applied
    rationale: A direct contradiction between two units. U1 now lands the test advisory - reporting the count without failing - and U2's final step flips it to fail-on-nonzero, the migration-aware pattern EN12 used for the anchor guard.
    location: U1, U2
  - finding_id: "2-1"
    iteration: 2
    severity: P1
    title: Mass-deletion units remain misclassified as high rather than destructive
    status: disagreed
    rationale: Raised twice at confidence 10, and declined on structural grounds. destructive means irrecoverable data loss; these delete git-tracked source in reviewed per-skill batches gated by a test. Decisively, the phase invariant requires every dependent to be at least as risky, and U3, U4 and U8 all depend on U2 - so destructive cascades to 10 of 11 units. A plan that is almost entirely destructive teaches the reader to type the confirmation without reading it, which is the over-gating failure Ensemble's own gated criteria warn about. Recorded in Decisions so the next reader sees the reasoning rather than re-litigating it.
    location: U2, U10
  - finding_id: "2-2"
    iteration: 2
    severity: P1
    title: The named-set baseline disagrees with the deletion target
    status: applied
    rationale: Correct and factual. The plan mixed a total file count (445, including SKILL.md and CONTRACT.md) with a payload-only named count (193). Baseline now stated once - 445 total, 422 payload, 193 named - and every downstream figure is payload-only.
    location: Why, U1, U2
  - finding_id: "2-3"
    iteration: 2
    severity: P2
    title: U4 has a forward test dependency on U9
    status: applied
    rationale: U4's negative control asserted a guard that U9 introduces, and U9 depends on U4. Rewritten to use cmp, which exists at U4 time, with the enforcing assertion left in U9 where it belongs.
    location: U4, U9
  - finding_id: "3-1"
    iteration: 3
    severity: P1
    title: Asset-changing units do not consistently maintain the new requires declarations
    status: applied
    rationale: A real hole I had missed. U12 creates the declarations, then U4-U8 and U11 add briefs, delete agents and move the linter without saying they update them, so the declarations would go stale immediately. Resolved by stating the standing rule in U12 and, more importantly, by naming the mechanism that already enforces it - U2 flips ENFORCING to true, so from U2 onward any unit adding an undeclared file fails the suite at its own gate. The enforcement existed; nothing said so.
    location: U4, U5, U6, U7, U8, U11, U12
  - finding_id: "3-2"
    iteration: 3
    severity: P1
    title: The baseline still asserts the discredited 193-file prune target
    status: applied
    rationale: Correct and embarrassing - I removed the target from U2's goal and left it in the Baseline block, the same fix-one-instance error the peer caught at iteration 2. The block now states no prune target at all and explains why: the end state is whatever the declarations imply.
    location: Why (Baseline), U2
  - finding_id: "3-3"
    iteration: 3
    severity: P2
    title: U12 omits its dependency on the U1 test that it rewrites
    status: applied
    rationale: U12 repoints U1's test, so it depends on it. Declared none because U1 is already built, which makes the dependency satisfied in practice but leaves the graph lying. Now U1.
    location: U1, U12
---

# EN13 — Remove the shared tree; each skill owns its files outright

## Goal

Every skill directory holds exactly the files it names, written for that skill.
`shared/` and `scripts/sync-shared` are gone. Where two skills genuinely need
identical bytes — a wire format both ends of a peer exchange must agree on — the
copies are duplicated and guarded. Everything else is written per skill and
nothing syncs it, because no two copies are the same document.

## Why

EN12 made skills self-contained and was right about that. It was wrong about
`shared/`, in a way only visible once the tree existed.

**Sharing forced genericity.** `host-detect.md` is 9.2KB because it serves 17
callers, so it documents every case. Thirteen of those seventeen skills source
it and consume none of its output — no `$HOST`, no `$PEER_CMD`. The four that do
are exactly the peer-review skills. It was never a general utility.

**The generic file was already fake.** `ensemble-build-peer-prompt` branches
three times on `ARTIFACT_TYPE`, always testing `= "plan"`. The plan's seven
review dimensions live in a heredoc inside an 11KB shell script; every other
artifact type hits `else` and gets `PLAN_REVIEW_DIMENSIONS=""`. So `en-review`
sends code to a peer with no review dimensions, and `en-foundation` sends a
document with none. One consumer's version won and the rest got an empty string.

**Inference does not work, and this is now measured rather than argued.** The
first build attempt derived "what a skill needs" by walking textual references
from `SKILL.md`. Five distinct false or missed edge classes surfaced, each found
only by breaking something: full repo paths (`skills/en-sweep/scripts/X`), the
pre-EN12 `bin/X` alias, shell sourcing closures, cross-skill paths credited to
the wrong skill, and — the one that settles it — **script comments naming
references**. `en-ship` reads as clean while carrying 15 files it never names,
because a 24KB script's comments mention them. Measured excess moved 98 → 54 →
14 as each was fixed. A number that unstable is not a basis for deleting files,
and no regex reliably separates a dependency from a mention. **U12 replaces the
walk with a declaration.**

**Baseline, stated once.** `skills/` holds 445 files: 17 `SKILL.md`, 6 `CONTRACT.md`, and **422 payload files** (references, scripts, agents). Every count below is payload-only unless it says otherwise. **No prune target is
stated.** The earlier 422 → 193 figure came from the walk U12 discards, and
restating it would lend a discredited number the authority of a goal. The end
state is whatever the 17 declarations imply, and U2 reaches it by comparison.

**The grants were seeded by inference, not declaration.** EN12 populated the
manifest with a one-time script that granted a skill anything its files
*mentioned*. `learn-lint.md` names `ensemble-lint` in a sentence that exists to
say it is a *different tool*; that one contrast pulled a 45KB script and 56KB of
its references into `en-learn`. Across the suite, skills carry 422 payload files; how many are genuinely needed is exactly the question U12 answers by declaration.

**Prose restates the executables it sits beside.** `host-detect.md` carries an
89-line inline bash snippet duplicating `ensemble-detect-host`. `outside-voice.md`
spends 161 lines describing what `ensemble-peer-invoke` does, which is precisely
what D41 moved into a script so it would be "executable and testable rather than
prose."

## Approach

Three passes, in order, each independently green.

**Prune to what is named.** Per skill, keep the files that skill names; delete
the rest. Verified by the checks EN12 already ships: over-pruning fails
`single-skill-install.test.sh` immediately, under-pruning is only bloat.

**Split the peer cluster.** A small generic core — the wire contract two ends
must agree on — stays byte-identical and copied. Everything policy-shaped
becomes a per-skill review brief. This fixes two live defects rather than
relocating them: code review and document review currently get no dimensions.

**Delete the mechanism.** `shared/`, `scripts/sync-shared`, `manifest.json`, and
the machinery that maintained them. The parity guard survives in reduced form
for the generic core only.

## Decisions, assumptions & risks

- **Duplication is the point, not a concession.** The Compound Engineering
  plugin duplicates a 2,250-line Python runner into six skills, pinned by a
  parity test, and keeps root `scripts/` for repo dev tooling only. Our generic
  core after the split is ~15KB against their 92KB.
- **A guard must survive `sync-shared`.** If the severity levels drift between
  skills, findings stop being comparable and `en-review`'s reconciliation
  buckets become meaningless with nothing failing. The generic core keeps a
  byte-parity check even though the tool that enforced it is being deleted. This
  is the single most important constraint in the plan; U9 is where it lands.
- **`ensemble-lint` is a project deliverable, not a skill asset.** `en-setup`
  step 9 already copies scripts into the consuming repo's `bin/` and already
  documents the drift. EN12's U6 mechanically rewrote `$ENSEMBLE_ROOT/bin/X` to
  `$SKILL_DIR/scripts/X` including call sites that meant "the project's linter."
  That conversion was wrong and U8 reverses it for those sites.
- **The bulk deletions are `high`, not `destructive`, and the peer disagreed twice.** `destructive` means irrecoverable data loss — DROP TABLE, TRUNCATE, recursive removal of persistent data. These delete git-tracked source in reviewed per-skill batches, each gated by a test that fails if the wrong file goes. More decisively: the phase invariant requires every dependent to be at least as risky, and U3, U4 and U8 all depend on U2, so marking it `destructive` cascades to 10 of 11 units. A plan that is almost entirely destructive teaches the reader to type the confirmation without reading it, which is the over-gating failure Ensemble's own criteria warn about. The protection the peer wants comes from U2's per-batch verification and PR review, not from a gate whose signal has been spent.
- **A project-relative path is not the dependency EN12 removed, and the plan must say so.** U8 has skills invoke `bin/ensemble-lint` in the repo they are operating on. `$ENSEMBLE_ROOT/bin/X` pointed into the *plugin install* and broke whenever that layout changed; `bin/ensemble-lint` points into the *user's project*, which is the working directory, in the same category as `npm test`. The distinction is real but narrow, so U8 carries a stated degradation: a project without the linter gets a repair instruction, never a bare exit 127.
- **The code-inspection lint rules have zero consumers.** Grepping all 17 skills
  for "fitness" returns nothing. `logging.unstructured` has no consumer either.
  Both inspect the *user's source*, which is a different product from a doc
  linter. Deleted, not relocated. Risk: someone wanted them. Mitigated by
  deleting in one reviewable unit, so restoring is a revert.
- **Assumption the plan bets on:** that per-skill briefs will be written well
  rather than copy-pasted from the generic file they replace. If U5–U7 produce
  four near-identical briefs, this plan has moved bytes and achieved nothing.
  U7's verification tests for divergence, not just presence.
- **Risk: the peer path is unreliable while we work on it.** TD1 records that a
  killed or truncated peer call returns a well-formed failure indistinguishable
  from a real one. Every unit here touching peer review may get a silently
  degraded review. Mitigated by EN11's mandatory `peer_decision:` outcome line.

## Implementation units

### U1. Freeze the named-set measurement as a test

> **Built and committed at `6fd31f3`.** Its advisory/enforcing mechanism and its
> four scaffold scenarios survive unchanged. U12 replaces only its *basis*:
> computed reachability becomes carried-vs-declared. Recorded here rather than
> rewritten, because the unit shipped and its ID is stable.

- **Goal:** The named-versus-carried gap becomes a checked number rather than an analysis that rots.
- **Dependencies:** none
- **Files:** `tests/lint/skill-payload.test.sh`
- **Approach:** A test that computes, per skill, the files it names versus the files it carries. It lands **advisory** — reporting the excess without failing — because a test that is red by design cannot coexist with U2's requirement that the suite be green after every batch. U2's final step flips it to fail-on-nonzero, the same migration-aware pattern EN12 used for the anchor guard. It asserts the excess is zero once flipped. Fails loudly now (228 excess) and is the acceptance signal for U2. Also asserts no skill carries a file no other file in that skill names, which is the condition the pruning must reach.
- **Risk:** low
- **Category:** diagnostics
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* a scaffolded skill naming exactly what it carries reports zero excess.
  - *Failure path:* a scaffolded skill carrying one unnamed file reports excess 1 and names the file.
  - *Edge:* a file named only inside another reference (not SKILL.md) counts as named, so legitimate chains like `recursion-guard` are not reported.
  - *Edge:* `en-guardrail` uses `bin/` rather than `scripts/`; the test must not report its three owned scripts as excess.
  - *Negative control:* against the tree as it stands, the test reports 228 excess across 17 skills.
- **Verification:** test written; reports 228 excess advisory-mode without failing the suite.

### U2. Prune every skill to its named set

- **Goal:** Each skill holds exactly what it declares.
- **Dependencies:** U1, U12
- **Files:** all `skills/*/`, `shared/manifest.json`
- **Approach:** Delete files not in the skill's `requires:` list. A comparison, not a walk — U12 removed the inference, so this unit makes no judgement about what a mention means. The absolute count is whatever the declarations imply and is deliberately not fixed here; the plan's earlier 193 figure came from the discredited method. Marked `high`, not `destructive` — see the risk note in Decisions. Per skill, largest excess first (en-cross-review 29, en-foundation 29, en-build 27, en-plan 26, en-review 24, en-ship 17, then the rest). Batch per skill with the suite green after each, as EN12's U3 did. `en-learn` is the traced example: 30 files to 17. The manifest shrinks to match; it is deleted in U10, not here, so this unit stays a data change.
- **Risk:** high
- **Category:** deletion
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* after each skill's batch, `single-skill-install.test.sh` and the full suite pass.
  - *Happy path:* U1's test reports zero excess for each pruned skill.
  - *Error path:* deleting a file that a reference chain genuinely needs fails `sync-shared --check`'s dangling-path rule naming the skill and path.
  - *Edge:* `en-loop` and `en-flow` reduce to one file and zero; confirm they still load and their SKILL.md names nothing absent.
  - *Integration:* `./setup --copy` into a temp HOME still installs all 17 skills and each resolves its assets.
- **Verification:** U1's test flipped to failing mode and green; suite green after every batch.

### U3. Remove the vestigial host-detect step from 13 skills

- **Goal:** Skills that never use host detection stop sourcing it.
- **Dependencies:** U2
- **Files:** `skills/{en-debug,en-flow,en-guardrail,en-learn,en-loop,en-qa,en-resolve-pr,en-ship,en-simplify,en-sweep}/SKILL.md`
- **Approach:** **10 skills, not 13.** The plan's original figure came from grepping `$HOST`/`$PEER_CMD` only. Measured against all ten variables `host-detect.md` exports, three of the named skills are genuine consumers: `en-build` uses `HOST` to choose orchestration vs handoff at its step 3, `en-setup` uses `HOST` and `PEER_AVAILABLE`, and `en-brainstorm` uses `QUESTION_TOOL` for its blocking-question selection. Deleting from those three breaks flavor selection outright. Delete the "Detect host" step from the remaining 10, and drop `host-detect.md`, `ensemble-detect-host` and `cli-wrappers.md` from them. Delete the step, not just the file: a dangling instruction is worse than an unused file.

  **The recursion-guard precondition was wrong and is dropped.** Those skills' step 2 is a self-contained `If ENSEMBLE_PEER_REVIEW=true, exit` — an env-var check that never reads `recursion-guard.md`. The file goes with the rest.

  `en-brainstorm` needing 9.2KB of host-detect for one variable is the genericity problem this plan exists to fix, but narrowing it is U4's business, not this unit's.
- **Risk:** high
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* the 7 consumers still source host-detect: `en-plan`, `en-review`, `en-cross-review` and `en-foundation` resolve `$PEER_CMD`; `en-build` still selects its flavor from `HOST`; `en-setup` reads `PEER_AVAILABLE`; `en-brainstorm` resolves `$QUESTION_TOOL`.
  - *Error path:* a skill retaining the step but not the file fails the dangling-path check.
  - *Edge:* each of the 10 still performs its recursion-guard check after losing the file, since the check is inline; asserted per skill, not in aggregate.
  - *Integration:* `en-cross-review` still completes a peer invocation end to end.
- **Verification:** suite green; recursion guard resolvable in every skill that names it.

### U4. Extract the generic wire contract

- **Goal:** One small set of files that two ends of a peer exchange must agree on byte for byte, separated from the policy currently fused with it.
- **Dependencies:** U2
- **Files:** `skills/{en-plan,en-review,en-cross-review,en-foundation,en-build}/references/peer-contract.md`, `.../finding-schema.md`, `.../recursion-guard.md`
- **Approach:** From `severity.md` keep the P0–P3 table (731B), the confidence scale, and the four autofix class names — the parts a peer emits and a host parses. From `peer-model-policy.md` keep the `peer_decision` schema, fail-soft ownership, and the "no concrete model ID anywhere in Ensemble" invariant. Leave behind everything that is host behaviour. Drop the tech-debt entry format from `severity.md`; `tech-debt-tracker-format.md` already defines it. Result is roughly 15KB carried by 5 skills.
- **Risk:** high
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** characterization-first
- **Test scenarios:**
  - *Happy path:* every severity level, confidence band and autofix class name that appears in any skill also appears in the contract, so nothing was dropped in the split.
  - *Happy path:* the 5 peer skills' contract copies are byte-identical (`cmp`).
  - *Error path:* a peer returning a finding at each severity level is routed correctly by each consuming skill after the split.
  - *Edge:* `severity.md`'s "re-verification after applying" and "three host responses" sections are code-shaped; confirm they left the contract and landed in the code-review briefs, not in en-plan's or en-foundation's.
  - *Negative control:* editing one skill's contract copy makes `cmp` report a difference. The *enforcing* guard arrives in U9, which depends on this unit; asserting it here would forward-reference a test that does not exist yet.
- **Verification:** contract copies byte-identical; no enum value lost in the split.

### U5. Give en-plan its own plan-review brief

- **Goal:** The plan review dimensions stop living in a shell heredoc.
- **Dependencies:** U4
- **Files:** `skills/en-plan/references/peer-brief.md`, `skills/en-plan/scripts/ensemble-build-peer-prompt`, `skills/en-plan/SKILL.md`
- **Approach:** Move the seven plan dimensions (A–G) out of `ensemble-build-peer-prompt`'s heredoc into a reviewable prose file en-plan owns, together with the plan-shaped routing that was in `severity.md` and the effort ladder and resolution order from `peer-model-policy.md` insofar as en-plan uses them. Remove `--artifact-type` and the three branches from en-plan's copy of the script.
- **Risk:** high
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** characterization-first
- **Test scenarios:**
  - *Happy path:* a peer prompt built for a plan contains all seven dimensions, asserted individually by name.
  - *Happy path:* the prompt no longer contains the string `ARTIFACT_TYPE`.
  - *Error path:* building a prompt with a missing brief fails loudly rather than emitting an empty dimensions block, which is today's silent failure.
  - *Edge:* the previous-review-context path for re-review iterations still assembles correctly.
  - *Integration:* a live `/en-plan` peer pass returns parseable findings anchored to unit ids.
- **Verification:** prompt contains every dimension; no artifact-type branching remains.

### U6. Give en-review and en-build code-review briefs

- **Goal:** Code review gets dimensions, which it does not currently have.
- **Dependencies:** U4
- **Files:** `skills/en-review/references/peer-brief.md`, `skills/en-build/references/peer-brief.md`, `skills/{en-review,en-build}/scripts/ensemble-build-peer-prompt`, both SKILL.md
- **Approach:** Write code-review dimensions where `PLAN_REVIEW_DIMENSIONS=""` is what ships today, **and wire each skill's prompt builder to read its brief** — a brief no builder consumes is decoration, and the current empty-string default means nothing would fail to reveal it. Fold in the 7 reviewer personas' unique `Scope` sections (~900B each) as the dimension list, since that is the content the reviewer agents actually carried. Take the effort ladder and resolution order from `peer-model-policy.md`, which names `/en-review` as their sole owner. Take the code-shaped routing from `severity.md`: "re-verification after applying" and "three host responses".
- **Risk:** high
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** characterization-first
- **Test scenarios:**
  - *Happy path:* a peer prompt built for code contains a non-empty dimensions block, which is the defect this unit fixes.
  - *Happy path:* every persona scope that existed as an agent appears in the brief.
  - *Error path:* an empty dimensions block fails the build rather than shipping.
  - *Edge:* en-build's brief and en-review's brief are not byte-identical; they review different things at different moments and identical files would mean the split was performed mechanically.
  - *Integration:* `/en-review --peer --mode headless` returns findings a caller can parse.
- **Verification:** non-empty dimensions for code; briefs measurably diverge.

### U7. Give en-foundation and en-cross-review their briefs

- **Goal:** Document review gets dimensions; ad-hoc review gets a target-shaped brief.
- **Dependencies:** U4
- **Files:** `skills/en-foundation/references/peer-brief.md`, `skills/en-cross-review/references/peer-brief.md`, `skills/{en-foundation,en-cross-review}/scripts/ensemble-build-peer-prompt`, both SKILL.md
- **Approach:** en-foundation sends a document to a peer today with no dimensions at all; write them, and wire its builder to read the brief.  en-cross-review reviews an arbitrary target, so its brief covers selecting dimensions by target shape rather than fixing one set.
- **Risk:** high
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* a foundation peer prompt contains document dimensions.
  - *Happy path:* pairwise comparison of all four briefs shows each is substantially distinct; a similarity above a stated threshold fails, because four near-identical briefs mean this plan moved bytes and achieved nothing.
  - *Error path:* en-cross-review with an unrecognised target shape falls back to a stated default rather than an empty block.
  - *Edge:* en-cross-review reviewing a plan does not silently reuse en-plan's brief by path.
- **Verification:** all four briefs present and divergent.

### U8. Make ensemble-lint a project deliverable

- **Goal:** No skill carries a 45KB linter.
- **Dependencies:** U2
- **Files:** `skills/en-setup/references/templates/`, `skills/{en-brainstorm,en-plan,en-review,en-setup,en-sweep}/SKILL.md`, `skills/*/scripts/ensemble-lint`
- **Approach:** Move `ensemble-lint` to an installable artifact `en-setup` places in the consuming repo's `bin/`, which that skill already does for four other scripts. Rewrite the five call sites from `$SKILL_DIR/scripts/ensemble-lint` to the project-relative `bin/ensemble-lint`, reversing EN12 U6's wrong conversion for these sites. Delete the `architecture.fitness-violation` and `logging.unstructured` rules and their references, which no skill consumes.
- **Risk:** high
- **Category:** deletion
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** characterization-first
- **Test scenarios:**
  - *Happy path:* the remaining 20 rules produce identical findings on a fixture corpus before and after the move.
  - *Happy path:* `en-setup` installs the linter into a scaffolded project and it runs there.
  - *Error path:* a skill invoking `bin/ensemble-lint` in a project without it surfaces a clear repair instruction naming `/en-setup`, rather than a bare 127. Asserted for each of the 5 call sites, since one silent site is enough to strand a user.
  - *Edge:* the CI workflow template still resolves its scripts.
  - *Edge:* deleting the fitness rules does not change findings on any fixture, confirming they never fired.
- **Verification:** identical findings on the corpus minus the two deleted rules; no skill carries the linter.

### U9. Replace sync-shared's parity check with a contract guard

- **Goal:** The wire contract cannot drift once the tool that enforced it is gone.
- **Dependencies:** U4, U5, U6, U7
- **Files:** `tests/parity/peer-contract-parity.test.sh`
- **Approach:** A test asserting the generic contract files are byte-identical across the 5 peer skills, and that no skill's copy has been edited. Narrower than `sync-shared --check` and it survives U10. This is the constraint the plan is built around: drift in the severity levels makes findings incomparable with nothing failing.
- **Risk:** high
- **Category:** diagnostics
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* all 5 copies identical, test passes.
  - *Failure path:* editing one byte of one skill's `peer-contract.md` fails, naming the skill and the file.
  - *Failure path:* a skill missing a contract file fails, distinguishing "absent" from "different".
  - *Edge:* a per-skill brief differing between skills does NOT fail; divergence there is the design.
  - *Negative control:* the test is verified red by mutating a copy before it is trusted.
- **Verification:** verified red by deliberate mutation, then green.

### U10. Delete shared/ and sync-shared

- **Goal:** The mechanism is gone.
- **Dependencies:** U3, U8, U9, U11
- **Files:** `shared/`, `scripts/sync-shared`, `tests/parity/shared-parity.test.sh`, `tests/lib/drop-generated`, `setup`, `README.md`, `docs/foundation.md`, `tests/lint/root-doc-links.test.sh`, `.github/workflows/ensemble-tests.yml`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
- **Approach:** **U11 must land first.** This unit deletes `shared/`, which still holds `shared/agents/*-reviewer.md` — the sources U11 reads to verify U6 absorbed every persona scope. Deleting them first makes that verification impossible and the loss silent. Delete the tree, the tool, its parity test (U9 replaces the part that still matters), the generated-copy filter that has no meaning without generated copies, and the `setup` gate that checks parity. Repoint the plugin manifests' `agents` key. Rewrite the README's layout and "Editing shared material" section, which becomes wrong the moment this lands.
- **Risk:** high
- **Category:** deletion
- **Reversibility:** rollback-required
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* full suite green with no `shared/` present.
  - *Happy path:* `./setup --copy` into a temp HOME installs 17 skills and 3 agents.
  - *Error path:* no file anywhere still references `shared/` or `sync-shared`; asserted repo-wide, including the README and CI.
  - *Edge:* the root-doc link test still passes after the README rewrite.
  - *Edge:* `tests/install/reinstall-sweep.test.sh` still passes; the setup parity gate is being removed and must not take the sweep fix with it.
  - *Edge:* `root-doc-links.test.sh` asserts the README does not link to pre-EN12 locations. That assertion inverts here and must be UPDATED, not deleted, or the guard silently stops working.
  - *Error path:* no document still instructs a contributor to edit `shared/` or run `sync-shared`, asserted repo-wide including README, foundation and CHANGELOG.
  - *Integration:* a single skill copied in isolation still resolves everything it names.
- **Verification:** suite green; no residual references; isolated skill still self-sufficient.

### U11. Cut the seven reviewer agents

- **Goal:** 39KB of agent definitions that are 81% boilerplate stop existing.
- **Dependencies:** U6
- **Files:** `shared/agents/*-reviewer.md`, `skills/*/agents/`, `skills/en-review/SKILL.md`, `skills/en-build/SKILL.md`, `docs/foundation.md`, `README.md`
- **Approach:** Delete the 7 reviewer definitions. Their unique `Scope` sections moved into the code-review briefs in U6; the remaining 81% duplicates `severity.md` and `finding-schema.md`, which the contract now owns. `en-review` dispatches personas by describing them inline. The 3 research agents stay: they do real dispatch work with distinct prompts and are genuinely invoked. **Deleting before verifying U6 absorbed every scope loses that content**, so the first verification here is a scope-by-scope diff against the briefs.
- **Risk:** high
- **Category:** deletion
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* `en-review` still dispatches every persona it did before, asserted by name.
  - *Happy path:* the 3 research agents remain and are still published by `setup`.
  - *Error path:* a persona named in en-review with no scope behind it fails the contract test.
  - *Edge:* `en-build`'s per-unit review still names its personas.
  - *Integration:* a full `/en-review` run produces findings in every always-on category.
  - *Edge:* the agent roster in `README.md` and `docs/foundation.md` reflects 3 agents, not 11; a doc claiming eleven is a stale count the next reader will trust.
- **Verification:** persona coverage unchanged; 7 files gone.

### U12. Each skill declares what it needs

> Numbered U12 because U-IDs are append-only; **execution order is dependency-
> driven, not numeric**, and this unit runs before U2. The plan already relies on
> that ordering for U11 before U10.

- **Goal:** Every skill states its own dependencies, so nothing has to infer them.
- **Dependencies:** U1
- **Files:** all 17 `skills/*/SKILL.md`, `tests/lint/skill-payload.test.sh`
- **Approach:** Add a `requires:` list to each skill's frontmatter — one entry per asset the skill needs, as a skill-relative path. Written by reading each skill, not generated: generating it from the walk would launder the same inference into a file that looks authoritative. Then repoint U1's committed test to compare *carried* against *declared* and delete its reachability walker entirely; the advisory/enforcing flip and the scaffold scenarios stay.

  Frontmatter rather than a separate file, because it keeps the declaration beside what it describes and adds no file to a tree this plan exists to shrink. The risk is a host rejecting an unknown key, which is why that is the first test scenario rather than an assumption. If a host does reject it, the fallback is `skills/<name>/requires.txt`, one path per line — same content, no parser.

  A declaration is also the artifact a human can review. The walk produced a number nobody could check; seventeen short lists can be read in a sitting.
- **Risk:** medium
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Integration (first, because it gates the design):* every skill still loads on **both** Claude Code and Codex with the new frontmatter key present. A host that rejects it sends this unit to the `requires.txt` fallback before any other work depends on the choice.
  - *Happy path:* each of the 17 declarations names only paths that exist in that skill today. A declared path with no file is a typo, caught here rather than as a dangling reference three units later.
  - *Happy path:* the repointed test reports the same PASS/FAIL shape as before, with `ENFORCING=false` still the default.
  - *Error path:* a declaration omitting a genuinely-needed file makes U2 delete it; the suite catches that, which is the check U2 relies on and must be shown to work — verified by omitting one entry deliberately and confirming red.
  - *Edge:* `en-guardrail` declares its own `bin/` scripts, which the reachability walker needed a special case for; a declaration needs none, and that carve-out is deleted.
  - *Edge:* the test contains no path-walking code afterwards; asserted by grep, so the inference cannot creep back.
- **Verification:** 17 declarations written by hand and reviewed; test compares against them; no walker remains.

  **Standing rule for every later unit.** A unit that adds or removes a skill asset updates that skill's `requires:` **in the same commit**. This is enforced mechanically rather than by discipline: U2's final step flips `ENFORCING` to true, so from U2 onward any unit adding an undeclared file, or declaring a deleted one, fails the suite at its own verification gate. U4 through U8 and U11 all move assets and are all covered by that flip. Stated here because the enforcement is easy to rely on without noticing it exists.

## Iteration log

> - 2026-08-27 (iteration 3, after a failed build): U2's method was proven wrong in
>   execution and the plan revised - new U12 replaces inference with explicit
>   per-skill declarations, U2 becomes a comparison, U3 corrected from 13 skills to
>   10. Re-reviewed at the user's request past the depth cap: verdict revise, 3
>   findings, all applied. One was a hole I had missed entirely: later units move
>   assets and nothing said the declarations move with them.
> - 2026-08-27 (iteration 2): verdict revise, 3 findings. Two applied (an
>   inconsistent file-count baseline; a forward test reference from U4 to U9).
>   One disagreed: promoting the bulk deletions to `destructive` cascades through
>   the phase invariant to 10 of 11 units. Iteration cap for depth `deep` reached.
> - 2026-08-27 (iteration 1): cross-agent peer (codex), verdict revise, 5 findings,
>   all applied. Two were structural defects rather than polish: U10 deleting the
>   reviewer sources U11 needs, and a test required to be red by one unit and
>   green by the next.
> - 2026-08-27 (initial): plan drafted. Depth deep, 12 units. Research came from
>   the EN12 post-mortem analysis rather than a fresh dispatch: per-skill
>   named-versus-carried counts, the host-detect consumption test across all 17
>   skills, and section-level analysis of the peer cluster. `docs/learnings/`
>   does not exist yet, so `learnings-research` had nothing to query.
