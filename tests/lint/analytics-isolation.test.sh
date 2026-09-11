#!/usr/bin/env bash
# tests/lint/analytics-isolation.test.sh
#
# A test suite that writes to the operator's real analytics store poisons the
# data it exists to produce. By 2026-09-10 ~/.ensemble/analytics/guardrail.jsonl
# held 71,171 events, 97% of which landed in the same second as another: that is
# tests/en-guardrail/check-guardrail.test.sh firing the matcher, not anybody's
# destructive commands. Four months of data, almost none of it usable.
#
# Guarded here:
#
#   EVERY WRITER TAKES AN OVERRIDE   a hardcoded ~/.ensemble path cannot be
#                                    redirected, so a test cannot avoid it.
#   EVERY SUITE SETS IT              a writer with an override nobody uses is
#                                    the same defect with extra steps.
#   THE LABEL IS NOT DERIVED         the pattern name reaches disk, so deriving
#                                    it from a regex put `(^|` in the data and
#                                    collapsed six git rules into one bucket.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="analytics isolation"

# --- every writer of the analytics store honours an override -----------------
writers=$(grep -rliE '>>[^\n]*analytics' "$REPO_ROOT"/skills/*/bin/* "$REPO_ROOT"/skills/*/scripts/* 2>/dev/null || true)
[ -n "$writers" ] && pass "found the analytics writers to check" \
  || fail "no analytics writer found; this guard has nothing to protect"

bad=""
for w in $writers; do
  grep -q 'ENSEMBLE_ANALYTICS_DIR' "$w" || bad="$bad $(basename "$w")"
done
[ -z "$bad" ] \
  && pass "every analytics writer honours ENSEMBLE_ANALYTICS_DIR" \
  || fail "an analytics writer cannot be redirected" "hardcoded:$bad"

# --- every suite that drives a writer redirects it ---------------------------
# Scoped to suites that actually invoke one: a suite that never fires the hook
# needs no override, and demanding one everywhere would be noise.
for t in "$REPO_ROOT"/tests/en-guardrail/*.test.sh; do
  drives=0
  grep -qE 'bash "\$HOOK"|bash "\$HOOK_SCRIPT"|\| *bash .*check-guardrail' "$t" && drives=1
  [ "$drives" -eq 1 ] || continue
  if grep -q 'ENSEMBLE_ANALYTICS_DIR' "$t"; then
    pass "$(basename "$t") redirects analytics away from the operator's store"
  else
    fail "$(basename "$t") drives the hook without redirecting analytics" \
         "it will append to ~/.ensemble/analytics on every run"
  fi
done

# --- the recorded label is explicit, never derived from a regex --------------
AN="$REPO_ROOT/skills/en-guardrail/bin/guardrail_analyze.py"
grep -vE '^\s*#' "$AN" | grep -q 'pat.split(chr(92))' \
  && fail "the analytics label is derived from the regex source" \
       "that wrote '(^|' to disk and collapsed six git rules to 'git'" \
  || pass "the analytics label is not derived from the regex source"

# Each rule carries its own name, and the names are distinct — the defect was
# not a bad name, it was many rules sharing one.
names=$(python3 - "$AN" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
block = src[src.index("TOOL_PATTERNS = ["):]
block = block[:block.index("\n]\n")]
print("\n".join(re.findall(r'^    \("([a-z0-9_]+)",', block, re.M)))
PY
)
total=$(printf '%s\n' "$names" | grep -c .)
uniq=$(printf '%s\n' "$names" | sort -u | grep -c .)
[ "$total" -gt 0 ] && [ "$total" -eq "$uniq" ] \
  && pass "every tool pattern has its own distinct name ($total rules)" \
  || fail "tool-pattern names must be distinct" "total=$total distinct=$uniq"

# The one that made the old data useless: the git rules must not share a label.
gits=$(printf '%s\n' "$names" | grep -c '^git_' || true)
[ "${gits:-0}" -ge 5 ] \
  && pass "the git rules are separately labelled ($gits of them)" \
  || fail "the git rules collapsed into one label again" "found $gits git_* names"

# --- the label reaches JSON escaped ------------------------------------------
HOOK="$REPO_ROOT/skills/en-guardrail/bin/check-guardrail.sh"
grep -q 'PATTERN_ESCAPED' "$HOOK" \
  && pass "the pattern is escaped before it reaches the JSON line" \
  || fail "an unescaped label with a quote writes a line no reader can parse"

# --- and it actually works, driven end to end --------------------------------
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' \
  | ENSEMBLE_ANALYTICS_DIR="$T" bash "$HOOK" >/dev/null 2>&1
if [ -f "$T/guardrail.jsonl" ]; then
  pass "the override actually redirects the write"
  lbl=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["pattern"])' \
        <(head -1 "$T/guardrail.jsonl") 2>/dev/null || head -1 "$T/guardrail.jsonl" | sed 's/.*"pattern":"\([^"]*\)".*/\1/')
  assert_eq "git_force_push" "$lbl" "a force-push records as git_force_push, not git"
else
  fail "the override actually redirects the write" "no file under $T"
fi

report
