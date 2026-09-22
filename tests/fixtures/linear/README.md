# Linear round-trip fixtures (EN18 U1)

Captured 2026-09-22 against a real Linear workspace (team `Emble`) by the EN18 U1
spike. These are not hand-written: `EN18-readback.json` holds the bytes Linear
actually returned. The scratch issues were cancelled afterwards, so this file is
the only remaining record of the round-trip.

| File | What it is |
|---|---|
| `EN18-sample-plan.md` | The source plan, copied verbatim from `docs/plans/completed/EN07-improvement_en-build-simplify-gate.md`. Its canonical hash is `40a510c0…`. |
| `EN18-readback.json` | What Linear returned for the parent and two sub-issues published from it. |

The point of the pair is that the second must be reducible to the first.
`skills/*/references/linear-plan-format.md` states the rules that do it, and
every one of them was derived from this capture rather than assumed.

Only two of the source's four units were published. The transformation Linear
applies is per-field and identical across units, so two demonstrates it and
four would only have cost more scratch issues.
