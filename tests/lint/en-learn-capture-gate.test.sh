#!/usr/bin/env bash
# tests/lint/en-learn-capture-gate.test.sh
#
# The capture gate is the whole point of en-learn's capture mode: coding agents
# reconstruct what and how from the tree, so a wiki restating that makes them
# read more to learn less. The gate's value is entirely in its defaults — write
# nothing unless three conditions hold, each answered by NAMING something — and
# defaults erode quietly under later edits.
#
# What this locks down is the shape that keeps the gate honest, not its wording.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
. "$REPO_ROOT/tests/lib/assert.sh"
TEST_NAME="en-learn capture gate"

SKILL="$REPO_ROOT/skills/en-learn/SKILL.md"
GATE="$REPO_ROOT/skills/en-learn/references/capture-gate.md"
TMPL="$REPO_ROOT/skills/en-learn/references/templates/learning-template.md"

assert_file_exists "$GATE" "the gate reference exists"

# --- the gate is reachable and runs before the work ---
grep -q 'references/capture-gate.md' "$SKILL" \
  && pass "capture reads the gate" || fail "capture reads the gate"
gate_line=$(grep -n 'references/capture-gate.md' "$SKILL" | head -1 | cut -d: -f1)
compose_line=$(grep -n 'Compose entry' "$SKILL" | head -1 | cut -d: -f1)
[ "$gate_line" -lt "$compose_line" ] \
  && pass "the gate is applied before the entry is composed" \
  || fail "the gate is applied before the entry is composed" "gate:$gate_line compose:$compose_line"

# --- the default must be to write nothing ---
# Scoped to the capture FLOW, not the whole file. The description also states
# the default, so a file-wide grep passed even with the step text deleted — the
# assertion has to pin where the instruction lives, or it checks marketing copy.
capture_flow=$(sed -n '/^## Process — Mode A/,/^## Process — Mode B/p' "$SKILL")
echo "$capture_flow" | grep -qi 'default is to write nothing' \
  && pass "the capture flow itself states the write-nothing default" \
  || fail "the capture flow itself states the write-nothing default"
grep -qi 'default is to write nothing' "$GATE" \
  && pass "the gate states the write-nothing default" || fail "the gate states the write-nothing default"

# --- three conditions, all required, each naming something ---
for c in 'Not recoverable from the code' 'Changes a future action' 'Outlives the occasion'; do
  grep -qF "$c" "$GATE" && pass "gate condition present: $c" || fail "gate condition present: $c"
done
grep -qi 'all three must hold' "$GATE" \
  && pass "the conditions are conjunctive, not a menu" || fail "the conditions are conjunctive, not a menu"
grep -qiE 'cannot name|unnamed answer' "$GATE" \
  && pass "an unnamed answer fails the condition" || fail "an unnamed answer fails the condition"

# --- a rejected capture is reported, never silent ---
grep -qiE 'report which condition failed' "$GATE" \
  && pass "the gate requires reporting which condition failed" || fail "the gate requires reporting which condition failed"
grep -qiE 'silent skip is indistinguishable' "$GATE" \
  && pass "the gate says why a silent skip is unacceptable" || fail "the gate says why a silent skip is unacceptable"

# --- bookkeeping is not conditional on filing content ---
# Regression guard: a plan left at in_progress because nothing was captured is
# the exact orphaning bug step 11 was unbundled to prevent.
grep -qiE 'bookkeeping is not conditional|11a.*always runs|always runs.*11a' "$SKILL" \
  && pass "lifecycle bookkeeping still runs when the gate rejects" \
  || fail "lifecycle bookkeeping still runs when the gate rejects"

# --- one learning per run ---
grep -qi 'one learning per run' "$GATE" \
  && pass "one learning per run, so batching cannot carry a weak entry" \
  || fail "one learning per run"

# --- the template must not reimpose mandatory sections ---
assert_file_exists "$TMPL" "the template exists"
grep -qiE 'one paragraph until it earns more' "$TMPL" \
  && pass "the template defaults to a paragraph" || fail "the template defaults to a paragraph"
for dead in '## TL;DR' '## Context' "## What didn't work" '## Prevention' '## Root cause'; do
  # Allowed only as an anti-example; a bare heading at line start is the tell.
  if grep -qE "^${dead}$" "$TMPL"; then
    fail "the template no longer mandates '$dead'"
  else
    pass "the template no longer mandates '$dead'"
  fi
done
grep -qi 'Optional sections' "$TMPL" \
  && pass "extra sections are optional and must earn their place" || fail "extra sections are optional"

# --- the categories the gate exists to admit ---
for q in 'Constraints that live outside the code' 'Paths not taken' 'Deliberate deviations' 'do not announce themselves'; do
  grep -qF "$q" "$GATE" && pass "qualifying category kept: $q" || fail "qualifying category kept: $q"
done
# --- and the ones it exists to reject ---
for n in 'How the code works' 'What a fix changed' 'Point-in-time state'; do
  grep -qF "$n" "$GATE" && pass "rejected category kept: $n" || fail "rejected category kept: $n"
done

# --- bootstrap's exemption must stay explicit and narrow ---
grep -qi 'Exempt from the capture gate' "$SKILL" \
  && pass "bootstrap-patterns declares its gate exemption" || fail "bootstrap-patterns declares its gate exemption"
grep -qi 'Never route ordinary capture through this exemption' "$SKILL" \
  && pass "the exemption is fenced to bootstrap only" || fail "the exemption is fenced to bootstrap only"

report
