#!/usr/bin/env bash
# tests/lint/en-review-verification-pass.test.sh
#
# D80: after en-review addresses a P0/P1, one verification pass confirms the
# fixes and looks for new P0/P1, with a mandatory outcome line so a skipped
# pass can never read as a clean one. Before D80 en-review and en-build's
# post-build review both ran once; the review-verdict trailer described the
# code before the fixes.
#
# Negative controls at authoring: deleting the `--verify` flags row turned the
# flag clause red; removing the `--iteration-context-file` mention from step
# 12a turned the context clause red; the builder clause is run, not grepped,
# so an empty iteration file turned it red.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-review verification pass"

SKILL="$REPO_ROOT/skills/en-review/SKILL.md"
CONTRACT="$REPO_ROOT/skills/en-review/CONTRACT.md"
BUILD="$REPO_ROOT/skills/en-build/SKILL.md"
BUILDER="$REPO_ROOT/skills/en-review/scripts/ensemble-build-peer-prompt"
BRIEF="$REPO_ROOT/skills/en-review/references/peer-brief-lite.md"

# --- the flag, in the flags table and in the contract ---
if grep -qE '^\| `--verify \[<envelope-path>\]` \|' "$SKILL" && grep -qF -- '--verify <envelope-path>' "$CONTRACT"; then
  pass "--verify is a documented flag and a contract invocation"
else
  fail "--verify must appear in the flags table and in CONTRACT.md"
fi

# --- mandatory outcome line, all three forms ---
if grep -qF "verification_pass: clean" "$SKILL" \
   && grep -qF "verification_pass: new-findings" "$SKILL" \
   && grep -qF "verification_pass: not-run" "$SKILL" \
   && grep -qiE "EVERY run emits exactly ONE.{0,40}verification_pass" "$SKILL"; then
  pass "verification_pass: line is mandatory with clean/new-findings/not-run"
else
  fail "SKILL must require exactly one verification_pass: line per run with the three outcomes"
fi
for r in no-p0-p1-addressed peer-failure; do
  grep -qF "$r" "$SKILL" && pass "not-run reason $r is named" || fail "not-run reason $r must be named"
done
if grep -qF '"verification_pass": {"outcome"' "$SKILL" \
   && sed -n '/## Markdown summary/,/## Reference files/p' "$SKILL" | grep -qF "verification_pass:"; then
  pass "envelope carries the structured object and the summary example shows the line"
else
  fail "the envelope must carry verification_pass and the summary example must show the line"
fi

# --- severity gate, single pass, mutation boundary ---
step=$(sed -n '/^12a\. \*\*Verification pass/,/^13\. /p' "$SKILL")
[ -n "$step" ] && pass "step 12a exists between apply and report" || fail "step 12a must sit between step 12 and step 13"
printf '%s' "$step" | grep -qE "P0 or P1" && pass "the pass is gated on an addressed P0/P1" || fail "step 12a must gate on P0/P1"
printf '%s' "$step" | grep -qiE "one pass, never a loop" && pass "one pass, never a loop" || fail "step 12a must state one pass, never a loop"
printf '%s' "$step" | grep -qiE "never applied in this run" && pass "verification findings are never applied in the same run" || fail "step 12a must forbid applying verification findings in-run"
printf '%s' "$step" | grep -qF -- "--iteration-context-file" && printf '%s' "$step" | grep -qF "peer-brief-lite.md" \
  && pass "the pass uses the lite brief plus the previous-review context" \
  || fail "step 12a must pass --iteration-context-file and use the lite brief"

# --- the builder really emits the previous-review section ---
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf 'diff --git a/x.ts b/x.ts\n+export const one = 1;\n' > "$T/d.diff"
printf -- '- 1-2 (P1) applied — verify the fix landed: Refresh token race; src/auth/refresh.ts:42\n- 1-5 (P2) deferred — do not re-flag: naming\n' > "$T/prev.md"
out=$(cd "$T" && bash "$BUILDER" --brief "$BRIEF" --artifact-file "$T/d.diff" --project-context c --goal g --peer-mode cross-agent --iteration-context-file "$T/prev.md" 2>"$T/err"); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF "## Previous review context" && printf '%s' "$out" | grep -qF "verify the fix landed" && printf '%s' "$out" | grep -qF "lite review"; then
  pass "builder emits the previous-review section with the lite brief"
else
  fail "builder emits the previous-review section with the lite brief" "rc=$rc $(head -c 200 "$T/err")"
fi

# --- en-build calls it before its single suite run ---
if grep -qF -- '/en-review --verify <envelope-path> --mode headless' "$BUILD"; then
  pass "en-build runs the verification pass after applying a P0/P1 batch"
else
  fail "en-build must call /en-review --verify after a batch that addressed a P0/P1"
fi

# --- foundation records it ---
grep -qE '^- \*\*D80\.' "$REPO_ROOT/docs/foundation.md" && pass "D80 recorded" || fail "foundation must add D80"

report
