# Run metrics — what a run records about itself

Carried by `/en-plan` and `/en-build`; the call-point tables below are per skill.

`scripts/ensemble-run-metrics` writes one JSON file per run under `$(git rev-parse --git-dir)/ensemble/runs/<plan_id>-<run_id>.json`, beside the verification receipt: never committed, no `.gitignore` entry, gone with the clone. The next improvement pass then has evidence without reconstructing a transcript, which is how the 2026-09-06 cost analysis had to be done.

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

## Call points for `/en-build`

Two analyses of real builds, on 2026-09-06 and 2026-09-08, had to be reconstructed from commit timestamps and peer job directories, and the persona timings came out `Unknown` because nothing recorded them. Same shorthand, same fire-and-forget contract.

| When | Call |
|---|---|
| Step 4a, once the plan id and baseline hash are known | `METRICS=$(run_metrics start --plan <plan_id>)` |
| Entering a unit at 9c, and again after 9e commits | `run_metrics event "$METRICS" --kind unit --json '{"unit":"U<N>","event":"start"}'` then `'{"unit":"U<N>","event":"end","commit":"<sha>","verify_exit":<n>,"selection_tier":"<TEST_SELECT_TIER>"}'` |
| Each 9f checkpoint | `run_metrics event "$METRICS" --kind phase --json '{"checkpoint":"before-U<N>\|end-of-loop","event":"end","units":<n>,"outcome":"passed\|failed"}'` |
| Any full-suite run (the cheap-suite tier at a checkpoint, and step 10.4) | `run_metrics event "$METRICS" --kind suite --json '{"where":"checkpoint\|post-build","seconds":<n>,"outcome":"passed\|failed"}'` |
| Around step 10.3's `/en-review` invocation | `run_metrics event "$METRICS" --kind review --json '{"event":"start"}'` then `'{"event":"end","reviewer":"<envelope.reviewer>","findings":<n>,"personas":[{"dimension":"testing","seconds":<n or null>}]}'` |
| Step 10.6, after the audit | `run_metrics finish "$METRICS"`, then `run_metrics summary "$METRICS"` for the report line |

`personas[].seconds` is whatever the host reported for that agent, and `null` when it reported nothing: a duration nobody measured is recorded as unmeasured, never estimated. A unit that pauses at a gate still records its `end` event when it resumes, so a gate's wait time is visible as the gap between two events rather than as a missing unit.

## Report line

Both skills end the run report with `metrics: <path> (<summary>)`, for example `metrics: .git/ensemble/runs/EN16-20260907T140000Z.json (2 dispatches, 2 peer passes, 3 lint runs)`. When metrics were disabled the line reads `metrics: disabled (<reason>)` with the helper's stderr reason, so a missing file is never mistaken for a run that recorded nothing.

## Reading a file

```
jq '.events[] | select(.kind=="peer") | {iteration, peer: .peer_decision.peer, tokens}' <file>
jq '[.events[] | select(.kind=="findings")] | map({iteration, P1})' <file>
```

The second query is what the loop-cap decision (design doc, U12) reads.
