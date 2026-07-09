---
name: en-review
description: "Multi-persona code review of the current branch. Always-on personas: correctness, testing, maintainability, standards. Conditional (fire when diff matches): security, performance, migrations. Confidence-gated — sub-threshold findings file as TD entries instead of cluttering output. Three modes: interactive (default), headless (skill-to-skill), report-only (mandatory in CI like en-sweep). Trigger phrases: 'review my changes', 'review this branch', 'code review', 'check this PR'."
---

> **Helper resolution.** All `references/X` and `bin/Y` paths in this skill resolve relative to `$ENSEMBLE_ROOT` — the install root (skill at `$ENSEMBLE_ROOT/skills/<name>/`, shared helpers at `$ENSEMBLE_ROOT/{references,bin}/`). Compute once at start: `$ENSEMBLE_ROOT` env var if set; otherwise `$(realpath "$(dirname <this-SKILL.md>)/../..")`. Fail loudly if `$ENSEMBLE_ROOT/references/host-detect.md` does not resolve — that indicates a partial install (run `/en-setup` to repair).


# `/en-review`

Multi-persona, confidence-gated code review. Optional cross-agent peer review on top.

## Process

1. **Detect host.** Source `$ENSEMBLE_ROOT/references/host-detect.md`.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, do not invoke `--peer` even if requested.
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
8. **Parallel dispatch.** Single message, multiple `Agent` tool calls. Wait for all to return.
9. **Outside Voice peer (`--peer` adds it on top; `--peer-only` makes it the sole reviewer).** Dispatch a cross-agent peer pass over the diff (build-by-orchestration: peer is the other agent per D23):
   - Build the prompt: `$ENSEMBLE_ROOT/bin/ensemble-build-peer-prompt --artifact-type code --artifact-file <diff> --project-context "<one-line>" --goal "<one-line>" --peer-mode "$PEER_MODE"`. Set `ENSEMBLE_PEER_REVIEW=true`; pipe into `$PEER_CMD` (wrapped in `$ENSEMBLE_TIMEOUT_BIN`). Parse findings per `$ENSEMBLE_ROOT/references/finding-schema.md`.
   - **`--peer`** (on top of personas): add the peer's findings tagged `persona: "peer"` to the persona envelope.
   - **`--peer-only`** (sole reviewer): the peer's findings ARE the envelope. Record the reviewer in the result: `cross-agent` (peer ran), `single-agent-fallback` (only one CLI → fresh-subprocess per `$ENSEMBLE_ROOT/references/single-agent-fallback.md`), or — only when `PEER_AVAILABLE=false` (no other CLI at all) — fall back to the full host persona roster (steps 7–8) and record `reviewer: en-review-host-fallback` so the weaker, same-agent evidence is visible.
   - **Recursion guard:** if `ENSEMBLE_PEER_REVIEW=true` at entry, do not dispatch a peer (would recurse). Under `--peer-only` that means falling back to the host roster (or, in a subprocess that can't review itself, returning the empty envelope with `reviewer: recursion-guard`).
10. **Synthesize.** Per `$ENSEMBLE_ROOT/references/persona-dispatch.md`:
    - Validate each response (drop malformed).
    - Collect findings; preserve persona attribution.
    - Dedup by location + title-similarity ≥ 0.7 (merge personas; boost confidence).
    - Conflict detection: same location, incompatible reasons → mark `conflict: true`.
    - Severity reorder: P0 → P3, then confidence, then persona priority.
11. **Confidence gate.** Read `review.confidence_threshold` from `~/.ensemble/config.json` (default `7`). Findings with `confidence < threshold` are **filtered out** of the surfaced output and **filed as TD entries** in `docs/plans/tech-debt-tracker.md` with the marker `Filed by /en-review (confidence <N>)`. This keeps a paper trail without cluttering review noise. Per `$ENSEMBLE_ROOT/references/review-confidence-gating.md`. Skipped in `report-only` mode (no mutations allowed; sub-threshold findings are returned in the JSON envelope under `sub_threshold_findings: []` instead).
12. **Apply / surface.**
    - In `interactive` mode: auto-apply `safe_auto`; surface `gated_auto`/`manual`/`advisory` to user. After user picks, apply chosen fixes; re-verify.
    - In `headless` mode: auto-apply `safe_auto` silently; return JSON envelope with all findings.
    - In `report-only` mode: never apply anything; return JSON only.
13. **Output report.** Markdown summary (for human consumption) plus JSON envelope (for programmatic callers). Both include a `sub_threshold_filed_count` line indicating how many findings were filed as TD entries (or surfaced separately in `report-only`).

## Flags

| Flag | Effect |
|---|---|
| `--mode interactive\|headless\|report-only` | Override default mode |
| `--peer` | Add cross-agent peer pass on top of the host personas |
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
