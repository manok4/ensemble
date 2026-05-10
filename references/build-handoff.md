# Build handoff (build-handoff flavor)

The default `en-build` flavor when **HOST = Codex**. Codex implements natively; Claude is dispatched as a **PEER-REVIEWER** (subject to D30: peer reports, host applies — never edits files). Codex parses the findings, applies what it agrees with, defers others to `tech-debt-tracker.md`, then commits.

> **Critical distinction.** This file describes PEER-REVIEWER dispatch. Worker dispatch (build-by-orchestration) lives in `build-orchestration.md`. Peer-reviewers must never modify files, run commands, or make commits — only return findings.

## Flow per unit

```
┌────────────────────────────────────────────────────────────────────┐
│  HOST = Codex                                                      │
│                                                                    │
│  for unit in plan.units:                                           │
│    1. Codex implements natively (edits files, runs tests).         │
│    2. Verification gate 1 (unit tests + lint).                     │
│    3. Code-simplifier pass (per references/code-simplifier-       │
│       dispatch.md).                                                │
│    4. Verification gate 2 (re-run after simplifier; revert on    │
│       failure).                                                    │
│    5. Dispatch Claude as PEER-REVIEWER. Pseudocode below; the      │
│       canonical, copy-pasteable invocation is in the next section │
│       ("Peer-reviewer dispatch prompt"). Pipe stdin, isolation     │
│       flags that PRESERVE subscription auth, wrapped in a          │
│       portable timeout binary, fail fast if neither timeout nor    │
│       gtimeout is on PATH:                                         │
│         ENSEMBLE_TIMEOUT_BIN=$(command -v timeout                  │
│           || command -v gtimeout) || exit 1   # see canonical for  │
│                                                  the full ERROR:   │
│                                                  message + brew    │
│                                                  install coreutils │
│         $ENSEMBLE_ROOT/bin/ensemble-build-peer-prompt ... | \      │
│           "$ENSEMBLE_TIMEOUT_BIN" "${peer_timeout_seconds:-600}" \ │
│             claude -p --output-format json --max-turns 1 \        │
│               --strict-mcp-config \                                │
│               --mcp-config '{"mcpServers":{}}' \                   │
│               --disable-slash-commands \                           │
│               --no-session-persistence \                           │
│               --setting-sources project \                          │
│               --tools ''                                           │
│         (env: ENSEMBLE_PEER_REVIEW=true; stderr captured to log)   │
│         (DO NOT use bare `timeout 600 claude ...` — fails on       │
│          macOS without coreutils; use the resolved binary above.)  │
│    6. Claude returns findings JSON (does NOT edit files — D30).    │
│    7. Codex parses JSON; apply / defer / disagree per             │
│       references/severity.md. Build a `resolutions[]` list as it   │
│       walks each finding (one entry per finding, with status).     │
│    8. Re-verify if any code changed.                               │
│    9. **Per-unit finalize loop.** Counter `re_review_count`       │
│       starts at 0; increments after each re-review pass. If        │
│       `verdict: revise` AND ≥1 finding applied AND                 │
│       `re_review_count < --max-per-unit-iterations` (default 1)   │
│       → re-invoke peer with `--iteration-context-file` carrying   │
│       the resolutions[] list, increment counter. Loop back to     │
│       step 6. On `approve` or cap exhaustion, continue. With      │
│       default cap=1, exactly one re-review fires when the         │
│       initial pass returned revise+applied findings.               │
│   10. Commit (conventional message + U-ID + `phase: P<N>` trailer │
│       + one `peer-resolution:` trailer per finding).               │
└────────────────────────────────────────────────────────────────────┘
```

## Peer-reviewer dispatch prompt

Use `bin/ensemble-build-peer-prompt` to assemble the Outside Voice prompt — do NOT build it by reasoning. The helper emits the slim template to **stdout** (single-agent fallback note + plan-specific dimensions are substituted automatically based on the flags you pass). The canonical invocation pipes that stdout directly into `claude` over stdin — never via `argv`.

### Canonical invocation (build-handoff)

Ensemble's peer-review subprocess **must use the host user's Claude subscription auth (OAuth / claude.ai / keychain)**, not an API key. This is a deliberate product decision: peer review piggy-backs on the user's existing subscription instead of requiring API credit. That rules out `--bare`, which by design reads only `ANTHROPIC_API_KEY` and bypasses keychain/OAuth entirely. Without `--bare` the peer subprocess pays for some startup work (hooks, LSP, plugin sync, CLAUDE.md auto-discovery), but `timeout` + the isolation flags below keep the cost bounded.

```bash
# 1. Build a tempfile containing the post-simplifier diff + the unit's plan section
cat > /tmp/en-build-unit-artifact.txt <<EOF
=== Unit: $U_ID — $UNIT_GOAL ===

== Unit specification (from plan) ==
$UNIT_BLOCK

== Post-simplifier diff ==
$POST_SIMPLIFIER_DIFF
EOF

# 2. Resolve a timeout binary. macOS doesn't ship `timeout`; coreutils
#    provides `gtimeout` via Homebrew. Fail fast if neither is present —
#    running peer review unwrapped re-enables the silent-hang failure
#    mode that prompted PR #9 in the first place.
ENSEMBLE_TIMEOUT_BIN=$(command -v timeout || command -v gtimeout) || {
  echo "ERROR: peer review requires 'timeout' or 'gtimeout' on PATH" >&2
  echo "  Install on macOS: brew install coreutils" >&2
  echo "  This guards against silent peer-subprocess hangs (per PR #9)." >&2
  exit 1
}

# 3. Pipe helper-stdout → claude-stdin. No argv-inlining of the prompt.
#    Isolation flags below skip MCP loading, slash-command/skill loading, session
#    persistence, and project/local settings — everything we can suppress without
#    losing the user's subscription auth.
#    timeout enforces peer_timeout_seconds (default 600) so a hang fails fast
#    instead of stalling the build forever.
#    stderr is captured for diagnostic visibility on failure.
ENSEMBLE_PEER_REVIEW=true $ENSEMBLE_ROOT/bin/ensemble-build-peer-prompt \
  --artifact-type code \
  --project-context "$ONE_LINE_PROJECT_CONTEXT" \
  --goal "Review unit $U_ID: $UNIT_GOAL" \
  --artifact-file /tmp/en-build-unit-artifact.txt \
  --peer-mode "$PEER_MODE" \
  | "$ENSEMBLE_TIMEOUT_BIN" "${peer_timeout_seconds:-600}" \
      claude -p --output-format json --max-turns 1 \
        --strict-mcp-config \
        --mcp-config '{"mcpServers":{}}' \
        --disable-slash-commands \
        --no-session-persistence \
        --setting-sources project \
        --tools '' \
      > /tmp/en-build-peer-response.json \
      2>/tmp/en-build-peer-stderr.log
```

> **Required on PATH:** `timeout` or `gtimeout` (GNU coreutils). macOS: `brew install coreutils`. Linux distros typically ship coreutils by default. Without it, peer review fails fast with a clear install instruction — never runs unwrapped.

For re-review iterations (see **Per-unit finalize loop** below), pass `--iteration-context-file <path>` with a serialized resolutions[] context — the helper inserts it between the artifact body and the JSON-shape instructions.

### Why this exact shape (not `prompt=$(...) ; claude -p "$prompt"`, and not `--bare`)

- **Pipe over argv.** Capturing the helper's stdout into a shell variable and re-passing as argv hits `ARG_MAX` and stalls some CLI argument-parsing paths — observed silent hangs in the field. Stdin avoids the entire class. The Claude CLI's `-p` description explicitly calls out: *"useful for pipes."*
- **No `--bare`.** *Per `claude --help`:* `--bare` is "Minimal mode: skip hooks, LSP, plugin sync, attribution, auto-memory, background prefetches, keychain reads, and CLAUDE.md auto-discovery." Functionally appealing — but it sets `CLAUDE_CODE_SIMPLE=1` and routes auth strictly through `ANTHROPIC_API_KEY` / `apiKeyHelper` (OAuth and keychain are NEVER read). On a host where the user is logged in via `claude.ai` (subscription) without a real API key in env, `--bare` returns `Not logged in · Please run /login` and the peer call fails. **Ensemble peer review must work with subscription auth, so `--bare` is intentionally not used.**
- **Isolation flags that preserve auth.** Drop-in substitutes for what `--bare` was buying us, all compatible with OAuth/keychain:
  - `--strict-mcp-config --mcp-config '{"mcpServers":{}}'` — skip MCP server loading entirely. The inline JSON must include the `mcpServers` key (an empty `{}` fails Claude's MCP-config schema validation); `{"mcpServers":{}}` is the schema-valid empty form.
  - `--disable-slash-commands` — skip skill / slash-command loading.
  - `--no-session-persistence` — don't write session state (works with `--print` only).
  - `--setting-sources project` — load **project-level** settings only; skip user-level config which typically includes the LSP plugin and other globally-enabled tools that can fire tool calls and consume `--max-turns 1` before producing output. Field-tested: `--setting-sources user` triggered an LSP-driven tool call that busted the single turn.
  - `--tools ''` — disable all built-in tools (Bash, Edit, Read, etc.) for the peer subprocess. **Load-bearing**: this is what physically prevents the model from making tool calls regardless of which settings load. Also matches the D30 contract — peer reports findings, never acts. With `--tools ''`, the `--max-turns 1` budget is reliably one model-response.
  - Hooks, LSP load, plugin sync, CLAUDE.md auto-discovery still happen at startup but cannot fire tool calls (because `--tools ''`). Bounded by `timeout`.
- **`timeout` wrapper, with portable resolution.** Without it, a hung peer blocks the build indefinitely. `peer_timeout_seconds` from `~/.ensemble/config.json` is the configured ceiling; the wrapper enforces it. macOS doesn't ship `timeout` in `/usr/bin/` — `brew install coreutils` provides it as `gtimeout`. The canonical invocation resolves with `command -v timeout || command -v gtimeout` and **fails fast (`exit 1`) if neither is present**, rather than silently dropping the wrapper. Falling back to unwrapped peer calls is exactly the failure mode PR #9 was built to eliminate.
- **stderr capture.** When a peer fails, the user needs `/tmp/en-build-peer-stderr.log` to diagnose (was it MCP init? auth? timeout? the dreaded `Please run /login`?). The default of swallowing stderr makes hangs invisible.

The Outside Voice prompt explicitly forbids file edits, commands, and commits (D30). The peer returns JSON-only findings (read from `/tmp/en-build-peer-response.json`).

### Auth preflight (recommended)

Skills should preflight subscription auth on the **first** peer dispatch in a session and fail loudly if it's missing — better than seeing every per-unit peer call fail with `Please run /login`:

```bash
auth_status=$(claude auth status --output-format json 2>/dev/null \
  | jq -r '.loggedIn // false')
if [ "$auth_status" != "true" ]; then
  echo "ERROR: Claude not logged in. Run 'claude /login' to authenticate." >&2
  echo "Ensemble peer review uses your subscription, not an API key." >&2
  exit 1
fi
```

Cache the result via the host-detect cache so it doesn't re-fire per unit.

## Per-unit finalize loop (`--max-per-unit-iterations`, default 1)

Same shape as `/en-plan`'s plan-level finalize loop, scoped to a single unit. When the per-unit peer returns `verdict: revise` and the host applies one or more findings, the implementation has changed since the peer reviewed it — those fixes haven't been verified. The loop runs the peer once more on the post-fix state.

**Counter semantics.** `re_review_count` starts at **0** and increments by 1 after each re-review pass. The initial peer pass at step 5 does NOT count toward it. With default cap=1, this guarantees **exactly one re-review pass** whenever the initial pass returned `revise` with applied findings — the post-fix diff is always peer-verified at default settings. (If the cap were checked against total iterations starting at 1, default cap=1 would never fire — that's the bug this counter avoids.)

Behavior:

| Verdict | Condition | Action |
|---|---|---|
| `approve` | any | Exit loop. Proceed to commit (step 10). The applied findings (if any) have been peer-verified. |
| `revise` | ≥1 finding applied AND `re_review_count < cap` | Build `peer_review_resolutions[]` (schema below), serialize into a `## Previous review context` tempfile, re-invoke peer with `--iteration-context-file`. Increment `re_review_count` after the re-review returns. |
| `revise` | cap reached AND ≥1 finding applied on the cap-hitting pass | Exit loop. **Surface a P1 warning** in the unit summary: those last applications were verified by lint+tests at step 8 but NOT by another peer pass. User can raise `--max-per-unit-iterations` if this recurs. Commit with current resolutions. |
| `revise` | cap reached AND all findings on the cap-hitting pass deferred/disagreed | Exit loop without warning. Commit with current resolutions. |
| `revise` | no findings applied (all deferred or disagreed) | Exit loop — re-running peer wouldn't see different code. Commit with current resolutions. |
| `reject` | any | Pause and surface to user. Don't loop. |

**Cap rationale.** Per-unit findings tend to be mechanical fixes that converge fast. Default `--max-per-unit-iterations: 1` means one re-review max (so total of 2 peer passes per unit max: initial + 1 re-review). Override with `--max-per-unit-iterations <N>` on `/en-build`. Set to `0` to disable per-unit looping entirely (revert to single-pass, pre-PR behavior).

**Iteration prompt context.** The "Previous review context" section is assembled from the unit's `peer_review_resolutions[]` list — same format as `/en-plan`'s plan-level loop:

```text
## Previous review context (iteration {N})

This is iteration {N+1} of the per-unit review for U{ID}. Verify previously-
applied findings actually resolve the concern; surface only NEW issues or
unresolved-from-previous. Do not re-litigate findings listed below unless
you have new evidence.

### Applied (peer should verify the fix landed):
- [{finding_id}] {title} — {applied_summary}

### Deferred (do NOT re-flag):
- [{finding_id}] {title} — Rationale: {rationale}

### Disagreed-with (do NOT re-flag unless new evidence):
- [{finding_id}] {title} — Rationale: {rationale}
```

## Resolution log (`peer_review_resolutions[]` per unit)

As Codex walks each finding in step 7, it appends a structured entry to a per-unit `resolutions[]` array. Each entry mirrors the plan-level schema in `references/templates/plan-template.md`, scoped to the unit:

```yaml
- finding_id: <peer-supplied or host-minted as `u<N>-<iteration>-<index>`, e.g. `u3-1-2`>
  u_id: U<N>
  iteration: <integer; iteration of the per-unit loop>
  severity: P0 | P1 | P2 | P3
  title: <short title from peer>
  status: applied | deferred | disagreed | superseded
  rationale: <one-line reason; required for non-applied>
  location: <file:line or section name>
```

This list is held in memory during the unit loop, surfaced in the unit's progress report, and serialized into the commit message as structured trailers (see Commit message format below).

## Single-agent fallback (when only Codex installed)

If Claude CLI isn't installed, fall back to **fresh subprocess of Codex itself** (`codex exec` with a separate context window):

- `PEER_MODE=single-agent-fallback`
- `PEER_CMD=codex exec`
- Outside Voice prompt augmented per `references/single-agent-fallback.md` (be more aggressive, bias toward finding problems)
- The contract from D30 still holds — the fresh Codex subprocess returns findings only.

## What Codex applies (step 7)

For each finding, Codex chooses one of three responses (per `references/severity.md`):

1. **Agree and apply.** Edit files; re-verify; commit.
2. **Agree but defer.** Append entry to `docs/plans/tech-debt-tracker.md` with a TD-ID. Cite the unit.
3. **Disagree with rationale.** Note in unit progress report; don't apply.

The user is surfaced only on contention (host disagrees with P0; high-confidence security/architecture deferral; peer verdict = reject; conflicting findings).

## Re-verify after applying

Same as build-by-orchestration — if Codex applies any code changes in response to peer findings, re-run unit tests + lint before commit. On failure: `git restore`; surface to user.

## Commit message format

```
<type>(<scope>): <short subject> — U<N>

<body>

Implementer: codex (native)
Code-simplifier: <changed N files | skipped>
Peer review (claude, mode: cross-agent, iterations: <N>):
  - Applied: <count> findings
  - Deferred to tech-debt-tracker.md: <count> findings
  - Disagreed: <count> findings

phase: P<N>
peer-verdict: {"verdict":"revise","peer_mode":"cross-agent","iteration":1,"findings_count":2,"summary":"Two correctness concerns; auth path solid, refresh-token race needs serialization"}
peer-resolution: {"finding_id":"u3-1-1","u_id":"U3","iteration":1,"severity":"P1","status":"applied","title":"Race in refresh path"}
peer-resolution: {"finding_id":"u3-1-2","u_id":"U3","iteration":1,"severity":"P2","status":"deferred","rationale":"low conf, tracked TD12","title":"Edge case"}
```

For a clean approve with zero findings, the commit carries the `peer-verdict:` trailer alone:

```
phase: P2
peer-verdict: {"verdict":"approve","peer_mode":"cross-agent","iteration":1,"findings_count":0,"summary":"Plan is well-scoped; no findings."}
```

**Trailers contract.**

- **`peer-verdict:`** — exactly one per peer pass on this unit. Written whenever the peer actually ran (`approve` / `revise` / `reject` verdict, regardless of finding count). Required keys: `verdict`, `peer_mode`, `iteration`, `findings_count`. Optional: `summary`. **The `findings_count` field MUST match the number of `peer-resolution:` trailers below** — `bin/ensemble-verify-peer-evidence` cross-checks them.
- **`peer-resolution:`** — one per finding. JSON schema per the resolution table above. Zero of these is valid when peer approved with no findings (the `peer-verdict:` trailer carries the evidence).
- **`peer-skipped:`** — present ONLY when peer didn't run; mutually exclusive with `peer-verdict:`.

Why trailers: `git interpret-trailers --parse` and `git log --grep="^peer-verdict:"` (or `peer-resolution:`, or `peer-skipped:`) are stable, scriptable, and don't require per-unit metadata files. Reviewers can audit by greppable history; future automation (e.g. `/en-resolve-pr` mining what got deferred) reads trailers cleanly.

### `peer-skipped:` trailer (for documented skip cases)

When peer review legitimately cannot run on a unit, the commit MUST carry a `peer-skipped:` trailer with a reason from the documented enum — and this is the ONLY way to advance without a `peer-resolution:` trailer. Writing "Peer review approved" as plain prose is **not** a valid skip; the verify gate (`bin/ensemble-verify-peer-evidence`) will reject the commit.

```
phase: P2
peer-skipped: PEER_AVAILABLE=false
```

Documented skip reasons (enum):

| Reason | When to use |
|---|---|
| `PEER_AVAILABLE=false` | Host-detect resolved no peer (cross-agent unavailable, single-agent disabled by override). build-handoff cannot dispatch. |
| `--no-peer-per-unit-flag` | User passed the flag explicitly to skip per-unit peer review. |
| `peer-subprocess-failed:<one-line-detail>` | Subprocess timeout, malformed JSON twice, D30 violation, or auth failure (e.g. `Please run /login`). The detail goes in a colon-separated suffix for diagnosis. **Surface to the user;** for `risk: destructive` or `gated: true` units, this skip is **not allowed** — the build must halt instead. |
| `cap-exhausted-with-applied-findings` | Per-unit finalize loop hit the iteration cap with applied findings on the last pass. Already P1-warning-surfaced per `skills/en-build/SKILL.md` step 9h.1; the trailer makes it auditable. |
| `recursion-guard-active` | `ENSEMBLE_PEER_REVIEW=true` was set at start (this build is itself running inside a peer subprocess). Cannot recursively dispatch; must skip. |
| `auto-skip:diff-below-threshold` | Unit's diff is smaller than `skip_peer_below_lines` (default 50). Per-unit cost-control auto-skip from `~/.ensemble/config.json`. |
| `auto-skip:lightweight-depth` | Plan's `depth: lightweight` AND `skip_peer_on_lightweight: true`. Per-plan cost-control auto-skip. |

**Anything else is a contract violation.** "I forgot," "the conversation was compacted," "I assumed it would be ok" — there are no entries in this enum for those. The verify gate at step 9k will reject the commit; the agent must either re-run peer review and produce a `peer-resolution:` trailer or halt and surface to the user.

**Destructive / gated units cannot use `peer-skipped:`.** Those units require an actual peer pass — no flag, no skip reason, no fallback path lets them ship without `peer-resolution:` evidence. The verify gate runs with `--require-peer-resolution` for those units; if peer dispatch fails, the build halts.

## Failure of peer subprocess

| Failure | Behavior |
|---|---|
| `claude -p` subprocess times out | Record `peer-skipped: peer-subprocess-failed:timeout` (not just "skipped") so the verify gate has machine-readable evidence. Commit; surface in summary. **Halt** if the unit is destructive or gated. |
| Malformed JSON response | Retry once with "respond with valid JSON only" suffix; on second failure, record `peer-skipped: peer-subprocess-failed:malformed-json` and proceed. **Halt** if destructive / gated. |
| Peer subprocess CLI error | Record `peer-skipped: peer-subprocess-failed:<error-message>`; surface; offer `--no-peer-per-unit` to continue without (will record `--no-peer-per-unit-flag` skip reason). **Halt** if destructive / gated. |
| Peer attempted to modify files (D30 violation) | Detect by checking git status before/after subprocess; revert any changes; record `peer-skipped: peer-subprocess-failed:d30-violation`; log violation; do not trust this round of findings. **Halt** if destructive / gated. |
| Auth failure (e.g. `Please run /login`) | Record `peer-skipped: peer-subprocess-failed:auth`. The auth preflight in step 5 should have caught this before the first unit; if it surfaces mid-build, halt and surface clearly. |

## Detecting D30 violations

Before invoking the peer subprocess:

```bash
git stash --include-untracked --quiet
PEER_BASE_SHA=$(git rev-parse HEAD)
```

After:

```bash
if [ -n "$(git status --porcelain)" ]; then
  echo "WARNING: peer subprocess modified the working tree (D30 violation). Reverting." >&2
  git restore --staged .
  git restore .
  git clean -fd  # remove any untracked files the peer created
  # Do not trust this round of findings — they came from a process that broke its contract
fi
git stash pop --quiet
```

This is defensive — Outside Voice prompt is explicit about not editing, so violations should be rare. The check ensures they're caught and contained.

## When to use this flavor

- HOST = Codex (default).
- HOST = Claude but user passed `--handoff` to explicitly use peer-reviewer dispatch.

## Environment

- `ENSEMBLE_PEER_REVIEW=true` is set in the subprocess — recursion guard.
- `--max-turns 1` for the peer call (single response).
- `peer_timeout_seconds` from `~/.ensemble/config.json` (default 600).
