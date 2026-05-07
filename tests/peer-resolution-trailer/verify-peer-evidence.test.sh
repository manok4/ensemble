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

report
