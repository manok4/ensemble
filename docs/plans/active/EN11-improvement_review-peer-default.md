---
type: plan
plan_type: improvement
plan_id: EN11
title: Default-on cross-agent peer review in /en-review with two-source reconciliation and a risk-tiered peer model/effort policy
status: in_progress
location: active
created: 2026-07-27
shipped:
deepened:
covers_requirements: []
requirements_pending: false
related_design:
peer_review_verdict: revise
peer_review_iterations: 3
peer_review_last_run: 2026-07-27
peer_review_plan_hash: 036d65286465665adfa40cf1feb46f584b93bbaa12576b84c74d1cabc7c0c915
peer_review_cap_hit: true
peer_review_resolutions:
  - finding_id: EN11-PR-001
    iteration: 1
    severity: P1
    title: Effort precedence can assign low effort to high-risk reviews
    status: applied
    rationale: ""
    location: U1 Approach, references/peer-model-policy.md risk ladder
  - finding_id: EN11-PR-002
    iteration: 1
    severity: P1
    title: The promised fail-soft flag policy has no executable fallback path
    status: applied
    rationale: ""
    location: U1 fail-soft rule, U2 binding helper, U3 invocation layer
  - finding_id: EN11-PR-003
    iteration: 1
    severity: P1
    title: The reconciliation result cannot represent corroborated provenance deterministically
    status: applied
    rationale: ""
    location: U5 Approach and references/finding-schema.md changes
  - finding_id: EN11-PR-004
    iteration: 1
    severity: P2
    title: The effort override resolution order has no clear owner or user-facing flag implementation
    status: applied
    rationale: ""
    location: U1 resolution order, U2 helper interface, U3 Flags table
  - finding_id: EN11-PR-005
    iteration: 1
    severity: P2
    title: Concurrent dispatch depends on an invariant established by a later undeclared unit
    status: applied
    rationale: ""
    location: U4 Dependencies and Approach
  - finding_id: EN11-PR-006
    iteration: 2
    severity: P1
    title: The fail-soft retry remains prose-only and cannot support the promised behavioral tests
    status: applied
    rationale: ""
    location: U3 Files and Test scenarios; U6 Approach
  - finding_id: EN11-PR-007
    iteration: 2
    severity: P1
    title: Conflict detection does not define global consumption or precedence against corroboration matching
    status: applied
    rationale: ""
    location: U5 Approach, Deterministic grouping and Conflict detection
  - finding_id: EN11-PR-008
    iteration: 2
    severity: P2
    title: The peer_decision schema contradicts itself and never enumerates its closed reasons
    status: applied
    rationale: ""
    location: Technical design Stage 2 and Key interfaces; U3 Approach and Test scenarios
  - finding_id: EN11-PR-009
    iteration: 2
    severity: P2
    title: The model_alias configuration key has no defined resolution or call-site path
    status: applied
    rationale: ""
    location: U1 Approach sections (b) and config keys; U2 interface; U3 Approach
  - finding_id: EN11-PR-010
    iteration: 3
    severity: P1
    title: Flat keys do not provide a safe YAML parsing contract
    status: applied
    rationale: ""
    location: U9 Approach and Error / failure path
  - finding_id: EN11-PR-011
    iteration: 3
    severity: P1
    title: Unset and semantically invalid values can defeat fail-soft precedence
    status: applied
    rationale: ""
    location: U9 Approach; U1(b); U3 resolver paragraph
  - finding_id: EN11-PR-012
    iteration: 3
    severity: P1
    title: Setup merge does not fully specify preservation and atomic-failure behavior
    status: applied
    rationale: ""
    location: U9 setup merge paragraph and Integration test
  - finding_id: EN11-PR-013
    iteration: 3
    severity: P2
    title: U9 dependency and setup ownership contradict its build-order claim
    status: applied
    rationale: ""
    location: U1 Files and config test; U9 Dependencies and build order note; U3 Dependencies
depth: standard
data_scale: small
---

# EN11 — Default-on cross-agent peer review in `/en-review` with two-source reconciliation and a risk-tiered peer model/effort policy

## Context

`/en-review` defaults to host personas only. The cross-agent peer is opt-in behind `--peer`, so a direct `/en-review` on code the host just wrote is same-stack review: the persona sub-agents are fresh-context, but they share the host's weights and blind spots. Field evidence from this repo's own recent builds is one-sided, EN09's 6 guardrail parser bypasses and EN10's 4 findings were **all** peer-only, none surfaced by a host persona.

Separately, the peer call site is `$PEER_CMD $PEER_FORMAT $PEER_TURNS "$prompt"` with no model and no effort flag, so it silently inherits the operator's interactive CLI defaults. On the author's machine `~/.codex/config.toml` sets `model_reasoning_effort = "high"`, so every Codex peer review Ensemble fires today runs at high effort by accident rather than by decision.

This plan flips the default, adds an explicit `--no-peer`, replaces the flat finding merge with a two-source reconciliation that distinguishes independent corroboration from same-stack agreement, and puts the peer's model and reasoning effort under an explicit, drift-resistant policy.

## Requirements covered

No numbered foundation R-IDs apply. This is a skill-behavior improvement on `/en-review`, consistent with prior meta-plans (EN07, EN08) which also carried `covers_requirements: []` with `requirements_pending: false`.

## Out of scope for this plan

- Changing `/en-build`'s post-build phase. It already passes `--peer-only` explicitly and is unaffected by the default flip.
- Changing `--peer-only` semantics.
- Feeding host persona findings to the peer. The peer is and stays blind (see U5).
- Any change to `references/severity.md`'s action matrix or the EN08 mutation boundary.
- A native cost/latency benchmark harness. Token deltas are recorded via the existing `~/.ensemble/analytics/review.jsonl`, not a new tool.
- Model selection for the host persona agents. They already pin `model: sonnet` in `agents/*.md` and are out of scope.

## Approach (high-level)

Three layers, deliberately separated so the volatile part can churn without touching the stable part. This is the `references/cli-wrappers.md` pattern that EN10 proved out: when a CLI literal was scattered across nine files, a single upstream flag removal cost a whole plan to repair. Model IDs are the same hazard, so no concrete model ID is allowed to appear in skill prose.

**Policy** (`references/peer-model-policy.md`, new) owns the stable risk ladder: which situation earns which reasoning-effort tier. It changes only when the review philosophy changes.

**Binding** (`bin/ensemble-peer-flags`, new) owns the volatile per-CLI syntax: it takes a tier and prints the flag fragments for the detected peer. Claude gets a tier alias that auto-resolves to the latest model of that tier plus `--effort <tier>`. Codex gets **no** `-m` at all, inheriting the operator's configured model, with Ensemble overriding only `-c model_reasoning_effort=<tier>`. Concrete model IDs like `gpt-5.6-sol` go stale every vendor release, so Ensemble never stores one.

**Call sites** read `$PEER_MODEL` and `$PEER_EFFORT` and never a literal.

On top of that, `/en-review` flips its default: when a real cross-agent peer exists and the mode permits, personas and the peer both run, dispatched concurrently (the peer is blind, so nothing orders it after the persona batch), and their two result sets are reconciled into four explicit buckets instead of being flattened into one pool.

## Technical design

Four components and a four-stage data flow, so the cross-cutting shape is worth sketching before the units.

```
                 ┌──────────────────────────────────────────────┐
 STAGE 1         │ bin/ensemble-detect-host  (existing)         │
 detect          │   -> PEER_MODE, PEER_CMD, PEER_AVAILABLE     │
                 └────────────────────┬─────────────────────────┘
                                      v
 STAGE 2         ┌──────────────────────────────────────────────┐
 classify        │ /en-review  (steps 3,4,7,7a)                 │
 + resolve       │   mode + is_small_and_safe + fired personas  │
 (SOLE OWNER     │   -> peer_decision {on|off|degraded, reason} │
  of precedence) │   -> ONE final effort tier, resolved via     │
                 │      --effort > repo cfg > user cfg > ladder │
                 └────────────────────┬─────────────────────────┘
                                      v
 STAGE 3         ┌──────────────────────────────────────────────┐
 dispatch        │ ONE parallel batch:                          │
 (concurrent)    │   Agent(persona) x N   ──┐                   │
                 │   peer subprocess:       │                   │
                 │     $PEER_CMD $PEER_FORMAT $PEER_TURNS \     │
                 │     $PEER_MODEL $PEER_EFFORT "$prompt"       │
                 │        ^ bin/ensemble-peer-flags (pure       │
                 │          translator: tier -> CLI syntax,     │
                 │          reads no config)                    │
                 │   on flagdrift: ONE retry minus the          │
                 │   rejected fragment, else persona-only       │
                 └────────────────────┬─────────────────────────┘
                                      v
 STAGE 4         ┌──────────────────────────────────────────────┐
 reconcile       │ references/persona-dispatch.md Synthesis     │
                 │   host_set  x  peer_set                      │
                 │   -> corroborated | peer-only |              │
                 │      host-only | conflicting                 │
                 └──────────────────────────────────────────────┘
```

**Key interfaces.**

`bin/ensemble-peer-flags --effort <low|medium|high> [--peer-cmd <cmd>]` prints two eval-able shell-escaped lines, matching the existing `bin/ensemble-detect-host` emission contract:

```
PEER_MODEL='--model sonnet'                       # claude peer
PEER_EFFORT='--effort medium'
```
```
PEER_MODEL=''                                     # codex peer: inherit operator's model
PEER_EFFORT='-c model_reasoning_effort="medium"'
```

`peer_decision` is a resolved struct carried into the report, not recomputed:

```json
{"peer": "on"|"off", "reason": "<enum>", "peer_mode": "cross-agent|single-agent-fallback|off", "effort": "low|medium|high"}
```

**Bucket contract.** Reconciliation is a set operation over `(location, title-similarity >= 0.7)` pairs, the same match predicate the existing persona dedup already uses, applied across sources rather than within one pool.

## Decisions, assumptions & risks

- **Decision:** Effort floor is **medium** for an ordinary code diff, with `low` reserved for lite-gated or small-and-safe diffs. Review is a recall problem and the findings that justify having a peer at all are the subtle ones, so bottoming out at `low` would erode the very capability being paid for. Settled with the user this session.
- **Decision:** Claude peer pins a **tier alias**, Codex peer pins **nothing** and inherits the operator's model. Claude aliases auto-resolve to the latest model of a tier, so an alias is drift-free; Codex takes concrete IDs which go stale every vendor release. Ensemble therefore never stores a concrete model ID.
- **Decision:** `report-only` never runs a peer, even when one is available. `/en-sweep` calls `/en-review` in that mode inside CI, and D38 deliberately keeps API secrets and repo-write off CI.
- **Alternative:** Feed host persona findings to the peer so it can confirm or counter them, as `references/persona-dispatch.md` currently (incorrectly) describes. Rejected: anchoring the peer on host findings turns independent discovery into confirmation, and overlap then stops being evidence of anything. Blindness is the property that makes the corroborated bucket meaningful.
- **Alternative:** Low-effort first, escalate to high only on a P0/P1 hit. Rejected for v1: expected cost is attractive since most reviews are clean, but a review that finds something pays for two peer calls and roughly doubles latency, and the added branch complicates the mandatory outcome line. Revisit if measured cost justifies it.
- **Alternative:** Default peer on for `single-agent-fallback` too. Rejected: `/en-review`'s personas are already fresh-context instances of the host stack, so an extra same-model subprocess adds cost without adding an independent perspective. The calculus differs in `/en-build`, where the alternative is the host reviewing its own inline work, which is why that path keeps the fallback.
- **Assumption:** `claude --model <alias>` continues to resolve aliases to the latest model of that tier (verified against `claude --help` on 2.1.219). Falsified by a future release dropping alias support, which U2's fail-soft branch degrades rather than breaks, and U6's helper test would surface.
- **Risk (latency):** Default-on peer makes every `/en-review` a subprocess-blocking operation. **Mitigation:** U4's concurrent dispatch hides the latency behind the persona batch; if it still bites, the knob is lowering `peer_timeout_seconds` for interactive runs rather than re-defaulting peer off.
- **Risk (unmeasured cost):** The token/latency delta of a default-on peer is **not measured**. **Mitigation:** the documented persona-roster cost is 15K to 40K per review; the peer add is one additional call at a pinned tier. Instrument via the existing `~/.ensemble/analytics/review.jsonl` (`findings_count`, `filtered_count`) before tuning the ladder further, rather than guessing now.
- **Risk (drift recurrence):** A future contributor re-adds a hardcoded model ID at a call site, recreating EN10's flag-drift failure mode one layer up. **Mitigation:** U6's drift test greps call sites for model-ID-shaped literals, with the pattern self-tested per EN10-CR-003.

## Implementation units

Each unit has a stable U-ID. Never renumbered after assignment.

### U1. Peer model/effort policy reference and config keys

- **Goal:** Establish the stable risk ladder and its config surface as the single source of policy truth.
- **Requirements covered:** none (skill-behavior improvement)
- **Dependencies:** none
- **Files:** `references/peer-model-policy.md` (new), `references/doc-lints.md` (register the new reference in the pointer map if applicable). **No `setup` edits: U9 owns the entire config block** (EN11-PR-013), so the two units never touch the same code.
- **Approach:** Write `references/peer-model-policy.md` defining four things.

  **(a) The effort ladder, as an ordered first-match cascade.** Evaluation order is fixed and `high` is tested first, so a diff that satisfies more than one condition always resolves to the strongest:

  | Order | Tier | Condition |
  |---|---|---|
  | 1 | `high` | `security-reviewer` or `migrations-reviewer` fired, OR an architectural trigger is present, OR the unit is `risk: destructive` or `gated: true` |
  | 2 | `low` | `is_small_and_safe` is `true` per `references/diff-signal-detection.md` |
  | 3 | `medium` | otherwise (the floor) |

  Ordering `high` first is belt-and-braces rather than redundant: `is_small_and_safe` already requires `RISK_SIGNALS` to be empty and no conditional persona to have fired, so security and migrations cannot collide with `low`, but the **architectural**, **destructive**, and **gated** conditions are *not* inputs to `is_small_and_safe` and genuinely could. A small, signal-free diff on a `gated: true` unit must still resolve `high`.

  **(b) The resolution order and its single owner.** `/en-review` is the **only** resolver. It evaluates, first hit wins, the `--effort` flag, then the config layers **via `bin/ensemble-config-get` (U9)**, which owns the repo-then-global cascade, then the ladder above, producing **one final tier**. `bin/ensemble-peer-flags` is a pure translator: it accepts that already-resolved tier and never reads config itself, so precedence exists in exactly one place and is testable there. Config keys are **flat**, matching the seven existing keys: `review_peer_effort_override` and `review_peer_model_alias`.

  **(c) The model-binding rule:** alias for Claude, inherit for Codex, with an explicit prohibition on storing a concrete model ID anywhere in Ensemble. **`review_peer_model_alias` resolves through the same owner and the same chain as effort** (EN11-PR-009): `/en-review` reads it via `bin/ensemble-config-get` (U9), falls back to the documented default alias, and forwards the result to `bin/ensemble-peer-flags --model-alias <alias>`. There is deliberately no `--model` CLI flag on `/en-review` (model choice is an operator setting, not a per-run one), and the resolved alias is **ignored entirely** on a Codex peer, which inherits the operator's model by design. So the key is never silently unused: it governs on Claude and is documented as inert on Codex.

  **(e) The `peer_decision` schema and its closed reason enum** (EN11-PR-008), published here once and consumed verbatim by U3 and U6 so there is one definition to drift from:

  ```json
  {"peer": "on" | "off" | "degraded",
   "reason": "<enum>",
   "peer_mode": "cross-agent" | "single-agent-fallback" | "off",
   "effort": "low" | "medium" | "high",
   "model_alias": "<alias>" | null}
  ```

  `peer: "degraded"` is the canonical representation of a successful-but-reduced peer run (the diagram and the JSON agree on three states). Complete `reason` enum:

  | `peer` | `reason` values |
  |---|---|
  | `on` | `default-on` , `explicit-flag` |
  | `off` | `no-peer-flag` , `single-agent-fallback` , `report-only-mode` , `recursion-guard` , `peer-unavailable` , `auto-skip:diff-below-threshold` , `auto-skip:lightweight-depth` , `peer-failed:auth` , `peer-failed:timeout` , `peer-failed:unknown` , `peer-failed:retry-exhausted` |
  | `degraded` | `dropped-model-fragment` , `dropped-effort-fragment` |

  **(d) The fail-soft rule and its owner.** Degradation is handled at the **invocation layer** (`/en-review` step 9, U3), not in the translator. On a peer invocation that fails, the classifier from `bin/ensemble-cli-smoke` (EN10, reused rather than duplicated) distinguishes a rejected flag from an auth or transport failure. A `flagdrift` classification triggers a **bounded single retry** that drops **only** the rejected fragment (`PEER_MODEL` or `PEER_EFFORT`, not both, not the prompt), so the peer degrades to inherited defaults and the review still gets its cross-agent pass. The degraded outcome is recorded in `peer_decision.reason`, never silently swallowed. Any other classification is an ordinary peer failure and falls back to persona-only.

  The policy **names** the two settings, `review_peer_model_alias` and `review_peer_effort_override`, both unset by default so the ladder governs. Writing them into `~/.ensemble/config.json` and delivering them to existing installs is entirely **U9's** concern (EN11-PR-013), since `setup`'s current `[ ! -f ]` guard would otherwise leave every already-configured machine without them.
- **Risk:** low
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Patterns to follow:** `references/cli-wrappers.md` (single-source-for-volatile-literals); `docs/foundation.md` D44 (the EN10 flag-drift lesson this generalizes)
- **Test scenarios:**
  - *Happy path:* `references/peer-model-policy.md` exists and names all three tiers plus the four resolution-order layers in order; a drift test asserts each tier string and the ordered layer list are present.
  - *Edge case (combined signals, EN11-PR-001):* The policy states `high` is evaluated first. A drift test asserts the ladder table lists `high` above `low`, and asserts the stated resolution for each combined case: small-and-safe **plus** `gated: true` resolves `high`; small-and-safe plus an architectural trigger resolves `high`; small-and-safe plus `risk: destructive` resolves `high`; small-and-safe alone resolves `low`.
  - *Edge case (naming):* The policy names both settings in their flat form (`review_peer_effort_override`, `review_peer_model_alias`) and states both are unset by default; a drift test asserts the flat spelling so the doc cannot drift back to a dotted form that no reader supports. Config-file delivery is asserted in U9, not here.
  - *Error / failure path:* The policy file must state the fail-soft rule, name `bin/ensemble-cli-smoke`, assign degradation to the invocation layer, and specify the single bounded retry that drops only the rejected fragment; a drift test fails if the policy describes erroring the whole review instead of degrading.
  - *Integration:* The policy file's low-tier condition must cite `is_small_and_safe` verbatim so it cannot drift from `references/diff-signal-detection.md`; a drift test greps both files for the shared identifier. The policy must also name `/en-review` as the sole resolver and state that `bin/ensemble-peer-flags` never reads config.
- **Verification:** `bin/ensemble-lint --scope docs/` clean; new drift assertions pass; `bash -n setup` valid.

### U2. `bin/ensemble-peer-flags` binding helper

- **Goal:** One executable owns the per-CLI model/effort syntax so no call site holds a literal.
- **Requirements covered:** none
- **Dependencies:** U1
- **Files:** `bin/ensemble-peer-flags` (new), `references/host-detect.md` (document the helper and the two emitted variables), `references/cli-wrappers.md` (add the model/effort rows to the Claude and Codex flag tables)
- **Approach:** New POSIX-shell helper accepting an **already-resolved** `--effort <low|medium|high>` plus an optional `--peer-cmd <cmd>` (defaulting to `$PEER_CMD`, or resolving via `bin/ensemble-detect-host` when unset) and an optional `--model-alias <alias>` passed in by the caller. **The helper is a pure translator: it never reads `~/.ensemble/config.json`, `.ensemble/config.local.yaml`, or the ladder.** All precedence lives in `/en-review` per U1(b), so this unit only maps a tier onto per-CLI syntax and there is exactly one place where precedence can be wrong. Emit `PEER_MODEL` and `PEER_EFFORT` as shell-escaped `KEY='value'` lines using the same `shellesc` contract `bin/ensemble-detect-host` already uses, so consumers `eval` both emissions identically. Claude branch emits `--model <alias>` (default mid tier when `--model-alias` is omitted) and `--effort <tier>`. Codex branch emits an **empty** `PEER_MODEL` and `-c model_reasoning_effort="<tier>"`. Unknown peer command emits both empty and exits 0, so an unrecognized future CLI degrades to inherit-everything rather than breaking review.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Patterns to follow:** `bin/ensemble-detect-host` (shellesc + eval-able emission); `bin/ensemble-cli-smoke` (sourceable, errexit-safe, no top-level side effects)
- **Test scenarios:**
  - *Happy path:* `--effort medium --peer-cmd "claude -p"` emits `PEER_MODEL='--model <alias>'` and `PEER_EFFORT='--effort medium'`; `--effort medium --peer-cmd "codex exec"` emits `PEER_MODEL=''` and `PEER_EFFORT='-c model_reasoning_effort="medium"'`.
  - *Edge case:* `--effort high` and `--effort low` produce the corresponding tier in both branches; an unknown `--peer-cmd "futurecli run"` emits both variables empty and exits 0.
  - *Error / failure path:* A missing `--effort` exits non-zero with a usage message; an invalid tier such as `--effort turbo` exits non-zero and does not emit partial output.
  - *Integration:* `eval "$(bin/ensemble-peer-flags --effort medium --peer-cmd 'codex exec')"` round-trips under `set -u` without unbound-variable errors, and the emitted `PEER_EFFORT` survives with its embedded quotes intact (the shellesc contract).
  - *Integration (purity, EN11-PR-004):* Running the helper with a `~/.ensemble/config.json` containing `review_peer_effort_override: "high"` and `--effort low` still emits the `low` tier, proving the helper does not resolve config and that precedence lives solely in `/en-review`.
- **Verification:** New `tests/lint/en-review-peer-default.test.sh` assertions pass with stub PATH isolation (the EN10 `mkstub` hermetic pattern); `bash -n bin/ensemble-peer-flags`; full suite green.

### U3. `/en-review` default-on peer, `--no-peer`, and mode scoping

- **Goal:** Peer runs by default when a real cross-agent peer exists and the mode permits, with an explicit opt-out.
- **Requirements covered:** none
- **Dependencies:** U1, U2, U8, U9
- **Files:** `skills/en-review/SKILL.md` (steps 2, 3, 9; Flags table)
- **Approach:** Add a peer-decision resolution step producing the `peer_decision` struct. On by default when `PEER_MODE=cross-agent` **and** mode is `interactive` or `headless`. Off when `--no-peer` is passed, when `PEER_MODE=single-agent-fallback` (the personas are already fresh-context host instances, so a redundant same-model subprocess is not worth defaulting on; `--peer` still opts in), when mode is `report-only`, or when the existing `ENSEMBLE_PEER_REVIEW=true` recursion guard is set. **`report-only` is off unconditionally**: `/en-sweep` invokes `/en-review` in that mode inside CI, and D38 deliberately keeps API secrets and peer CLI credentials off CI, so a naive default-flip would silently require them. Honor the existing `skip_peer_below_lines` and `skip_peer_on_lightweight` config keys rather than inventing new ones. Add `--no-peer` to the Flags table (naming already consistent with `/en-plan`), and keep `--peer` accepted as a back-compat no-op when the default already turned it on.

  **This step is the sole resolver (U1(b), U1(c)).** It walks the precedence chain for the effort tier (`--effort` flag, then `bin/ensemble-config-get review_peer_effort_override`, then the ladder) and for the model alias (`bin/ensemble-config-get review_peer_model_alias`, then the default alias), producing one final tier and one alias, and passes both to `bin/ensemble-peer-flags`. The repo-then-global cascade inside each config lookup belongs to **U9's reader**, not to this step, so there is one implementation of layering rather than one per consumer. Add **`--effort <low|medium|high>`** to the Flags table so the highest-precedence layer is actually reachable by a user.

  **Invocation and degradation are delegated to `bin/ensemble-peer-invoke` (U8), not restated here.** EN11-PR-006: the retry state machine must be executable to be testable, so this step *calls* the helper and consumes its `peer_decision` result rather than describing the algorithm in prose. The skill's job is resolution and reporting. Emit a mandatory one-line `peer_decision:` outcome in every summary using the U1(e) schema and its closed reason enum verbatim, following the EN08 `lite_gate:` precedent so neither a skip nor a degradation is ever silent.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Patterns to follow:** `docs/foundation.md` D42 (mandatory outcome line, fail-closed, never a silent override); D38 (CI stays read-only and secret-free)
- **Test scenarios:**
  - *Happy path:* The skill text states peer is on by default for `cross-agent` + `interactive`/`headless`, and the Flags table lists both `--no-peer` and `--effort <low|medium|high>`.
  - *Edge case:* The skill states `single-agent-fallback` defaults peer **off** with `--peer` as the opt-in, and that `--peer` is a back-compat no-op when peer is already on.
  - *Error / failure path (delegation, EN11-PR-006):* A drift test asserts step 9 **calls** `bin/ensemble-peer-invoke` and does not restate the retry algorithm, so the executable helper stays the single implementation. The retry behavior itself is proven by U8's behavioral tests, not by asserting on this prose.
  - *Error / failure path (CI posture):* A drift test fails if `report-only` is described anywhere as running a peer by default, guarding the D38 CI posture; the recursion-guard override is still stated.
  - *Integration (effort precedence, EN11-PR-004):* The precedence chain is asserted end to end: `--effort high` on a small-and-safe diff yields `high` (flag beats ladder); with no flag, a repo `config.local.yaml` value beats a `~/.ensemble/config.json` value; with neither, the ladder governs.
  - *Integration (model_alias precedence, EN11-PR-009):* A configured `review_peer_model_alias` reaches `bin/ensemble-peer-flags` and appears in `PEER_MODEL` on a Claude peer; repo config beats user config (via U9's reader); with neither set the documented default alias is used; and on a Codex peer the resolved alias is ignored and `PEER_MODEL` stays empty.
  - *Integration:* The `peer_decision:` outcome line is documented as mandatory and uses the U1(e) schema and enum verbatim; the skill still references `skip_peer_below_lines` / `skip_peer_on_lightweight` rather than new keys.
- **Verification:** Drift assertions pass; `bin/ensemble-lint` clean; full suite green.

### U4. Concurrent peer dispatch

- **Goal:** Hide peer latency behind the persona batch instead of adding to it.
- **Requirements covered:** none
- **Dependencies:** U3, U5
- **Files:** `skills/en-review/SKILL.md` (step 8, and step 9's dispatch paragraph only), `references/persona-dispatch.md` (Parallel dispatch section only)
- **Approach:** Because the peer is blind to persona findings there is no ordering dependency, so the peer subprocess is fired in the **same** parallel batch as the `Agent` persona calls rather than serially after them. Restate step 9's dispatch as a participant in the step 8 batch, keeping its own failure handling. **Depends on U5** (EN11-PR-005): concurrency is only safe *because* of the blind-peer invariant, so U5 must land first or an intermediate commit would document concurrency whose justification does not yet exist. To keep the two units from colliding on the same prose, ownership of the overlapping files is split explicitly: **U5 owns** the Synthesis / reconciliation and Outside Voice sections of `references/persona-dispatch.md` plus `/en-review` step 10; **U4 owns** the Parallel dispatch section plus step 8 and step 9's dispatch paragraph. This matters because `peer_timeout_seconds` defaults to 600, and a serial peer would add that worst case to every default review.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Patterns to follow:** `references/persona-dispatch.md` Parallel dispatch (single message, multiple calls)
- **Test scenarios:**
  - *Happy path:* Skill and reference both describe the peer as dispatched in the same batch as the personas; a drift test asserts neither file describes the peer as running "after" the persona batch completes.
  - *Edge case:* A peer failure or timeout inside the concurrent batch still degrades to persona-only findings with a recorded reason, and does not discard already-returned persona results.
  - *Error / failure path:* The documented failure protocol covers peer timeout within the batch and states the review still completes.
  - *Integration:* The concurrency rationale explicitly cites peer blindness, so the two units stay coupled in the docs.
- **Verification:** Drift assertions pass; `bin/ensemble-lint` clean.

### U5. Two-source reconciliation and the blind-peer invariant

- **Goal:** Replace the flat merge with four explicit buckets, and correct the doc that claims the peer sees host findings.
- **Requirements covered:** none
- **Dependencies:** U3
- **Files:** `references/persona-dispatch.md` (Synthesis and Optional Outside Voice sections only; the Parallel dispatch section belongs to U4), `references/finding-schema.md` (add `source` on findings plus the reconciliation-record shape), `skills/en-review/SKILL.md` (step 10 only)
- **Approach:** Tag every raw finding with `source: host|peer`, then reconcile into a distinct **reconciliation record** rather than mutating findings in place (EN11-PR-003, a single `source` enum cannot express a corroborated pair). The record carries provenance for both sides:

  ```json
  {"bucket": "corroborated|peer-only|host-only|conflicting",
   "sources": ["host", "peer"],
   "canonical": {"<the presented finding>"},
   "contributing": [{"source": "host", "finding_id": "..."},
                    {"source": "peer", "finding_id": "..."}],
   "confidence": 9, "conflict": false}
  ```

  **One global reconciliation algorithm (EN11-PR-007).** Conflict and corroboration are two stages of a *single* pass over a shared consumption pool, with a fixed order, so the four buckets always partition the input:

  1. **Conflict stage first.** Within each `location`, enumerate cross-source pairs whose claims are contradictory, ordered by ascending `(host finding_id, peer finding_id)`. Greedily allocate each pair to a `conflicting` record, **consuming both members**. Conflict runs first because a contradiction is the more consequential classification and must not be masked by a similarity match.
  2. **Corroboration stage on the remainder.** Among findings not consumed in stage 1, order cross-source candidate pairs within a `location` by descending title-similarity (`>= 0.7`), greedily match one-to-one, and consume both members.
  3. **Singles.** Every finding still unconsumed becomes a `host-only` or `peer-only` record.

  Ties break on ascending `finding_id` at every stage, so the result is stable across runs. `canonical` selection is the highest-severity then highest-confidence then host-source member, so the presented text is deterministic.

  **Partition invariant (asserted, not assumed):** every raw finding contributes to **exactly one** reconciliation record. A finding can never be both corroborated and conflicting, and none may be dropped. The count of `contributing[]` entries across all records must equal the count of raw findings.

  **Why conflict detection cannot key off the similarity predicate.** Two findings at the same `location` whose claims are incompatible are frequently *dissimilar* in title, so reusing the `>= 0.7` corroboration predicate for conflict would systematically miss them. Conflict is therefore evaluated on contradictory assertions at a shared `location` regardless of similarity.

  **Bucket semantics.** **corroborated** (host and peer, confidence `+2`, because two independent architectures agreeing is materially stronger evidence than two same-stack personas agreeing), **peer-only** (surfaced prominently, empirically where the value has been), **host-only** (normal ranking, skews to standards/testing/maintainability where project context beats fresh eyes), **conflicting** (both surfaced, `conflict: true`, never auto-applied). The existing same-source `+1` overlap boost is unchanged and the cap of 10 still applies; the `+2` applies only across sources. The codebase already establishes that not all agreement is equal, `fast-pass` findings are explicitly barred from corroboration promotion, and that carve-out is preserved.

  Separately, **correct the doc drift**: `references/persona-dispatch.md` currently claims the peer reads the persona findings "so it can confirm or counter them", but `bin/ensemble-build-peer-prompt` has no such flag and `/en-review` never passes them, so the peer is blind in the implementation. Blind is correct, anchoring the peer on host findings would destroy the independence that makes corroboration meaningful, so the fix is to correct the prose and state peer-blindness as an explicit named invariant rather than to build the described feature.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** pragmatic
- **Patterns to follow:** existing dedup predicate in `references/persona-dispatch.md` Synthesis; the `fast-pass` corroboration carve-out as precedent
- **Test scenarios:**
  - *Happy path:* All four bucket names appear in `references/persona-dispatch.md`, and `references/finding-schema.md` documents `source` on findings plus the reconciliation record with its `sources[]` and `contributing[]` fields.
  - *Edge case (provenance, EN11-PR-003):* A corroborated record is documented as carrying **both** sources in `sources[]` (not a single `source` enum), with a stated `canonical` selection rule; the doc gives a worked one-to-one grouping example where two host findings and one peer finding share a `location`, showing which pair matches, which finding is left over, and which bucket the leftover lands in.
  - *Edge case (weighting):* Cross-source corroboration is documented as `+2` while same-source overlap stays `+1`, and the confidence cap of 10 still applies; the `fast-pass` exclusion from corroboration promotion survives the rewrite.
  - *Error / failure path (conflict independence):* A drift test asserts conflict detection is documented as **independent of** the `0.7` similarity predicate, and that a same-location dissimilar-title contradiction still lands in `conflicting`; conflicting findings are documented as never auto-applied and never simultaneously corroborated.
  - *Error / failure path (partition, EN11-PR-007):* The doc states the three-stage order (conflict, then corroboration, then singles) over one shared consumption pool, and states the partition invariant that every raw finding contributes to exactly one record. A worked example covers a `location` carrying both a contradictory pair and a similar pair, showing the contradictory pair is allocated first and that its members are unavailable to the corroboration stage.
  - *Error / failure path (blindness):* A drift test fails if the file still claims the peer reads persona findings, and separately asserts the blind-peer invariant sentence is present.
  - *Integration:* Corroboration matching reuses the existing `location` + `0.7` title-similarity predicate rather than introducing a second matcher, asserted by grepping for the shared threshold in the reconciliation section; determinism (greedy descending-similarity match, `finding_id` tie-break) is stated so two runs on identical input produce identical buckets.
- **Verification:** Drift assertions pass; `bin/ensemble-lint` clean; full suite green.

### U6. Drift tests

- **Goal:** Make every invariant in U1 to U5, U8, and U9 mechanically enforced rather than prose.
- **Requirements covered:** none
- **Dependencies:** U1, U2, U3, U4, U5, U8, U9
- **Files:** `tests/lint/en-review-peer-default.test.sh` (new)
- **Approach:** One drift-test file covering every unit, following the EN08 and EN10 precedent. The enforcement tier is **mixed by design**: text-level drift assertions where the surface is genuinely prose (the skill's default resolution, the CI carve-out, the reconciliation contract), and **behavioral checks driving the real executables** where behavior is claimed. Per EN11-PR-006, any claim of the form "exactly one retry" or "only the rejected fragment is dropped" MUST be proven against `bin/ensemble-peer-invoke` (U8) with stub CLIs and an invocation counter, never against skill prose. Drive the **real** `bin/ensemble-peer-flags` and `bin/ensemble-peer-invoke` with a hermetic stub PATH (the EN10 `mkstub` pattern) rather than reimplementing their logic. **Self-test every grep pattern used as a guard**: EN10-CR-003 showed that a `[^\n]` character class is not a newline exclusion in POSIX ERE and silently fails to guard on GNU grep, so each drift pattern must be proven to match a known-bad string and to not match a known-good prose string before it is trusted. End the file with the mandatory `report` call (a `tests/lint/*.test.sh` without it silently always passes).
- **Risk:** medium
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** test-first
- **Patterns to follow:** `tests/lint/en-codex-flag-drift.test.sh` (hermetic stubs, pattern self-tests, real-helper sourcing); `tests/lib/assert.sh` (`report` is mandatory)
- **Test scenarios:**
  - *Happy path:* The full suite runs the new file and all assertions pass; `tests/run.sh` file count increases by one.
  - *Edge case:* Each drift pattern's self-test proves it matches a synthetic regression string and does not match a synthetic prose string, so a guard cannot silently stop guarding.
  - *Error / failure path:* Temporarily reverting any one of U1 to U5's, U8's, or U9's key strings makes the corresponding assertion fail rather than silently pass, confirmed during the build.
  - *Integration:* The file sources `tests/lib/assert.sh` and ends with `report`; helper checks run against the real `bin/ensemble-peer-flags`, `bin/ensemble-peer-invoke`, and `bin/ensemble-config-get` on an isolated PATH so a host CLI or the operator's own `~/.ensemble/config.json` cannot influence the result (config fixtures are pointed at a temp `HOME`).
  - *Integration (enum coherence, EN11-PR-008):* Every `reason` string emitted by `bin/ensemble-peer-invoke` is asserted to be a member of the enum published in `references/peer-model-policy.md`, so the helper and the reference cannot drift apart.
- **Verification:** `bash tests/run.sh` green with the new file counted; `bash -n tests/lint/en-review-peer-default.test.sh`.

### U7. Foundation decision D45

- **Goal:** Record the decision so the rationale survives the plan.
- **Requirements covered:** none
- **Dependencies:** none
- **Files:** `docs/foundation.md`
- **Approach:** Add D45 after D44 capturing: the default-on peer and its mode/availability scoping; the explicit `report-only` carve-out and why it protects D38's secret-free CI posture; the `single-agent-fallback` carve-out and why a redundant same-model subprocess is not worth defaulting on in `/en-review` specifically (unlike `/en-build`, where the alternative is the host reviewing its own inline work); the four-bucket reconciliation and why cross-source corroboration outranks same-source; the blind-peer invariant and why the doc was corrected rather than the feature built; and the policy/binding/call-site split for models with the inherit-for-Codex rule, generalizing D44's flag-drift lesson from flags to model IDs.
- **Risk:** low
- **Category:** other
- **Reversibility:** trivial
- **Gated:** false
- **Execution note:** pragmatic
- **Patterns to follow:** existing D41 to D44 entries (single dense paragraph, bold lead, enforcement tier named at the end)
- **Test expectation:** none, documentation-only; the D45 presence assertion lives in U6's drift test.
- **Verification:** `bin/ensemble-lint --scope docs/` clean; U6's D45 assertion passes.

### U8. `bin/ensemble-peer-invoke` executable invocation + degradation helper

> **Build order note.** U-IDs are stable once assigned and are never renumbered (`references/stable-ids.md`), so U8 is appended here rather than inserted. `/en-build` executes in **dependency order**, which places U8 after U2 and before U3.

- **Goal:** Make the fail-soft state machine executable so it can be behaviorally tested, rather than prose that only a text assertion can "verify".
- **Requirements covered:** none
- **Dependencies:** U2
- **Files:** `bin/ensemble-peer-invoke` (new), `references/peer-model-policy.md` (point the fail-soft rule at the helper)
- **Approach:** EN11-PR-006 established that U3's promised stub-CLI behavioral tests were unprovable, because the retry/classification/fallback logic lived only in `skills/en-review/SKILL.md` prose and text assertions cannot prove "exactly one retry" or "only the rejected fragment was dropped". This is the same failure mode EN07 named (a prose invariant with no auditable gate) and the same remedy EN10 applied when it extracted `bin/ensemble-cli-smoke` so the drift test could drive the **real** classifier. Extract the state machine into a sourceable, errexit-safe helper with no top-level side effects, matching `bin/ensemble-cli-smoke`'s conventions. `ensemble_peer_invoke()` takes the peer command, format, turns, model and effort fragments, and a prompt file; runs the peer; on failure classifies via the **reused** `ensemble_smoke_classify`; on `flagdrift` retries **exactly once** with only the attributable fragment removed; and prints a `peer_decision`-shaped result using the U1(e) schema verbatim. Fragment attribution reads the rejected-argument name out of the captured stderr, defaulting to dropping `PEER_MODEL` first when attribution is ambiguous (it is the fragment more likely to be unsupported, and Codex never sets it). `/en-review` step 9 calls this helper rather than restating the algorithm.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Patterns to follow:** `bin/ensemble-cli-smoke` (sourceable, errexit-safe `if err=$(...)` capture, pure functions); `docs/foundation.md` D41 (prose invariants need an auditable gate)
- **Test scenarios:**
  - *Happy path:* A stub peer exiting 0 returns `peer: "on"` with `reason: default-on`, no retry attempted (asserted by a stub-side invocation counter file showing exactly one call).
  - *Edge case:* A stub rejecting only `--effort` retries once **without** `PEER_EFFORT`, the second call succeeds, the result is `peer: "degraded"` / `reason: dropped-effort-fragment`, and the counter shows exactly two calls. Same for a stub rejecting only `--model` yielding `dropped-model-fragment`.
  - *Error / failure path:* A stub rejecting every invocation stops after exactly **one** retry (counter shows two calls, never more) and returns `peer: "off"` / `reason: peer-failed:retry-exhausted`. A stub emitting an auth error returns `peer: "off"` / `reason: peer-failed:auth` with the counter showing exactly one call, proving auth never triggers a flag retry.
  - *Integration:* Sourcing the helper under `set -eu` does not abort the caller on a non-zero peer exit; every emitted `reason` is a member of the U1(e) enum, asserted by cross-checking the helper's strings against the policy reference.
- **Verification:** Behavioral tests in `tests/lint/en-review-peer-default.test.sh` drive the real helper against stub CLIs on an isolated PATH; `bash -n bin/ensemble-peer-invoke`; full suite green.

### U9. `bin/ensemble-config-get` shared config reader + `setup` key merge

> **Build order note.** Appended per `references/stable-ids.md` (U-IDs are never renumbered). Dependency order places U9 first, before U3 consumes it.

- **Goal:** Give the precedence chain an actual implementation, and stop new keys from being invisible to existing installs.
- **Requirements covered:** none
- **Dependencies:** none
- **Files:** `bin/ensemble-config-get` (new), `setup` (**sole owner** of the config-defaults block and the merge), `references/doc-lints.md` (pointer map, if applicable)
- **Approach:** Two defects block EN11's stated four-layer precedence, both found by inspection before build. **(1) Layer 2 has no reader.** `.ensemble/config.local.yaml` is parsed only by `skills/en-sweep/scripts/triage-findings` with bespoke awk for `sweep.*` keys, so "repo config beats user config" is unimplementable as written. **(2) Existing installs never receive new keys**, because `setup` writes `~/.ensemble/config.json` only under `[ ! -f ]`, so any machine that already ran `setup` silently lacks every key added afterwards.

  Fix both with one small shared reader. `bin/ensemble-config-get <key> [--default <value>] [--allowed <v1,v2,...>]` resolves, first hit wins: `<repo>/.ensemble/config.local.yaml`, then `~/.ensemble/config.json`, then `--default`, then empty. Keys are **flat**, matching all seven existing keys and the single `jq -r '.<key>'` pattern already used at `bin/ensemble-detect-host` line 106; the two new settings are therefore `review_peer_model_alias` and `review_peer_effort_override`.

  **Supported YAML grammar (EN11-PR-010), stated narrowly so a hand-rolled parser is safe.** The reader recognizes exactly one shape: a **top-level, non-indented** `key: value` line whose value is a plain or quoted scalar. It strips surrounding single/double quotes, honors a `#` inside quotes as literal, and treats an unquoted ` #` as starting a comment. Anything else for the requested key, an indented occurrence, a nested-lookalike under some parent, a block/flow collection, or a duplicate key, is treated as **absent** and falls through to the next layer. Unrelated nested sections elsewhere in the file (for example en-sweep's `sweep:` block) are tolerated and ignored. This deliberately does not attempt general YAML; anything outside the grammar is unsupported rather than best-effort guessed.

  **Absence and validity (EN11-PR-011).** A key whose value is JSON `null`, an empty string, or whitespace-only counts as **absent**, not as a hit, so `setup`'s defaults can ship the keys present-but-unset without shadowing the ladder. With `--allowed`, a value outside the allowed set is also treated as absent for that layer and resolution continues downward, so an invalid repo value falls through to global and an invalid global value falls through to the ladder. `/en-review` passes `--allowed low,medium,high` for the effort key, which is what stops a typo like `turbo` from ever reaching `bin/ensemble-peer-flags`.

  The reader is otherwise **fail-soft by construction**: a missing file, unreadable file, malformed JSON/YAML, or missing `jq` all fall through rather than erroring, because a config problem must never take down a review. Migrating existing consumers is out of scope; note that adopting the documented-but-unimplemented `review.confidence_threshold` would first require flattening that key, since this reader is flat-only by design.

  **`setup` ownership and the merge (EN11-PR-012, EN11-PR-013).** To avoid two units editing the same block, **U9 owns every `setup` change to the config file**, both the two new default keys and the merge behavior; U1 owns only the policy reference. Replace the `[ ! -f ]` skip with a merge that adds only absent keys: `jq -s '.[0] * .[1]'` with defaults first and the existing file second, so user values always win. Atomicity requires all of: `mktemp` **in the destination directory** (a cross-filesystem `mv` is not atomic), `jq` output validated as a non-empty JSON **object** before it is used, `mv` only after that validation, a `trap` removing the temp file on any exit path, and the original left **untouched** on any failure. Unknown user-added keys are preserved. When `jq` is unavailable, make no change and print a one-line notice naming the keys to add by hand.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Execution note:** test-first
- **Patterns to follow:** `bin/ensemble-detect-host` line 106 (`jq -r '.key // default'`, the established flat-key read); `bin/ensemble-cli-smoke` (sourceable, errexit-safe, no top-level side effects)
- **Test scenarios:**
  - *Happy path:* With `review_peer_effort_override: high` in `~/.ensemble/config.json` and no repo file, `ensemble-config-get review_peer_effort_override` prints `high`. With the key also present in `.ensemble/config.local.yaml` as `low`, it prints `low`, proving repo beats global.
  - *Edge case (grammar, EN11-PR-010):* Quoted and unquoted values round-trip; `"a # b"` keeps the literal `#` while `a # b` yields `a`; a value containing a colon is preserved; an **indented** occurrence of the key, a nested lookalike under a parent, a block/flow collection value, and a duplicate key are each treated as absent and fall through; an unrelated `sweep:` block elsewhere in the file is ignored without affecting the lookup.
  - *Edge case (absence/validity, EN11-PR-011):* JSON `null`, `""`, and whitespace-only all count as absent and fall through, so a present-but-unset default never shadows a lower layer. With `--allowed low,medium,high`, a repo value of `turbo` falls through to a valid global value; an invalid global value falls through to `--default`; a valid repo value still wins.
  - *Error / failure path:* Malformed JSON, malformed YAML, an unreadable file, and a `PATH` without `jq` each fall through to the next layer and exit 0 rather than erroring. Asserted with a stub `PATH` that omits `jq`.
  - *Integration (setup merge, EN11-PR-012):* Given an existing config with only the original seven keys, `./setup` adds the two new keys while every original key's **value is semantically unchanged** (jq reserializes, so byte-identity is not claimed), including a user-modified `peer_timeout_seconds` that must **not** revert to the default, and an unknown user-added key that must survive. Running `./setup` twice is idempotent.
  - *Error / failure path (merge safety, EN11-PR-012):* A malformed existing config, a non-object existing config (for example a top-level array), an injected `jq` failure, and an injected `mv` failure each leave the original file **byte-for-byte untouched**, leave no stray temp file behind, and do not abort `setup`. With `jq` absent, both the fresh-install and existing-install paths make no change and print the notice.
- **Verification:** Behavioral tests drive the real `bin/ensemble-config-get` against fixture config files on an isolated PATH; `bash -n bin/ensemble-config-get`; `bash -n setup`; full suite green.

## Tracked debt

None resolved or deferred by this plan.

## Iteration log

### Iteration 1 — cross-agent peer (codex), verdict: revise

Five findings, all applied.

- **EN11-PR-001 (P1) — effort precedence could assign `low` to a high-risk review.** Applied. The ladder is now an explicit ordered first-match cascade with `high` evaluated first. Worth noting the finding was partly pre-mitigated: `is_small_and_safe` already requires empty `RISK_SIGNALS` and no fired conditional persona, so security and migrations could not have collided with `low`. The **architectural**, **destructive**, and **gated** conditions are genuinely not inputs to `is_small_and_safe`, so the hole was real for those, and explicit ordering closes all cases cheaply.
- **EN11-PR-002 (P1) — fail-soft had no executable path.** Applied. Degradation ownership moved to the invocation layer (U3), with `bin/ensemble-cli-smoke`'s classifier deciding, a bounded single retry dropping only the rejected fragment, the outcome recorded in `peer_decision.reason`, and stub-CLI behavioral tests per fragment.
- **EN11-PR-003 (P1) — reconciliation could not represent corroborated provenance.** Applied. Introduced a distinct reconciliation record with `sources[]` and `contributing[]` rather than a single `source` enum, plus deterministic one-to-one greedy grouping with a `finding_id` tie-break, a stated `canonical` selection rule, and conflict detection decoupled from the `0.7` similarity predicate (incompatible claims are frequently dissimilar in title, so keying conflict off similarity would have systematically missed them).
- **EN11-PR-004 (P2) — effort resolution had no owner and `--effort` was unreachable.** Applied. `/en-review` is now the sole resolver and `bin/ensemble-peer-flags` is a pure translator that reads no config; `--effort` added to the Flags table; a purity test asserts the helper ignores config.
- **EN11-PR-005 (P2) — U4 depended on an invariant from an undeclared unit.** Applied. U4 now depends on U3 and U5, and file ownership across the overlapping `references/persona-dispatch.md` sections is split explicitly between U4 (Parallel dispatch) and U5 (Synthesis / Outside Voice).

### Iteration 2 — cross-agent peer (codex), verdict: revise

Peer confirmed PR-001, PR-003's provenance issue, PR-004, and PR-005 as materially addressed. Four further findings, all applied.

- **EN11-PR-006 (P1) — the fail-soft retry was prose-only and could not support the behavioral tests iteration 1 promised.** Applied, and the most valuable finding of the two rounds. Iteration 1's fix put the retry state machine in `skills/en-review/SKILL.md`, then claimed stub-CLI tests would prove "exactly one retry" and "only the rejected fragment dropped", which a text assertion cannot do. This is precisely the failure mode D41 named and the remedy D44 used when EN10 extracted `bin/ensemble-cli-smoke` so its test could drive the real classifier. Resolution: new **U8** extracts `bin/ensemble-peer-invoke` as a sourceable helper owning invocation, classification, bounded retry, fragment attribution, and fallback; U3 now calls it instead of restating it; U6 proves the behavior against the real executable with stub CLIs and an invocation counter.
- **EN11-PR-007 (P1) — conflict and corroboration had no defined consumption order, so the buckets did not partition.** Applied. U5 now specifies one global algorithm over a shared consumption pool: conflict stage first (consuming both members, since a contradiction must not be masked by a similarity match), corroboration on the remainder, then singles, with `finding_id` tie-breaks at every stage and an asserted partition invariant that every raw finding contributes to exactly one record.
- **EN11-PR-008 (P2) — the `peer_decision` schema contradicted itself and its "closed" enum was never enumerated.** Applied. U1 gains section (e) publishing the schema once with `peer: on | off | degraded` (the diagram and JSON now agree) plus the complete `reason` enum covering every default-off condition, configured skip, recursion guard, fragment degradation, auth, timeout, unknown, and retry exhaustion. U3 and U6 consume it verbatim, and U6 asserts the helper's emitted strings are enum members.
- **EN11-PR-009 (P2) — `review.peer.model_alias` had no resolution owner or call-site path.** Applied. U1(c) now routes the alias through the same owner and chain as effort, states there is deliberately no `--model` run-flag (model choice is an operator setting), and documents the alias as inert on a Codex peer by design so the key is never silently unused. U3 gained an integration scenario covering configured, default, and Codex-inherit behavior.

### Post-acceptance amendment (2026-07-27) — U9 added, keys flattened

Raised by the user after the cap-hit acceptance, when asking how model and effort would actually be set on a deployed install. Inspection found the stated four-layer precedence had **two layers with no implementation**:

- `.ensemble/config.local.yaml` (layer 2) is read only by `skills/en-sweep/scripts/triage-findings` via bespoke awk for `sweep.*` keys, so "repo config beats user config" was unimplementable as specced.
- `setup` writes `~/.ensemble/config.json` only under `[ ! -f ]`, so every machine that already ran `setup` would silently never receive the new keys.
- The proposed `review.peer.*` keys were also two levels deep, while all seven real keys are flat and the only reader pattern in the repo is `jq -r '.<key>'` at `bin/ensemble-detect-host` line 106. The dotted `review.confidence_threshold` in `references/review-confidence-gating.md` is documented but read by nothing executable, so dotted notation had no working precedent to follow.

Resolution, both decided with the user: add **U9** (`bin/ensemble-config-get` shared reader plus a `setup` merge-missing-keys change), and use **flat** keys `review_peer_effort_override` / `review_peer_model_alias`. U1(b) and U1(c) now delegate layering to the reader, U3 depends on U9, and U6 covers it. `peer_review_plan_hash` was recomputed because unit-immutable fields changed.

**Review status of this amendment:** U9 was added after the peer loop closed and carries a single **targeted** peer pass (scoped to U9 plus the U1/U3 rewiring, not a third full iteration). It returned four findings, all applied:

- **EN11-PR-010 (P1) — flat keys gave no safe YAML parsing contract.** Applied. U9 now states a narrow supported grammar (top-level non-indented `key: value` scalars, quote stripping, `#` handling) and treats anything outside it, including indented occurrences, nested lookalikes, collections, and duplicate keys, as absent rather than best-effort guessed. The claim that the reader could later adopt `review.confidence_threshold` was **wrong** and is corrected: that key would first need flattening, since this reader is flat-only by design.
- **EN11-PR-011 (P1) — unset and invalid values could defeat precedence.** Applied. `null`, empty, and whitespace-only now count as absent, so `setup` shipping the keys present-but-unset cannot shadow the ladder. Added `--allowed` so an out-of-set value falls through per layer, which is what stops a typo like `turbo` reaching `bin/ensemble-peer-flags`.
- **EN11-PR-012 (P1) — the setup merge underspecified preservation and atomic failure.** Applied. Now requires a same-directory `mktemp` (a cross-filesystem `mv` is not atomic), `jq` output validated as a non-empty object before use, `mv` only after validation, `trap` cleanup, and the original untouched on any failure. The peer also caught a genuine error in the test scenario: `jq` reserializes, so **byte-identical** was not something the merge could promise. Reworded to semantically-unchanged values, with byte-identity now asserted only on the failure paths where the file must not be rewritten at all.
- **EN11-PR-013 (P2) — U9's dependency and setup ownership contradicted its build-order claim.** Applied. U9 is now the **sole owner** of every `setup` config change (defaults and merge both), U1 no longer edits `setup` at all, and U1's stale `[ ! -f ]` scenario is replaced with a naming assertion. Both units keep `Dependencies: none` and no longer contend for the same block.
