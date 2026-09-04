#!/usr/bin/env bash
# Tests for skills/*/scripts/ensemble-verify-peer-evidence (branch-coverage mode).
#
# The helper is the mechanical gate /en-build's end-of-build audit and /en-ship's
# plan-completion checkpoint read. It inspects git trailers, never an agent's
# memory of having run the review. D83 retired its single-commit mode and the
# per-unit trailers (peer-verdict / peer-resolution / peer-skipped) that D52 had
# already stopped any skill from emitting; the clauses that drove that mode went
# with it, and one clause now proves the retired form is refused rather than
# answered with "missing evidence" for trailers nothing writes.

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

# === Branch-level review-verdict (FR01 U2) ===

# === D83: the retired single-commit form is refused, not answered ===
cat > /tmp/msg.txt <<'EOF'
feat(x): a unit commit with no trailer at all
EOF
plain_sha=$(make_commit /tmp/msg.txt)
rc=0; err=$("$VERIFY" "$plain_sha" --json 2>&1 >/dev/null) || rc=$?
assert_eq "2" "$rc" "a single commit ref exits 2"
printf '%s' "$err" | grep -q -- "--branch-coverage" && pass "the refusal names --branch-coverage" || fail "the refusal names --branch-coverage" "$err"
rc=0; "$VERIFY" "$plain_sha" --require-peer-resolution --json >/dev/null 2>&1 || rc=$?
assert_eq "2" "$rc" "--require-peer-resolution is an unknown flag now"
rc=0; "$VERIFY" --json >/dev/null 2>&1 || rc=$?
assert_eq "2" "$rc" "no range at all exits 2"

# === D83: legacy per-unit trailers are ignored, never parsed, never fatal ===
cat > /tmp/msg.txt <<'EOF'
feat(auth): legacy unit commit (pre-D52)

peer-verdict: {"verdict":"approve","peer_mode":"cross-agent","iteration":1,"findings_count":1}
peer-resolution: {"finding_id":"1-1","u_id":"U9","iteration":1,"severity":"P2","status":"applied","title":"x"}
peer-skipped: recursion-guard-active
EOF
legacy_sha=$(make_commit /tmp/msg.txt)
out=$("$VERIFY" --branch-coverage "${legacy_sha}~1..${legacy_sha}" --json); rc=$?
assert_eq "0" "$rc" "a range holding only legacy per-unit trailers exits 0"
assert_eq "[]" "$(echo "$out" | jq -c .covered_units)" "legacy trailers cover nothing"
assert_eq "missing" "$(echo "$out" | jq -r .branch_review_pass)" "legacy trailers are not a branch review"

# === Branch-level review-verdict (FR01 U2) ===

cat > /tmp/msg.txt <<'EOF'
chore(build): branch-level review pass

review-verdict: {"verdict":"approve","reviewer":"en-review","mode":"headless","units_covered":["U1","U2","U3"],"findings_count":1}
EOF
rv_sha=$(make_commit /tmp/msg.txt)

# malformed review-verdict (missing units_covered) → not counted, exit 1
cat > /tmp/msg.txt <<'EOF'
chore(build): bad rv

review-verdict: {"verdict":"approve","reviewer":"en-review","mode":"headless","findings_count":0}
EOF
bad_sha=$(make_commit /tmp/msg.txt)
rc=0; out=$("$VERIFY" --branch-coverage "${bad_sha}~1..${bad_sha}" --json 2>/dev/null) || rc=$?
assert_eq "1" "$rc" "review-verdict missing units_covered → exit 1"
assert_eq "1" "$(echo "$out" | jq -r '.invalid_review_verdict_commits | length')" "review-verdict missing units_covered → reported invalid"

# review-verdict with bad VALUES/TYPES → invalid (not just presence; FR01 review finding 2)
cat > /tmp/msg.txt <<'EOF'
chore(build): typed-bad rv

review-verdict: {"verdict":"banana","reviewer":null,"mode":{},"units_covered":"U1","findings_count":"many"}
EOF
typed_sha=$(make_commit /tmp/msg.txt)

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
