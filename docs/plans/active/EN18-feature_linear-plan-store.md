---
type: plan
plan_type: feature
plan_id: EN18
title: Linear plan store — publish reviewed plans to Linear and build from them
status: in_progress
location: active
created: 2026-09-19
shipped:
deepened:
covers_requirements: []
requirements_pending: true
related_design: docs/designs/2026-09-18-linear-plan-store-design.md
peer_review_verdict: revise
peer_review_iterations: 3
peer_review_last_run: 2026-09-22
peer_review_plan_hash: d60bd1a2f2d91322d6da0c2903fc9f66b9b4aa968e8e6d56f1de76e244fc396a
peer_review_resolutions:
  - finding_id: "1-1"
    iteration: 1
    severity: P1
    title: The format contract cannot reproduce the complete plan
    status: applied
    location: U1
  - finding_id: "1-2"
    iteration: 1
    severity: P1
    title: Invalid Linear configuration silently selects local mode
    status: applied
    location: U2
  - finding_id: "1-3"
    iteration: 1
    severity: P1
    title: Partial publish recovery is claimed but not designed
    status: applied
    location: U3
  - finding_id: "1-4"
    iteration: 1
    severity: P1
    title: The materialized plan path is not actually ignored
    status: applied
    location: U3, U4
  - finding_id: "1-5"
    iteration: 1
    severity: P1
    title: Core protocol behavior has only prose assertions
    status: deferred
    rationale: Correct, and already named as the headline risk. The fix the peer proposes, an offline deterministic seam over saved MCP payloads, requires a materializer script; the operator considered exactly that split and chose model-driven MCP for the whole path, knowing it forfeits negative controls. Partially mitigated instead - U1 now acceptance-tests on hash equality rather than eyeballing, and lands a golden fixture pair the materialization has to reproduce. Revisit by promoting the fallback already recorded in Decisions - a script over the GraphQL API - if the model-followed path proves unreliable in use.
    location: global
  - finding_id: "1-6"
    iteration: 1
    severity: P1
    title: Abruptly abandoned builds cannot run the promised cleanup
    status: applied
    location: U5
  - finding_id: "1-7"
    iteration: 1
    severity: P1
    title: Required Linear workflow states are not validated
    status: applied
    location: U5
  - finding_id: "1-8"
    iteration: 1
    severity: P1
    title: The en-learn configuration carrier has no owner
    status: applied
    location: U6
  - finding_id: "1-9"
    iteration: 1
    severity: P2
    title: The recorded blast radius is factually inconsistent
    status: applied
    location: U7
  - finding_id: "1-10"
    iteration: 1
    severity: P2
    title: The reversed design decision has no implementation unit
    status: applied
    location: U7
  - finding_id: "2-1"
    iteration: 2
    severity: P1
    title: Linear mode does not actually keep en-flow local
    status: applied
    location: U3
  - finding_id: "2-2"
    iteration: 2
    severity: P1
    title: Archiving can leave tracked source files deleted
    status: applied
    location: U3
  - finding_id: "2-3"
    iteration: 2
    severity: P1
    title: The GitHub handoff does not guarantee a Linear issue link
    status: applied
    location: U4
  - finding_id: "2-4"
    iteration: 2
    severity: P1
    title: Shipping mode is inferred from mutable repository configuration
    status: applied
    location: U6
  - finding_id: "2-5"
    iteration: 2
    severity: P2
    title: Materialization does not reject duplicate unit identifiers
    status: applied
    location: U4
  - finding_id: "3-1"
    iteration: 3
    severity: P1
    title: The read-back gate still verifies only the hashed subset
    status: applied
    location: U3
  - finding_id: "3-2"
    iteration: 3
    severity: P1
    title: The retry protocol still has unrecoverable publish windows
    status: applied
    location: U3
  - finding_id: "3-3"
    iteration: 3
    severity: P1
    title: The plan itself can be tracked when promotion archives it
    status: applied
    location: U3
  - finding_id: "3-4"
    iteration: 3
    severity: P1
    title: U4 consumes an ignore rule without depending on U3
    status: applied
    location: U4
  - finding_id: "3-5"
    iteration: 3
    severity: P1
    title: Linear intake is selected by argument shape instead of plan_store
    status: applied
    location: U4
  - finding_id: "3-6"
    iteration: 3
    severity: P1
    title: Workflow-state validation is not scoped to Linear mode
    status: applied
    location: U5
  - finding_id: "3-7"
    iteration: 3
    severity: P1
    title: Build provenance remains asymmetric
    status: applied
    location: U6
  - finding_id: "3-8"
    iteration: 3
    severity: P2
    title: The design amendment check is ordered after possible archival
    status: applied
    location: U7
depth: standard
data_scale: small
---

# EN18 — Linear plan store — publish reviewed plans to Linear and build from them

## Context

Plans live in `docs/plans/active/` and are invisible to anyone not reading the repo. The
operator wants one place to watch work, with app-reported issues triaged in Linear alongside
plans that `/en-build` executes. A second driver is a reframing recorded in the design: plans
are transient execution artifacts, not documentation, so the durable record belongs in ADRs
and architecture docs derived from the actual diff.

**Build state, 2026-09-22.** U1 and U2 are built and committed on
`EN18-linear-plan-store` (`ee14ac9`, `aadaf67`). U1 was a live round-trip spike and its
findings changed what the remaining units must do; this revision is that rewrite.

## Requirements covered

None. `docs/foundation.md` carries no R-IDs (it uses G-IDs, UC-IDs and D-IDs), so this plan is
in the State-2 retrofit state: `requirements_pending: true`. Run `/en-foundation --retrofit`
later to back-fill.

## Out of scope for this plan

- **Operator configuration, not code**: adding the "Agent Ready" workflow state to the Linear
  team, and setting the GitHub integration to transition issues on merge only. If it transitions
  on PR open it will drag the parent out of Review, and no code here can defend against that.
- **Migrating existing plans.** `docs/plans/completed/` stays as a build log; nothing moves.
- **Wiring Linear mode through `/en-flow`.** The chained flow is a follow-up. It is not merely
  documented as unsupported: U3 gives it an enforceable boundary, because `/en-flow` calling
  `/en-plan` in a Linear repo would otherwise publish, archive, and then hand `/en-build` a path
  that no longer exists.
- **`/en-sweep`, `/en-brainstorm`, `/en-setup`, `/en-foundation`.** Each references a plan path
  but degrades harmlessly: sweep's draft-archiving finds no local drafts, brainstorm's resume
  pool simply stops seeing archived designs (intended), setup still scaffolds the directories,
  foundation only cross-links.

## Approach (high-level)

A per-repo switch selects where a plan lives. Authoring does not change: `/en-plan` writes the
plan to `docs/plans/active/`, peer-reviews it against that file, and computes
`peer_review_plan_hash` exactly as today. Only the promotion step differs. In Linear mode the
plan is published to Linear as a parent issue plus one sub-issue per unit, the publish is
verified by reading it back, and the plan and its design doc move to gitignored archives under
`.ensemble/`. No plan-related commit is made at all.

`/en-build` gains one new capability: given a Linear identifier instead of a path, it fetches
the plan and **materializes it back into a plan file** in the canonical format. Everything
downstream is unchanged, because it is once again reading a file: the preflight sub-state
matrix, `ensemble-plan-hash`, the unit loop, the 9f checkpoint. That materialization is the
single seam that keeps the blast radius to three skills rather than nine.

All Linear I/O goes through the Linear MCP server, which the operator is already connected to
over OAuth. No credential is stored, and no helper makes an HTTP call.

## Test seams

Two existing seams, inherited by every unit. Both are cheap and neither needs a network.

- **Drift tests over skill prose** (`tests/lint/*.test.sh`). The house pattern for a prose
  invariant: assert the instruction is present and specific. Every SKILL.md change here lands
  with one. They must end in `report`, or they silently always pass.
- **Carrier parity** (`tests/parity/*.test.sh`). A reference or script copied into more than one
  skill must be byte-identical; the existing parity tests already enforce this and pick up new
  carriers automatically.

No new seam is added. The publish and fetch paths run through MCP tool calls, which cannot be
PATH-shadowed the way `tests/lint/peer-isolation.test.sh` fakes the `claude` CLI, so they are
not directly testable. U1's fixtures stand in as worked examples rather than assertions. This
is a deliberate, recorded cost of the MCP decision; see Decisions, assumptions & risks.

## Technical design

Five components change, and the publish and build paths are each a multi-step protocol, so a
directional sketch rather than a spec.

**Publish (`/en-plan`, after promotion):**

```
plan file (reviewed, hashed)
  -> create parent issue        state: Agent Ready, team from config
  -> create sub-issue per unit  in dependency order, blockers first
                                title: "<goal summary> (U3)"
                                description: the unit's markdown fields
  -> read back parent + all sub-issues
  -> materialize to a temp plan file, hash it with ensemble-plan-hash
  -> compare against the plan's own peer_review_plan_hash
       match    -> archive plan + design doc, stamp linear_issue:, no commit
       mismatch -> leave everything in place, surface the diff, stop
```

**Build (`/en-build`, given `ENG-412`):**

```
identifier -> fetch parent + sub-issues
           -> materialize to docs/plans/active/<id>.md (gitignored path)
           -> existing step 4 preflight, unchanged from here on
           -> parent: In Progress
           -> per unit: sub-issue In Progress -> Done as the unit commits
           -> parent: Review
```

The canonical format contract is one reference doc carried by both `/en-plan` and `/en-build`,
so publish and materialize cannot drift apart.

## Implementation units

Each unit has a stable U-ID. Never renumbered after assignment.

### U1. Pin the Linear plan format against a live round-trip

- **Goal:** Establish, by publishing a real plan and reading it back, exactly what Linear
  preserves, and record it as the format contract both later units build on.
- **Requirements covered:** none (requirements_pending)
- **Dependencies:** none
- **Interfaces:**
  - *Produces:* `references/linear-plan-format.md`, an **invertible** mapping for every part of
    a plan that materialization must reproduce, not just the unit fields:
    (a) the seven hashed unit fields (Goal, Files, Approach, Risk, Category, Gated,
    Dependencies); (b) the two hashed plan-level frontmatter values `depth` and `data_scale`,
    without which `ensemble-plan-hash` cannot match; (c) the frontmatter the preflight matrix
    reads, namely `status`, `peer_review_verdict`, `peer_review_resolutions`,
    `peer_review_plan_hash`, `plan_id`, `title`, `related_design`; (d) the unit fields
    `/en-build` step 4 validates but the hash excludes, namely Test scenarios, Verification,
    Requirements covered, Reversibility, Ship scope, Execution note, Interfaces; (e) the
    `(U<N>)` title suffix; (f) the ordering rule (sort by U-ID, never Linear's sub-issue
    order); and (g) the materialization rules that invert all of it.
- **Files:** `skills/en-plan/references/linear-plan-format.md`,
  `skills/en-build/references/linear-plan-format.md`, `tests/fixtures/linear/README.md`,
  `tests/fixtures/linear/EN18-sample-plan.md`, `tests/fixtures/linear/EN18-readback.json`
- **Approach:** Take a real multi-unit plan from `docs/plans/completed/`. Publish it by hand to
  a scratch Linear team through the MCP server: one parent, one sub-issue per unit, each
  description carrying the `- **Label:**` bullets verbatim and each title suffixed `(U<N>)`.
  Read all of it back. Diff the retrieved field values against the source. Record what survived
  and what Linear altered. If the bullet markup does not survive, the format doc specifies the
  carrier that does (a fenced block inside the description) and later units follow it. Land the
  source plan and the read-back JSON as fixtures so the format is legible without a Linear
  account. Delete the scratch issues afterwards. Gated because this writes to the operator's
  real Linear workspace: nothing in this repo has ever written to an external service, and no
  test or lint can verify the result. The issues are throwaway, but the write is real.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** true
- **Ship scope:** in
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* a 5-unit plan publishes, reads back, and materializes to a plan file whose
    `ensemble-plan-hash` is **identical** to the source plan's. Hash equality is the acceptance
    test, not field-by-field eyeballing, because it is exactly what U3 and U4 depend on.
  - *Edge case:* a unit whose `Approach` contains backticks and a multi-line list; confirm code
    spans and list structure survive, since real plans are full of both.
  - *Error / failure path:* Linear alters or strips the `- **Label:**` markup. Expected outcome
    is not a failed unit: the format doc records the alteration and specifies the fallback
    carrier, and the fixtures capture what Linear actually returned.
  - *Integration:* the `(U<N>)` title suffix survives and is parseable back to the U-ID, which
    is what gives later units their ordering key.
- **Verification:** both carriers byte-identical (parity test); fixtures present and readable;
  the format doc states a decision for every item (a) through (g) above, with no gaps; and the
  round-trip produces a matching `ensemble-plan-hash`.

### U2. Per-repo config for the plan store, and the carriers to read it

- **Goal:** `plan_store: local|linear` and `linear_team` resolve through the existing config
  layers in every skill that needs them.
- **Requirements covered:** none (requirements_pending)
- **Dependencies:** none
- **Files:** `.ensemble/config.local.example.yaml`,
  `skills/en-setup/references/templates/config-local-example.yaml`,
  `skills/en-build/scripts/ensemble-config-get`, `skills/en-ship/scripts/ensemble-config-get`,
  `tests/lint/plan-store-config.test.sh`
- **Approach:** Document both keys in the scaffold template and the repo's own example file,
  commented out, with `plan_store` defaulting to `local` so every existing repo is unaffected by
  omission. `ensemble-config-get` treats an out-of-set value as absent and falls through, which
  is wrong here: an operator who writes `plan_store: Linear` would silently get local mode and
  commit a plan they believed was published. So read the **raw** value first and branch on three
  cases: absent means `local`; exactly `local` or `linear` is honoured; **present but anything
  else is a blocking error**, naming the key and the accepted values. `linear` additionally
  requires a non-empty `linear_team`, checked at the same point, or it is the same blocking
  error. `ensemble-config-get` has no carrier in `en-build` or `en-ship` today, so copy it in
  verbatim; the anchor test forbids resolving a helper outside its own skill directory, which is
  why this is a copy and not a shared path.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* `plan_store: linear` in `.ensemble/config.local.yaml` resolves to `linear`;
    absent resolves to `local`.
  - *Edge case:* `plan_store: Linear` and `plan_store: tracker` are **errors**, not a silent
    fall back to local. The message names the key and the two accepted values.
  - *Edge case:* `plan_store: linear` with `linear_team` absent or empty is the same blocking
    error, raised before any Linear call.
  - *Error / failure path:* `~/.ensemble/config.json` is malformed. Expected: one stderr line
    naming the file; a repo with no `plan_store` set still resolves `local` and proceeds, since
    a machine-config problem must not break a repo that never opted in.
  - *Integration:* the two new carriers are byte-identical to the eight existing ones.
- **Verification:** new drift test passes; carrier parity test picks up the two new copies;
  `ensemble-lint` clean.

### U8. Make room in the two SKILL.md files every remaining unit edits

- **Goal:** `skills/en-build/SKILL.md` and `skills/en-plan/SKILL.md` have enough headroom
  under the 24576-byte budget for U3 through U7 to add their pointers.
- **Requirements covered:** none (requirements_pending)
- **Resolves:** TD14
- **Dependencies:** none
- **Files:** `skills/en-build/SKILL.md`, `skills/en-build/references/autonomy-contract.md`,
  `skills/en-plan/SKILL.md`, `skills/en-plan/references/finalize-loop.md`,
  `tests/lint/en-build-autonomy-contract.test.sh`, `tests/lint/en-qa-autonomy-contract.test.sh`,
  `tests/lint/en-build-stop-conditions.test.sh`, `tests/lint/en-build-suite-sequencing.test.sh`,
  `tests/peer-resolution-trailer/peer-resolution-trailer.test.sh`
- **Approach:** This is listed first because it unblocks everything after it, and numbered U8
  because U-IDs are never reassigned. Measured on 2026-09-22: en-build has **2 bytes** of
  headroom and en-plan **23**, so U1's one-line pointer already had to be paid for by trimming
  prose. Five more units edit these same two files.
  Move en-build's `## Agent autonomy contract` block (the scope note, the five legitimate pause
  cases and the anti-pattern table, about 2.1KB) into `references/autonomy-contract.md`, leaving
  a pointer in the flow that names it. Move `/en-plan`'s step 16 finalize-loop **policy** (the
  severity gate on the re-loop, the iteration cap, the resolutions log) into a new en-plan-only
  `references/finalize-loop.md`. Deliberately NOT into the existing `references/outside-voice.md`:
  that file is carried byte-identical by three skills, so editing it turns a headroom fix into a
  three-carrier parity change. Five tests assert on the moved prose; each must follow the text to
  its new location rather than be deleted or loosened. This is a move, not a rewrite: the words
  that land in the references are the words that left the skills.
- **Risk:** low
- **Category:** other
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* both files are under 24576 with at least 1KB spare, asserted by the existing
    `skill-size` test; `skill-payload` still passes, so both new references are reached from
    their skill's own flow.
  - *Edge case:* every assertion in the five coupled tests still passes, now reading the
    reference rather than the SKILL.md. A test that cannot find its text must be repointed, never
    deleted: the prose it guards did not stop mattering because it moved.
  - *Error / failure path:* `references/outside-voice.md` is untouched, so the three-carrier
    parity test is unaffected. Asserted, because editing it is the tempting shortcut here.
  - *Integration:* `tests/lint/en-qa-autonomy-contract.test.sh` compares en-qa's contract against
    en-build's; it must still find both after the move.
- **Verification:** `skill-size` and `skill-payload` pass; all five coupled tests pass; carrier
  parity unchanged; `./tests/run.sh` green.

### U3. `/en-plan` publishes to Linear, verifies, archives, and makes no commit

- **Goal:** On promotion in Linear mode, the reviewed plan reaches Linear, is verified by
  read-back, and both it and its design doc leave the working tree without being committed.
- **Requirements covered:** none (requirements_pending)
- **Dependencies:** U1, U2, U8
- **Files:** `skills/en-plan/SKILL.md`, `skills/en-plan/references/linear-publish.md`,
  `.gitignore`, `tests/lint/en-plan-linear-publish.test.sh`
- **Approach:** Add a step between promotion (17) and auto-commit (18). In `local` mode both
  are unchanged. In `linear` mode: publish per U1's format doc, in dependency order so each
  unit's blocking edges reference identifiers that already exist; read back; materialize; hash
  with `ensemble-plan-hash` and compare against the plan's own `peer_review_plan_hash`.

  **The hash is necessary but not sufficient, so it is not the whole gate.**
  `ensemble-plan-hash` covers seven unit fields plus `depth` and `data_scale`; U1's format
  contract maps considerably more, including Test scenarios, Verification, Requirements covered,
  Reversibility, Ship scope, Execution note and Interfaces. A field Linear mangled outside the
  hashed subset would verify clean here and then reach `/en-build` step 4, which validates
  exactly those fields. So verification is **field-by-field over the full invertible mapping**,
  with the hash comparison as one clause of it rather than a proxy for it. Archive only when
  both hold.

  On match, archive both sources.

  **Three things U1 measured that this step has to handle, none of which were assumed when the
  plan was first written.** First, **Linear rewrites `- ` list markers to `* `** in a stored
  description, so the read-back never matches what was sent. The verify step normalizes `* **`
  back to `- **` before canonicalizing, exactly as U4 does on the build side, and the two
  normalizations are the same rule written once in U1's format doc rather than twice from
  memory. Without it the read-back hashes seven empty fields and verification fails on every
  plan. Second, **a sub-issue does not inherit its parent's state**: one created under an Agent
  Ready parent lands in **Backlog**. Each sub-issue's state is therefore set explicitly at
  creation, never left to the default, or U5 starts a build against units nobody marked ready.
  Third, **`list_issues` truncates descriptions** (`"(truncated, use get_issue for full
  description)"`), so read-back is one list call plus a `get_issue` per unit. That N+1 is a
  deliberate accepted cost: a truncated description that silently verified would be worse than
  a slow one that verified honestly. **The tracked-file contract comes first, because moving a tracked
  file into an ignored directory leaves a tracked deletion in the working tree and the promised
  no-commit promotion would leave the repo dirty.** **Both sources get the check, and for the
  same reason.** An earlier draft of this unit assumed the plan was always untracked because
  `/en-plan` wrote it that run, which is false on `--resume`: a `/en-sweep` draft, or any plan
  committed before promotion, arrives tracked. EN18 itself is tracked, so the first plan this
  feature would ever have published is the counterexample. So: an **untracked** source moves to
  `.ensemble/archive-plans/` or `.ensemble/archive-designs/`, stamped with `linear_issue:` and
  `archived:` so it reads as superseded and doubles as the plan-to-issue audit trail. A
  **tracked** source, plan or design, is left exactly where it is: the design doc is closed out
  to `accepted` in the normal way, and a tracked plan keeps its place in `docs/plans/active/`
  with `linear_issue:` and `archived:` stamped into its frontmatter, so it reads as superseded
  without a tracked deletion appearing in a tree the promotion promised not to dirty. Both are
  already durable and in history, which is what archiving was for. Removing them is then a
  normal committed change someone makes deliberately, not a side effect of promotion.
  **Check tracked status for both sources before any Linear mutation**, not after, so the
  decision is never made with a half-published plan on the other side.

  **Confirm the design doc's amendments here too**, before deciding its fate: once the design is
  archived or closed out, an un-amended one is the version that survives. U7 records the decision
  in the foundation and runs last, so it cannot be the thing that checks this. Then skip
  step 18 entirely: a repo in Linear mode makes no plan-related commit. On mismatch or partial
  publish, move nothing and surface what landed; the plan stays in `active/` and the failure is
  visible. **Rollback is cancel, not delete**: U1 found the MCP server exposes no delete-issue
  tool. A failed publish therefore cancels what it created and says so, and the idempotency
  protocol below is what makes a retry safe, rather than the cleanup being. **Idempotency protocol, in this order, because a retry must never create a second
  parent:** (1) if the plan's frontmatter already carries `linear_issue:`, that parent is
  authoritative; (2) otherwise **search the team for an existing parent carrying this plan's
  stable identity before creating one**. Writing `linear_issue:` immediately after the create
  narrows the crash window but cannot close it: a process killed between the API returning and
  the frontmatter write leaves an orphan parent that the next run cannot see, and the run after
  that creates a second. Remote discovery is what closes it, so the plan's `plan_id` is carried
  in the parent's title as the durable identity and searched for first. Then (3) create the
  parent if discovery found none, writing `linear_issue:` into the frontmatter before any
  sub-issue exists; (4) fetch the parent's existing sub-issues and reconcile by the `(U<N>)`
  suffix, creating only units that are absent and **setting each one's state explicitly**;
  (5) refuse and surface if two sub-issues claim the same U-ID, rather than guessing which is
  current. **A cancelled parent is not reusable**: discovery ignores parents in a canceled state
  and creates a replacement, because reusing one would resurrect the sub-issues a rollback
  cancelled alongside it. Discovery that finds two live parents for one `plan_id` refuses and
  names both; that is a human decision, not a coin flip. Add the two archive directories to `.gitignore` as individual entries, matching the
  existing precise style (`.ensemble/config.local.yaml`), never `.ensemble/` wholesale, because
  `.ensemble/config.local.example.yaml` is tracked. The third entry,
  `.ensemble/materialized-plans/`, belongs to U4, which is the unit that writes there. **Enforce the `/en-flow` boundary rather than
  documenting it:** when `/en-plan` is invoked from `/en-flow` in a repo whose `plan_store` is
  `linear`, refuse before publishing, naming the reason, so the chain cannot reach the state
  where the plan is in Linear and `/en-flow` is holding a dead path. Not gated: implementing this edits prose and `.gitignore`, and it
  writes to Linear only when someone later runs `/en-plan` in a configured repo.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* drift test asserts the prose names the dependency-order rule, the read-back
    verification, both archive paths, the `linear_issue:`/`archived:` stamps, and the no-commit
    rule.
  - *Edge case:* `local` mode prose is unchanged and step 18 still commits. The test asserts
    both modes, or a future edit could quietly make local mode stop committing.
  - *Edge case:* a **tracked** source, plan or design, is left in place and stamped rather than
    moved, so promotion leaves no tracked deletion; an **untracked** one is archived. Asserted
    for **both** sources, since the plan being tracked on a `--resume` run is the case the first
    draft of this unit got wrong.
  - *Edge case:* verification compares the full invertible mapping, not only the hashed fields.
    Asserted, because a hash-only gate passes while `/en-build` step 4 later fails on a field
    the hash never covered.
  - *Error / failure path:* `/en-flow` invoking `/en-plan` in a `linear` repo refuses before
    publishing, rather than stranding the chain with a path that no longer exists.
  - *Error / failure path:* the prose states that a hash mismatch or partial publish archives
    nothing and leaves the plan in `active/`, and that cleanup cancels rather than deletes
    because no delete tool exists. Asserted, because it is the recovery contract.
  - *Error / failure path:* the verify step normalizes `* **` to `- **` before hashing.
    Asserted, because without it every publish fails verification and the tempting "fix" is to
    weaken the comparison.
  - *Edge case:* each sub-issue's state is set explicitly at creation rather than inherited.
    Asserted against the Backlog default U1 measured.
  - *Error / failure path:* the five-step idempotency protocol is present and ordered, and
    **remote discovery by `plan_id` precedes the create**. Asserted specifically, because
    write-after-create alone leaves a crash window that produces a duplicate parent on the run
    after next, which is the failure a retry protocol exists to prevent.
  - *Error / failure path:* discovery skips canceled parents, and two live parents for one
    `plan_id` refuse rather than pick. Duplicate U-IDs under one parent likewise refuse.
  - *Integration:* `.gitignore` gains exactly the two archive directory entries and does not
    contain a bare `.ensemble/` line, which would contradict the tracked example file.
- **Verification:** drift test passes and fails when any of the prose invariants is removed;
  `git check-ignore` confirms both archive paths are ignored and
  `.ensemble/config.local.example.yaml` is not.

### U4. `/en-build` accepts a Linear identifier and materializes the plan

- **Goal:** `/en-build ENG-412` fetches the plan from Linear, writes it back as a plan file in
  the canonical format, and hands to the existing preflight unchanged.
- **Requirements covered:** none (requirements_pending)
- **Dependencies:** U1, U2, U8
- **Files:** `skills/en-build/SKILL.md`, `skills/en-build/references/build-preflight.md`,
  `.gitignore`, `tests/lint/en-build-linear-intake.test.sh`
- **Approach:** Step 4 currently opens with "Read `<plan-path>`". Put an argument resolver in
  front of it. **The mode comes from `plan_store`, and the argument's shape only has to agree
  with it**; selecting on shape alone would let `/en-build ENG-412` reach Linear in a repo
  configured `local`, which is the one thing the per-repo switch exists to prevent. Four
  combinations, resolved before any fetch and before the branch is created:

  | `plan_store` | argument | outcome |
  |---|---|---|
  | `local` | a path | unchanged, today's behaviour |
  | `local` | an `ABC-123` identifier | refuse, naming `plan_store: local`; no fetch, no branch |
  | `linear` | an `ABC-123` identifier | fetch and materialize |
  | `linear` | a path | build it, and record provenance as `local` (see U6) |

  That last row is deliberate rather than a refusal: a repo mid-migration still has plans on
  disk, and refusing them would strand work the switch was never meant to touch. What matters is
  that the **resolved mode is recorded as immutable build provenance**, so `/en-ship` and
  `/en-learn` act on what this build did rather than on what the config says later.
  `.gitignore` gains `.ensemble/materialized-plans/` **here, in the unit that writes to it**,
  rather than inheriting it from U3; a unit that writes a file to a tracked path is not
  independently safe just because a neighbour was supposed to have ignored it first. Materialize per U1's format doc into `.ensemble/materialized-plans/<identifier>.md`,
  the ignored directory U3 adds, then let the existing "Read `<plan-path>`" proceed against it.

  **Materialization is not a copy, and U1 is why.** Linear rewrites `- ` list markers to `* `,
  so a description read back from Linear carries `* **Goal:** …` where the plan carried
  `- **Goal:** …`. `ensemble-plan-hash` anchors on `^- \*\*(Goal|Files|Approach|Risk|Category|Gated|Dependencies):\*\*`,
  so a materialized-as-returned plan canonicalizes to seven empty fields per unit. Proven with
  `--canon` during U1: as returned, `Goal:0: Files:0: Approach:0: Risk:0:`; after normalizing
  the markers, `Goal:204:… Files:107:… Risk:3:low`. Every unit therefore hashes identically to
  every other and the 9f plan-hash checkpoint compares two meaningless digests. **So
  materialization normalizes `* **` back to `- **` at the start of every unit body**, per U1's
  format doc, before anything reads the result. Field values themselves survive byte-for-byte,
  backticks, `=>`, `+`, `--flags` and all, so the normalization is the whole of the repair, not
  the first of several. Fetching is one `list_issues` for the children plus a **`get_issue` per
  unit**, because `list_issues` truncates descriptions; a build that read the truncated form
  would silently implement a plan with its Approach cut off.
  A materialized file is always overwritten, never merged, and its path can never collide with an
  authoring plan in `docs/plans/active/` because the directories are disjoint. Everything after that point, the sub-state
  matrix, `ensemble-plan-hash` at 4a, the status flip at 4b, the 9f checkpoint, is untouched,
  which is the whole point of materializing rather than teaching the preflight about Linear.
  Order units by the `(U<N>)` suffix, never by Linear's sub-issue ordering: U1's capture came
  back `updatedAt` descending, U2 before U1, so the default order is not merely unspecified, it
  is actively wrong for a build. **Name the branch
  from the Linear identifier**, `ENG-412-<slug>`, at step 5 where the feature branch is created.
  This is what lets Linear's GitHub integration associate the PR with the plan and move it to
  Done on merge; U5 hands the parent over on that assumption and nothing else establishes the
  link. In local mode the branch name is unchanged. Record in the
  preflight doc that a materialized plan is not git-tracked, so the matrix's `git tracked`
  column reads `no` and must not trigger the auto-commit offer. The materialized path is how U6
  tells a generated file from an authoring plan whose archive failed: same shape, different
  directory.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* drift test asserts the resolver distinguishes a path from an identifier, that
    materialization precedes the existing read, and that ordering comes from the U-ID suffix.
  - *Happy path:* a round-trip fixture proves it end to end. Materialize
    `tests/fixtures/linear/EN18-readback.json` (U1's real capture, markers and all) and assert
    `ensemble-plan-hash --canon` on the result matches `--canon` on
    `tests/fixtures/linear/EN18-sample-plan.md`. This is the assertion the whole unit exists
    for, and it is a real comparison rather than a prose check.
  - *Error / failure path:* the negative control for that fixture test: skip the marker
    normalization and it must go red. A canonical form of seven empty fields is a *valid*
    canonical form, so a test that only checks "hashing succeeded" passes against the bug.
  - *Edge case:* a plan whose units were created out of order in Linear still materializes in
    U-ID order. Asserted with `updatedAt`-descending input, which is what Linear actually
    returns.
  - *Edge case:* materialization refuses a description carrying the `(truncated, use get_issue
    for full description)` marker rather than treating it as the unit's Approach.
  - *Error / failure path:* the identifier does not resolve, or a sub-issue is missing a `(U<N>)`
    suffix. Expected: refuse before any build work, and say which unit is unparseable.
  - *Error / failure path:* two sub-issues carry the same `(U<N>)` suffix. Expected: refuse,
    naming the duplicate, and write no materialized file. U3 rejects duplicates on re-publish and
    U4 must reject them on read, or hand-edited Linear data makes unit contents ambiguous.
  - *Integration:* the preflight sub-state matrix is unchanged in local mode, and the
    materialized-plan row states `git tracked: no` without offering the auto-commit path.
  - *Error / failure path:* all four `plan_store` x argument combinations are asserted, in
    particular that an identifier under `plan_store: local` refuses **before** any fetch and
    before the branch is created. Mode selection on argument shape alone passes a happy-path
    test and defeats the per-repo switch.
  - *Integration:* `.gitignore` carries `.ensemble/materialized-plans/` as part of this unit, so
    U4 is safe to build whether or not U3 landed first.
  - *Integration:* in Linear mode the branch is named `<identifier>-<slug>`, which is the only
    thing that makes the later GitHub-to-Linear association work. Asserted here rather than
    assumed in U5.
- **Verification:** drift test passes; `build-preflight.md` carries the untracked-materialized
  row; no change to any local-mode assertion in the existing en-build tests.

### U5. `/en-build` owns the plan's Linear state through the build

- **Goal:** Linear reflects build progress at unit granularity, and an abandoned build leaves
  the plan visibly re-runnable.
- **Requirements covered:** none (requirements_pending)
- **Dependencies:** U4
- **Files:** `skills/en-build/SKILL.md`, `skills/en-plan/SKILL.md`,
  `tests/lint/en-build-linear-state.test.sh`
- **Approach:** The flow needs four states on the team: Agent Ready, In Progress,
  **In Review** and Done. That third name is what the team actually calls it (U1 listed the
  states on team Emble: `Agent Ready` type `unstarted`, `In Progress` and `In Review` both type
  `started`, `Done` type `completed`); an earlier draft of this unit said "Review" and would have
  failed its own preflight on a correctly configured team.

  **All of this is scoped to `plan_store: linear` and nothing else.** A local-mode run makes no
  state lookup, no MCP call and no preflight of any of it: the check fires after mode resolution
  and only on the Linear branch. Worth stating because the sentence below says "before the first
  mutation, local or remote", which reads as unconditional, and a workspace-wide state preflight
  running on every local build would be both a latency cost and a failure mode for repos that
  have no Linear workspace at all. Only Agent Ready is something the operator is told to create, so **resolve all
  four before the first mutation of this run, local or remote**: in `/en-plan` before publishing
  and in `/en-build` before the branch is created. A missing or ambiguous state is a blocking error
  naming which one, raised before any commit exists, not discovered halfway through a build.
  Then, in Linear mode, move the parent to In Progress once at step 4b beside the existing status
  flip. Per unit, move its sub-issue to In Progress when the unit starts and to
  Done when it commits, at the same points the unit loop already records progress. Move the
  parent to In Review after the last unit commits. **Match states by name, not by type**: two
  states share type `started`, so resolving "the started one" picks arbitrarily between In
  Progress and In Review. On a **graceful** failure or abort, return the
  parent to Agent Ready and leave every sub-issue at whatever state it reached, so a resumed
  build can see which units are already Done. A killed process cannot run that transition, so the
  guarantee is explicitly narrowed to graceful exits and the gap is closed at the other end:
  **at build start, reconcile a parent already In Progress** by comparing its sub-issue states
  against the branch's commits, and surface the discrepancy for an operator decision rather than
  silently resuming or silently restarting. State explicitly that `/en-build` stops touching
  the parent once it sets Review: from the moment `/en-ship` pushes a branch, Linear's own
  GitHub integration owns it, and the handoff point is the PR. Progress is never written back
  into the plan body.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* drift test asserts all four transitions and the point at which `/en-build`
    stops touching the parent, and that the third state is named In Review.
  - *Error / failure path:* a team missing the In Review state fails the preflight in both
    skills with a message naming it, before any local commit or remote write.
  - *Edge case:* state resolution matches on name. Asserted, because In Progress and In Review
    share a type and a type-based lookup would pass on a team that happens to list them in the
    convenient order.
  - *Edge case:* a resumed build does not reset sub-issues already at Done.
  - *Edge case:* in `plan_store: local`, neither `/en-plan` nor `/en-build` performs a state
    lookup. Asserted in both skills, because the state preflight is described as running before
    any mutation and a repo with no Linear workspace must not pay for or fail on it.
  - *Error / failure path:* a graceful abort returns the parent to Agent Ready. A killed
    process cannot, so the prose says so rather than promising it.
  - *Error / failure path:* starting a build against a parent already In Progress triggers
    reconciliation against the branch's commits and an operator decision, never a silent resume.
    This is what stops an interrupted build from sitting In Progress forever.
  - *Integration:* the prose states that the plan body is never edited to record progress,
    which is the rule the whole design rests on.
- **Verification:** drift test passes and goes red when any single transition is removed.

### U6. `/en-ship` and `/en-learn` stop assuming a plan file exists

- **Goal:** Neither skill breaks when the plan lives in Linear and no file is on disk.
- **Requirements covered:** none (requirements_pending)
- **Dependencies:** U4
- **Files:** `skills/en-ship/SKILL.md`, `skills/en-ship/references/plan-completion.md`,
  `skills/en-learn/SKILL.md`, `tests/lint/plan-completion-linear.test.sh`
- **Approach:** `/en-ship`'s plan-completion checkpoint sets frontmatter and `git mv`s the plan
  to `docs/plans/completed/`. `/en-learn` flips the plan's `status:` to `completed` at ship.
  Both assume a file. In Linear mode neither runs: the PR merge moves the parent to Done through
  the GitHub integration, and the completion checkpoint records
  `plan_completion_checkpoint: linear_mode` instead of `completed_and_moved`. Both skills read
  the build's **provenance**, not the repo's current configuration. `plan_store` is mutable, so
  flipping it between build and ship would make a Linear build run local completion logic, or a
  local build skip the move to `completed/`. Instead `/en-build` records the resolved mode
  as provenance at intake, and `/en-ship` and `/en-learn` read it from the plan they were handed.
  **Both directions of drift have to be catchable, so provenance is written on both paths**, not
  only the Linear one: `plan_store: linear` into the materialized plan's frontmatter alongside
  `linear_issue:`, and `plan_store: local` into the plan file on a local build. A Linear-only
  field catches a Linear build shipped under a config since flipped to local, and misses the
  inverse, a local build shipped under a config since flipped to linear, which is the one that
  would skip the `git mv` and lose the plan's move to `completed/`. When the current `plan_store`
  disagrees with the plan's recorded provenance, that is configuration drift: stop with a
  blocking error naming both values rather than guessing which is right. **A plan carrying no
  provenance field at all is a legacy plan**, predating this feature: treat it as `local`, which
  is what every plan written before U3 actually was, and say so once rather than refusing. `/en-ship` gets its
  `ensemble-config-get` carrier from U2; `/en-learn` already has one at
  `skills/en-learn/scripts/ensemble-config-get`, so it needs no new file and U2 does not add
  one. This unit exists because these two are the only remaining skills that
  would silently misbehave; the other six that reference a plan path
  degrade harmlessly and are listed under Out of scope.
- **Risk:** low
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* drift tests assert both skills branch on `plan_store` and that Linear mode
    records `linear_mode` rather than attempting a `git mv`.
  - *Edge case:* local mode is entirely unchanged, asserted explicitly in both skills.
  - *Error / failure path:* `plan_store: linear` but a plan file does exist in
    `docs/plans/active/`, from a failed archive. Expected: do not `git mv` it; surface that the
    archive did not complete. A file under `.ensemble/materialized-plans/` is a generated
    artifact and is never confused for this case, because the directories are disjoint.
  - *Integration:* `/en-ship`'s completion checkpoint's recorded value is one of the three
    known states, so a reader can tell a Linear-mode ship from an unfinished one.
  - *Integration:* `plan_store` resolves in `/en-learn` through its existing carrier, asserted so
    the unstated dependency on that file cannot rot.
  - *Error / failure path:* the repo's `plan_store` was changed to `local` after a Linear build.
    Expected: both skills stop with a drift error naming the recorded provenance and the current
    setting, rather than silently running the wrong completion path.
  - *Error / failure path:* the inverse, a **local** build shipped after `plan_store` was flipped
    to `linear`. Expected: the same drift error. Asserted separately, because provenance written
    only on the Linear path passes the first scenario and silently skips the `git mv` on this one.
  - *Edge case:* a plan with no provenance field, written before this feature existed, is read as
    `local` with a one-line note and is not refused.
- **Verification:** drift tests pass; existing en-ship completion tests still pass unchanged.

### U7. Record the decision in the foundation

- **Goal:** The foundation carries the Linear plan store as a numbered decision, so the next
  reader finds the rationale and the vocabulary rule without excavating this plan.
- **Requirements covered:** none (requirements_pending)
- **Dependencies:** U1, U2, U3, U4, U5, U6, U8
- **Files:** `docs/foundation.md`
- **Approach:** Add a D-ID taking the next free number, recording: the per-repo switch and its
  default; that authoring and peer review are unchanged and only promotion differs; that
  materializing from Linear is what leaves `/en-build`'s preflight, hash check and unit loop
  untouched, with the changed surface being `/en-plan`, `/en-build`, `/en-ship`, `/en-learn` and
  the `/en-setup` config template; that a description read back from Linear has its `- ` list
  markers rewritten to `* ` and must be normalized before it is hashed, which is the single
  non-obvious fact in the whole design; that a workflow state
  carries approval, and that U1 measured sub-issues inheriting neither their parent's labels nor
  its state, so each unit's state is set explicitly; that `/en-build` owns state until
  the PR exists; and that all Linear I/O goes through MCP rather than a script, with the
  testability cost that follows. Restate the vocabulary rule: plan and unit, never ticket.
  `docs/CONTEXT.md` needs no change, which is the point. Written last so it records what was
  built rather than what was proposed. Also verify that
  `docs/designs/2026-09-18-linear-plan-store-design.md` carries its 2026-09-19 amendment
  recording the MCP decision and its testability cost; a design that still argues for a
  script would contradict what shipped. **U3 is where that check gates anything**, since U3
  decides the design's fate and runs long before this unit; here it is a final read of whichever
  copy U3 left behind, archived or in place.
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Ship scope:** in
- **Execution note:** pragmatic
- **Test expectation:** none, documentation; `ensemble-lint --scope docs/` covers its shape.
- **Verification:** `bin/ensemble-lint --scope docs/` clean; the D-ID is the next free number and
  collides with nothing on main; the named skills match what the plan actually changed; the design
  doc's amendment is present.

## Decisions, assumptions & risks

- **Decision: all Linear I/O goes through the MCP server, not a script.** Chosen during
  planning, reversing the design doc, which is amended to say so. It needs no credential, and no
  helper in this repo has ever made an HTTP call. The design doc's original argument stands as
  the cost.
- **Risk: the verify-then-archive gate is a model-followed step, not a fail-closed one.** MCP
  tool calls cannot be PATH-shadowed the way `tests/lint/peer-isolation.test.sh` fakes the
  `claude` CLI, so publish, verify and archive carry no negative control and no automated test.
  The mitigation is weak but real: the archive move is the last step, so a skipped or failed
  verification leaves the plan sitting in `docs/plans/active/`, visibly unfinished. If this
  proves unreliable in use, the fallback is the design's original shape, a script over the
  GraphQL API with a `LINEAR_API_KEY`. Peer review raised this as P1 (finding 1-5) and proposed
  an offline seam over saved MCP payloads; that needs a materializer script, which is the split
  the operator considered and declined. Deferred knowingly, with U1 strengthened to accept on
  hash equality and to land a golden fixture pair as the partial mitigation.
- **Decision: materialize from Linear into a plan file rather than teach the preflight about
  Linear.** One seam, and six of the nine skills that reference a plan path need no change at
  all. The cost is a file written to a gitignored path on every Linear-mode build.
- **Resolved, and refuted: Linear does NOT preserve the labelled-field bullet markup.** U1 ran
  the live round-trip on 2026-09-22 against team Emble and found Linear rewrites `- ` list
  markers to `* `. Everything else held: field values survive byte-for-byte, and titles survive
  exactly with the `(U<N>)` suffix intact. So the carrier is unchanged and the repair is one
  normalization, `* **` to `- **`, applied on both sides, in U3's verify step and in U4's
  materialization. This is why U1 was a live round-trip rather than a paper exercise: the
  failure mode was silent. A plan materialized as returned still hashes, it just hashes seven
  empty fields per unit, so the 9f checkpoint would have compared two meaningless digests and
  reported green.
- **Resolved: three further facts U1 measured, each of which changed a later unit.** A sub-issue
  does **not** inherit its parent's state and lands in Backlog, so U3 sets each one explicitly.
  `list_issues` truncates descriptions, so materialization is one list call plus a `get_issue`
  per unit. The team's third state is named **In Review**, not Review, and it shares type
  `started` with In Progress, so U5 matches states by name.
- **Assumption: a partial publish is recoverable by re-running.** Re-publish must not duplicate
  sub-issues, which means matching on the `(U<N>)` suffix under the parent before creating. U3
  carries this; if it proves unreliable the operator cancels the parent and re-runs, which is
  acceptable because nothing was archived. **Cancels, not deletes**: U1 found the MCP server
  exposes no delete-issue tool, so a cancelled parent is the strongest cleanup available and
  the idempotency protocol has to carry the weight instead.
- **Risk: identifier drift.** Moving an issue between teams changes `ENG-412` and orphans a
  branch name already created from it. `previousIdentifiers` makes it recoverable by hand. Not
  mitigated in this plan.
- **Decision: no R-IDs.** `docs/foundation.md` carries none, so `requirements_pending: true`.
  This is the documented State-2 retrofit path, not an oversight.

## Tracked debt

None opened by this plan. **TD14** (both `en-build/SKILL.md` and `en-plan/SKILL.md` sitting
within a few bytes of the 24576-byte budget) is resolved by U8, which exists because five units
of this plan add prose to those two files.

## Iteration log

- 2026-09-19: Plan drafted from `docs/designs/2026-09-18-linear-plan-store-design.md`.
- 2026-09-19: Peer review iteration 1 (codex, cross-agent, effort high): `revise`, 10 findings
  (8 P1, 2 P2). Nine applied, one deferred. The P1s were substantive: the format contract mapped
  only the seven hashed unit fields and so could not reproduce a plan that hashes equal; invalid
  config silently selected local mode; partial-publish recovery was asserted but never designed;
  and the materialized plan was written to a tracked directory described as ignored. Each would
  have surfaced as a build failure rather than a review comment.
- 2026-09-19: Peer review iteration 2, `revise`, 5 findings (4 P1, 1 P2), **all new**. None of
  iteration 1's were re-raised, so those applications held. All five applied. The strongest were
  structural rather than cosmetic: `/en-flow` was only documented as unsupported rather than
  prevented, so the chain could publish a plan and then hand `/en-build` a dead path; archiving a
  **tracked** design doc into a gitignored directory would leave a tracked deletion and dirty a
  tree the promotion promises not to touch; nothing guaranteed the branch carried the Linear
  identifier that the GitHub handoff in U5 depends on; and `/en-ship` inferred its mode from
  mutable config rather than from the build's provenance.
- 2026-09-22: U1 and U2 built and committed (`ee14ac9`, `aadaf67`). U1 was the live round-trip
  spike, and it refuted the plan's central assumption: **Linear rewrites `- ` list markers to
  `* `**, which silently reduces a materialized plan to seven empty hashed fields per unit.
  It also found that sub-issues do not inherit parent state (they land in Backlog), that
  `list_issues` truncates descriptions so materialization needs a `get_issue` per unit, that the
  default sort is `updatedAt` descending, that the MCP server has no delete-issue tool, and that
  the team's third state is named In Review, not Review.
- 2026-09-22: `/en-plan --resume`. U3, U4 and U5 rewritten against those measurements; the
  assumption in Decisions marked resolved-and-refuted. **U8 added and listed first**: en-build
  had 2 bytes of headroom under the 24576-byte skill budget and en-plan 23, and five remaining
  units all add prose to those two files, so the plan could not physically be built as written.
  U8 moves en-build's autonomy contract and en-plan's finalize-loop policy into references,
  taking their drift assertions with them, and resolves TD14.
- 2026-09-22: Peer review iteration 3 (codex, cross-agent, effort high, 443s): `revise`, 8
  findings (7 P1, 1 P2), **all new**. All eight applied. The sharpest was that U3 assumed the
  plan file is always untracked because `/en-plan` wrote it that run, which is false on a
  `--resume`: EN18 itself is tracked, so the first plan this feature would ever publish was the
  counterexample, and promotion would have left a tracked deletion in a tree it promised not to
  dirty. Two more were structural: read-back verified only the nine hashed fields while
  `/en-build` step 4 validates seven the hash excludes, so a field Linear mangled outside the
  subset would verify clean and fail at build; and the idempotency protocol's write-after-create
  narrowed the duplicate-parent window without closing it, so discovery by `plan_id` now precedes
  the create. The rest tightened mode selection (resolved from `plan_store`, not the argument's
  shape), scoped the workflow-state preflight to Linear mode, made build provenance symmetric so
  the local-to-linear drift direction is caught too, moved the `materialized-plans/` ignore rule
  into the unit that writes there, and removed U7's claim to check the design doc before U3
  archives it, which U7 runs too late to do.
- 2026-09-22: Iteration cap reached (`--max-iterations` not raised), so no confirmation pass ran.
  Plan stays `in_progress`; U8 is next in build order.

