---
name: en-plan
description: "Turn a feature, refactor, or bug fix into a plan with stable U-IDs: reads the foundation, runs research agents, breaks work into units with files, tests and risk, then cross-agent peer review. Trigger phrases: 'plan this', 'plan a feature', 'before I build', 'plan <id>'."
---


# `/en-plan`

> **Running a bundled script.** Anchor every call to this skill's own directory: `SKILL_DIR="<absolute path of the directory containing this SKILL.md>"; bash "$SKILL_DIR/scripts/<name>"`. The trailing `;` is load-bearing. See `references/script-invocation.md`.


> **Dispatching a bundled agent.** This skill carries its agents in `agents/`. Dispatch by name as usual; when the name is not registered (a lone skill directory), resolve it from the bundled definition per `references/agent-dispatch.md`.


Concrete implementation plan with stable U-IDs and Outside Voice peer review. Hands off to `/en-build`.

> **Priority principle (D39): performance > speed ≥ cost.** Optimize first for plan quality, then speed, then token cost. Research depth, peer-review iterations and plan rigor earn their cost when they lift build quality; keep them self-gating so lightweight work stays fast.

> **Hard gate.** Plan only — no code, no commits, no PR. Output is a markdown plan file plus the peer-review verdict.

> **Peer contract.** Severity, confidence, autofix class and the `peer_decision` object are defined once in `references/peer-contract.md`, byte-identical across every skill that exchanges findings. What this skill does with a finding is its own policy.

## Process

1. **Detect host.** Source `references/host-detect.md`. Resolve `PEER_CMD`, `PEER_MODE`.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, skip the Outside Voice pass.
3. **Resume or create.**
   - **`--resume <plan-path>`** (explicit) — load the named plan, preserve its `plan_id`, `plan_type`, `created` and `generator`, and run the rest of the flow over it. This is how a `/en-sweep` draft becomes a peer-reviewed plan. Status stays `draft` until the status-flip step.
   - **`--from-legacy <path>`** (explicit) — mint a *new* plan from an archived legacy plan, which is never modified or moved. **Read `references/plan-from-legacy.md` when this flag is passed**; it owns the confirmation, the `migrated_from:` frontmatter and the legacy README back-reference.
   - **Auto-resume** (heuristic) — a plan in `docs/plans/active/` matching the request by title or `related_design` is offered as a resume rather than a new plan.
   - **Create** — no match; mint a new plan.

   Then `METRICS=$(bash "$SKILL_DIR/scripts/ensemble-run-metrics" start --skill en-plan --plan <plan_id>)` and record at the call points in `references/run-metrics.md`; it never blocks a run.
4. **Source the request.** Identify input, reading the candidates below in one message, since none depends on another:
   - Brainstorm design doc (`docs/designs/*.md`) — pre-explored, recommendation already on the table.
   - `docs/foundation.md` — pulling a requirement (R-ID) for the next slice of work.
   - Direct rough description from the user.
   - Bug report or tracked debt item (`Resolves: TD<N>`).

   **Read `references/plan-intake.md` here.** It owns the bounded foundation read (`docs/foundation.md` runs past 2,000 lines and is never read whole: section index first, then the sections you need), the rule that a matching design doc's decisions are already settled and must not be re-asked, the context-sufficiency check that offers `/en-brainstorm`, and the brainstorm soft-nudge. Proceeding is always allowed; neither is a hard gate.

   **Infer `plan_type`**: `feature` (net-new behavior), `improvement` (refactor, perf, DX, TD) or `bug`. Default `feature`, and confirm when the request is ambiguous.
5. **Right-size depth.**
   - Lightweight: 1–3 units, a file or two, no architecture changes.
   - Standard: 3–10 units, several files, possible new components.
   - Deep: 10+ units, structural change, multi-week work.
   Asked or inferred; default Standard.
6. **Phase 1 research (parallel).** Per `references/research-dispatch.md`:

   **`--research <path>`.** Per the *User-supplied research* rule there: an unreadable path stops the run before any dispatch; otherwise its first 200 lines stand in for `repo-research` and `web-research`, and neither is dispatched. `learnings-research` keeps its own rule. Report `research: user-supplied (<path>)`.
   - `repo-research` — patterns, conventions, file paths, prior art (Standard/Deep always).
   - `docs/learnings/index.md` — read inline first; it is an index and rarely more than a screen. Dispatch `learnings-research` only when it lists more than ~5 candidate entries on the topic, in the same parallel batch as `repo-research`.
   - `web-research` — only if a 3rd-party library not used elsewhere AND the library has known footguns AND the user hasn't said "skip web research". Recognising the library's name is not knowing its current state: a name from a fast-moving area is a reason to fire, not to skip.

   Do not wait for research before round 1. The architecture question rarely depends on it; ask it while the agents run, and let round 2 read their results.
7. **Resolve planning questions — frontier rounds.** Ask every question whose prerequisites are settled in **one numbered round**, each carrying your **recommended answer**, so a round is "confirm these, correct what I got wrong" rather than "answer these". A question that depends on another still open **in this round** waits for the next round; that dependency rule is what keeps batching from producing diluted answers. Skip anything the design doc already settled or research already answered; facts in the repo are looked up, never asked.

   Two rounds is the natural shape, because file boundaries and test strategy both partly depend on the architecture answer:

   - **Round 1:** which architecture do we land on (if multiple were on the table)?
   - **Round 2:** file boundaries, new files vs extending existing · test strategy, which **seams** do we test at, and unit / integration / end-to-end, test-first / characterization-first / pragmatic · dependencies, any new packages (**bias toward boring tech**: what the project already has, or none, beats a new one that is marginally nicer) · migrations, schema / data / config?

   **Seams are a plan-level decision, made once.** A seam is where a test observes the system: an HTTP boundary, a module's public function, a queue, a DB row. Decide the set here and let the units inherit it. Three rules, in order: **prefer a seam that already exists**; **take the highest seam that can still observe the behaviour**, since a test at the top survives refactors underneath it; **keep the set small**, because each seam couples the suite to the design. One is the ideal, and a plan needing four should say why. Deciding once is what stops each unit inventing its own mock boundary, which is how a suite ends up with three ways to fake the same dependency and no way to run the feature end to end.

   On **Lightweight**, ask one question per turn instead; a 1–3 unit plan does not need a tree. Stop when the frontier is empty or the design doc and research have answered it.
8. **Break into units (U-IDs).**
   - Each unit is one logical change, peer-reviewable and atomically committable. **The test for a boundary: could a reviewer reject this unit while approving its neighbour?** If not, they are one unit. Fold setup, config, scaffolding and doc steps into the unit whose deliverable needs them.
   - Prefer a unit that cuts a **narrow but complete path** through the layers it touches, so it is verifiable on its own, over a horizontal slice of one layer that leaves nothing demonstrable.
   - Tightly-coupled changes batch into one unit; independent concerns split. Auth, payments and migrations always get their own unit even when small.
   - **Never renumber after assignment** (per `references/stable-ids.md`).

   **Wide refactors are the exception to all of the above**, because one mechanical change whose blast radius fans across the codebase cannot be a single unit that lands green. Sequence it expand → migrate → contract per `references/wide-refactors.md`, which owns the batching and the risk split.

9. **Per-unit metadata.** `references/templates/plan-template.md` carries every field, its enum and the test-scenario categories; fill each unit from there. Four calls it cannot make for you:

   - **Risk** drives `/en-build`'s safety gates and unit order. Ask when unclear; default `medium` only when the unit is genuinely additive and reversible, and mark `destructive` for any DROP TABLE / DROP SCHEMA / mass DELETE / TRUNCATE / recursive removal of persistent data.
   - **Gated** defaults `false`, and is `true` ONLY when running the unit at build time changes production user state or external system state beyond what tests, lint and peer review can verify. Never for refactors, renames, copy changes, tests, docs, schema additions (`risk:` covers those) or new code behind an off flag. Over-gating trains users to autopilot through the prompts and erodes the gates that matter.
   - **Interfaces:** omit it entirely unless a later unit calls something this one creates. `/en-build` implements one unit at a time, so a name U3 invents that U7 calls has to match exactly and this block pins both to the same signature. Most units have no interface with a neighbour, and inventing one is noise.
   - **Requirements covered** takes R-IDs and AE-IDs from foundation; **Resolves** takes `TD<N>` from `docs/plans/tech-debt-tracker.md`, also appended to `resolves:` in frontmatter. Never delete a tracker entry: `/en-learn` marks it resolved at ship.

   **Ordering check.** **Irreversible work goes last**: no `risk: destructive` unit may be listed before a non-destructive one, because `/en-build` runs the plan's order and the point is that everything reversible is proven first (D108). The `unit.destructive-order` lint enforces it, and `/en-build` refuses a plan that arrives violating it. Fix it by moving the unit later, or by raising the other's risk if it is irreversible too.
10. **Resolve `plan_id_prefix`.** Read `plan_id_prefix:` from `docs/foundation.md` frontmatter. If absent (older project, retrofit, or `/en-foundation` not yet run), default to `FR`. Plans inherit the prefix in force at the time they are minted; the prefix is part of the plan's stable ID and never rewritten.
11. **Auto-increment plan number.** Scan `docs/plans/active/` and `docs/plans/completed/` for the highest number under the *current* `plan_id_prefix`. Legacy `FR` plans count toward `FR` only, so a new `EN` project starts at `EN01` even if `FR99` exists. Zero-pad to 2 digits, 3 once `99` is reached.

12. **Confidence check.** Name the sections you are least sure of and offer to deepen them with one more research dispatch, or to leave each as a stated assumption in `## Decisions, assumptions & risks`. Before the write, not after: `peer_review_plan_hash` covers Approach and Files, so a deepening edit made after promotion looks like tampering to `/en-build`.
13. **Pre-write plan-quality review.** Read `references/plan-prewrite.md` and run its five checks over the plan you are about to write: test-scenario completeness, decisions/assumptions/risks capture, the technical-design audit, name and signature consistency, and no placeholders. It also owns the warranted-file gate the write step calls. These catch the gaps peer review would otherwise spend an iteration on.
14. **Default-branch checkpoint.** Resolve the target branch BEFORE the plan file is written, so a resume run never hits "untracked working tree file would be overwritten" on `git checkout`.

    On any branch that is not the detected default (a feature branch, failed detection, detached HEAD), stay put and skip the checkpoint. On the default branch it **fires**: read `references/plan-default-branch-checkpoint.md`, which owns detection, the prompt, the four response handlers and the non-interactive `--branch-on-default` flag. Like `references/plan-from-legacy.md` it is gated, read only when its step's gate fires, never up front.

    Record the outcome as `default_branch_checkpoint: <auto_branched | no_commit_requested | committed_to_default_branch>` in the report.

15. **Write the plan.** One precondition first, and it can end the step.

    **Is a plan file warranted?** Offer the no-file path only when **all** of these hold: depth is **Lightweight**, the work is **one unit**, its `risk:` is **low**, nothing is `gated: true`, this is not a `--resume` or `--from-legacy` run, **no design doc was consumed**, and the user did not ask for a plan file. `references/plan-prewrite.md` owns the offer's wording and why the design-doc condition is not about size.

    If they take the no-file path, state the change concretely and stop: **no file, no U-IDs, no peer review, and `/en-build` is not available** for it, since `/en-build` consumes a plan file and there will not be one. Say that plainly rather than implying a handoff that cannot happen.

    **Never offer the skip** when the work touches a risk surface, authentication, payments, migrations or external contracts, however small it looks. Those are exactly the one-unit changes that earn a written plan and a peer pass.

    Then write to `docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md` (e.g. `EN03-improvement_dashboard-overview.md`) using `references/templates/plan-template.md`. Settle the unit boundaries and the hard calls in reasoning; write the file once. Substitute `plan_id` (`<PREFIX><NN>`), `plan_type` and `data_scale` (default `small`), and initialize `peer_review_iterations: 0` and `peer_review_resolutions: []`. Status starts `draft`; the finalize loop may flip it to `open`.
16. **Outside Voice review with finalize loop.**

    **The host authors; the peer only reviews.** The host writes every plan. The peer returns structured findings and nothing else, so it does not draft units, edit the plan file, run commands or commit (D30, in full in `references/outside-voice.md`). Do not confuse a peer with a **worker**: since D52 no Ensemble skill dispatches one, and `/en-plan` has no worker and never delegates authorship.

    Runs when `PEER_AVAILABLE=true` and `--no-peer` is not set. Auto-skipped under `skip_peer_below_lines` (plan < 50 lines) or `skip_peer_on_lightweight: true` at Lightweight depth; a skipped pass still reaches the status flip.
    - Build the prompt with `$SKILL_DIR/scripts/ensemble-build-peer-prompt --brief "$SKILL_DIR/references/peer-brief.md" --project-context "<one-line>" --goal "<one-line>" --artifact-file <plan-path> --peer-mode "$PEER_MODE"`; it substitutes the review-dimensions block and the single-agent fallback note. Do NOT assemble the prompt by reasoning: that is slow and drifts from the canonical template in `references/outside-voice.md`.
    - Set `ENSEMBLE_PEER_REVIEW=true`.
    - **Resolve the peer's model and effort, then invoke via `$SKILL_DIR/scripts/ensemble-peer-invoke`** with `ENSEMBLE_PEER_REVIEW=true`. Read `peer_model_<peer>` and `peer_effort_<peer>` for the peer's host through `$SKILL_DIR/scripts/ensemble-config-get` (effort `--allowed low,medium,high,xhigh`, `--legacy` the old names, D104); `eval "$($SKILL_DIR/scripts/ensemble-peer-flags --effort "${override:-inherit}" --peer-cmd "$PEER_CMD" --model-alias "$alias" --codex-model "$codex")"`; pass `$PEER_CMD`, `$PEER_FORMAT`, `$PEER_TURNS`, `$PEER_MODEL`, `$PEER_EFFORT`, the prompt file and `--peer-mode "$PEER_MODE"`. The helper owns timeout, failure classification, retry and fallback (D41); do not restate them. Surface the returned `peer_decision`'s `peer`/`reason` (`references/peer-contract.md`) in the run report, so a skipped or degraded peer never reads as normal.
    - Parse JSON per `references/finding-schema.md`. Mint `finding_id` as `<iteration>-<index>` for any finding the peer didn't supply one for.
    - Update frontmatter: `peer_review_verdict`, `peer_review_iterations` (+1), `peer_review_last_run` (ISO 8601 date).
    - **Re-review loop** (the finalize loop):
      `references/outside-voice.md` owns verdict handling and the previous-review-context section; below is en-plan's policy on top of it.
      - On `approve` → exit; go to the status flip. On `reject` → pause, surface, leave `status: draft`, no re-loop. A timeout or malformed JSON after one retry behaves the same way.
      - On `revise` → walk findings, apply / defer / disagree per `references/peer-brief.md`, each application a surgical edit to the plan file, never a rewrite of it. Record each in `peer_review_resolutions:` (entry schema in `references/templates/plan-template.md`) and keep the narrative iteration log in sync. Run `bin/ensemble-lint --scope <plan-path>` so a broken citation surfaces now, not at promotion. Then re-invoke with a `## Previous review context` section assembled into a tempfile **from `peer_review_resolutions:`, never from the iteration-log prose**, passed as `--iteration-context-file <path>`.
        - **Severity gate on the re-loop.** Re-invoke **only if at least one finding this pass was `P0` or `P1`**. A pass returning only `P2`/`P3` applies what is cheap, records the rest, and exits with `reloop_skipped: advisory-only`; a second full pass to confirm a typo fix is not worth its latency.
        - **Iteration cap: 1 at every depth**, so at most **two** peer passes. `--max-iterations <N>` raises it; `--no-reloop` runs the initial pass only. At the cap, ask "accept as-is and flip to `open`, or stay in `draft`?" and let the user decide. A finding the user disagreed with goes on a "do not re-flag" list in the next prompt; a third appearance counts as the cap hit.
17. **Promote to `open` (status flip).** Every path that produces a buildable plan flips it, not just peer-approve. Flip when any of these is true:
    - The loop exited with `verdict: approve`.
    - `--no-peer` was passed.
    - `PEER_AVAILABLE=false` from host detection.
    - The peer was auto-skipped under `skip_peer_below_lines` (plan < 50 lines) or `skip_peer_on_lightweight: true`.
    - The cap was hit on `verdict: revise` AND the user chose "accept as-is".
    - The peer returned `verdict: reject` AND the user explicitly overrode it.

    **Validate first.** Run `bin/ensemble-lint --scope docs/plans/active` here (the directory scope also catches a plan-ID collision with a sibling) and fix what it flags on this file until clean. Its P1 rules (`unit.risk-class`, `unit.destructive-order`, the filename shape) are what `/en-build` refuses later, and the peer does not lint. Without the lint, check the frontmatter fields, `risk:` on every unit and the destructive ordering by hand, and say so (`/en-setup` installs it).

    On promotion: compute `peer_review_plan_hash` with `$SKILL_DIR/scripts/ensemble-plan-hash <plan-path>`, write its output to frontmatter alongside `peer_review_verdict`, and flip `status: draft → open`. **Do not canonicalize the fields yourself** (D41): no model computes sha256, and each ad-hoc shell attempt canonicalizes differently, so `/en-build` re-checking with the same helper would refuse a plan nobody edited. The file stays in `active/`, the directory; there is no `status: active` value.

    **Close out the design doc.** If this plan consumed a `docs/designs/*.md` (the path in `related_design:`), that exploration is settled. In the same promotion, write this plan's `plan_id` into the design's `related_plan:` and set its `status:` to **`accepted`** when the plan carries the design's recommendation, or **`superseded`** when planning committed to a different approach, noting the plan in `replaced_by:`. Only `/en-plan` holds both, so only it can tell these apart. Leave an already-closed design alone; the first plan to open owns the flip. This sits here rather than on the peer-approve path because a Lightweight plan commonly reaches `open` with no peer pass, and without it every design ever written stays in `/en-brainstorm`'s resume pool.

    The plan stays `draft` ONLY on an unoverridden `reject`, or a peer timeout or malformed JSON the user has not yet decided on. Then do not advance to the auto-commit step or the hand-off: surface state and stop. `/en-build`'s pre-flight offers recovery next time.
18. **Auto-commit the plan file.**
    - Commit on the current branch, whatever it is. Skip on detached HEAD or any unusual state; surface and ask.
    - Refuse if `git diff --cached` holds unrelated staged changes; surface and ask the user to commit the plan by hand. Untracked or unstaged changes to *other* files are fine: `git add` takes the plan file path only, never `git add -A`.
    - Commit message (HEREDOC):
      ```
      docs(plan): <plan_id> <slug> (<N> units)

      Plan finalized after <peer_review_iterations> peer-review iteration(s).
      Verdict: approve. Generated by /en-plan.
      ```
    - Does not push. Does not open a PR. `/en-ship` owns those.
19. **Capture-from-synthesis reflex (D21).** Soft-prompt to capture any non-obvious pattern that emerged during planning as a learning.
20. **Hand off to `/en-build`.** Close the run first: `bash "$SKILL_DIR/scripts/ensemble-run-metrics" finish "$METRICS"`.
    > "Plan written and finalized: `docs/plans/active/EN07-feature_auth-rotation.md` (5 units, status: open, committed as <commit-sha>). Ready to build with `/en-build <that path>`?"

## Flags

| Flag | Effect |
|---|---|
| `--no-peer` | Skip peer review entirely. Plan is left at `status: open` with `peer_review_verdict: null` (legacy/no-peer mode). |
| `--no-reloop` | Run the initial peer pass only; never re-invoke. (Pre-finalize-loop behavior.) |
| `--max-iterations <N>` | Raise the re-loop cap above 1. |
| `--branch-on-default <y\|current\|no-commit>` | Pre-answer the default-branch checkpoint for non-interactive runs (CI, automation). No effect off the detected default branch. |
| `--research <path>` | Prior research replaces the two research dispatches (Phase 1 research). |
| `--resume <plan-path>` | See the resume-or-create step. |
| `--from-legacy <path>` | See the resume-or-create step. |

## State-2 retrofit fallback

No `docs/foundation.md` yet (a retrofit reaching `/en-plan` before `/en-foundation`): set `covers_requirements: []` and `requirements_pending: true`, and surface the gap, "Plan will reference requirements as `requirements_pending: true`. Run `/en-foundation --retrofit` later to back-fill R-IDs." `bin/ensemble-lint` emits a P3 advisory, not a P1 blocker, for plans in this state; once foundation has R-IDs the rule upgrades to P1 and `/en-learn` back-fills `covers_requirements`.

## Output

Report the file actually written this run, with the resolved `<PREFIX><NN>` and `<plan_type>_<slug>` substituted, never the literal example below:

```
Plan: docs/plans/active/EN07-feature_auth-rotation.md (5 units, 380 lines)

Units:
  - U1: Add singleFlight<K, V> helper (test-first)
  - U2: Wire Redis connection (pragmatic)
  - U3: Wrap rotateRefreshToken in singleFlight (test-first)  ← critical path
  - U4: Migration for refresh_token_rotated_at column (characterization-first)

Research: repo-research, learnings-research
Peer review: cross-agent (codex). Verdict: revise. Applied 2 of 3 findings (1 deferred to TD8).

Default-branch checkpoint: auto_branched (created EN07-auth-rotation from main)
metrics: <path> (2 dispatches, 2 peer passes)

Next: /en-build docs/plans/active/EN07-feature_auth-rotation.md
```

## Failure protocol

**`references/plan-failures.md` owns the table**: one row per failure and what to do. Three of them stop the run rather than degrade it.

| Failure | Behavior |
|---|---|
| Two units claim the same file with conflicting changes | A planning bug. Do not write the plan. |
| A `risk: destructive` unit is ordered before a non-destructive one | Refuse to write. Surface the two units and the fix: move the destructive unit later, or raise the other's risk. |
| Peer rejects the plan (verdict: reject) | Pause and surface the reject reason; leave `status: draft`. If the user explicitly overrides the rejection ("proceed anyway"), treat as approved: run the **status-flip step** (compute hash, flip `status: draft → open`, write `peer_review_verdict: reject` + a `peer_review_overridden: true` marker for audit) and continue to the **auto-commit step**. |
