#!/usr/bin/env bash
# tests/lint/contract-shape.test.sh
#
# EN12 U10. A skill invoked by another skill owes its callers a stated promise,
# so callers depend on that instead of reading the callee's internals.
#
# A shape lint alone would prove only that six headings exist. Two more checks
# make the promise mean something:
#
#   coverage  — the callee set is DERIVED from actual invocations, not
#               hand-counted, and every derived callee must carry a contract.
#               This is what caught EN12's own plan naming en-cross-review
#               (never invoked programmatically) while omitting en-ship (invoked
#               by en-flow).
#   truth     — enums a contract publishes must match what the skill emits, and
#               the mutation/recursion promises must match documented behavior.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="skill contracts"
cd "$REPO_ROOT"

REQUIRED_SECTIONS="Accepted invocations|Non-interactive guarantee|Return|Authority envelope|Cost bounds|Recursion"

# --- coverage: derive the callee set from real invocation sites ---
# A programmatic invocation carries an invocation verb ("invoke `/en-x`").
# A bare mention is a suggestion to the USER ("tell the user to re-run
# `/en-setup`", "Next: /en-qa -> /en-ship") and owes nobody a contract.
derived=$(grep -rhoiE '(invoke|invoking|dispatch(es|ed)?) (the )?`?/(en-[a-z-]+)' skills/*/SKILL.md \
            | grep -oE 'en-[a-z-]+' | sort -u)
contracts=$(ls -1 skills/*/CONTRACT.md 2>/dev/null | sed -E 's|skills/([^/]+)/CONTRACT.md|\1|' | sort)

assert_eq "$derived" "$contracts" "every derived callee has a contract, and no contract is unused"

for skill in $derived; do
  assert_file_exists "skills/$skill/CONTRACT.md" "$skill is invoked programmatically, so it carries a contract"
done

# A skill only ever suggested to the user owes no contract.
for s in en-setup en-qa en-cross-review; do
  if echo "$derived" | grep -qx "$s"; then
    pass "$s is programmatically invoked (contract required)"
  else
    assert_file_missing "skills/$s/CONTRACT.md" "$s is only suggested to the user, so it carries no contract"
  fi
done

# --- a programmatically invoked skill must be invocable by the model ---
# `disable-model-invocation: true` lets only a person run a skill and keeps its
# description out of context (Claude Code docs, "Control who invokes a skill").
# en-resolve-pr carried it while en-ship's watch loop invoked it unattended, so
# on a Claude Code host the D59 delegate could not be reached at all (D84).
for skill in $derived; do
  if sed -n '1,/^---$/p' "skills/$skill/SKILL.md" | sed '1d' | grep -qE '^disable-model-invocation: *true'; then
    fail "$skill is invoked by another skill, so it must not be disable-model-invocation: true" \
         "the flag makes the skill user-only; the calling skill's invocation would be refused"
  else
    pass "$skill stays model-invocable for its callers"
  fi
done

# --- shape: every contract carries all six sections ---
for f in skills/*/CONTRACT.md; do
  skill=$(basename "$(dirname "$f")")
  missing=""
  echo "$REQUIRED_SECTIONS" | tr '|' '\n' | while IFS= read -r sec; do
    grep -qE "^## $sec" "$f" || echo "$sec"
  done > /tmp/_missing_$$
  missing=$(tr '\n' ' ' < /tmp/_missing_$$; rm -f /tmp/_missing_$$)
  missing=$(echo "$missing" | sed 's/ *$//')
  assert_eq "" "$missing" "[$skill] contract carries all six required sections"
done

# --- truth: published enums must match what the skill emits ---
grep -q 'cross-agent' skills/en-review/CONTRACT.md \
  && grep -q 'cross-agent' skills/en-review/SKILL.md \
  && pass "en-review contract's reviewer enum appears in the skill" \
  || fail "en-review contract's reviewer enum appears in the skill"

for v in completed not_applicable failed missing; do
  grep -qF "$v" skills/en-build/CONTRACT.md && grep -qF "$v" skills/en-build/SKILL.md \
    && pass "en-build gate value '$v' is in both contract and skill" \
    || fail "en-build gate value '$v' is in both contract and skill"
done

for v in captured intentionally_skipped up_to_date ci_environment; do
  grep -qF "$v" skills/en-build/CONTRACT.md && grep -qF "$v" skills/en-build/SKILL.md \
    && pass "en-build learning_checkpoint value '$v' is in both" \
    || fail "en-build learning_checkpoint value '$v' is in both"
done

for v in approve revise reject; do
  grep -qF "$v" skills/en-plan/CONTRACT.md && grep -qF "$v" skills/en-plan/SKILL.md \
    && pass "en-plan verdict value '$v' is in both" \
    || fail "en-plan verdict value '$v' is in both"
done

for v in fixed fixed-differently replied not-addressing declined needs-human; do
  grep -qF "\`$v\`" skills/en-resolve-pr/CONTRACT.md && grep -qF "\`$v\`" skills/en-resolve-pr/SKILL.md \
    && pass "en-resolve-pr verdict '$v' is in both contract and skill" \
    || fail "en-resolve-pr verdict '$v' is in both contract and skill"
done
for fl in --orchestrated --yes --enable-auto-merge; do
  grep -qF -- "$fl" skills/en-resolve-pr/CONTRACT.md && grep -qF -- "$fl" skills/en-resolve-pr/SKILL.md \
    && pass "en-resolve-pr flag '$fl' is in both contract and skill" \
    || fail "en-resolve-pr flag '$fl' is in both contract and skill"
done
grep -qE 'exactly one pass' skills/en-resolve-pr/CONTRACT.md && grep -qiE 'do not cycle at all|exactly one pass' skills/en-resolve-pr/SKILL.md \
  && pass "en-resolve-pr's one-pass promise under --orchestrated matches the skill" \
  || fail "en-resolve-pr's one-pass promise under --orchestrated matches the skill"

# --- truth: behavioral promises must match documented behavior ---
grep -qE 'report-only.*(read-only|none)' skills/en-review/CONTRACT.md \
  && grep -qiE 'report-only.*strictly read-only|Strictly read-only' skills/en-review/SKILL.md \
  && pass "en-review promises report-only mutates nothing, and the skill says so" \
  || fail "en-review promises report-only mutates nothing, and the skill says so"

grep -qi 'never runs a peer' skills/en-review/CONTRACT.md \
  && grep -qi 'never runs a peer' skills/en-review/SKILL.md \
  && pass "en-review's report-only no-peer cost bound matches the skill" \
  || fail "en-review's report-only no-peer cost bound matches the skill"

grep -q 'does not commit' skills/en-simplify/CONTRACT.md \
  && grep -qi 'does not commit' skills/en-build/SKILL.md \
  && pass "en-simplify promises not to commit, and its caller expects that" \
  || fail "en-simplify promises not to commit, and its caller expects that"

grep -q 'ENSEMBLE_PEER_REVIEW' skills/en-build/CONTRACT.md \
  && grep -q 'recursion-guard-active' skills/en-build/SKILL.md \
  && pass "en-build's recursion posture matches its documented trailer value" \
  || fail "en-build's recursion posture matches its documented trailer value"

# --- no contract may point a caller at a path inside the callee ---
for f in skills/*/CONTRACT.md; do
  skill=$(basename "$(dirname "$f")")
  if grep -qE '(references|scripts|agents)/[A-Za-z0-9._-]+' "$f"; then
    fail "[$skill] contract names an internal path; callers must depend on the promise, not the files"
  else
    pass "[$skill] contract exposes no internal paths"
  fi
done

report
