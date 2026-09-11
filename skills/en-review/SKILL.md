---
name: en-review
description: "Multi-persona code review of the current branch with a cross-agent peer on by default: correctness, testing, maintainability and standards always; security, performance and migrations when the diff matches. Trigger phrases: 'review my changes', 'review this branch', 'code review', 'check this PR'."
---


# `/en-review`

> **Running a bundled script.** Anchor every call to this skill's own directory: `SKILL_DIR="<absolute path of the directory containing this SKILL.md>"; bash "$SKILL_DIR/scripts/<name>"`. The trailing `;` is load-bearing. See `references/script-invocation.md`.


> **Dispatching a bundled agent.** This skill carries its agents in `agents/`. Dispatch by name as usual; when the name is not registered (a lone skill directory), resolve it from the bundled definition per `references/agent-dispatch.md`.


Multi-persona, confidence-gated code review **with the cross-agent peer on by default** (EN11). Host personas and the blind peer run concurrently; their findings reconcile into four explicit buckets.

## Process

1. **Detect host.** Source `references/host-detect.md`.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, no peer is dispatched (it would recurse) regardless of the default or an explicit `--peer`. Resolves `peer_decision.reason: recursion-guard`.

2b. **Start the run ledger.** `bash "$SKILL_DIR/scripts/ensemble-run-metrics" start --skill en-review`. A standalone review gets its own ledger; one nested inside `/en-build` gets its own too, with a pointer from the build's. Fire-and-forget; `references/run-metrics.md` carries the event vocabulary.

2a. **Resolve the peer decision** (EN11). Produce ONE `peer_decision` object per the schema in `references/peer-model-policy.md` section (e), and carry it into the report rather than recomputing it later.

   | Condition | `peer` | `reason` |
   |---|---|---|
   | `PEER_MODE=cross-agent` AND mode is `interactive`/`headless` | `on` | `default-on` (or `explicit-flag` if `--peer` was passed) |
   | `--host` passed | `off` | `host-only-mode` |
   | mode is `report-only` | `off` | `report-only-mode` |
   | `ENSEMBLE_PEER_REVIEW=true` | `off` | `recursion-guard` |
   | `PEER_AVAILABLE=false` | `off` | `peer-unavailable` |
   | Diff below `skip_peer_below_lines` | `off` | `auto-skip:diff-below-threshold` |
   | Lightweight depth AND `skip_peer_on_lightweight` | `off` | `auto-skip:lightweight-depth` |

   **`report-only` never runs a peer**: `/en-sweep` invokes `/en-review` in that mode inside CI, where D38 keeps API secrets and repo-write off, so a default peer would silently require credentials there. **`single-agent-fallback` is ON.** With `--peer` the default, "no peer CLI" cannot mean "no review": the peer role runs on the host model in a fresh subprocess, and `peer_decision.peer_mode` records `single-agent-fallback` so the report never reads as a cross-agent pass. `--host` declines the fallback and takes the persona roster instead.

2b. **Read the effort/alias config overrides** (the two high-precedence layers only). This skill is the **SOLE resolver** (`peer-model-policy.md` (b)), but resolution is deliberately **split across two points** because the ladder's inputs do not exist yet at step 2:

   - **Overrides, read here:** the `--effort <low|medium|high|xhigh>` flag, then `$SKILL_DIR/scripts/ensemble-config-get peer_effort_<peer>` (`codex` or `claude`, whichever the peer is; `--allowed low,medium,high,xhigh`; `--legacy peer_effort_override --legacy review_peer_effort_override`). Either one is final; step 7b then skips the ladder.
   - **Models, read here:** `ensemble-config-get peer_model_claude` (alias; `--legacy peer_model_alias --legacy review_peer_model_alias`) and `peer_model_codex` (`-m`; `--legacy peer_codex_model --legacy review_peer_codex_model`). Personas: `$SKILL_DIR/scripts/ensemble-agent-model --agent dimension-reviewer --host "$HOST"` decides model and, on Claude, nothing for effort per call (the installed file's `effort:` does, rendered by `setup` from `agent_effort_claude_*`; D104). No `--model` flag.
3. **Determine mode** (per `references/persona-dispatch.md` and the §5.2.5 contract). The caller picks: `en-build` → `headless` (auto-applies `safe_auto` silently, returns JSON); `en-sweep` → `report-only` (CI; **strictly read-only**, never configurable); a user directly → `interactive` (auto-applies `safe_auto`, surfaces the rest). Mutation rights per mode are the table under Flags.
4. **Resolve the review target.** Most runs review a branch diff, but the target is whatever the invocation names:

   | Invocation | Target |
   |---|---|
   | no target | the branch diff — PR target if on a PR branch, else the default branch (`main` per config) |
   | `--base <ref>` | diff against `<ref>`; `--base HEAD` reviews uncommitted work (`git diff` + `git diff --cached`) |
   | `<git-ref>` or `<ref>..<ref>` | diff between those refs |
   | `<branch-name>` | diff between that branch and the default branch |
   | **`<path>` to a file** | **the file's contents, reviewed as they stand** — not a diff |
   | `--scope <path>` | narrows any of the above to that path |

   **A file target is not a diff.** Its findings carry no base ref, the spec axis (step 7c) does not apply, and Coverage names the target shape so a file review is never read as a branch review.
5. **Read context.**
   - `git diff <base>...HEAD > /tmp/ensemble/en-review/<run-id>/diff.patch`, then read `git diff --stat <base>...HEAD` and open hunks from the file as findings need them. **Do not read the whole diff into the window**: a 250KB branch diff is about 65k tokens re-read on every turn until the next compaction, the personas and the peer each read the file themselves (step 8, step 9), and the detection scans in step 7 are greps over it.
   - Plan(s) referenced by the branch (per branch name `<plan_id>-<slug>` or commit messages citing the plan ID, e.g. `EN03`).
   - `AGENTS.md`, `CLAUDE.md`, project conventions.
6. **Pre-flight lint.** Run `bin/ensemble-lint --scope <path>` **once per changed `docs/` path** and surface its failures as P1 findings before any dispatch. Scope is a file or a directory: one file is seconds, `--scope docs/` walks the tree and took 68s a run on this repo, five runs a build.
7. **Conditional persona detection.** Per `references/persona-dispatch.md`:

   **Peer-sole short-circuit (`--peer`, the default).** Unless `--cross` or `--host` was passed, **run the detection scans below but dispatch no persona**: the conditional-persona heuristics and the diff-signal classification are greps over the diff and cost nothing, and step 7b's effort ladder reads them (a security diff must still resolve `high` when the peer is the only reviewer). Skip the roster in 7a and the persona batch in step 8, and proceed to step 9, where the cross-agent Outside Voice peer is the sole reviewer.

   - Always-on (4): `correctness-reviewer`, `testing-reviewer`, `maintainability-reviewer`, `standards-reviewer`.
   - Conditional (3) — fire when diff content matches: `security-reviewer`, `performance-reviewer`, `migrations-reviewer`.
   - Plus `learnings-research` over `docs/learnings/` for prior terms, decisions and solutions. **Unless step 5's plan already cites `docs/learnings/` paths**: read those files directly, skip the agent, and record `learnings: from-plan (<n> cited)`, since `/en-plan` already ran that pass and a second agent rediscovers citations already on disk.

   **7a. Lite (`--lite`).** A lite run is a lighter review by whichever reviewers the mode runs. Under `--peer` the peer gets `references/peer-brief-lite.md` (correctness, regression risk, standards visible in the diff; one turn). Under `--host` the roster collapses to **`correctness-reviewer` + `standards-reviewer` + a `fast-pass` lens**, skipping `testing`, `maintainability`, `learnings` and all conditionals. Under `--cross`, both. **Fail closed on risk:** when `references/diff-signal-detection.md` finds a risk signal (`is_low_risk` false), or any conditional persona fired above, the **full brief and full roster run regardless of `--lite`** — the gate wins, the flag is advisory. Size does not gate: a quick fix with its test and changelog line is lite. `fast-pass` findings are confidence-capped (anchor ≤ 50) so they surface on their own only at P0; otherwise they reach the actionable tier only by deduping onto an independent persona finding (per `references/persona-dispatch.md`).

   **Emit the `lite_gate:` outcome line** (EN08). Whatever the gate decided, including when `--lite` was never passed, the run says so: the decision is **never a silent override**. Forms and grammar in `references/review-report.md`.
7b. **Finalize the effort tier against the ladder** (EN11-CR-001). The ladder reads which conditional personas fired, `is_small_and_safe`, and the unit's `risk`/`gated` metadata, none of which exist before step 7, so resolving at step 2 would let a security, migration, architectural, destructive or gated diff settle at `low`/`medium`. Resolve here, after classification and before step 8's dispatch:

   - If step 2b produced a tier from `--effort` or config, **use it** (higher precedence than the ladder).
   - Otherwise apply the ordered cascade from `references/peer-model-policy.md` (a): **`high`** when `security-reviewer` or `migrations-reviewer` fired, an architectural trigger is present, or the unit is `risk: destructive` / `gated: true`; **`low`** when `lite_gate` is `applied` or `is_small_and_safe` is `true`; **`medium`** otherwise.

   `high` is evaluated first, so a small-and-safe diff that is nonetheless gated or architectural still resolves `high`. Record the final tier in `peer_decision.effort`.
7c. **Requirements coverage (the spec axis).** When step 5 found a plan, ask the question no persona asks: **does this diff do what the plan asked?** All four always-on personas can pass a change that implements the wrong thing. Report these as their own findings, each citing the unit's U-ID. **Missing:** a unit's `Goal` or `Test scenarios` nothing in the diff satisfies. **Unasked-for:** behaviour no unit called for, scope the plan did not authorize. **Implemented but wrong:** a unit addressed in a way its own `Verification` would not accept. **Do not rerank these against persona findings**: flawless code can solve the wrong problem, and merging the axes lets one mask the other. With no plan, skip the axis and say so in Coverage rather than silently omitting it.

8. **Dispatch, per review mode.** `--peer` (default) dispatches the peer alone: step 7's detection fed the effort tier and nothing else, and no persona roster runs. `--host` dispatches the persona roster alone. Only `--cross` dispatches both, and only `--cross` reaches the reconciliation in step 10.

    **`--cross`: the peer first, then the personas in ONE batch.** Start the peer detached (step 9), then one message with multiple `Agent` tool calls for the roster, each carrying `model: $AGENT_MODEL` from step 2b when non-empty. The peer is **blind** to persona findings (step 9), so nothing orders it after the roster. Collect the personas, then wait for the peer.
9. **Outside Voice peer (runs in `--peer` and `--cross`; `--peer` is the default and makes it the sole reviewer).** Dispatch a cross-agent peer pass over the diff (peer is the other agent per D23):
   - **Blind-peer invariant.** The peer receives the diff, the project context and the goal, and **NOT** the host persona findings. That independence is what makes overlap mean anything, and what licenses the concurrent dispatch in step 8. `references/persona-dispatch.md` states it in full.
   - Build the prompt: `$SKILL_DIR/scripts/ensemble-build-peer-prompt --brief "$SKILL_DIR/references/peer-brief.md" --artifact-file <diff> --project-context "<one-line>" --goal "<one-line>" --peer-mode "$PEER_MODE"` (the brief supplies the review dimensions; pass `references/peer-brief-lite.md` instead when `lite_gate` is `applied`).
   - Translate step 2b's result: `eval "$($SKILL_DIR/scripts/ensemble-peer-flags --effort <tier> --peer-cmd "$PEER_CMD" --model-alias <peer_model_claude> --codex-model <peer_model_codex>)"` → `$PEER_MODEL`, `$PEER_EFFORT`.
   - **Invoke via `$SKILL_DIR/scripts/ensemble-peer-invoke`** with `ENSEMBLE_PEER_REVIEW=true`, passing `$PEER_CMD`, `$PEER_FORMAT`, `$PEER_TURNS`, `$PEER_MODEL`, `$PEER_EFFORT`, the prompt file, `--schema "$SKILL_DIR/scripts/peer-findings.schema.json"`, and the access mode: **`--access read-tree` with the full brief** (callers and tests readable; 25 turns, 1200s), **`--access none` with the lite brief and on the verification pass** (one turn, diff only, 600s). Run it detached: `ensemble_peer_start --job-dir /tmp/ensemble/en-review/<run-id>/peer …` returns at once; after the personas (`--cross`) or immediately (`--peer`), `ensemble_peer_wait <dir> --max-secs 480` in slices until `done` or the ceiling, then `ensemble_peer_result`, or `ensemble_peer_reap` past it. The helper owns invocation, isolation, classification, retry and fallback (EN11-PR-006, D81); not restated here. Merge the returned `peer_decision`'s `peer`/`reason`/`model_actual` into step 2a's object. Parse the peer's findings per `references/finding-schema.md`, tagged `source: "peer"`.
   - **`--peer` (the default), sole reviewer:** the peer's findings ARE the envelope; no reconciliation is needed.
   - **`--cross` (personas + peer):** the peer's findings join the persona findings and both sets reconcile in step 10. Record the reviewer: `cross-agent` (peer ran), `single-agent-fallback` (only one CLI → a fresh subprocess of the host's own CLI), or — only when `PEER_AVAILABLE=false` — fall back to the full host persona roster (steps 7–8) and record `reviewer: en-review-host-fallback` so the weaker, same-agent evidence is visible.
   - **Peer off** (any `peer: "off"` reason from step 2a): skip this step; the persona findings are the envelope. The reason is still reported.

9a. **Emit the `peer_decision:` outcome line**, so a skip or degradation never reads as a normal peer run (fail-closed, like `lite_gate:`, D42). Its `<reason>` MUST be a member of the closed enum in `references/peer-model-policy.md` (e); the format is in `references/review-report.md`.
10. **Synthesize.** With one source — `--peer` or `--host` — there is nothing to reconcile: validate, collect, and report. Say which single source produced the findings so nobody reads a one-source pass as a corroborated one.

    **Under `--cross`, run `references/persona-dispatch.md`'s Two-source reconciliation** and **report the `corroborated` bucket first**: two independent reads agreeing is the strongest signal available. The other three buckets are reported below it, never dropped, because `peer-only` is what the host missed and is usually the reason to run a peer at all, and `host-only` is where project context lives. Three of its rules bind this step's callers: `conflicting` records are **never auto-applied** and step 12 excludes them from the frozen authorized set; the rank is `corroborated` first, then P0 → P3, then confidence, then persona priority; and `fast-pass` findings are barred from corroboration promotion.
11. **Confidence gate.** Read `review.confidence_threshold` from `~/.ensemble/config.json` (default `7`). Findings with `confidence < threshold` are **filtered out** of the surfaced output and **filed as TD entries** in `docs/plans/tech-debt-tracker.md` with the marker `Filed by /en-review (confidence <N>)`. Per `references/review-confidence-gating.md`. In `report-only` nothing is filed; sub-threshold findings return in the envelope under `sub_threshold_findings: []`.
12. **Apply / surface — two-phase mutation protocol (EN08).** `references/mutation-protocol.md` owns both phases and the verification pass below; read it here. The applied set is a *boundary fixed before editing*, not a post-hoc assertion. Four rules bind every mode:

    - **Authorization precedes mutation.** Collect ALL authorizations up front, freeze one final authorized set, and capture the pre-review baseline, all before ANY edit. The frozen set never changes after mutation begins, and any finding you do not understand stops the phase before authorizations are collected.
    - **Per mode.** `interactive` applies the frozen set, and **`manual` findings are NEVER applied without the user's explicit pick, and the pick always precedes mutation**. `headless` applies `safe_auto` ONLY, silently. `report-only` applies nothing.
    - **P0 halt.** Any P0 finding halts ALL automatic mutation — including `safe_auto` and `gated_auto` — until severity.md's P0 pause-and-ask handling occurs.
    - **The recorded set bounds the tree.** `applied_fixes[]` derives from the ACTUAL before-vs-after delta, excluding pre-existing changes, and the working-tree delta attributable to the review MUST NOT exceed the recorded `applied_fixes[]`. **en-review MUST NOT implement findings outside the mode-permitted, announced, and recorded `applied_fixes[]` set — wholesale implementation of findings is a contract violation.**

    **Emit the `review_fixes:` outcome line**, derived from `applied_fixes[]` and never composed independently. Forms and the count invariant in `references/review-report.md`.
12a. **Verification pass (severity-gated, one pass).** A fix can be wrong or introduce a new fault, and the findings above describe the code before it. So when this run addressed any **P0 or P1** finding (an `applied_fixes[]` entry whose finding is P0/P1), or `--verify` was passed, review once more against the same target, mode, review mode and effort tier, with `references/peer-brief-lite.md` whatever `lite_gate` said: the pass is narrow by design, confirming the fixes landed and scanning the changed hunks for new P0/P1. `references/mutation-protocol.md` owns the previous-review context passed as `--iteration-context-file`, and the envelope selection under bare `--verify`.

    **One pass, never a loop.** A P0/P1 the verification pass reports, unfixed or new, is surfaced with its id and **never applied in this run**: the frozen set closed above, and a third pass mostly resamples the second (D49). Fixing it is a new run.

    **Emit the `verification_pass:` outcome line**, including on a run where the pass did not fire. When the pass ran, the envelope's `verdict` is its verdict. Forms and reasons in `references/review-report.md`.
13. **Record the outcome, output the report, then close the run.** First: `bash "$SKILL_DIR/scripts/ensemble-run-metrics" emit --kind outcome --json '{"verdict":"<approve|revise|reject>","findings_total":<n>,"peer_only":<n>,"corroborated":<n>,"host_only":<n>,"applied":<n>,"deferred":<n>,"disagreed":<n>}'` — the counts step 10's reconciliation and step 12's application already produced. **This is the one event a helper cannot observe**: the buckets exist only in the reconciliation, and `ensemble-peer-invoke` has no notion of corroboration, which is why this single call point is the deliberate exception to helper-emitted recording. Keys not in the `outcome` allowlist are dropped at the write, so add a key to both or to neither. Then finish with `bash "$SKILL_DIR/scripts/ensemble-run-metrics" finish`. **Every terminal path closes the run**, a failed peer and an empty mode included. Per `references/review-report.md`, which owns the envelope shape and the markdown summary: write the envelope to `/tmp/ensemble/en-review/<run-id>/envelope.json`, emit the markdown summary alongside it in every mode including `headless` and `report-only`, and name the path in the summary so `--verify` can read it. Both carry `sub_threshold_filed_count`, how many findings were filed as TD entries (or surfaced separately in `report-only`).

## Flags

**`--peer`, `--cross` and `--host` are mutually exclusive review modes**; passing two is an error, not a merge. `--peer` is the default, so a bare `/en-review` is a peer-only pass.

| Flag | Effect |
|---|---|
| `--mode interactive\|headless\|report-only` | Override the default mode (caller-selected; see step 3) |
| `--peer` | **Default.** The peer is the sole reviewer; host personas do not run. Where no peer CLI exists, the peer role runs on the host model in a **fresh subprocess** rather than being skipped — see the fallback note in step 2a. |
| `--cross` | Host personas **and** the peer, reconciled into the four buckets, **corroborated findings reported first**. The thorough mode: it is the only one that produces standards / testing / maintainability findings with project context alongside an independent read. Used by `/en-build` (D46). |
| `--host` | Host personas only, in fresh-context sub-agents. No peer subprocess and no same-model fallback. |
| `--effort low\|medium\|high\|xhigh` | Pin the peer's reasoning-effort tier for this run, the highest-precedence layer in `references/peer-model-policy.md` (b). Omit to let repo config, then user config, then the ladder decide. |
| `--base <ref>` | Override diff base |
| `--no-lint` | Skip pre-flight lint |
| `--scope <path>` | Limit review to a path (default: full target) |
| `--focus security\|performance\|tests\|correctness\|maintainability\|all` | Bias the reviewer's attention toward one concern. It **narrows emphasis, never coverage**: a P0 outside the focus is still reported. In `--cross` it biases the peer only; the roster is already dimension-split. |
| `--lite` | A lighter review for a quick fix (step 7a): lite brief for the peer, `correctness` + `standards` (+ `fast-pass`) for the roster. **Fail-closed on risk**; size does not gate. |
| `--verify [<envelope-path>]` | Run only the verification pass of step 12a against a previous run's envelope, for P0/P1 fixes made after that run. Bare, it takes the newest matching envelope under `/tmp/ensemble/en-review/`. |

## Mutation rules per mode

| Mode | Auto-apply `safe_auto`? | Surface `gated_auto`/`manual`? | Apply user-selected fixes? | Commit? |
|---|---|---|---|---|
| `interactive` | Yes | Yes (asks user) | Yes | No (user runs `/en-ship`) |
| `headless` | Yes (silent) | No (returns JSON) | N/A | No |
| `report-only` | **No** | No | N/A | No |

Every application is recorded in `applied_fixes[]` (`{finding_id, tier, files[]}`, `files[]` sorted and deduplicated) and echoed by the mandatory `review_fixes:` line (step 12). Tier definitions live in `references/severity.md`, referenced, not duplicated.

**Post-review check** (`references/post-review-check.md`). Ask `$SKILL_DIR/scripts/ensemble-verification-receipt` first: a valid receipt skips lint, typecheck and tests, which is only possible when nothing was applied. Otherwise run lint, typecheck and the graph-selected set (`test_changed_command`), revert the applied edits on failure, and on success record `lint`, `typecheck` and `targeted_tests` for `/en-ship`. `report-only` never runs it.

## Failure protocol

`references/persona-dispatch.md` owns the persona-side failures (a persona times out, returns malformed JSON, all fail, the diff is too large for one context). These three are en-review's own:

| Failure | Behavior |
|---|---|
| Mode is `report-only` but `safe_auto` would apply | Note "Would apply N safe_auto fixes (skipped — report-only mode)" in summary; don't apply |
| Re-verification fails after applying findings | Revert; surface to user; do not commit |
| Verification pass peer times out or returns malformed JSON | `verification_pass: not-run (peer-failure)`; the initial verdict stands, flagged as unverified |
