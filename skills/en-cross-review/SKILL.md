---
name: en-cross-review
description: "Ad-hoc Outside Voice peer review of any artifact (file, git diff, branch, uncommitted work). Ships the target to the peer agent (Codex if host is Claude; Claude if Codex; same-CLI fresh subprocess as single-agent fallback) and returns findings grouped by severity. Optional --focus (security | performance | tests | all). Trigger phrases: 'cross-review', 'second opinion', 'peer review this', 'outside voice on'."
# What this skill needs. Every path is skill-relative and must exist here.
# A skill is self-contained: nothing outside this directory is listed.
requires:
  - references/agent-dispatch.md
  - references/build-handoff.md
  - references/build-orchestration.md
  - references/cli-wrappers.md
  - references/diff-signal-detection.md
  - references/doc-lints.md
  - references/finding-schema.md
  - references/host-detect.md
  - references/outside-voice.md
  - references/peer-brief.md
  - references/peer-contract.md
  - references/peer-model-policy.md
  - references/persona-dispatch.md
  - references/recursion-guard.md
  - references/script-invocation.md
  - references/severity.md
  - references/single-agent-fallback.md
  - references/stable-ids.md
  - references/templates/plan-template.md
  - scripts/en-sweep-ci
  - scripts/ensemble-build-peer-prompt
  - scripts/ensemble-cli-smoke
  - scripts/ensemble-config-get
  - scripts/ensemble-detect-host
  - scripts/ensemble-extract-json
  - scripts/ensemble-lint
  - scripts/ensemble-peer-flags
  - scripts/ensemble-peer-invoke
  - scripts/ensemble-verify-peer-evidence

---


# `/en-cross-review`

> **Running a bundled script.** Anchor every call to this skill's own directory: `SKILL_DIR="<absolute path of the directory containing this SKILL.md>"; bash "$SKILL_DIR/scripts/<name>"`. The trailing `;` is load-bearing. See `references/script-invocation.md`.


> **Dispatching a bundled agent.** This skill carries its agents in `agents/`. Dispatch by name as usual; when the name is not registered (a lone skill directory), resolve it from the bundled definition per `references/agent-dispatch.md`.


Ad-hoc peer review. Wraps any artifact and ships it to the peer agent. The host parses findings JSON and surfaces them; the host applies the user-selected ones.

> **Peer contract.** Severity, confidence, autofix class, the `peer_decision`
> object and its reason enum are defined once in `references/peer-contract.md`
> and are byte-identical across every skill that exchanges findings. What this
> skill *does* with a finding is its own policy, not part of that contract.

> **Peer brief.** What the peer is asked, and what this skill does with the
> answer, is in `references/peer-brief.md`. The shared wire format is
> `references/peer-contract.md`.

## Process

1. **Detect host.** Source `references/host-detect.md`. Resolve `PEER`, `PEER_MODE`, `PEER_CMD`, `PEER_FORMAT`, `PEER_AVAILABLE`.
2. **Recursion guard.** If `ENSEMBLE_PEER_REVIEW=true`, exit with note: "Already inside a peer subprocess — skipping cross-review to avoid recursion."
3. **Resolve target.**
   - **No arg** → current uncommitted diff (`git diff` + `git diff --cached`).
   - **`<path>`** → contents of the file.
   - **`<git-ref>`** (e.g., `main..HEAD`, `HEAD~1`) → diff between refs.
   - **`<branch-name>`** → diff between branch and the default branch.
4. **Verify availability.** If `PEER_AVAILABLE=false`, exit with the reason (peer_mode_override=off; cross-agent-only without other CLI installed; etc.).
5. **Compose review prompt.** Shell out to `$SKILL_DIR/scripts/ensemble-build-peer-prompt` — do not assemble the prompt by reasoning. Required args:
   - `--artifact-type <code|plan|markdown artifact|mixed>` — `code` for diffs/files of source, `markdown artifact` for `docs/`, `plan` only when reviewing a `docs/plans/active/*.md` (rare for ad-hoc cross-review), else `mixed`.
   - `--project-context "<one-line>"` — first paragraph of `AGENTS.md` or foundation §1.
   - `--goal "<one-line>"` — for diffs: the most-recent commit subject; for files: the user's stated reason for the cross-review.
   - `--artifact-file <path>` (or pipe via stdin with `--artifact-stdin`) — the resolved target body.
   - `--peer-mode "$PEER_MODE"` — from host-detect.

   The helper substitutes the conditional blocks (single-agent fallback note, plan-specific review dimensions) for you.
6. **Apply `--focus` flag** (if set). Append to the prompt: "Focus your review on <focus>; deprioritize other concerns."
   Valid: `security`, `performance`, `tests`, `correctness`, `maintainability`, `all` (default).
7. **Set `ENSEMBLE_PEER_REVIEW=true`** in the subprocess env (recursion guard).
8. **Invoke peer via `$SKILL_DIR/scripts/ensemble-peer-invoke`.**
   ```bash
   . "$SKILL_DIR/scripts/ensemble-peer-invoke"
   peer_decision=$(ENSEMBLE_PEER_REVIEW=true ensemble_peer_invoke \
     --peer-cmd "$PEER_CMD" --peer-format "$PEER_FORMAT" --peer-turns "$PEER_TURNS" \
     --prompt-file "$prompt_file" --out-file /tmp/peer-response.json \
     --peer-mode "$PEER_MODE")
   ```
   **Do not hand-roll the invocation.** The helper owns the `timeout` wrapper (`peer_timeout_seconds`, default 600), failure classification (`auth` / `unknown` / `timeout`), the single bounded retry, and the fallback — executable and testable rather than prose (D41). It returns a `peer_decision` object per `references/peer-model-policy.md` (e); report its `peer`/`reason` so a failed or degraded peer never reads as a clean one.
9. **Detect D30 violations** (peer modified files). Per the protocol in `references/build-handoff.md`:
   - `git stash --include-untracked` before; check `git status` after.
   - Any change → revert; log violation; do not trust this round.
10. **Parse JSON response** per `references/finding-schema.md`. On malformed JSON: retry once with "respond with valid JSON only" suffix; if it fails again, surface and exit.
11. **Present findings** to the user grouped by severity (P0 → P3) and confidence:
    ```
    Cross-review verdict: revise (3 findings)
    Mode: cross-agent (peer: codex)
    Focus: all
    
    ### High (P1)
    
    1. **Refresh-token race in concurrent path** (correctness; conf 9)
       - src/auth/refresh.ts:42
       - Two requests can race during rotation; second invalidates the first.
       - Fix: serialize per-user via singleFlight cache.
       - Apply? (y/n/defer/disagree)
    
    [...]
    ```
12. **User picks per finding** (or `--apply-all-safe-auto` to auto-apply mechanical fixes).
13. **Apply selections** (per `references/severity.md`). Re-verify with project test/lint after edits. On regression: revert; surface.
14. **Capture-from-synthesis (D21)** — soft prompt at the end if the cross-review surfaced a non-obvious lesson worth filing.

## Flags

| Flag | Effect |
|---|---|
| `--focus security\|performance\|tests\|correctness\|maintainability\|all` | Bias the peer's attention |
| `--apply-all-safe-auto` | Auto-apply `safe_auto` findings without prompting |
| `--no-apply` | Show findings only; don't apply anything |
| `--mode cross-agent\|single-agent\|auto` | Override peer-mode resolution |

## Cross-review

This skill **is** the cross-review. No additional `--peer` flag.

## When `single-agent-fallback` fires

When only one CLI is installed (or `peer_mode_override: single-agent-only`):

- `PEER_CMD` = host's own CLI (e.g., `claude -p` from Claude Code).
- The Outside Voice prompt includes the single-agent augmentation (be more aggressive, bias toward finding problems).
- Findings carry `peer_mode: "single-agent-fallback"` so the user knows which mode they're in.

The contract from D30 still holds — the fresh subprocess returns findings only.

## No-write contract

The peer subprocess never modifies files. Detected violations (rare) are reverted automatically. The skill is fully read-only on the peer side; only the host applies user-selected findings.

## Reference files

- `references/host-detect.md` — host detection
- `references/outside-voice.md` — prompt template + verdict handling
- `references/single-agent-fallback.md` — same-CLI fallback contract
- `references/finding-schema.md` — JSON shape
- `references/severity.md` — apply / defer / disagree routing
- `references/recursion-guard.md` — `ENSEMBLE_PEER_REVIEW` env var

## Failure protocol

| Failure | Behavior |
|---|---|
| `PEER_AVAILABLE=false` | Exit with reason; suggest install of other CLI or `peer_mode_override` change |
| Peer subprocess times out | Log to stderr; mark cross-review as skipped; exit |
| Peer returns malformed JSON | Retry once; on second failure, surface raw output and exit |
| Peer attempted to modify files | Revert; log violation; do not trust findings; surface |
| Target file/ref doesn't resolve | Surface; suggest a valid target |
| User declines all findings | No-op; the cross-review still ran (cost incurred); surface a summary |
| `--no-apply` set + findings present | Output report; don't ask user to pick |

## Cost characteristics

| Artifact size | Approximate token cost |
|---|---|
| Small file or per-unit diff (< 100 lines) | 5K–15K |
| Mid-size diff (~500 lines) | 15K–40K |
| Large branch diff (1000+ lines) | 40K–100K (consider splitting) |

For genuinely large reviews, the user is better served by `/en-review` (multi-persona, parallel) than by `/en-cross-review` (single-pass peer). Use `/en-cross-review` when:
- The user wants a specifically *different* perspective (the other agent).
- The user wants a focused pass (`--focus security`).
- The user is operating from Codex and explicitly wants a Claude review (or vice versa).
