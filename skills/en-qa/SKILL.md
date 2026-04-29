---
name: en-qa
description: "Test the work like a real user. Phase 1 system checks (lint + typecheck + test suite); Phase 2 browser end-to-end via Playwright MCP (golden-path flows + edge cases like empty states, error states, slow network, double-click, navigate-mid-action, keyboard-only, mobile viewport). For each bug found: reproduce, identify root cause, fix, add regression test, atomic commit, re-verify. Outputs a QA report with screenshots. Use whenever the user wants to verify a feature behaves correctly end-to-end before shipping. Trigger phrases: 'test this', 'qa', 'browser test', 'end-to-end', 'verify the feature works', 'click through it', 'make sure nothing broke'."
---

# `/en-qa`

System checks plus live browser end-to-end testing. Bug fixes commit atomically with regression tests.

## Process

1. **Detect host (light).** Source `references/host-detect.md` only for path conventions; no peer-review setup needed (cross-review is off for QA).
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, exit (peer subprocess shouldn't QA in CI).
3. **Phase 1 — system checks.** Run in this order; stop on first failure:
   - Project lint (from `AGENTS.md` `{{LINT_CMD}}`).
   - Typecheck if applicable.
   - Project test suite.
   On failure: report what failed, surface to user, exit. Don't proceed to browser QA on a broken build.
4. **Detect URL.** Browser QA needs a URL. Sources, in order:
   - `--url <url>` flag.
   - PR comment containing a Vercel/Cloudflare preview URL (regex match).
   - Local dev server detection (e.g., `localhost:3000` if a dev server is responsive).
   - User asks if none found.
5. **Verify Playwright MCP.** Per `references/playwright-helpers.md`. If unavailable → run Phase 1 only and surface the gap.
6. **Bootstrap test framework if absent.** If the project has no test suite at all, surface and offer to install Playwright (or the project's preferred framework). Bootstrap is its own commit.
7. **Phase 2 — browser QA.** Per `references/qa-flows.md`:
   - Walk each top-level user flow (from foundation §6 F-IDs).
   - For each, exercise the golden path + the edge cases (empty state, error state, slow network, double-click, navigate-mid-action, keyboard-only, mobile viewport).
   - Capture screenshots at decision points.
8. **Bug protocol** (for each bug found):
   - Reproduce — confirm consistently.
   - Identify root cause — read source; trace path.
   - Fix in source code.
   - Add regression test (must fail on unfixed code, pass on fix).
   - Atomic commit: `fix(qa): <one-line>`. Body cites the QA flow.
   - Re-verify — re-run failing flow + regression test.
9. **Output QA report** — system-check status, flows exercised, bugs found and fixed, regression tests added, screenshots, skipped flows with reasons.

## Flags

| Flag | Effect |
|---|---|
| `--url <url>` | Override URL detection |
| `--system-only` | Skip Phase 2 (browser QA) |
| `--flow <name>` | Run only the named flow |
| `--no-fix` | Find bugs, don't fix; output as a list for triage |
| `--mobile-only` / `--desktop-only` | Limit viewports |

## When Phase 2 is skipped

Surface a one-line note in the report: "Browser QA skipped — <reason>." Reasons:

- No URL provided and none detected.
- Playwright MCP unavailable.
- Branch is doc-only (`git diff --name-only` shows only `docs/`).
- `--system-only` flag.
- `peer_mode_override: off` and the user disabled all browser ops.

## Cross-review

**Off.** Bug fixes from QA are mechanical; over-reviewing them costs more than it surfaces. The user can run `/en-cross-review` ad-hoc on a QA branch if they want a peer pass before shipping.

## Auto-invoke `/en-learn`

After QA wraps, soft-prompt:

> "QA found and fixed N bugs. Capture as learnings? (yes / skip)"

User accepts → invoke `/en-learn capture` for each fixed bug. User declines → no-op. Bugs are the highest-signal source of learnings; capturing them is what makes the wiki valuable over time.

## Output format

```markdown
# QA report — FR07-auth-rotation

## System checks

- Lint: ✓
- Typecheck: ✓
- Test suite: ✓ (247 passing, 0 failing)

## Browser QA

URL: https://preview-fr07.vercel.app

### Golden-path flows

- ✓ Sign in (desktop, mobile)
- ✓ Refresh token rotation (golden)

### Edge cases

- ✗ **Bug:** Refresh token race when 2 tabs open (mobile, throttled 3G)
  - **Root cause:** singleFlight TTL too short under network jitter.
  - **Fix:** `src/auth/refresh.ts:34` — bumped TTL from 5s to 10s.
  - **Regression test:** `tests/auth/refresh.test.ts:142` — `expectsSingleRotateUnderNetworkJitter`.
  - **Commit:** `fix(qa): adjust singleFlight TTL for network jitter` (b7c2e1d)
- ✓ Empty form
- ✓ Slow network (throttle 3G)
- ⏭ Keyboard-only (skipped — flow has no keyboard-actionable elements)

## Summary

- 1 bug found and fixed.
- 1 regression test added.
- 4 screenshots captured under `.test-output/qa/`.
- Auto-invoking /en-learn (capture? y/n) →
```

## Reference files

- `references/qa-flows.md` — flow catalog and bug protocol
- `references/playwright-helpers.md` — MCP usage patterns
- `references/host-detect.md` — light usage

## Failure protocol

| Failure | Behavior |
|---|---|
| Lint fails | Surface; exit. Don't proceed to browser. |
| Test suite fails | Surface failing tests; exit. Don't proceed. |
| Playwright MCP unavailable | Phase 1 only; note in report. |
| URL unreachable | Surface; ask user for a different URL or `--system-only`. |
| Bug found but root cause unclear | Surface the symptom; capture screenshot; mark as "needs human" in the report; don't commit a guessed fix. |
| Regression test passes on unfixed code | The test isn't actually exercising the fix. Surface; iterate on the test until it fails on unfixed code. |
| `max_bugs_to_fix_per_run` exceeded (default 5) | Fix the first N; surface the rest as a list for follow-up. |
