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

VERIFY="$REPO_ROOT/skills/en-build/scripts/ensemble-verify-peer-evidence"

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

# review-verdict with bad VALUES/TYPES → malformed (not just presence; FR01 review finding 2)
cat > /tmp/msg.txt <<'EOF'
chore(build): typed-bad rv

review-verdict: {"verdict":"banana","reviewer":null,"mode":{},"units_covered":"U1","findings_count":"many"}
EOF
typed_sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" "$typed_sha" --json 2>/dev/null)
assert_eq "malformed" "$(echo "$out" | jq -r .verdict)" "review-verdict bad values/types → malformed"

# --branch-coverage enumerates covered U-IDs across the range
out=$("$VERIFY" --branch-coverage "${rv_sha}~1..${rv_sha}" --json)
covered=$(echo "$out" | jq -c '.covered_units')
assert_eq '["U1","U2","U3"]' "$covered" "branch-coverage enumerates covered units"

# --branch-coverage fails closed on a malformed review-verdict (FR01 review finding 3)
rc=0
"$VERIFY" --branch-coverage "${typed_sha}~1..${typed_sha}" --json >/tmp/bc_out.json 2>/dev/null || rc=$?
assert_eq "1" "$rc" "branch-coverage exits non-zero when a review-verdict is malformed"
inv=$(jq -r '.invalid_review_verdict_commits | length' /tmp/bc_out.json)
assert_eq "1" "$inv" "branch-coverage reports the malformed trailer as invalid"
covered=$(jq -c '.covered_units' /tmp/bc_out.json)
assert_eq '[]' "$covered" "branch-coverage does not count a malformed trailer's units"

# === EN07: post-build simplify+review gate (simplify-verdict trailer) ===

# --- Happy path: cross-agent review + completed simplify → both pass, --require-simplify exit 0
cat > /tmp/msg.txt <<'EOF'
chore(build): post-build simplify + review (happy)

review-verdict: {"verdict":"approve","reviewer":"cross-agent","mode":"headless","units_covered":["U1","U2"],"findings_count":1}
simplify-verdict: {"outcome":"completed","reason":"","findings_count":3,"units_covered":["U1","U2"]}
EOF
ok_sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" --branch-coverage "${ok_sha}~1..${ok_sha}" --json)
assert_eq "completed" "$(echo "$out" | jq -r .simplify_pass)" "EN07 happy: simplify_pass=completed"
assert_eq "completed" "$(echo "$out" | jq -r .branch_review_pass)" "EN07 happy: branch_review_pass=completed"
rc=0; "$VERIFY" --branch-coverage "${ok_sha}~1..${ok_sha}" --require-simplify --json >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "EN07 happy: --require-simplify exits 0"

# --- not_applicable with a recorded reason → passes the gate
cat > /tmp/msg.txt <<'EOF'
chore(build): post-build simplify + review (docs-only)

review-verdict: {"verdict":"approve","reviewer":"cross-agent","mode":"headless","units_covered":["U1"],"findings_count":0}
simplify-verdict: {"outcome":"not_applicable","reason":"docs-only","findings_count":0,"units_covered":[]}
EOF
na_sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" --branch-coverage "${na_sha}~1..${na_sha}" --json)
assert_eq "not_applicable" "$(echo "$out" | jq -r .simplify_pass)" "EN07 n/a: simplify_pass=not_applicable"
rc=0; "$VERIFY" --branch-coverage "${na_sha}~1..${na_sha}" --require-simplify --json >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "EN07 n/a: recorded not_applicable passes --require-simplify"

# --- Fallback review (single-agent-fallback) → fallback_completed, still passes
cat > /tmp/msg.txt <<'EOF'
chore(build): post-build simplify + review (fallback)

review-verdict: {"verdict":"approve","reviewer":"single-agent-fallback","mode":"headless","units_covered":["U1"],"findings_count":0}
simplify-verdict: {"outcome":"completed","reason":"","findings_count":1,"units_covered":["U1"]}
EOF
fb_sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" --branch-coverage "${fb_sha}~1..${fb_sha}" --json)
assert_eq "fallback_completed" "$(echo "$out" | jq -r .branch_review_pass)" "EN07 fallback: branch_review_pass=fallback_completed"
rc=0; "$VERIFY" --branch-coverage "${fb_sha}~1..${fb_sha}" --require-simplify --json >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "EN07 fallback: recorded fallback passes --require-simplify"

# --- Missing simplify (review present, no simplify-verdict) → the exact EN06 hole
cat > /tmp/msg.txt <<'EOF'
chore(build): post-build review only (missing simplify)

review-verdict: {"verdict":"approve","reviewer":"cross-agent","mode":"headless","units_covered":["U1"],"findings_count":0}
EOF
miss_sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" --branch-coverage "${miss_sha}~1..${miss_sha}" --json)
assert_eq "missing" "$(echo "$out" | jq -r .simplify_pass)" "EN07 missing: simplify_pass=missing"
rc=0; "$VERIFY" --branch-coverage "${miss_sha}~1..${miss_sha}" --require-simplify --json >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "EN07 missing: --require-simplify FAILS on missing simplify (the EN06 hole)"
# Backward-compat: WITHOUT the flag, a missing simplify does not fail (existing callers unaffected)
rc=0; "$VERIFY" --branch-coverage "${miss_sha}~1..${miss_sha}" --json >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "EN07 backward-compat: missing simplify exits 0 without --require-simplify"

# --- Malformed simplify (not_applicable missing its reason) → failed
cat > /tmp/msg.txt <<'EOF'
chore(build): post-build (malformed simplify)

review-verdict: {"verdict":"approve","reviewer":"cross-agent","mode":"headless","units_covered":["U1"],"findings_count":0}
simplify-verdict: {"outcome":"not_applicable","reason":"","findings_count":0,"units_covered":[]}
EOF
badsv_sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" --branch-coverage "${badsv_sha}~1..${badsv_sha}" --json)
assert_eq "failed" "$(echo "$out" | jq -r .simplify_pass)" "EN07 malformed: not_applicable without reason → simplify_pass=failed"
rc=0; "$VERIFY" --branch-coverage "${badsv_sha}~1..${badsv_sha}" --require-simplify --json >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "EN07 malformed: --require-simplify FAILS on an invalid simplify-verdict"

# --- Explicit failed simplify outcome → gate blocks
cat > /tmp/msg.txt <<'EOF'
chore(build): post-build (simplify failed)

review-verdict: {"verdict":"approve","reviewer":"cross-agent","mode":"headless","units_covered":["U1"],"findings_count":0}
simplify-verdict: {"outcome":"failed","reason":"simplifier reverted: gate-2 regression","findings_count":0,"units_covered":["U1"]}
EOF
failsv_sha=$(make_commit /tmp/msg.txt)
rc=0; "$VERIFY" --branch-coverage "${failsv_sha}~1..${failsv_sha}" --require-simplify --json >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "EN07 failed-outcome: --require-simplify FAILS on outcome:failed"

# --- Unpaired trailers across DIFFERENT commits must NOT satisfy the gate
#     (EN07 U1 review finding: simplify-verdict on a commit without a review-verdict
#      is not a valid post-build checkpoint). Commit A = review only; commit B =
#      simplify only. The gate pairs on the latest review commit (A), which has
#      NO simplify → simplify_pass=missing, --require-simplify FAILS.
cat > /tmp/msg.txt <<'EOF'
chore(build): review-only commit (A)

review-verdict: {"verdict":"approve","reviewer":"cross-agent","mode":"headless","units_covered":["U1"],"findings_count":0}
EOF
pairA_sha=$(make_commit /tmp/msg.txt)
cat > /tmp/msg.txt <<'EOF'
chore(cleanup): unrelated simplify-only commit (B)

simplify-verdict: {"outcome":"completed","reason":"","findings_count":1,"units_covered":["U1"]}
EOF
pairB_sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" --branch-coverage "${pairA_sha}~1..${pairB_sha}" --json)
assert_eq "missing" "$(echo "$out" | jq -r .simplify_pass)" "EN07 unpaired: simplify on a non-review commit → simplify_pass=missing"
rc=0; "$VERIFY" --branch-coverage "${pairA_sha}~1..${pairB_sha}" --require-simplify --json >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "EN07 unpaired: --require-simplify FAILS when no single commit carries BOTH trailers"

report
