# `/en-plan` finalize loop

> Read at step 16, after the first peer pass returns. `references/outside-voice.md` owns verdict
> handling and the previous-review-context section; this file is `/en-plan`'s policy on top of it.

## Verdict handling

- On `approve` → exit; go to the status flip. On `reject` → pause, surface, leave `status: draft`, no re-loop. A timeout or malformed JSON after one retry behaves the same way.
- On `revise` → walk findings, apply / defer / disagree per `references/peer-brief.md`, each application a surgical edit to the plan file, never a rewrite of it. Record each in `peer_review_resolutions:` (entry schema in `references/templates/plan-template.md`) and keep the narrative iteration log in sync. Run `bin/ensemble-lint --scope <plan-path>` so a broken citation surfaces now, not at promotion. Then re-invoke with a `## Previous review context` section assembled into a tempfile **from `peer_review_resolutions:`, never from the iteration-log prose**, passed as `--iteration-context-file <path>`, with `--plan-before` naming the copy of the plan taken before the first edit (`references/peer-pass.md`). The builder renders the unit and byte counts and a diff capped at 200 lines, and the peer flags any growth no applied finding required, at P2, so it cannot start a third pass.

## Checking the paraphrase

For a plan review the peer's `summary` is a paraphrase of what the plan builds (`references/peer-brief.md`), not an assessment, and progress reports label it as a paraphrase. After parsing, compare it with the plan's Context and each unit's Goal. A mismatch the plan's wording caused is a host finding, `finding_id` `<iteration>-h<index>`, fixed by editing the plan and recorded like any other: a goal no unit covers is check A's **P1**, a wording or framing gap **P2**. A mismatch from the peer misreading goes in the iteration log only. A host finding never re-invokes the peer by itself; the re-review runs only on the peer's own P0/P1, as below.

## Severity gate on the re-loop

Re-invoke **only if at least one finding this pass was `P0` or `P1`**. A pass returning only `P2`/`P3` applies what is cheap, records the rest, and exits with `reloop_skipped: advisory-only`; a second full pass to confirm a typo fix is not worth its latency.

## Iteration cap

**1 at every depth**, so at most **two** peer passes. `--max-iterations <N>` raises it; `--no-reloop` runs the initial pass only. At the cap, ask "accept as-is and flip to `open`, or stay in `draft`?" and let the user decide. A finding the user disagreed with goes on a "do not re-flag" list in the next prompt; a third appearance counts as the cap hit.
