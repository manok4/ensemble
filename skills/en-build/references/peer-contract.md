# The peer contract

**Byte-identical in every skill that carries it.** These are the values two ends
of a peer exchange must agree on: a peer emits them, a host parses them. If one
skill's copy drifts, findings stop being comparable and `/en-review`'s
reconciliation buckets become meaningless with nothing failing.

Nothing here describes what a skill *does* with a finding. That is policy, it
differs per skill, and it lives in each skill's own review brief. What `/en-plan`
does with a P1 on a plan is not what `/en-build` does with a P1 on a diff, and
the file that fused the two is why ten skills carried a routing matrix shaped
for code review.

## Severity

| Level | Meaning |
|---|---|
| **P0** | Blocking. Do not proceed without resolution. |
| **P1** | High priority. Apply, or surface for an explicit decision. |
| **P2** | Should fix soon. Apply if cheap; defer otherwise. |
| **P3** | Advisory. Note and move on. |

A P1 means the same thing to every caller. That is the whole reason this file is
copied rather than specialised.

## Confidence

An integer 1–10: how sure the reviewer is that the finding is real. It grades the
*claim*, not the importance — a P3 can be confidence 10 and a P0 can be
confidence 4.

Which confidences a host surfaces, caveats or suppresses is policy, not contract.

## Autofix class

Every finding carries exactly one:

| Class | What it asserts about the finding |
|---|---|
| `safe_auto` | Mechanically applicable with no judgement |
| `gated_auto` | Applicable, but a human should see it go by |
| `manual` | Needs a human decision |
| `advisory` | Not an action; an observation |

The class describes the *finding*. What a host does on receiving each class is
policy.

## The `peer_decision` object

Emitted once per run by every skill that can invoke a peer, so a skipped or
degraded peer can never read as a normal one.

```json
{"peer": "on" | "off" | "degraded",
 "reason": "<enum below>",
 "peer_mode": "cross-agent" | "single-agent-fallback" | "off",
 "effort": "low" | "medium" | "high",
 "model_alias": "<alias>" | null,
 "model_actual": "<served model, from the CLI's own receipt>" | null}
```

`model_actual` is what the CLI reported serving (Claude's `modelUsage` key), not what was asked for; `null` where the route gives no receipt. It is evidence for a degraded or fallback run, never an input to any decision.

`degraded` is the canonical representation of a successful-but-reduced run, so
the three states mean the same thing everywhere.

| `peer` | `reason` values |
|---|---|
| `on` | `default-on`, `explicit-flag` |
| `off` | `no-peer-flag`, `host-only-mode`, `single-agent-fallback`, `report-only-mode`, `recursion-guard`, `peer-unavailable`, `auto-skip:diff-below-threshold`, `auto-skip:lightweight-depth`, `peer-failed:auth`, `peer-failed:timeout`, `peer-failed:unknown`, `peer-failed:retry-exhausted` |
| `degraded` | `dropped-model-fragment`, `dropped-effort-fragment`, `dropped-isolation-fragment` |

**Anything outside this enum is a contract violation.** Callers branch on these
exact spellings, so never rename, abbreviate or add to them without changing
every copy of this file together.

## Resolution status

When a host records what it did with a finding, exactly one of:

`applied` · `deferred` · `disagreed` · `superseded`

`deferred`, `disagreed` and `superseded` each require a stated rationale.
`applied` does not, because the change itself is the record.

## Where degradation is handled

**At the invocation layer** (the ensemble-peer-invoke helper, carried by the skills that invoke a peer), never at the call
site and never in the flag translator. A failed invocation is classified, and the
classification decides whether a retry happens:

| Classification | Behaviour |
|---|---|
| `flagdrift` | One bounded retry dropping **only** the rejected fragment — never both, never the prompt |
| `auth` | No retry. Ordinary failure. |
| `unknown` | No retry. Ordinary failure. |
| Second failure | Stop. `peer-failed:retry-exhausted`. |

This is contract rather than policy because the `reason` a caller receives
depends on it: a skill that retried differently would emit reasons that do not
mean what this file says they mean.

## No concrete model IDs

**No concrete model ID may appear anywhere in Ensemble.** Model IDs go stale on
every vendor release. A Claude peer pins a tier *alias*, which resolves to the
current model of that tier; a Codex peer pins nothing and inherits the operator's
configured model, with only reasoning effort overridden.

Which tier a given skill asks for is policy. That none of them may hardcode an ID
is contract, because one stale literal breaks every skill that copied it.
