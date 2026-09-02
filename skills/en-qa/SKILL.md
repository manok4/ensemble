---
name: en-qa
description: "Test the work like a real user. Phase 1: lint + typecheck + test suite. Phase 2: Playwright browser end-to-end (golden path + edge cases — empty/error states, slow network, double-click, navigate-mid-action, keyboard, mobile). Per bug: reproduce → root cause → fix → regression test → atomic commit → re-verify. Outputs a QA report with screenshots. Trigger phrases: 'test this', 'qa', 'browser test', 'end-to-end', 'verify the feature works', 'click through it'."
disable-model-invocation: true
---


# `/en-qa`

System checks plus live browser end-to-end testing. Bug fixes commit atomically with regression tests.

## Process

1. **Resolve context.** Establish once: the branch and its base, the changed files, and **whether a human is driving**. A caller (`/en-build`, `/en-loop`) drives this unattended; a person invoking it directly does not. That single fact changes what happens at every prompt below, so resolve it first and state it in the report.

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
5. **Select a browser driver, then keep it.** Per `references/browser-driver.md`. In order:
   1. **A host-native browser surface**, if the harness has one that can navigate, inspect rendered state, click and type, screenshot, and read console errors. Prefer it: it needs no install and is already permitted.
   2. **Playwright MCP**, when present.
   3. Neither → Phase 1 only, and say which drivers were looked for.

   **Never introduce a third stack.** Do not install Puppeteer, a standalone Playwright, or another automation surface to make a run possible; a project that has none is a finding, not a setup task.

   **One driver for the whole run.** After the first flow is exercised, do not switch: element references, screenshots, session and auth state do not carry across drivers, and a run that mixes them produces a report where half the evidence describes a session that no longer exists. Falling back is allowed only before the first flow runs.
6. **Bootstrap test framework if absent.** If the project has no test suite at all, surface and offer to install Playwright (or the project's preferred framework). Bootstrap is its own commit.
6a. **Browser-phase detector.** Before running Phase 2, classify the change via `references/diff-signal-detection.md`. Run Phase 2 only when `needs_browser` is `true` (the diff touches frontend/UI files) **OR** the user passed `--browser`. When `needs_browser` is `false` AND `--browser` was not passed: skip Phase 2 with the one-line note *"Browser QA auto-skipped — no frontend files changed; pass --browser to force."* and proceed to the report. **Fail closed:** if the diff can't be classified (no base ref, detached HEAD), treat as `needs_browser: true` and run Phase 2. `--browser` always forces Phase 2; `--system-only` always skips it (and wins over `--browser`).
7. **Phase 2 — browser QA of what was implemented.** Per `references/qa-flows.md`.

   **Scope first: map the change to flows.** Take the changed files and attribute each to the flows (foundation §6 F-IDs) it can reach, through routes, components, and the modules those import. **Exercise only those flows.** This is QA of a change, not a release regression sweep: walking twenty flows for a one-route edit spends most of the run re-proving things nobody touched, and buries the finding that matters in a wall of green.

   **When attribution is incomplete, say so — do not fall back to everything.** If a changed file cannot be attributed to any flow (a shared utility, a build-config change, no route map available), exercise the flows you *did* attribute, then list the unattributed files in the report under "impact undetermined". Expanding silently to the full catalogue trades a stated gap for an unstated cost, and the reader can no longer tell which flows were run because they were implicated and which were swept up. `--flow <name>` overrides attribution; `--all-flows` is the explicit way to ask for the sweep.

   For each in-scope flow, exercise the golden path + the edge cases (empty state, error state, slow network, double-click, navigate-mid-action, keyboard-only, mobile viewport), and capture screenshots at decision points.

   **A flow that cannot be driven automatically is Skipped, never faked.** OAuth handoffs, email or SMS confirmation, real payments, third-party APIs without a sandbox: when a human is driving, ask whether to do that step manually; when a caller is driving, record `Skip — needs external interaction: <what>` and continue.
8. **Bug protocol** (for each bug found):
   - Reproduce — confirm consistently.
   - Identify root cause — read source; trace path.
   - Fix in source code.
   - Add regression test (must fail on unfixed code, pass on fix).
   - Atomic commit: `fix(qa): <one-line>`. Body cites the QA flow.
   - Re-verify — re-run failing flow + regression test.
8a. **Done means every in-scope flow has an outcome.** The run ends one of two ways: a report in which **every flow selected at step 7 is marked Pass, Fail, or Skip with its reason**, or a preflight blocker that stopped QA before any flow could run, named alongside what would clear it. Ending in neither, or dropping a flow from the report because nothing could reach it, is the failure this bar exists to prevent — an absent flow reads as a flow that passed.

9. **Output QA report** — system-check status, flows exercised, bugs found and fixed, regression tests added, screenshots, skipped flows with reasons.

## Flags

| Flag | Effect |
|---|---|
| `--url <url>` | Override URL detection |
| `--system-only` | Skip Phase 2 (browser QA). Wins over `--browser`. |
| `--browser` | Force Phase 2 even when the detector finds no frontend files changed. |
| `--flow <name>` | Run only the named flow; overrides change attribution |
| `--all-flows` | Exercise the whole §6 catalogue, not just flows the change reaches. The explicit way to ask for a regression sweep. |
| `--no-fix` | Find bugs, don't fix; output as a list for triage |
| `--mobile-only` / `--desktop-only` | Limit viewports |

## When Phase 2 is skipped

Surface a one-line note in the report: "Browser QA skipped — <reason>." Reasons:

- No URL provided and none detected.
- No usable browser driver (host-native or Playwright MCP).
- Branch is doc-only (`git diff --name-only` shows only `docs/`).
- **No frontend files changed** (detector `needs_browser: false`, no `--browser`) — per `references/diff-signal-detection.md`.
- `--system-only` flag.
- `peer_mode_override: off` and the user disabled all browser ops.

## Cross-review

**Off.** Bug fixes from QA are mechanical; over-reviewing them costs more than it surfaces. The user can run `/en-review --peer` ad-hoc on a QA branch if they want a peer pass before shipping.

## Agent autonomy contract (mirrors `/en-build`)

`/en-qa` is autonomous by design. After fixing a bug (or confirming a flow passed), advance to the next flow immediately. **Do not pause** for confirmation, "let me checkpoint before the bigger test surface," or any reason not in the enumerated cases below.

### Scope of the contract

The contract governs **already-runnable QA flows** — the period after setup has cleared, during which Phase 1 system checks are executing or Phase 2 Playwright flows are running and the bug-fix loop is iterating. Within this window, pauses are restricted to the five cases below.

**Pre-flow setup is NOT governed by this contract.** Specifically, the following en-qa prompts and skip decisions have their own documented handlers and are NOT inter-flow pauses:

- **URL discovery prompt** — when no app URL is found, ask the user. Pre-flow; the QA flow can't start without a URL.
- **Phase 2 skip on doc-only branches / `--system-only` / browser-disabled config** — Phase 2 is correctly skipped; the contract doesn't force it to run.
- **Test-framework bootstrap offer** when none is detected — pre-flow setup question; out of contract scope.

**When a caller is driving, none of those three may block.** `/en-build` and `/en-loop` both hand off to `/en-qa`, and `/en-loop` runs unattended overnight. Each pre-flow question becomes a **Skip with its reason** instead: no URL found, no driver available, no framework to bootstrap. The run continues and the report says what could not be done. A question asked with nobody watching does not fail — it waits, which is worse, because the caller cannot tell a stalled run from a slow one.

Why scope this way: the autonomy bug class is the same as en-build's — agent-initiated checkpoints during the QA loop ("the next flow has more assertions; let me checkpoint"). The contract closes that, without invalidating legitimate pre-flow decisions about whether QA can sensibly run at all.

### Legitimate pause cases within the contract window (exhaustive within scope, no others permitted)

1. **System check fails** at Phase 1 (e.g. test suite red, typecheck broken). The QA flow can't sensibly proceed; surface and stop.
2. **Playwright MCP unavailable mid-flow.** A flow that started but lost MCP connectivity; surface gap and skip remaining flows. *(Distinct from the pre-flow Playwright availability check at setup — that's out of scope per Scope above.)*
3. **Bug found that requires user judgment** to fix (e.g. ambiguous expected behavior; missing requirement). Surface the bug and ask the user.
4. **Bug fix breaks Phase 1 checks** (regression). Stop; surface state.
5. **User-initiated abort.**

### Anti-patterns (explicitly forbidden — same as `/en-build`)

- "Phase 1 passed; should I proceed to Phase 2?" No — proceed automatically.
- "Test fixture X is more complex; let me verify before running it." No — run it.
- "All bugs fixed; should I run the full suite once more?" No — the autoflow already does this.
- "Big surface area in the next flow; checkpoint here." No — advance.

### Right response to LLM uncertainty: advance, not ask

If uncertain, continue. The pause cases above and Phase 1's system checks are the safety net. Agent-initiated checkpoints add no protection on top — they just add friction.

## Learning capture

`/en-qa` does **not** prompt for learnings. Learning capture is a single, structured checkpoint at **`/en-build` completion** (after the branch-level review — see foundation D26). If a QA pass surfaces something worth filing, capture it with an explicit `/en-learn capture`; otherwise the en-build checkpoint is the one place the decision is made.

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
```

## Reference files

- `references/qa-flows.md` — flow catalog and bug protocol
- `references/browser-driver.md` — driver selection, and per-driver usage patterns

## Failure protocol

| Failure | Behavior |
|---|---|
| Lint fails | Surface; exit. Don't proceed to browser. |
| Test suite fails | Surface failing tests; exit. Don't proceed. |
| No usable browser driver | Phase 1 only; name the drivers looked for. Never install one to proceed. |
| URL unreachable | Surface; ask user for a different URL or `--system-only`. |
| Bug found but root cause unclear | Surface the symptom; capture screenshot; mark as "needs human" in the report; don't commit a guessed fix. |
| Regression test passes on unfixed code | The test isn't actually exercising the fix. Surface; iterate on the test until it fails on unfixed code. |
| `max_bugs_to_fix_per_run` exceeded (default 5) | Fix the first N; surface the rest as a list for follow-up. |
