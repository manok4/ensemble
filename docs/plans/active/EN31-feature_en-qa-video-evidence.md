---
type: plan
plan_type: feature
plan_id: EN31
title: en-qa records a video per verified flow, viewable over the tailnet
status: in_progress
location: active
created: 2026-11-12
shipped:
deepened:
covers_requirements: []
requirements_pending: true
related_design: docs/designs/2026-11-12-en-qa-video-evidence-design.md
peer_review_verdict: revise
peer_review_iterations: 2
peer_review_last_run: 2026-11-12
peer_review_plan_hash: 0086325557e6a6276e496f9735468d4307bb66f54b3274b1713c9d9632965365
# Machine-readable resolution log written by /en-plan as findings are
# applied/deferred/disagreed/superseded/escalated. /en-build pre-flight reads this
# directly — never the iteration-log prose.
peer_review_resolutions:
  - finding_id: 1-1
    iteration: 1
    severity: P1
    title: Encoding failure can delete the source recording
    status: applied
    location: U1
  - finding_id: 1-2
    iteration: 1
    severity: P1
    title: Fallback copy failures have no truthful output policy
    status: applied
    location: U1
  - finding_id: 1-3
    iteration: 1
    severity: P1
    title: Recording integration lacks behavioral scenarios
    status: applied
    rationale: live scenarios added and checked by hand during build; no behavioural eval case, since evals are on-demand and a recorder in a headless eval is flaky
    location: U3
  - finding_id: 2-1
    iteration: 2
    severity: P1
    title: Successful encoding can still replace the source recording
    status: applied
    location: U1
  - finding_id: 2-2
    iteration: 2
    severity: P2
    title: Screenshot URL validation leaves a security decision open
    status: applied
    location: U1
depth: standard
data_scale: small
---

# EN31 — en-qa records a video per verified flow, viewable over the tailnet

## Context

`/en-qa` Phase 2 keeps screenshots only, so a reviewer cannot see that an action led to the end state it reports. The design (`docs/designs/2026-11-12-en-qa-video-evidence-design.md`) settled the shape. Record each verified flow's live run with the driver the run already uses, keep the video in the gitignored `.test-output/qa/<run-id>/`, and reach it from a second Mac through a tailnet link. Nothing is uploaded.

## Requirements covered

None. Foundation has no R-IDs for skill behaviour (`requirements_pending: true`, as on recent plans).

## Out of scope for this plan

- Uploading video to a PR (`gh --attach`). See Decisions for the reason.
- A link in the PR body. Reversed from the design's call, see Decisions.
- Retention or pruning of old run dirs and videos.
- Recording edge-case checks, and a polished scripted replay mode.
- Editing Tailscale, launchd or `~/.ensemble/config.json` on the user's behalf. Machine setup is print-only.

## Approach (high-level)

One new en-qa script, `ensemble-qa-evidence`, does every mechanical step, so the prose only says when to call it. It has four subcommands:

- `video` copies a driver's recording into the run dir. When ffmpeg is on PATH it first strips idle frames and encodes H.264 MP4.
- `page` renders a self-contained `index.html` from `flows.json`.
- `link` registers the run dir under a machine-level directory, `~/.ensemble/qa/<repo>/<run-id>`, as a symlink, and prints the tailnet URL when the machine has opted in.
- `setup` prints the one-time machine commands, which put a loopback static file server behind `tailscale serve` on its own HTTPS port.

`/en-qa` records each in-scope flow's golden path, or its failing step, with the driver it already chose:

- T3 Code preview: `preview_recording_start` / `preview_recording_stop`.
- Playwright MCP: `page.screencast` through its run-code tool.

A driver with no recorder keeps screenshots and reports the video as unavailable. A recording failure never changes a flow's outcome. `CONTRACT.md` gains an `evidence` return field, so `/en-conductor` can relay the link from its QA stage.

## Test seams

- **The `ensemble-qa-evidence` CLI** (new). It runs in a scratch git repo with `HOME` pointed at a scratch dir and `ffmpeg` / `tailscale` stubbed on PATH, following `tests/lint/ensemble-ship-watch.test.sh` and `tests/lint/ensemble-pr-body.test.sh`. Every behaviour in U1 and U2 is observed here: stdout lines, files written, symlinks made.
- **Skill prose clauses** (existing pattern: `tests/lint/en-qa-browser-detector.test.sh`, `tests/lint/run-ledgers.test.sh`). U3's wiring is prose a model follows. The repo pins such clauses with greps, and live browser behaviour is covered only by the on-demand behavioural evals, which stay out of CI.

## Technical design

Data flows through four stages. Each stage's output is the next stage's input, and every path is relative to the run dir.

```
driver recorder ──(local file path)──▶ ensemble-qa-evidence video ──▶ <run-dir>/<flow-id>.mp4|.webm
                                                                          │ (model writes the value into flows.json)
<run-dir>/flows.json ──▶ ensemble-qa-evidence page ──▶ <run-dir>/index.html
<run-dir> ──▶ ensemble-qa-evidence link ──▶ ~/.ensemble/qa/<repo-slug>/<run-id> → <run-dir>  (symlink)
                                         └─▶ stdout: link: https://<dns-name>:8443/<repo-slug>/<run-id>/index.html
machine (once): python3 http.server 127.0.0.1:8765 --directory ~/.ensemble/qa  ◀── tailscale serve --https=8443
```

**`flows.json` shape**, pinned here because the model writes it (U3) and `page` reads it (U1). Fields beyond these are ignored:

```json
{
  "run_id": "20261112T161420Z",
  "flows": [
    {
      "id": "F3",
      "name": "Sign in",
      "outcome": "pending | Pass | Fail | Skip",
      "reason": "free text, empty on Pass",
      "video": "F3.mp4 | unavailable: <reason> | null",
      "screenshots": ["F3-golden-1.png"]
    }
  ]
}
```

**`<run-id>`** is the UTC time Phase 2 starts, as `YYYYMMDDTHHMMSSZ`. The run dir is `.test-output/qa/<run-id>/`.

## Implementation units

### U1. `ensemble-qa-evidence video` and `page`: keep the recording and render the run page

- **Goal:** A recording ends up in the run dir as a short clip, and a run's flows render as one self-contained HTML page.
- **Requirements covered:** none
- **Dependencies:** none
- **Interfaces:**
  - *Produces:* `ensemble-qa-evidence video --run-dir <dir> --flow <id> --src <path>`. It prints exactly one stdout line, `video: <file>` (a basename inside `<dir>`) or `video: unavailable: <reason>`, and exits 0. A usage error exits 64 with a usage line on stderr.
  - *Produces:* `ensemble-qa-evidence page --run-dir <dir>`. It writes `<dir>/index.html`, prints `page: <dir>/index.html` and exits 0. A missing or unparsable `<dir>/flows.json` prints `page: no readable flows.json in <dir>` on stderr and exits 1.
  - Compatibility: new script, no existing callers.
- **Files:**
  - `skills/en-qa/scripts/ensemble-qa-evidence` (create)
  - `tests/lint/ensemble-qa-evidence.test.sh` (create)
- **Approach:** A POSIX-ish bash script with a subcommand dispatch, `set -u`, and an inline `python3` for the HTML, the same way `skills/en-ship/scripts/ensemble-pr-body` uses python3.
  - **`video`:**
    - Sanitize `--flow` to `[A-Za-z0-9._-]`, replacing anything else with `-`.
    - A missing or empty `--src` prints `video: unavailable: no recording at <src>`.
    - **The source is never deleted, truncated or replaced.** Every write goes to a temp name in `<dir>` (`.<id>.tmp.<pid>.<ext>`) and is renamed over the destination only after it succeeds. A temp file left by a failure is removed. The original `<src>` is only ever read.
    - **An aliased source is left alone on every path.** First compare `<src>`'s physical path (`cd -P` on its dir plus its basename) with `<dir>/<id>.mp4` and `<dir>/<id>.<ext>`. If it equals either, run no encode and no copy, and print `video: <that basename>`.
    - When `command -v ffmpeg` succeeds, encode to the temp name with `ffmpeg -nostdin -loglevel error -y -i <src> -vf mpdecimate,setpts=N/FRAME_RATE/TB -an -c:v libx264 -pix_fmt yuv420p -movflags +faststart <dir>/.<id>.tmp.<pid>.mp4`. On exit 0 with a non-empty temp, `mv -f` it to `<dir>/<id>.mp4` and print `video: <id>.mp4`.
    - Otherwise (no ffmpeg, or a failed encode, which also writes `ffmpeg failed; kept the raw recording` to stderr), keep the raw file as `<dir>/<id>.<ext>`. `<ext>` is the source extension lowercased, `webm` when it has none.
      - `cp` it to the temp name and `mv -f` it into place. The aliased case never reaches this point.
      - Print `video: <id>.<ext>` only after that succeeds.
    - Any copy or rename failure, such as an unreadable source or an unwritable run dir, prints `video: unavailable: could not write <id>.<ext>: <error>` and exits 0. A filename is printed only when the file exists and is non-empty.
    - A re-run for the same flow overwrites its files, which is how a re-verify replaces the clip.
  - **`page`:**
    - Load `flows.json` and accept only an object with a `flows` list.
    - Render a page titled `QA run <run_id>` with inline CSS and light and dark colours through `prefers-color-scheme`, and no external assets.
    - Each flow gets a section with id, name, outcome and reason. A `video` that is a plain relative filename renders `<video controls preload="metadata">` with a `<source>` whose `type` is `video/mp4` or `video/webm` by extension. Any other `video` value renders as text.
    - Each screenshot renders as a linked `<img>`.
    - Every value is HTML-escaped.
    - **One local-media rule** covers every video `src`, screenshot `src` and screenshot `href`. A value is used as a link only when it matches `^[A-Za-z0-9._/-]+$` (so no scheme `:`, no `%`, no space), does not start with `/`, and has no `..` segment. It is then passed through `urllib.parse.quote` with `safe="/"`. Any other value renders as escaped text and never as an attribute.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Patterns to follow:** `tests/lint/ensemble-ship-watch.test.sh` (PATH stubs whose output is asserted); `tests/lib/assert.sh` helpers, with a final `report` call.
- **Test scenarios:**
  - *Happy path:* an `ffmpeg` stub that writes a non-empty file at its last argument. `video --flow F3 --src rec.webm` prints `video: F3.mp4`, `<dir>/F3.mp4` exists, and the stub's recorded argv contains `mpdecimate`.
  - *Happy path:* no `ffmpeg` on PATH (PATH restricted to a stub bin plus system dirs without ffmpeg). `video --flow F3 --src rec.WEBM` prints `video: F3.webm`, the copy is byte-identical, and `rec.WEBM` still exists.
  - *Edge case:* `--flow 'F 3/x'` writes `F-3-x.mp4`. A second `video` call for F3 overwrites the first file.
  - *Error path:* `--src` missing prints `video: unavailable: no recording at <path>` and exits 0. An `ffmpeg` stub that exits 1 falls back to the raw copy, prints the stderr note, and leaves no `F3.mp4` and no `.F3.tmp.*` file.
  - *Error path:* source already in place. `--src <dir>/F3.mp4 --flow F3` leaves `<dir>/F3.mp4` byte-identical and prints `video: F3.mp4`. This is checked twice, once with an `ffmpeg` stub that exits 1 and once with one that succeeds, whose argv log must then be empty (no encode ran).
  - *Error path:* an unreadable source (`chmod 000`) prints `video: unavailable: could not write F3.webm:` and leaves no `F3.webm`. A read-only run dir (`chmod 555`) prints the same prefix. Both exit 0. Both checks are skipped with a `pass` note when running as root, where permissions do not bite.
  - *Error path:* `video` without `--run-dir` exits 64.
  - *Happy path:* `page` over a `flows.json` with a Pass flow (`video: "F3.mp4"`) and a Skip flow (`video: "unavailable: no recorder"`) writes `index.html` containing a `<video` element with `F3.mp4` and `video/mp4`, plus the literal text `unavailable: no recorder`.
  - *Edge case:* a flow name `<script>x</script>` appears escaped. None of these appears inside any `src=` or `href=` attribute, and each renders as text: a `video` of `../secret.mp4`, and screenshots `/etc/x.png`, `javascript:alert(1)`, `https://example.com/x.png` and `%2e%2e/x.png`. A screenshot `shots/F3 1.png` is rejected for its space. A valid `shots/F3-1.png` appears as both `src="shots/F3-1.png"` and `href="shots/F3-1.png"`.
  - *Error path:* `page` with no `flows.json`, or with `{"flows": 3}`, exits 1 with the stderr line.
- **Verification:** `./tests/run.sh -k ensemble-qa-evidence` passes; `./tests/select-for.sh skills/en-qa/scripts/ensemble-qa-evidence` selection passes.

### U2. `ensemble-qa-evidence link` and `setup`: reach the run from another machine

- **Goal:** On an opted-in machine, every QA run prints a tailnet URL to its page. On any other machine it prints the local page path and how to opt in.
- **Requirements covered:** none
- **Dependencies:** U1
- **Interfaces:**
  - *Produces:* `ensemble-qa-evidence link --run-dir <dir> [--home <dir>]`. It prints two stdout lines and exits 0. The first is `link: <url>` or `link: none: <reason>`. The second is `page: <absolute path to <dir>/index.html>`.
  - *Produces:* `ensemble-qa-evidence setup [--port <n>] [--https-port <n>]`, print-only. It exits 0 after printing the commands, and exits 1 with `setup: tailscale not available: <reason>` when `tailscale status --json` fails or has no `Self.DNSName`.
  - *Produces:* config key `qa_evidence_base_url`, flat and read through `ensemble-config-get`, so the cascade puts the repo `.ensemble/config.local.yaml` over `~/.ensemble/config.json`. The value is the base URL with no trailing slash, e.g. `https://<mac>.<tailnet>.ts.net:8443`.
  - *Consumes:* the `ensemble-config-get` sibling script (`--home` passthrough).
  - Compatibility: additive subcommands and a new optional key.
- **Files:**
  - `skills/en-qa/scripts/ensemble-qa-evidence` (modify)
  - `skills/en-qa/scripts/ensemble-config-get` (create; byte-identical copy of `skills/en-ship/scripts/ensemble-config-get`, kept so by `tests/parity/script-parity.test.sh`)
  - `tests/lint/ensemble-qa-evidence.test.sh` (modify)
- **Approach:**
  - **`link`:**
    - Resolve `<dir>` to an absolute path. `<run-id>` is its basename.
    - `<slug>` is the basename of `git -C <dir> rev-parse --show-toplevel`, sanitized to `[A-Za-z0-9._-]`. It is `local` outside a git repo.
    - Read `qa_evidence_base_url` with the sibling `ensemble-config-get`, passing `--home` when given (default `$HOME`).
    - Unset or empty prints `link: none: this machine has not opted in; run: bash <this script's absolute path> setup`.
    - Set: `mkdir -p <home>/.ensemble/qa/<slug>`, delete every dangling symlink directly under it, `ln -sfn <abs dir> <home>/.ensemble/qa/<slug>/<run-id>`, and print `link: <base-url>/<slug>/<run-id>/index.html`. A trailing `/` on the base URL is stripped.
    - Any filesystem error prints `link: none: <error>` and still exits 0, because evidence never fails a QA run.
  - **`setup`:**
    - Read `Self.DNSName` from `tailscale status --json` with python3 and strip the trailing dot. Defaults are `--port 8765` and `--https-port 8443`.
    - Print, filled in, these commands:
      1. `mkdir -p ~/.ensemble/qa`.
      2. A `cat > ~/Library/LaunchAgents/dev.ensemble.qa-evidence.plist` heredoc. Its `ProgramArguments` are `/usr/bin/python3 -m http.server <port> --bind 127.0.0.1 --directory <abs home>/.ensemble/qa`, with `RunAtLoad` and `KeepAlive` true.
      3. `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/dev.ensemble.qa-evidence.plist`.
      4. `tailscale serve --bg --https=<https-port> http://127.0.0.1:<port>`.
      5. A `jq` line that sets `qa_evidence_base_url` to `https://<dns-name>:<https-port>` in `~/.ensemble/config.json`, creating `{}` first when the file is absent.
      6. `curl -sfI https://<dns-name>:<https-port>/` as the check.
    - Close with one line: the Mac must stay awake for the link to answer.
    - Writes nothing itself.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** reversible
- **Gated:** false
- **Ship scope:** in
- **Execution note:** test-first
- **Patterns to follow:** `skills/en-setup/references/setup-optional-installs.md` "The sweep machine's commands" (print-only machine commands).
- **Test scenarios:**
  - *Happy path:* scratch `HOME` whose `.ensemble/config.json` sets `qa_evidence_base_url` to `https://box.tail.ts.net:8443/`, and a run dir `<repo>/.test-output/qa/20261112T000000Z` inside a scratch git repo named `demo`. `link` prints `link: https://box.tail.ts.net:8443/demo/20261112T000000Z/index.html`, and `$HOME/.ensemble/qa/demo/20261112T000000Z` is a symlink resolving to the run dir.
  - *Edge case:* a dangling symlink already under `$HOME/.ensemble/qa/demo/` is removed by `link`, and a live sibling symlink is kept. Running `link` twice for the same run leaves one symlink.
  - *Edge case:* a run dir outside any git repo uses slug `local`.
  - *Error path:* no config key prints `link: none: this machine has not opted in; run: bash ` followed by the script path ending `ensemble-qa-evidence setup`, then the `page:` line. It creates no `$HOME/.ensemble/qa`.
  - *Happy path:* a `tailscale` stub printing `{"Self":{"DNSName":"box.tail.ts.net."}}` makes `setup` print `tailscale serve --bg --https=8443 http://127.0.0.1:8765`, `https://box.tail.ts.net:8443` and `launchctl bootstrap`, and leaves `$HOME` unchanged (no new files).
  - *Error path:* a `tailscale` stub that exits 1 makes `setup` exit 1 with `setup: tailscale not available:`.
  - *Integration:* `tests/parity/script-parity.test.sh` passes with the new `skills/en-qa/scripts/ensemble-config-get` copy.
- **Verification:** `./tests/run.sh -k ensemble-qa-evidence` and `./tests/run.sh -k script-parity` pass.

### U3. Wire recording into `/en-qa` and relay the link through `/en-conductor`

- **Goal:** `/en-qa` records each in-scope flow's golden path, or its failing step, with the run's own driver, renders the run page, and reports the link. Its contract returns the link, and `/en-conductor` puts it in its report.
- **Requirements covered:** none
- **Dependencies:** U1, U2
- **Files:**
  - `skills/en-qa/SKILL.md` (modify)
  - `skills/en-qa/references/browser-driver.md` (modify)
  - `skills/en-qa/CONTRACT.md` (modify)
  - `skills/en-conductor/SKILL.md` (modify)
  - `docs/foundation.md` (modify)
  - `tests/lint/en-qa-video-evidence.test.sh` (create)
- **Approach:**
  - **`skills/en-qa/SKILL.md` step 7:**
    - Define `<run-id>` as the UTC start of Phase 2 (`YYYYMMDDTHHMMSSZ`) where the flow ledger is introduced. Keep the existing substrings `.test-output/qa/<run-id>/flows.json` and `from the flow ledger`, which `tests/lint/run-ledgers.test.sh` pins.
    - Name the ledger fields `id`, `name`, `outcome`, `reason`, `video` and `screenshots`.
    - Add one paragraph, "Record the golden path". Start the driver's recorder at the flow's entry point and stop it at the verified end state, or at the failing step on `Fail`. Then run `bash "$SKILL_DIR/scripts/ensemble-qa-evidence" video --run-dir <run-dir> --flow <id> --src <recording>` and store its value in the flow's `video` field.
    - Edge cases are not recorded. A re-verify after a `fix(qa):` commit re-records and replaces the clip.
    - A recorder that fails to start or stop never changes the flow's outcome. The field reads `unavailable: <reason>`.
  - **`skills/en-qa/SKILL.md` step 9:** before the report, run `page` then `link` and print the `link:` and `page:` lines in the report. Add one `Evidence:` line to the `## Output format` example.
  - **`skills/en-qa/references/browser-driver.md`:**
    - Add a "Recording a flow" section:
      - T3 Code: `preview_recording_start` with the tab, then `preview_recording_stop`, which returns the file path (≤50 MiB).
      - Playwright MCP: its run-code tool (`browser_run_code_unsafe` or `browser_run_code`, whichever the host lists). Start with `async page => { await page.screencast.start({ path: '<abs run-dir>/<id>.raw.webm' }) }` and stop with `async page => { await page.screencast.stop() }`. An error from either call means `unavailable: playwright has no screencast`.
      - Any other host-native surface records only if it lists a recording tool, else `unavailable: <driver> has no recorder`.
      - Never install a recorder.
    - Fix the existing screenshot path, which disagrees with `SKILL.md`: `.test-output/qa-<flow-name>-<step>.png` becomes `.test-output/qa/<run-id>/<flow-id>-<step>.png`. Mention the run page and link in "Output evidence".
  - **`skills/en-qa/CONTRACT.md`:**
    - Return table gets a row `evidence`: `link: <url>` or `link: none: <reason>`, plus the run page path, present whenever Phase 2 ran.
    - Under Authority envelope, add that the skill writes evidence under the run dir and one symlink under `~/.ensemble/qa/`.
    - Name no `scripts/` or `references/` paths (`tests/lint/contract-shape.test.sh` forbids it).
  - **`skills/en-conductor/SKILL.md`:** in the QA stage row's Gate cell, add that QA's `evidence` line is logged as the stage's evidence and printed in the report. Keep the substring `only when \`needs_browser\` is true` (`tests/lint/en-conductor.test.sh:47`).
  - **`docs/foundation.md`:**
    - §5.2.6 step 6 now names video and the run page.
    - Its Reference files line names the script.
    - Add **D148** at the end of §4.1: "/en-qa keeps a video of each verified flow, local and gitignored, and reaches it over the tailnet, never by upload." The rationale names the trust-strategy verifier's video-on-FAIL default as unchanged for the verifier.
  - **`tests/lint/en-qa-video-evidence.test.sh`:** greps, ending in `report`:
    - SKILL.md contains `ensemble-qa-evidence" video`, `ensemble-qa-evidence" page` and `ensemble-qa-evidence" link`, plus `never changes the flow's outcome`.
    - browser-driver.md contains `preview_recording_start` and `page.screencast`, and no longer contains `.test-output/qa-`.
    - CONTRACT.md has an `evidence` row.
    - en-conductor's QA row contains `evidence`.
    - foundation contains `D148`.
- **Risk:** medium
- **Category:** feature
- **Reversibility:** trivial
- **Gated:** false
- **Ship scope:** in
- **Execution note:** pragmatic
- **Patterns to follow:** `tests/lint/en-qa-browser-detector.test.sh` (clause greps with a final `report`).
- **Test scenarios:** the clause test pins the wording. The behaviour is the model following that wording, which only a live run observes. Behavioural evals (`tests/evals/run-behavioral`) are on demand and never in CI, and this plan adds no eval case: a browser plus a recorder in a headless eval is the flaky setup that path avoids. So the live scenarios below are checked once by hand during the build, against a static two-page fixture served from the scratchpad with `python3 -m http.server`, driven by whichever driver the build session has. If none is available, the build report says so and the PR lists them as unverified.
  - *Happy path (live):* `/en-qa --browser --flow F1` on a flow whose golden path passes. Expect: `flows.json` has F1 `outcome: Pass` with `video: "F1.mp4"` (or `F1.webm` without ffmpeg), the file exists in the run dir, `index.html` plays it, and the report carries the `link:` and `page:` lines.
  - *Error path (live):* a flow whose end state is wrong (the fixture's second page omits the expected text). Expect `outcome: Fail` and a `video` that ends at the failing step. The report names the flow, and the outcome is unchanged by recording.
  - *Error path (live):* the recorder cannot start, simulated by passing a `--src` path that does not exist to `video`. Expect `video: "unavailable: no recording at <path>"` while the flow keeps its own outcome.
  - *Edge case (live):* after a `fix(qa):` re-verify, the same flow's `video` file is replaced, with a newer mtime, and the ledger entry points at it.
  - *Integration:* `/en-conductor`'s QA stage agent returns the `evidence` field verbatim, and the conductor logs it as the stage's evidence (`log stage qa ok '<link line>'`) and prints it. This is pinned by the clause test on the QA row and checked live only when a conductor run reaches QA.
  - *Happy path:* `tests/lint/en-qa-video-evidence.test.sh` passes with every clause above present.
  - *Error path (negative control):* deleting the `video` call line from a scratch copy of SKILL.md makes the test fail. The test reads the path from an overridable variable, so the control runs against the copy.
  - *Integration:* `tests/lint/run-ledgers.test.sh`, `tests/lint/en-qa-browser-detector.test.sh`, `tests/lint/en-qa-autonomy-contract.test.sh`, `tests/lint/contract-shape.test.sh`, `tests/lint/en-conductor.test.sh`, `tests/lint/skill-helper-anchor.test.sh` and `tests/lint/skill-size.test.sh` still pass. `bin/ensemble-lint --scope docs/foundation.md` is clean, and the decision-log order test passes with D148.
- **Verification:** `./tests/select-for.sh` over the changed paths passes; full `./tests/run.sh` before commit.

## Decisions, assumptions & risks

- **Decision:** No PR-body link, reversing the design's "private repos only" call. `/en-ship` runs in a fresh agent with no channel to `/en-qa`'s run. Its only QA input is a free-text `--qa` line (`skills/en-ship/scripts/ensemble-pr-body:29,75-78`), and nothing under `skills/` detects repo visibility. Adding both is a second feature, and on this public repo it would never fire. The QA report and `/en-conductor`'s report carry the link.
- **Decision:** Machine setup is a print-only `setup` subcommand of the en-qa script, not an `/en-setup` step. The setup is per machine, not per project, and `skills/en-setup/SKILL.md` is at 24,503 of 26,624 bytes. This follows the precedent of `/en-setup`'s print-only sweep-machine commands.
- **Decision:** A loopback `python3 -m http.server` behind `tailscale serve --https=8443`, over serving the directory itself or mounting a path under `/`. Directory serving needs root and is unverified on the standalone macOS build, and a path mount's prefix stripping is unverified. The user's existing `/` proxy keeps port 443. Verified 2026-11-12: `/usr/bin/python3` 3.9.6 `http.server` serves files through a symlinked dir.
- **Decision:** Registry symlinks under `~/.ensemble/qa/<repo>/<run-id>`, over serving each repo's `.test-output/` directly. This keeps one served root per machine, and the video stays in the repo's gitignored dir as asked.
- **Alternative:** `gh pr comment --attach`. Rejected: every clip would be public on a public repo, and the user asked for local storage.
- **Assumption:** `page.screencast` exists in the Playwright bundled by `@playwright/mcp@latest` (API since Playwright 1.59). If not, the run reports `unavailable` and keeps screenshots. Falsified by the first Playwright-driven run.
- **Assumption:** T3 Code's recording file plays in Safari and QuickTime. With ffmpeg present it is re-encoded to H.264 MP4 regardless. Without ffmpeg it is kept as recorded.
- **Risk:** disk growth from raw recordings up to 50 MiB each. **Mitigation:** idle compression when ffmpeg exists. Retention is out of scope and noted for a follow-up.
- **Risk:** the link answers only while the recording Mac is awake and the worktree exists. **Mitigation:** `setup` says so. Dangling registry links are pruned on the next `link`.

## Tracked debt

None resolved or filed.

## Iteration log

> - 2026-11-12 (initial): plan v0 from `docs/designs/2026-11-12-en-qa-video-evidence-design.md`.
> - 2026-11-12 (iteration 1, codex, revise): applied 1-1, encoding goes to a temp file and never deletes the source. Applied 1-2, a filename is printed only after a successful write, with `unavailable` otherwise. Applied 1-3, live behavioural scenarios for U3, checked by hand during the build.
> - 2026-11-12 (iteration 2, codex, revise; cap reached): applied 2-1 (the peer re-used id 1-1, recorded as 2-1), so an aliased source is left alone on the encode path too. Applied 2-2, one local-media rule for every `src` and `href`. Accepted as-is at the cap with every finding applied, a call made under `/en-conductor`'s question policy.
