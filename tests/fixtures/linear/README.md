# Linear round-trip fixtures (EN18 U1, EN19 U1)

Captured 2026-09-22 against a real Linear workspace (team `Emble`) by the EN18 U1
spike. These are not hand-written: `EN18-readback.json` holds the bytes Linear
actually returned. The scratch issues were cancelled afterwards, so this file is
the only remaining record of the round-trip.

| File | What it is |
|---|---|
| `EN18-sample-plan.md` | The source plan, copied verbatim from `docs/plans/completed/EN07-improvement_en-build-simplify-gate.md`. Its canonical hash is `40a510c0…`. |
| `EN18-readback.json` | What Linear returned for the parent and two sub-issues published from it. |
| `EN19-source-plan.md` | The sample plan with its `peer_review_plan_hash` refreshed. The EN07 original records a hash from an older canonicalizer, which `verify` now correctly calls stale, so the EN19 pair is rendered from this copy. |
| `EN19-readback.json` | **Synthetic.** `ensemble-linear-plan render` of `EN19-source-plan.md` with Linear's measured `- ` to `* ` rewrite applied and the units reversed, as `list_issues` returns them. |
| `EN19-rendered-plan.md` | The golden output of `ensemble-linear-plan materialize` on `EN19-readback.json`. Its body is byte-identical to the source plan's. |

The point of the pair is that the second must be reducible to the first.
`skills/*/references/linear-plan-format.md` states the rules that do it, and
every one of them was derived from this capture rather than assumed.

Only two of the source's four units were published. The transformation Linear
applies is per-field and identical across units, so two demonstrates it and
four would only have cost more scratch issues.

**The EN19 pair is not a capture.** The EN18 capture has no parent description,
so nothing live has yet shown how Linear stores the plan-level sections and the
Verification Contract block. The EN19 read-back applies the one transformation
EN18 measured and nothing else, and not inside code fences: whether Linear rewrites
there is unmeasured, and `materialize` leaves fenced text alone, so if it does the
first live publish fails `verify` rather than passing quietly. The first end-to-end publish should replace it
with a real `get_issue` capture; if Linear rewrites anything more, the golden
test in `tests/linear-plan/linear-plan.test.sh` is where it will show.
