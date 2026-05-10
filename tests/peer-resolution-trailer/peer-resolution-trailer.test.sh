#!/usr/bin/env bash
# Tests for the peer-resolution: git-trailer format used by /en-build's
# per-unit commits (Phase A+B+C: per-unit finalize loop).
#
# The trailer carries single-line JSON describing one peer-review finding's
# resolution. Tools downstream (audit, /en-resolve-pr mining, etc.) parse it
# via `git interpret-trailers --parse` or `git log --grep="^peer-resolution:"`.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="peer-resolution trailer"

# --- Build a sample commit message with the documented trailer format ---
TMP_MSG=$(mktemp)
cat > "$TMP_MSG" <<'EOF'
feat(auth): wrap rotateRefreshToken in singleFlight — U3

Body of the commit.

Implementer: codex (native)
Code-simplifier: changed 2 files
Peer review (claude, mode: cross-agent, iterations: 2):
  - Applied: 1 findings
  - Deferred to tech-debt-tracker.md: 1 findings
  - Disagreed: 0 findings

phase: P2
peer-resolution: {"finding_id":"u3-1-1","u_id":"U3","iteration":1,"severity":"P1","status":"applied","title":"Race in refresh path"}
peer-resolution: {"finding_id":"u3-1-2","u_id":"U3","iteration":1,"severity":"P2","status":"deferred","rationale":"low conf, tracked TD12","title":"Edge case"}
peer-resolution: {"finding_id":"u3-2-1","u_id":"U3","iteration":2,"severity":"P2","status":"applied","title":"Test coverage gap caught on re-review"}
EOF

# --- git interpret-trailers parses all peer-resolution lines ---
trailer_count=$(git interpret-trailers --parse < "$TMP_MSG" | grep -c "^peer-resolution:" || true)
assert_eq "3" "$trailer_count" "git interpret-trailers parses 3 peer-resolution lines"

phase_trailer=$(git interpret-trailers --parse < "$TMP_MSG" | grep "^phase:" | head -1)
if echo "$phase_trailer" | grep -q "phase: P2"; then
  pass "phase: trailer also parsed alongside peer-resolution:"
else
  fail "phase: trailer missing or malformed" "$phase_trailer"
fi

# Stash the parsed trailers into an array (process substitution keeps us
# in the main shell so pass/fail counters update correctly).
trailers=()
while IFS= read -r line; do
  trailers+=("$line")
done < <(git interpret-trailers --parse < "$TMP_MSG" | grep "^peer-resolution:")

assert_eq "3" "${#trailers[@]}" "captured 3 trailer lines into array"

# --- Each peer-resolution value is single-line valid JSON ---
i=0
for line in "${trailers[@]}"; do
  i=$((i+1))
  json="${line#peer-resolution: }"
  if echo "$json" | jq empty 2>/dev/null; then
    pass "peer-resolution[$i] value is valid JSON"
  else
    fail "peer-resolution[$i] value is not valid JSON" "$json"
  fi
done

# --- All required fields are present in each entry ---
i=0
for line in "${trailers[@]}"; do
  i=$((i+1))
  json="${line#peer-resolution: }"
  for f in finding_id u_id iteration severity status title; do
    if echo "$json" | jq -e "has(\"$f\")" >/dev/null 2>&1; then
      pass "peer-resolution[$i] has required field: $f"
    else
      fail "peer-resolution[$i] missing required field: $f" "$json"
    fi
  done
done

# --- finding_id format: u<N>-<iteration>-<index> ---
for line in "${trailers[@]}"; do
  json="${line#peer-resolution: }"
  fid=$(echo "$json" | jq -r '.finding_id')
  if echo "$fid" | grep -qE '^u[0-9]+-[0-9]+-[0-9]+$'; then
    pass "finding_id matches u<N>-<iter>-<idx> format: $fid"
  else
    fail "finding_id format wrong (expected u<N>-<iter>-<idx>)" "got: $fid"
  fi
done

# --- u_id matches the U-ID pattern ---
for line in "${trailers[@]}"; do
  json="${line#peer-resolution: }"
  uid=$(echo "$json" | jq -r '.u_id')
  if echo "$uid" | grep -qE '^U[0-9]+$'; then
    pass "u_id matches U<N> format: $uid"
  else
    fail "u_id format wrong" "got: $uid"
  fi
done

# --- severity is one of P0/P1/P2/P3 ---
for line in "${trailers[@]}"; do
  json="${line#peer-resolution: }"
  sev=$(echo "$json" | jq -r '.severity')
  case "$sev" in
    P0|P1|P2|P3) pass "severity in valid enum: $sev" ;;
    *) fail "severity not in P0|P1|P2|P3" "got: $sev" ;;
  esac
done

# --- status is one of applied/deferred/disagreed/superseded ---
for line in "${trailers[@]}"; do
  json="${line#peer-resolution: }"
  st=$(echo "$json" | jq -r '.status')
  case "$st" in
    applied|deferred|disagreed|superseded) pass "status in valid enum: $st" ;;
    *) fail "status not in applied|deferred|disagreed|superseded" "got: $st" ;;
  esac
done

# --- non-applied entries have rationale ---
for line in "${trailers[@]}"; do
  json="${line#peer-resolution: }"
  st=$(echo "$json" | jq -r '.status')
  if [ "$st" != "applied" ]; then
    rat=$(echo "$json" | jq -r '.rationale // empty')
    if [ -n "$rat" ]; then
      pass "non-applied entry ($st) has rationale: '$rat'"
    else
      fail "non-applied entry ($st) missing rationale" "$json"
    fi
  fi
done

# --- iteration is an integer >= 1 ---
for line in "${trailers[@]}"; do
  json="${line#peer-resolution: }"
  it=$(echo "$json" | jq -r '.iteration')
  if echo "$it" | grep -qE '^[1-9][0-9]*$'; then
    pass "iteration is positive integer: $it"
  else
    fail "iteration not a positive integer" "got: $it"
  fi
done

# Sanity: at least one entry has iteration > 1 (proves the schema supports
# the per-unit finalize loop's re-review pass).
has_reiter=false
for line in "${trailers[@]}"; do
  json="${line#peer-resolution: }"
  it=$(echo "$json" | jq -r '.iteration')
  [ "$it" -gt 1 ] 2>/dev/null && has_reiter=true
done
if [ "$has_reiter" = "true" ]; then
  pass "trailer schema supports iteration > 1 (re-review findings)"
else
  fail "trailer schema example should include at least one iteration > 1 entry"
fi

# --- Both reference docs include the trailer format example (no drift) ---
HANDOFF_DOC="$REPO_ROOT/references/build-handoff.md"
ORCH_DOC="$REPO_ROOT/references/build-orchestration.md"

if grep -q "^peer-resolution: " "$HANDOFF_DOC"; then
  pass "build-handoff.md includes peer-resolution: trailer example"
else
  fail "build-handoff.md missing peer-resolution: trailer example"
fi

if grep -q "^peer-resolution: " "$ORCH_DOC"; then
  pass "build-orchestration.md includes peer-resolution: trailer example"
else
  fail "build-orchestration.md missing peer-resolution: trailer example"
fi

# --- Documentation example JSON is parseable (catches typos in copy-paste) ---
for doc in "$HANDOFF_DOC" "$ORCH_DOC"; do
  doc_name=$(basename "$doc")
  doc_trailers=()
  while IFS= read -r line; do
    doc_trailers+=("$line")
  done < <(grep "^peer-resolution: " "$doc")
  for line in "${doc_trailers[@]}"; do
    json="${line#peer-resolution: }"
    if echo "$json" | jq empty 2>/dev/null; then
      pass "[$doc_name] trailer example JSON parses"
    else
      fail "[$doc_name] trailer example JSON broken" "$json"
    fi
  done
done

# --- en-build SKILL.md mentions the new flag and the per-unit loop ---
SKILL="$REPO_ROOT/skills/en-build/SKILL.md"
if grep -q -- "--max-per-unit-iterations" "$SKILL"; then
  pass "en-build SKILL.md documents --max-per-unit-iterations flag"
else
  fail "en-build SKILL.md missing --max-per-unit-iterations"
fi
if grep -q "Per-unit finalize loop" "$SKILL"; then
  pass "en-build SKILL.md mentions Per-unit finalize loop"
else
  fail "en-build SKILL.md missing per-unit finalize loop reference"
fi
if grep -q "peer-resolution" "$SKILL"; then
  pass "en-build SKILL.md references peer-resolution trailer"
else
  fail "en-build SKILL.md missing peer-resolution trailer reference"
fi

# --- build-handoff.md uses ensemble-build-peer-prompt helper ---
if grep -q "bin/ensemble-build-peer-prompt" "$HANDOFF_DOC"; then
  pass "build-handoff.md wires through bin/ensemble-build-peer-prompt"
else
  fail "build-handoff.md should reference the helper script"
fi

# --- Counter semantics are explicit: re_review_count starts at 0 (P2 from Codex review) ---
# The condition "iteration < cap" with iteration starting at 1 and default cap=1
# never fires — that was the bug. Each ref doc must state explicit counter
# semantics (`re_review_count` starting at 0) so the loop fires at default settings.
for doc in "$HANDOFF_DOC" "$ORCH_DOC"; do
  doc_name=$(basename "$doc")
  if grep -q "re_review_count" "$doc"; then
    pass "[$doc_name] uses explicit re_review_count counter"
  else
    fail "[$doc_name] missing explicit re_review_count semantics" "loop condition is ambiguous without it"
  fi
  if grep -q "starts at 0" "$doc"; then
    pass "[$doc_name] documents re_review_count starting at 0"
  else
    fail "[$doc_name] should document counter starting value (starts at 0)"
  fi
done

if grep -q "re_review_count" "$SKILL"; then
  pass "en-build SKILL.md uses explicit re_review_count counter"
else
  fail "en-build SKILL.md missing re_review_count semantics"
fi
if grep -q "starts at 0" "$SKILL"; then
  pass "en-build SKILL.md documents re_review_count starting at 0"
else
  fail "en-build SKILL.md should document counter starting value"
fi

# --- Both flow charts mention phase: P<N> trailer alongside peer-resolution ---
# Codex flagged the flow charts only mentioning peer-resolution: trailers,
# omitting the required phase: P<N> trailer that /en-ship and greppable
# history rely on.
for doc in "$HANDOFF_DOC" "$ORCH_DOC"; do
  doc_name=$(basename "$doc")
  # Extract just the flow chart block (between the ASCII art borders).
  flow_chart=$(awk '
    /^```$/ && capture { exit }
    /┌─/ { capture=1 }
    capture { print }
  ' "$doc")
  if echo "$flow_chart" | grep -q "phase: P"; then
    pass "[$doc_name] flow chart mentions phase: P<N> trailer"
  else
    fail "[$doc_name] flow chart should mention phase: P<N> trailer alongside peer-resolution"
  fi
  if echo "$flow_chart" | grep -q "peer-resolution"; then
    pass "[$doc_name] flow chart mentions peer-resolution trailer"
  else
    fail "[$doc_name] flow chart missing peer-resolution mention"
  fi
done

# --- Cap-hit warning surfaces a P1 (regression for P2 #1 from Codex) ---
# When the cap is hit AND findings were applied on the last re-review pass,
# the spec requires a P1 warning surfaced to the user — those applications
# weren't peer-verified. The wording should make the un-peer-verified status
# explicit so users notice and consider raising the cap.
if grep -q -E "(P1 warning|cap.exhaust|cap-hit|cap exhaust)" "$HANDOFF_DOC"; then
  if grep -q -E "(NOT (be|been|by) (peer|another peer)|not.*verified by.*peer|NOT.*another peer pass)" "$HANDOFF_DOC"; then
    pass "build-handoff.md surfaces cap-hit warning that calls out un-peer-verified state"
  else
    fail "build-handoff.md should explicitly note that cap-hit applications are NOT peer-verified"
  fi
else
  fail "build-handoff.md missing cap-hit / cap-exhaustion language"
fi
if grep -q -E "(P1 warning|cap.exhaust|cap-hit|cap exhaust)" "$SKILL"; then
  pass "en-build SKILL.md mentions cap-hit handling"
else
  fail "en-build SKILL.md should mention cap-hit warning behavior"
fi

# --- Peer invocation hardening (silent-hang failure mode) ---
# Field-observed silent hang: capturing helper stdout into a shell variable
# and re-passing via argv hit ARG_MAX on a large staged diff. Documented
# pattern must pipe stdin, wrap in timeout, capture stderr.
#
# Auth note: Ensemble's contract is subscription-auth (OAuth / claude.ai /
# keychain). The Claude CLI's `--bare` flag bypasses that auth and produces
# "Not logged in · Please run /login" on subscription-only hosts. So we
# CANNOT use --bare; we use weaker isolation flags that are auth-compatible.

OUTSIDE_VOICE="${REPO_ROOT}/references/outside-voice.md"
HELPER="${REPO_ROOT}/bin/ensemble-build-peer-prompt"

# 1. Both build-handoff and outside-voice document piping helper-stdout
#    directly into the peer command (no `prompt=$(...)` capture).
for doc in "$HANDOFF_DOC" "$OUTSIDE_VOICE"; do
  doc_name=$(basename "$doc")
  if grep -qE 'ensemble-build-peer-prompt[[:space:]]*\\?$' "$doc" || grep -qE '\| (timeout|claude|\$PEER_CMD)' "$doc"; then
    pass "[$doc_name] uses pipe-stdin invocation pattern"
  else
    fail "[$doc_name] should pipe helper stdout into peer (not argv-capture)"
  fi
done

# 2. Both reference docs wrap the peer call in `timeout`.
for doc in "$HANDOFF_DOC" "$OUTSIDE_VOICE"; do
  doc_name=$(basename "$doc")
  if grep -qE '\btimeout\b' "$doc"; then
    pass "[$doc_name] wraps peer call in timeout"
  else
    fail "[$doc_name] should wrap peer call in timeout for hang protection"
  fi
done

# 3. Both reference docs capture stderr for diagnostic visibility.
for doc in "$HANDOFF_DOC" "$OUTSIDE_VOICE"; do
  doc_name=$(basename "$doc")
  if grep -qE '2>/tmp/[^ ]*stderr' "$doc"; then
    pass "[$doc_name] captures peer stderr"
  else
    fail "[$doc_name] should capture peer stderr to a log file"
  fi
done

# 4. argv-inlining anti-pattern is explicitly labeled.
if grep -q "ARG_MAX\|argv" "$OUTSIDE_VOICE"; then
  pass "outside-voice.md explicitly warns against argv-inlining"
else
  fail "outside-voice.md should explicitly warn against argv-capture anti-pattern"
fi
if grep -qE "[Aa]nti-pattern|ANTI-PATTERN|do not use" "$OUTSIDE_VOICE"; then
  pass "outside-voice.md surfaces an explicit anti-pattern block"
else
  fail "outside-voice.md should label the anti-pattern explicitly"
fi

# 5. Subscription-auth contract — --bare must be explicitly forbidden in the
#    canonical invocation across all three docs (it bypasses subscription auth
#    and produces "Please run /login" failures on subscription-only hosts).
for doc in "$HANDOFF_DOC" "$OUTSIDE_VOICE" "$HELPER"; do
  doc_name=$(basename "$doc")
  # Extract just the canonical invocation block (between ```bash and ``` after the canonical pattern, or the relevant comment block in the helper header).
  # The simpler check: --bare must NOT appear as part of an active claude or $PEER_CMD invocation on a single line.
  if grep -qE '^\s*(\|?\s*claude|\|?\s*\$PEER_CMD)[^#]*--bare' "$doc"; then
    fail "[$doc_name] uses --bare in a canonical claude invocation — bypasses subscription auth"
  else
    pass "[$doc_name] does not use --bare in canonical invocation"
  fi
done

# 6. Subscription-auth rationale is explicit (so future contributors don't
#    re-add --bare for performance reasons).
for doc in "$HANDOFF_DOC" "$OUTSIDE_VOICE" "$HELPER"; do
  doc_name=$(basename "$doc")
  if grep -qE "subscription.*auth|claude\.ai|OAuth|/login" "$doc"; then
    pass "[$doc_name] explains subscription-auth contract"
  else
    fail "[$doc_name] should explain why --bare is rejected (subscription-auth)"
  fi
done

# 7. Auth-compatible isolation flags are documented as the --bare substitute.
for doc in "$HANDOFF_DOC" "$OUTSIDE_VOICE"; do
  doc_name=$(basename "$doc")
  for flag in "--strict-mcp-config" "--disable-slash-commands" "--no-session-persistence" "--setting-sources project" "--tools ''"; do
    if grep -qF -- "$flag" "$doc"; then
      pass "[$doc_name] documents isolation flag: $flag"
    else
      fail "[$doc_name] missing isolation flag: $flag"
    fi
  done
done

# 7a. --setting-sources user must NOT be in the canonical invocation
#     (loads LSP plugin which fires tool calls and busts --max-turns 1).
#     Allow mentions in markdown prose (`--setting-sources user` in
#     backticks or in rationale text) — only flag active code-block uses.
#     Active uses end with " \" (bash line continuation) or appear in
#     ASCII-art flow charts (lines with leading │).
for doc in "$HANDOFF_DOC" "$OUTSIDE_VOICE" "$HELPER"; do
  doc_name=$(basename "$doc")
  if grep -qE '(\\$|│.*user[[:space:]]+│).*--setting-sources[[:space:]]+user' "$doc" \
     || grep -qE '--setting-sources[[:space:]]+user[[:space:]]+\\$' "$doc" \
     || grep -qE '│[[:space:]]+--setting-sources[[:space:]]+user' "$doc"; then
    fail "[$doc_name] still uses --setting-sources user in an active invocation"
  else
    pass "[$doc_name] does not use --setting-sources user in active invocation"
  fi
done

# 7b. --mcp-config must use schema-valid empty form, not plain '{}' (fails MCP schema).
for doc in "$HANDOFF_DOC" "$OUTSIDE_VOICE" "$HELPER"; do
  doc_name=$(basename "$doc")
  if grep -qE "[-]-mcp-config[[:space:]]+'\{\}'" "$doc"; then
    fail "[$doc_name] uses --mcp-config '{}' (fails Claude MCP schema validation; use '{\"mcpServers\":{}}')"
  else
    pass "[$doc_name] does not use the schema-invalid --mcp-config '{}' form"
  fi
  if grep -qF "{\"mcpServers\":{}}" "$doc"; then
    pass "[$doc_name] uses schema-valid --mcp-config '{\"mcpServers\":{}}'"
  else
    fail "[$doc_name] should use --mcp-config '{\"mcpServers\":{}}' (schema-valid empty form)"
  fi
done

# 7c. --tools '' must be present in canonical invocations (load-bearing:
#     prevents tool calls that would bust --max-turns 1, enforces D30).
for doc in "$HANDOFF_DOC" "$OUTSIDE_VOICE" "$HELPER"; do
  doc_name=$(basename "$doc")
  if grep -qE -- "--tools[[:space:]]+''" "$doc"; then
    pass "[$doc_name] uses --tools '' to disable built-in tools"
  else
    fail "[$doc_name] missing --tools '' (peer must not be able to fire tool calls)"
  fi
done

# 8. Helper script header surfaces the canonical pattern + both anti-patterns.
if grep -qE 'ARG_MAX|ANTI-PATTERN|anti-pattern' "$HELPER"; then
  pass "ensemble-build-peer-prompt header surfaces anti-pattern label"
else
  fail "ensemble-build-peer-prompt header should surface the anti-pattern"
fi
if grep -qE '\| timeout' "$HELPER"; then
  pass "ensemble-build-peer-prompt header documents timeout-wrapping"
else
  fail "ensemble-build-peer-prompt header should show timeout-wrapping in canonical example"
fi
if grep -qE "subscription|claude\.ai|OAuth|/login" "$HELPER"; then
  pass "ensemble-build-peer-prompt header explains subscription-auth contract"
else
  fail "ensemble-build-peer-prompt header should explain subscription-auth requirement"
fi
if grep -q -- "--bare" "$HELPER" && grep -qE "do NOT use|bypass.*OAuth|bypasses keychain|bypasses subscription" "$HELPER"; then
  pass "ensemble-build-peer-prompt header explicitly warns against --bare"
else
  fail "ensemble-build-peer-prompt header should warn against --bare and explain why"
fi

# 9. Auth preflight is documented (so users see clear errors instead of
#    every per-unit peer call failing with "Please run /login").
if grep -qE "auth status|auth preflight|loggedIn" "$HANDOFF_DOC" "$OUTSIDE_VOICE"; then
  pass "Auth preflight documented in reference docs"
else
  fail "Auth preflight should be documented (claude auth status check before first peer call)"
fi

# === Verify-peer-evidence gate (PR #14: fail-closed peer enforcement) ===

VERIFY_HELPER="${REPO_ROOT}/bin/ensemble-verify-peer-evidence"

# 10. The verify helper exists and is executable.
if [ -x "$VERIFY_HELPER" ]; then
  pass "bin/ensemble-verify-peer-evidence exists and is executable"
else
  fail "bin/ensemble-verify-peer-evidence must exist and be executable"
fi

# 11. peer-skipped trailer schema documented in build-handoff with the
#     full enum (no skipping the documentation).
for reason in \
  "PEER_AVAILABLE=false" \
  "--no-peer-per-unit-flag" \
  "peer-subprocess-failed:" \
  "cap-exhausted-with-applied-findings" \
  "recursion-guard-active"; do
  if grep -qF -- "$reason" "$HANDOFF_DOC"; then
    pass "build-handoff.md documents peer-skipped reason: $reason"
  else
    fail "build-handoff.md should document peer-skipped reason: $reason"
  fi
done

# 12. The "anything else is a contract violation" rule is explicit so future
#     readers don't add weak skip reasons (the field-observed failure: agents
#     wrote 'Peer review approved' without invoking the peer).
if grep -qE "contract violation|forgot|compacted|I assumed" "$HANDOFF_DOC"; then
  pass "build-handoff.md explicitly forbids forgot/compacted/assumed-OK skips"
else
  fail "build-handoff.md should explicitly forbid weak skip reasons"
fi

# 13. Destructive/gated rule: peer-skipped is NOT enough for those units.
if grep -qE "[Dd]estructive.*cannot use.*peer-skipped|gated.*cannot use.*peer-skipped|require an actual peer pass|--require-peer-resolution" "$HANDOFF_DOC"; then
  pass "build-handoff.md states destructive/gated units cannot use peer-skipped"
else
  fail "build-handoff.md should state that destructive/gated units cannot use peer-skipped"
fi

# 14. en-build SKILL.md has the verify-and-commit gate at step 9k.
if grep -qE "[Vv]erify-and-commit|verify-peer-evidence" "$SKILL"; then
  pass "en-build SKILL.md has verify-and-commit gate"
else
  fail "en-build SKILL.md should have a verify-and-commit gate at step 9k"
fi

# 15. en-build SKILL.md has plugin-install preflight (fail-fast on missing references).
if grep -qE "[Pp]lugin-install preflight|fail-fast|missing.*reference" "$SKILL"; then
  pass "en-build SKILL.md has plugin-install preflight"
else
  fail "en-build SKILL.md should fail-fast when reference files are missing"
fi

# 16. en-build SKILL.md has end-of-build peer-evidence audit.
if grep -qE "[Pp]eer-evidence audit|end-of-build.*invariant|invariant.*peer" "$SKILL"; then
  pass "en-build SKILL.md has end-of-build peer-evidence audit"
else
  fail "en-build SKILL.md should have an end-of-build peer-evidence audit"
fi

# 17. The skill's "What this skill never does" lists the new fail-closed contracts.
if grep -qE "[Nn]ever commits a unit without peer evidence|[Nn]ever declares a build.*complete.*missing peer" "$SKILL"; then
  pass "en-build SKILL.md 'never does' lists peer-evidence enforcement"
else
  fail "en-build SKILL.md 'never does' should list the peer-evidence enforcement"
fi

# 18. Reference list mentions the verify helper.
if grep -qF "bin/ensemble-verify-peer-evidence" "$SKILL"; then
  pass "en-build SKILL.md reference list mentions verify-peer-evidence helper"
else
  fail "en-build SKILL.md reference list should mention bin/ensemble-verify-peer-evidence"
fi

# === peer-verdict: trailer (P1 from PR #14 review) ===
# Zero-finding peer approve was rejected as missing-evidence because the
# old contract only accepted peer-resolution: per finding. New contract:
# peer-verdict: trailer is always emitted when peer ran, separate from
# per-finding peer-resolution: trailers.

# 19. peer-verdict: trailer documented in both reference docs and SKILL.md.
for doc in "$HANDOFF_DOC" "${REPO_ROOT}/references/build-orchestration.md" "$SKILL"; do
  doc_name=$(basename "$doc")
  if grep -qF "peer-verdict:" "$doc"; then
    pass "[$doc_name] documents peer-verdict: trailer"
  else
    fail "[$doc_name] should document peer-verdict: trailer"
  fi
done

# 20. peer-verdict: schema fields documented (in build-handoff.md, the canonical schema home).
for field in "verdict" "peer_mode" "iteration" "findings_count"; do
  if grep -qE "peer-verdict.*$field|\`$field\`.*\\(approve|$field\`.*peer-verdict" "$HANDOFF_DOC" \
     || grep -qE "$field.*\(approve\|revise\|reject\)|peer-verdict.*$field" "$HANDOFF_DOC" \
     || grep -qF "\"$field\"" "$HANDOFF_DOC"; then
    pass "build-handoff.md documents peer-verdict field: $field"
  else
    fail "build-handoff.md missing peer-verdict field documentation: $field"
  fi
done

# 21. The "always emitted when peer ran" rule is explicit (so future
#     contributors don't drop the peer-verdict trailer for zero-finding cases).
if grep -qE "always emitted|written WHENEVER|exactly one per peer pass|whenever the peer actually ran" "$HANDOFF_DOC" "$SKILL"; then
  pass "peer-verdict 'always emitted when peer ran' rule documented"
else
  fail "peer-verdict trailer should be documented as always emitted when peer ran"
fi

# 22. Zero-finding example present in build-handoff.md (shows the schema works
#     for clean approves with no findings).
if grep -qE 'findings_count":0' "$HANDOFF_DOC" \
   || grep -qE '"findings_count":[[:space:]]*0' "$HANDOFF_DOC"; then
  pass "build-handoff.md includes a zero-finding peer-verdict example"
else
  fail "build-handoff.md should include a zero-finding peer-verdict example (the field-bug case)"
fi

# 23. peer-verdict.findings_count cross-check rule documented (the value MUST
#     match the peer-resolution count).
if grep -qE "MUST match|must match|cross-check.*peer-resolution|findings_count.*peer-resolution" "$HANDOFF_DOC"; then
  pass "build-handoff.md documents findings_count cross-check rule"
else
  fail "build-handoff.md should document findings_count must match peer-resolution count"
fi

# === Auto-skip enum entries (P2 from PR #14 review) ===
# The skill's Cross-review section listed two auto-skip cases (small diff,
# lightweight depth) that didn't have entries in the peer-skipped enum, so
# agents following auto-skip rules would produce no valid trailer and fail
# the verify gate. New enum entries close the loophole.

# 24. New auto-skip enum entries documented in build-handoff.md.
for reason in "auto-skip:diff-below-threshold" "auto-skip:lightweight-depth"; do
  if grep -qF -- "$reason" "$HANDOFF_DOC"; then
    pass "build-handoff.md documents new peer-skipped reason: $reason"
  else
    fail "build-handoff.md should document peer-skipped reason: $reason"
  fi
done

# 25. en-build SKILL.md's auto-skip section now maps each auto-skip case to
#     a documented peer-skipped enum value (no orphan auto-skip rules).
for reason in \
  "PEER_AVAILABLE=false" \
  "recursion-guard-active" \
  "--no-peer-per-unit-flag" \
  "auto-skip:diff-below-threshold" \
  "auto-skip:lightweight-depth"; do
  if grep -qF -- "$reason" "$SKILL"; then
    pass "en-build SKILL.md auto-skip section maps to peer-skipped: $reason"
  else
    fail "en-build SKILL.md auto-skip section should reference peer-skipped value: $reason"
  fi
done

# 26. Auto-skip is explicitly forbidden on destructive/gated units (so they
#     can't ship without an actual peer pass via the auto-skip loophole).
if grep -qiE "auto-skip.*not permitted|auto-skip.*not allowed" "$SKILL"; then
  pass "en-build SKILL.md forbids auto-skip on destructive/gated units"
else
  fail "en-build SKILL.md should forbid auto-skip on destructive/gated units"
fi

# === Portable timeout resolution (PR #N — macOS doesn't ship GNU timeout) ===
# Field-observed: bare `timeout 600 claude ...` failed on macOS-without-coreutils
# because `timeout` is GNU coreutils, available as `gtimeout` via brew. The
# agent's workaround (drop the wrapper) silently re-enabled the silent-hang
# failure mode that prompted PR #9. Canonical pattern now resolves with
# `command -v timeout || command -v gtimeout` and fails fast on missing.

# 27. All three documented surfaces have the resolution pattern.
EN_SETUP="${REPO_ROOT}/skills/en-setup/SKILL.md"
for doc in "$HANDOFF_DOC" "$OUTSIDE_VOICE" "$HELPER"; do
  doc_name=$(basename "$doc")
  if grep -qE "command -v timeout \|\| command -v gtimeout" "$doc"; then
    pass "[$doc_name] documents timeout-binary resolution pattern"
  else
    fail "[$doc_name] should use 'command -v timeout || command -v gtimeout' resolution"
  fi
done

# 28. All three surfaces document `brew install coreutils` as the macOS remedy.
for doc in "$HANDOFF_DOC" "$OUTSIDE_VOICE" "$HELPER"; do
  doc_name=$(basename "$doc")
  if grep -qF "brew install coreutils" "$doc"; then
    pass "[$doc_name] documents 'brew install coreutils' as macOS remedy"
  else
    fail "[$doc_name] should document brew install coreutils for macOS"
  fi
done

# 29. All three surfaces fail fast on missing timeout (mention exit 1 / ERROR:).
for doc in "$HANDOFF_DOC" "$OUTSIDE_VOICE" "$HELPER"; do
  doc_name=$(basename "$doc")
  if grep -qE "(exit 1|ERROR:.*timeout)" "$doc"; then
    pass "[$doc_name] documents fail-fast on missing timeout binary"
  else
    fail "[$doc_name] should fail fast (exit 1) on missing timeout binary"
  fi
done

# 30. outside-voice.md anti-pattern block lists the new wrong forms.
if grep -qF "timeout 600 claude" "$OUTSIDE_VOICE"; then
  pass "outside-voice.md anti-pattern flags bare 'timeout 600 claude'"
else
  fail "outside-voice.md anti-pattern block should flag bare 'timeout 600 claude' (fails on macOS without coreutils)"
fi

if grep -qE "dropping the timeout|drop.*timeout.*regress|timeout silently|silently.*re-enables.*PR #9" "$OUTSIDE_VOICE"; then
  pass "outside-voice.md anti-pattern flags dropped-timeout"
else
  fail "outside-voice.md anti-pattern block should flag dropped-timeout (silently regresses hang protection)"
fi

# 31. /en-setup checks for timeout binary in BOTH State-2 verification AND
#     State-3 diagnostic, but does NOT block install on missing.
if grep -qE "command -v timeout \|\| command -v gtimeout" "$EN_SETUP"; then
  pass "en-setup SKILL.md checks for timeout/gtimeout"
else
  fail "en-setup SKILL.md should check for timeout/gtimeout (advisory)"
fi
if grep -qF "brew install coreutils" "$EN_SETUP"; then
  pass "en-setup SKILL.md documents 'brew install coreutils' repair"
else
  fail "en-setup SKILL.md should mention brew install coreutils as the timeout repair"
fi

# 31a. The flow chart in build-handoff.md must not show the OLD bare
#      `timeout "${peer_timeout_seconds:-600}"` form (regression from
#      PR #16 review). Bare timeout in load-bearing diagrams misleads
#      agents into copying the stale form and either failing on macOS
#      or dropping the wrapper.
#      Allow it ONLY inside the explicit anti-pattern code block in
#      outside-voice.md — that's where it's labeled as wrong.
for doc in "$HANDOFF_DOC" "$HELPER"; do
  doc_name=$(basename "$doc")
  # Find any `timeout "${peer_timeout_seconds...` not preceded by ENSEMBLE_TIMEOUT_BIN=
  # context. Easy heuristic: count lines that contain bare-timeout AND don't have ENSEMBLE_TIMEOUT_BIN nearby.
  bare_count=$(grep -nE '(\| |  +)timeout "\$\{peer_timeout' "$doc" | grep -v 'ENSEMBLE_TIMEOUT_BIN' | wc -l | tr -d ' ')
  if [ "$bare_count" = "0" ]; then
    pass "[$doc_name] flow chart / examples do not show bare timeout form"
  else
    fail "[$doc_name] still shows bare 'timeout \"\${peer_timeout_seconds...' (use \$ENSEMBLE_TIMEOUT_BIN instead)"
  fi
done

# === Tightened gated:true criteria (PR #N) ===
# Field-observed: a wide-surface UI/terminology rename (no production state
# change) was marked gated:true by /en-plan, forcing a y/skip/abort prompt
# for what was operationally inert work. Cause: criteria included a vague
# "any non-destructive unit that needs explicit confirmation" catch-all,
# which the planning LLM read too liberally. New bar: gated is for
# production-state-changing units only.

PLAN_TEMPLATE="${REPO_ROOT}/references/templates/plan-template.md"

# A. The vague "any non-destructive unit" catch-all is GONE.
if grep -qE "any non-destructive unit that needs explicit confirmation" "$PLAN_TEMPLATE"; then
  fail "plan-template.md still has the vague 'any non-destructive unit' catch-all (it was the root cause of over-gating)"
else
  pass "plan-template.md no longer uses the vague non-destructive catch-all"
fi

# B. The five concrete qualifying cases are documented (each must appear
#    in the gated-criteria section).
for keyword in \
  "Customer-facing feature flag flip" \
  "Production data backfill" \
  "Third-party API with real side effects" \
  "API contract break" \
  "Production config change"; do
  if grep -qF "$keyword" "$PLAN_TEMPLATE"; then
    pass "plan-template.md gated criteria documents: $keyword"
  else
    fail "plan-template.md gated criteria missing: $keyword"
  fi
done

# C. Explicit drop-list is documented (these should NOT trigger gated).
for keyword in \
  "internal renames" \
  "UI text" \
  "Test additions" \
  "still off"; do
  if grep -qiF "$keyword" "$PLAN_TEMPLATE"; then
    pass "plan-template.md gated criteria documents drop-list item: $keyword"
  else
    fail "plan-template.md gated criteria should explicitly exclude: $keyword"
  fi
done

# D. The over-gating rationale is explicit.
if grep -qE "(over-gating|trains users to autopilot|erodes.*signal)" "$PLAN_TEMPLATE"; then
  pass "plan-template.md explains why over-gating is harmful"
else
  fail "plan-template.md should explain the cost of over-gating (signal erosion)"
fi

# E. gated and risk: are documented as orthogonal.
if grep -qE "(independent of risk|orthogonal to risk:|risk: low.*gated: true|low-risk.*gated: true)" "$PLAN_TEMPLATE"; then
  pass "plan-template.md documents gated as orthogonal to risk"
else
  fail "plan-template.md should clarify gated and risk are independent"
fi

# F. Default-false instruction is explicit.
if grep -qE "[Dd]efault.*false|Default to .false." "$PLAN_TEMPLATE"; then
  pass "plan-template.md instructs 'default to false'"
else
  fail "plan-template.md should say 'default to false' for gated"
fi

# G. The Outside Voice peer prompt challenges over-gating.
if grep -qiE "challenge gated|flag.*gated:true.*just an internal|over-gating" "$OUTSIDE_VOICE"; then
  pass "outside-voice.md peer prompt instructs the peer to challenge over-gating"
else
  fail "outside-voice.md should instruct the peer to challenge over-gating in plan reviews"
fi

# H. Peer prompt also flags MISSING gated on production-state-changing units
#    (the symmetric case — under-gating is also a real risk).
if grep -qiE "missing gated|under-gating|gated:false on units that DO change production" "$OUTSIDE_VOICE"; then
  pass "outside-voice.md peer prompt flags under-gating (missing gated:true on production-state changes)"
else
  fail "outside-voice.md should also flag under-gating, not just over-gating"
fi

# I. The helper script's PLAN_REVIEW_DIMENSIONS substitution carries the
#    same instruction (so peer calls dispatched via the helper get the
#    challenge-over-gating language).
if grep -qiE "(challenge gated|flag.*gated:true.*internal/UI|over-gating)" "$HELPER"; then
  pass "ensemble-build-peer-prompt PLAN_REVIEW_DIMENSIONS challenges over-gating"
else
  fail "ensemble-build-peer-prompt PLAN_REVIEW_DIMENSIONS should challenge over-gating"
fi

# J. en-plan SKILL.md's per-unit gated guidance matches the new bar.
EN_PLAN_SKILL="${REPO_ROOT}/skills/en-plan/SKILL.md"
if grep -qE "production user state|production-state-changing|production data backfill" "$EN_PLAN_SKILL"; then
  pass "en-plan SKILL.md gated guidance uses the production-state criterion"
else
  fail "en-plan SKILL.md gated guidance should reference production-state criterion"
fi
if grep -qE "any non-destructive unit that needs explicit confirmation" "$EN_PLAN_SKILL"; then
  fail "en-plan SKILL.md still has the vague non-destructive catch-all"
else
  pass "en-plan SKILL.md no longer has the vague non-destructive catch-all"
fi

# K. bin/ensemble-lint's gated suggestion uses the new criteria, not the
#    old "admin endpoints / flag flips / rate-limited APIs" phrasing
#    (PR #17 review found the lint script was still recommending the old
#    bar on missing-Gated violations, undoing the tightening).
LINT_SCRIPT="${REPO_ROOT}/bin/ensemble-lint"
# Old phrasing that must NOT appear in the suggestion text.
if grep -qE 'admin endpoints[[:space:]]*/[[:space:]]*flag flips[[:space:]]*/[[:space:]]*rate-limited APIs' "$LINT_SCRIPT"; then
  fail "bin/ensemble-lint still uses the old gated suggestion (admin endpoints / flag flips / rate-limited APIs) — that contradicts the tightened criteria"
else
  pass "bin/ensemble-lint no longer uses the old gated suggestion language"
fi
# New phrasing must reference the production-state criterion AND point at the canonical doc.
if grep -qF "production user state or external system state" "$LINT_SCRIPT"; then
  pass "bin/ensemble-lint suggestion references the production-state criterion"
else
  fail "bin/ensemble-lint gated suggestion should reference 'production user state or external system state'"
fi
if grep -qF "references/templates/plan-template.md" "$LINT_SCRIPT"; then
  pass "bin/ensemble-lint suggestion points at plan-template.md for full criteria"
else
  fail "bin/ensemble-lint gated suggestion should point at references/templates/plan-template.md"
fi

# 32. en-setup advisory is non-blocking (per the resolved open question).
if grep -qiE "do NOT block install|advisory|surface 🟡" "$EN_SETUP" && grep -qE "🟡.*timeout|timeout.*🟡|🟡 No .timeout" "$EN_SETUP"; then
  pass "en-setup SKILL.md treats timeout-binary as advisory (not blocking)"
else
  fail "en-setup SKILL.md should mark missing-timeout as advisory (🟡), not blocking"
fi

rm -f "$TMP_MSG"
report
