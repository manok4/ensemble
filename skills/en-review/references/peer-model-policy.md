# Peer model and reasoning-effort policy

Which model and how much reasoning effort the cross-agent peer runs with, and who decides.

> **Three layers, deliberately separated.** **Policy** (this file) owns the stable risk ladder. **Binding** (the `ensemble-peer-flags` helper) owns the volatile per-CLI syntax. **Call sites** read `$PEER_MODEL` / `$PEER_EFFORT` and never a literal. This is the cli-wrappers pattern: when a CLI literal was scattered across nine files, one upstream flag removal cost a whole plan to repair (D44). Model IDs are the same hazard, so **no concrete model ID may appear anywhere in Ensemble**.

## (a) The effort ladder

An **ordered first-match cascade**. `high` is evaluated first, so a change that satisfies more than one condition always resolves to the strongest tier.

| Order | Tier | Condition |
|---|---|---|
| 1 | `high` | `security-reviewer` or `migrations-reviewer` fired, OR an architectural trigger is present, OR the unit is `risk: destructive` or `gated: true` |
| 2 | `low` | `/en-review`'s `lite_gate` is `applied`, or `is_small_and_safe` is `true` per diff-signal-detection, carried by the skills that review a diff |
| 3 | `medium` | otherwise (the floor) |

**Rung 2 is unevaluable for a skill that reviews a document.** Both rung-2 inputs come from a diff: `lite_gate` from `/en-review`'s flag and risk gate, `is_small_and_safe` from diff-signal-detection. A skill that ships a document it just wrote has no diff to classify, so the fail-closed default applies and the cascade lands on the rung-3 floor. Those skills therefore do not carry diff-signal-detection; the path above is deliberately unlinked so it is not billed to them.

**Why `high` is tested first even though it looks redundant.** Both rung-2 inputs already require `RISK_SIGNALS` to be empty (and `lite_gate: applied` requires no conditional persona to have fired), so security and migrations can never collide with `low`. But the **architectural**, **destructive**, and **gated** conditions are *not* inputs to `is_small_and_safe`, and genuinely can co-occur with it. A small, signal-free diff on a `gated: true` unit must still resolve `high`. Ordering the cascade makes that true by construction rather than by coincidence.

**Why the floor is `medium` and not `low`.** Review is a recall problem, and the findings that justify running a peer at all are the subtle ones. Bottoming out at `low` would erode the capability being paid for. `low` is an explicit cost opt-in for diffs that have earned it.

## (b) Resolution order, and its single owner

**`/en-review` is the only resolver.** It walks the chain below, produces **one final tier** and **one final model alias**, and passes them to `$SKILL_DIR/scripts/ensemble-peer-flags`.

| Order | Layer | How |
|---|---|---|
| 1 | `--effort <low\|medium\|high>` flag | Parsed by `/en-review` |
| 2 | `<repo>/.ensemble/config.local.yaml` | Via `$SKILL_DIR/scripts/ensemble-config-get` |
| 3 | `~/.ensemble/config.json` | Via `$SKILL_DIR/scripts/ensemble-config-get` |
| 4 | The ladder in (a) | Default |

First hit wins. Layers 2 and 3 are read through `$SKILL_DIR/scripts/ensemble-config-get`, which owns the repo-then-global cascade so there is one implementation of layering rather than one per consumer.

**`$SKILL_DIR/scripts/ensemble-peer-flags` never reads config.** It is a pure translator: tier and alias in, CLI syntax out. Precedence therefore exists in exactly one place and is testable there.

Config keys are **flat**, matching every existing key in `~/.ensemble/config.json` and the `jq -r '.<key>'` read pattern already used in `$SKILL_DIR/scripts/ensemble-detect-host`:

| Key | Meaning |
|---|---|
| `review_peer_effort_override` | Pins the effort tier, bypassing the ladder |
| `review_peer_model_alias` | Pins the Claude peer's model tier alias |

Both are unset by default, so the ladder governs. `setup` writes and merges them (see `$SKILL_DIR/scripts/ensemble-config-get` and the `setup` merge, which owns that block).

## (c) Model binding

**Claude peer: pin a tier alias.** `claude --model <alias>` resolves an alias to the latest model of that tier, so an alias is drift-free and inherits upgrades without an Ensemble change.

**Codex peer: pin nothing.** `codex exec -m` takes a concrete model ID, and concrete IDs go stale on every vendor release. Ensemble therefore does **not** set `-m` at all; the peer inherits the operator's `~/.codex/config.toml` model, and Ensemble overrides **only** `model_reasoning_effort`.

`review_peer_model_alias` resolves through the same owner and the same chain as effort (layers 2, 3, then the documented default alias). There is deliberately **no `--model` run flag** on `/en-review`: model choice is an operator setting, not a per-run one. On a Codex peer the resolved alias is **ignored by design**, so the key is never silently unused: it governs on Claude and is documented as inert on Codex.

## (d) Fail-soft, and its owner

**Degradation is handled at the invocation layer** (`$SKILL_DIR/scripts/ensemble-peer-invoke`, called from `/en-review`'s Outside Voice peer step), never in the translator.

When a peer invocation fails, classify it with `ensemble_smoke_classify` from `$SKILL_DIR/scripts/ensemble-cli-smoke` (reused from D44, not duplicated):

| Classification | Behavior |
|---|---|
| `flagdrift` | **Bounded single retry** dropping **only** the rejected fragment (`PEER_MODEL` or `PEER_EFFORT`, never both, never the prompt). The peer degrades to inherited defaults and the review still gets its cross-agent pass. |
| `auth` | No flag retry. Ordinary peer failure; fall back to persona-only. |
| `unknown` | No flag retry. Ordinary peer failure; fall back to persona-only. |
| Second failure | Stop. Fall back to persona-only, reason `peer-failed:retry-exhausted`. |

Every outcome is recorded in `peer_decision.reason` and echoed in the mandatory `peer_decision:` summary line. A degradation is never silently swallowed.

A rejected effort or model value degrades **that peer call**; it never errors the review.

## (e) The `peer_decision` schema

Published here once, and consumed verbatim by `/en-review` and the drift tests, so there is a single definition to drift from.

```json
{"peer": "on" | "off" | "degraded",
 "reason": "<enum>",
 "peer_mode": "cross-agent" | "single-agent-fallback" | "off",
 "effort": "low" | "medium" | "high",
 "model_alias": "<alias>" | null,
 "model_actual": "<served model>" | null}
```

`peer: "degraded"` is the canonical representation of a successful-but-reduced peer run, so the three states are the same everywhere.

| `peer` | `reason` values |
|---|---|
| `on` | `default-on` , `explicit-flag` |
| `off` | `no-peer-flag` , `host-only-mode` , `single-agent-fallback` , `report-only-mode` , `recursion-guard` , `peer-unavailable` , `auto-skip:diff-below-threshold` , `auto-skip:lightweight-depth` , `peer-failed:auth` , `peer-failed:timeout` , `peer-failed:unknown` , `peer-failed:retry-exhausted` |
| `degraded` | `dropped-model-fragment` , `dropped-effort-fragment` , `dropped-isolation-fragment` (an isolation, access or schema flag the installed CLI rejected; the set is dropped as one fragment) |

Anything outside this enum is a contract violation, the same standard the build flavors apply to `peer-skipped:`.

## Related

- cli-wrappers — the per-CLI flag tables this policy binds against (carried by the skills that bind them)
- diff-signal-detection — defines `is_small_and_safe` (carried by the skills that review a diff)
- `references/host-detect.md` — emits `PEER_CMD` / `PEER_FORMAT` / `PEER_TURNS`
- persona-dispatch — how the peer's findings reconcile with the host personas (carried by `/en-review`)
