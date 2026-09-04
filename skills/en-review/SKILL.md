---
name: en-review
description: "Multi-persona code review of the current branch with a cross-agent peer on by default: correctness, testing, maintainability and standards always; security, performance and migrations when the diff matches. Trigger phrases: 'review my changes', 'review this branch', 'code review', 'check this PR'."
---


# `/en-review`

> **Running a bundled script.** Anchor every call to this skill's own directory: `SKILL_DIR="<absolute path of the directory containing this SKILL.md>"; bash "$SKILL_DIR/scripts/<name>"`. The trailing `;` is load-bearing. See `references/script-invocation.md`.


> **Dispatching a bundled agent.** This skill carries its agents in `agents/`. Dispatch by name as usual; when the name is not registered (a lone skill directory), resolve it from the bundled definition per `references/agent-dispatch.md`.


Multi-persona, confidence-gated code review **with the cross-agent peer on by default** (EN11). Host personas and the blind peer run concurrently; their findings reconcile into four explicit buckets.

> **Peer contract.** Severity, confidence, autofix class, the `peer_decision`
> object and its reason enum are defined once in `references/peer-contract.md`
> and are byte-identical across every skill that exchanges findings. What this
> skill *does* with a finding is its own policy, not part of that contract.

> **Peer brief.** What the peer is asked, and what this skill does with the
> answer, is in `references/peer-brief.md`. The wire format it shares with every
> other skill is `references/peer-contract.md`.

## Process

1. **Detect host.** Source `references/host-detect.md`.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, no peer is dispatched (it would recurse) regardless of the default or an explicit `--peer`. Resolves `peer_decision.reason: recursion-guard`.

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

   Two carve-outs are deliberate, not oversights. **`report-only` never runs a peer**: `/en-sweep` invokes `/en-review` in that mode inside CI, and D38 deliberately keeps API secrets and repo-write off CI, so defaulting a peer on there would silently require peer CLI credentials. **`single-agent-fallback` is ON.** With `--peer` as the default, the peer is the sole reviewer, so "no peer CLI" cannot mean "no review" — the peer role runs on the host model in a fresh subprocess instead, and `peer_decision.peer_mode` records `single-agent-fallback` so the report never reads as a cross-agent pass. It is a weaker review than a genuinely different architecture, and the recorded mode is what says so. `--host` is the way to decline the fallback and take the persona roster instead.

2b. **Read the effort/alias config overrides** (the two high-precedence layers only). This skill is the **SOLE resolver** (`peer-model-policy.md` (b)), but resolution is deliberately **split across two points** because the ladder's inputs do not exist yet at step 2:

   - **Overrides, read here:** the `--effort <low|medium|high>` flag, then `$SKILL_DIR/scripts/ensemble-config-get review_peer_effort_override --allowed low,medium,high`. If either yields a tier, that tier is final and step 7b skips the ladder.
   - **Model alias, read here:** `$SKILL_DIR/scripts/ensemble-config-get review_peer_model_alias` → the default alias. There is no `--model` run flag by design, and the alias does not depend on diff signals.

   The repo-then-global cascade inside each lookup belongs to `$SKILL_DIR/scripts/ensemble-config-get`, and translating the resolved tier into CLI syntax belongs to `$SKILL_DIR/scripts/ensemble-peer-flags`. Neither re-derives policy, so precedence exists in exactly one place.
3. **Determine mode** (per `references/persona-dispatch.md` and the §5.2.5 contract):
   - **`interactive`** — direct user invocation. Auto-applies `safe_auto` fixes; surfaces `gated_auto` / `manual` to user. May write to working tree.
   - **`headless`** — invoked by another skill (`/en-build`'s post-build review). Auto-applies `safe_auto` silently; returns structured JSON. May write to working tree.
   - **`report-only`** — invoked from CI (`en-sweep`). **Strictly read-only.** No edits, no commits. Returns findings JSON only.

   The mode is selected by the caller (or the skill picks based on context). Mandatory rules:
   - `en-build` → `headless`.
   - `en-sweep` → `report-only` (never configurable).
   - User direct → `interactive`.
4. **Resolve the review target.** Most runs review a branch diff, but the target is whatever the invocation names:

   | Invocation | Target |
   |---|---|
   | no target | the branch diff — PR target if on a PR branch, else the default branch (`main` per config) |
   | `--base <ref>` | diff against `<ref>`; `--base HEAD` reviews uncommitted work (`git diff` + `git diff --cached`) |
   | `<git-ref>` or `<ref>..<ref>` | diff between those refs |
   | `<branch-name>` | diff between that branch and the default branch |
   | **`<path>` to a file** | **the file's contents, reviewed as they stand** — not a diff |
   | `--scope <path>` | narrows any of the above to that path |

   **The file case is not a diff, and the difference matters.** A diff review asks "is this change sound"; a file review asks "is this code sound". Findings from a file target carry no base ref, the spec axis (step 7c) does not apply because there is no plan unit to check against, and Coverage says which target shape produced the findings so nobody reads a file review as a branch review.
5. **Read context.**
   - `git diff <base>...HEAD` — the full diff under review.
   - Plan(s) referenced by the branch (per branch name `<plan_id>-<slug>` or commit messages citing the plan ID, e.g. `EN03`).
   - `AGENTS.md`, `CLAUDE.md`, project conventions.
6. **Pre-flight lint.** Run `bin/ensemble-lint --scope docs/` and `bin/ensemble-lint` on changed `docs/` paths. Surface lint failures as P1 findings before persona dispatch.
7. **Conditional persona detection.** Per `references/persona-dispatch.md`:

   **Peer-sole short-circuit (`--peer`, the default).** Unless `--cross` or `--host` was passed, **skip persona detection and dispatch entirely (steps 7, 7a, 8)** and proceed directly to step 9, where the cross-agent Outside Voice peer is the sole reviewer. This is also what `/en-build`'s post-build phase relies on: the host implemented the code, so the review must come from the *other* agent.

   This block said `--peer-only` until 2026-09-03. That flag was renamed to `--peer` on 2026-09-01 and made the default; the short-circuit is therefore the ordinary path, not an opt-in, and the sentence describing it as one read as though the persona roster ran by default. It does not.

   **`--lite` does nothing under `--peer`.** It collapses the *host persona roster*, and this mode runs no personas. That used to be a rare collision between two opt-ins; with `--peer` as the default it is what happens to anyone who passes `--lite` alone. Do not silently ignore it: report `lite_gate: overridden (no-persona-roster)` so the run says the flag had no effect, and pair `--lite` with `--host` or `--cross` to get the collapsed roster. The reason id is the existing `overridden` shape rather than a fourth outcome, so the three-value enum and the JSON envelope are unchanged.

   - Always-on (4): `correctness-reviewer`, `testing-reviewer`, `maintainability-reviewer`, `standards-reviewer`.
   - Conditional (3) — fire when diff content matches: `security-reviewer`, `performance-reviewer`, `migrations-reviewer`.
   - Plus `learnings-research` to query `docs/learnings/` for relevant prior terms, decisions, and solutions.

   **7a. Lite roster (`--lite`).** When `--lite` is passed, classify the diff via `references/diff-signal-detection.md`. If `is_small_and_safe` is `true` (1–39 executable lines, zero uncounted files, no risk signals, **and** no conditional persona was triggered above), collapse the roster to **`correctness-reviewer` + `standards-reviewer` + a `fast-pass` lens** — skip `testing`, `maintainability`, `learnings`, and all conditionals. **Fail closed:** if `is_small_and_safe` is `false` for any reason (unknown line count, any uncounted non-code file, any risk signal, or any conditional persona fired), run the **full roster regardless of `--lite`** — the gate wins, the flag is advisory. `fast-pass` findings are confidence-capped (anchor ≤ 50) so they surface on their own only at P0; otherwise they reach the actionable tier only by deduping onto an independent persona finding (per `references/persona-dispatch.md`).

   **Mandatory `lite_gate:` outcome line (EN08).** EVERY run emits exactly ONE `lite_gate:` line in the markdown summary — so a missing line is always distinguishable from a not-requested lite, and the gate's decision is **never a silent override**:

   - `lite_gate: applied` — `--lite` requested, roster collapsed.
   - `lite_gate: overridden (<reasons>)` — `--lite` requested but the fail-closed gate won. `<reasons>` uses the **canonical override-reason identifiers from `references/diff-signal-detection.md`** (`unknown-line-count`, `exec-lines-out-of-range`, `uncounted-files`, `risk-signal`, `conditional-persona:<names>`), deduplicated, in that fixed canonical order, comma+space separated, with exactly one space before the paren. Persona names in `conditional-persona:` are alphabetically sorted and `+`-joined. Example: `lite_gate: overridden (risk-signal, conditional-persona:performance+security)`.
   - `lite_gate: not-requested` — the run had no `--lite` flag.

   The JSON envelope carries the structured form (see envelope shape): `"lite_gate": {"outcome": "applied" | "overridden" | "not-requested", "reasons": []}` with `reasons` in the same canonical order (empty for `applied` / `not-requested`); the markdown line is DERIVED from that object, never composed independently.
7b. **Finalize the effort tier against the ladder** (EN11-CR-001). The ladder's inputs — which conditional personas fired, `is_small_and_safe`, and the unit's `risk`/`gated` metadata — only exist once steps 7 and 7a have run, so resolving the tier at step 2 would let a diff resolve `low`/`medium` **before** a security, migration, architectural, destructive, or gated signal established that `high` was required. Resolve here, after classification and before step 8's dispatch:

   - If step 2b produced a tier from `--effort` or config, **use it** (higher precedence than the ladder).
   - Otherwise apply the ordered cascade from `references/peer-model-policy.md` (a): **`high`** when `security-reviewer` or `migrations-reviewer` fired, an architectural trigger is present, or the unit is `risk: destructive` / `gated: true`; **`low`** when `is_small_and_safe` is `true`; **`medium`** otherwise.

   `high` is evaluated first, so a small-and-safe diff that is nonetheless gated or architectural still resolves `high`. Record the final tier in `peer_decision.effort`.
7c. **Requirements coverage (the spec axis).** When step 5 found a plan for this branch, one more question is on the table, and it is not the one any persona asks: **does this diff do what the plan asked?** The personas judge the diff on its own terms — is it correct, tested, maintainable, conventional. All four can pass on a change that implements the wrong thing.

    Read the plan's units and check three things, reported as their own findings rather than folded into a persona's:

    - **Missing:** a unit's `Goal` or `Test scenarios` that nothing in the diff satisfies.
    - **Unasked-for:** behaviour in the diff no unit called for — scope the plan did not authorize and review would otherwise wave through as clean code.
    - **Implemented but wrong:** a unit whose requirement is addressed in a way its own `Verification` would not accept.

    Cite the unit's U-ID on every finding, so the plan and the review reconcile by ID rather than by prose. **Do not rerank these against persona findings** — a diff can be flawless code that solves the wrong problem, and merging the two axes is what lets one mask the other. Skip the axis entirely when step 5 found no plan, and say so in Coverage rather than silently omitting it.

8. **Dispatch, per review mode.** `--peer` (default) dispatches the peer alone — no persona roster, so steps 7/7b/7c produced routing that this mode does not consume, and the conditional-persona work is skipped rather than computed and discarded. `--host` dispatches the persona roster alone. Only `--cross` dispatches both, and only `--cross` reaches the reconciliation in step 10.

    **`--cross`: personas AND the peer in ONE batch.** Single message, multiple `Agent` tool calls, **plus the peer subprocess from step 9 launched in the same batch**. Because the peer is **blind** to persona findings (see step 9), nothing orders it after the persona roster, so serializing it would add its latency to every review for no benefit (`peer_timeout_seconds` defaults to 600). Wait for all to return.
9. **Outside Voice peer (runs in `--peer` and `--cross`; `--peer` is the default and makes it the sole reviewer).** Dispatch a cross-agent peer pass over the diff (peer is the other agent per D23):
   - **Blind-peer invariant.** The peer receives the diff, the project context, and the goal. It does **NOT** receive the host persona findings. This is load-bearing, not an omission: anchoring the peer on host findings turns independent discovery into confirmation, and overlap then stops being evidence of anything. It is also what makes the concurrent dispatch in step 8 valid. Any change that feeds persona findings to the peer must also re-serialize step 8 and invalidate the corroboration weighting in step 10.
   - Build the prompt: `$SKILL_DIR/scripts/ensemble-build-peer-prompt --brief "$SKILL_DIR/references/peer-brief.md" --artifact-file <diff> --project-context "<one-line>" --goal "<one-line>" --peer-mode "$PEER_MODE"` (the brief supplies the review dimensions; the artifact type is fixed per skill since D50).
   - Translate the tier resolved in step 2b: `eval "$($SKILL_DIR/scripts/ensemble-peer-flags --effort <tier> --peer-cmd "$PEER_CMD" --model-alias <alias>)"` → `$PEER_MODEL`, `$PEER_EFFORT`.
   - **Invoke via `$SKILL_DIR/scripts/ensemble-peer-invoke`** with `ENSEMBLE_PEER_REVIEW=true`, passing `$PEER_CMD`, `$PEER_FORMAT`, `$PEER_TURNS`, `$PEER_MODEL`, `$PEER_EFFORT`, and the prompt file. **Do not restate the retry algorithm here** — the helper owns invocation, classification, the single bounded retry that drops only the rejected fragment, and the fallback, so the behavior is executable and testable rather than prose (EN11-PR-006). It returns the updated `peer_decision`; merge its `peer`/`reason` into step 2a's object. Parse the peer's findings per `references/finding-schema.md`, tagged `source: "peer"`.
   - **`--peer` (the default), sole reviewer:** the peer's findings ARE the envelope; no reconciliation is needed.
   - **`--cross` (personas + peer):** the peer's findings join the persona findings and both sets reconcile in step 10. This bullet was labelled "Default" until 2026-09-03, which had the two modes exactly backwards: `--cross` is the thorough opt-in, and the default is peer-sole. Record the reviewer: `cross-agent` (peer ran), `single-agent-fallback` (only one CLI → fresh-subprocess per `references/single-agent-fallback.md`), or — only when `PEER_AVAILABLE=false` — fall back to the full host persona roster (steps 7–8) and record `reviewer: en-review-host-fallback` so the weaker, same-agent evidence is visible.
   - **Peer off** (any `peer: "off"` reason from step 2a): skip this step; the persona findings are the envelope. The reason is still reported.

9a. **Mandatory `peer_decision:` outcome line.** EVERY run emits exactly ONE, so a skip or a degradation can never read as a normal peer run — the same fail-closed discipline as `lite_gate:` (D42). Format: `peer_decision: <peer> (<reason>, effort=<tier>)`, e.g. `peer_decision: on (default-on, effort=medium)` / `peer_decision: off (report-only-mode, effort=medium)` / `peer_decision: degraded (dropped-effort-fragment, effort=high)`. `<reason>` MUST be a member of the closed enum in `references/peer-model-policy.md` (e). The JSON envelope carries the structured `peer_decision` object; the markdown line is DERIVED from it, never composed independently.
10. **Synthesize.** With one source — `--peer` or `--host` — there is nothing to reconcile: validate, collect, and report. Say which single source produced the findings so nobody reads a one-source pass as a corroborated one.

    **Under `--cross`, reconcile the two sources** and **report the `corroborated` bucket first**: two independent reads agreeing is the strongest signal available, so it leads. The other three buckets are still reported below it, never dropped — `peer-only` is what the host missed and is usually the reason to run a peer at all, and `host-only` is where project context lives. Per `references/persona-dispatch.md`:
    - Validate each response (drop malformed).
    - Collect findings; preserve persona attribution and tag `source: host | peer`.
    - Dedup **within** the host set by location + title-similarity ≥ 0.7 (merge personas; same-source overlap boosts confidence +1).
    - **Two-source reconciliation** (when a peer ran): one global pass over a shared consumption pool — **conflict stage first** (contradictory cross-source pairs at a `location`, consuming both members, so a contradiction is never masked by a similarity match), then **corroboration** on the remainder (same `>= 0.7` predicate, one-to-one, greedy by descending similarity), then **singles**. Ties break on ascending `finding_id`. Emit `reconciliation[]` records with `bucket` / `sources[]` / `canonical` / `contributing[]` per `references/finding-schema.md`.
    - **Assert the partition invariant:** the total `contributing[]` count across all records equals the raw finding count. Every finding lands in exactly one record; none is both corroborated and conflicting, and none is dropped.
    - Cross-source corroboration boosts confidence **+2** (capped at 10) versus **+1** for same-source, because independent architectures agreeing is stronger evidence than two same-stack personas agreeing. `fast-pass` findings remain barred from corroboration promotion.
    - Rank `corroborated` first, then surface `peer-only` prominently. `conflicting` records surface both sides and are **never auto-applied** (they are excluded from the frozen authorized set in step 12).
    - Severity reorder: P0 → P3, then confidence, then persona priority.
11. **Confidence gate.** Read `review.confidence_threshold` from `~/.ensemble/config.json` (default `7`). Findings with `confidence < threshold` are **filtered out** of the surfaced output and **filed as TD entries** in `docs/plans/tech-debt-tracker.md` with the marker `Filed by /en-review (confidence <N>)`. This keeps a paper trail without cluttering review noise. Per `references/review-confidence-gating.md`. Skipped in `report-only` mode (no mutations allowed; sub-threshold findings are returned in the JSON envelope under `sub_threshold_findings: []` instead).
12. **Apply / surface — two-phase mutation protocol (EN08).** The applied set is a *boundary fixed before editing*, not a post-hoc assertion:

    **Phase 1 — authorize, then baseline + freeze (before ANY edit).** Authorization comes FIRST, so the frozen set never changes after mutation begins:
    0. **Any finding you do not understand stops the whole phase.** Before collecting authorizations, read the frozen candidates and ask about anything ambiguous — what the finding means, what fix it implies, whether it holds for this codebase. **Ask about all of them at once, and apply nothing until they are answered.** Findings interact: applying the four you understood and asking about the fifth is how a partial reading becomes a wrong implementation, and the frozen-set protocol below cannot undo it because the set was already frozen around a misreading. In `headless` and `report-only` there is no one to ask, so an ambiguous finding is not authorized — it is surfaced unapplied with the ambiguity named.

    1. **Collect ALL authorizations up front.** In `interactive` mode, surface every finding before touching anything: `gated_auto` announcements (user can decline) and `manual` picks are gathered NOW — not mid-run. In `headless` mode there is no user, so the authorized set is `safe_auto` findings ONLY. In `report-only` the authorized set is empty.
    2. **Freeze one final authorized set** — the ONLY findings whose fixes may be applied this run, per the severity.md action matrix. A finding not in the frozen set is not applied this run, period; if the user wants more later, that is a NEW run with a new baseline.
    3. **Capture the pre-review baseline** with a non-mutating snapshot that covers **content of tracked AND untracked files** — e.g. a temporary-index tree (`GIT_INDEX_FILE=<tmp> git add -A && git write-tree` against a throwaway index) or a content-hash manifest over every working-tree path (`git ls-files -co --exclude-standard` + per-file hashes). `git status --porcelain` alone is NOT sufficient (it records that an untracked path exists, not its content) and `git stash create` does NOT preserve untracked content — without content coverage, a review edit to a pre-existing untracked file could not be distinguished from the user's original work. Pre-existing dirty-tree changes belong to the user, never to the review.

    **Phase 2 — apply within the frozen set.**
    - In `interactive` mode: apply the frozen set (auto-tier `safe_auto`; `gated_auto` entries the user did not decline; `manual` entries the user explicitly picked in Phase 1). Re-verify after. **`manual` findings are NEVER applied without the user's explicit pick, and the pick always precedes mutation.**
    - In `headless` mode: apply `safe_auto` ONLY, silently; return JSON envelope with all findings.
    - In `report-only` mode: never apply anything; return JSON only.
    - **P0 halt:** any P0 finding halts ALL automatic mutation — including `safe_auto` and `gated_auto` — until severity.md's P0 pause-and-ask handling occurs.
    - Stop before touching any finding or file outside the frozen set. **en-review MUST NOT implement findings outside the mode-permitted, announced, and recorded `applied_fixes[]` set — wholesale implementation of findings is a contract violation.** Permitted auto-fixes per the severity.md matrix are in-contract; anything beyond them is *implementing*, which belongs to `/en-build` / `/en-resolve-pr`, not review.

    **Record.** Derive `applied_fixes[]` from the ACTUAL before-vs-after tree delta (baseline vs post-review), excluding pre-existing changes — never from intent. The working-tree delta attributable to the review MUST NOT exceed the recorded `applied_fixes[]`.

    **Mandatory `review_fixes:` outcome line.** Every run emits exactly one:
    - `review_fixes: applied <N> (<finding-ids with tiers>)` — `<N>` MUST equal the count of unique `applied_fixes[]` entries; the list is DERIVED from the array: finding IDs in ascending ID order, each rendered `<finding_id>/<tier>`, comma+space separated. Example: `review_fixes: applied 2 (rev-1-3/safe_auto, rev-1-7/safe_auto)`.
    - `review_fixes: none` — nothing applied (and `applied_fixes` MUST be `[]`).
    - `review_fixes: none (report-only)` — report-only mode (and `applied_fixes` MUST be `[]`).
13. **Output report.** Markdown summary (for human consumption) plus JSON envelope (for programmatic callers). Both include a `sub_threshold_filed_count` line indicating how many findings were filed as TD entries (or surfaced separately in `report-only`).

## Flags

| Flag | Effect |
|---|---|
| `--mode interactive\|headless\|report-only` | Override default mode |

**`--peer`, `--cross` and `--host` are mutually exclusive review modes**; passing two is an error, not a merge. `--peer` is the default, so a bare `/en-review` is a peer-only pass.

| Flag | Effect |
|---|---|
| `--peer` | **Default.** The peer is the sole reviewer; host personas do not run. Fastest and cheapest of the three. Where no peer CLI exists, the peer role runs on the host model in a **fresh subprocess** rather than being skipped — see the fallback note in step 2a. |
| `--cross` | Host personas **and** the peer, reconciled into the four buckets, **corroborated findings reported first**. The thorough mode: it is the only one that produces standards / testing / maintainability findings with project context alongside an independent read. Used by `/en-build` (D46). |
| `--host` | Host personas only, in fresh-context sub-agents. No peer subprocess. Use when no peer is wanted or reachable and you do not want the same-model fallback. |
| `--effort low\|medium\|high` | Pin the peer's reasoning-effort tier for this run, the highest-precedence layer in `references/peer-model-policy.md` (b). Omit to let repo config, then user config, then the ladder decide. |
| `--base <ref>` | Override diff base |
| `--no-lint` | Skip pre-flight lint |
| `--scope <path>` | Limit review to a path (default: full target) |
| `--focus security\|performance\|tests\|correctness\|maintainability\|all` | Bias the reviewer's attention toward one concern. It **narrows emphasis, never coverage**: a P0 outside the focus is still reported, because a reviewer that suppresses a security finding while focused on tests is worse than one that was never focused. In `--cross` it biases the peer only; the persona roster is already dimension-split. |
| `--lite` | Fast path for tiny, low-risk diffs: collapse to `correctness` + `standards` (+ `fast-pass`) when `references/diff-signal-detection.md` classifies the diff `is_small_and_safe`. **Fail-closed** — any uncounted file, unknown line count, risk signal, or triggered conditional persona forces the full roster regardless of the flag. |

## Mutation rules per mode

| Mode | Auto-apply `safe_auto`? | Surface `gated_auto`/`manual`? | Apply user-selected fixes? | Commit? |
|---|---|---|---|---|
| `interactive` | Yes | Yes (asks user) | Yes | No (user runs `/en-ship`) |
| `headless` | Yes (silent) | No (returns JSON) | N/A | No |
| `report-only` | **No** | No | N/A | No |

`report-only` is the **mandatory** mode when `/en-sweep` invokes `/en-review` in CI. Why that is mandatory, and what sweep does with the findings, belongs to `/en-sweep`; from this side the mode is simply read-only.

**Auditable boundary (EN08).** Every application is recorded in `applied_fixes[]` (each entry `{finding_id, tier, files[]}`, `files[]` sorted and deduplicated) and echoed by the mandatory `review_fixes:` outcome line (see step 12). Tier definitions live in `references/severity.md` — referenced, not duplicated.

## Re-verification

If the skill applies any code edits in `interactive` or `headless` mode, run unit tests + lint after. On failure: revert the applied edits; surface the regression.

## JSON envelope shape

```json
{
  "verdict": "approve | revise | reject",
  "summary": "<2-3 sentence overall>",
  "personas": ["correctness", "testing", "maintainability", "standards", "security"],
  "mode": "interactive | headless | report-only",
  "lite_gate": {"outcome": "applied | overridden | not-requested", "reasons": []},
  "diff_base": "main",
  "diff_files_count": 12,
  "lint_findings_count": 0,
  "applied_safe_auto_count": 3,
  "applied_fixes": [
    {"finding_id": "rev-1-2", "tier": "safe_auto", "files": ["src/auth/refresh.ts"]},
    {"finding_id": "rev-1-5", "tier": "safe_auto", "files": ["src/lib/redis.ts"]},
    {"finding_id": "rev-1-8", "tier": "safe_auto", "files": ["tests/auth/refresh.test.ts"]}
  ],
  "findings": [
    {
      "severity": "P1",
      "confidence": 9,
      "title": "...",
      "location": "src/auth/refresh.ts:42",
      "personas": ["correctness", "security"],
      "why_it_matters": "...",
      "suggested_fix": "...",
      "autofix_class": "manual",
      "applied": false
    }
  ]
}
```

## Markdown summary

Always emit a markdown summary alongside the JSON, even in `headless`/`report-only`. Example:

```markdown
## Code review — FR07-auth-rotation

**Verdict:** revise (3 findings)
**Personas fired:** correctness, testing, maintainability, standards, security
**Pre-flight lint:** clean
**Auto-applied:** 3 safe_auto fixes
lite_gate: not-requested
review_fixes: applied 3 (rev-1-2/safe_auto, rev-1-5/safe_auto, rev-1-8/safe_auto)

### High (P1)

- **U3 — Refresh token race in concurrent path** (correctness, security; conf 9)
  - `src/auth/refresh.ts:42`
  - Two requests can race during rotation; second invalidates the first.
  - Fix: serialize per-user via singleFlight cache.

### Medium (P2)

- **U3 — Missing test for expired-token path** (testing; conf 7)
  - `tests/auth/refresh.test.ts`
  - Coverage gap on the most-likely production path.

### Advisory

- **U2 — Variable name `tmp` in src/lib/redis.ts:18** (maintainability; conf 6)
```

## Reference files

- `references/host-detect.md`
- `references/persona-dispatch.md` — which personas fire and how
- `references/finding-schema.md` — JSON shape
- `references/severity.md` — autofix routing
- `references/severity-and-routing.md` — alias
- `references/outside-voice.md` — peer-review prompt (used by `--peer` and `--cross`)
- `$SKILL_DIR/scripts/ensemble-build-peer-prompt` — assembles the Outside Voice prompt for `--peer` and `--cross`
- `references/single-agent-fallback.md` — fallback when only one CLI is installed
- `references/recursion-guard.md`

## Failure protocol

| Failure | Behavior |
|---|---|
| One persona times out | Drop its findings; note in summary; continue |
| All personas fail | `verdict: error`; do not return findings; surface to user |
| Diff is too large for any persona | Split by file; run persona per file; merge findings |
| Mode is `report-only` but `safe_auto` would apply | Note "Would apply N safe_auto fixes (skipped — report-only mode)" in summary; don't apply |
| Re-verification fails after applying findings | Revert; surface to user; do not commit |
