#!/usr/bin/env bash
# tests/en-sweep/review-history.test.sh
#
# EN22 U6. ensemble-review-history feeds the sweep's recurrence scan: review
# comments from merged PRs, one JSON line each. `gh` is stubbed on PATH and
# answers from a fixture of raw GraphQL, filtering by the merged:>= date in the
# search query the way GitHub would; the script's own jq transform runs for real.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="ensemble-review-history"

HIST="$REPO_ROOT/skills/en-sweep/scripts/ensemble-review-history"
T=$(mktemp -d)
trap "rm -rf '$T'" EXIT
mkdir -p "$T/stub"

# PR 101 merged 2026-08-17 and PR 130 merged 2026-09-23 carry the same
# correction; PR 130 also has a bot comment and an unrelated one.
cat > "$T/prs.json" <<'EOF'
{"data":{"search":{"nodes":[
 {"number":101,"mergedAt":"2026-08-17T10:00:00Z","reviewThreads":{"nodes":[
   {"isResolved":true,"comments":{"nodes":[
     {"path":"backend/app/api/routes/items.py","body":"Don't return the ORM row; validate through the schema.","author":{"login":"mano","__typename":"User"}}]}}]}},
 {"number":130,"mergedAt":"2026-09-23T10:00:00Z","reviewThreads":{"nodes":[
   {"isResolved":true,"comments":{"nodes":[
     {"path":"backend/app/api/routes/orders.py","body":"This returns an ORM instance again, use Schema.model_validate.","author":{"login":"mano","__typename":"User"}}]}},
   {"isResolved":false,"comments":{"nodes":[
     {"path":"frontend/src/routes/_layout/inventory.tsx","body":"Nit: rename this variable.","author":{"login":"claude[bot]","__typename":"Bot"}}]}}]}}
]}}}
EOF

cat > "$T/stub/gh" <<'S'
#!/bin/sh
[ -n "${STUB_GH_FAIL:-}" ] && { echo "gh: HTTP 502" >&2; exit 1; }
case "$1 $2" in
  "repo view") echo "manok4/emble"; exit 0 ;;
  "api graphql") ;;
  *) echo "stub gh: unexpected $*" >&2; exit 2 ;;
esac
since=$(printf '%s\n' "$@" | sed -n 's/.*merged:>=\([0-9-]*\).*/\1/p' | head -1)
jq --arg s "$since" '.data.search.nodes |= map(select(.mergedAt[0:10] >= $s))' "$STUB_GH_PRS"
S
chmod +x "$T/stub/gh"
export PATH="$T/stub:$PATH" STUB_GH_PRS="$T/prs.json"

# --- happy path: every review comment, one line each ---
out=$("$HIST" --since 2026-07-28 --repo manok4/emble); rc=$?
assert_eq "0" "$rc" "exits 0 when PRs matched"
assert_eq "3" "$(printf '%s\n' "$out" | grep -c '^{')" "one JSON line per review comment (3)"
printf '%s\n' "$out" | jq -e 'select(.pr == 101 and .path == "backend/app/api/routes/items.py" and (.body | test("ORM row")))' >/dev/null \
  && pass "a line carries pr, path and body" || fail "a line carries pr, path and body" "$out"
printf '%s\n' "$out" | jq -e 'select(.author == "claude[bot]" and .bot == true and .resolved == false)' >/dev/null \
  && pass "a bot comment is kept and marked bot: true" || fail "a bot comment is kept and marked bot: true" "$out"
printf '%s\n' "$out" | jq -e 'select(.author == "mano" and .bot == false)' >/dev/null \
  && pass "a human comment is bot: false" || fail "a human comment is bot: false" "$out"

# --- the sweep boundary: the window, not the last sweep, decides recall ---
# Last sweep 2026-09-06, today 2026-09-26. A 60-day window reaches PR 101.
prs=$("$HIST" --since 2026-07-28 --repo manok4/emble | jq -r .pr | sort -u | tr '\n' ' ')
assert_eq "101 130 " "$prs" "a 60-day window returns both PRs of the recurring correction"
prs=$("$HIST" --since 2026-09-06 --repo manok4/emble | jq -r .pr | sort -u | tr '\n' ' ')
assert_eq "130 " "$prs" "since the last sweep alone, only PR 130 is seen"

# --- no PRs: exit 3 with nothing on stdout ---
out=$("$HIST" --since 2026-09-25 --repo manok4/emble); rc=$?
assert_eq "3|" "$rc|$out" "no merged PRs exits 3 with empty stdout"

# --- gh fails: exit 1, gh named, never a quiet 0 ---
err=$(STUB_GH_FAIL=1 "$HIST" --since 2026-07-28 --repo manok4/emble 2>&1 >/dev/null); rc=$?
assert_eq "1" "$rc" "a gh failure exits 1"
printf '%s' "$err" | grep -q 'gh' && pass "stderr names gh" || fail "stderr names gh" "$err"

# --- repo defaults to the current one ---
out=$("$HIST" --since 2026-07-28); rc=$?
assert_eq "0" "$rc" "without --repo it asks gh for the current repo"

# --- usage ---
"$HIST" --since yesterday >/dev/null 2>&1
assert_eq "2" "$?" "a non-ISO --since is a usage error"
"$HIST" >/dev/null 2>&1
assert_eq "2" "$?" "a missing --since is a usage error"

# --- the sweep step and its reference, anchored per file ---
SKILL="$REPO_ROOT/skills/en-sweep/SKILL.md"
REF="$REPO_ROOT/skills/en-sweep/references/recurrence-scan.md"
step=$(grep -F '8b.' "$SKILL" | head -1)
printf '%s' "$step" | grep -qF 'sweep.recurrence_scan' \
  && pass "step 8b is opt-in behind sweep.recurrence_scan" || fail "step 8b is opt-in behind sweep.recurrence_scan" "$step"
printf '%s' "$step" | grep -qF 'references/recurrence-scan.md' \
  && pass "step 8b reads its reference" || fail "step 8b reads its reference"
grep -qF 'recurrence_window_days' "$REF" \
  && pass "the reference sets a trailing window" || fail "the reference sets a trailing window"
grep -qiF 'two or more distinct PRs' "$REF" \
  && pass "the reference states the two-PR threshold" || fail "the reference states the two-PR threshold"
grep -qF -- '--list-keys' "$REF" \
  && pass "the reference reuses open entries' keys" || fail "the reference reuses open entries' keys"
grep -qF 'recurrence_scan: failed' "$REF" \
  && pass "a failed scan is reported in the summary" || fail "a failed scan is reported in the summary"

report
