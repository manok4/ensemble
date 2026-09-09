# Pre-flight (`/en-build` steps 1 to 4)

What the build checks before it touches a branch: that the skill's own payload
arrived intact, which plan states are buildable, and how the plan-hash baseline
is set. `SKILL.md` keeps the four outcomes and the refusals; this file is read
when the build starts.

## The payload check

**Plugin-install preflight (fail-fast).** Confirm each of these exists. A partial install carrying only `SKILL.md` leaves peer review to degrade silently:

- `references/severity.md`
- `references/finding-schema.md`
- `$SKILL_DIR/scripts/ensemble-verify-peer-evidence`

If any are missing, **fail at start with a clear error** — do not proceed with a degraded build. Surface the exact paths missing and tell the user to re-run `/en-setup` or sync the plugin.

## Which plan states are buildable

**Pre-flight sub-state matrix** — read `peer_review_verdict` and the count of unresolved entries in `peer_review_resolutions:` (an entry is "unresolved" when its `status` is absent or anything other than `applied | deferred | disagreed | superseded`):

| status | verdict | unresolved findings | git tracked | Pre-flight action |
|---|---|---|---|---|
| `open` | `approve` | 0 | yes | Proceed to step 4a |
| `open` | `approve` | 0 | **no** | Offer auto-commit (one prompt), then proceed |
| `draft` | `revise` | 0 | yes or no | **Offer finalize-and-build:** one prompt to re-run the peer pass via `/en-plan`'s finalize loop, on `approve` flip to `open`, auto-commit, then proceed |
| `draft` | `revise` | > 0 | any | Refuse; list the unresolved findings; ask the user to apply/defer/disagree first via `/en-plan --resume` |
| `open` | `null` | n/a | yes | Proceed (the plan was made with `/en-plan --no-peer`; no peer verdict expected) |
| `open` | `null` | n/a | **no** | Offer auto-commit, then proceed |
| `draft` | `null` | n/a | any | Refuse; peer review never ran. Suggest `/en-plan --resume <plan-path>`. |
| `draft` | `reject` | any | any | Refuse; user must take over. Surface `peer_review_resolutions:` for context. |
| `completed` / `abandoned` | any | any | any | Refuse |

**Legacy inference** (a plan with no `peer_review_verdict` field at all): read `references/build-legacy-plans.md`, which owns the inference table; it maps the old iteration-log signals onto the matrix above or refuses.

Recovery prompt (when offering finalize-and-build):

> Plan is in draft. Findings from the last peer review (verdict: revise) appear to be applied (resolutions: 8 applied, 0 deferred, 0 disagreed). I can finalize now: re-run the peer pass, flip to `open` on approve, and commit the plan. Then proceed with `/en-build`. (y / n / details)

Declining the offer at the prompt is how you skip it; `--finalize-only` runs finalize and stops without building.

## The plan-hash baseline

**4a. Plan-hash baseline.** If `peer_review_plan_hash` is present, record it as the build's baseline; the phase-boundary check will compare against it. If absent (legacy plan), compute one with `$SKILL_DIR/scripts/ensemble-plan-hash <plan-path>` and record it (but skip the boundary check this run; surface a notice). **Always use that helper — never canonicalize the fields yourself**, or the baseline and the boundary check will disagree and refuse a plan nobody edited.
