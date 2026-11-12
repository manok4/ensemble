---
type: design
created: 2026-11-12
topic: en-qa records a short video of each UI change it verifies, kept out of git and viewable from another machine on the tailnet
status: accepted
related_plan: EN31
---

# en-qa records a short video of each UI change it verifies, kept out of git and viewable from another machine on the tailnet

## Problem

When `/en-qa` runs Phase 2 on a change that alters what a user sees or does, the only evidence it keeps is screenshots under `.test-output/qa/`. The PR body reports nothing beyond a test line (`skills/en-ship/scripts/ensemble-pr-body:84-100`). A screenshot shows an end state. It cannot show that a click led to that state, so a reviewer either trusts the report or checks out the branch and drives the app by hand.

The goal is a short video per verified flow. It stays in the gitignored test output, and the user can open it from a second Mac: QA runs on the Mac Mini, and the user reviews on the MacBook Pro.

## Constraints and context

Verified in this repository and on this machine on 2026-11-12:

- **Phase 2 is already gated.** It runs only when `needs_browser` is true or `--browser` is passed (`skills/en-qa/SKILL.md:38`). Video inherits that gate, so it never fires on a backend-only change.
- **The run dir already exists.** Each run writes `.test-output/qa/<run-id>/flows.json` before its first flow (`skills/en-qa/SKILL.md:43`). `.test-output/` is gitignored (`.gitignore`, "Build / test output").
- **One driver per run, and never a third stack** (`skills/en-qa/references/browser-driver.md`, "Selecting"). Recording must use the driver the run already picked.
- **Driver recording support:**
  - T3 Code preview has `preview_recording_start` / `preview_recording_stop`. Stop returns a local path, capped at 50 MiB. The container format is not stated.
  - Playwright MCP, as installed (`@playwright/mcp@latest` with no `--caps`), lists no video tool. Upstream, `browser_start_video` needs `--caps=devtools` (https://playwright.dev/mcp/tools/video). The installed server does expose `browser_run_code_unsafe`, and Playwright 1.59+ has `page.screencast.start({ path })` / `stop()` (https://playwright.dev/docs/api/class-screencast). That gives a recorder without changing the plugin config.
  - Claude desktop browser pane: recording support is unknown.
- **The tailnet is already in use.** Both Macs are on one tailnet, and the Mini shows `active; direct`. The MacBook already runs `tailscale serve` for a T3 Code proxy (`/ proxy http://127.0.0.1:3773`, tailnet only). Tailscale here is the standalone build 1.104.4, not the App Store build.
- **`ensemble` is a public repo.** A link or upload placed in its PRs is public.
- **No ffmpeg** on the MacBook. The Mac Mini is unchecked.
- **Prior decision to reconcile.** The accepted trust-strategy design sets "Video only on FAIL or bug reproduction" as the evidence default for the future ship-time verifier harness (`docs/designs/2026-09-26-agent-trust-strategy-design.md`, "Harness performance" item 6). It also lists "Proof in the PR" as a medium gap (A3). That harness does not exist yet. This design covers `/en-qa`, which is already the slow, deep pass. The verifier's light-evidence default stands for the verifier.

### Prior art

Sources and quotes are from the web-research pass on 2026-11-12.

| Harness | How it records | Where the reviewer sees it |
|---|---|---|
| Cursor cloud agents | Live: "The agent recorded itself interacting with desktop applications in its VM" (cursor.com/blog/agent-computer-use) | Opt-in posting into the PR description, at unauthenticated, unguessable URLs (cursor.com/docs/cloud-agents/capabilities). Its forum reports broken Playwright-built mp4s |
| Devin | Live full-screen capture during its post-PR test. "Raw recordings are processed to highlight important actions and compress idle time" (docs.devin.ai, testing-and-recordings) | Attached to the session message, in the webapp or Slack, not the PR |
| Google Antigravity | WebM session recordings from the browser subagent on its DevTools MCP path | Its Artifacts view |
| GitHub Copilot coding agent | Screenshots only, through Playwright MCP | Inline in the PR |
| Vercel agent-browser, playwright-cli | In-place recorders (`record start/stop`, `video-start/stop`). The playwright-cli skill advises recording a scripted "hero" replay for proof of work | Local file |

Two patterns stand out. Every harness that ships video records the agent's own live run rather than a replay, and the one that makes live video watchable (Devin) compresses the idle time afterwards. None keeps video only on local disk: each uploads it somewhere the reviewer already looks.

## Assumptions & unverified claims

- T3 Code's recording plays in Safari and QuickTime. The container is not documented. If it is WebM, Safari has played VP8/VP9 since 14.1, but no 2026 source confirms it. Unverified.
- `tailscale serve` can serve a directory on the standalone macOS build. Tailscale's docs say file serving needs root, and this build runs its daemon as a system extension. Unverified. The fallback is a proxy to a local static file server, which is the mode the user already runs.
- Tailscale's file server follows symlinks. Unverified, and the registry in the recommendation depends on it.
- The Mac Mini stays awake. A sleeping Mini drops off the tailnet, and Wake for network access is reported as unreliable. Unverified for this machine.
- `page.screencast` is available through `browser_run_code_unsafe` on the installed `@playwright/mcp@latest`. It depends on the bundled Playwright version. Unverified.

## Approaches considered

### A. Record the live run, link it over the tailnet

**Sketch:** When a flow starts, `/en-qa` starts the active driver's recorder and stops it when the flow reaches its verified end state, or its failing step. The recorder is T3 `preview_recording_*`, or `page.screencast` through `browser_run_code_unsafe` on Playwright MCP. The file lands in `.test-output/qa/<run-id>/<flow-id>.<ext>`, and the flow's entry in `flows.json` gets a `video` field. If ffmpeg is present, a post-process removes duplicate frames, so a two-minute model-paced run becomes a short clip, and writes an H.264 MP4. Otherwise the raw file is kept. The run also writes one `index.html` beside `flows.json` that shows each flow's outcome, video and screenshots. A machine-level tailnet mapping serves those run dirs, and the QA report prints one `https://<host>.<tailnet>.ts.net/qa/...` link per run.

**Pros:**
- Same pattern as Cursor, Devin and Antigravity: the video shows the run that was actually judged, not a reenactment.
- Uses the driver the run already chose, so the one-driver and no-third-stack rules hold.
- Nothing leaves the user's devices. That matters on a public repo.
- The tailnet and `tailscale serve` are already part of the user's setup.

**Cons:**
- Without ffmpeg the clips are long. Each model turn is seconds of a still page.
- The link dies when the Mini sleeps or a worktree is deleted.
- Needs a one-time per-machine step to set up the tailnet mapping.

### B. Replay a scripted "hero" run with video on

**Sketch:** The flow runs as today, with no recorder. Once it passes, the model writes a short Playwright script from the locators it used and replays it with `page.screencast`, chapter cards and action highlights. It is linked over the tailnet as in A.

**Pros:**
- Tight 15 to 30 second clips that read well, without ffmpeg.
- The script is the seed of a scripted drive, the shape the trust-strategy harness (A1) wants under `.ensemble/verify/drives/`.

**Cons:**
- T3 preview, the preferred driver, cannot run Playwright code. B would force a second driver on most runs, which breaks the one-driver rule.
- The video shows a replay, not the verified run. A replay that passes where the live run was flaky is the false evidence this skill exists to prevent.
- Roughly doubles browser time per flow, plus a model turn to write the script.

### C. Record live, attach to the PR with `gh --attach`

**Sketch:** Record as in A. `/en-ship`, or `/en-qa` when a PR exists, uploads each MP4 with `gh pr comment --attach` (`gh` 2.99+, MP4/MOV/WebM, 10 MB on free plans and 100 MB on paid; github.blog changelog 2026-09-01). Installed `gh` is 2.102.0.

**Pros:**
- The video sits where the review happens, works while the Mini sleeps, and plays on any device.
- No tailnet setup.

**Cons:**
- On a public repo, every clip of the app becomes public. On a private repo, sources disagree on whether attachment URLs need auth.
- The user asked for local storage. This publishes a copy.
- Size caps force short clips, so it needs the same ffmpeg step as A anyway.
- An upload happens on every UI PR, which is outward-facing by default.

## Recommendation

**Approach A, with idle compression when ffmpeg is present and one link per run.** It is the only option that meets the request as stated: stored in the gitignored test output, not published, viewable from the MacBook. It also matches what every shipping harness does: record the run that was judged. B was rejected because it breaks the one-driver rule on the preferred driver and swaps evidence for a reenactment. C is a good later addition for private repos, but on by default it would publish app recordings from a public repo.

Calls made without asking (`/en-conductor` question policy), each reversible in the plan:

- **What gets recorded:** each in-scope flow's golden path and the failing step of a `Fail`. Edge cases are not recorded. After a `fix(qa):` commit, the re-verify run replaces the flow's video. This was chosen over recording every edge case, which multiplies clip count for checks a screenshot already covers.
- **Viewing:** a tailnet link printed in the QA report and stored in `flows.json`. `gh --attach` was not chosen.
- **The PR body** links the run page only when the repo is private, chosen over always linking. A public PR would otherwise carry the Mini's hostname and tailnet name.
- **Machine setup:** a one-time opt-in step in `setup` or `/en-setup` maps `/qa` on the tailnet to a machine-level registry dir, chosen over having `/en-qa` edit Tailscale config itself. On each run, `/en-qa` symlinks `~/.ensemble/qa/<repo>/<run-id>` to the run dir and prunes dangling links. The video stays in the repo's `.test-output/`. With no mapping on the machine, the report prints the local path and says why no link was made.
- **A driver with no recorder** (the Claude desktop pane, if it has none) keeps screenshots and reports `video: unavailable (<driver>)`. It never installs a stack.
- **The trust-strategy default** stays for the verifier harness. `/en-qa` records on Pass because it is the deep pass, and the PR proof (A3) is the gap this design starts to close.

## Devil's advocate

- **Nobody will watch a two-minute clip of a page idling.** True without ffmpeg, which is absent on the MacBook today. Devin's answer, compressing idle time, is the one that works. If the plan finds ffmpeg absent on the Mini too, installing it there is a one-line machine step. A missing ffmpeg degrades the clip, never the QA run.
- **The link dies with the worktree.** Worktrees that `/en-conductor` creates are cleaned up after merge, so their `.test-output/` goes with them. That is acceptable for "review the PR today". It is not durable evidence. Durable evidence is C's job, scoped to private repos, later.
- **Recording adds cost to every Phase 2 flow.** The recorder runs in the browser, not in the model, so token cost is roughly unchanged. Disk use is the real cost: an uncompressed clip can reach the 50 MiB T3 cap. Retention (prune runs older than N days) is out of scope here, but the plan should size it.
- **Recording can break a flow.** A recorder that fails to start must not fail the flow. The flow runs, the video field reads `unavailable: <reason>`, and the report says so.
- **What if the framing is wrong, and the user wants a demo for others rather than proof for themselves?** Then C's PR upload, or B's polished replay, matter more. The request says "I can still view it from my MacBook Pro", so the reader is the user. The recommendation optimizes for that.
- **Six months out:** if the trust-strategy harness lands, scripted drives will replace model clicking, and the drive itself can record (`recordVideo`). That makes A's live clips short for free and retires the ffmpeg step. Nothing here blocks that path.

## Open questions

These are for `/en-plan`'s first unit, a spike on the Mac Mini:

- Does `tailscale serve --bg --set-path /qa <dir>` serve files and follow symlinks on the standalone build, or does it need the local static-server proxy?
- What container and codec does `preview_recording_stop` write, and does it play in Safari and QuickTime on the MacBook?
- Does `page.screencast` work through `browser_run_code_unsafe` on the installed Playwright MCP?
- Is ffmpeg on the Mac Mini, and does `mpdecimate,setpts=N/FRAME_RATE/TB` give a watchable clip from a real T3 recording?
- Does the Claude desktop browser pane expose a recorder?

## Next steps

- Run `/en-conductor docs/designs/2026-11-12-en-qa-video-evidence-design.md` to plan and build it, or `/en-plan` for the plan alone.
- Not in scope: `gh --attach` uploads, retention and pruning of old runs, recording edge cases, and a polished replay mode.
