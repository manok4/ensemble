# en-flow pipeline — stage contracts

The `/en-flow` orchestrator (`disable-model-invocation: true`) chains the lifecycle skills. Each stage hands a durable artifact to the next and gates before advancing. Adapted from compound-engineering's `lfg`, specialized to Ensemble's branch-level review model (D35).

## Stage graph

```
[--plan? ]── en-plan ──▶ plan file (status: open)        GATE: plan exists & buildable
                 │
                 ▼
            en-build ──▶ branch w/ unit commits +        GATE: evidence audit verdict: ok
                         post-build review-verdict
                 │       (en-build internally runs
                 │        en-simplify → en-review)
                 ▼
        en-learn (model-decided) ─▶ optional learning    no-op if en-build already captured
                 │
                 ▼
     [local-only? / --no-ship? ]── en-ship ──▶ PR +      no auto-merge; watch loop → en-resolve-pr
                                    watch loop            (bounded 2 cycles, then escalate)
                 │
                 ▼
             <promise>DONE</promise>
```

## Artifact contracts

| Stage | Input | Output | Gate to advance |
|---|---|---|---|
| Plan | feature description OR `--plan <path>` | `docs/plans/active/<PREFIX><NN>-*.md`, `status: open` | plan file exists, buildable (not `draft`-stuck, not non-software) |
| Build | plan path | feature branch: unit commits + branch-level `review-verdict:` | end-of-build evidence audit `verdict: ok` |
| Learn | build outcome | optional learning entry | always passes (capture is model-decided; no-op if already captured) |
| Ship | branch | PR (ready for review) OR local-only commits | n/a (terminal) |

## Why each gate

- **Plan gate** — building without a finalized, peer-reviewed plan is the failure mode the pipeline exists to prevent. No plan → no build.
- **Build gate** — an audit failure means a unit lacks review evidence; shipping it would merge unreviewed work. Stop and route to `/en-cross-review`.
- **Learn** — never blocks; it's a judgment backstop. The model captures only durable insight and never double-files when en-build's hand-off already captured.
- **Ship** — no-auto-merge and the bounded watch loop are inherited from `/en-ship`; en-flow adds no merge authority of its own.

## Local-only mode

When `git remote` returns nothing, the pipeline runs plan → build → learn with local commits and stops before push/PR/watch. A missing remote is a terminal success state — never retry a push, never hunt for a remote.
