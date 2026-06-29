# Validator dispatch (en-review false-positive sweep)

An optional, independent re-check that kills false positives before they reach the user. **Off the hot path** — it spawns one validator subagent per in-scope finding, so it's gated to where it earns the cost.

## When it runs

- **`--validate`** — run the validator over all surfaced findings.
- **Default (no flag)** — auto-run for **P0 and P1 findings only**, capped at **10** (prioritizing P0, then P1 by anchor). P2/P3 are not validated by default (the confidence gate + quote-the-line gate already filter them cheaply).
- **`--no-validate`** — skip entirely.

The cap bounds the cost: at most 10 extra subagent calls, only on the highest-severity findings. Routine reviews (no P0/P1, or `--no-validate`) pay nothing.

## What each validator answers

For one finding, a fresh subagent re-checks — independently of the reviewer that raised it — three questions against the actual diff + surrounding code:

1. **Real?** Is the issue real in the code as written (not a misreading)?
2. **Introduced by THIS diff?** Or is it pre-existing / unrelated to the change under review?
3. **Not handled elsewhere?** Is there already a guard, validation, or handler that covers it that the reviewer missed?

Returns: `{ "validated": true | false, "reason": "<one line>" }`.

## Applying the result

- `validated: true` → keep the finding as-is.
- `validated: false` → **drop** the finding — **but only P2/P3**. Record the drop in the coverage section (count + reasons) so it's auditable, not silent.
- **Keep P0/P1 even on `validated: false`** unless the reason is clearly decisive (e.g. "this exact guard exists at `file:line`"). A validator disagreeing with a critical finding is a flag for human judgment, not an auto-drop — surface the disagreement.
- **Infra failure** (validator subagent errors/times out): keep the finding; never let a transient failure silently remove a finding. For P2/P3 on infra failure, keep and mark `validation: degraded`.

## After validation

Prune any finding dropped here from the triage groups (`references/persona-dispatch.md` grouping) so a group never references a dropped `#`. Surface a coverage line: `validated N findings; dropped M as false-positive (P2/P3); K kept despite validator disagreement (P0/P1)`.

## Cost note

The validator is the most expensive optional layer (N subagent calls). It is deliberately **not** part of Lite/Standard routine review — those rely on the quote-the-line gate + cross-agent peer for false-positive control. Reach for `--validate` (or let the P0/P1 auto-run fire) when a review surfaces high-severity findings you want independently confirmed before acting.
