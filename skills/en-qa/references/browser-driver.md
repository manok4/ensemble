# Browser driver

Which browser surface a QA run drives, and how to use each one.

## Selecting

1. **A host-native browser surface** the harness already owns — one that can
   navigate, inspect rendered and interactive state, click and type, screenshot,
   and read console errors. Prefer it: nothing to install, already permitted.
2. **Playwright MCP**, when present. Its patterns are below.
3. **Neither** — Phase 1 only. Name the drivers that were looked for, so the
   report distinguishes "no browser here" from "browser QA was skipped".

**Never introduce a third stack.** Do not install Puppeteer, a standalone
Playwright, or any other automation surface to make a run possible. A project
with no usable driver is reporting a fact about itself; installing one turns a
QA pass into a setup task nobody asked for. A Playwright API exposed *inside* a
host-native browser is still host-native — that is not the standalone stack.

**One driver per run.** Element references, screenshots, cookies and auth state
do not survive a switch. A run that changes driver mid-way produces a report
whose earlier evidence describes a session that no longer exists. Falling back
is allowed only before the first flow is exercised; after that, a driver failure
ends Phase 2 and is reported.

## Which host-native surface

Use the browser of the harness the run is in: **T3 Code's preview tools** in T3
Code (`preview_open`, `preview_navigate`, `preview_snapshot`, `preview_click`,
`preview_type`, `preview_wait_for`, `preview_evaluate`, under the host's MCP
prefix), the **browser pane** in the Claude desktop app, and Playwright MCP only
when neither is there. On one machine, en-qa runs used all three in one month
(about 400, 250 and 250 actions), with 20 to 28 failed actions on each (D135).
Most of those failures came from three habits, and the rules below are their
inverse; they apply to every driver, Playwright included.

**One dependent action per message.** Snapshot, act on a ref from that snapshot,
then snapshot again to see what happened. Sending a click, a type and a wait in
one parallel batch acts on refs the first action already invalidated: on the
other machine 33 of 36 failed preview actions were dependent steps batched
together. Batch only reads that do not depend on each other, such as console
messages beside a screenshot.

**Make the dev server reachable before opening the browser.** Start it bound to
an address the surface can reach (most dev servers take `--host 127.0.0.1`), then
confirm with one bounded wait, `timeout 60 sh -c 'until curl -sf <url> >/dev/null;
do sleep 1; done'`, never a series of separate `sleep` calls. A preview that
cannot reach `localhost` fails every action that follows, and each failure looks
like a page bug.

**Retry a failed action once, after a fresh snapshot.** A bare "failed on client"
or a timeout usually means a stale ref or a page still settling. If the same
action fails again, the driver is not working: record it, end Phase 2 under the
one-driver rule above, and say which action failed.

## Recording a flow

SKILL.md step 7 records each in-scope flow's golden path with the run's own
driver, then hands the file to `ensemble-qa-evidence video`. Start the recorder
at the flow's entry point and stop it at the verified end state, or at the
failing step.

- **T3 Code:** `preview_recording_start` with the flow's tab, then
  `preview_recording_stop` on the same tab, which returns the recording's local
  path (at most 50 MiB). That path is the `--src`.
- **Playwright MCP:** its run-code tool, `browser_run_code_unsafe` or
  `browser_run_code`, whichever the host lists. Start with
  `async page => { await page.screencast.start({ path: '<abs run-dir>/<id>.raw.webm' }) }`
  and stop with `async page => { await page.screencast.stop() }`; the `path`
  given at start is the `--src`. An error from either call means
  `unavailable: playwright has no screencast`.
- **Any other host-native surface** records only if it lists a recording tool;
  otherwise the flow's `video` is `unavailable: <driver> has no recorder`.

**Never install a recorder**, for the same reason the run never installs a
driver. A recording that fails never changes the flow's outcome; screenshots
remain the evidence.

## Playwright MCP patterns

Only when selection landed on Playwright MCP. Its tools appear under the host's
MCP prefix (`browser_navigate`, `browser_snapshot`, … after `mcp__<server>__`,
where `<server>` is whatever the host registered). On Claude Code they are
deferred: load the navigate tool with `ToolSearch` (`select:` its full name as
the host lists it) before the first call. If no host lists one, this driver is
absent and selection moves on; that is not a reason to install one.

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
browser_take_screenshot({ path: ".test-output/qa/<run-id>/<flow-id>-<step>.png" })
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

1. Check the repo-local `.ensemble/config.local.yaml` for a test account.
2. If present → log in once via `browser_fill_form` + `browser_click`; subsequent flows reuse the session.
3. If absent → a person is asked: "Browser QA needs auth. Provide a test account in `.ensemble/config.local.yaml` or skip the auth-gated flows? (skip / provide / abort)". A caller gets `Skip — needs auth` on the gated flows.

Test accounts in config:

```yaml
qa:
  test_accounts:
    primary:
      email: qa-primary@example.com
      password: <password>  # WARN: gitignored — never commit real creds
```

The `<password>` field, by convention, references an env var: `password: $QA_PRIMARY_PASSWORD` so secrets stay out of files.

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

Save screenshots and recordings in the run dir, `.test-output/qa/<run-id>/` (gitignored by default). The QA report references them as relative paths. At the end of Phase 2, `ensemble-qa-evidence page` renders the run as one `index.html` that plays each flow's video beside its screenshots, and `ensemble-qa-evidence link` prints the page's tailnet URL on a machine that has opted in, or the local path and how to opt in.
