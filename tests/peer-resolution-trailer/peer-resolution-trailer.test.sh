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

rm -f "$TMP_MSG"
report
