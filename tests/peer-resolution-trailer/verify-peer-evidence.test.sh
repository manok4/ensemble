#!/usr/bin/env bash
# Tests for bin/ensemble-verify-peer-evidence.
#
# This helper is the mechanical gate that /en-build calls to verify peer
# evidence on each unit commit BEFORE advancing. Catches the failure mode
# observed in the field: agent skipped peer review and wrote "Peer review
# approved" as plain text without invoking the peer subprocess.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="ensemble-verify-peer-evidence"

VERIFY="$REPO_ROOT/bin/ensemble-verify-peer-evidence"

# Setup: a temp git repo with crafted commits we can inspect.
TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT

cd "$TMP"
git init --quiet
git config user.email "test@test.local"
git config user.name "Test"
git config commit.gpgsign false 2>/dev/null || true
echo "init" > README.md
git add README.md
git commit --quiet -m "init"

make_commit() {
  local message_file="$1"
  echo "change-$RANDOM" >> file.txt
  git add file.txt
  git commit --quiet -F "$message_file"
  git rev-parse HEAD
}

# === 1. Commit with valid peer-resolution trailers — verdict: ok ===
cat > /tmp/msg.txt <<'EOF'
feat: U3

Body.

phase: P2
peer-resolution: {"finding_id":"u3-1-1","u_id":"U3","iteration":1,"severity":"P1","status":"applied","title":"Race in refresh path"}
peer-resolution: {"finding_id":"u3-1-2","u_id":"U3","iteration":1,"severity":"P2","status":"deferred","rationale":"low conf","title":"Edge case"}
EOF
sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" "$sha" --json)
rc=$?
assert_eq "0" "$rc" "valid peer-resolution → exit 0"
verdict=$(echo "$out" | jq -r .verdict)
assert_eq "ok" "$verdict" "valid peer-resolution verdict=ok"
res=$(echo "$out" | jq -r .peer_resolutions)
assert_eq "2" "$res" "valid peer-resolution count=2"
uid=$(echo "$out" | jq -r .u_id)
assert_eq "U3" "$uid" "valid peer-resolution extracts u_id"

# === 2. Commit with no trailers — verdict: missing-evidence (the field bug) ===
cat > /tmp/msg.txt <<'EOF'
feat: U10 (skipped peer review silently)

Body. Peer review approved.
EOF
sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" "$sha" --json)
rc=$?
assert_eq "1" "$rc" "no trailers → exit 1 (refuse to advance)"
verdict=$(echo "$out" | jq -r .verdict)
assert_eq "missing-evidence" "$verdict" "no trailers verdict=missing-evidence"

# === 3. Commit with peer-skipped trailer (valid reason) — verdict: ok ===
cat > /tmp/msg.txt <<'EOF'
feat: U5 (peer subprocess failed)

Body.

phase: P2
peer-skipped: peer-subprocess-failed:timeout after 600s
EOF
sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" "$sha" --json)
rc=$?
assert_eq "0" "$rc" "valid peer-skipped → exit 0"
verdict=$(echo "$out" | jq -r .verdict)
assert_eq "ok" "$verdict" "valid peer-skipped verdict=ok"
reasons=$(echo "$out" | jq -r '.skipped_reasons | join(",")')
assert_eq "peer-subprocess-failed" "$reasons" "peer-skipped reason normalized"

# === 4. Commit with peer-skipped invalid reason — verdict: malformed ===
cat > /tmp/msg.txt <<'EOF'
feat: U6 (skipped with bogus reason)

Body.

peer-skipped: I-forgot
EOF
sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" "$sha" --json)
rc=$?
assert_eq "1" "$rc" "invalid peer-skipped reason → exit 1"
verdict=$(echo "$out" | jq -r .verdict)
assert_eq "malformed" "$verdict" "invalid peer-skipped verdict=malformed"

# === 5. --require-peer-resolution: peer-skipped is NOT enough ===
cat > /tmp/msg.txt <<'EOF'
feat: U8 (destructive unit; peer-skipped not allowed)

Body.

peer-skipped: PEER_AVAILABLE=false
EOF
sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" "$sha" --require-peer-resolution --json)
rc=$?
assert_eq "1" "$rc" "--require-peer-resolution + only peer-skipped → exit 1"
verdict=$(echo "$out" | jq -r .verdict)
assert_eq "missing-resolution" "$verdict" "--require-peer-resolution verdict=missing-resolution"

# === 6. --require-peer-resolution: peer-resolution present → ok ===
cat > /tmp/msg.txt <<'EOF'
feat: U8 (destructive; peer review present)

Body.

peer-resolution: {"finding_id":"u8-1-1","u_id":"U8","iteration":1,"severity":"P0","status":"applied","title":"Critical issue"}
EOF
sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" "$sha" --require-peer-resolution --json)
rc=$?
assert_eq "0" "$rc" "--require-peer-resolution + peer-resolution present → exit 0"

# === 7. peer-resolution malformed JSON — verdict: malformed ===
cat > /tmp/msg.txt <<'EOF'
feat: U7 (malformed peer-resolution)

Body.

peer-resolution: not-valid-json
EOF
sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" "$sha" --json)
rc=$?
assert_eq "1" "$rc" "malformed peer-resolution JSON → exit 1"
verdict=$(echo "$out" | jq -r .verdict)
assert_eq "malformed" "$verdict" "malformed JSON verdict=malformed"

# === 8. peer-resolution missing required field — verdict: malformed ===
cat > /tmp/msg.txt <<'EOF'
feat: U7 (missing field)

Body.

peer-resolution: {"finding_id":"u7-1-1","severity":"P1","status":"applied","title":"x"}
EOF
sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" "$sha" --json)
rc=$?
assert_eq "1" "$rc" "peer-resolution missing required field → exit 1"
verdict=$(echo "$out" | jq -r .verdict)
assert_eq "malformed" "$verdict" "missing field verdict=malformed"

# === 9. Both peer-resolution and peer-skipped present — peer-resolution wins ===
cat > /tmp/msg.txt <<'EOF'
feat: U9 (mixed; resolution wins)

Body.

peer-resolution: {"finding_id":"u9-1-1","u_id":"U9","iteration":1,"severity":"P2","status":"applied","title":"x"}
peer-skipped: cap-exhausted-with-applied-findings
EOF
sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" "$sha" --json)
rc=$?
assert_eq "0" "$rc" "peer-resolution + peer-skipped → exit 0 (resolution counts)"

# === 10. Default ref is HEAD ===
cd "$TMP"
out=$("$VERIFY" --json)
rc=$?
assert_eq "0" "$rc" "default ref=HEAD on the just-made commit"

# === 11. Invalid commit ref → exit 2 ===
out=$("$VERIFY" "definitely-not-a-real-sha-xyz" 2>&1)
rc=$?
assert_eq "2" "$rc" "invalid ref → exit 2"

# === 12. All five documented peer-skipped reasons accepted ===
for reason in \
  "PEER_AVAILABLE=false" \
  "--no-peer-per-unit-flag" \
  "peer-subprocess-failed:timeout" \
  "cap-exhausted-with-applied-findings" \
  "recursion-guard-active"; do
  cat > /tmp/msg.txt <<EOF
feat: enum check

Body.

peer-skipped: $reason
EOF
  sha=$(make_commit /tmp/msg.txt)
  rc=0
  "$VERIFY" "$sha" --json >/dev/null 2>&1 || rc=$?
  assert_eq "0" "$rc" "accepted reason: $reason"
done

# === 13. Human-readable output (no --json) ===
out=$("$VERIFY" "$sha")
if echo "$out" | grep -q "verdict: ok"; then
  pass "human-readable output includes verdict"
else
  fail "human-readable output should include verdict line" "$out"
fi
if echo "$out" | grep -q "peer-skipped trailers:"; then
  pass "human-readable output includes peer-skipped count"
else
  fail "human-readable output should include peer-skipped count line"
fi
if echo "$out" | grep -q "peer-verdict trailers:"; then
  pass "human-readable output includes peer-verdict count"
else
  fail "human-readable output should include peer-verdict count line"
fi

# === 14. Zero-finding peer approve — the field-observed bug from PR #14 review ===
# Peer ran, found nothing, approved. Documented commit format emitted only
# peer-resolution: per finding, so a clean approve had no trailers and the
# verifier rejected it. Fix: peer-verdict trailer is always emitted when peer
# ran (regardless of finding count), and is sufficient evidence.
cat > /tmp/msg.txt <<'EOF'
feat: U2 (clean approve, zero findings)

Body.

phase: P2
peer-verdict: {"verdict":"approve","peer_mode":"cross-agent","iteration":1,"findings_count":0,"summary":"Plan is well-scoped; no findings."}
EOF
sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" "$sha" --json)
rc=$?
assert_eq "0" "$rc" "approve with 0 findings + peer-verdict → exit 0"
verdict=$(echo "$out" | jq -r .verdict)
assert_eq "ok" "$verdict" "approve+0-findings verdict=ok (no longer rejected)"
pv=$(echo "$out" | jq -r .peer_verdict)
assert_eq "approve" "$pv" "peer_verdict surfaced in JSON output"
vc=$(echo "$out" | jq -r .peer_verdicts)
assert_eq "1" "$vc" "peer_verdicts count = 1"
rc_count=$(echo "$out" | jq -r .peer_resolutions)
assert_eq "0" "$rc_count" "peer_resolutions = 0 (no findings)"

# === 15. peer-verdict + peer-resolution both present, counts match → ok ===
cat > /tmp/msg.txt <<'EOF'
feat: U3 (revise with 2 findings)

Body.

phase: P2
peer-verdict: {"verdict":"revise","peer_mode":"cross-agent","iteration":1,"findings_count":2}
peer-resolution: {"finding_id":"u3-1-1","u_id":"U3","iteration":1,"severity":"P1","status":"applied","title":"x"}
peer-resolution: {"finding_id":"u3-1-2","u_id":"U3","iteration":1,"severity":"P2","status":"deferred","rationale":"low conf","title":"y"}
EOF
sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" "$sha" --json)
rc=$?
assert_eq "0" "$rc" "peer-verdict + matching peer-resolution count → exit 0"

# === 16. peer-verdict findings_count mismatches peer-resolution count → malformed ===
cat > /tmp/msg.txt <<'EOF'
feat: U4 (count mismatch)

Body.

peer-verdict: {"verdict":"revise","peer_mode":"cross-agent","iteration":1,"findings_count":3}
peer-resolution: {"finding_id":"u4-1-1","u_id":"U4","iteration":1,"severity":"P1","status":"applied","title":"x"}
EOF
sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" "$sha" --json)
rc=$?
assert_eq "1" "$rc" "findings_count mismatch → exit 1"
verdict=$(echo "$out" | jq -r .verdict)
assert_eq "malformed" "$verdict" "findings_count mismatch verdict=malformed"

# === 17. peer-verdict invalid verdict value → malformed ===
cat > /tmp/msg.txt <<'EOF'
feat: U5 (bad verdict value)

Body.

peer-verdict: {"verdict":"maybe","peer_mode":"cross-agent","iteration":1,"findings_count":0}
EOF
sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" "$sha" --json)
rc=$?
assert_eq "1" "$rc" "invalid verdict value → exit 1"
verdict=$(echo "$out" | jq -r .verdict)
assert_eq "malformed" "$verdict" "invalid verdict value verdict=malformed"

# === 18. peer-verdict missing required field → malformed ===
cat > /tmp/msg.txt <<'EOF'
feat: U6 (missing field)

Body.

peer-verdict: {"verdict":"approve","peer_mode":"cross-agent","iteration":1}
EOF
sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" "$sha" --json)
rc=$?
assert_eq "1" "$rc" "peer-verdict missing findings_count → exit 1"
verdict=$(echo "$out" | jq -r .verdict)
assert_eq "malformed" "$verdict" "missing findings_count verdict=malformed"

# === 19. multiple peer-verdict trailers → malformed ===
cat > /tmp/msg.txt <<'EOF'
feat: U7 (duplicate verdict)

Body.

peer-verdict: {"verdict":"approve","peer_mode":"cross-agent","iteration":1,"findings_count":0}
peer-verdict: {"verdict":"approve","peer_mode":"cross-agent","iteration":2,"findings_count":0}
EOF
sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" "$sha" --json)
rc=$?
assert_eq "1" "$rc" "multiple peer-verdict → exit 1"
verdict=$(echo "$out" | jq -r .verdict)
assert_eq "malformed" "$verdict" "multiple peer-verdict verdict=malformed"

# === 20. --require-peer-resolution accepts peer-verdict alone (zero findings approve) ===
cat > /tmp/msg.txt <<'EOF'
feat: U8 (destructive; clean approve)

Body.

peer-verdict: {"verdict":"approve","peer_mode":"cross-agent","iteration":1,"findings_count":0}
EOF
sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" "$sha" --require-peer-resolution --json)
rc=$?
assert_eq "0" "$rc" "--require-peer-resolution + peer-verdict (0 findings) → exit 0"
verdict=$(echo "$out" | jq -r .verdict)
assert_eq "ok" "$verdict" "destructive unit with clean approve passes the gate"

# === 21. New auto-skip enum entries accepted ===
for reason in \
  "auto-skip:diff-below-threshold" \
  "auto-skip:lightweight-depth"; do
  cat > /tmp/msg.txt <<EOF
feat: auto-skip enum check

Body.

peer-skipped: $reason
EOF
  sha=$(make_commit /tmp/msg.txt)
  rc=0
  "$VERIFY" "$sha" --json >/dev/null 2>&1 || rc=$?
  assert_eq "0" "$rc" "accepted new auto-skip reason: $reason"
done

# === Branch-level review-verdict (FR01 U2) ===

# review-verdict alone → verdict ok (branch-level evidence)
cat > /tmp/msg.txt <<'EOF'
chore(build): branch-level review pass

review-verdict: {"verdict":"approve","reviewer":"en-review","mode":"headless","units_covered":["U1","U2","U3"],"findings_count":1}
EOF
rv_sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" "$rv_sha" --json); rc=$?
assert_eq "0" "$rc" "review-verdict alone → exit 0"
assert_eq "ok" "$(echo "$out" | jq -r .verdict)" "review-verdict verdict=ok"
assert_eq "1" "$(echo "$out" | jq -r .review_verdicts)" "review-verdict count=1"

# review-verdict is NOT sufficient under --require-peer-resolution
rc=0
"$VERIFY" "$rv_sha" --require-peer-resolution --json >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "review-verdict rejected under --require-peer-resolution"
out=$("$VERIFY" "$rv_sha" --require-peer-resolution --json 2>/dev/null)
assert_eq "missing-resolution" "$(echo "$out" | jq -r .verdict)" "review-verdict → missing-resolution when peer-resolution required"

# malformed review-verdict (missing units_covered) → malformed
cat > /tmp/msg.txt <<'EOF'
chore(build): bad rv

review-verdict: {"verdict":"approve","reviewer":"en-review","mode":"headless","findings_count":0}
EOF
bad_sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" "$bad_sha" --json 2>/dev/null)
assert_eq "malformed" "$(echo "$out" | jq -r .verdict)" "review-verdict missing units_covered → malformed"

# --branch-coverage enumerates covered U-IDs across the range
out=$("$VERIFY" --branch-coverage "${rv_sha}~1..${rv_sha}" --json)
covered=$(echo "$out" | jq -c '.covered_units')
assert_eq '["U1","U2","U3"]' "$covered" "branch-coverage enumerates covered units"

report
