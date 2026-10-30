# One peer pass, exactly

Read at step 14 before the first pass, and again before each re-loop. It is the
same five commands every time, so they are written out here to copy, not to
rediscover: runs re-learned `ensemble-peer-invoke` with `--help` and `sed` on
every plan, and one plan got a third peer pass against a cap of two (D136).

## 1. Count the passes first

```bash
n=$(awk '/^---$/{c++; next} c==1 && /^peer_review_iterations:/{print $2; exit}' "<plan-path>")
echo "peer passes so far: ${n:-0}"
```

The cap is **two passes** (`references/finalize-loop.md`; `--max-iterations <N>`
allows `N + 1`, and `--no-reloop` allows one). At the cap, do not invoke: ask
"accept as-is and flip to `open`, or stay in `draft`?" and let the user decide.
A pass that would exceed the cap is never run "to confirm".

## 2. Resolve the peer, its model and its effort

```bash
eval "$(bash "$SKILL_DIR/scripts/ensemble-detect-host")"
alias=$(bash "$SKILL_DIR/scripts/ensemble-config-get" peer_model_claude --legacy peer_model_alias --legacy review_peer_model_alias)
codex=$(bash "$SKILL_DIR/scripts/ensemble-config-get" peer_model_codex --legacy peer_codex_model --legacy review_peer_codex_model)
override=$(bash "$SKILL_DIR/scripts/ensemble-config-get" "peer_effort_$PEER" --allowed low,medium,high,xhigh --legacy peer_effort_override --legacy review_peer_effort_override)
eval "$(bash "$SKILL_DIR/scripts/ensemble-peer-flags" --effort "${override:-inherit}" --peer-cmd "$PEER_CMD" --model-alias "$alias" --codex-model "$codex")"
```

`PEER_AVAILABLE=false` means no peer: skip to the status flip and say so.

## 3. Build the prompt into a file

```bash
D=$(mktemp -d)
bash "$SKILL_DIR/scripts/ensemble-build-peer-prompt" --brief "$SKILL_DIR/references/peer-brief.md" \
  --project-context "<one line>" --goal "<one line>" --artifact-file "<plan-path>" \
  --peer-mode "$PEER_MODE" > "$D/prompt.md"
```

Before applying a pass's fixes, `cp "<plan-path>" "$D/plan-before.md"`. On a
re-loop, build into that same `$D` rather than a new one, and add
`--iteration-context-file <path>` with the previous review context
(`references/outside-voice.md`) and `--plan-before "$D/plan-before.md"`, so the
peer sees exactly what the fixes changed.

## 4. Run the pass

```bash
. "$SKILL_DIR/scripts/ensemble-peer-invoke"
ENSEMBLE_PEER_REVIEW=true ensemble_peer_invoke --peer-cmd "$PEER_CMD" --peer-format "$PEER_FORMAT" \
  --peer-turns "$PEER_TURNS" --peer-model "$PEER_MODEL" --peer-effort "$PEER_EFFORT" \
  --prompt-file "$D/prompt.md" --out-file "$D/peer.json" --peer-mode "$PEER_MODE"
```

It prints one `peer_decision` object and writes the findings to `$D/peer.json`.
It owns the timeout, failure classification, retry and fallback (D41); surface
the decision's `peer` and `reason` in the run report.

## 5. Record the pass

Parse `$D/peer.json` per `references/finding-schema.md`, then update the plan's
frontmatter: `peer_review_verdict`, `peer_review_iterations` (+1) and
`peer_review_last_run`.
