---
type: plan
plan_type: feature
plan_id: EN19
title: Linear plan store follow-ups: deterministic transforms, issue intake, amend, portable provenance, setup check
status: completed
location: completed
created: 2026-09-22
shipped: 2026-09-23
deepened:
covers_requirements: []
requirements_pending: true
related_design:
peer_review_verdict: revise
peer_review_iterations: 2
peer_review_last_run: 2026-09-22
peer_review_plan_hash: f359264c95b3dfefb686dc3e38ab94c00b0c903880b84bc38b6cca9c056c8607
peer_review_resolutions:
  - finding_id: "1-1"
    iteration: 1
    severity: P1
    title: Untracked designs are still stamped
    status: applied
    location: U4
  - finding_id: "1-2"
    iteration: 1
    severity: P1
    title: Cancelled units break amend verification
    status: applied
    location: U1, U6, Technical design
  - finding_id: "1-3"
    iteration: 1
    severity: P1
    title: Resume checks build state only before revision
    status: applied
    location: U6
  - finding_id: "1-4"
    iteration: 1
    severity: P1
    title: Verification rule conflicts with iteration log exclusion
    status: applied
    location: U1
  - finding_id: "1-5"
    iteration: 1
    severity: P1
    title: Issue intake can overwrite changes made during review
    status: applied
    location: U5
  - finding_id: "2-1"
    iteration: 2
    severity: P0
    title: Resume can overwrite an existing untracked plan
    status: applied
    location: U6
  - finding_id: "2-2"
    iteration: 2
    severity: P1
    title: Issue intake does not recheck sub-issues
    status: applied
    location: U5
  - finding_id: "2-3"
    iteration: 2
    severity: P1
    title: Quoted issue headings can break plan parsing
    status: applied
    location: U1, U5
  - finding_id: "2-4"
    iteration: 2
    severity: P1
    title: Issue intake needs a production write gate
    status: disagreed
    rationale: Gated covers state changed by running the unit at build time; building U5 edits skill prose and tests and writes nothing to Linear. The Linear writes happen when an operator later runs /en-plan, behind its own refusals and re-fetch checks.
    location: U5
  - finding_id: "2-5"
    iteration: 2
    severity: P1
    title: Amend needs a production write gate
    status: disagreed
    rationale: Same as 2-4. Building U6 writes nothing to Linear; the template reserves Gated for build-time external effects, and over-gating trains operators to click through.
    location: U6
depth: standard
data_scale: small
---

# EN19: Linear plan store follow-ups

## Context

EN18 (D118) lets a repo keep plans in Linear: `/en-plan` publishes a reviewed plan as a parent
issue with one sub-issue per unit, and `/en-build ENG-412` materializes it back into a plan file.
An overall review after EN18's branch review found gaps that would surface in the first real use,
and the operator approved five follow-ups to land **before the first end-to-end run**, so that run
exercises the flow as it will stay:

1. The mapping carries frontmatter and units only. Context, Out of scope, Technical design,
   Decisions and the iteration log never reach Linear, so a build loses them and the only full
   copy ends in a gitignored archive on the publishing machine.
2. Every transform (plan to payload, payload to plan, read-back comparison) is model-followed, so
   none can carry a negative control.
3. A triaged issue cannot become the plan's parent; the design doc's driving workflow (app issues
   land in Linear, get triaged, become agent work) produces two unrelated issues.
4. A plan edited in Linear makes intake refuse, and the only remedy is re-running `/en-plan` on a
   source archived on one machine.
5. Ship-time provenance lives only in the gitignored `.ensemble/materialized-plans/` file, so a
   fresh clone or `git clean` silently turns the drift check off.
6. Nothing checks the Linear workspace before the first publish, and the GitHub integration's
   state mapping (which en-build's In Review hand-off depends on) cannot be read over MCP.
7. Committed design docs trigger the tracked-source refusal on most promotions in this repo.

## Requirements covered

None: `docs/foundation.md` carries no R-IDs (`requirements_pending: true`, the State-2 retrofit
path EN18 also took).

## Out of scope for this plan

- Sub-issues reaching Done at unit commit rather than at merge (gap 8 of the overall review).
- An offline cache for building without Linear access; Linear stays a hard dependency for intake.
- Identifier drift when an issue moves teams (EN18 accepted it).
- Moving Linear I/O off the MCP server. The new script transforms data; it never calls Linear.
- The first end-to-end run itself. The operator runs it after this plan ships.

## Approach (high-level)

Split every Linear operation into a **model-followed MCP call** and a **deterministic
transform**. A new `ensemble-linear-plan` script (python3, carried byte-identical by `/en-plan`
and `/en-build`) owns three transforms: `render` (plan file to issue payloads, now including the
plan-level sections), `materialize` (saved `get_issue` JSON to plan file) and `verify` (read-back
JSON against a source plan). The MCP calls stay where they are; the skill prose shrinks to "call
Linear, save the JSON, run the script". This reverses the part of D118 that declined a
materializer script, recorded as D119, and gives the path its first negative controls.

With that seam in place, two new `/en-plan` entry points reuse it: an issue identifier as the
request (publish onto that issue) and `--resume <IDENT>` (materialize, revise, re-review, update
in place). Provenance moves into a `plan-provenance:` trailer on every unit commit so ship and
learn read git history, not a gitignored file. `/en-setup` gains a Linear check. In linear mode a
design doc is never moved or stamped.

Byte budgets constrain where prose goes: en-setup's SKILL.md has 52 bytes of headroom, en-plan's
247, en-build's 375. Every new flow lives in a reference, and each unit that adds a SKILL.md
pointer trims an equal amount elsewhere in the same file.

## Test seams

1. **The `ensemble-linear-plan` CLI** (new): subprocess tests over JSON fixtures in
   `tests/fixtures/linear/`, asserting stdout, files and exit codes. The primary seam; every
   transform rule is observed here, with negative controls.
2. **The `ensemble-plan-checkpoint` CLI** (exists): fixture git repos, as
   `tests/verification-receipt/plan-checkpoint.test.sh` already does.
3. **Prose drift tests** (exist, `tests/lint/`): only for the model-followed MCP steps, which have
   no other observable seam. Kept to routing and ordering claims.

## Technical design

Components and data flow for a Linear-mode round trip:

```
plan file ──render──▶ payload.json ──(model: save_issue per object)──▶ Linear
Linear ──(model: get_issue parent + each unit)──▶ readback.json
readback.json ──verify <plan>──▶ exit 0 | 3 + diff        (publish, en-plan)
readback.json ──materialize──▶ .ensemble/materialized-plans/<IDENT>.md   (intake, en-build)
unit commit ──trailer plan-provenance──▶ git history ──▶ ensemble-plan-checkpoint / en-learn 11a
```

**`payload.json`** (render output, consumed by the model and by tests):

```json
{"plan_id": "EN19", "repo": "github.com/owner/name",
 "parent": {"title": "<plan title> (EN19)", "description": "<markdown>"},
 "units": [{"u_id": "U1", "title": "<unit title> (U1)", "description": "<markdown>",
            "blocked_by": []}]}
```

**`readback.json`** (materialize and verify input, written by the model from MCP responses):
`{"parent": <get_issue result>, "sub_issues": [<get_issue result>, ...]}`, reading only
`identifier` (or `id`), `title`, `description` and `status` from each object, so extra MCP fields
are ignored and the EN18 capture remains a valid input. A sub-issue whose `status` is a canceled
state is not a unit: `materialize` and `verify` skip it, which is how an amend removes one.

**Parent description layout:** the plan's `##` sections other than `## Implementation units`,
verbatim and in order, then `## Verification Contract` with one fenced `yaml` block holding the
frontmatter plus `plan_full_hash` and `repo`.

**`plan-provenance:` trailer:** `{"plan_source":"linear|local","configured_store":"linear|local","plan_ref":"<IDENT or plan path>"}`.

## Implementation units

Each unit has a stable U-ID. Never renumbered after assignment.

### U1. `ensemble-linear-plan`: render, materialize and verify, tested offline

- **Goal:** One deterministic script owns every Linear data transform, covering the whole plan
  including plan-level sections, with golden fixtures and negative controls.
- **Requirements covered:** none (requirements_pending)
- **Dependencies:** none
- **Interfaces:**
  - *Produces:* `ensemble-linear-plan render <plan> [--repo <id>]` prints `payload.json` (shape in
    Technical design) and exits 0, or exits 3 naming the problem (no units, missing U-ID, a unit
    without a title). `ensemble-linear-plan materialize <readback.json> [--out <path>]` writes the
    plan file and exits 0, or exits 3 with a reason. `ensemble-linear-plan verify <plan>
    <readback.json>` exits 0 when the read-back materializes to the same default and `--full`
    digests and the same plan-level sections as `<plan>`, `## Iteration log` excepted on every
    comparison, else exits 3 printing a unified diff of the first differing section. `ensemble-plan-hash --full` extended to cover plan-level
    sections except `## Iteration log`.
  - *Consumes:* `ensemble-plan-hash` (default and `--full`), called as a sibling script.
- **Files:** `skills/en-plan/scripts/ensemble-linear-plan`,
  `skills/en-build/scripts/ensemble-linear-plan`, `skills/en-plan/scripts/ensemble-plan-hash`,
  `skills/en-build/scripts/ensemble-plan-hash`, `tests/linear-plan/linear-plan.test.sh`,
  `tests/fixtures/linear/EN19-rendered-plan.md`, `tests/fixtures/linear/EN19-readback.json`,
  `tests/fixtures/linear/README.md`, `tests/plan-hash/plan-hash.test.sh`
- **Approach:** python3, stdlib only, matching `ensemble-plan-checkpoint`. `render` splits the
  plan at the first line that is exactly `## Implementation units` (a blockquoted `> ## …` is not
  a heading), builds the parent description per the layout in Technical
  design, and one unit description per `### U<N>.` block with its title carrying the `(U<N>)`
  suffix; `blocked_by` comes from each unit's Dependencies. `repo` is the `origin` remote with
  scheme, userinfo and `.git` stripped and lowercased, overridable with `--repo` for tests; no
  origin is exit 3, per EN18's rule. `materialize` normalizes `* **` to `- **` in every
  description (and `* ` to `- ` inside the Verification Contract block), refuses a description
  still carrying Linear's truncation marker, refuses a missing or duplicate `(U<N>)` suffix among
  live sub-issues, skips canceled ones (a canceled unit and a live one may share a U-ID only if
  the canceled one came first; two live ones never), sorts units by the integer, rebuilds frontmatter from the Verification Contract, and emits the
  file. `verify` materializes to a temp file and compares. Extend `--full` so edits to Out of
  scope or Technical design in Linear are caught, not only unit fields; `## Iteration log` stays
  out because `/en-plan` appends to it, and `verify`'s section comparison skips it by the same
  rule, so the digest and the section check can never disagree. The EN19 fixtures are produced by running `render` on a
  sample plan and applying Linear's measured transformation (the marker rewrite) by hand, so the
  parent encoding is tested against the known rewrite and remains unmeasured against a live
  workspace until the end-to-end run replaces the fixture with a capture. Both carriers
  byte-identical; each carrier names the script where its SKILL.md or references already route
  Linear work, so the payload lint sees it.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* `render` then `materialize` on `EN18-sample-plan.md` reproduces a file whose
    default and `--full` digests equal the source's, and whose Context, Out of scope and Technical
    design sections are byte-equal after whitespace collapse.
  - *Happy path:* `materialize` on the EN18 capture (`EN18-readback.json`) reproduces U1's hashed
    fields, the round trip `en-build-linear-intake.test.sh` proves today, now through the script.
  - *Edge case:* sub-issues in the read-back arrive U2 before U1; the output orders U1 first.
  - *Edge case:* a read-back with U3 canceled materializes without U3, and `verify` against a
    plan that removed U3 exits 0.
  - *Edge case:* a unit Approach holding backticks and a nested list survives `render` and
    `materialize` unchanged.
  - *Error / failure path:* a description ending in `(truncated, use get_issue for full
    description)` exits 3 naming the unit; two sub-issues titled `(U2)` exit 3 naming both; a
    title with no suffix exits 3.
  - *Error / failure path (negative control):* with the marker normalization disabled, the
    happy-path digest comparison fails. With `## Out of scope` edited in the read-back, `verify`
    exits 3 and `--full` moves; editing only `## Iteration log` leaves `--full` unchanged and
    `verify` exits 0.
  - *Integration:* parity test passes with the script in both carriers; `render` refuses a repo
    with no `origin` and accepts `--repo`.
- **Verification:** `tests/linear-plan/linear-plan.test.sh` and `tests/plan-hash/plan-hash.test.sh`
  green with the negative controls confirmed red against a broken build of the script; parity and
  payload tests green.

### U2. Route publish and intake through the script (D119)

- **Goal:** `/en-plan`'s publish and read-back, and `/en-build`'s intake, call the script for every
  transform; the prose keeps only the MCP calls and their order.
- **Requirements covered:** none (requirements_pending)
- **Dependencies:** U1
- **Files:** `skills/en-plan/SKILL.md`, `skills/en-plan/references/linear-publish.md`,
  `skills/en-plan/references/linear-plan-format.md`,
  `skills/en-build/references/linear-plan-format.md`,
  `skills/en-build/references/build-preflight.md`, `docs/foundation.md`,
  `tests/lint/en-plan-linear-publish.test.sh`, `tests/lint/en-build-linear-intake.test.sh`
- **Approach:** Publish becomes: `render` to a payload file; create or update each object with
  `save_issue` per the idempotency protocol; `get_issue` the parent and each unit into a
  read-back file; `verify` against the plan; archive only on exit 0. Intake becomes: fetch into
  a read-back file, `materialize` to `.ensemble/materialized-plans/<IDENT>.md`, then the existing
  digest comparison. `linear-plan-format.md` (both carriers) becomes the spec the script
  implements, pointing at the script as the one implementation, the same relationship
  `ensemble-plan-hash` has with its canonical form. Name the MCP tools explicitly (`get_issue`,
  `list_issues`, `save_issue`, `list_issue_statuses`) where EN18's prose left them implied.
  Shorten en-plan's step 18 by routing to the reference, which frees the bytes U3 and U4 need.
  Record D119 in `docs/foundation.md`: the transforms move into a script; Linear I/O stays on MCP;
  what D118 accepted as untestable is now tested. The round-trip block in
  `en-build-linear-intake.test.sh` moves to U1's test and the drift test asserts the routing.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* drift test asserts publish runs `render`, then `save_issue`, then `get_issue`,
    then `verify`, and archives only after `verify` exits 0.
  - *Happy path:* drift test asserts intake runs `materialize` before any read of the plan and
    refuses on its non-zero exit.
  - *Error / failure path:* the references no longer instruct the model to normalize markers or
    sort units itself (`hasnt` clauses), so the two implementations cannot drift apart.
  - *Integration:* D119 present in foundation and cited from both references.
- **Verification:** drift tests green; skill-size, payload and parity tests green; en-plan
  SKILL.md smaller than before this unit.

### U3. Provenance in a `plan-provenance:` trailer on every unit commit

- **Goal:** Ship and learn resolve a build's provenance from git history on any machine; the
  gitignored materialized file becomes a fallback, not the source.
- **Requirements covered:** none (requirements_pending)
- **Dependencies:** none
- **Interfaces:**
  - *Produces:* trailer `plan-provenance: {"plan_source":"linear|local","configured_store":"linear|local","plan_ref":"<IDENT or path>"}`
    on every unit commit; checkpoint outcome `provenance_conflict` (blocking) when trailers in
    the range disagree.
- **Files:** `skills/en-build/SKILL.md`, `skills/en-build/references/unit-loop.md`,
  `skills/en-build/references/build-preflight.md`,
  `skills/en-ship/scripts/ensemble-plan-checkpoint`,
  `skills/en-ship/references/plan-completion.md`, `skills/en-learn/SKILL.md`,
  `tests/verification-receipt/plan-checkpoint.test.sh`,
  `tests/lint/plan-completion-linear.test.sh`
- **Approach:** 9e's commit adds the trailer with the values already resolved at intake, on both
  the local and Linear paths (drift detection is symmetric). The checkpoint reads
  `git log <base>..HEAD --format='%(trailers:key=plan-provenance,valueonly)'`; precedence is
  trailers, then the materialized file's frontmatter, then legacy (`local`). All trailers in the
  range must be identical or the outcome is `provenance_conflict`. A trailer saying `linear`
  returns `linear_mode` even when no materialized file exists on this machine, which is the case
  this unit exists for. en-learn 11a reads the same command. 9e's SKILL.md line gains a clause
  pointing at `unit-loop.md`, which carries the trailer format; trim an equal number of bytes
  from en-build's SKILL.md.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Test scenarios:**
  - *Happy path:* a Linear branch with `plan-provenance` trailers and **no** materialized file
    returns `linear_mode`.
  - *Happy path:* trailers recording `configured_store: linear` with the repo now on `local`
    return `config_drift` naming both values, without any file on disk.
  - *Edge case:* no trailer, materialized file present: falls back to the file (today's
    behaviour). No trailer, no file, local plan: legacy `local`, unchanged outcomes.
  - *Error / failure path:* two unit commits whose trailers disagree return
    `provenance_conflict`.
  - *Error / failure path (negative control):* with the trailer read removed from the script, the
    no-file case falls back to `not_applicable` and the test goes red.
- **Verification:** checkpoint tests green including the negative control; drift tests assert 9e
  and en-learn 11a name the trailer; en-build within budget.

### U4. Designs are never moved or stamped in linear mode

- **Goal:** A Linear promotion never touches a design doc, tracked or not, and no longer refuses
  because of one.
- **Requirements covered:** none (requirements_pending)
- **Dependencies:** U2
- **Files:** `skills/en-plan/references/linear-publish.md`, `skills/en-plan/SKILL.md`,
  `.gitignore`, `tests/lint/en-plan-linear-publish.test.sh`
- **Approach:** The tracked-source check and table cover the plan only. A design doc, tracked or
  untracked, is left untouched: no stamp, no status flip, no move. The parent's Verification
  Contract carries `related_design`, and the run report says the design stays open until the
  operator closes it. `.ensemble/archive-designs/` is no longer
  written, so its `.gitignore` entry and every reference to it go. en-plan's write-the-plan
  step says "the plan" rather than "the plan and its design".
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Ship scope:** in
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* drift test asserts a tracked design is untouched and does not refuse.
  - *Edge case:* an untracked design is untouched too (no `status:` or `related_plan:` edit), and
    the run report says it stays open.
  - *Error / failure path:* a tracked plan still refuses (the EN18 clause stays green).
  - *Integration:* `git check-ignore .ensemble/archive-designs/x` no longer matches, and no file
    under `skills/` names that directory.
- **Verification:** drift tests green; en-plan within budget.

### U5. Plan from a triaged issue: `/en-plan <IDENT>`

- **Goal:** Under `plan_store: linear`, an issue identifier is a valid request; the plan is
  authored from it and published onto that same issue as the parent.
- **Requirements covered:** none (requirements_pending)
- **Dependencies:** U2
- **Files:** `skills/en-plan/SKILL.md`, `skills/en-plan/references/linear-intake.md`,
  `skills/en-plan/references/linear-publish.md`, `tests/lint/en-plan-linear-intake.test.sh`
- **Approach:** New reference `linear-intake.md` owns both identifier entry points (this unit and
  U6). Resolution follows en-build's rule: the mode comes from `plan_store`, not the argument's
  shape, and an identifier under `local` refuses. `get_issue` the issue; refuse when its team is
  not `linear_team`, when it already has sub-issues, or when its state is started, completed or
  canceled. Quote its title and description into the plan's Context under
  `### Original request (<IDENT>)` as a markdown blockquote, every line prefixed `> `, so a
  report carrying its own `## ` headings (even `## Implementation units`) cannot open a plan
  section; `render` republishes it and nothing is lost. Author and
  review as normal, keeping the issue's title, description, team and state as fetched.
  **Immediately before publish**, `get_issue` it again and refuse, naming what changed, if any of
  the four differs or it now has sub-issues: the report was edited, the issue moved team, someone
  started it, or someone split it while the plan was under review. At publish, the idempotency protocol's first rule applies: `linear_issue:` is
  set to `<IDENT>` from the start, so publish updates that issue with `save_issue` (title,
  description, state Agent Ready) instead of creating a parent, and creates the sub-issues under
  it. Step 4 of en-plan gains one clause routing an identifier to the reference.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* drift test asserts an identifier under `linear` is fetched, quoted into
    Context, and published onto the same issue (no second parent).
  - *Edge case:* U1's `render` and `materialize` on a plan whose Context carries a quoted report
    with its own `- ` bullets and a `## Implementation units` line round-trip with the same unit
    set and section list (added to U1's fixtures here).
  - *Error / failure path:* drift test asserts refusal for an identifier under `local`, a
    different team, an issue with sub-issues, and a started or closed issue.
  - *Error / failure path:* drift test asserts the pre-publish re-fetch refuses when the issue's
    description, team or state changed after intake, or a sub-issue was added, before any write.
  - *Integration:* the step-4 clause names the reference and the byte budget holds.
- **Verification:** drift and script tests green; en-plan within budget.

### U6. Amend in place: `/en-plan --resume <IDENT>`

- **Goal:** A published plan can be revised, re-reviewed and updated in Linear from any machine,
  before a build starts.
- **Requirements covered:** none (requirements_pending)
- **Dependencies:** U2, U5
- **Files:** `skills/en-plan/SKILL.md`, `skills/en-plan/references/linear-intake.md`,
  `skills/en-plan/references/linear-publish.md`, `tests/lint/en-plan-linear-intake.test.sh`
- **Approach:** `--resume` with an identifier under `linear`: `get_issue` the parent; refuse
  unless its state is Agent Ready or earlier (unstarted or backlog type), naming the state, since
  a build may already be running on the reviewed version. Fetch the units, `materialize` into
  `docs/plans/active/<file>.md`, refusing **before any write** if any file with that `plan_id`
  already exists there, tracked or not (an unfinished earlier revision is not overwritten),
  and run the normal flow over it: revise, finalize loop, promotion with fresh hashes. Keep the
  intake read-back file. **Immediately before updating Linear**, fetch a fresh read-back and
  refuse if the parent's state has left the amendable set or if the fresh read-back differs from
  the intake one (`verify <intake-materialized> <fresh>` exits non-zero): a build started, or
  someone edited the plan, while it was under review. Then update in place: the parent and every
  surviving sub-issue via `save_issue` by id, new units created, units removed by the revision
  **cancelled** (no delete tool exists). U-IDs are never renumbered or reused: a new unit takes
  one above the highest U-ID among **all** sub-issues, canceled included. `verify` gates the
  archive as for a first publish, and skips canceled sub-issues per the read-back contract. Step 3 of en-plan gains one
  clause routing an identifier to the reference.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* drift test asserts the flow: state check, materialize, normal review, update in
    place, `verify` before archive.
  - *Edge case:* a unit removed in revision is cancelled, not deleted or renumbered, and the
    post-publish `verify` passes because canceled sub-issues are skipped; a new unit takes one
    above the highest U-ID including canceled ones.
  - *Error / failure path:* drift test asserts the pre-publish re-fetch: a parent moved to In
    Progress, or a unit edited in Linear, between intake and publish refuses with no write.
  - *Error / failure path:* drift test asserts refusal for a parent In Progress, In Review or
    Done, and for any existing local file with the same `plan_id`, tracked or untracked, with
    nothing written.
  - *Integration:* U1's `materialize` output for a published plan re-renders to an identical
    payload (idempotent round trip, added to U1's tests here).
- **Verification:** drift and script tests green; en-plan within budget.

### U7. Linear check in `/en-setup`

- **Goal:** Before the first publish, the operator learns whether the team, the four states,
  python3 and the GitHub integration mapping are in place.
- **Requirements covered:** none (requirements_pending)
- **Dependencies:** U1
- **Files:** `skills/en-setup/SKILL.md`, `skills/en-setup/references/setup-linear-check.md`,
  `skills/en-setup/references/templates/config-local-example.yaml`,
  `.ensemble/config.local.example.yaml`, `skills/en-plan/references/linear-publish.md`,
  `tests/lint/en-setup-linear-check.test.sh`
- **Approach:** Runs in State 3 and at the end of State 2 only when `plan_store` resolves to
  `linear`. Over MCP: `list_teams` confirms `linear_team` exists (🔴 if not);
  `list_issue_statuses` for that team confirms Agent Ready, In Progress, In Review and Done by
  name (🔴 naming any missing or duplicated). Locally: `command -v python3` (🔴, since the
  script needs it). The GitHub mapping cannot be read over MCP, so the check states the required
  mapping (PR open to In Review or no automation, merge to Done; any PR-open mapping to an
  earlier state would move the parent backwards from In Review), asks the operator to confirm it
  in team settings, and on yes writes `linear_github_confirmed: true` to
  `.ensemble/config.local.yaml` (🟡 until then). `linear-publish.md` warns, without blocking,
  when the key is unset. en-setup's SKILL.md has 52 bytes of headroom: its State 3 list gains one
  bullet pointing at the reference, paid for by shortening an existing bullet.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Ship scope:** in
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* drift test asserts the check names all four states by name, the team lookup,
    python3 and the GitHub confirmation key.
  - *Edge case:* under `plan_store: local` the check does not run and makes no MCP call.
  - *Error / failure path:* drift test asserts a missing state is 🔴 naming it, and an unset
    `linear_github_confirmed` is 🟡 with the required mapping printed.
  - *Integration:* both config templates document `linear_github_confirmed`; publish warns when
    it is unset; en-setup within budget.
- **Verification:** drift tests green; skill-size green with en-setup at or under its current
  size.

## Decisions, assumptions & risks

- **Decision:** reverse D118's "no script" for the transforms only (D119). The MCP-only choice was
  about credentials and HTTP; a script that never calls Linear keeps both properties and makes
  the transforms testable, which EN18 recorded as its headline risk.
- **Decision:** plan-level sections live in the parent description, not a Linear Document, so one
  `get_issue` returns the whole plan and one object is published, verified and amended.
- **Decision:** every unit commit carries the provenance trailer, not only the post-build commit,
  so a build that stopped early still records it.
- **Decision:** amend only before a build (Agent Ready or earlier).
- **Decision:** the GitHub mapping is confirmed by the operator and recorded, because it cannot be
  read over MCP.
- **Alternative:** a linked Linear Document for plan-level sections. Rejected: a second object to
  keep in sync for a size limit nobody has hit.
- **Assumption:** Linear's description size limit accommodates a full plan's plan-level sections.
  Unmeasured; `verify` catches truncation at publish. Falsified by the end-to-end run.
- **Assumption:** `save_issue` with an existing id updates title, description and state in place.
  The MCP server exposes one tool for create and update; confirmed or refuted by the end-to-end
  run.
- **Assumption:** Linear rewrites `- ` to `* ` inside the Verification Contract's fenced block as
  it does elsewhere. Unmeasured; `materialize` normalizes both, so the assumption only matters if
  Linear rewrites something else.
- **Risk:** python3 becomes a hard requirement for Linear mode. **Mitigation:** U7 checks it, and
  local mode does not need it.
- **Risk:** the EN19 fixtures are synthetic apart from the measured marker rewrite.
  **Mitigation:** the end-to-end run captures a real read-back to replace them.

## Tracked debt

None resolved or opened.

## Iteration log

> - 2026-09-22 (initial): plan v0 from the overall EN18 review in the operator's session. Round 1
>   settled issue intake (quote into Context), amend window (before a build), trailer placement
>   (every unit commit) and designs (left alone). Round 2 settled plan-level sections (parent
>   description) and the GitHub mapping (instruct and confirm).
> - 2026-09-22: Peer review iteration 1 (codex, cross-agent, effort high, 80s): `revise`, 5 P1,
>   all applied. U4 no longer closes out untracked designs, which contradicted its own goal.
>   Canceled sub-issues are skipped by `materialize` and `verify`, so an amend that removes a unit
>   can pass read-back. Amend and issue intake both re-fetch immediately before writing and refuse
>   on a change, closing the window where a build starts or the issue is edited mid-review.
>   `verify` skips the iteration log by the same rule as `--full`.
> - 2026-09-22: Peer review iteration 2 (80s): `revise`, 1 P0 and 4 P1. Applied three: resume
>   refuses on any existing local file for the plan_id, intake re-checks for sub-issues before
>   the first write, and the original request is blockquoted so its headings cannot open a plan
>   section. Disagreed with gating U5 and U6: building them writes nothing to Linear.
