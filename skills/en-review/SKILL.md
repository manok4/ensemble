---
name: en-review
description: "Multi-persona code review of the current branch, with the cross-agent peer ON BY DEFAULT (skip via --no-peer). Always-on personas: correctness, testing, maintainability, standards. Conditional (fire when diff matches): security, performance, migrations. Host and peer findings reconcile into four buckets (corroborated / peer-only / host-only / conflicting). Confidence-gated — sub-threshold findings file as TD entries instead of cluttering output. Three modes: interactive (default), headless (skill-to-skill), report-only (mandatory in CI like en-sweep; never runs a peer). Trigger phrases: 'review my changes', 'review this branch', 'code review', 'check this PR'."
---

> **Helper resolution.** All `references/X` and `bin/Y` paths in this skill resolve relative to `$ENSEMBLE_ROOT` — the install root (skill at `$ENSEMBLE_ROOT/skills/<name>/`, shared helpers at `$ENSEMBLE_ROOT/{references,bin}/`). Compute once at start: `$ENSEMBLE_ROOT` env var if set; otherwise `$(realpath "$(dirname <this-SKILL.md>)/../..")`. Fail loudly if `$ENSEMBLE_ROOT/references/host-detect.md` does not resolve — that indicates a partial install (run `/en-setup` to repair).


# `/en-review`

Multi-persona, confidence-gated code review **with the cross-agent peer on by default** (EN11). Host personas and the blind peer run concurrently; their findings reconcile into four explicit buckets.

## Process

1. **Detect host.** Source `$ENSEMBLE_ROOT/references/host-detect.md`.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, no peer is dispatched (it would recurse) regardless of the default or an explicit `--peer`. Resolves `peer_decision.reason: recursion-guard`.

2a. **Resolve the peer decision** (EN11). Produce ONE `peer_decision` object per the schema in `$ENSEMBLE_ROOT/references/peer-model-policy.md` section (e), and carry it into the report rather than recomputing it later.

   | Condition | `peer` | `reason` |
   |---|---|---|
   | `PEER_MODE=cross-agent` AND mode is `interactive`/`headless` | `on` | `default-on` (or `explicit-flag` if `--peer` was passed) |
   | `--no-peer` passed | `off` | `no-peer-flag` |
   | `PEER_MODE=single-agent-fallback` (unless `--peer`) | `off` | `single-agent-fallback` |
   | mode is `report-only` | `off` | `report-only-mode` |
   | `ENSEMBLE_PEER_REVIEW=true` | `off` | `recursion-guard` |
   | `PEER_AVAILABLE=false` | `off` | `peer-unavailable` |
   | Diff below `skip_peer_below_lines` | `off` | `auto-skip:diff-below-threshold` |
   | Lightweight depth AND `skip_peer_on_lightweight` | `off` | `auto-skip:lightweight-depth` |

   Two carve-outs are deliberate, not oversights. **`report-only` never runs a peer**: `/en-sweep` invokes `/en-review` in that mode inside CI, and D38 deliberately keeps API secrets and repo-write off CI, so defaulting a peer on there would silently require peer CLI credentials. **`single-agent-fallback` defaults off** because en-review's personas are already fresh-context instances of the host stack, so a same-model subprocess adds cost without an independent perspective; `--peer` still opts in. (The calculus differs in `/en-build`, where the alternative is the host reviewing its own inline work.)

2b. **Resolve effort and model alias — this skill is the SOLE resolver** (`peer-model-policy.md` (b)). Walk the precedence chain and produce one final tier plus one final alias:

   - **Effort:** `--effort <low|medium|high>` flag → `$ENSEMBLE_ROOT/bin/ensemble-config-get review_peer_effort_override --allowed low,medium,high` → the ladder (`high` when `security-reviewer`/`migrations-reviewer` fired, an architectural trigger is present, or the unit is `risk: destructive`/`gated: true`; `low` when `is_small_and_safe`; else `medium`).
   - **Model alias:** `$ENSEMBLE_ROOT/bin/ensemble-config-get review_peer_model_alias` → the default alias. There is no `--model` run flag by design.

   The repo-then-global cascade inside each lookup belongs to `$ENSEMBLE_ROOT/bin/ensemble-config-get`, and translating the resolved tier into CLI syntax belongs to `$ENSEMBLE_ROOT/bin/ensemble-peer-flags`. Neither re-derives policy, so precedence exists in exactly one place.
3. **Determine mode** (per `$ENSEMBLE_ROOT/references/persona-dispatch.md` and the §5.2.5 contract):
   - **`interactive`** — direct user invocation. Auto-applies `safe_auto` fixes; surfaces `gated_auto` / `manual` to user. May write to working tree.
   - **`headless`** — invoked by another skill (`en-build` per-unit, `en-cross-review`). Auto-applies `safe_auto` silently; returns structured JSON. May write to working tree.
   - **`report-only`** — invoked from CI (`en-sweep`). **Strictly read-only.** No edits, no commits. Returns findings JSON only.

   The mode is selected by the caller (or the skill picks based on context). Mandatory rules:
   - `en-build` → `headless`.
   - `en-sweep` → `report-only` (never configurable).
   - User direct → `interactive`.
   - `en-cross-review` → `headless`.
4. **Determine diff base.**
   - PR target if running on a PR branch.
   - Default branch (`main` per config) otherwise.
   - User can override with `--base <ref>`.
5. **Read context.**
   - `git diff <base>...HEAD` — the full diff under review.
   - Plan(s) referenced by the branch (per branch name `<plan_id>-<slug>` or commit messages citing the plan ID, e.g. `EN03`).
   - `AGENTS.md`, `CLAUDE.md`, project conventions.
6. **Pre-flight lint.** Run `$ENSEMBLE_ROOT/bin/ensemble-lint --scope docs/` and `$ENSEMBLE_ROOT/bin/ensemble-lint` on changed `docs/` paths. Surface lint failures as P1 findings before persona dispatch.
7. **Conditional persona detection.** Per `$ENSEMBLE_ROOT/references/persona-dispatch.md`:

   **Peer-only short-circuit (`--peer-only`).** If `--peer-only` is set, **skip persona detection and dispatch entirely (steps 7, 7a, 8)** — the sole reviewer is the cross-agent Outside Voice peer (step 9). This is the mode `/en-build`'s post-build phase uses: the host implemented the code, so review must come from the *other* agent, with no host-side personas. `--peer-only` and `--lite` are mutually exclusive (lite is a host-persona roster; peer-only has no host personas) — if both are passed, `--peer-only` wins. Proceed directly to step 9.

   - Always-on (4): `correctness-reviewer`, `testing-reviewer`, `maintainability-reviewer`, `standards-reviewer`.
   - Conditional (3) — fire when diff content matches: `security-reviewer`, `performance-reviewer`, `migrations-reviewer`.
   - Plus `learnings-research` to query `docs/learnings/` for relevant prior bugs/patterns/decisions.

   **7a. Lite roster (`--lite`).** When `--lite` is passed, classify the diff via `$ENSEMBLE_ROOT/references/diff-signal-detection.md`. If `is_small_and_safe` is `true` (1–39 executable lines, zero uncounted files, no risk signals, **and** no conditional persona was triggered above), collapse the roster to **`correctness-reviewer` + `standards-reviewer` + a `fast-pass` lens** — skip `testing`, `maintainability`, `learnings`, and all conditionals. **Fail closed:** if `is_small_and_safe` is `false` for any reason (unknown line count, any uncounted non-code file, any risk signal, or any conditional persona fired), run the **full roster regardless of `--lite`** — the gate wins, the flag is advisory. `fast-pass` findings are confidence-capped (anchor ≤ 50) so they surface on their own only at P0; otherwise they reach the actionable tier only by deduping onto an independent persona finding (per `$ENSEMBLE_ROOT/references/persona-dispatch.md`).

   **Mandatory `lite_gate:` outcome line (EN08).** EVERY run emits exactly ONE `lite_gate:` line in the markdown summary — so a missing line is always distinguishable from a not-requested lite, and the gate's decision is **never a silent override**:

   - `lite_gate: applied` — `--lite` requested, roster collapsed.
   - `lite_gate: overridden (<reasons>)` — `--lite` requested but the fail-closed gate won. `<reasons>` uses the **canonical override-reason identifiers from `$ENSEMBLE_ROOT/references/diff-signal-detection.md`** (`unknown-line-count`, `exec-lines-out-of-range`, `uncounted-files`, `risk-signal`, `conditional-persona:<names>`), deduplicated, in that fixed canonical order, comma+space separated, with exactly one space before the paren. Persona names in `conditional-persona:` are alphabetically sorted and `+`-joined. Example: `lite_gate: overridden (risk-signal, conditional-persona:performance+security)`.
   - `lite_gate: not-requested` — the run had no `--lite` flag.

   The JSON envelope carries the structured form (see envelope shape): `"lite_gate": {"outcome": "applied" | "overridden" | "not-requested", "reasons": []}` with `reasons` in the same canonical order (empty for `applied` / `not-requested`); the markdown line is DERIVED from that object, never composed independently.
8. **Parallel dispatch — personas AND the peer in ONE batch.** Single message, multiple `Agent` tool calls, **plus the peer subprocess from step 9 launched in the same batch**. Because the peer is **blind** to persona findings (see step 9), nothing orders it after the persona roster, so serializing it would add its latency to every review for no benefit (`peer_timeout_seconds` defaults to 600). Wait for all to return.
9. **Outside Voice peer (on by default per step 2a; `--peer-only` makes it the sole reviewer).** Dispatch a cross-agent peer pass over the diff (peer is the other agent per D23):
   - **Blind-peer invariant.** The peer receives the diff, the project context, and the goal. It does **NOT** receive the host persona findings. This is load-bearing, not an omission: anchoring the peer on host findings turns independent discovery into confirmation, and overlap then stops being evidence of anything. It is also what makes the concurrent dispatch in step 8 valid. Any change that feeds persona findings to the peer must also re-serialize step 8 and invalidate the corroboration weighting in step 10.
   - Build the prompt: `$ENSEMBLE_ROOT/bin/ensemble-build-peer-prompt --artifact-type code --artifact-file <diff> --project-context "<one-line>" --goal "<one-line>" --peer-mode "$PEER_MODE"`.
   - Translate the tier resolved in step 2b: `eval "$($ENSEMBLE_ROOT/bin/ensemble-peer-flags --effort <tier> --peer-cmd "$PEER_CMD" --model-alias <alias>)"` → `$PEER_MODEL`, `$PEER_EFFORT`.
   - **Invoke via `$ENSEMBLE_ROOT/bin/ensemble-peer-invoke`** with `ENSEMBLE_PEER_REVIEW=true`, passing `$PEER_CMD`, `$PEER_FORMAT`, `$PEER_TURNS`, `$PEER_MODEL`, `$PEER_EFFORT`, and the prompt file. **Do not restate the retry algorithm here** — the helper owns invocation, classification, the single bounded retry that drops only the rejected fragment, and the fallback, so the behavior is executable and testable rather than prose (EN11-PR-006). It returns the updated `peer_decision`; merge its `peer`/`reason` into step 2a's object. Parse the peer's findings per `$ENSEMBLE_ROOT/references/finding-schema.md`, tagged `source: "peer"`.
   - **Default (personas + peer):** the peer's findings join the persona findings and both sets reconcile in step 10.
   - **`--peer-only`** (sole reviewer): the peer's findings ARE the envelope; no reconciliation is needed. Record the reviewer: `cross-agent` (peer ran), `single-agent-fallback` (only one CLI → fresh-subprocess per `$ENSEMBLE_ROOT/references/single-agent-fallback.md`), or — only when `PEER_AVAILABLE=false` — fall back to the full host persona roster (steps 7–8) and record `reviewer: en-review-host-fallback` so the weaker, same-agent evidence is visible.
   - **Peer off** (any `peer: "off"` reason from step 2a): skip this step; the persona findings are the envelope. The reason is still reported.

9a. **Mandatory `peer_decision:` outcome line.** EVERY run emits exactly ONE, so a skip or a degradation can never read as a normal peer run — the same fail-closed discipline as `lite_gate:` (D42). Format: `peer_decision: <peer> (<reason>, effort=<tier>)`, e.g. `peer_decision: on (default-on, effort=medium)` / `peer_decision: off (report-only-mode, effort=medium)` / `peer_decision: degraded (dropped-effort-fragment, effort=high)`. `<reason>` MUST be a member of the closed enum in `$ENSEMBLE_ROOT/references/peer-model-policy.md` (e). The JSON envelope carries the structured `peer_decision` object; the markdown line is DERIVED from it, never composed independently.
10. **Synthesize.** Per `$ENSEMBLE_ROOT/references/persona-dispatch.md`:
    - Validate each response (drop malformed).
    - Collect findings; preserve persona attribution.
    - Dedup by location + title-similarity ≥ 0.7 (merge personas; boost confidence).
    - Conflict detection: same location, incompatible reasons → mark `conflict: true`.
    - Severity reorder: P0 → P3, then confidence, then persona priority.
11. **Confidence gate.** Read `review.confidence_threshold` from `~/.ensemble/config.json` (default `7`). Findings with `confidence < threshold` are **filtered out** of the surfaced output and **filed as TD entries** in `docs/plans/tech-debt-tracker.md` with the marker `Filed by /en-review (confidence <N>)`. This keeps a paper trail without cluttering review noise. Per `$ENSEMBLE_ROOT/references/review-confidence-gating.md`. Skipped in `report-only` mode (no mutations allowed; sub-threshold findings are returned in the JSON envelope under `sub_threshold_findings: []` instead).
12. **Apply / surface — two-phase mutation protocol (EN08).** The applied set is a *boundary fixed before editing*, not a post-hoc assertion:

    **Phase 1 — authorize, then baseline + freeze (before ANY edit).** Authorization comes FIRST, so the frozen set never changes after mutation begins:
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
| `--no-peer` | Skip the cross-agent peer entirely; host personas only. Resolves `peer_decision: off (no-peer-flag)`. (Same spelling as `/en-plan`'s flag.) |
| `--effort low\|medium\|high` | Pin the peer's reasoning-effort tier for this run, the highest-precedence layer in `$ENSEMBLE_ROOT/references/peer-model-policy.md` (b). Omit to let repo config, then user config, then the ladder decide. |
| `--peer` | **Back-compat no-op when the peer is already on by default** (EN11). Still meaningful where the default is off: it opts a `single-agent-fallback` run into a fresh same-model subprocess. Resolves `reason: explicit-flag`. |
| `--peer-only` | Cross-agent peer is the **sole** reviewer; skip host personas entirely (implementer ≠ reviewer). Used by `/en-build`'s post-build phase. Falls back to host roster only when no peer CLI exists. Mutually exclusive with `--lite`. |
| `--base <ref>` | Override diff base |
| `--no-lint` | Skip pre-flight lint |
| `--scope <path>` | Limit review to a path (default: full diff) |
| `--lite` | Fast path for tiny, low-risk diffs: collapse to `correctness` + `standards` (+ `fast-pass`) when `$ENSEMBLE_ROOT/references/diff-signal-detection.md` classifies the diff `is_small_and_safe`. **Fail-closed** — any uncounted file, unknown line count, risk signal, or triggered conditional persona forces the full roster regardless of the flag. |

## Mutation rules per mode

| Mode | Auto-apply `safe_auto`? | Surface `gated_auto`/`manual`? | Apply user-selected fixes? | Commit? |
|---|---|---|---|---|
| `interactive` | Yes | Yes (asks user) | Yes | No (user runs `/en-ship`) |
| `headless` | Yes (silent) | No (returns JSON) | N/A | No |
| `report-only` | **No** | No | N/A | No |

`report-only` is the **mandatory** mode when `en-sweep` invokes `en-review` in CI — see `$ENSEMBLE_ROOT/references/sweep-checks.md`.

**Auditable boundary (EN08).** Every application is recorded in `applied_fixes[]` (each entry `{finding_id, tier, files[]}`, `files[]` sorted and deduplicated) and echoed by the mandatory `review_fixes:` outcome line (see step 12). Tier definitions live in `$ENSEMBLE_ROOT/references/severity.md` — referenced, not duplicated.

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

- `$ENSEMBLE_ROOT/references/host-detect.md`
- `$ENSEMBLE_ROOT/references/persona-dispatch.md` — which personas fire and how
- `$ENSEMBLE_ROOT/references/finding-schema.md` — JSON shape
- `$ENSEMBLE_ROOT/references/severity.md` — autofix routing
- `$ENSEMBLE_ROOT/references/severity-and-routing.md` — alias
- `$ENSEMBLE_ROOT/references/outside-voice.md` — peer-review prompt (when `--peer` / `--peer-only`)
- `$ENSEMBLE_ROOT/bin/ensemble-build-peer-prompt` — assembles the Outside Voice prompt for `--peer` / `--peer-only`
- `$ENSEMBLE_ROOT/references/single-agent-fallback.md` — fallback when only one CLI is installed
- `$ENSEMBLE_ROOT/references/recursion-guard.md`

## Failure protocol

| Failure | Behavior |
|---|---|
| One persona times out | Drop its findings; note in summary; continue |
| All personas fail | `verdict: error`; do not return findings; surface to user |
| Diff is too large for any persona | Split by file; run persona per file; merge findings |
| Mode is `report-only` but `safe_auto` would apply | Note "Would apply N safe_auto fixes (skipped — report-only mode)" in summary; don't apply |
| Re-verification fails after applying findings | Revert; surface to user; do not commit |
