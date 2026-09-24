---
type: plan
plan_type: feature
plan_id: EN20
title: Brainstorm from a Linear issue, and hand the design to /en-plan
status: in_progress
location: active
created: 2026-09-24
shipped:
deepened:
covers_requirements: []
requirements_pending: true
related_design:
peer_review_verdict: revise
peer_review_iterations: 2
peer_review_last_run: 2026-09-24
peer_review_plan_hash: 8620e4c8655aa9562c9b12980c6d7e9eae690269abaca8ec3e67644ff7a4c0d4
peer_review_resolutions:
  - finding_id: "1-1"
    iteration: 1
    severity: P1
    title: Gate the Linear comment write
    status: disagreed
    rationale: Gated covers state changed by running the unit at build time. Building U1 edits a reference, a template and a test and writes nothing to Linear; the comment is posted later, when an operator runs /en-brainstorm. Same ruling as EN19 findings 2-4 and 2-5.
    location: U1
  - finding_id: "1-2"
    iteration: 1
    severity: P1
    title: Specify concrete feature scenarios
    status: applied
    location: U1, U2, Test seams
  - finding_id: "2-1"
    iteration: 2
    severity: P1
    title: Keep topic matching from relinking another issue's design
    status: applied
    location: U1
depth: lightweight
data_scale: small
---

# EN20: Brainstorm from a Linear issue, and hand the design to /en-plan

## Context

EN19 let `/en-plan ENG-123` take a triaged Linear issue as its request and publish the plan onto
that issue. That serves an issue that is ready to plan. It does not serve the earlier stage the
EN18 design's Problem statement also names: an issue someone opened with a half-formed idea, a
problem to investigate, or a feature to explore. Today that issue has to be copied into a
`/en-brainstorm` conversation by hand, and the resulting design has no link back to it, so
`/en-plan ENG-123` re-asks what the brainstorm already settled.

The operator settled the shape in conversation (not re-asked here): under `plan_store: linear`,
`/en-brainstorm EMB-123` takes the issue as its starting request, writes the design doc to
`docs/designs/` exactly as today with `linear_issue: EMB-123` in its frontmatter, and comments on
the issue naming the design and its recommendation. The issue's description and state are never
touched. `/en-plan EMB-123` then finds that design by `linear_issue:` and consumes it. One issue
carries the whole path: idea, design, plan, build, merge.

## Requirements covered

None: `docs/foundation.md` carries no R-IDs (`requirements_pending: true`).

## Out of scope for this plan

- Mirroring the design into a Linear Document. The operator chose a comment: one source of truth.
- Committing the design. `/en-brainstorm` never commits (its hard gate), and that does not change.
- Closing out an issue-linked design after its plan publishes. In `linear` mode `/en-plan` leaves
  designs untouched (D119); this plan keeps that rule.
- A behavioural harness for the MCP calls (TD20 tracks it for every Linear flow).

## Approach (high-level)

Both skills gain one Linear entry point each, in a reference, with a one-clause route from
SKILL.md. The mode comes from `plan_store`, never from the argument's shape, as in `/en-build`
and `/en-plan`.

**`/en-brainstorm EMB-123`.** Admit the issue before any Q&A with the same rules `/en-plan`'s
issue intake applies (team is `linear_team`; no sub-issues; not started, completed or canceled),
so every issue brainstorming accepts is one planning will accept. The issue's title and
description, blockquoted, are the starting request. Resume matches first on `linear_issue:` in an
open design's frontmatter, then on topic, and still confirms before resuming. The write step
adds `linear_issue: EMB-123` to the frontmatter. After each write (first write or a resumed
revision) post one `save_comment` on the issue naming the design path and its current
recommendation in two or three lines, and the next step (`/en-plan EMB-123`).

**`/en-plan EMB-123`.** After admission, look for a design in `docs/designs/` whose frontmatter
carries `linear_issue: EMB-123` and consume it as settled input (`related_design:`), exactly as
`plan-intake.md` consumes a matching design today. The issue's report is still quoted into
Context: the report says what was asked, the design what was decided. When the issue's comments
name a brainstorm design that is not in this checkout (brainstorm never commits, so it may live
on another machine), warn and ask whether to proceed without it. When the request is
insufficient to plan from, the brainstorm offer names `/en-brainstorm EMB-123` rather than a bare
`/en-brainstorm`.

## Test seams

1. **The `ensemble-linear-plan` CLI** (exists): the one deterministic step, finding the design
   linked to an issue, becomes a subcommand tested against fixture designs, so an exact-match
   bug (`EMB-12` matching `EMB-123`, a case slip) is caught by a test rather than trusted to prose.
2. **Prose drift tests** in `tests/lint/` (exist): for the model-followed MCP steps (admission,
   the comment), which have no other observable seam. TD20 tracks a behavioural harness for all
   Linear flows.

## Implementation units

Each unit has a stable U-ID. Never renumbered after assignment.

### U1. `/en-brainstorm <IDENT>`: admit, source, link and comment

- **Goal:** Under `plan_store: linear`, a Linear issue identifier is a valid `/en-brainstorm`
  request; the design it produces carries `linear_issue:` and is announced on the issue.
- **Requirements covered:** none (requirements_pending)
- **Dependencies:** none
- **Interfaces:**
  - *Produces:* design-doc frontmatter key `linear_issue: <IDENT>` (the identifier as given,
    upper-case), and an issue comment whose first line is `Design: <repo-relative path>`.
- **Files:** `skills/en-brainstorm/SKILL.md`,
  `skills/en-brainstorm/references/linear-intake.md`,
  `skills/en-brainstorm/references/templates/design-doc-template.md`, `docs/foundation.md`,
  `tests/lint/en-brainstorm-linear-intake.test.sh`
- **Approach:** New reference `linear-intake.md` in en-brainstorm, read when the request is an
  identifier (`^[A-Z][A-Z0-9]*-[0-9]+$`). It resolves `plan_store` with
  `$SKILL_DIR/scripts/ensemble-config-get plan_store --allowed local,linear --default local
  --strict` (en-brainstorm already carries the script) and refuses an identifier under `local`.
  Admission before any Q&A: `get_issue`, then `list_issues` with its `parentId`; refuse, naming
  the reason, when the team is not `linear_team`, it has sub-issues, or its state is started,
  completed or canceled. The issue's title and description, blockquoted with every line
  prefixed `> `, are the request the frontier rounds start from. Resume: an open design whose
  frontmatter has `linear_issue: <IDENT>` is the first candidate, then the existing topic match,
  which **excludes any design already linked to a different issue**: resuming one would overwrite
  its `linear_issue:` and strand the issue it came from. A topic match with no `linear_issue:` may
  be adopted, and gains the key. Confirmation before resuming is unchanged. Write: `linear_issue: <IDENT>` in the frontmatter.
  After each write, one `save_comment` on the issue: `Design: <path>` on its first line, the
  recommendation in two or three lines, then `Next: /en-plan <IDENT>`; never edit the
  description or state, and say why (en-plan quotes the description and its re-check refuses a
  changed one; plan intake refuses a started issue). A failed comment warns and does not fail
  the run: the design is written. SKILL.md step 3 gains one clause routing an identifier to the
  reference, and step 15 one clause for the key and the comment. The template documents
  `linear_issue:` as an optional key. Record D120 in the foundation: the brainstorm-to-plan link
  is a design frontmatter key plus an issue comment, not a Linear Document, and the issue's
  description and state belong to the reporter and to `/en-plan`.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Ship scope:** in
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* `EMB-7`, team Emble (`linear_team: EMB`), state Backlog, no sub-issues,
    description "Exports time out on large workspaces". Expected: admitted; the frontier starts
    from `> Exports time out on large workspaces`; the design written to
    `docs/designs/2026-09-24-export-timeouts-design.md` carries `linear_issue: EMB-7`; one comment
    on EMB-7 whose first line is `Design: docs/designs/2026-09-24-export-timeouts-design.md` and
    whose last is `Next: /en-plan EMB-7`. Asserted in the drift test as the reference's worked
    example, so the expected shapes are pinned, not paraphrased.
  - *Edge case:* resume looks for `linear_issue: <IDENT>` before the topic match, and still
    confirms before resuming.
  - *Edge case:* EMB-7 and EMB-9 on the same topic. After brainstorming EMB-7, running
    `/en-brainstorm EMB-9` does not offer EMB-7's design for resume, so EMB-7's design keeps
    `linear_issue: EMB-7` and EMB-9 gets its own. The drift test pins the exclusion clause.
  - *Error / failure path:* refusal under `plan_store: local`, for another team, for an issue
    with sub-issues, and for a started, completed or canceled issue, each before any Q&A.
  - *Error / failure path:* the reference forbids editing the description or state, and a failed
    comment warns without failing the run.
  - *Integration:* the template documents `linear_issue:`; `bin/ensemble-lint --scope
    docs/designs` accepts a design carrying it; D120 exists in the foundation; en-brainstorm
    stays within the byte budget and its step anchors are unchanged.
- **Verification:** new drift test green with a negative control (removing the admission
  paragraph turns it red); `en-brainstorm-step-anchors`, `skill-size`, `skill-payload` and
  `design-lifecycle` tests green.

### U2. `/en-plan <IDENT>` consumes the linked design

- **Goal:** Planning from an issue that was brainstormed consumes that design as settled input,
  and points an unready issue at `/en-brainstorm <IDENT>`.
- **Requirements covered:** none (requirements_pending)
- **Dependencies:** U1
- **Files:** `skills/en-plan/references/linear-intake.md`,
  `skills/en-plan/scripts/ensemble-linear-plan`, `skills/en-build/scripts/ensemble-linear-plan`,
  `tests/linear-plan/linear-plan.test.sh`, `tests/lint/en-plan-linear-intake.test.sh`
- **Interfaces:**
  - *Consumes:* the `linear_issue: <IDENT>` design frontmatter key from U1.
  - *Produces:* `ensemble-linear-plan find-design <IDENT> [--dir docs/designs]`: prints each
    design whose frontmatter `linear_issue:` equals `<IDENT>` exactly (case-sensitive, whole
    value), one repo-relative path per line, sorted; exit 0 with one or more, 1 with none, 2 on
    usage, 3 when `<IDENT>` is not `^[A-Z][A-Z0-9]*-[0-9]+$`.
- **Approach:** In `## An issue as the request`, after admission and before the Context quote:
  run `bash "$SKILL_DIR/scripts/ensemble-linear-plan" find-design <IDENT>` to find the design
  whose frontmatter has `linear_issue: <IDENT>`. The frontmatter is read only between the opening
  and closing `---`, so a body line that happens to say `linear_issue:` never matches. One match:
  consume it per `plan-intake.md` (its decisions are settled; record `related_design:`; only
  what it left open reaches the planning questions), and still quote the report into Context.
  Two or more: list them and ask which, never guess. None, but a comment on the issue
  (`list_comments`) starts `Design: <path>` and that path is not in this checkout: warn that the
  design lives elsewhere (brainstorm never commits it) and ask whether to proceed without it.
  When the context-sufficiency check finds the issue too thin to plan from, the brainstorm offer
  names `/en-brainstorm <IDENT>`. No change to en-plan's SKILL.md (285 bytes of headroom): the
  step that routes an identifier here already exists.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Ship scope:** in
- **Execution note:** pragmatic
- **Test scenarios:**
  - *Happy path:* fixture designs in a temp dir: `a.md` with `linear_issue: EMB-7`, `b.md` with
    `linear_issue: EMB-70`, `c.md` with `linear_issue: emb-7`, `d.md` whose body (not frontmatter)
    says `linear_issue: EMB-7`. `find-design EMB-7` prints only `a.md` and exits 0.
  - *Happy path:* drift test asserts the reference runs `find-design` after admission and before
    the Context quote, consumes the one match as `related_design`, and still quotes the report.
  - *Edge case:* two designs both carrying `linear_issue: EMB-7` print two lines, exit 0, and the
    reference says to list them and ask rather than pick.
  - *Edge case:* no match exits 1; `find-design emb-7` and `find-design EMB` exit 3.
  - *Error / failure path:* a comment naming a design missing from this checkout warns and asks.
  - *Integration:* the insufficiency offer names `/en-brainstorm <IDENT>`; the existing clauses
    (admission, re-check before publish, publish onto the issue) and their line order still hold.
- **Verification:** `tests/linear-plan` green with a negative control (a prefix match instead of
  an exact one turns the `EMB-70` case red); drift test green; parity green with the script in
  both carriers; `en-plan-context-sufficiency` and `en-plan-brainstorm-nudge` tests green; en-plan
  SKILL.md unchanged.

## Decisions, assumptions & risks

- **Decision:** a design frontmatter key plus an issue comment is the whole link (D120). The
  design stays in the repo as the durable record; the issue says where to find it.
- **Decision:** brainstorm admits exactly the issues planning admits, so the chain cannot
  dead-end on a started issue or one already planned.
- **Decision:** one comment per design write, so the issue's history shows how the thinking moved.
- **Alternative:** mirror the design into a Linear Document. Rejected by the operator: two copies
  drift the moment either is edited.
- **Assumption:** `save_comment` and `list_comments` on the Linear MCP server post and read issue
  comments as named. Confirmed by name in this session's tool list; the end-to-end run confirms
  behaviour.
- **Risk:** the design is uncommitted, so `/en-plan EMB-123` in another checkout cannot find it.
  **Mitigation:** U2 warns when the issue's comment names a design this checkout lacks.
- **Risk:** an issue-linked design stays `open` after its plan publishes, since `linear` mode never
  closes designs out, so it remains in brainstorm's topic-match resume pool. **Mitigation:** resume
  already confirms before continuing, and admission refuses the planned issue itself.

## Tracked debt

None resolved or opened.

## Iteration log

> - 2026-09-24 (initial): plan v0 from the operator's conversation. Round 1 settled started issues
>   (refuse), reruns (resume by `linear_issue:`), comment timing (each write) and the plan's input
>   (report and design both).
> - 2026-09-24: Peer review iteration 1 (codex, effort high, 47s; run despite
>   `skip_peer_on_lightweight` because the flow writes to Linear): `revise`, 2 P1. Applied 1-2: the
>   design lookup moves into `ensemble-linear-plan find-design`, tested against fixture designs, and
>   both units carry worked examples. Disagreed with 1-1 (gate U1): building it writes nothing to
>   Linear.
> - 2026-09-24: Peer review iteration 2 (31s): `revise`, 1 P1, applied: topic-match resume excludes
>   designs linked to a different issue, so a second issue on the same topic cannot take over the
>   first issue's design.
