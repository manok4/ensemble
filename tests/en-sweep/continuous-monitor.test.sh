#!/usr/bin/env bash
# Tests for skills/en-sweep/scripts/continuous-monitor + triage-findings.
# Focuses on the triage logic (deterministic) since the monitor wraps external
# tools (ts-prune, npm audit, etc.) we can't reliably exercise here.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="sweep continuous-monitor / triage"

SWEEP_SCRIPTS="$REPO_ROOT/skills/en-sweep/scripts"
MONITOR="$SWEEP_SCRIPTS/continuous-monitor"
TRIAGE="$SWEEP_SCRIPTS/triage-findings"

# --- Scripts exist and are executable ---
for s in continuous-monitor triage-findings; do
  if [ -x "$SWEEP_SCRIPTS/$s" ]; then
    pass "script exists and is executable: $s"
  else
    fail "script missing: $s"
  fi
done

# --- triage: empty input → empty output ---
out=$(echo "" | bash "$TRIAGE" 2>&1)
if echo "$out" | python3 -c 'import sys,json; d=json.loads(sys.stdin.read()); assert d["td_entries"]==[] and d["draft_plans"]==[]' 2>/dev/null; then
  pass "triage returns empty buckets on empty input"
else
  fail "triage did not handle empty input" "$out"
fi

# --- triage: single dead-code finding → TD entry ---
SINGLE_DEAD='{"check":"dead-code","category":"dead_function","file":"src/foo.ts","line":42,"symbol":"unusedFn","severity":"P3","message":"Unused export: unusedFn","details":"","loc_estimate":5,"fix_command":""}'
out=$(echo "$SINGLE_DEAD" | bash "$TRIAGE")
td_count=$(echo "$out" | python3 -c 'import sys,json; print(len(json.loads(sys.stdin.read())["td_entries"]))')
plan_count=$(echo "$out" | python3 -c 'import sys,json; print(len(json.loads(sys.stdin.read())["draft_plans"]))')
if [ "$td_count" = "1" ] && [ "$plan_count" = "0" ]; then
  pass "single dead-code finding goes to TD (not plan)"
else
  fail "single dead-code triage wrong" "td=$td_count plan=$plan_count"
fi

# --- triage: ≥2 dead-code findings clustered in same area → draft plan ---
CLUSTER=$(cat <<'EOF'
{"check":"dead-code","category":"dead_function","file":"src/utils/a.ts","line":10,"symbol":"a1","severity":"P3","message":"Unused: a1","details":"","loc_estimate":5,"fix_command":""}
{"check":"dead-code","category":"dead_function","file":"src/utils/b.ts","line":20,"symbol":"b1","severity":"P3","message":"Unused: b1","details":"","loc_estimate":5,"fix_command":""}
{"check":"dead-code","category":"dead_function","file":"src/utils/c.ts","line":30,"symbol":"c1","severity":"P3","message":"Unused: c1","details":"","loc_estimate":5,"fix_command":""}
EOF
)
out=$(echo "$CLUSTER" | bash "$TRIAGE")
plan_count=$(echo "$out" | python3 -c 'import sys,json; print(len(json.loads(sys.stdin.read())["draft_plans"]))')
plan_findings=$(echo "$out" | python3 -c 'import sys,json; d=json.loads(sys.stdin.read()); print(len(d["draft_plans"][0]["findings"]) if d["draft_plans"] else 0)')
plan_area=$(echo "$out" | python3 -c 'import sys,json; d=json.loads(sys.stdin.read()); print(d["draft_plans"][0]["area"] if d["draft_plans"] else "")')
if [ "$plan_count" = "1" ] && [ "$plan_findings" = "3" ] && [ "$plan_area" = "src/utils" ]; then
  pass "clustered dead-code findings (≥2 in same dir) become a single draft plan"
else
  fail "cluster triage wrong" "plans=$plan_count findings_in_plan=$plan_findings area=$plan_area"
fi

# --- triage: dep-audit with auto-fix → TD ---
DEP_AUTOFIX='{"check":"dep-audit","category":"vuln","file":"package.json","line":null,"symbol":"lodash","severity":"P1","message":"lodash CVE","details":"","loc_estimate":1,"fix_command":"npm audit fix"}'
out=$(echo "$DEP_AUTOFIX" | bash "$TRIAGE")
td_count=$(echo "$out" | python3 -c 'import sys,json; print(len(json.loads(sys.stdin.read())["td_entries"]))')
plan_count=$(echo "$out" | python3 -c 'import sys,json; print(len(json.loads(sys.stdin.read())["draft_plans"]))')
if [ "$td_count" = "1" ] && [ "$plan_count" = "0" ]; then
  pass "dep-audit with auto-fix goes to TD (mechanical)"
else
  fail "dep-audit autofix triage wrong" "td=$td_count plan=$plan_count"
fi

# --- triage: dep-audit P1 without auto-fix and large loc_estimate → draft plan ---
DEP_PLAN='{"check":"dep-audit","category":"vuln","file":"package.json","line":null,"symbol":"react","severity":"P1","message":"React major-version migration needed","details":"","loc_estimate":200,"fix_command":""}'
out=$(echo "$DEP_PLAN" | bash "$TRIAGE")
plan_count=$(echo "$out" | python3 -c 'import sys,json; print(len(json.loads(sys.stdin.read())["draft_plans"]))')
if [ "$plan_count" = "1" ]; then
  pass "dep-audit P1 without auto-fix + non-trivial scope → draft plan"
else
  fail "dep-audit plan triage wrong" "plans=$plan_count out=$out"
fi

# --- triage: max_drafts_per_run cap; overflow rolls to TD ---
LARGE_CLUSTER=""
for area in alpha beta gamma delta epsilon; do
  for sym in s1 s2 s3; do
    LARGE_CLUSTER="${LARGE_CLUSTER}"$'\n'"{\"check\":\"dead-code\",\"category\":\"dead_function\",\"file\":\"src/$area/$sym.ts\",\"line\":1,\"symbol\":\"$sym\",\"severity\":\"P3\",\"message\":\"Unused: $sym\",\"details\":\"\",\"loc_estimate\":5,\"fix_command\":\"\"}"
  done
done
out=$(printf '%s' "$LARGE_CLUSTER" | SWEEP_MAX_DRAFTS_PER_RUN=2 bash "$TRIAGE")
plan_count=$(echo "$out" | python3 -c 'import sys,json; print(len(json.loads(sys.stdin.read())["draft_plans"]))')
td_overflow=$(echo "$out" | python3 -c 'import sys,json; d=json.loads(sys.stdin.read()); print(sum(1 for e in d["td_entries"] if "Would have been a plan" in str(e.get("note", ""))))')
if [ "$plan_count" = "2" ] && [ "$td_overflow" -gt 0 ]; then
  pass "max_drafts_per_run caps draft plans; overflow rolls to TD with note"
else
  fail "max_drafts cap not applied" "plans=$plan_count overflow=$td_overflow"
fi

# Regression: overflow findings should NOT also appear in `skipped` (they're
# already counted in td_entries; previous version copied them and lost
# identity, leading to double-counting).
skipped_count=$(echo "$out" | python3 -c 'import sys,json; print(len(json.loads(sys.stdin.read())["skipped"]))')
if [ "$skipped_count" = "0" ]; then
  pass "overflow findings are not double-counted in skipped"
else
  fail "overflow findings leaked into skipped" "skipped=$skipped_count"
fi

# --- triage: respects auto_plan_threshold_locations env override ---
TWO_FILES='{"check":"dead-code","category":"dead_function","file":"src/utils/a.ts","line":1,"symbol":"a","severity":"P3","message":"a","details":"","loc_estimate":5,"fix_command":""}
{"check":"dead-code","category":"dead_function","file":"src/utils/b.ts","line":1,"symbol":"b","severity":"P3","message":"b","details":"","loc_estimate":5,"fix_command":""}'
# With locations threshold = 5 (high), 2 findings should NOT cluster
out=$(echo "$TWO_FILES" | SWEEP_AUTO_PLAN_THRESHOLD_LOCATIONS=5 bash "$TRIAGE")
plan_count=$(echo "$out" | python3 -c 'import sys,json; print(len(json.loads(sys.stdin.read())["draft_plans"]))')
if [ "$plan_count" = "0" ]; then
  pass "auto_plan_threshold_locations override raises bar for clustering"
else
  fail "threshold override not respected" "plans=$plan_count"
fi

# --- continuous-monitor: runs cleanly on a project with no detection tools ---
TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT
cd "$TMP"
out=$(bash "$MONITOR" true true 2>&1)
rc=$?
if [ "$rc" = "0" ]; then
  pass "continuous-monitor exits 0 even when no project tools available"
else
  fail "continuous-monitor exited non-zero" "rc=$rc out=$out"
fi
cd - >/dev/null

report
