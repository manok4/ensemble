# `/en-review` — contract for calling skills

What another skill may rely on. Owned by `en-review`; a caller depends on this
page, never on `SKILL.md` internals and never on a file inside this directory.

## Accepted invocations

| Form | Caller |
|---|---|
| `/en-review --cross --mode headless --base <merge-base>` | `en-build`, post-build branch review (peer plus personas, D46) |
| `/en-review --peer --mode headless --base <merge-base>` | `en-loop` checkpoints (peer alone) |
| `/en-review --mode report-only` | CI (`en-sweep`); mandatory there, and it never runs a peer |
| `/en-review --host` | any caller wanting the persona roster and no peer subprocess |

`--peer` (default), `--cross` and `--host` are mutually exclusive. There is no
`--no-peer` on this skill; `--host` is how a caller declines the peer.

`--mode` takes exactly `interactive`, `headless`, `report-only`. A caller that
omits `--mode` gets `interactive`, which blocks; skills must pass one.

## Non-interactive guarantee

In `headless` and `report-only` this skill never calls a blocking-question tool.
It infers intent from flags, git state and the diff, and records uncertainty in
its output rather than stopping to ask. A caller may run it unattended.

## Return

A findings envelope. Callers branch on these fields:

| Field | Values |
|---|---|
| `reviewer` | `cross-agent` · `single-agent-fallback` · `en-review-host-fallback` |
| `reconciliation[]` | buckets `corroborated` · `peer-only` · `host-only` · `conflicting` |
| `peer_decision` | `{peer, reason, peer_mode, effort, model_alias}`; `reason` is a closed enum |
| `sub_threshold_findings[]` | present in `report-only`; filed as TD entries in other modes |

**Branch on these exact spellings.** Never rename, abbreviate or add to them. A
caller that matches on anything else is relying on an internal detail.
`reviewer` records whether the cross-agent property held, not how many personas
ran; it is what an evidence audit gates on.

## Authority envelope

Being invoked by another skill is not authorization. This skill mutates only
within the scope its caller already holds, and may narrow that scope but never
widen it.

| Mode | Mutation |
|---|---|
| `interactive` | applies `safe_auto`; gathers authorization for the rest |
| `headless` | applies `safe_auto` **only**, silently |
| `report-only` | none — strictly read-only, no edits, no commits |

`conflicting` findings are never auto-applied in any mode. This skill never
pushes, opens PRs or files tickets.

## Cost bounds

`report-only` never runs a peer, deliberately: `en-sweep` invokes it inside CI,
where API secrets and repo-write are kept off (D38), so defaulting a peer on
would silently require peer credentials there. Every run emits one
`peer_decision:` line, so a peer that did not run (`--host`, `report-only`,
recursion guard, unavailable) is recorded rather than passing quietly.

## Recursion

Under `ENSEMBLE_PEER_REVIEW=true` this skill proceeds without the peer even when
`--peer` was passed, and records why. It never spawns a nested peer subprocess.
