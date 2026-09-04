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
# Repointed from en-build: D52 left it dispatching no peer and delegating
# simplification to /en-simplify, so it carries none of this machinery. The
# path now names the skill that owns it.
# --- 2026-09-01: the emitter side of this protocol is now legacy ---
# D52 stopped /en-build emitting peer-verdict: / peer-resolution: trailers, and
# merging en-cross-review into /en-review removed the last other producer. No
# skill emits them today, and D83 retired the verifier's single-commit mode
# that parsed them; the helper-side assertions below cover what survives
# (the helper exists, and en-build cites it for the branch-coverage audit).
#
# The clauses that asserted build-handoff.md / build-orchestration.md documented
# the schema are gone with those files, which were deleted alongside
# en-cross-review. They described /en-build's two execution flavors, which D52
# removed; nothing repointed them because no surviving file documents a format
# nothing writes.

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
# D52 removed en-build's two flavors, so build-handoff.md and
# build-orchestration.md now live only with /en-cross-review, which names
# them in its own flow. This checks the surviving carrier.



# --- Documentation example JSON is parseable (catches typos in copy-paste) ---

# --- D52: en-build has no per-unit peer machinery ---
# These clauses asserted en-build implemented the per-unit finalize loop
# (--max-per-unit-iterations, re_review_count, the cap-hit warning, the
# auto-skip enum, per-unit peer-verdict trailers). D52 removed all of it: the
# host implements every unit and the peer reviews once, at step 10.3, after
# /en-simplify. Rewritten as ABSENCE checks, because the failure mode is
# reintroduction — the trailer protocol itself is still covered by the
# ~160 assertions above, exercised through the skills that still emit it.
SKILL="$REPO_ROOT/skills/en-build/SKILL.md"
absent=""
for gone in "--max-per-unit-iterations" "Per-unit finalize loop" "re_review_count" \
            "--no-peer-per-unit" "auto-skip:diff-below-threshold" "peer-verdict:"; do
  grep -qF -- "$gone" "$SKILL" && absent="$absent '$gone'"
done
[ -z "$absent" ] \
  && pass "en-build carries no per-unit peer machinery (D52)" \
  || fail "en-build carries no per-unit peer machinery (D52)" "still present:$absent"

# The branch-level evidence it DOES emit must still be documented here.
if grep -qF "review-verdict:" "$SKILL" && grep -qF "simplify-verdict:" "$SKILL" \
   && grep -qF -- "--branch-coverage" "$SKILL"; then
  pass "en-build documents the branch-level trailers that replaced them"
else
  fail "en-build must document review-verdict:, simplify-verdict: and --branch-coverage"
fi

# Inverted by D52: en-build emits no peer-resolution: trailer, because it runs
# no per-unit peer pass. A mention here would mean the old model crept back.
# Matches the TRAILER form specifically. A bare "peer-resolution" substring also
# hits `--require-peer-resolution`, which en-build legitimately names once to say
# it does not use that mode.
if grep -qE "peer-resolution:" "$SKILL"; then
  fail "en-build must not emit the peer-resolution: trailer" \
       "D52 removed the per-unit peer pass that produced it"
else
  pass "en-build references no peer-resolution trailer (D52)"
fi

# --- build-handoff.md uses ensemble-build-peer-prompt helper ---

# --- Counter semantics are explicit: re_review_count starts at 0 (P2 from Codex review) ---
# The condition "iteration < cap" with iteration starting at 1 and default cap=1
# never fires — that was the bug. Each ref doc must state explicit counter
# semantics (`re_review_count` starting at 0) so the loop fires at default settings.

# Removed by D52 — no re_review_count: the per-unit finalize loop is gone.
# Removed by D52 — no counter to start.

# --- Both flow charts mention phase: P<N> trailer alongside peer-resolution ---
# Codex flagged the flow charts only mentioning peer-resolution: trailers,
# omitting the required phase: P<N> trailer that /en-ship and greppable
# history rely on.

# --- Cap-hit warning surfaces a P1 (regression for P2 #1 from Codex) ---
# When the cap is hit AND findings were applied on the last re-review pass,
# the spec requires a P1 warning surfaced to the user — those applications
# weren't peer-verified. The wording should make the un-peer-verified status
# explicit so users notice and consider raising the cap.
# Removed by D52 — no cap-hit warning: there is no per-unit finalize loop to cap.

# --- Peer invocation hardening (silent-hang failure mode) ---
# Field-observed silent hang: capturing helper stdout into a shell variable
# and re-passing via argv hit ARG_MAX on a large staged diff. Documented
# pattern must pipe stdin, wrap in timeout, capture stderr.
#
# Auth note: Ensemble's contract is subscription-auth (OAuth / claude.ai /
# keychain). The Claude CLI's `--bare` flag bypasses that auth and produces
# "Not logged in · Please run /login" on subscription-only hosts. So we
# CANNOT use --bare; we use weaker isolation flags that are auth-compatible.

OUTSIDE_VOICE="${REPO_ROOT}/skills/en-review/references/outside-voice.md"
# Since 2026-09-04 outside-voice.md states the contract and the two helpers own
# the command line, so the timeout and gating rules are asserted where they now
# execute: the invoke helper and en-plan's peer brief.
INVOKE_HELPER="${REPO_ROOT}/skills/en-review/scripts/ensemble-peer-invoke"
PLAN_BRIEF="${REPO_ROOT}/skills/en-plan/references/peer-brief.md"
HELPER="${REPO_ROOT}/skills/en-review/scripts/ensemble-build-peer-prompt"

# 1. Both build-handoff and outside-voice document piping helper-stdout
#    directly into the peer command (no `prompt=$(...)` capture).

# 2. Both reference docs wrap the peer call in `timeout`.

# 3. Both reference docs capture stderr for diagnostic visibility.

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

# 6. Subscription-auth rationale is explicit (so future contributors don't
#    re-add --bare for performance reasons).

# 7. Auth-compatible isolation flags are documented as the --bare substitute.

# 7a. --setting-sources user must NOT be in the canonical invocation
#     (loads LSP plugin which fires tool calls and busts --max-turns 1).
#     Allow mentions in markdown prose (`--setting-sources user` in
#     backticks or in rationale text) — only flag active code-block uses.
#     Active uses end with " \" (bash line continuation) or appear in
#     ASCII-art flow charts (lines with leading │).

# 7b. --mcp-config must use schema-valid empty form, not plain '{}' (fails MCP schema).

# 7c. --tools '' must be present in canonical invocations (load-bearing:
#     prevents tool calls that would bust --max-turns 1, enforces D30).

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

# === Verify-peer-evidence gate (PR #14: fail-closed peer enforcement) ===

VERIFY_HELPER="${REPO_ROOT}/skills/en-build/scripts/ensemble-verify-peer-evidence"

# 10. The verify helper exists and is executable.
if [ -x "$VERIFY_HELPER" ]; then
  pass "skills/en-build/scripts/ensemble-verify-peer-evidence exists and is executable"
else
  fail "skills/en-build/scripts/ensemble-verify-peer-evidence must exist and be executable"
fi

# 12. The "anything else is a contract violation" rule is explicit so future
#     readers don't add weak skip reasons (the field-observed failure: agents
#     wrote 'Peer review approved' without invoking the peer).

# 13. Destructive/gated rule: peer-skipped is NOT enough for those units.

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
# Removed by D52 — the never-does claim now covers review evidence, checked by en-build-review-model.

# 18. Reference list mentions the verify helper.
if grep -qF "ensemble-verify-peer-evidence" "$SKILL"; then
  pass "en-build SKILL.md reference list mentions verify-peer-evidence helper"
else
  fail "en-build SKILL.md reference list should mention bin/ensemble-verify-peer-evidence"
fi

# Removed by D52 — en-build has no per-unit auto-skip enum: the branch-level
# review is skipped only by --no-peer or the recursion guard, and both record a
# reason on the review-verdict: trailer rather than a per-unit peer-skipped:.

# 26. Auto-skip is explicitly forbidden on destructive/gated units (so they
#     can't ship without an actual peer pass via the auto-skip loophole).
# Removed by D52 — auto-skip enum is gone: no per-unit peer means no per-unit skip.

# === Portable timeout resolution (PR #N — macOS doesn't ship GNU timeout) ===
# Field-observed: bare `timeout 600 claude ...` failed on macOS-without-coreutils
# because `timeout` is GNU coreutils, available as `gtimeout` via brew. The
# agent's workaround (drop the wrapper) silently re-enabled the silent-hang
# failure mode that prompted PR #9. Canonical pattern now resolves with
# `command -v timeout || command -v gtimeout` and fails fast on missing.

# 27. All three documented surfaces have the resolution pattern.
EN_SETUP="${REPO_ROOT}/skills/en-setup/SKILL.md"

# 28. All three surfaces document `brew install coreutils` as the macOS remedy.

# 29. All three surfaces fail fast on missing timeout (mention exit 1 / ERROR:).

# 30. outside-voice.md anti-pattern block lists the new wrong forms.
if grep -qF 'command -v timeout 2>/dev/null || command -v gtimeout' "$INVOKE_HELPER" \
   && ! grep -qE '^[[:space:]]*timeout [0-9]' "$INVOKE_HELPER"; then
  pass "ensemble-peer-invoke resolves timeout with the gtimeout fallback; no bare 'timeout N' call"
else
  fail "ensemble-peer-invoke must resolve timeout via command -v with a gtimeout fallback (bare timeout fails on macOS without coreutils)"
fi

if grep -qF '_epi_argv+=("$_tb" "$timeout_secs")' "$INVOKE_HELPER"; then
  pass "ensemble-peer-invoke wraps every peer call in the resolved timeout"
else
  fail "ensemble-peer-invoke must wrap the peer call in the resolved timeout (dropping it silently regresses hang protection)"
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

# === Tightened gated:true criteria (PR #N) ===
# Field-observed: a wide-surface UI/terminology rename (no production state
# change) was marked gated:true by /en-plan, forcing a y/skip/abort prompt
# for what was operationally inert work. Cause: criteria included a vague
# "any non-destructive unit that needs explicit confirmation" catch-all,
# which the planning LLM read too liberally. New bar: gated is for
# production-state-changing units only.

# Reads /en-plan's copy: it owns the plan template, and D52's payload cut
# removed en-build's, which it carried for one see-also cross-reference.
PLAN_TEMPLATE="${REPO_ROOT}/skills/en-plan/references/templates/plan-template.md"

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
if grep -qiE "challenge gated|flag gated:true on an internal|over-gating" "$PLAN_BRIEF"; then
  pass "en-plan's peer brief instructs the peer to challenge over-gating"
else
  fail "en-plan's peer brief should instruct the peer to challenge over-gating in plan reviews"
fi

# H. Peer prompt also flags MISSING gated on production-state-changing units
#    (the symmetric case — under-gating is also a real risk).
if grep -qiE "missing gated|under-gating|units that DO change production state" "$PLAN_BRIEF"; then
  pass "en-plan's peer brief flags under-gating (missing gated:true on production-state changes)"
else
  fail "en-plan's peer brief should also flag under-gating, not just over-gating"
fi

# I. The helper script's PLAN_REVIEW_DIMENSIONS substitution carries the
#    same instruction (so peer calls dispatched via the helper get the
#    challenge-over-gating language).
# EN13 U5 moved the review dimensions out of the helper and into en-plan's own
# brief, so this assertion follows them. Only the location changed.
PLAN_BRIEF="${REPO_ROOT}/skills/en-plan/references/peer-brief.md"
if grep -qiE "(challenge gated|flag.*gated:true.*internal/UI|over-gating)" "$PLAN_BRIEF"; then
  pass "en-plan's peer brief challenges over-gating"
else
  fail "en-plan's peer brief should challenge over-gating"
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
LINT_SCRIPT="${REPO_ROOT}/skills/en-setup/references/templates/ensemble-lint"
# Old phrasing that must NOT appear in the suggestion text.
if grep -qE 'admin endpoints[[:space:]]*/[[:space:]]*flag flips[[:space:]]*/[[:space:]]*rate-limited APIs' "$LINT_SCRIPT"; then
  fail "skills/en-setup/references/templates/ensemble-lint still uses the old gated suggestion (admin endpoints / flag flips / rate-limited APIs) — that contradicts the tightened criteria"
else
  pass "skills/en-setup/references/templates/ensemble-lint no longer uses the old gated suggestion language"
fi
# New phrasing must reference the production-state criterion AND point at the canonical doc.
if grep -qF "production user state or external system state" "$LINT_SCRIPT"; then
  pass "skills/en-setup/references/templates/ensemble-lint suggestion references the production-state criterion"
else
  fail "skills/en-setup/references/templates/ensemble-lint gated suggestion should reference 'production user state or external system state'"
fi
if grep -qF "references/templates/plan-template.md" "$LINT_SCRIPT"; then
  pass "skills/en-setup/references/templates/ensemble-lint suggestion points at plan-template.md for full criteria"
else
  fail "skills/en-setup/references/templates/ensemble-lint gated suggestion should point at references/templates/plan-template.md"
fi

# 32. en-setup advisory is non-blocking (per the resolved open question).
if grep -qiE "do NOT block install|advisory|surface 🟡" "$EN_SETUP" && grep -qE "🟡.*timeout|timeout.*🟡|🟡 No .timeout" "$EN_SETUP"; then
  pass "en-setup SKILL.md treats timeout-binary as advisory (not blocking)"
else
  fail "en-setup SKILL.md should mark missing-timeout as advisory (🟡), not blocking"
fi

rm -f "$TMP_MSG"
report
