# Run metrics — what a plan run records about itself

`scripts/ensemble-run-metrics` writes one JSON file per `/en-plan` run under `$(git rev-parse --git-dir)/ensemble/runs/<plan_id>-<run_id>.json`, beside the verification receipt: never committed, no `.gitignore` entry, gone with the clone. The next improvement pass then has evidence without reconstructing a transcript, which is how the 2026-09-06 cost analysis had to be done.

It records only what the skill can observe. Compaction count and dollar cost are not visible from inside a run and are not recorded; the report line says so once.

## Call points

The rows below use a shorthand; bind it once in the same shell, anchored on the skill directory (`references/script-invocation.md`), because a bare `event` resolves against the user's project and exits 127:

```bash
run_metrics() { bash "$SKILL_DIR/scripts/ensemble-run-metrics" "$@"; }
```

Every call is fire-and-forget: outside a git repo, without `jq`, or on a bad payload the helper prints one stderr line and exits 0, and a run is never blocked by its own bookkeeping.

| When | Call |
|---|---|
| Right after the plan id is known (resume or create) | `METRICS=$(run_metrics start --plan <plan_id>)` |
| Each research dispatch, once it returns | `run_metrics event "$METRICS" --kind dispatch --json '{"agent":"repo-research","host":"<HOST>","model":"<AGENT_MODEL or null>","model_source":"<AGENT_MODEL_SOURCE or null>","started":<epoch>,"ended":<epoch>}'` |
| Each peer pass | `run_metrics event "$METRICS" --kind peer --json '{"iteration":<N>,"peer_decision":<the object the invoke printed>,"tokens":{"input":<n or null>,"output":<n or null>}}'`. Codex `--json` reports `token_count`; a Claude peer reports `usage`; absent counts are `null`, never guessed. |
| Each lint run | `run_metrics event "$METRICS" --kind lint --json '{"scope":"<scope>","seconds":<n>}'` |
| After parsing a pass's findings | `run_metrics event "$METRICS" --kind findings --json '{"iteration":<N>,"P0":<n>,"P1":<n>,"P2":<n>,"P3":<n>}'` |
| Promotion or any terminal stop | `run_metrics finish "$METRICS"`, then `run_metrics summary "$METRICS"` for the report line |

`<AGENT_MODEL>` and `<AGENT_MODEL_SOURCE>` come from the agent-model resolver (`ensemble-agent-model`, EN16 U3) when a dispatch resolved through it; a dispatch that passed no model records `null` and the source `inherit`.

## Report line

The run report ends with `metrics: <path> (<summary>)`, for example `metrics: .git/ensemble/runs/EN16-20260907T140000Z.json (2 dispatches, 2 peer passes, 3 lint runs)`. When metrics were disabled the line reads `metrics: disabled (<reason>)` with the helper's stderr reason, so a missing file is never mistaken for a run that recorded nothing.

## Reading a file

```
jq '.events[] | select(.kind=="peer") | {iteration, peer: .peer_decision.peer, tokens}' <file>
jq '[.events[] | select(.kind=="findings")] | map({iteration, P1})' <file>
```

The second query is what the loop-cap decision (design doc, U12) reads.
