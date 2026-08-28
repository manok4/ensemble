# Peer review brief — reviewing a plan

What the peer is asked to judge when `/en-plan` sends it a plan, and what this
skill does with what comes back. The wire format both ends share is
`references/peer-contract.md`; everything here is en-plan's own.

These dimensions used to live in a heredoc inside
`scripts/ensemble-build-peer-prompt`, behind `if [ "$ARTIFACT_TYPE" = "plan" ]`.
Every other artifact type hit the `else` and got an empty string, so code review
and document review went to their peers with no dimensions at all. Prose belongs
where it can be read and reviewed, not inside a shell conditional.

## What the peer is asked

Plan review dimensions: does the plan build the right thing, and is it safe to run?

A. Does it achieve the goal? Read GOAL, then the units. Flag work the goal needs that no unit covers, and units that serve no stated goal.
B. Unit decomposition. Flag units too large to review or commit atomically, units that should have been split (auth/payments/migrations always stand alone), and independent concerns fused into one unit.
C. Test scenarios. Every feature-bearing unit needs real scenarios with concrete inputs and expected outcomes across happy path, edge cases and error paths — not \"tests pass\". A feature unit with none, or with vague ones, is P1.
D. risk: correctness. Cross-check against each unit's approach (DROP/TRUNCATE/mass-DELETE → destructive; backfills over large row counts → high). Misclassified destructive units are P0/P1.
E. Dependency-vs-phase violations (a low-risk unit depending on a higher-risk one).
F. gated: correctness. gated is for production-state-changing units only (customer-facing flag flips, production backfills, real-side-effect 3rd-party APIs, API contract breaks, production config changes). Flag gated:true on an internal/UI rename, refactor, test addition, or new code behind an off flag — over-gating trains users to autopilot through prompts and erodes signal value. Equally flag missing gated:true on units that DO change production state.
G. Stated assumptions. Flag anything the plan bets on without saying so, especially claims that something does not already exist.

Do NOT flag: prose style, heading format, markdown formatting, unit ID numbering, or wording preferences. This is a plan, not a document review.

## Where a finding points

Use the unit id (e.g. "U3") when the finding is about a unit, the section name for plan-level issues, or "global".

The finding's `u_id` field: u_id            "U<N>" when the finding is about a specific unit, else null.
                  The host dispatches per-unit off this field, so set it
                  whenever the finding belongs to a unit.

## What en-plan does with the findings

Contract first: severity, confidence, the autofix classes and the resolution
statuses are defined in `references/peer-contract.md` and mean the same thing
everywhere. What follows is this skill's policy.

| Finding | en-plan's action |
|---|---|
| P0, any confidence | Stop. Surface to the user; a plan with a blocking defect is not buildable. |
| P1, confidence ≥ 7 | Apply to the plan text, record the resolution. |
| P1, confidence < 7 | Surface; the user decides. |
| P2 | Apply if the edit is cheap and local; otherwise record as `deferred` with a rationale. |
| P3 | Record as `deferred` unless it costs nothing to fix. |

**A plan is prose, so every fix is an edit to the plan file.** There is no code
to re-verify, which is why en-plan's policy has no re-verification step at all —
the code-shaped "re-run unit tests and lint" that used to sit in the shared
severity file means nothing here.

Record each finding in `peer_review_resolutions:` with its `finding_id`,
`iteration`, `severity`, `title`, `status` and, for anything not `applied`, a
`rationale`. That record is what the re-review reads; never assemble the
previous-review context from the iteration-log prose.

## The re-review loop

Cap by depth: lightweight 1, standard 2, deep 2. Re-invoke only when the pass
returned at least one P0 or P1 — a second full round to confirm a typo fix is not
worth its latency. On cap-hit with findings outstanding, ask the user to accept
or stay in draft; never flip to `open` on the skill's own judgement.

## Effort

A plan review is a reading task on a bounded document, so it does not need the
diff-shaped effort ladder `/en-review` uses. Ask for the default tier and let the
operator's configuration override it.
