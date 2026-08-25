# The Outside Voice finalize loop: cost analysis and remedies

- **Written:** 2026-08-25
- **Scope:** cross-cutting — `en-plan`, `en-foundation`, `en-cross-review`, `en-review`, `en-build`
- **Prompted by:** the open question left by the `en-plan` review (D48)

---

## 1. What the loop actually is

On `verdict: revise`, the host applies findings, records them in `peer_review_resolutions:`, and **re-invokes the peer** with a `## Previous review context` section. It repeats until `approve` or the depth-aware cap.

| Depth | Re-loop cap | Total peer passes |
|---|---:|---:|
| Lightweight | 1 | 2 |
| Standard | 2 | 3 |
| Deep | 2 | 3 |

Each pass is a **separate CLI subprocess** (`claude -p` or `codex exec`), wrapped in `timeout` at `peer_timeout_seconds` (default **600**).

## 2. Measured facts

Built a real prompt with `bin/ensemble-build-peer-prompt` against `docs/plans/completed/EN04-improvement_hands-off-ship.md` (211 lines):

| Component | Bytes | ~tokens |
|---|---:|---:|
| Full peer prompt | 24,229 | **6,057** |
| — of which the artifact | 22,417 | 5,604 |
| — of which Ensemble scaffolding | 1,812 | 453 |

**The artifact is 93% of the prompt.** Ensemble's own framing is 453 tokens — already lean. A 380-line plan lands near 10K tokens per pass, re-sent in full on **every** iteration, plus a `## Previous review context` section that grows each time.

Other measured facts:

- The Claude peer runs `--max-turns 1` — **single-shot**, no agentic exploration. `codex exec` has no turn flag at all (EN10).
- Worst-case wall clock is `3 × 600s = 30 minutes` before the caps and timeouts bottom out.
- `skip_peer_below_lines: 50` and `skip_peer_on_lightweight: true` already exist and already work. The gap is not "peer runs too often" — it is "when it runs, it runs to the cap regardless of what it found."

## 3. Why passes 2 and 3 are suspect

Four mechanism-level reasons, none of which require telemetry to state:

**a. The re-loop is severity-blind.** It continues while `verdict == revise`, full stop. A pass-1 result of three `P3` advisories ("style preference", "consider doing X later") triggers exactly the same second full-artifact pass as a `P0` data-loss finding. `references/severity.md` already defines P0–P3 with clear semantics; the loop simply doesn't consult them.

**b. Re-review is whole-artifact, not delta.** Pass 2 re-reads the entire plan even though only the sections touched by applied findings changed. A single-shot peer therefore re-derives its whole assessment, most of which it already delivered in pass 1.

**c. Same-finding-twice suppression is itself the evidence.** `en-plan` carries a "do not re-flag" list, and escalates to "treat the cap as hit early" if a finding reappears a third time despite suppression. That machinery exists because **repeat findings were observed**. Diminishing returns are already an acknowledged property of the loop; the loop just isn't allowed to act on them until it has burned the passes.

**d. Verification and discovery are conflated.** Pass 2 does two jobs: *did the applied fixes land correctly* (cheap, narrow, high-value) and *what else is wrong* (expensive, broad, mostly a resample of pass 1). Only the first justifies a full pass, and it is the smaller of the two.

## 4. A separate finding: three skills bypass the peer infrastructure

`references/peer-model-policy.md` states plainly: *"`/en-review` is the only resolver."* That is true, and it is a problem, because three other skills invoke a peer directly:

| Skill | Invocation | Effort ladder | Fail-soft retry | `peer_decision` telemetry |
|---|---|---|---|---|
| `en-review` | `bin/ensemble-peer-invoke` | ✅ | ✅ | ✅ |
| `en-build` | delegates to `/en-review` | ✅ (inherited) | ✅ | ✅ |
| **`en-plan`** | `$PEER_CMD` direct | ❌ | ❌ | ❌ |
| **`en-foundation`** | `$PEER_CMD` direct | ❌ | ❌ | ❌ |
| **`en-cross-review`** | `$PEER_CMD` direct | ❌ | ❌ | ❌ |

Three consequences:

1. **No effort scaling.** A Lightweight 60-line plan with no risk signals runs its peer at the same effort as a destructive migration plan. The ladder that exists to prevent exactly this is not consulted.
2. **No fail-soft.** `en-plan` has no `flagdrift` classification and no bounded retry. A rejected flag fails the pass outright where `en-review` would degrade and continue.
3. **No telemetry — which is why the question in the title is unanswerable.** The `peer_decision` schema is emitted only by `en-review`. The skills that actually run the *finalize loop* emit nothing, so there is no record of how long a pass took or what iteration 2 added.

That third point matters most: **the measurement gap is structural, not incidental.**

## 5. Remedies

Ranked by payoff ÷ risk.

### Remedy 1 — Gate the re-loop on severity *(highest value, lowest risk)*

Re-invoke the peer only when pass N produced at least one finding at **P0 or P1**. On an all-P2/P3 result: apply what's cheap, record the rest, exit the loop, flip to `open`.

- **Saves:** the entire second pass on advisory-only reviews — likely the common case for a plan that was already drafted carefully.
- **Risk:** low. P2/P3 are defined as "apply if cheap, defer otherwise" and "note and move on"; neither warrants a verification round trip.
- **Cost:** a conditional and a config key (`reloop_min_severity`, default `P1`).

### Remedy 2 — Scope re-review to the delta

On pass ≥ 2, send the **resolutions** plus a **diff of what changed**, not the whole artifact again, and instruct: *verify the applied fixes address their findings; raise new findings only in changed regions or where a fix has downstream effects.*

- **Saves:** ~60–80% of input tokens per re-pass, and sharpens the task.
- **Honest caveat:** this is primarily a **cost** and **focus** win, not a latency win. Inference time is driven more by reasoning than input length, so do not expect it to halve wall clock.
- **Risk:** medium. A fix in one section can break another. Mitigate by keeping the full artifact attached but marking the delta as the review scope.

### Remedy 3 — Route `en-plan` / `en-foundation` / `en-cross-review` through `bin/ensemble-peer-invoke`

Adopt what `en-review` already has: the effort ladder, `flagdrift` fail-soft, and `peer_decision` emission.

- **Saves:** real effort scaling on low-risk artifacts; removes a whole class of hard failure.
- **Risk:** low — the infrastructure exists, is tested, and has a defined schema. This is wiring, not design.
- **Bonus:** it is the precondition for Remedy 4.

### Remedy 4 — Instrument, then answer the question with data

Extend `peer_decision` with `iteration`, `duration_ms`, `findings_by_severity`, and `new_findings_this_iteration`. Log one line per pass.

After a few dozen real runs you can answer directly: *what fraction of pass-2 findings are new and ≥P1?* If it is small, cut Standard's cap to 1 and keep 2 only for Deep or `risk: destructive`. If it is large, the loop is earning its keep and Remedy 1 is the only change needed.

- **This is the actual answer to "no data answers it."** It is cheap, and it converts a standing argument into a measurement.

### Remedy 5 — Short-circuit on an unchanged plan hash

`peer_review_plan_hash` already exists and is already computed, but is used only by `en-build` to detect mid-build plan mutation. On `/en-plan --resume` over an unchanged plan, the full peer loop re-runs.

Skip the peer when the recomputed hash matches the stored one and the previous verdict was `approve`.

- **Risk:** very low. Same input, same reviewer, same verdict.

### Remedy 6 — Right-size the timeout per artifact type

600s per pass is calibrated for a large branch diff. A single-shot review of a bounded plan file does not need it. A per-artifact-type default (plan/foundation ~180s; diff/branch 600s) cuts the pathological worst case from 30 minutes to under 10.

- **Risk:** low, but it is a real trade — a slow peer under load could be cut off. Make it config-visible.

## 6. Recommended sequence

1. **Remedy 3** (wiring) → unlocks Remedy 1 and Remedy 4 cleanly.
2. **Remedy 1** (severity gate) → the immediate latency win.
3. **Remedy 4** (instrumentation) → makes the cap question empirical.
4. **Remedy 5**, **Remedy 6** → cheap cleanups.
5. **Remedy 2** → last, and only if Remedy 4 shows re-passes are worth keeping at all. If the data says cut Standard to one re-loop, Remedy 2's complexity may never be needed.

**The honest framing:** Remedy 1 and Remedy 5 are safe on reasoning alone. Remedy 2 and any change to the caps themselves should wait for Remedy 4, because the argument that passes 2–3 underperform is *mechanistically plausible and currently unproven*.

---

## 7. Applied (D49)

Three of the six landed. `./tests/run.sh` 60/60 green; `ensemble-lint --scope docs` exit 0.

| Remedy | Status |
|---|---|
| Remedy 1 — severity-gated re-loop | **applied** |
| Remedy 3 — unified peer invocation | **applied** |
| Cap 2→1 re-loop (beyond Remedy 1) | **applied** — review, apply, one verification pass |
| Remedy 2 — delta-scoped re-review | not done; may be unnecessary now the cap is 1 |
| Remedy 4 — instrumentation | not done; routing through `ensemble-peer-invoke` makes `peer_decision` available as the hook |
| Remedy 5 — plan-hash short-circuit | not done |
| Remedy 6 — per-artifact timeout | not done; the cap change already halves the worst case |

**A note on Remedy 4.** The analysis argued for measuring before changing the caps. That was overridden deliberately: the cap change is defensible on the mechanism alone (the suppression list is itself evidence of repeat findings), and waiting for telemetry that does not exist yet would have blocked a safe change indefinitely. Remedy 4 is still worth doing — it is now cheaper, because all four peer-invoking skills emit `peer_decision`.

**Lint caught this document.** The remedies were originally labelled with a bare `R`-plus-number prefix, which is Ensemble's requirement-ID shape — `bin/ensemble-lint` read all six as citations into `foundation.md §5` and flagged them as broken. Renamed to `Remedy N`. Worth recording twice over: the doc lint applies to review documents too, and the first attempt at *describing* this fix reintroduced the same prefix and failed lint again.
