---
title: Plan finalization loop — spec
status: draft
owner: mano
related:
  - skills/en-plan/SKILL.md
  - skills/en-build/SKILL.md
  - skills/en-cross-review/SKILL.md
  - references/outside-voice.md
  - references/finding-schema.md
---

# Plan finalization loop

## Problem

`/en-plan` ends after the first peer-review pass. When the verdict is `revise`,
findings are applied (recorded in the iteration log) but three follow-through
steps are left to the human:

1. **Re-review** the revised plan to clear the `revise` verdict.
2. **Flip `status: draft` → `open`** once cleared.
3. **Commit the plan file** so `/en-build` has a tracked artifact.

The human applies the findings, then forgets the bookkeeping. `/en-build`
correctly refuses (`status: draft`, untracked file) but only offers a 3-option
recovery menu — no one-command path back to a buildable state.

This spec covers improvements **#1, #2, #3** from the workflow analysis:

- **#1** — re-review loop owned by `/en-plan`.
- **#2** — auto-commit the plan once finalized.
- **#3** — `/en-build` pre-flight offers an actionable recovery, not just refusal.

Improvement **#4** (scope-aware slicing for deep plans) is out of scope — handled
in a follow-up spec.

---

## Improvement #1 — Re-review loop in `/en-plan`

### Behavior

After the **first** peer pass returns a verdict:

| Verdict | New behavior |
|---|---|
| `approve` | Flip `status: draft` → `open` automatically. (Today: requires manual flip.) |
| `revise` | Apply / defer / disagree per `references/severity.md` as today; **then re-invoke peer** with the revised plan. Loop. |
| `reject` | Pause and surface to user (unchanged). |

The loop terminates when one of:

- Verdict becomes `approve` → flip to `open`.
- `max_finalize_iterations` reached → leave `status: draft`, surface latest
  findings, ask user to take over. Default is **depth-aware**:

  | Plan depth | Max iterations | Total peer passes (initial + re-reviews) |
  |---|---|---|
  | Lightweight | 1 | 2 |
  | Standard | 2 | 3 |
  | Deep | 2 | 3 |

  Lightweight plans (1–3 units) are small enough that one re-review is
  usually decisive; further loops are mostly noise. Standard and Deep get one
  more pass to handle structural findings that need a second look.
- User declines a re-review pass mid-loop (`--no-reloop` flag, or interactive
  prompt between iterations).

### Iteration prompt context

Each re-review pass MUST include in the peer prompt:

- **The full revised plan** (not a diff). The "previous review context"
  section below provides the framing the peer needs to avoid re-litigating
  settled ground; a diff would lose surrounding context the peer needs to
  judge whether a fix actually resolves the concern.
- A `## Previous review context` section listing:
  - Findings **applied** this iteration (so the peer can verify the fix landed).
  - Findings **deferred** (with rationale; peer should not re-flag).
  - Findings **disagreed-with** (with rationale; peer should not re-flag unless
    they have new evidence).

Framing line: *"This is iteration N of finalization. Verify previously-applied
findings actually resolve the concern, and surface only **new** issues or
unresolved-from-previous."*

This prevents the peer from re-litigating settled ground and keeps token cost
roughly flat across iterations.

### Frontmatter changes

Add to plan frontmatter (additive — doesn't break existing plans):

```yaml
peer_review_verdict: approve | revise | reject | null
peer_review_iterations: <integer>          # 0, 1, 2, ...
peer_review_last_run: <ISO 8601 date>
peer_review_plan_hash: <sha256-hex>        # see Improvement #4 spec; covers immutable plan-input fields only
peer_review_resolutions:                   # machine-readable resolution log (see below)
  - finding_id: <stable id assigned by peer or by /en-plan>
    iteration: <N>
    severity: P0 | P1 | P2 | P3
    title: <short title from peer>
    status: applied | deferred | disagreed | superseded
    rationale: <one-line reason; required for deferred / disagreed / superseded>
    location: <file:line or section name from peer>
```

The existing iteration log section in the plan body remains the human-readable
narrative; the frontmatter fields are the machine-readable state for
`/en-build`'s pre-flight and `/en-plan`'s re-review-loop "previous review
context" assembly. **Pre-flight decisions (and the recovery path in
Improvement #3) read `peer_review_resolutions` and `peer_review_verdict`
directly — they never parse the iteration-log prose.**

`finding_id` is assigned at the time the peer surfaces the finding. If the
peer doesn't return an id, `/en-plan` mints one as
`<iteration>-<index>` (e.g. `1-3` = third finding from iteration 1) and
records it in both the resolution log and the iteration narrative for
traceability.

`status: superseded` covers the edge case where a later iteration's fix
makes an earlier finding moot — record it explicitly rather than dropping
the entry.

### Failure cases

| Case | Behavior |
|---|---|
| Peer subprocess times out on iteration N | Surface; leave `status: draft`; no re-loop |
| Peer returns malformed JSON (after retry) | Surface; leave `status: draft` |
| Max iterations hit, still `revise` | Surface latest findings; ask user "accept as-is and flip to `open`, or stay in `draft`?" |
| User rejects a finding the peer keeps re-raising | Bump `peer_review_iterations`; if it's the same finding twice, suppress on 3rd peer pass via "do not re-flag" list |

### Flags

| Flag | Effect |
|---|---|
| `--no-reloop` | Run only the initial peer pass; never re-review. (Today's behavior.) |
| `--max-iterations <N>` | Override the depth-aware default. |

---

## Improvement #2 — Commit-on-finalize

### Behavior

Once `/en-plan` flips `status` to `open` (via #1's loop or `--no-peer`), the skill:

1. Stages the plan file: `git add docs/plans/active/<plan-file>.md`.
2. Commits with a conventional message:
   ```
   docs(plan): <plan_id> <slug> (<N> units)

   Plan finalized after <iterations> peer-review iteration(s).
   Verdict: approve. Generated by /en-plan.
   ```
3. Does **not** push, does **not** open a PR.

The commit lands on whichever branch the user is currently on.

### Branching policy

- **On default branch (main / master / develop)** → commit there. Plans become
  discoverable in main-line history. `/en-build` later branches off and
  inherits the plan file.
- **On a feature branch** → commit there. `/en-build` will reuse the same
  branch (matches today's en-build step 5).
- **On detached HEAD or unusual state** → skip auto-commit; surface and ask.

### Working-tree safety

Before committing:

- If `git diff --cached` has unrelated staged changes → **abort auto-commit**;
  surface: *"Uncommitted unrelated changes are staged. Stage and commit the
  plan manually, then re-run."*
- If working tree has unrelated unstaged changes to files **other than** the
  plan file → proceed (we only stage the plan file by name; `git add -A` is
  never used).
- If the plan file path itself has uncommitted unstaged changes from a prior
  `/en-plan` invocation → these are the ones we want to commit. Proceed.

### Flags

| Flag | Effect |
|---|---|
| `--no-commit` | Finalize (status: open) but do not commit. (Today's behavior.) |
| `--commit-branch <name>` | Create / switch to `<name>` before committing the plan. |

### Open question

Should `/en-plan` ever create a `plan/<plan_id>-<slug>` branch? Argument for:
keeps main-line clean if plans churn. Argument against: extra branch lifecycle
to manage, and `/en-build` already creates a feature branch later. **Default
recommendation: commit to current branch; `--commit-branch` is opt-in.** Mark
this as a follow-up if the team wants the cleaner separation.

---

## Improvement #3 — `/en-build` pre-flight recovery

### Today

`/en-build` step 4 reads the plan and refuses on `status: draft`. The user
gets a 3-option menu (re-review / narrow slice / override) as conversational
guidance.

### New behavior

Pre-flight reads the structured frontmatter (`peer_review_verdict`,
`peer_review_resolutions`) — never the iteration-log prose — and applies
the matrix below.

For plans **without the new frontmatter fields** (drafted before this spec
lands), pre-flight runs **legacy inference** first:

| Legacy signal | Inferred state |
|---|---|
| `status: draft` AND a parseable iteration-log section exists with at least one entry marked applied/deferred/disagreed | Treat as `peer_review_verdict: revise` + reconstructed `peer_review_resolutions` (best-effort; flagged `inferred: true`) |
| `status: draft` AND no iteration log, AND no peer-review section anywhere | Treat as `peer_review_verdict: null` (peer review never ran) |
| `status: open` AND no peer-review fields | Treat as `peer_review_verdict: null` AND `--no-peer` was used (legacy plan, accept) |
| `status: open` AND iteration log shows a final `verdict: approve` | Treat as `peer_review_verdict: approve` |
| Any other ambiguous combination | Surface explicitly: *"Plan has no machine-readable peer-review state and the iteration log is ambiguous. Please re-run `/en-plan --resume` to refresh the frontmatter, or set `peer_review_verdict:` manually."* Refuse to proceed. |

Inferred plans get a one-line notice on the recovery prompt:

> NOTE: this plan's peer-review state was inferred from the iteration log
> (no `peer_review_resolutions:` field). Continuing will rebuild the
> structured field from the inference. (y / n / details)

After inference (or for new plans with the field present), apply this
matrix:

> Plan is in draft. Findings from the last peer review (verdict: revise) appear
> to be applied (resolutions: 8 applied, 0 deferred, 0 disagreed). I can
> finalize now: re-run the peer pass, flip to `open` on approve, and commit
> the plan. Then proceed with `/en-build`. (y / n / details)

- **y** → invoke the same finalize flow described in Improvement #1
  (re-review loop with iteration prompt context). On `approve`, auto-commit
  per #2, then continue with the existing build flow from step 5.
- **n** → refuse with current behavior (show the 3-option menu).
- **details** → print the resolution log, frontmatter state, and uncommitted
  status; re-prompt.

### Sub-state matrix

Read `peer_review_verdict` and the *count of unresolved findings* from
`peer_review_resolutions` (a finding is "unresolved" when its `status` is
absent or anything other than `applied | deferred | disagreed | superseded`).

| status | verdict | unresolved findings | git tracked | Pre-flight action |
|---|---|---|---|---|
| `open` | `approve` | 0 | yes | Proceed (today's behavior) |
| `open` | `approve` | 0 | **no** | Offer auto-commit, then proceed |
| `draft` | `revise` | 0 | yes or no | **Offer finalize-and-build (the new flow)** |
| `draft` | `revise` | > 0 | any | Refuse; user must resolve remaining findings first (list them) |
| `open` | `null` | n/a | yes | Proceed (`--no-peer` was used; no peer expected) |
| `open` | `null` | n/a | **no** | Offer auto-commit, then proceed |
| `draft` | `null` | n/a | any | Refuse; peer review never ran |
| `draft` | `reject` | any | any | Refuse; user must take over |
| `completed` / `abandoned` | any | any | any | Refuse (today's behavior) |
| `draft` | inferred `revise` | inferred 0 | yes or no | Offer finalize-and-build with legacy notice (see legacy inference above) |
| `draft` | inferred `null` | n/a | any | Refuse; surface that no peer review ran |

### Flags

| Flag | Effect |
|---|---|
| `--no-finalize` | Disable the recovery offer; refuse on draft as today |
| `--finalize-only` | Run finalize flow but don't proceed to build (useful for scripting) |

---

## Decisions

1. **Iteration cap is depth-aware.** Lightweight=1, Standard=2, Deep=2
   (folded into Improvement #1's behavior table).
2. **Re-review scope is the full plan**, not a diff. The "previous review
   context" framing handles re-litigation concerns; the peer needs surrounding
   context to judge fixes. Revisit only if token cost becomes a real issue.
3. **`peer_review_verdict: null` + `status: open`** is a valid state
   (`--no-peer` was used). Pre-flight proceeds without a finalize loop.
   Reflected in the sub-state matrix.
4. **Hand-edit drift is partially handled via `peer_review_plan_hash`** —
   covered structurally in the scope-aware-slicing spec's plan-hash check
   at phase boundaries. The hash covers immutable plan-input fields only
   (per-unit goal/files/approach/risk/category/gated/Depends, plan-level
   depth/data_scale); it excludes the iteration log, per-unit `status`, and
   `peer_review_resolutions` (fields `/en-plan` and `/en-build` legitimately
   update). `/en-plan` writes the hash at finalize; `/en-build` re-validates
   at phase boundaries.
5. **Pre-flight reads structured frontmatter, not iteration-log prose.**
   `peer_review_resolutions` is the machine-readable resolution log;
   `peer_review_verdict` is the machine-readable verdict. Pre-flight never
   parses the human-readable iteration log to make decisions. The
   iteration log remains the human-readable narrative and is kept in sync
   by `/en-plan` (one-way: structured fields drive the prose, not the
   reverse).
6. **Legacy plans get explicit inference rules.** Plans drafted before
   this spec lands have neither `peer_review_resolutions` nor the
   verdict field. Pre-flight applies a defined inference table (see
   Improvement #3 / "legacy inference"); ambiguous cases refuse rather
   than guess, with a clear instruction to re-run `/en-plan --resume` to
   refresh the frontmatter.

---

## Implementation outline (for follow-up plan)

Once this spec is approved, the implementation breaks into roughly:

- **U1** — Add re-review loop to `en-plan` step 13 (`references/outside-voice.md`
  iteration prompt section gets a new "Previous review context" template).
- **U2** — Add `peer_review_*` frontmatter fields to plan template,
  including the structured `peer_review_resolutions` schema and
  `peer_review_plan_hash`.
- **U3** — Resolution-log writer: as findings get applied/deferred/
  disagreed, `/en-plan` writes structured entries to
  `peer_review_resolutions` (in addition to the human-readable iteration
  log) with stable `finding_id`s.
- **U4** — Auto-flip `status: draft → open` on `approve` (replaces today's
  manual flip in step 12); compute and write `peer_review_plan_hash`
  at finalize.
- **U5** — Auto-commit the plan file (new step 15.5 between hand-off-prep
  and the suggestion to run `/en-build`).
- **U6** — Update `en-build` step 4 with the sub-state matrix + recovery
  prompt; pre-flight reads structured fields only.
- **U7** — Legacy inference handler: for plans without the new fields,
  apply the legacy inference table; surface notice; reconstruct
  `peer_review_resolutions` best-effort.
- **U8** — Tests in `tests/en-plan/` and `tests/en-build/` for each
  sub-state (new-field path AND legacy-inference path).
- **U9** — Update `docs/workflow-and-catalog.md` to document the new
  lifecycle including the structured resolution schema.

Total roughly Standard depth (9 units, multi-file).
