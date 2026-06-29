# Debug investigation — anti-patterns & techniques

Loaded by `/en-debug` code mode before hypothesis formation. Adapted from compound-engineering `ce-debug`.

## Anti-patterns (stop if you catch yourself here)

These phrases mark mode-drift toward symptom patches, not progress on the root cause:

- **"Quick fix for now, investigate later."** The quick fix becomes permanent and the cause stays active.
- **"This should work"** — stated without a tested prediction. If you can't predict what else must be true, you don't understand the cause yet.
- **"Let me just try…"** — a change with no hypothesis. That's shotgun debugging; one change at a time, each testing one hypothesis.
- **"One more attempt"** after a failed fix, retrying variants of the same theory ("maybe it was the other branch", "let me also catch this case"). This is the rationalization spiral — invalidate the hypothesis explicitly and form a new one instead.
- **"Works on my machine."** That's an environment signal, not a dismissal — chase the env/config/timing difference.

## Assumption audit

Before forming hypotheses, list the concrete "this must be true" beliefs your understanding depends on — the framework behaves as expected here, this function returns what its name implies, the config loads before this runs, the caller passes non-null, the DB is in the state the test implies. Mark each *verified* (you read the code, checked state, or ran it) or *assumed*. Assumptions are the most common source of stuck debugging — many "wrong hypotheses" are correct hypotheses tested against a wrong assumption.

## Grounding observations

A hypothesis needs at least one concrete observation, not a hunch:

- ❌ "X seems off."
- ✅ "X equals null at `line 42` because Y was never initialized in the constructor path that runs under condition Z."

Grounding = a runtime variable value, a log line, an instrumented boundary capture, a behavior delta against a working comparison case, or a specific code reference. No grounding → go back and instrument.

## Predictions for uncertain links

When a link in the causal chain is uncertain, form a prediction — something in a *different* code path or scenario that must also be true if the link is correct. Test it. If the prediction is wrong but a fix appears to work, you found a symptom; the real cause is still active. When the chain is obvious (missing import, clear null deref), the chain explanation itself is sufficient — predictions are for uncertain links, not a ritual for every hypothesis.

## Intermittent / won't-reproduce bugs

When a bug doesn't reproduce after 2–3 attempts:

- **Add timing variance** — run under load, with delays, concurrently. Races hide at steady state.
- **Vary the environment** — fresh process, cold cache, different data ordering, different locale/timezone.
- **Capture more state at the boundary** — log inputs/outputs around the suspected frame across many runs; look for the run that differs.
- **Check shared/global state** — singletons, module-level caches, connection pools that carry state between requests.
- **Bisect history** — `git bisect` when it's a regression ("worked before").

## Smart escalation table

After 2–3 exhausted hypotheses, diagnose *why* rather than trying harder:

| Pattern | Diagnosis | Next move |
|---|---|---|
| Hypotheses point to different subsystems | Architecture/design problem, not a localized bug | Present findings; suggest `/en-brainstorm` |
| Evidence contradicts itself | Wrong mental model of the code | Re-read the code path without assumptions |
| Works locally, fails in CI/prod | Environment problem | Focus on env/config/dependencies/timing |
| Fix works but prediction was wrong | Symptom fix, not root cause | Keep investigating; the real cause is active |
