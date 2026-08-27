# Playwright MCP helpers — usage patterns for `/en-qa`

Reference patterns for invoking Playwright MCP tools during browser QA. The MCP server provides `mcp__playwright_*` tools (or platform equivalents); skills consult this file for canonical usage.

## Setup check

Before invoking any browser tool, verify Playwright MCP is available. In Claude Code:

```text
ToolSearch with query "select:mcp__plugin_playwright_playwright__browser_navigate"
```

If the tool isn't loaded, browser QA is unavailable — fall back to system checks only.

## Canonical patterns

### Navigate and snapshot

```
browser_navigate({ url: "https://preview-url.example.com" })
browser_snapshot()
```

`browser_snapshot()` returns the accessibility tree — preferred over `take_screenshot` for asserting structure (it's deterministic; screenshots aren't).

### Click

Prefer ref-based interactions over selector-based:

```
browser_snapshot()  // get the ref
browser_click({ ref: "<ref from snapshot>", element: "Login button" })
```

Pass `element` as a human-readable label so the action is self-explanatory in logs.

### Fill a form

```
browser_fill_form({
  fields: [
    { ref: "<ref>", element: "Email", text: "user@example.com" },
    { ref: "<ref>", element: "Password", text: "<test-password>" }
  ]
})
browser_click({ ref: "<submit-ref>", element: "Submit" })
```

### Wait for state

```
browser_wait_for({ text: "Welcome back" })
```

`text` is the accessible text the page should contain after the action settles. Avoid hard `setTimeout` waits.

### Capture evidence

```
browser_take_screenshot({ path: ".test-output/qa-<flow-name>-<step>.png" })
```

For bugs: capture before-fix and after-fix screenshots. Include both in the QA report.

### Console + network for debugging

```
browser_console_messages()  // returns recent console output
browser_network_requests()  // returns recent network calls
```

Use when a bug is suspected and you need backend evidence (failed XHR, console error).

### Cleanup

```
browser_close()
```

Run at the end of the QA pass to release the browser context.

## Common pitfalls

- **Don't trust visual stability across viewports.** A flow that works at 1280x720 may fail at 375x667. Always exercise mobile viewport (`browser_resize({ width: 375, height: 667 })`) for any flow involving forms or navigation.

- **Re-snapshot after every navigation.** Refs are stale after a page change. Browser-state in skill memory is unreliable; query the page.

- **Throttle for slow-network checks.** Use `browser_run_code({ code: "<context-throttle script>" })` if the MCP exposes throttling, or simulate by adding `await new Promise(r => setTimeout(r, 2000))` inside form-submit handlers temporarily (revert before commit).

- **Don't overload one test with multiple flows.** One Playwright session per logical flow; fail fast.

## Auth handling

If the app requires auth:

1. Check `~/.ensemble/config.local.yaml` for a test account.
2. If present → log in once via `browser_fill_form` + `browser_click`; subsequent flows reuse the session.
3. If absent → surface and ask user: "Browser QA needs auth. Provide a test account in `.ensemble/config.local.yaml` or skip the auth-gated flows? (skip / provide / abort)"

Test accounts in config:

```yaml
qa:
  test_accounts:
    primary:
      email: qa-primary@example.com
      password: <password>  # WARN: gitignored — never commit real creds
```

The `<password>` field, by convention, references an env var: `password: $QA_PRIMARY_PASSWORD` so secrets stay out of files.

## When MCP isn't available

Hard fall-back: surface a one-line note in the QA report ("Playwright MCP unavailable; system checks only.") and continue with Phase 1 only.

The user can install the Playwright MCP server later and re-run `/en-qa` for full coverage.

## Token cost

Browser QA is the most expensive part of any Ensemble flow:

- One snapshot ≈ 5K–20K tokens depending on page size.
- A 6-step flow ≈ 30K–120K tokens.
- 5 flows × 8 edge cases each ≈ 1M+ tokens (rare; usually exercises far fewer).

Heuristics:

- Use snapshot at decision points only, not every action.
- Use `browser_wait_for` with `text` rather than re-snapshotting.
- Skip mobile viewport for non-form-heavy flows.

## Output evidence

Save screenshots under `.test-output/qa/` (gitignored by default). The QA report references them as relative paths. After the QA pass, the user can review the screenshots manually if anything looks off.
