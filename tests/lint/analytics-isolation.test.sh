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
# Discovery is by the PATH, not by the redirection operator. `>> ... analytics`
# only finds a writer whose append names the directory on the same line;
# ensemble-run-metrics appends to "$adir/$repo.jsonl", so that pattern missed it
# entirely. Anything that can resolve the operator's analytics path is a writer
# for this purpose, and must be redirectable.
writers=$(grep -rlE '\.ensemble/analytics' "$REPO_ROOT"/skills/*/bin/* "$REPO_ROOT"/skills/*/scripts/* 2>/dev/null || true)
[ -n "$writers" ] && pass "found the analytics writers to check" \
  || fail "no analytics writer found; this guard has nothing to protect"

# CODE ONLY, NEVER COMMENTS. Every writer here carries a comment explaining why
# the override exists, so a grep over the whole file is satisfied by the prose
# alone: deleting the actual `${ENSEMBLE_ANALYTICS_DIR:-...}` expansion left this
# assertion green. Strip comment lines first, and require the expansion rather
# than the bare name.
code_only() { grep -vE '^[[:space:]]*#' "$1"; }
bad=""
for w in $writers; do
  code_only "$w" | grep -qE '\$\{ENSEMBLE_ANALYTICS_DIR:-' || bad="$bad $(basename "$w")"
done
[ -z "$bad" ] \
  && pass "every analytics writer honours ENSEMBLE_ANALYTICS_DIR" \
  || fail "an analytics writer cannot be redirected" "hardcoded:$bad"

# --- every suite that drives a writer redirects it ---------------------------
# Scoped to suites that actually invoke one: a suite that never drives a writer
# needs no override, and demanding one everywhere would be noise. The scan is
# the WHOLE suite tree, not tests/en-guardrail/: ensemble-run-metrics writes the
# rollup from `finish`, and its tests live elsewhere.
# A driver is a suite that EXECUTES a writer, which is not the same as one that
# mentions its filename: install-guardrail.test.sh asserts about the installed
# hook command as a string and never runs the hook. So each writer declares how
# it is invoked, and the table is self-enforcing — a writer with no entry fails
# below, so a new one cannot arrive without saying how a suite drives it.
driver_pattern() {
  case "$1" in
    check-guardrail.sh)   printf '%s' 'bash "\$HOOK"|bash "\$HOOK_SCRIPT"|\| *bash .*check-guardrail' ;;
    ensemble-run-metrics) printf '%s' 'bash "\$RM"|ensemble-run-metrics" +(start|emit|event|finish|summary)' ;;
    *) return 1 ;;
  esac
}

undeclared=""
PATTERNS=""
for w in $writers; do
  b=$(basename "$w")
  case " $PATTERNS " in *" $b "*) continue ;; esac
  if pat=$(driver_pattern "$b"); then
    PATTERNS="$PATTERNS $b"
  else
    undeclared="$undeclared $b"
  fi
done
[ -z "$undeclared" ] \
  && pass "every analytics writer declares how a suite drives it" \
  || fail "an analytics writer has no driver pattern" \
          "undeclared:$undeclared — add it to driver_pattern() or its suites go unchecked"

drove=0
while IFS= read -r t; do
  drives=0
  for b in $PATTERNS; do
    pat=$(driver_pattern "$b")
    code_only "$t" | grep -qE "$pat" && { drives=1; break; }
  done
  [ "$drives" -eq 1 ] || continue
  # This file matches its own driver_pattern table, because the table holds the
  # invocation shapes as literal text. That is data, not execution. Its one real
  # driving call is asserted directly below, with the override on the line.
  [ "$(basename "$t")" = "analytics-isolation.test.sh" ] && continue
  drove=$((drove + 1))
  # EVERY DRIVING LINE, not merely a mention somewhere in the file. A suite that
  # redirects one call and not another is the defect this guard exists for, and
  # ensemble-run-metrics.test.sh was exactly that: a late `export` with fifteen
  # sections of `finish` calls above it, 156 lines into the operator's store.
  # A line passes if it sets the override itself, or if the file exports it at
  # file scope, which covers every call below.
  # POSITION, NOT PRESENCE. An export below the first driving line covers
  # nothing above it, and "somewhere in the file" was satisfied by exactly that
  # arrangement while 156 lines went into the operator's store.
  exp_line=$(grep -nE '^[[:space:]]*export[[:space:]]+ENSEMBLE_ANALYTICS_DIR=' "$t" | head -1 | cut -d: -f1)
  first_drive=$(for b in $PATTERNS; do pat=$(driver_pattern "$b"); grep -nE "$pat" "$t" || true; done \
                | cut -d: -f1 | sort -n | head -1)
  exported=0
  [ -n "$exp_line" ] && [ -n "$first_drive" ] && [ "$exp_line" -lt "$first_drive" ] && exported=1
  uncovered=0
  while IFS= read -r ln; do
    [ "$exported" -eq 1 ] && break
    printf '%s' "$ln" | grep -q 'ENSEMBLE_ANALYTICS_DIR=' || uncovered=$((uncovered + 1))
  done < <(for b in $PATTERNS; do pat=$(driver_pattern "$b"); code_only "$t" | grep -E "$pat" || true; done)
  if [ "$exported" -eq 1 ] || [ "$uncovered" -eq 0 ]; then
    pass "$(basename "$t") redirects analytics away from the operator's store"
  else
    fail "$(basename "$t") drives an analytics writer without redirecting it" \
         "$uncovered driving line(s) carry no override; it will append to ~/.ensemble/analytics"
  fi
done < <(find "$REPO_ROOT/tests" -name '*.test.sh' -type f | sort)
[ "$drove" -ge 2 ] \
  && pass "the suite scan found the drivers it is meant to check ($drove)" \
  || fail "the suite scan found $drove drivers; it should find the guardrail hook and the rollup"

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
