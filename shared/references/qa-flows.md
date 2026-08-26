# QA flows — what `/en-qa` exercises

The catalog of flows `en-qa` should walk through, in order, when testing like a real user.

## Phase 1 — System checks (always run first)

1. **Lint.** Project's linter command (from `AGENTS.md`).
2. **Typecheck.** Project's typecheck command if applicable.
3. **Test suite.** Full project test suite.

If anything fails here, **stop and report**. Don't proceed to browser QA on a broken build.

## Phase 2 — Browser QA (Playwright MCP)

Only runs if a URL is provided (or auto-detected from the branch — e.g., a Vercel preview URL in a PR comment).

### Golden-path flows

For each top-level user flow listed in `docs/foundation.md` §6 (User Experience, F-IDs):

1. Navigate to the entry point.
2. Execute the flow as a user would.
3. Verify the expected end state.
4. Capture screenshot at each meaningful step.

### Edge-case flows

For each golden-path flow, exercise these edge cases:

| Edge case | What to check |
|---|---|
| **Empty state** | Form with no input; list with no items; cart with no products |
| **Maximum input** | Field with the maximum allowed length; pagination at the last page |
| **Error state** | Trigger a 4xx (bad form data); trigger a 5xx (offline; bad backend) |
| **Slow network** | Throttle to slow 3G; verify loading states; verify no double-submit on lag |
| **Double-click** | Click a button twice rapidly; verify idempotency or single-firing |
| **Navigate-mid-action** | Submit a form and immediately navigate away; verify either cancel or completion |
| **Keyboard-only** | Tab through the flow; verify focus order; verify all actions reachable |
| **Mobile viewport** | Resize to mobile (375x667); verify the flow still works |

For each bug found, follow the **Bug protocol** below.

## Bug protocol

For each bug:

1. **Reproduce.** Confirm the bug fires consistently. If flaky, capture the conditions that make it manifest.
2. **Identify root cause.** Read the source; trace the path; find the actual issue (not just symptoms).
3. **Fix in source code.** Surgical edit; preserve unrelated behavior.
4. **Add regression test.** A test that fails on the unfixed code and passes on the fix. Test belongs in the project's test suite (not in `docs/`).
5. **Atomic commit.** `fix(qa): <one-line description>` with body citing the QA flow that surfaced the bug.
6. **Re-verify.** Re-run the failing flow and the regression test. Both should now pass.

## Output

A QA report (markdown) with:

- System-check status (lint / typecheck / tests pass or fail).
- Browser flows exercised.
- Per-flow result: ✓ pass, ✗ fail (with screenshot path), or ⏭ skipped.
- Bugs found and fixed (commit SHA + one-line description each).
- Regression tests added (file path + test name).
- Any flows that couldn't be tested (e.g., feature requires real auth and Playwright session isn't authenticated).

## Bootstrapping a test suite

If the project has no test suite at all when `en-qa` runs:

1. Surface: "No test suite detected. Set up <framework> for browser tests?"
2. If user accepts → install the project's preferred framework (Playwright direct, or via `playwright/test`); add minimal config; add one example test that exercises the golden path.
3. The bootstrap is its own unit (separate commit) before any bug-fix commits.

## When to skip Phase 2

- No URL provided and no preview URL detected.
- Playwright MCP is not available in the host.
- Branch is doc-only (`git diff --name-only` shows only `docs/`).
- User passed `--system-only` flag.

In all these cases, run Phase 1 only and surface a note: "Browser QA skipped because <reason>."

## Cross-review

`en-qa` is **off** for cross-review (per foundation §5.2.6). Bug fixes are mechanical; over-reviewing them costs more than it surfaces. The user can run `/en-cross-review` ad-hoc on a QA branch if they want a peer pass.

## Time budgets

Default soft cap on browser QA: 15 minutes per flow. If a flow takes longer, surface and ask whether to continue or skip.

Configurable via `~/.ensemble/config.json`:

```json
{
  "qa": {
    "browser_flow_timeout_minutes": 15,
    "max_bugs_to_fix_per_run": 5
  }
}
```

`max_bugs_to_fix_per_run` — if more bugs are found than this cap, fix the first N and surface the rest as a list for follow-up. Prevents a single QA run from cascading into a multi-hour bug-fix marathon.
