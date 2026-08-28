---
name: en-plan
description: "Turn a feature, refactor, or bug fix into a plan with stable U-IDs and plan_type (feature | improvement | bug). Reads foundation, runs research agents (repo-research + learnings-research; web-research conditional), breaks work into units with files / tests / execution notes; runs cross-agent peer review on the draft. Modes: --resume <plan> (promote a draft); --from-legacy <path> (migrate legacy plan). Outputs docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md. Trigger phrases: 'plan this', 'plan a feature', 'before I build', 'plan <id>'."
# What this skill needs. Every path is skill-relative and must exist here.
# A skill is self-contained: nothing outside this directory is listed.
requires:
  - agents/learnings-research.md
  - agents/repo-research.md
  - agents/web-research.md
  - references/agent-dispatch.md
  - references/build-handoff.md
  - references/build-orchestration.md
  - references/cli-wrappers.md
  - references/diff-signal-detection.md
  - references/doc-lints.md
  - references/finding-schema.md
  - references/host-detect.md
  - references/outside-voice.md
  - references/peer-brief.md
  - references/peer-contract.md
  - references/peer-model-policy.md
  - references/persona-dispatch.md
  - references/plan-default-branch-checkpoint.md
  - references/recursion-guard.md
  - references/research-dispatch.md
  - references/script-invocation.md
  - references/severity.md
  - references/single-agent-fallback.md
  - references/stable-ids.md
  - references/templates/plan-template.md
  - scripts/en-sweep-ci
  - scripts/ensemble-build-peer-prompt
  - scripts/ensemble-cli-smoke
  - scripts/ensemble-config-get
  - scripts/ensemble-detect-host
  - scripts/ensemble-extract-json
  - scripts/ensemble-peer-flags
  - scripts/ensemble-peer-invoke
  - scripts/ensemble-plan-hash
  - scripts/ensemble-verify-peer-evidence

---


# `/en-plan`

> **Running a bundled script.** Anchor every call to this skill's own directory: `SKILL_DIR="<absolute path of the directory containing this SKILL.md>"; bash "$SKILL_DIR/scripts/<name>"`. The trailing `;` is load-bearing. See `references/script-invocation.md`.


> **Dispatching a bundled agent.** This skill carries its agents in `agents/`. Dispatch by name as usual; when the name is not registered (a lone skill directory), resolve it from the bundled definition per `references/agent-dispatch.md`.


Concrete implementation plan with stable U-IDs and Outside Voice peer review. Hands off to `/en-build`.

> **Priority principle (D39): performance > speed ≥ cost.** Optimize first for plan quality (does the plan lead to the right thing, built well), then for speed, then for token/tool cost. Research depth, peer-review iterations, and plan-content rigor are worth their cost when they lift build quality; keep them self-gating so lightweight work stays fast.

> **Hard gate.** Plan only — no code, no commits, no PR. Output is a markdown plan file plus the peer-review verdict.

> **Peer contract.** Severity, confidence, autofix class, the `peer_decision`
> object and its reason enum are defined once in `references/peer-contract.md`
> and are byte-identical across every skill that exchanges findings. What this
> skill *does* with a finding is its own policy, not part of that contract.

## Process

1. **Detect host.** Source `references/host-detect.md`. Resolve `PEER_CMD`, `PEER_MODE`.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, skip the Outside Voice pass.
3. **Resume or create.**
   - **`--resume <plan-path>`** (explicit) — load the named plan; preserve its `plan_id`, `plan_type`, `created`, `generator` (if present); apply the rest of the planning flow (research, questions, U-IDs, peer review) to flesh it out. Used to promote auto-generated draft plans (from `/en-sweep`'s continuous monitoring) into full peer-reviewed plans. Status remains `draft` until the status-flip step; only the user can flip to `open`.
   - **`--from-legacy <path>`** (explicit) — read content from a legacy plan (typically `docs/plans/legacy/<file>.md` archived during `/en-setup` retrofit). The legacy file is **not modified** and **not moved**; this flag uses it as input to mint a *new* Ensemble plan. Steps:
     - Read the legacy file's full content (no frontmatter assumed; treat all of it as narrative).
     - Pass it to the user as initial context; ask: *"Migrate this legacy plan into Ensemble. I'll run the normal plan flow (research → questions → U-IDs → peer review). The legacy file stays in `docs/plans/legacy/` untouched. Confirm? (y/n)"*.
     - On `y`, treat the legacy content as the **rough description** input (per the source-the-request step) and proceed normally — agent runs research, asks planning questions, breaks into U-IDs, mints a fresh `<PREFIX><NN>` ID, writes a new plan in `docs/plans/active/`.
     - The new plan's frontmatter carries `migrated_from: docs/plans/legacy/<file>.md` for traceability. The legacy README's "list of archived files" gets a back-reference: *"Migrated to <new plan path> on <date>."* — written alongside the plan file so the auto-commit picks it up.
     - Use this to bring meaningful legacy plans into the active flow with proper R-ID/U-ID assignment and peer review — never an in-place auto-conversion.
   - **Auto-resume** (heuristic) — if a plan in `docs/plans/active/` already matches the user's request by title or `related_design`, offer to resume rather than create a new one.
   - **Create** — no match; mint a new plan.
4. **Source the request.** Identify input:
   - Brainstorm design doc (`docs/designs/*.md`) — pre-explored, recommendation already on the table.
   - `docs/foundation.md` — pulling a requirement (R-ID) for the next slice of work.
   - Direct rough description from the user.
   - Bug report or tracked debt item (`Resolves: TD<N>`).

   **Bounded foundation read.** Never read `docs/foundation.md` whole — it routinely runs past 2,000 lines. Read the **frontmatter** (for `plan_id_prefix`), then `grep -n '^#' docs/foundation.md` for the section index, then `sed -n '<start>,<end>p'` on the sections you actually need: **Functional Requirements** for R-IDs and acceptance examples, **Technical Direction** when the plan makes stack or dependency choices. Nothing else.

   **Consume the design doc; don't re-interview across it.** When a `docs/designs/*.md` matches this topic with `status: open` or `accepted`, its settled decisions are **already answered** — architecture, scope boundaries, rejected alternatives, and the recommendation. Read it, carry those decisions into the plan (record the path in `related_design:`), and put **only what the doc left open** to the user in the planning questions. Re-asking a question the design doc settled is the most common way this seam wastes the user's time. The doc's `## Assumptions & unverified claims` section is the exception: those are explicitly *not* settled — verify them against the repo or carry them forward as plan-level assumptions.

   **Context-sufficiency check.** Before planning, judge whether you have enough to plan *from* — not whether a design doc happens to exist. Skip this entirely for a bug/TD fix or a `--resume`/`--from-legacy` run, and skip it when a matching design doc was consumed above (that doc already did this work).

   The request is **insufficient** when one or more of these is genuinely unresolved, and nothing in the foundation, research, or the request itself settles it:

   - **The problem is unstated.** You know what to build but not what it's for or who for — so no unit can claim a requirement and "done" has no definition.
   - **The approach is genuinely open.** Two or more materially different designs are viable and there is no basis in context to choose. Planning here picks an architecture by accident.
   - **Scope has no edges.** You cannot tell what's in and what's out, so units can't be sized and the plan will either sprawl or miss half the work.

   **Insufficient → offer the brainstorm, and mean it:**
   > *"I don't have enough to plan from yet — <the specific gap, in one clause>. `/en-brainstorm` would settle that in a few questions and hand back a design doc. Brainstorm first, or plan anyway on my assumptions? (brainstorm / plan anyway)"*

   Recommend `brainstorm` — but **proceeding is always allowed** and remains the default on any non-answer; this is never a hard gate (gating-shrink philosophy — encourage, don't block). If the user proceeds anyway, record each unresolved gap in the plan's `## Decisions, assumptions & risks` section as an explicit assumption, so the guess is visible rather than buried in a unit's `Approach:`.

   **Sufficient but no design doc → one-line soft nudge only:** *"No design doc for this — want to `/en-brainstorm` first, or go straight to planning? (brainstorm / proceed)."* Default proceed. A well-specified request does not need to be talked out of being well-specified.

   **Infer `plan_type`** from the request — `feature` (net-new behavior), `improvement` (refactor / perf / DX work, including TD), or `bug` (fix). Default `feature` when unclear; confirm with the user when the request is ambiguous.
5. **Right-size depth.**
   - Lightweight: 1–3 units, single file or two, no architecture changes.
   - Standard: 3–10 units, several files, possible new components.
   - Deep: 10+ units, structural change, multi-week work.
   Depth is asked or inferred; default Standard.
6. **Phase 1 research (parallel).** Per `references/research-dispatch.md`:
   - `repo-research` — patterns, conventions, file paths, prior art (Standard/Deep always).
   - `learnings-research` — relevant entries from `docs/learnings/` via `index.md` (Lightweight optional, Standard/Deep always).
   - `web-research` — only if a 3rd-party library not used elsewhere AND the library has known footguns AND the user hasn't said "skip web research".
7. **Resolve planning questions — frontier rounds.** Ask every question whose prerequisites are settled in **one numbered round**, each carrying your **recommended answer**, so a round is "confirm these, correct what I got wrong" rather than "answer these". A question that depends on another still open **in this round** waits for the next round — that dependency rule is what keeps batching from producing diluted answers. Skip outright anything the design doc already settled (the source-the-request step) or that research already answered; facts in the repo are looked up, never asked.

   The natural shape here is two rounds, because file boundaries and test strategy both partly depend on the architecture answer:

   - **Round 1:** which architecture do we land on (if multiple were on the table)?
   - **Round 2:** file boundaries — new files vs extending existing? · test strategy — unit / integration / end-to-end, and test-first / characterization-first / pragmatic? · dependencies — any new packages? (**bias toward boring tech**: prefer the dependency the project already has, or none, over a new one that is marginally nicer) · migrations — schema, data, config?

   On **Lightweight**, ask one question per turn instead; a 1–3 unit plan does not need a tree. Stop when the frontier is empty or the questions are answered by the design doc and research.
8. **Break into units (U-IDs).**
   - Each unit: one logical change, peer-reviewable, atomically committable.
   - Tightly-coupled changes batch into one unit; independent concerns become separate units.
   - Auth/payments/migrations always get their own unit even if small.
   - **Never renumber after assignment** (per `references/stable-ids.md`).
9. **Per-unit metadata.** For each U-ID:
   - **Goal:** one line.
   - **Requirements covered:** R-IDs and AE-IDs from foundation. (For State-2 retrofit projects without a foundation yet, leave `covers_requirements: []` and set `requirements_pending: true`.)
   - **Dependencies:** other U-IDs that must complete first.
   - **Files:** repo-relative paths.
   - **Approach:** how the unit will be implemented.
   - **Risk:** `low | medium | high | destructive`. Drives `/en-build` phase placement and safety gates. Ask if unclear; default `medium` only when the unit is genuinely additive and reversible. Mark `destructive` for any DROP TABLE / DROP SCHEMA / mass DELETE / TRUNCATE / recursive removal of persistent data.
   - **Category:** one of `feature | observability | diagnostics | api-additive | migration-additive | migration | backfill | schema-evolution | deletion | drop | removal | other`. Metadata only; does not override `risk:`.
   - **Reversibility:** `trivial | reversible | rollback-required | irreversible`. Informational; helps the user judge risk.
   - **Gated:** `true | false`. **Default `false`.** Set `true` ONLY when running this unit at build time changes **production user state** or **external system state** beyond what tests / lint / peer review can verify. Concrete cases that qualify: customer-facing feature flag flips that change real-user behavior on deploy; production data backfills; third-party APIs with real side effects (email/SMS/payment/Slack against non-test endpoints); API contract breaks (renaming/removing public response fields, breaking generated-client signatures); production config changes with behavior impact. **Do NOT gate**: refactors, internal renames, UI text/copy renames, new code behind an off flag, test additions, lint fixes, doc updates, or schema additions (those are handled by `risk:`). Default `false` and only flip to `true` when one of the qualifying cases clearly applies — see `references/templates/plan-template.md` for the full criteria. Over-gating trains users to autopilot through y/skip/abort prompts and erodes the signal value of the gates that matter.
   - **Execution note:** `test-first` / `characterization-first` / `pragmatic`.
   - **Patterns to follow:** citations to `docs/learnings/patterns/` if relevant.
   - **Test scenarios:** for a **feature-bearing** unit, enumerate **actual** scenarios across the applicable categories — **happy path, edge cases, error/failure paths, integration** — each with concrete inputs/actions/expected outcomes (not a single vague "tests pass" line). **Non-feature-bearing** units (pure config, scaffolding, styling, docs) use `**Test expectation:** none — <reason>` instead. See `references/templates/plan-template.md`.
   - **Verification:** what counts as done (tests passing, lint clean, manual check).
   - **Resolves (optional):** `TD<N>` IDs from `docs/plans/tech-debt-tracker.md`.

   **Phase invariant check.** For every dependency edge `U → V` (U depends on V), verify `risk(V) <= risk(U)` in the order `low < medium < high < destructive`. A low-risk unit depending on a higher-risk unit is a structural error — `/en-build`'s phase loop refuses to run such plans. Surface and resolve before writing the plan: either remove the dependency, promote `U`'s `risk:`, or split `U` into a part that doesn't depend on the higher-risk unit.
10. **Resolve `plan_id_prefix`.** Read `plan_id_prefix:` from `docs/foundation.md` frontmatter. If absent (older project, retrofit, or `/en-foundation` not yet run), default to `FR`. Plans inherit the prefix in force at the time they are minted; the prefix is part of the plan's stable ID and never rewritten.
11. **Auto-increment plan number.** Scan `docs/plans/active/` and `docs/plans/completed/` for the highest existing plan number under the *current* `plan_id_prefix`. Legacy `FR` plans count toward `FR`'s numbering only; a new `EN` project starts at `EN01` even if `FR99` already exists. Zero-pad to 2 digits (3 once `99` is reached).

12. **Pre-write plan-quality review** (before writing the plan file). A lightweight self-check that catches the two most common quality gaps before peer review sees them:

    - **Test-scenario completeness.** For every **feature-bearing** unit, confirm the `Test scenarios:` enumerate real scenarios across the applicable categories (happy path / edge cases / error-failure paths / integration) with concrete inputs/actions/outcomes. A feature unit with blank or fewer-than-two scenarios is **incomplete** — strengthen it before finalizing (or, if genuinely non-feature, switch it to `**Test expectation:** none — <reason>`). This mirrors the `unit.test-scenarios` lint (P2 advisory) so plans arrive at peer review already clean.
    - **Decisions / assumptions / risks capture.** If research (repo/learnings/web) or the planning discussion surfaced a **non-obvious decision, a rejected alternative, an inferred assumption the plan bets on, or a genuine risk**, capture it in the optional `## Decisions, assumptions & risks` section (per `references/templates/plan-template.md`) rather than burying it in unit `Approach:` fields. **Omit the section entirely** when nothing substantive surfaced — do not add it as empty boilerplate on trivial plans.
    - **Technical-design load-bearing audit (self-gating).** Count the **architecture-complexity triggers** the plan fires: **≥3 new/changed components**, a **≥3-step protocol/handshake**, a **state machine**, **≥3 data-flow stages**, or **DSL / public-API design**. If **any** trigger fires (typically Deep / high-risk plans), the plan MUST carry a plan-level `## Technical design` section — a **directional** high-level sketch of the cross-cutting architecture (component boundaries, data flow, key interfaces), not a spec. Verify the section is present when a trigger fired; a missing section with a fired trigger is **incomplete** — add it before finalizing. **Self-gating:** if no trigger fires (simple plans), the section is not required and must not be added as boilerplate.

13. **Default-branch checkpoint** (resolve the target branch BEFORE the plan file is written, so a resume run never hits "untracked working tree file would be overwritten" on `git checkout`).

    | Condition | Action |
    |---|---|
    | `--commit-branch <name>` passed | Check out `<name>` (create if needed); skip the checkpoint. |
    | `--no-commit` passed | Stay on the current branch; skip the checkpoint. The auto-commit step is skipped later. |
    | Current branch **is** the detected default branch | **Checkpoint fires.** Read `references/plan-default-branch-checkpoint.md` and follow it — it owns default-branch detection, the prompt, the four response handlers, and the non-interactive `--branch-on-default` flag. |
    | Anything else (already on a feature branch, detection failed, detached HEAD) | Stay on the current branch; skip the checkpoint. |

    Record the outcome as `default_branch_checkpoint: <auto_branched | no_commit_requested | committed_to_default_branch>` in the `/en-plan` report.

14. **Write to `docs/plans/active/<PREFIX><NN>-<plan_type>_<slug>.md`** using `references/templates/plan-template.md`. Filename example: `EN03-improvement_dashboard-overview.md`. Substitute fields including `plan_id` (`<PREFIX><NN>`), `plan_type`, and `data_scale` (default `small`). Initialize `peer_review_iterations: 0` and `peer_review_resolutions: []`. Status starts as `draft`; the **finalize loop** in the Outside Voice step may flip to `open` automatically.
15. **Outside Voice review with finalize loop.** If `PEER_AVAILABLE=true` (and `--no-peer` not set):
    - Build the prompt by shelling out to `$SKILL_DIR/scripts/ensemble-build-peer-prompt --brief references/peer-brief.md --project-context "<one-line>" --goal "<one-line>" --artifact-file <plan-path> --peer-mode "$PEER_MODE"` — the helper substitutes the plan-specific review-dimensions block and the single-agent fallback note for you. Do NOT assemble the prompt by reasoning; that's slow and produces drift from the canonical template in `references/outside-voice.md`.
    - Set `ENSEMBLE_PEER_REVIEW=true`.
    - **Invoke via `$SKILL_DIR/scripts/ensemble-peer-invoke`** with `ENSEMBLE_PEER_REVIEW=true`, passing `$PEER_CMD`, `$PEER_FORMAT`, `$PEER_TURNS`, the prompt file, and `--peer-mode "$PEER_MODE"`. **Do not restate the invocation or retry algorithm** — the helper owns the `timeout` wrapper, failure classification (`auth` / `unknown` / `timeout`), the single bounded retry, and the fallback, so the behaviour is executable and testable rather than prose (D41). It returns a `peer_decision` object per `references/peer-model-policy.md` (e); surface its `peer`/`reason` in the run report so a skipped or degraded peer can never read as a normal one.
    - Parse JSON per `references/finding-schema.md`. Mint `finding_id` as `<iteration>-<index>` for any finding the peer didn't supply one for.
    - Update frontmatter: `peer_review_verdict`, `peer_review_iterations` (+1), `peer_review_last_run` (ISO 8601 date).
    - **Re-review loop** (the finalize loop):
      - On `verdict: approve` → exit the loop. Proceed to the status-flip step.
      - On `verdict: revise` → walk findings, apply / defer / disagree per `references/severity.md`. Write each as a structured entry to `peer_review_resolutions:` with `finding_id`, `iteration`, `severity`, `title`, `status` (`applied | deferred | disagreed | superseded`), `rationale` (required for non-`applied`), and `location`. Update the human-readable iteration log narrative to match. Then **re-invoke the peer** with a `## Previous review context` section: assemble the section into a tempfile from `peer_review_resolutions:` (NEVER from the iteration-log prose) and pass it as `--iteration-context-file <path>` to `$SKILL_DIR/scripts/ensemble-build-peer-prompt`. Continue looping until `approve` or the depth-aware iteration cap is hit.
        - **Severity gate on the re-loop.** Re-invoke the peer **only if at least one finding this pass was `P0` or `P1`** (per `references/severity.md`). When the pass returned **only `P2`/`P3`** findings — naming inconsistencies, style preferences, "consider X later" — apply what's cheap, record the rest in `peer_review_resolutions:`, and **exit the loop**; a second full peer pass to confirm a typo fix is not worth its latency. Record `reloop_skipped: advisory-only` alongside the resolutions so the exit is auditable.
        - **Iteration cap: 1 at every depth** — at most **two** peer passes total (the initial pass plus one verification pass). `--max-iterations <N>` raises it when a plan genuinely warrants more; `--no-reloop` runs the initial pass only and never re-invokes.
        - **Cap-hit behavior:** Surface the latest findings; ask the user "accept as-is and flip to `open`, or stay in `draft`?". User keeps control.
        - **Same-finding-twice suppression:** If a finding the user disagreed with re-appears on the next pass, append it to a "do not re-flag" list in the next prompt. If it appears a third time despite suppression, treat the cap as hit early.
      - On `verdict: reject` → pause, surface to user, leave `status: draft`. Do not re-loop.
      - **Failure handling:** Peer timeout → surface, leave `status: draft`, no re-loop. Malformed JSON after one retry → same behavior.
16. **Promote to `open` (status flip).** The plan moves from `status: draft` to `status: open` in **every** path that produces a buildable plan, not just peer-approve. Specifically, flip to `open` when any of these is true:
    - Peer ran and the loop exited with `verdict: approve`.
    - `--no-peer` was passed (peer was deliberately skipped).
    - `PEER_AVAILABLE=false` from host detection (peer unavailable; no flag needed).
    - Peer was auto-skipped under `skip_peer_below_lines` (plan < 50 lines) or `skip_peer_on_lightweight: true` (Lightweight depth).
    - Loop hit the iteration cap with `verdict: revise` AND the user chose "accept as-is" at the cap-hit prompt (per failure protocol).
    - Peer returned `verdict: reject` AND the user explicitly overrode the rejection (per failure protocol).

    On promotion: compute `peer_review_plan_hash` by running `$SKILL_DIR/scripts/ensemble-plan-hash <plan-path>`, write its output to frontmatter alongside `peer_review_verdict`, and flip `status: draft → open`. **Do not canonicalize the fields yourself.** The helper owns the covered-field list and the canonicalization, so producer and consumer cannot drift; deriving the hash from prose is not merely slower, it is unimplementable, since no model computes sha256 and each ad-hoc shell attempt canonicalizes differently. `/en-build` re-computes with the same helper at every phase boundary, so a mismatch means a real edit rather than a formatting difference (D41). The file stays in `active/` (the directory; not to be confused with status — there is no `status: active` value).

    The plan stays in `status: draft` ONLY when:
    - Peer returned `verdict: reject` AND the user did NOT override.
    - Peer subprocess timed out or returned malformed JSON (after one retry) AND the user has not yet decided.

    In those `draft`-stuck cases, do not advance to the auto-commit step or the hand-off to `/en-build`; surface state and stop. `/en-build`'s pre-flight will offer the recovery path on the next attempt if findings get resolved later.
17. **Auto-commit the plan file.**
    - Branch policy: commit on the current branch (default `main` / `master` / `develop`, or whatever feature branch the user is on). Skip auto-commit on detached HEAD or unusual states; surface and ask.
    - Working-tree safety: refuse auto-commit if `git diff --cached` has unrelated staged changes; surface and ask the user to commit the plan manually. Untracked or unstaged changes to *other* files are fine — `git add` is invoked with the plan file path only, never `git add -A`.
    - Commit message (HEREDOC):
      ```
      docs(plan): <plan_id> <slug> (<N> units)

      Plan finalized after <peer_review_iterations> peer-review iteration(s).
      Verdict: approve. Generated by /en-plan.
      ```
    - Does not push. Does not open a PR. `/en-ship` owns those.
    - Flags: `--no-commit` (skip), `--commit-branch <name>` (create/switch to `<name>` first).
18. **Confidence check.** Identify low-confidence sections (typically integrations or unfamiliar libraries); offer to deepen with a research dispatch or to leave as-is and resolve during build.
19. **Capture-from-synthesis reflex (D21).** If a non-obvious connection or pattern emerged during planning, soft-prompt to capture as a learning.
20. **Hand off to `/en-build`.** Suggest the build command:
    > "Plan written and finalized: `docs/plans/active/EN07-feature_auth-rotation.md` (5 units, status: open, committed as <commit-sha>). Ready to build with `/en-build docs/plans/active/EN07-feature_auth-rotation.md`?"

## Cross-review and finalize loop

**On by default.** Skip with `--no-peer`. Skipped automatically when:

- `PEER_AVAILABLE=false`.
- The plan has < 50 lines (`skip_peer_below_lines` config).
- Depth is Lightweight AND `skip_peer_on_lightweight: true`.

**Finalize loop:** when peer runs and returns `revise`, `/en-plan` applies findings (per `references/severity.md`), records them in `peer_review_resolutions:`, and re-invokes the peer with the previous-review-context section (per `references/outside-voice.md`).

**Two passes, not three.** The shape is: review → apply → **one** verification pass → done.

| Pass 1 returned | Peer passes |
|---|---|
| `approve` | 1 |
| `revise`, all findings `P2`/`P3` | 1 — apply, record, exit (`reloop_skipped: advisory-only`) |
| `revise`, any finding `P0`/`P1` | 2 |
| `reject` | 1 — pause, stay `draft`, no re-loop |

The iteration cap is **1 at every depth**. Raise it with `--max-iterations <N>` when a plan genuinely warrants more; disable re-looping entirely with `--no-reloop`. The rationale for capping at one: a single-shot peer re-reviewing a whole artifact mostly resamples its first pass, which is why the "do not re-flag" suppression list exists at all — repeat findings were already being observed and worked around.

When the loop exits with `approve` (or `--no-peer` was used), `/en-plan` computes `peer_review_plan_hash`, flips `status: draft → open`, and auto-commits the plan file (per the status-flip and auto-commit steps).

## Flags

| Flag | Effect |
|---|---|
| `--no-peer` | Skip peer review entirely. Plan is left at `status: open` with `peer_review_verdict: null` (legacy/no-peer mode). |
| `--no-reloop` | Run the initial peer pass only; never re-invoke. (Pre-finalize-loop behavior.) |
| `--max-iterations <N>` | Override the depth-aware iteration cap. |
| `--no-commit` | Finalize (`status: open`) but do not auto-commit the plan file. |
| `--commit-branch <name>` | Create/switch to `<name>` before committing the plan file. |
| `--branch-on-default <y\|current\|no-commit>` | Pre-answer the default-branch checkpoint for non-interactive runs (CI / automation). No effect when the current branch isn't the detected default branch. |
| `--resume <plan-path>` | See the resume-or-create step. |
| `--from-legacy <path>` | See the resume-or-create step. |

When peer is available:

- Cross-agent (both CLIs installed) → peer is the other agent.
- Single-agent fallback → fresh subprocess of host's CLI; prompt augmented per `references/single-agent-fallback.md`.

## Tech-debt resolution

If the user mentions a tech-debt item or the plan addresses one:

1. Read `docs/plans/tech-debt-tracker.md`.
2. Cite the TD-ID(s) in the plan's per-unit metadata: `Resolves: TD7, TD12`.
3. Frontmatter: append to the plan's `resolves:` field (if extending the schema for the project).
4. Don't delete the tech-debt entry — `/en-learn` will mark it resolved when the plan ships.

## State-2 retrofit fallback

If `docs/foundation.md` doesn't exist yet (the user is using `/en-plan` before `/en-foundation` for retrofits):

- Set `covers_requirements: []` and `requirements_pending: true` in the plan's frontmatter.
- Surface the gap: "No `docs/foundation.md` yet. Plan will reference requirements as `requirements_pending: true`. Run `/en-foundation --retrofit` later to back-fill R-IDs."
- `bin/ensemble-lint` emits a P3 advisory (not a P1 blocker) for plans in this state. Once foundation has R-IDs, the rule upgrades to P1 and `/en-learn` back-fills `covers_requirements` based on plan content.

## Output

After the run completes:

The reported path is the file actually written this run — substitute the resolved `<PREFIX><NN>` and `<plan_type>_<slug>` values, not the literal example below. Example output for an `EN`-prefixed project planning an auth-rotation feature:

```
Plan: docs/plans/active/EN07-feature_auth-rotation.md (5 units, 380 lines)

Units:
  - U1: Add singleFlight<K, V> helper (test-first)
  - U2: Wire Redis connection (pragmatic)
  - U3: Wrap rotateRefreshToken in singleFlight (test-first)  ← critical path
  - U4: Migration for refresh_token_rotated_at column (characterization-first)
  - U5: Update tests covering AE2, AE3 (test-first)

Peer review: cross-agent (codex). Verdict: revise. Applied 2 of 3 findings (1 deferred to TD8).

Default-branch checkpoint: auto_branched (created EN07-auth-rotation from main)

Next: /en-build docs/plans/active/EN07-feature_auth-rotation.md
```

## Reference files

- `references/templates/plan-template.md` — body template
- `references/host-detect.md` — host detection
- `references/outside-voice.md` — peer-review prompt and verdict handling
- `references/single-agent-fallback.md` — fallback mode contract
- `references/finding-schema.md` — peer JSON shape
- `references/severity.md` — apply / defer / disagree routing
- `references/research-dispatch.md` — when to dispatch which research agent
- `references/stable-ids.md` — U-ID stability rules

Gated — read only when its step's gate fires, never up front:

- `references/plan-default-branch-checkpoint.md` — the default-branch checkpoint (skipped whenever the run is already on a feature branch)

## Failure protocol

| Failure | Behavior |
|---|---|
| Plan touches > 30 files | Surface size warning; offer to split into multiple FRs |
| `docs/foundation.md` too large to scan cheaply | Section-index read only (source-the-request step); never fall back to reading it whole. |
| Design doc matching the topic is `superseded` | Do not carry its decisions; treat the request as unexplored and apply the brainstorm soft-nudge. |
| Two units claim the same file with conflicting changes | Flag as a planning bug; don't write the plan |
| User accepts plan but peer review hasn't returned yet | Wait for peer (with timeout); if peer times out, plan is written without peer verdict; surface "peer review timed out" in the report |
| Peer rejects the plan (verdict: reject) | Pause and surface the reject reason; leave `status: draft`. If the user explicitly overrides the rejection ("proceed anyway"), treat as approved: run the **status-flip step** (compute hash, flip `status: draft → open`, write `peer_review_verdict: reject` + a `peer_review_overridden: true` marker for audit) and continue to the **auto-commit step**. The valid post-flip status is **`open`** — `active/` is the directory the file lives in, not a status value. |
| Finalize loop hits iteration cap with `verdict: revise` | Surface latest findings; ask user "accept as-is and flip to `open`, or stay in `draft`?". User keeps control. |
| Re-review surfaces a finding the user previously disagreed with | Append finding to "do not re-flag" list in the next prompt. If it appears a third time despite suppression, treat the cap as hit early. |
| Auto-commit refused due to unrelated staged changes | Surface and skip the commit step; user finalizes manually. Plan still flips to `open`; just isn't tracked yet. `/en-build` pre-flight will offer auto-commit on next attempt. |
| Plan structure violates phase invariant (low-risk depends on higher-risk) | Refuse to write. Surface the offending dependency and the three remediation options (remove dependency / promote risk / split unit). |
| FRXX collision (race condition) | Re-scan; increment; retry. Lint will catch if it actually slips through |
